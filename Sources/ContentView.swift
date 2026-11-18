import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = B8XBluetoothManager()
    @State private var windSelection = 4000.0
    @State private var coldSelection = 92.0
    // Keep slider drafts independent from incoming BLE telemetry.
    @State private var hasWindDraft = false
    @State private var hasColdDraft = false

    var body: some View {
        NavigationStack {
            ZStack {
                InstrumentBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 15) {
                        header
                        connectionPanel
                        if let status = bluetooth.status {
                            livePanel(status)
                            telemetryGrid(status)
                            controlsPanel(status)
                        } else {
                            waitingPanel
                        }
                        devicePanel
                        diagnosticsPanel
                        safetyFooter
                    }
                    .padding(.horizontal, 17)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onChange(of: bluetooth.status) { status in
            guard let status else {
                hasWindDraft = false
                hasColdDraft = false
                return
            }
            if !hasWindDraft { windSelection = Double(status.windLevel) }
            if !hasColdDraft { coldSelection = Double(status.coldLevel) }
        }
        .onChange(of: bluetooth.lastCommandText) { message in
            guard message == "设备已回报确认，控制成功",
                  let status = bluetooth.status else { return }
            if hasWindDraft && status.windLevel == Int(windSelection) {
                windSelection = Double(status.windLevel)
                hasWindDraft = false
            }
            if hasColdDraft && status.coldLevel == Int(coldSelection) {
                coldSelection = Double(status.coldLevel)
                hasColdDraft = false
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("B8X OC")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(B8XPalette.primaryText)
                Text("EXTREME THERMAL CONTROLLER")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.35)
                    .foregroundStyle(B8XPalette.muted)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Circle()
                    .fill(bluetooth.connectedName == nil ? B8XPalette.muted : B8XPalette.green)
                    .frame(width: 7, height: 7)
                    .shadow(color: B8XPalette.green.opacity(bluetooth.connectedName == nil ? 0 : 0.7), radius: 5)
                Text(bluetooth.connectedName == nil ? "未连接" : "已连接")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(bluetooth.connectedName == nil ? B8XPalette.muted : B8XPalette.green)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(B8XPalette.green.opacity(bluetooth.connectedName == nil ? 0.08 : 0.13), in: Capsule())
            .overlay(Capsule().strokeBorder(B8XPalette.green.opacity(0.2), lineWidth: 0.7))
        }
        .padding(.top, 5)
        .padding(.bottom, 2)
    }

    // MARK: - Connection

    private var connectionPanel: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(B8XPalette.cyan)
                    Text("DEVICE LINK")
                        .instrumentCaption()
                    Spacer()
                    Text(bluetooth.isScanning ? "正在扫描" : (bluetooth.connectedName == nil ? "BLE · READY" : "BLE · ACTIVE"))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(bluetooth.isScanning ? B8XPalette.amber : B8XPalette.muted)
                }

                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bluetooth.connectedName ?? "等待连接 B8X")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(B8XPalette.primaryText)
                        Text(bluetooth.stateText)
                            .font(.system(size: 11))
                            .foregroundStyle(B8XPalette.muted)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if bluetooth.connectedName != nil {
                        Button {
                            bluetooth.refreshStatus()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(B8XPalette.cyan.opacity(0.13), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(B8XPalette.cyan)
                        .disabled(bluetooth.isBusy)
                        Button("断开") { bluetooth.disconnect() }
                            .font(.system(size: 11, weight: .semibold))
                            .buttonStyle(.bordered)
                            .tint(B8XPalette.red)
                    } else {
                        Button(bluetooth.isScanning ? "停止" : "搜索设备") {
                            bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.startScan()
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(B8XPalette.cyan)
                    }
                }
            }
        }
    }

    // MARK: - Live hero

    private func livePanel(_ status: B8XStatus) -> some View {
        InstrumentCard {
            VStack(spacing: 10) {
                HStack {
                    Label("LIVE TELEMETRY", systemImage: "waveform.path.ecg")
                        .instrumentCaption()
                    Spacer()
                    Text("20 BYTE FRAME")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(B8XPalette.muted.opacity(0.8))
                }

                FanGauge(actualRPM: status.fanRPM, targetRPM: Int(windSelection))
                    .frame(height: 218)
                    .padding(.top, 2)

                HStack(spacing: 7) {
                    StatusPill(
                        title: status.modeRaw == 0 ? "自动模式" : status.modeRaw == 1 ? "手动模式" : "模式 \(status.modeRaw)",
                        icon: "dial.low",
                        tint: status.modeRaw == 1 ? B8XPalette.cyan : B8XPalette.green
                    )
                    StatusPill(
                        title: status.lightEnabled ? "灯光开启" : "灯光关闭",
                        icon: "lightbulb",
                        tint: status.lightEnabled ? B8XPalette.amber : B8XPalette.muted
                    )
                    Spacer(minLength: 0)
                    Text("刷新状态可同步")
                        .font(.system(size: 9))
                        .foregroundStyle(B8XPalette.muted)
                }
            }
        }
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(LinearGradient(colors: [B8XPalette.cyan.opacity(0.35), .clear, B8XPalette.green.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Telemetry

    private func telemetryGrid(_ status: B8XStatus) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionHeader("THERMAL SENSORS", detail: "实时温度")
            HStack(spacing: 10) {
                temperatureCard(title: "冷面温度", value: status.coldTemperature, suffix: "°C", icon: "snowflake")
                temperatureCard(title: "热面温度", value: Double(status.hotTemperature), suffix: "°C", icon: "thermometer.high")
            }
            HStack(spacing: 10) {
                smallMetricCard(title: "实际转速", value: status.fanRPM.formatted(), unit: "RPM", icon: "fan", tint: B8XPalette.cyan)
                smallMetricCard(title: "制冷设定", value: status.coldLevel.formatted(), unit: "LEVEL", icon: "snowflake", tint: B8XPalette.green)
            }
        }
    }

    private func temperatureCard(title: String, value: Double, suffix: String, icon: String) -> some View {
        let tint = B8XPalette.temperature(value)
        return InstrumentCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(B8XPalette.muted)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.1f", value))
                        .font(.system(size: 29, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(suffix)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(B8XPalette.muted)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(B8XPalette.track)
                        Capsule()
                            .fill(LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * min(max(value / 60, 0), 1))
                    }
                }
                .frame(height: 5)
                Text(value >= 44 ? "温度偏高" : value >= 39 ? "温度上升" : "温度正常")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(tint.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func smallMetricCard(title: String, value: String, unit: String, icon: String, tint: Color) -> some View {
        InstrumentCard {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 31, height: 31)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(B8XPalette.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(B8XPalette.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(unit)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(B8XPalette.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Controls

    private func controlsPanel(_ status: B8XStatus) -> some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Label("DEVICE CONTROL", systemImage: "slider.horizontal.3")
                        .instrumentCaption()
                    Spacer()
                    if bluetooth.isBusy {
                        ProgressView().tint(B8XPalette.cyan).scaleEffect(0.8)
                        Text("处理中")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(B8XPalette.amber)
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("运行模式").font(.system(size: 12, weight: .semibold)).foregroundStyle(B8XPalette.primaryText)
                        Spacer()
                        Text(status.modeRaw == 0 ? "AUTO" : status.modeRaw == 1 ? "MANUAL" : "UNKNOWN")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(B8XPalette.muted)
                    }
                    HStack(spacing: 8) {
                        modeButton(title: "自动调节", icon: "sparkles", selected: status.modeRaw == 0) {
                            bluetooth.setMode(0)
                        }
                        modeButton(title: "手动固定", icon: "hand.raised.fill", selected: status.modeRaw == 1) {
                            bluetooth.setMode(1)
                        }
                    }
                }

                controlSlider(
                    title: "风扇转速",
                    valueText: "\(Int(windSelection)) RPM",
                    rangeText: "4,000 — 4,500 RPM",
                    value: $windSelection,
                    range: 4000...4500,
                    step: 100,
                    tint: B8XPalette.cyan,
                    isUnchanged: Int(windSelection) == status.windLevel,
                    apply: { bluetooth.setWind(Int(windSelection)) },
                    editing: { editing in if editing { hasWindDraft = true } }
                )

                controlSlider(
                    title: "制冷档位",
                    valueText: "\(Int(coldSelection))",
                    rangeText: "协议档位 · 92 — 175",
                    value: $coldSelection,
                    range: 92...175,
                    step: 1,
                    tint: B8XPalette.green,
                    isUnchanged: Int(coldSelection) == status.coldLevel,
                    apply: { bluetooth.setCold(Int(coldSelection)) },
                    editing: { editing in if editing { hasColdDraft = true } }
                )

                Rectangle()
                    .fill(B8XPalette.stroke)
                    .frame(height: 1)

                HStack(spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(B8XPalette.amber)
                        .frame(width: 33, height: 33)
                        .background(B8XPalette.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("设备灯光").font(.system(size: 12, weight: .semibold)).foregroundStyle(B8XPalette.primaryText)
                        Text(status.lightEnabled ? "当前已开启" : "当前已关闭")
                            .font(.system(size: 10)).foregroundStyle(B8XPalette.muted)
                    }
                    Spacer()
                    Toggle("设备灯光", isOn: Binding(
                        get: { status.lightEnabled },
                        set: { bluetooth.setLight($0) }
                    ))
                    .labelsHidden()
                    .tint(B8XPalette.green)
                    .disabled(bluetooth.isBusy)
                }

                Text(bluetooth.lastCommandText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(bluetooth.isBusy ? B8XPalette.amber : B8XPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func controlSlider(
        title: String,
        valueText: String,
        rangeText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        tint: Color,
        isUnchanged: Bool,
        apply: @escaping () -> Void,
        editing: @escaping (Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(B8XPalette.primaryText)
                Spacer()
                Text(valueText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            Slider(value: value, in: range, step: step, onEditingChanged: editing)
                .tint(tint)
                .disabled(bluetooth.isBusy)
            HStack {
                Text(rangeText)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(B8XPalette.muted)
                Spacer()
                Button(action: apply) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("应用")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isUnchanged ? B8XPalette.muted : B8XPalette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(isUnchanged ? B8XPalette.track : tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(bluetooth.isBusy || isUnchanged)
            }
        }
    }

    private func modeButton(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(selected ? B8XPalette.ink : B8XPalette.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(selected ? B8XPalette.cyan : B8XPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? B8XPalette.cyan.opacity(0.35) : B8XPalette.stroke, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .disabled(bluetooth.isBusy || selected)
    }

    // MARK: - Empty state / devices / diagnostics

    private var waitingPanel: some View {
        InstrumentCard {
            VStack(spacing: 12) {
                Image(systemName: "fanblades")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(B8XPalette.cyan)
                    .padding(.top, 5)
                Text("等待设备数据")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(B8XPalette.primaryText)
                Text("连接 B8X 并开启状态通知后，这里会显示实时转速、冷面温度和热面温度。")
                    .font(.system(size: 11))
                    .foregroundStyle(B8XPalette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
        }
    }

    private var devicePanel: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("NEARBY DEVICES", systemImage: "antenna.radiowaves.left.and.right")
                        .instrumentCaption()
                    Spacer()
                    Text("\(bluetooth.devices.count) FOUND")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(B8XPalette.muted)
                }
                if bluetooth.devices.isEmpty {
                    Text("搜索附近设备后，发现的 B8X 将显示在这里。")
                        .font(.system(size: 10))
                        .foregroundStyle(B8XPalette.muted)
                        .padding(.vertical, 4)
                }
                ForEach(bluetooth.devices) { device in
                    Button {
                        bluetooth.connect(device)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "fanblades")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(B8XPalette.cyan)
                                .frame(width: 31, height: 31)
                                .background(B8XPalette.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(B8XPalette.primaryText)
                                Text(device.id.uuidString)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(B8XPalette.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("\(device.rssi) dBm")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(B8XPalette.muted)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(B8XPalette.muted)
                        }
                        .padding(9)
                        .background(B8XPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(bluetooth.connectedName != nil)
                }
            }
        }
    }

    private var diagnosticsPanel: some View {
        InstrumentCard {
            DisclosureGroup(isExpanded: .constant(false)) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(bluetooth.detailText)
                        .font(.system(size: 10))
                        .foregroundStyle(B8XPalette.muted)
                    Text("FFE0 SERVICE  ·  FFE1 WRITE  ·  FFE4 NOTIFY")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(B8XPalette.cyan)
                    if let status = bluetooth.status {
                        Text(status.raw.map { String(format: "%02X", $0) }.joined(separator: " "))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(B8XPalette.green)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 10)
            } label: {
                HStack {
                    Label("协议诊断", systemImage: "waveform.path")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(B8XPalette.muted)
                    Spacer()
                    Text("ADVANCED")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(B8XPalette.muted.opacity(0.7))
                }
            }
            .tint(B8XPalette.cyan)
        }
    }

    private var safetyFooter: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(B8XPalette.green)
            Text("当前开放已验证的常规范围：风扇 4,000–4,500 RPM，制冷原始值 92–175。未验证的超频数值不会写入设备。")
                .font(.system(size: 9))
                .foregroundStyle(B8XPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 3)
        .padding(.top, 1)
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).instrumentCaption()
            Spacer()
            Text(detail)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(B8XPalette.muted)
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Instrument components

private struct InstrumentBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.045, green: 0.063, blue: 0.09), Color(red: 0.018, green: 0.024, blue: 0.038)],
                startPoint: .top,
                endPoint: .bottom
            )
            Canvas { context, size in
                var grid = Path()
                stride(from: CGFloat(0), through: size.width, by: 28).forEach { x in
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                stride(from: CGFloat(0), through: size.height, by: 28).forEach { y in
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(.white.opacity(0.025)), lineWidth: 0.5)
            }
            .drawingGroup()
            RadialGradient(
                colors: [B8XPalette.cyan.opacity(0.14), .clear],
                center: UnitPoint(x: 0.82, y: 0.06),
                startRadius: 0,
                endRadius: 390
            )
            RadialGradient(
                colors: [B8XPalette.green.opacity(0.06), .clear],
                center: UnitPoint(x: 0.04, y: 0.47),
                startRadius: 0,
                endRadius: 300
            )
            .blendMode(.screen)
        }
        .ignoresSafeArea()
    }
}

private struct InstrumentCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(B8XPalette.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .strokeBorder(B8XPalette.stroke, lineWidth: 0.8)
            )
    }
}

private struct FanGauge: View {
    let actualRPM: Int
    let targetRPM: Int
    private let sweep: CGFloat = 280.0 / 360.0

    private var fraction: CGFloat {
        CGFloat(min(max(Double(actualRPM) / 5000.0, 0), 1))
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(B8XPalette.track, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(130))
            Circle()
                .trim(from: 0, to: sweep * fraction)
                .stroke(
                    AngularGradient(colors: [B8XPalette.cyan.opacity(0.45), B8XPalette.cyan, B8XPalette.green], center: .center, startAngle: .degrees(130), endAngle: .degrees(410)),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(130))
                .shadow(color: B8XPalette.cyan.opacity(0.32), radius: 8)
            GaugeTicks()
                .stroke(B8XPalette.muted.opacity(0.32), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .padding(1)
            VStack(spacing: 3) {
                Text("ACTUAL FAN SPEED")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(B8XPalette.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(actualRPM > 0 ? actualRPM.formatted() : "—")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(B8XPalette.primaryText)
                    Text("RPM")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(B8XPalette.cyan)
                }
                Text("目标 \(targetRPM.formatted()) RPM")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(B8XPalette.muted)
                    .padding(.top, 2)
            }
            .offset(y: 1)
        }
        .frame(width: 214, height: 214)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("实际风扇转速 \(actualRPM) RPM，目标 \(targetRPM) RPM")
    }
}

private struct GaugeTicks: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 2
        for index in 0...40 {
            let progress = Double(index) / 40
            let angle = CGFloat((130.0 + progress * 280.0) * Double.pi / 180)
            let major = index % 5 == 0
            let innerRadius = radius - (major ? 10 : 5)
            path.move(to: CGPoint(x: centre.x + cos(angle) * innerRadius, y: centre.y + sin(angle) * innerRadius))
            path.addLine(to: CGPoint(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius))
        }
        return path
    }
}

private struct StatusPill: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(title).font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 0.6))
    }
}

