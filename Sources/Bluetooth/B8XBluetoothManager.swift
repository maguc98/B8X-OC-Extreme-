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

    @Published private(set) var stateText = "等待蓝牙初始化"
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var connectedName: String?
    @Published private(set) var detailText = "尚未连接设备"
    @Published private(set) var status: B8XStatus?
    @Published private(set) var isScanning = false
    @Published private(set) var isBusy = false
    @Published private(set) var lastCommandText = "尚未发送控制指令"

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var requestedControl: B8XControl?
    private var awaitingConfirmation: B8XStatusExpectation?
    private var notificationReady = false
    private var operationTimeout: DispatchWorkItem?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else {
            stateText = "请先开启 iPhone 蓝牙"
            return
        }
        devices.removeAll()
        isScanning = true
        stateText = "正在搜索附近蓝牙设备…"
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
        if connectedPeripheral == nil { stateText = "扫描已停止" }
    }

    func connect(_ device: DiscoveredDevice) {
        stopScan()
        stateText = "正在连接 \(device.name)…"
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    func refreshStatus() {
        guard notificationReady else {
            detailText = "请先连接 B8X 并完成通知订阅"
            return
        }
        guard write(Data([0x13])) else { return }
        detailText = "正在请求设备状态…"
    }

    func setLight(_ enabled: Bool) { send(.light(enabled)) }
    func setMode(_ mode: Int) { send(.mode(mode)) }
    func setWind(_ value: Int) { send(.wind(value)) }
    func setCold(_ value: Int) { send(.cold(value)) }

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
    }
}

extension B8XBluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: stateText = "蓝牙已就绪"
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
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        operationTimeout?.cancel()
        operationTimeout = nil
        requestedControl = nil
        awaitingConfirmation = nil
        isBusy = false
        connectedPeripheral = peripheral
        connectedName = peripheral.name ?? "B8X"
        stateText = "已连接 \(connectedName ?? "B8X")"
        detailText = "正在发现 B8X 服务…"
        status = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        notificationReady = false
        peripheral.delegate = self
        peripheral.discoverServices([serviceID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        stateText = "连接失败：\(error?.localizedDescription ?? "未知错误")"
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
    }
}

extension B8XBluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            detailText = "发现服务失败：\(error.localizedDescription)"
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else {
            detailText = "未发现已验证的 B8X 服务 FFE0"
            return
        }
        peripheral.discoverCharacteristics([writeID, notifyID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error {
            detailText = "发现特征值失败：\(error.localizedDescription)"
            return
        }
        let characteristics = service.characteristics ?? []
        guard let write = characteristics.first(where: { $0.uuid == writeID }),
              write.properties.contains(.write),
              let notify = characteristics.first(where: { $0.uuid == notifyID }),
              notify.properties.contains(.notify) || notify.properties.contains(.indicate) else {
            detailText = "缺少可写的 FFE1 或可通知的 FFE4 特征值"
            return
        }
        writeCharacteristic = write
        notifyCharacteristic = notify
        peripheral.setNotifyValue(true, for: notify)
        detailText = "正在订阅设备状态通知…"
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
        guard characteristic.uuid == notifyID else { return }
        if let error {
            detailText = "读取状态失败：\(error.localizedDescription)"
            return
        }
        guard let value = characteristic.value else { return }
        do {
            handleStatus(try B8XStatus.decode(value))
        } catch {
            detailText = "收到非状态数据：\(error.localizedDescription)"
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
