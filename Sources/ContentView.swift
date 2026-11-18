import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = B8XBluetoothManager()
    @State private var windSelection = 4000.0
    @State private var coldSelection = 92.0
    @State private var hasWindDraft = false
    @State private var hasColdDraft = false

    var body: some View {
        ZStack {
            MacaronBackdrop()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
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
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 30)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacaronPalette.canvas.ignoresSafeArea())
        .preferredColorScheme(.light)
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
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(MacaronPalette.lavender)
                    .frame(width: 52, height: 52)
                Image(systemName: "fanblades.fill")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(MacaronPalette.purple)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("B8X OC")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(MacaronPalette.ink)
                Text("小小散热控制站")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacaronPalette.muted)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(bluetooth.connectedName == nil ? MacaronPalette.muted.opacity(0.55) : MacaronPalette.mintStrong)
                    .frame(width: 7, height: 7)
                Text(bluetooth.connectedName == nil ? "未连接" : "已连接")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(bluetooth.connectedName == nil ? MacaronPalette.muted : MacaronPalette.mintText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(bluetooth.connectedName == nil ? MacaronPalette.lilacWash : MacaronPalette.mint)
            .clipShape(Capsule())
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    // MARK: - Connection

    private var connectionPanel: some View {
        MacaronCard(tint: MacaronPalette.sky) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("设备连接", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MacaronPalette.blueText)
                    Spacer()
                    Text(bluetooth.isScanning ? "正在搜索…" : (bluetooth.connectedName == nil ? "蓝牙已就绪" : "连接正常"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(bluetooth.isScanning ? MacaronPalette.peachText : MacaronPalette.muted)
                }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bluetooth.connectedName ?? "等待连接 B8X")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(MacaronPalette.ink)
                        Text(bluetooth.stateText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MacaronPalette.muted)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if bluetooth.connectedName != nil {
                        Button {
                            bluetooth.refreshStatus()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(MacaronPalette.blueText)
                                .frame(width: 38, height: 38)
                                .background(.white.opacity(0.72), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(bluetooth.isBusy)
                        Button("断开") { bluetooth.disconnect() }
                            .font(.system(size: 11, weight: .semibold))
                            .buttonStyle(.bordered)
                            .tint(MacaronPalette.pinkText)
                    } else {
                        Button(bluetooth.isScanning ? "停止搜索" : "搜索设备") {
                            bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.startScan()
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .background(MacaronPalette.blueStrong, in: Capsule())
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Live status

    private func livePanel(_ status: B8XStatus) -> some View {
        MacaronCard(tint: MacaronPalette.lavender) {
            VStack(spacing: 10) {
                HStack {
                    Label("实时运行", systemImage: "waveform.path.ecg")
                        .macaronSectionLabel()
                    Spacer()
                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(MacaronPalette.purple)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.7), in: Capsule())
                }
                FanGauge(actualRPM: status.fanRPM, targetRPM: Int(windSelection))
                    .frame(height: 214)
                HStack(spacing: 7) {
                    StatusPill(
                        title: status.modeRaw == 0 ? "自动模式" : status.modeRaw == 1 ? "手动模式" : "模式 \(status.modeRaw)",
                        icon: "dial.low",
                        tint: status.modeRaw == 1 ? MacaronPalette.blueStrong : MacaronPalette.mintStrong
                    )
                    StatusPill(
                        title: status.lightEnabled ? "灯光开启" : "灯光关闭",
                        icon: "lightbulb",
                        tint: status.lightEnabled ? MacaronPalette.yellowText : MacaronPalette.muted
                    )
                    Spacer(minLength: 0)
                    Text("可刷新同步")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(MacaronPalette.muted)
                }
            }
        }
    }

    // MARK: - Sensors

    private func telemetryGrid(_ status: B8XStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("温度与状态", detail: "实时数据")
            HStack(spacing: 10) {
                temperatureCard(title: "冷面温度", value: status.coldTemperature, suffix: "°C", icon: "snowflake")
                temperatureCard(title: "热面温度", value: Double(status.hotTemperature), suffix: "°C", icon: "thermometer.high")
            }
            HStack(spacing: 10) {
                smallMetricCard(title: "实际转速", value: status.fanRPM.formatted(), unit: "RPM", icon: "fan", tint: MacaronPalette.blueStrong, wash: MacaronPalette.sky)
                smallMetricCard(title: "制冷设定", value: status.coldLevel.formatted(), unit: "LEVEL", icon: "snowflake", tint: MacaronPalette.mintText, wash: MacaronPalette.mint)
            }
        }
    }

    private func temperatureCard(title: String, value: Double, suffix: String, icon: String) -> some View {
        let tint = MacaronPalette.temperature(value)
        return MacaronCard(tint: tint.wash) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tint.text)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacaronPalette.muted)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.1f", value))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(MacaronPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(suffix)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(MacaronPalette.muted)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MacaronPalette.track)
                        Capsule()
                            .fill(tint.fill)
                            .frame(width: proxy.size.width * min(max(value / 60, 0), 1))
                    }
                }
                .frame(height: 6)
                Text(value >= 44 ? "温度偏高" : value >= 39 ? "温度上升" : "温度正常")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func smallMetricCard(title: String, value: String, unit: String, icon: String, tint: Color, wash: Color) -> some View {
        MacaronCard(tint: wash) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MacaronPalette.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(MacaronPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(unit)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(MacaronPalette.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Controls

    private func controlsPanel(_ status: B8XStatus) -> some View {
        MacaronCard(tint: MacaronPalette.peach) {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Label("设备控制", systemImage: "slider.horizontal.3")
                        .macaronSectionLabel()
                    Spacer()
                    if bluetooth.isBusy {
                        ProgressView().tint(MacaronPalette.peachText).scaleEffect(0.85)
                        Text("处理中")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MacaronPalette.peachText)
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("运行模式")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(MacaronPalette.ink)
                        Spacer()
                        Text(status.modeRaw == 0 ? "AUTO" : status.modeRaw == 1 ? "MANUAL" : "UNKNOWN")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(MacaronPalette.muted)
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
                    rangeText: "4,000 — 8,000 RPM · 1 RPM 步进",
                    value: $windSelection,
                    range: 4000...8000,
                    step: 1,
                    tint: MacaronPalette.blueStrong,
                    wash: MacaronPalette.sky,
                    isUnchanged: Int(windSelection) == status.windLevel,
                    apply: { bluetooth.setWind(Int(windSelection)) },
                    editing: { editing in if editing { hasWindDraft = true } }
                )

                controlSlider(
                    title: "制冷档位",
                    valueText: "\(Int(coldSelection))",
                    rangeText: "单字节协议可表示范围 · 92 — 255",
                    value: $coldSelection,
                    range: 92...255,
                    step: 1,
                    tint: MacaronPalette.mintText,
                    wash: MacaronPalette.mint,
                    isUnchanged: Int(coldSelection) == status.coldLevel,
                    apply: { bluetooth.setCold(Int(coldSelection)) },
                    editing: { editing in if editing { hasColdDraft = true } }
                )

                Rectangle()
                    .fill(MacaronPalette.line)
                    .frame(height: 1)

                HStack(spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MacaronPalette.yellowText)
                        .frame(width: 36, height: 36)
                        .background(MacaronPalette.yellow, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("设备灯光")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(MacaronPalette.ink)
                        Text(status.lightEnabled ? "当前已开启" : "当前已关闭")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MacaronPalette.muted)
                    }
                    Spacer()
                    Toggle("设备灯光", isOn: Binding(
                        get: { status.lightEnabled },
                        set: { bluetooth.setLight($0) }
                    ))
                    .labelsHidden()
                    .tint(MacaronPalette.mintStrong)
                    .disabled(bluetooth.isBusy)
                }

                Text(bluetooth.lastCommandText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(bluetooth.isBusy ? MacaronPalette.peachText : MacaronPalette.muted)
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
        wash: Color,
        isUnchanged: Bool,
        apply: @escaping () -> Void,
        editing: @escaping (Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MacaronPalette.ink)
                Spacer()
                Text(valueText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            Slider(value: value, in: range, step: step, onEditingChanged: editing)
                .tint(tint)
                .disabled(bluetooth.isBusy)
            HStack(alignment: .center) {
                Text(rangeText)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(MacaronPalette.muted)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button(action: apply) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                        Text("应用")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isUnchanged ? MacaronPalette.muted : MacaronPalette.ink)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(isUnchanged ? MacaronPalette.track : wash, in: Capsule())
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
                Text(title).font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(selected ? MacaronPalette.purpleText : MacaronPalette.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selected ? MacaronPalette.lavender : MacaronPalette.surfaceSoft, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(selected ? MacaronPalette.purple.opacity(0.22) : MacaronPalette.line, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .disabled(bluetooth.isBusy || selected)
    }

    // MARK: - Empty state / devices / diagnostics

    private var waitingPanel: some View {
        MacaronCard(tint: MacaronPalette.lavender) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.72))
                        .frame(width: 74, height: 74)
                    Image(systemName: "fanblades")
                        .font(.system(size: 35, weight: .regular))
                        .foregroundStyle(MacaronPalette.blueStrong)
                }
                .padding(.top, 5)
                Text("等待设备数据")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(MacaronPalette.ink)
                Text("连接 B8X 并开启状态通知后，这里就会显示实时转速、冷面温度和热面温度。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MacaronPalette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 7)
                Text("READY WHEN YOU ARE")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(MacaronPalette.purpleText)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.68), in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var devicePanel: some View {
        MacaronCard(tint: MacaronPalette.mint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("附近设备", systemImage: "antenna.radiowaves.left.and.right")
                        .macaronSectionLabel()
                    Spacer()
                    Text("\(bluetooth.devices.count) FOUND")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(MacaronPalette.mintText)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.7), in: Capsule())
                }
                if bluetooth.devices.isEmpty {
                    Text("搜索附近设备后，发现的 B8X 将显示在这里。")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MacaronPalette.muted)
                        .padding(.vertical, 5)
                }
                ForEach(bluetooth.devices) { device in
                    Button {
                        bluetooth.connect(device)
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "fanblades.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MacaronPalette.mintText)
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(MacaronPalette.ink)
                                Text(device.id.uuidString)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(MacaronPalette.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("\(device.rssi) dBm")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(MacaronPalette.muted)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(MacaronPalette.muted)
                        }
                        .padding(9)
                        .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                    .disabled(bluetooth.connectedName != nil)
                }
            }
        }
    }

    private var diagnosticsPanel: some View {
        MacaronCard(tint: MacaronPalette.lilacWash) {
            DisclosureGroup(isExpanded: .constant(false)) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(bluetooth.detailText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MacaronPalette.muted)
                    Text("FFE0 SERVICE  ·  FFE1 WRITE  ·  FFE4 NOTIFY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(MacaronPalette.purpleText)
                    if let status = bluetooth.status {
                        Text(status.raw.map { String(format: "%02X", $0) }.joined(separator: " "))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(MacaronPalette.mintText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 10)
            } label: {
                HStack {
                    Label("协议诊断", systemImage: "waveform.path")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MacaronPalette.purpleText)
                    Spacer()
                    Text("ADVANCED")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(MacaronPalette.muted)
                }
            }
            .tint(MacaronPalette.purpleText)
        }
    }

    private var safetyFooter: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MacaronPalette.peachText)
                .frame(width: 27, height: 27)
                .background(MacaronPalette.peach, in: RoundedRectangle(cornerRadius: 9))
            Text("风扇设定范围已扩展至 4,000–8,000 RPM（1 RPM 步进）；制冷原始档位目前开放 92–255。300 档超出当前单字节协议表示范围，暂不发送。")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(MacaronPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(MacaronPalette.line, lineWidth: 0.8))
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(MacaronPalette.ink)
            Spacer()
            Text(detail)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MacaronPalette.muted)
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Macaron visual system