private enum B8XPalette {
    static let primaryText = Color(red: 0.93, green: 0.95, blue: 0.99)
    static let muted = Color(red: 0.53, green: 0.58, blue: 0.68)
    static let cyan = Color(red: 0.21, green: 0.87, blue: 1.00)
    static let green = Color(red: 0.25, green: 0.88, blue: 0.55)
    static let amber = Color(red: 1.00, green: 0.70, blue: 0.27)
    static let red = Color(red: 1.00, green: 0.37, blue: 0.34)
    static let ink = Color(red: 0.02, green: 0.08, blue: 0.11)
    static let card = Color(red: 0.075, green: 0.09, blue: 0.125).opacity(0.96)
    static let surfaceRaised = Color(red: 0.105, green: 0.125, blue: 0.17)
    static let stroke = Color.white.opacity(0.075)
    static let track = Color.white.opacity(0.09)

    static func temperature(_ value: Double) -> Color {
        switch value {
        case ..<28: return Color(red: 0.30, green: 0.63, blue: 1.0)
        case ..<34: return green
        case ..<39: return Color(red: 0.95, green: 0.80, blue: 0.30)
        case ..<44: return amber
        default: return red
        }
    }
}

private extension View {
    func instrumentCaption() -> some View {
        font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.95)
            .foregroundStyle(B8XPalette.muted)
    }
}
