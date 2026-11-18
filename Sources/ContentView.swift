import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = B8XBluetoothManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    connectionCard
                    deviceList
                    gattCard
                    safetyNote
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("B8X OC")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("EXTREME · iOS BLE CONTROLLER")
                .font(.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(.cyan)
        }
        .padding(.top, 12)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("设备连接", systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)
            Text(bluetooth.stateText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button(bluetooth.isScanning ? "停止搜索" : "搜索 B8X") {
                    bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.startScan()
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                if bluetooth.connectedName != nil {
                    Button("断开连接", role: .destructive) { bluetooth.disconnect() }
                        .buttonStyle(.bordered)
                }
            }
            if let name = bluetooth.connectedName {
                Text("已连接：\(name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("附近设备")
                .font(.headline)
            if bluetooth.devices.isEmpty {
                Text("点击“搜索 B8X”发现附近的 BLE 设备。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(bluetooth.devices) { device in
                Button {
                    bluetooth.connect(device)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.name).foregroundStyle(.primary)
                            Text(device.id.uuidString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(device.rssi) dBm")
                            .font(.caption.monospacedDigit())
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var gattCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("协议诊断")
                .font(.headline)
            Text(bluetooth.detailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(Array(bluetooth.discoveredCharacteristics.enumerated()), id: \.offset) { _, row in
                Text(row)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var safetyNote: some View {
        Label("首版仅扫描、连接和枚举协议，不写入未知控制值，也不修改固件或温度保护。", systemImage: "shield.lefthalf.filled")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }
}