private struct MacaronBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [MacaronPalette.canvas, Color(red: 1.0, green: 0.97, blue: 0.94)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(MacaronPalette.pink.opacity(0.30))
                .frame(width: 230, height: 230)
                .blur(radius: 65)
                .offset(x: 155, y: -300)
            Circle()
                .fill(MacaronPalette.sky.opacity(0.42))
                .frame(width: 250, height: 250)
                .blur(radius: 75)
                .offset(x: -170, y: 30)
            Circle()
                .fill(MacaronPalette.mint.opacity(0.42))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: 145, y: 390)
        }
        .ignoresSafeArea()
    }
}

private struct MacaronCard<Content: View>: View {
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .fill(.white.opacity(0.92))
                    .shadow(color: tint.opacity(0.48), radius: 14, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .strokeBorder(tint.opacity(0.78), lineWidth: 1)
            )
    }
}

private struct FanGauge: View {
    let actualRPM: Int
    let targetRPM: Int
    private let sweep: CGFloat = 280.0 / 360.0
    private let scaleMaximum = 8000.0

    private var fraction: CGFloat {
        CGFloat(min(max(Double(actualRPM) / scaleMaximum, 0), 1))
    }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(MacaronPalette.track, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                .rotationEffect(.degrees(130))
            Circle()
                .trim(from: 0, to: sweep * fraction)
                .stroke(
                    LinearGradient(colors: [MacaronPalette.pinkStrong, MacaronPalette.purple, MacaronPalette.blueStrong], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(130))
                .shadow(color: MacaronPalette.pink.opacity(0.55), radius: 7)
            GaugeTicks()
                .stroke(MacaronPalette.muted.opacity(0.45), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .padding(1)
            VStack(spacing: 4) {
                Text("ACTUAL FAN SPEED")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(MacaronPalette.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(actualRPM > 0 ? actualRPM.formatted() : "—")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(MacaronPalette.ink)
                    Text("RPM")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(MacaronPalette.pinkStrong)
                }
                Text("目标 \(targetRPM.formatted()) RPM")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MacaronPalette.muted)
                    .padding(.top, 2)
                HStack(spacing: 5) {
                    Circle().fill(MacaronPalette.pinkStrong).frame(width: 5, height: 5)
                    Text("实际转速进度 · 0–8,000 RPM")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MacaronPalette.muted)
                }
                .padding(.top, 3)
            }
            .offset(y: 2)
        }
        .frame(width: 214, height: 214)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("实际风扇转速 \(actualRPM) RPM，量程 0 至 8000 RPM，目标 \(targetRPM) RPM")
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
            Text(title).font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(MacaronPalette.ink.opacity(0.78))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(tint.opacity(0.62), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.95), lineWidth: 0.7))
    }
}

