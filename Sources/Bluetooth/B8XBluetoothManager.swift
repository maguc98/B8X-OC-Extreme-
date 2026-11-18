import Foundation
import Combine
import CoreBluetooth

struct DiscoveredDevice: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let peripheral: CBPeripheral
}

final class B8XBluetoothManager: NSObject, ObservableObject {
    private enum BLEWritePurpose { case statusRequest, controlCommand, confirmationReadback, lightingCaptureReadback, lightingProtocolProbe }
    private let serviceID = CBUUID(string: "FFE0")
    private let writeID = CBUUID(string: "FFE1")
    private let notifyID = CBUUID(string: "FFE4")
    private let deviceInformationServiceID = CBUUID(string: "180A")
    private let firmwareRevisionID = CBUUID(string: "2A26")
    private let modelNumberID = CBUUID(string: "2A24")
    private let manufacturerNameID = CBUUID(string: "2A29")

    @Published private(set) var stateText = "等待蓝牙初始化"
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var connectedName: String?
    @Published private(set) var detailText = "尚未连接设备"
    @Published private(set) var status: B8XStatus?
    @Published private(set) var isScanning = false
    @Published private(set) var isBusy = false
    @Published private(set) var lastCommandText = "尚未发送控制指令"
    @Published private(set) var thermalProtectionText = "温度保护待机"
    @Published private(set) var rawFrameHistory: [String] = []
    @Published private(set) var gattInventory = "尚未枚举 GATT 服务"
    @Published private(set) var firmwareRevision: String?
    @Published private(set) var modelNumber: String?
    @Published private(set) var manufacturerName: String?
    @Published private(set) var statusFrameDeltaSummary = "等待第二条状态帧进行对比"
    @Published private(set) var physicalActionMarkers: [String] = []
    @Published private(set) var isCapturingLightingAction = false
    @Published private(set) var lightingCaptureText = "等待实体按键双击抓包"
    @Published private(set) var lightingProtocolProbeText = "尚未执行灯效协议只读探测"
    @Published private(set) var lightingProtocolProbeRawFrame: String?

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var requestedControl: B8XControl?
    private var awaitingConfirmation: B8XStatusExpectation?
    private var notificationReady = false
    private var operationTimeout: DispatchWorkItem?
    private var confirmationReadbackWorkItem: DispatchWorkItem?
    private var confirmationReadbackAttempt = 0
    private var pendingWritePurposes: [BLEWritePurpose] = []
    private var reconnectWorkItem: DispatchWorkItem?
    private var userRequestedDisconnect = false
    private let rememberedPeripheralKey = "B8X.rememberedPeripheralUUID"
    private var lowTemperatureProtectionEnabled = true
    private var highTemperatureProtectionEnabled = true
    private var lowProtectionLatched = false
    private var highProtectionLatched = false
    private var lastCapturedRawFrame: [UInt8]?
    private var lightingCaptureID: UUID?
    private var lightingCaptureWorkItems: [DispatchWorkItem] = []
    private var lightingCaptureFrameCount = 0
    private var awaitingLightingProtocolProbeResponse = false
    private var lightingProtocolProbeEffectID: UInt8?
    private var lightingProtocolProbeResponseCount = 0
    private var lightingProtocolProbeTimeout: DispatchWorkItem?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        userRequestedDisconnect = false
        guard central.state == .poweredOn else {
            stateText = "请先开启 iPhone 蓝牙"
            return
        }
        devices.removeAll()
        isScanning = true
        stateText = "正在自动寻找 B8X…"
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
        if connectedPeripheral == nil { stateText = "扫描已停止" }
    }

    func connect(_ device: DiscoveredDevice) {
        userRequestedDisconnect = false
        reconnectWorkItem?.cancel()
        stopScan()
        stateText = "正在连接 \\(device.name)…"
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        userRequestedDisconnect = true
        reconnectWorkItem?.cancel()
        guard let peripheral = connectedPeripheral else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    private func isB8X(_ name: String) -> Bool {
        name.uppercased().replacingOccurrences(of: " ", with: "").contains("B8X")
    }

    private func resumeAutomaticConnection() {
        guard !userRequestedDisconnect, connectedPeripheral == nil, central.state == .poweredOn else { return }
        if let remembered = UserDefaults.standard.string(forKey: rememberedPeripheralKey),
           let uuid = UUID(uuidString: remembered),
           let peripheral = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            stateText = "正在重新连接已记住的 B8X…"
            central.connect(peripheral, options: nil)
        } else {
            startScan()
        }
    }
    func refreshStatus() {
        guard notificationReady else {
            detailText = "请先连接 B8X 并完成通知订阅"
            return
        }
        guard write(Data([0x13]), purpose: .statusRequest) else { return }
        detailText = "正在请求设备状态…"
    }

    private func cancelLightingActionCapture(statusText: String) {
        lightingCaptureWorkItems.forEach { $0.cancel() }
        lightingCaptureWorkItems.removeAll()
        lightingCaptureID = nil
        isCapturingLightingAction = false
        lightingCaptureText = statusText
    }

    func clearRawFrameHistory() {
        cancelLightingActionCapture(statusText: "样本已清空，等待新的状态帧")
        rawFrameHistory.removeAll()
        physicalActionMarkers.removeAll()
        lastCapturedRawFrame = nil
        statusFrameDeltaSummary = "样本已清空，等待新的状态帧"
    }

    /// Mark the user's physical double-press and collect read-only status frames
    /// for five seconds. The only BLE payload sent by this capture is the
    /// documented status query (0x13); no unknown lighting command is written.
    func markPhysicalDoublePress() {
        guard notificationReady else {
            lightingCaptureText = "请先连接 B8X 并完成状态通知订阅"
            return
        }

        cancelLightingActionCapture(statusText: "准备新的实体按键抓包")
        let captureID = UUID()
        lightingCaptureID = captureID
        lightingCaptureFrameCount = 0
        isCapturingLightingAction = true

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let latestFrame = rawFrameHistory.first ?? "尚无状态帧"
        let marker = "DOUBLE_PRESS \(timestamp) | baselineFrames=\(rawFrameHistory.count) | latest=\(latestFrame)"
        physicalActionMarkers.insert(marker, at: 0)
        if physicalActionMarkers.count > 20 { physicalActionMarkers.removeLast() }

        lightingCaptureText = "抓包中：现在请立即双击 B8X 实体按键；5 秒内自动读取 6 次状态。"

        let readbackDelays: [TimeInterval] = [0.0, 0.65, 1.4, 2.3, 3.5, 5.0]
        for (index, delay) in readbackDelays.enumerated() {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.lightingCaptureID == captureID else { return }
                guard self.notificationReady else {
                    self.cancelLightingActionCapture(statusText: "抓包中断：设备状态通知已断开")
                    return
                }
                guard self.write(Data([0x13]), purpose: .lightingCaptureReadback) else {
                    self.lightingCaptureText = "第 \(index + 1) 次状态读取未能写入，请检查连接。"
                    return
                }
                self.lightingCaptureText = "抓包中：已发出第 \(index + 1)/6 次状态读取请求…"
            }
            lightingCaptureWorkItems.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        let finish = DispatchWorkItem { [weak self] in
            guard let self, self.lightingCaptureID == captureID else { return }
            let frames = self.lightingCaptureFrameCount
            self.lightingCaptureWorkItems.removeAll()
            self.lightingCaptureID = nil
            self.isCapturingLightingAction = false
            self.lightingCaptureText = "抓包完成：收到 \(frames) 条状态帧。请导出抓包并重复 3 次进行对比。"
        }
        lightingCaptureWorkItems.append(finish)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.8, execute: finish)
    }

    var captureExportText: String {
        let markers = physicalActionMarkers.isEmpty ? "无动作标记" : physicalActionMarkers.reversed().joined(separator: "\n")
        let frames = rawFrameHistory.reversed().joined(separator: "\n")
        let probeFrame = lightingProtocolProbeRawFrame ?? "尚未收到 0x51 回包"
        return "【灯效协议只读探测】\n\(lightingProtocolProbeText)\n\(probeFrame)\n\n【实体按键动作标记】\n\(markers)\n\n【状态帧（新→旧）】\n\(frames)"
    }

    /// Sends only the candidate read-only 0x51 0x00 configuration query.
    /// This is manual (never automatic) because its B8X support is unverified.
    /// No 0x50 LED write is sent by this diagnostic.
    func probeLightingProtocol() {
        guard notificationReady else {
            lightingProtocolProbeText = "请先连接 B8X 并完成通知订阅"
            return
        }
        guard !isBusy, !awaitingLightingProtocolProbeResponse else {
            lightingProtocolProbeText = "当前有其他蓝牙操作，请稍后再试"
            return
        }
        guard let current = status else {
            lightingProtocolProbeText = "请先读取设备状态，再查询当前灯效配置"
            refreshStatus()
            return
        }

        let effectID = current.raw[15]
        guard let request = B8XLightingProtocolProbe.readConfiguration(forEffect: effectID) else {
            lightingProtocolProbeText = String(
                format: "当前 byte[15]=0x%02X 不在候选灯效编号中；未发送任何探测命令。",
                effectID
            )
            return
        }

        lightingProtocolProbeTimeout?.cancel()
        lightingProtocolProbeTimeout = nil
        awaitingLightingProtocolProbeResponse = true
        lightingProtocolProbeEffectID = effectID
        lightingProtocolProbeResponseCount = 0
        lightingProtocolProbeRawFrame = nil
        lightingProtocolProbeText = String(
            format: "正在查询当前候选灯效 0x%02X（命令 51 %02X），等待回包…",
            effectID, effectID
        )
        guard write(request, purpose: .lightingProtocolProbe) else {
            awaitingLightingProtocolProbeResponse = false
            lightingProtocolProbeEffectID = nil
            lightingProtocolProbeText = "查询未能写入，请检查连接"
            return
        }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.awaitingLightingProtocolProbeResponse else { return }
            self.awaitingLightingProtocolProbeResponse = false
            self.lightingProtocolProbeTimeout = nil
            self.lightingProtocolProbeEffectID = nil
            if self.lightingProtocolProbeResponseCount > 0 {
                self.lightingProtocolProbeText = "收到 \(self.lightingProtocolProbeResponseCount) 条 0x51 候选回包。请导出原始数据；这仍不能证明 B8X 的 0x50 写入格式。"
            } else {
                self.lightingProtocolProbeText = "3 秒内未收到匹配的 0x51 回包；固件可能不支持此查询，或回包格式不同。未发送任何灯效写入。"
            }
        }
        lightingProtocolProbeTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
    }

    private func receiveLightingProtocolProbeResponse(_ data: Data) {
        guard awaitingLightingProtocolProbeResponse,
              data.first == B8XLightingProtocolProbe.responseCommand,
              data.count >= 2,
              data[1] == lightingProtocolProbeEffectID else { return }

        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        if lightingProtocolProbeRawFrame == nil {
            lightingProtocolProbeRawFrame = hex
        } else {
            lightingProtocolProbeRawFrame! += "\n" + hex
        }
        lightingProtocolProbeResponseCount += 1
        lightingProtocolProbeText = "已收到第 \(lightingProtocolProbeResponseCount) 条匹配的 0x51 候选回包，继续收集可能的分包…"
    }

    private func resetLightingProtocolProbe(_ message: String) {
        lightingProtocolProbeTimeout?.cancel()
        lightingProtocolProbeTimeout = nil
        awaitingLightingProtocolProbeResponse = false
        lightingProtocolProbeEffectID = nil
        lightingProtocolProbeResponseCount = 0
        lightingProtocolProbeText = message
        lightingProtocolProbeRawFrame = nil
    }

    func setLight(_ enabled: Bool) { send(.light(enabled)) }
    func setMode(_ mode: Int) { send(.mode(mode)) }
    func setWind(_ value: Int) { send(.wind(value)) }
    func setCold(_ value: Int) { send(.cold(value)) }
    func applySettings(wind: Int, cold: Int) { send(.settings(wind: wind, cold: cold)) }

    func configureThermalProtection(lowEnabled: Bool, highEnabled: Bool) {
        lowTemperatureProtectionEnabled = lowEnabled
        highTemperatureProtectionEnabled = highEnabled
        if !lowEnabled { lowProtectionLatched = false }
        if !highEnabled { highProtectionLatched = false }
        evaluateThermalProtection(using: status)
    }

    private func evaluateThermalProtection(using current: B8XStatus?) {
        guard let current, notificationReady, !isBusy, requestedControl == nil, awaitingConfirmation == nil else { return }
        if lowTemperatureProtectionEnabled {
            if current.coldTemperature > 7 { lowProtectionLatched = false }
            // Never overwrite a user's manually selected cooling level.
            // Low-temperature cooling reduction is automatic-mode behavior only.
            if current.isAutomaticMode, current.coldTemperature <= 5, !lowProtectionLatched {
                lowProtectionLatched = true
                thermalProtectionText = "低温保护触发（自动模式）：制冷已请求降至最低档 1"
                send(.cold(1))
                return
            }
        }
        if highTemperatureProtectionEnabled {
            if current.hotTemperature < 42 { highProtectionLatched = false }
            if current.hotTemperature >= 45, !highProtectionLatched {
                highProtectionLatched = true
                thermalProtectionText = "高温保护触发：风扇已请求升至 6000 RPM"
                send(.wind(6000))
                return
            }
        }
        if !lowProtectionLatched && !highProtectionLatched { thermalProtectionText = "温度正常，保护监测中" }
    }

    private func send(_ control: B8XControl) {
        guard notificationReady, !isBusy else { return }
        guard !awaitingLightingProtocolProbeResponse else {
            lastCommandText = "正在读取灯效配置，请稍后再调整设备参数。"
            return
        }
        guard let current = status else {
            lastCommandText = "请先读取设备状态"
            refreshStatus()
            return
        }
        operationTimeout?.cancel()
        operationTimeout = nil
        confirmationReadbackWorkItem?.cancel()
        confirmationReadbackWorkItem = nil
        confirmationReadbackAttempt = 0
        do {
            _ = try control.expectedStatus(from: current)
            requestedControl = control
            awaitingConfirmation = nil
            isBusy = true
            lastCommandText = "正在读取最新状态，准备发送控制指令…"
            guard write(Data([0x13]), purpose: .statusRequest) else {
                requestedControl = nil
                isBusy = false
                lastCommandText = "状态请求未能写入，请检查连接后重试"
                return
            }
            scheduleFreshStatusTimeout()
        } catch {
            lastCommandText = error.localizedDescription
        }
    }

    @discardableResult
    private func write(_ data: Data, purpose: BLEWritePurpose = .statusRequest) -> Bool {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            detailText = "写入通道尚未就绪"
            return false
        }
        pendingWritePurposes.append(purpose)
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        return true
    }

    private func scheduleFreshStatusTimeout() {
        operationTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.requestedControl != nil else { return }
            self.requestedControl = nil
            self.isBusy = false
            self.operationTimeout = nil
            self.lastCommandText = "读取最新设备状态超时，控制指令未发送。请检查连接后刷新状态。"
        }
        operationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
    }

    private func scheduleConfirmationTimeout() {
        operationTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.awaitingConfirmation != nil else { return }
            self.awaitingConfirmation = nil
            self.isBusy = false
            self.operationTimeout = nil
            self.confirmationReadbackWorkItem?.cancel()
            self.confirmationReadbackWorkItem = nil
            self.lastCommandText = "设备确认超时。请刷新状态核对实际值，不要连续重复发送。"
            self.refreshStatus()
        }
        operationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
    }

    /// Actively request fresh telemetry after a successful control write.
    /// Some firmware revisions do not emit an immediate unsolicited update.
    private func scheduleConfirmationReadback(after delay: TimeInterval = 0.4) {
        guard awaitingConfirmation != nil, confirmationReadbackAttempt < 3 else { return }
        confirmationReadbackWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.awaitingConfirmation != nil, self.notificationReady else { return }
            self.confirmationReadbackAttempt += 1
            let attempt = self.confirmationReadbackAttempt
            guard self.write(Data([0x13]), purpose: .confirmationReadback) else {
                self.lastCommandText = "指令已发送，但主动读取设备状态失败。请检查连接。"
                return
            }
            self.lastCommandText = "指令已发送，正在读取设备状态（\(attempt)/3）…"
        }
        confirmationReadbackWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func handleStatus(_ newStatus: B8XStatus) {
        status = newStatus
        let hex = newStatus.raw.map { String(format: "%02X", $0) }.joined(separator: " ")
        if let previous = lastCapturedRawFrame, previous.count == newStatus.raw.count {
            let changes = zip(previous, newStatus.raw).enumerated().compactMap { index, pair -> String? in
                guard pair.0 != pair.1 else { return nil }
                return String(format: "byte[%02d] %02X→%02X", index, pair.0, pair.1)
            }
            statusFrameDeltaSummary = changes.isEmpty ? "与上一帧完全相同" : changes.joined(separator: " · ")
        } else {
            statusFrameDeltaSummary = "等待第二条状态帧进行对比"
        }
        lastCapturedRawFrame = newStatus.raw
        let frameFormatter = ISO8601DateFormatter()
        frameFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        rawFrameHistory.insert("\(frameFormatter.string(from: Date()))  \(hex)", at: 0)
        if lightingCaptureID != nil { lightingCaptureFrameCount += 1 }
        if rawFrameHistory.count > 64 {
            rawFrameHistory.removeLast(rawFrameHistory.count - 64)
        }
        if let control = requestedControl {
            operationTimeout?.cancel()
            operationTimeout = nil
            do {
                let packet = try control.packet(using: newStatus)
                awaitingConfirmation = try control.expectedStatus(from: newStatus)
                requestedControl = nil
                guard write(packet, purpose: .controlCommand) else {
                    awaitingConfirmation = nil
                    isBusy = false
                    lastCommandText = "控制指令未能写入，请检查蓝牙连接"
                    return
                }
                lastCommandText = "指令已发送，等待设备状态确认…"
                scheduleConfirmationTimeout()
                return
            } catch {
                requestedControl = nil
                isBusy = false
                lastCommandText = "控制指令未发送：\(error.localizedDescription)"
                return
            }
        }
        if let expected = awaitingConfirmation, expected.matches(newStatus) {
            awaitingConfirmation = nil
            confirmationReadbackWorkItem?.cancel()
            confirmationReadbackWorkItem = nil
            confirmationReadbackAttempt = 0
            operationTimeout?.cancel()
            operationTimeout = nil
            isBusy = false
            lastCommandText = "设备已回报确认，控制成功"
        }
        detailText = "已接收并解析 B8X 状态帧"
        evaluateThermalProtection(using: newStatus)
    }
}

