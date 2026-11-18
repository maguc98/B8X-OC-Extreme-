import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = B8XBluetoothManager()
    @State private var windSelection = 4000.0
    @State private var coldSelection = 92.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    connectionCard
                    if let status = bluetooth.status {
                        telemetryCard(status)
                        controlsCard(status)
                    } else {
                        emptyStatusCard
                    }
                    deviceList
                    protocolCard
                    safetyNote
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
        .onChange(of: bluetooth.status) { status in
            guard let status else { return }
            windSelection = Double(status.windLevel)
            coldSelection = Double(status.coldLevel)
        }
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
                    Button("刷新状态") { bluetooth.refreshStatus() }
                        .buttonStyle(.bordered)
                    Button("断开", role: .destructive) { bluetooth.disconnect() }
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

    private func telemetryCard(_ status: B8XStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("实时遥测", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                Text("已解析")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            HStack(spacing: 10) {
                metric("冷面温度", value: String(format: "%.1f°", status.coldTemperature), icon: "snowflake")
                metric("热面温度", value: "\(status.hotTemperature)°", icon: "thermometer.high")
                metric("实际转速", value: "\(status.fanRPM)", icon: "fan")
            }
            HStack {
                Label(status.lightEnabled ? "灯光开启" : "灯光关闭", systemImage: "lightbulb")
                Spacer()
                Text("模式：\(status.modeRaw == 0 ? "自动调节" : status.modeRaw == 1 ? "手动固定" : "未知 \(status.modeRaw)")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                Text("原始状态帧 · 20 bytes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(status.raw.map { String(format: "%02X", $0) }.joined(separator: " "))
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.cyan)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.cyan)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
    }

    private func controlsCard(_ status: B8XStatus) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("设备控制", systemImage: "slider.horizontal.3")
                .font(.headline)

            HStack {
                Text("运行模式")
                Spacer()
                Button(status.modeRaw == 0 ? "切换到手动" : "切换到自动") {
                    bluetooth.setMode(status.modeRaw == 0 ? 1 : 0)
                }
                .buttonStyle(.bordered)
                .disabled(bluetooth.isBusy || !(status.modeRaw == 0 || status.modeRaw == 1))
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("风扇设定")
                    Spacer()
                    Text("\(Int(windSelection)) RPM")
                        .monospacedDigit()
                        .foregroundStyle(.cyan)
                }
                Slider(value: $windSelection, in: 4000...4500, step: 100)
                    .tint(.cyan)
                Button("应用风扇设定") { bluetooth.setWind(Int(windSelection)) }
                    .buttonStyle(.bordered)
                    .disabled(bluetooth.isBusy || Int(windSelection) == status.windLevel)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("制冷设定（协议原始档位）")
                    Spacer()
                    Text("\(Int(coldSelection))")
                        .monospacedDigit()
                        .foregroundStyle(.cyan)
                }
                Slider(value: $coldSelection, in: 92...175, step: 1)
                    .tint(.cyan)
                Button("应用制冷设定") { bluetooth.setCold(Int(coldSelection)) }
                    .buttonStyle(.bordered)
                    .disabled(bluetooth.isBusy || Int(coldSelection) == status.coldLevel)
            }

            Toggle("设备灯光", isOn: Binding(
                get: { status.lightEnabled },
                set: { bluetooth.setLight($0) }
            ))
            .disabled(bluetooth.isBusy)

            Text(bluetooth.lastCommandText)
                .font(.caption)
                .foregroundStyle(bluetooth.isBusy ? .orange : .secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var emptyStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("等待设备数据", systemImage: "thermometer")
                .font(.headline)
            Text("连接 B8X 并订阅 FFE4 状态通知后，这里会显示冷面温度、热面温度和实际风扇转速。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("附近蓝牙设备")
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
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(bluetooth.connectedName != nil)
            }
        }
    }

    private var protocolCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("协议状态")
                .font(.headline)
            Text(bluetooth.detailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("FFE0 服务 · FFE1 写入 · FFE4 通知")
                .font(.caption.monospaced())
                .foregroundStyle(.cyan)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var safetyNote: some View {
        Label("当前只开放参考项目已验证的常规档位：风扇 4000–4500 RPM、制冷原始值 92–175。未验证的超频数值不会写入设备，原厂温度保护保持不变。", systemImage: "shield.lefthalf.filled")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }
}