private enum MacaronPalette {
    static let canvas = Color(red: 1.00, green: 0.975, blue: 0.955)
    static let ink = Color(red: 0.22, green: 0.25, blue: 0.34)
    static let muted = Color(red: 0.53, green: 0.56, blue: 0.65)
    static let line = Color(red: 0.89, green: 0.88, blue: 0.91)
    static let track = Color(red: 0.91, green: 0.90, blue: 0.94)
    static let surfaceSoft = Color(red: 0.98, green: 0.97, blue: 0.99)

    static let sky = Color(red: 0.84, green: 0.94, blue: 0.99)
    static let blueStrong = Color(red: 0.35, green: 0.69, blue: 0.86)
    static let blueText = Color(red: 0.23, green: 0.53, blue: 0.70)

    static let lavender = Color(red: 0.93, green: 0.89, blue: 0.99)
    static let lilacWash = Color(red: 0.96, green: 0.93, blue: 0.99)
    static let purple = Color(red: 0.69, green: 0.57, blue: 0.85)
    static let purpleText = Color(red: 0.49, green: 0.38, blue: 0.68)

    static let mint = Color(red: 0.87, green: 0.96, blue: 0.89)
    static let mintStrong = Color(red: 0.49, green: 0.74, blue: 0.59)
    static let mintText = Color(red: 0.27, green: 0.56, blue: 0.40)

