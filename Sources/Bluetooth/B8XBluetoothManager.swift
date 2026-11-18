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

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var requestedControl: B8XControl?
    private var awaitingConfirmation: B8XStatusExpectation?
    private var notificationReady = false
    private var operationTimeout: DispatchWorkItem?
    private var reconnectWorkItem: DispatchWorkItem?
    private var userRequestedDisconnect = false
    private let rememberedPeripheralKey = "B8X.rememberedPeripheralUUID"
    private var lowTemperatureProtectionEnabled = true
    private var highTemperatureProtectionEnabled = true
    private var lowProtectionLatched = false
    private var highProtectionLatched = false
    private var lastCapturedRawFrame: [UInt8]?

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
        guard write(Data([0x13])) else { return }
        detailText = "正在请求设备状态…"
    }

    func clearRawFrameHistory() {
        rawFrameHistory.removeAll()
        physicalActionMarkers.removeAll()
        lastCapturedRawFrame = nil
        statusFrameDeltaSummary = "样本已清空，等待新的状态帧"
    }

    func markPhysicalDoublePress() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let latestFrame = rawFrameHistory.first ?? "尚无状态帧"
        let marker = "DOUBLE_PRESS \(timestamp) | frameCount=\(rawFrameHistory.count) | latest=\(latestFrame)"
        physicalActionMarkers.insert(marker, at: 0)
        if physicalActionMarkers.count > 20 { physicalActionMarkers.removeLast() }
    }

    var captureExportText: String {
        let markers = physicalActionMarkers.isEmpty ? "无动作标记" : physicalActionMarkers.reversed().joined(separator: "\n")
        let frames = rawFrameHistory.reversed().joined(separator: "\n")
        return "【实体按键动作标记】\n\(markers)\n\n【状态帧（新→旧）】\n\(frames)"
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
            if current.coldTemperature <= 5, !lowProtectionLatched {
                lowProtectionLatched = true
                thermalProtectionText = "低温保护触发：制冷已请求降至最低档 92"
                send(.cold(92))
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
        guard let current = status else {
            lastCommandText = "请先读取设备状态"
            refreshStatus()
            return
        }
        operationTimeout?.cancel()
        operationTimeout = nil
        do {
            _ = try control.expectedStatus(from: current)
            requestedControl = control
            awaitingConfirmation = nil
            isBusy = true
            lastCommandText = "正在读取最新状态，准备发送控制指令…"
            guard write(Data([0x13])) else {
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
    private func write(_ data: Data) -> Bool {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            detailText = "写入通道尚未就绪"
            return false
        }
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
            self.lastCommandText = "设备确认超时。请刷新状态核对实际值，不要连续重复发送。"
            self.refreshStatus()
        }
        operationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
    }

    private func handleStatus(_ newStatus: B8XStatus) {
        status = newStatus
        let hex = newStatus.raw.map { String(format: "%02X", $0) }.joined(separator: " ")
        let stamp = Date().formatted(date: .omitted, time: .standard)
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
        rawFrameHistory.insert("\(stamp)  \(hex)", at: 0)
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
                guard write(packet) else {
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
        isBusy = false
        connectedPeripheral = nil
        connectedName = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        notificationReady = false
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
        requestedControl = nil
        awaitingConfirmation = nil
        operationTimeout?.cancel()
        operationTimeout = nil
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
        if let error {
            isBusy = false
            requestedControl = nil
            awaitingConfirmation = nil
            operationTimeout?.cancel()
            operationTimeout = nil
            lastCommandText = "写入失败：\(error.localizedDescription)"
        }
    }
}
