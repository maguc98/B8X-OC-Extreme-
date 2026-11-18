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
    @Published private(set) var stateText = "等待蓝牙初始化"
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var connectedName: String?
    @Published private(set) var detailText = "尚未连接设备"
    @Published private(set) var discoveredCharacteristics: [String] = []
    @Published private(set) var isScanning = false

    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?

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
        let item = DiscoveredDevice(id: peripheral.identifier,
                                    name: name,
                                    rssi: RSSI.intValue,
                                    peripheral: peripheral)
        devices.append(item)
        devices.sort { $0.rssi > $1.rssi }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        connectedName = peripheral.name ?? "B8X"
        detailText = "已连接。正在读取 GATT 服务…"
        discoveredCharacteristics.removeAll()
        peripheral.delegate = self
        peripheral.discoverServices(nil)
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
        detailText = error.map { "连接断开：\($0.localizedDescription)" } ?? "设备已断开"
    }
}

extension B8XBluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            detailText = "读取服务失败：\(error.localizedDescription)"
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            detailText = "设备未公开可读取的 GATT 服务"
            return
        }
        detailText = "发现 \(services.count) 个服务，正在枚举特征值…"
        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error {
            detailText = "读取特征值失败：\(error.localizedDescription)"
            return
        }
        let rows = (service.characteristics ?? []).map {
            "\(service.uuid.uuidString) / \($0.uuid.uuidString) [\($0.properties.description)]"
        }
        discoveredCharacteristics.append(contentsOf: rows)
        detailText = "GATT 枚举完成。当前仅执行发现，不发送控制指令。"
    }
}

private extension CBCharacteristicProperties {
    var description: String {
        var values: [String] = []
        if contains(.read) { values.append("read") }
        if contains(.write) { values.append("write") }
        if contains(.writeWithoutResponse) { values.append("writeNR") }
        if contains(.notify) { values.append("notify") }
        if contains(.indicate) { values.append("indicate") }
        return values.isEmpty ? "无已知属性" : values.joined(separator: ",")
    }
}