extension B8XBluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            isScanning = false
            requestedControl = nil
            awaitingConfirmation = nil
            operationTimeout?.cancel()
            operationTimeout = nil
            confirmationReadbackWorkItem?.cancel()
            confirmationReadbackWorkItem = nil
            pendingWritePurposes.removeAll()
            cancelLightingActionCapture(statusText: "抓包已中断：蓝牙不可用")
            resetLightingProtocolProbe("蓝牙不可用，灯效协议探测已重置")
            isBusy = false
        }
        switch central.state {
        case .poweredOn:
            stateText = "蓝牙已就绪，正在自动寻找 B8X…"
            resumeAutomaticConnection()
        case .poweredOff: stateText = "蓝牙已关闭"
        case .unauthorized: stateText = "蓝牙权限未授权"
        case .unsupported: stateText = "此设备不支持蓝牙 LE"
        case .resetting: stateText = "蓝牙正在重置"
        case .unknown: stateText = "蓝牙状态未知"
        @unknown default: stateText = "未知蓝牙状态"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "未命名设备"
        guard !devices.contains(where: { $0.id == peripheral.identifier }) else { return }
        devices.append(DiscoveredDevice(id: peripheral.identifier, name: name,
                                        rssi: RSSI.intValue, peripheral: peripheral))
        devices.sort { $0.rssi > $1.rssi }
        if isB8X(name), connectedPeripheral == nil, !userRequestedDisconnect {
            stateText = "已识别 \\(name)，正在自动连接…"
            stopScan()
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        operationTimeout?.cancel()
        operationTimeout = nil
        requestedControl = nil
        awaitingConfirmation = nil
        isBusy = false
        connectedPeripheral = peripheral
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: rememberedPeripheralKey)
        connectedName = peripheral.name ?? "B8X"
        stateText = "已连接 \(connectedName ?? "B8X")"
        detailText = "正在发现 B8X 服务…"
        status = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        notificationReady = false
        firmwareRevision = nil
        modelNumber = nil
        manufacturerName = nil
        gattInventory = "正在枚举设备公开的 GATT 服务…"
        clearRawFrameHistory()
        resetLightingProtocolProbe("设备已连接；可手动执行候选只读查询")
        peripheral.delegate = self
        // Read-only discovery: enumerate services to identify standard
        // Device Information metadata and any advertised update service.
        // No unknown characteristic is written or activated.
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        requestedControl = nil
        awaitingConfirmation = nil
        operationTimeout?.cancel()
        operationTimeout = nil
        confirmationReadbackWorkItem?.cancel()
        confirmationReadbackWorkItem = nil
        pendingWritePurposes.removeAll()
        isBusy = false
        connectedPeripheral = nil
        connectedName = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        notificationReady = false
        resetLightingProtocolProbe("连接失败，灯效协议探测已重置")
        cancelLightingActionCapture(statusText: "抓包已中断：连接失败")
        stateText = "连接失败：\(error?.localizedDescription ?? "未知错误")"
        detailText = "连接失败，将自动重新搜索 B8X"
        scheduleAutomaticReconnect()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        connectedPeripheral = nil
        connectedName = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        notificationReady = false
        resetLightingProtocolProbe("设备已断开，灯效协议探测已重置")
        requestedControl = nil
        awaitingConfirmation = nil
        operationTimeout?.cancel()
        operationTimeout = nil
        confirmationReadbackWorkItem?.cancel()
        confirmationReadbackWorkItem = nil
        pendingWritePurposes.removeAll()
        cancelLightingActionCapture(statusText: "抓包已中断：设备已断开")
        isBusy = false
        status = nil
        detailText = error.map { "连接断开：\($0.localizedDescription)" } ?? "设备已断开"
        stateText = "设备已断开"
        if !userRequestedDisconnect { scheduleAutomaticReconnect() }
    }

    private func scheduleAutomaticReconnect() {
        guard !userRequestedDisconnect else { return }
        reconnectWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.resumeAutomaticConnection() }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}