    static let pink = Color(red: 0.99, green: 0.88, blue: 0.92)
    static let pinkStrong = Color(red: 0.88, green: 0.52, blue: 0.65)
    static let pinkText = Color(red: 0.73, green: 0.37, blue: 0.51)

    static let peach = Color(red: 1.00, green: 0.92, blue: 0.85)
    static let peachText = Color(red: 0.72, green: 0.48, blue: 0.31)
    static let yellow = Color(red: 1.00, green: 0.96, blue: 0.80)
    static let yellowText = Color(red: 0.70, green: 0.56, blue: 0.23)

    struct TemperatureTint {
        let fill: LinearGradient
        let text: Color
        let wash: Color
    }

    static func temperature(_ value: Double) -> TemperatureTint {
        switch value {
        case ..<28:
            return TemperatureTint(fill: LinearGradient(colors: [sky, blueStrong], startPoint: .leading, endPoint: .trailing), text: blueText, wash: sky)
        case ..<34:
            return TemperatureTint(fill: LinearGradient(colors: [mint, mintStrong], startPoint: .leading, endPoint: .trailing), text: mintText, wash: mint)
        case ..<39:
            return TemperatureTint(fill: LinearGradient(colors: [yellow, yellowText], startPoint: .leading, endPoint: .trailing), text: yellowText, wash: yellow)
        case ..<44:
            return TemperatureTint(fill: LinearGradient(colors: [peach, peachText], startPoint: .leading, endPoint: .trailing), text: peachText, wash: peach)
        default:
            return TemperatureTint(fill: LinearGradient(colors: [pink, pinkStrong], startPoint: .leading, endPoint: .trailing), text: pinkText, wash: pink)
        }
    }
}

private extension View {
    func macaronSectionLabel() -> some View {
        font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(MacaronPalette.ink)
    }
}