extension B8XBluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            detailText = "发现服务失败：\(error.localizedDescription)"
            gattInventory = "服务枚举失败：\(error.localizedDescription)"
            return
        }
        let services = peripheral.services ?? []
        guard !services.isEmpty else {
            gattInventory = "设备未公开 GATT 服务"
            detailText = "未发现设备服务"
            return
        }
        gattInventory = services.map { "Service \($0.uuid.uuidString)" }.joined(separator: "\n")
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error {
            detailText = "发现特征值失败：\(error.localizedDescription)"
            return
        }

        let characteristics = service.characteristics ?? []
        let rows = characteristics.map { characteristic in
            let properties = characteristic.properties
            var flags: [String] = []
            if properties.contains(.read) { flags.append("R") }
            if properties.contains(.write) { flags.append("W") }
            if properties.contains(.writeWithoutResponse) { flags.append("WNR") }
            if properties.contains(.notify) { flags.append("N") }
            if properties.contains(.indicate) { flags.append("I") }
            return "  \(characteristic.uuid.uuidString) [\(flags.joined(separator: ","))]"
        }
        let section = (["Service \(service.uuid.uuidString)"] + rows).joined(separator: "\n")
        if gattInventory.isEmpty {
            gattInventory = section
        } else {
            gattInventory += "\n" + rows.joined(separator: "\n")
        }

        if service.uuid == serviceID {
            writeCharacteristic = characteristics.first(where: {
                $0.uuid == writeID && $0.properties.contains(.write)
            })
            notifyCharacteristic = characteristics.first(where: {
                $0.uuid == notifyID &&
                ($0.properties.contains(.notify) || $0.properties.contains(.indicate))
            })
            if let writeCharacteristic, let notifyCharacteristic {
                peripheral.setNotifyValue(true, for: notifyCharacteristic)
                detailText = "正在订阅设备状态通知…"
            } else {
                detailText = "缺少可写的 FFE1 或可通知的 FFE4 特征值"
            }
        }

        // Only read the standard Bluetooth Device Information characteristics.
        // Never probe undocumented vendor characteristics with arbitrary reads.
        if service.uuid == deviceInformationServiceID {
            for characteristic in characteristics where characteristic.properties.contains(.read) {
                if [firmwareRevisionID, modelNumberID, manufacturerNameID].contains(characteristic.uuid) {
                    peripheral.readValue(for: characteristic)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == notifyID else { return }
        if let error {
            detailText = "订阅状态通知失败：\(error.localizedDescription)"
            return
        }
        notificationReady = characteristic.isNotifying
        detailText = notificationReady ? "通知已订阅，正在读取设备状态…" : "设备状态通知未开启"
        if notificationReady { refreshStatus() }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            if characteristic.uuid == notifyID {
                detailText = "读取状态失败：\(error.localizedDescription)"
            }
            return
        }
        guard let value = characteristic.value else { return }

        if characteristic.uuid == firmwareRevisionID {
            firmwareRevision = String(data: value, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if characteristic.uuid == modelNumberID {
            modelNumber = String(data: value, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if characteristic.uuid == manufacturerNameID {
            manufacturerName = String(data: value, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if characteristic.uuid == notifyID {
            if value.first == B8XLightingProtocolProbe.responseCommand {
                receiveLightingProtocolProbeResponse(value)
                return
            }
            do {
                handleStatus(try B8XStatus.decode(value))
            } catch {
                detailText = "收到非状态数据：\(error.localizedDescription)"
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == writeID else { return }
        let purpose = pendingWritePurposes.isEmpty ? BLEWritePurpose.statusRequest : pendingWritePurposes.removeFirst()
        if let error {
            switch purpose {
            case .controlCommand:
                isBusy = false
                requestedControl = nil
                awaitingConfirmation = nil
                operationTimeout?.cancel()
                operationTimeout = nil
                confirmationReadbackWorkItem?.cancel()
                confirmationReadbackWorkItem = nil
                lastCommandText = "写入失败：\(error.localizedDescription)"
            case .confirmationReadback:
                detailText = "主动状态回读失败：\(error.localizedDescription)"
                if awaitingConfirmation != nil { scheduleConfirmationReadback(after: 0.8) }
            case .statusRequest:
                detailText = "状态请求写入失败：\(error.localizedDescription)"
            case .lightingCaptureReadback:
                lightingCaptureText = "自动状态读取写入失败：\(error.localizedDescription)"
            case .lightingProtocolProbe:
                awaitingLightingProtocolProbeResponse = false
                lightingProtocolProbeEffectID = nil
                lightingProtocolProbeTimeout?.cancel()
                lightingProtocolProbeTimeout = nil
                lightingProtocolProbeText = "只读探测写入失败：\(error.localizedDescription)"
            }
            return
        }

        switch purpose {
        case .controlCommand:
            if awaitingConfirmation != nil {
                lastCommandText = "蓝牙已接受写入，正在主动核对设备状态…"
                scheduleConfirmationReadback()
            }
        case .confirmationReadback:
            if awaitingConfirmation != nil, confirmationReadbackAttempt < 3 {
                scheduleConfirmationReadback(after: 0.9)
            }
        case .statusRequest, .lightingCaptureReadback:
            break
        case .lightingProtocolProbe:
            if lightingProtocolProbeResponseCount == 0 {
                lightingProtocolProbeText = "候选只读查询已写入，等待设备回包…"
            }
        }
    }
}
