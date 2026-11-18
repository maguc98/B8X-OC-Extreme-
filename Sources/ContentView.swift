import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = B8XBluetoothManager()
    @State private var tab: AppTab = .overview
    @State private var fanTarget = 4200.0
    @State private var coldTarget = 110.0
    @State private var fanDirty = false
    @State private var coldDirty = false

    var body: some View {
        ZStack {
            Studio.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView(showsIndicators: false) {
                    Group {
                        switch tab {
                        case .overview: overview
                        case .controls: controls
                        case .devices: devices
                        case .diagnostics: diagnostics
                        }
                    }
                    .padding(.horizontal, 19)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .preferredColorScheme(.light)
        .onChange(of: bluetooth.status) { value in
            guard let value else { fanDirty = false; coldDirty = false; return }
            if !fanDirty { fanTarget = min(max(Double(value.windLevel), 4000), 6000) }
            if !coldDirty { coldTarget = min(max(Double(value.coldLevel), 92), 255) }
        }
        .onChange(of: bluetooth.lastCommandText) { message in
            guard message == "设备已回报确认，控制成功", let value = bluetooth.status else { return }
            fanTarget = min(max(Double(value.windLevel), 4000), 6000)
            coldTarget = min(max(Double(value.coldLevel), 92), 255)
            fanDirty = false
            coldDirty = false
        }
    }

    private var topBar: some View {
        HStack(spacing: 11) {
            Image(systemName: "fanblades.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Studio.violetInk)
                .frame(width: 44, height: 44)
                .background(Studio.lilac, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 2) {
                Text("B8X").font(.system(size: 18, weight: .heavy, design: .rounded)).tracking(1.1).foregroundStyle(Studio.ink)
                Text("COOLING STUDIO").font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(1.5).foregroundStyle(Studio.muted)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(bluetooth.connectedName == nil ? Studio.stone : Studio.green).frame(width: 7, height: 7)
                Text(bluetooth.connectedName == nil ? "未连接" : "设备在线")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(bluetooth.connectedName == nil ? Studio.muted : Studio.greenInk)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(bluetooth.connectedName == nil ? Studio.neutral : Studio.mint, in: Capsule())
        }
        .padding(.horizontal, 19).padding(.top, 9).padding(.bottom, 10)
        .background(Studio.canvas)
    }

    private var tabBar: some View {
        HStack(spacing: 5) {
            ForEach(AppTab.allCases, id: \.self) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { tab = item }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item == tab ? item.selectedIcon : item.icon)
                            .font(.system(size: 17, weight: .semibold)).frame(height: 20)
                        Text(item.title).font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(item == tab ? Studio.ink : Studio.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(item == tab ? item.tint : .clear, in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 7)
        .background(.white.opacity(0.98))
        .overlay(alignment: .top) { Rectangle().fill(Studio.line).frame(height: 1) }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 15) {
            heading("DEVICE OVERVIEW", "散热状态", "设备运行情况，一眼掌握。")
            if let s = bluetooth.status {
                Card {
                    VStack(spacing: 12) {
                        HStack {
                            Label("实时风扇", systemImage: "wind").font(.system(size: 12, weight: .bold)).foregroundStyle(Studio.ink)
                            Spacer()
                            Text("LIVE DATA").font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(1.2)
                                .foregroundStyle(Studio.blueInk).padding(.horizontal, 9).padding(.vertical, 6).background(Studio.sky, in: Capsule())
                        }
                        SpeedDial(actual: s.fanRPM, target: Int(fanTarget)).frame(height: 210)
                        HStack(spacing: 8) {
                            statusChip(s.modeRaw == 0 ? "自动模式" : "手动模式", icon: "slider.horizontal.3", wash: Studio.lilac, ink: Studio.violetInk)
                            statusChip(s.lightEnabled ? "灯光开启" : "灯光关闭", icon: "lightbulb", wash: Studio.butter, ink: Studio.goldInk)
                        }
                    }
                }
                HStack(spacing: 10) {
                    temperatureCard("冷面温度", value: String(format: "%.1f", s.coldTemperature), unit: "°C", icon: "snowflake", wash: Studio.sky, ink: Studio.blueInk)
                    temperatureCard("热面温度", value: "\(s.hotTemperature)", unit: "°C", icon: "thermometer.medium", wash: Studio.peach, ink: Studio.coral)
                }
                HStack(spacing: 10) {
                    metricCard("实测转速", value: s.fanRPM.formatted(), unit: "RPM", icon: "fan", wash: Studio.lilac, ink: Studio.violetInk)
                    metricCard("制冷档位", value: "\(s.coldLevel)", unit: "LEVEL", icon: "snowflake", wash: Studio.mint, ink: Studio.greenInk)
                }
                Button { tab = .controls } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("调整散热表现").font(.system(size: 13, weight: .bold))
                            Text("前往风扇、制冷与灯光控制").font(.system(size: 10, weight: .medium)).opacity(0.75)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .bold))
                            .frame(width: 31, height: 31).background(.white.opacity(0.55), in: Circle())
                    }
                    .foregroundStyle(Studio.ink).padding(15).background(Studio.butter, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
            } else {
                emptyState
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 15) {
            heading("TUNING", "设备控制", "每项调整都会等待设备回报确认。")
            if let s = bluetooth.status {
                Card {
                    VStack(alignment: .leading, spacing: 11) {
                        section("运行模式", note: "MODE")
                        HStack(spacing: 9) {
                            modeButton("自动调节", detail: "由设备管理风扇", icon: "sparkles", selected: s.modeRaw == 0) { bluetooth.setMode(0) }
                            modeButton("手动控制", detail: "使用下方设定值", icon: "hand.raised.fill", selected: s.modeRaw == 1) { bluetooth.setMode(1) }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            section("风扇转速", note: "FAN SPEED")
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(Int(fanTarget).formatted()).font(.system(size: 24, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Studio.blueInk)
                                Text("RPM").font(.system(size: 8, weight: .heavy)).tracking(1).foregroundStyle(Studio.muted)
                            }
                        }
                        Slider(value: $fanTarget, in: 4000...6000, step: 1) { editing in if editing { fanDirty = true } }.tint(Studio.blue)
                        HStack {
                            Text("4,000 RPM"); Spacer(); Text("上限 6,000 RPM")
                        }.font(.system(size: 9, weight: .semibold)).foregroundStyle(Studio.muted)
                        if s.windLevel > 6000 {
                            Text("设备当前回报 \(s.windLevel) RPM，高于新上限。可先将风扇设定调低至 6,000 RPM 或以下。")
                                .font(.system(size: 9, weight: .medium)).foregroundStyle(Studio.goldInk)
                                .padding(9).frame(maxWidth: .infinity, alignment: .leading).background(Studio.butter, in: RoundedRectangle(cornerRadius: 11))
                        }
                        HStack {
                            Text(fanDirty ? "有未应用的更改" : "设备设定 \(s.windLevel) RPM").font(.system(size: 10, weight: .medium)).foregroundStyle(Studio.muted)
                            Spacer()
                            Button { bluetooth.setWind(Int(fanTarget)) } label: { actionPill("应用转速") }
                                .disabled(bluetooth.isBusy || Int(fanTarget) == s.windLevel)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            section("制冷档位", note: "COOLING LEVEL")
                            Spacer()
                            Text("\(Int(coldTarget))").font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Studio.greenInk)
                        }
                        Slider(value: $coldTarget, in: 92...255, step: 1) { editing in if editing { coldDirty = true } }.tint(Studio.green)
                        HStack {
                            Text("92"); Spacer(); Text("255 · 协议上限")
                        }.font(.system(size: 9, weight: .semibold)).foregroundStyle(Studio.muted)
                        HStack {
                            Text(coldDirty ? "有未应用的更改" : "设备设定 \(s.coldLevel)").font(.system(size: 10, weight: .medium)).foregroundStyle(Studio.muted)
                            Spacer()
                            Button { bluetooth.setCold(Int(coldTarget)) } label: { actionPill("应用档位") }
                                .disabled(bluetooth.isBusy || Int(coldTarget) == s.coldLevel)
                        }
                    }
                }
                Card {
                    HStack(spacing: 11) {
                        Image(systemName: "lightbulb.fill").font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Studio.goldInk).frame(width: 40, height: 40).background(Studio.butter, in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("设备灯光").font(.system(size: 12, weight: .bold)).foregroundStyle(Studio.ink)
                            Text(s.lightEnabled ? "当前已开启" : "当前已关闭").font(.system(size: 9, weight: .medium)).foregroundStyle(Studio.muted)
                        }
                        Spacer()
                        Toggle("设备灯光", isOn: Binding(get: { s.lightEnabled }, set: { bluetooth.setLight($0) }))
                            .labelsHidden().tint(Studio.green).disabled(bluetooth.isBusy)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: bluetooth.isBusy ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                    Text(bluetooth.lastCommandText).font(.system(size: 10, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if bluetooth.isBusy { ProgressView().tint(Studio.blue) }
                }.foregroundStyle(Studio.muted).padding(12).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            } else { emptyState }
        }
    }

    private var devices: some View {
        VStack(alignment: .leading, spacing: 15) {
            heading("BLUETOOTH", "设备管理", "搜索并连接附近的飞智 B8X。")
            Card {
                VStack(alignment: .leading, spacing: 11) {
                    section("当前连接", note: "CONNECTION")
                    Text(bluetooth.connectedName ?? "尚未连接设备").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Studio.ink)
                    Text(bluetooth.stateText).font(.system(size: 10, weight: .medium)).foregroundStyle(Studio.muted)
                    if bluetooth.connectedName != nil {
                        HStack(spacing: 9) {
                            Button { bluetooth.refreshStatus() } label: { actionPill("刷新状态", icon: "arrow.clockwise") }
                            Button { bluetooth.disconnect() } label: { actionPill("断开连接", icon: "xmark") }
                        }
                    } else {
                        Button { bluetooth.isScanning ? bluetooth.stopScan() : bluetooth.startScan() } label: {
                            Label(bluetooth.isScanning ? "停止搜索" : "搜索附近设备", systemImage: bluetooth.isScanning ? "stop.fill" : "dot.radiowaves.left.and.right")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white).frame(maxWidth: .infinity)
                                .padding(.vertical, 13).background(Studio.blueInk, in: RoundedRectangle(cornerRadius: 13))
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Text("附近设备").font(.system(size: 14, weight: .bold)).foregroundStyle(Studio.ink)
                Spacer()
                Text(bluetooth.devices.isEmpty ? "暂无发现" : "\(bluetooth.devices.count) 个设备").font(.system(size: 9, weight: .semibold)).foregroundStyle(Studio.muted)
            }
            if bluetooth.devices.isEmpty {
                Card {
                    VStack(spacing: 9) {
                        Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 23)).foregroundStyle(Studio.blueInk)
                        Text(bluetooth.isScanning ? "正在寻找设备…" : "暂未发现设备").font(.system(size: 12, weight: .bold)).foregroundStyle(Studio.ink)
                        Text("请让散热器保持开机并靠近 iPhone。").font(.system(size: 10, weight: .medium)).foregroundStyle(Studio.muted)
                    }.frame(maxWidth: .infinity).padding(.vertical, 15)
                }
            } else {
                ForEach(bluetooth.devices) { device in
                    Button { bluetooth.connect(device) } label: {
                        HStack(spacing: 11) {
                            Image(systemName: "fanblades").font(.system(size: 17)).foregroundStyle(Studio.blueInk)
                                .frame(width: 40, height: 40).background(Studio.sky, in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name).font(.system(size: 11, weight: .bold)).foregroundStyle(Studio.ink)
                                Text("信号强度 \(device.rssi) dBm").font(.system(size: 9, weight: .medium)).foregroundStyle(Studio.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Studio.muted)
                        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Studio.line, lineWidth: 1))
                    }.buttonStyle(.plain).disabled(bluetooth.connectedName != nil)
                }
            }
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 15) {
            heading("SYSTEM INFO", "运行诊断", "连接链路、设备回报与协议数据。")
            Card {
                VStack(alignment: .leading, spacing: 11) {
                    section("蓝牙状态", note: "BLUETOOTH")
                    diagnosticRow("连接", bluetooth.stateText)
                    Divider().overlay(Studio.line)
                    diagnosticRow("服务", bluetooth.detailText)
                    Divider().overlay(Studio.line)
                    diagnosticRow("控制任务", bluetooth.isBusy ? "正在处理" : "空闲")
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    section("最近指令", note: "COMMAND FEEDBACK")
                    Text(bluetooth.lastCommandText).font(.system(size: 11, weight: .semibold)).foregroundStyle(Studio.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 11) {
                    section("原始状态帧", note: "RAW TELEMETRY")
                    if let s = bluetooth.status {
                        Text(s.raw.map { String(format: "%02X", $0) }.joined(separator: " "))
                            .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(Studio.violetInk).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                        Divider().overlay(Studio.line)
                        diagnosticRow("数据长度", "\(s.raw.count) bytes")
                        diagnosticRow("模式", "\(s.modeRaw)")
                        diagnosticRow("风扇设定", "\(s.windLevel) RPM")
                        diagnosticRow("实际转速", "\(s.fanRPM) RPM")
                        diagnosticRow("制冷原始值", "\(s.coldLevel)")
                    } else {
                        Text("连接设备后，这里会显示原始数据帧。").font(.system(size: 10, weight: .medium)).foregroundStyle(Studio.muted)
                    }
                    Button { bluetooth.refreshStatus() } label: { actionPill("重新读取状态", icon: "arrow.clockwise") }
                        .disabled(bluetooth.connectedName == nil || bluetooth.isBusy)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    section("控制范围", note: "SAFE LIMITS")
                    diagnosticRow("风扇设定", "4,000–6,000 RPM")
                    diagnosticRow("制冷原始档位", "92–255")
                    Text("风扇控制上限固定为 6,000 RPM。制冷值是当前单字节协议原始值，不代表瓦数或温度；未经验证的扩展档位不会发送。")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(Studio.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "cable.connector").font(.system(size: 23)).foregroundStyle(Studio.blueInk)
                    .frame(width: 48, height: 48).background(Studio.sky, in: RoundedRectangle(cornerRadius: 14))
                Text("先连接你的 B8X").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Studio.ink)
                Text("连接成功后，这里会显示实时温度、转速和制冷数据。")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(Studio.muted).fixedSize(horizontal: false, vertical: true)
                Button { tab = .devices } label: {
                    HStack { Text("前往连接设备"); Spacer(); Image(systemName: "arrow.right") }
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white).padding(13)
                        .background(Studio.blueInk, in: RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(.plain)
            }
        }
    }

    private func heading(_ eyebrow: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow).font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(1.7).foregroundStyle(Studio.blueInk)
            Text(title).font(.system(size: 27, weight: .heavy, design: .rounded)).tracking(-0.6).foregroundStyle(Studio.ink)
            Text(subtitle).font(.system(size: 10, weight: .medium)).foregroundStyle(Studio.muted)
        }.padding(.bottom, 2)
    }

    private func section(_ title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(Studio.ink)
            Text(note).font(.system(size: 7, weight: .heavy, design: .rounded)).tracking(1.3).foregroundStyle(Studio.muted)
        }
    }

    private func statusChip(_ title: String, icon: String, wash: Color, ink: Color) -> some View {
        Label(title, systemImage: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(ink)
            .frame(maxWidth: .infinity).padding(.vertical, 9).background(wash, in: Capsule())
    }

    private func temperatureCard(_ title: String, value: String, unit: String, icon: String, wash: Color, ink: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                Label(title, systemImage: icon).font(.system(size: 9, weight: .semibold)).foregroundStyle(ink)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 28, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Studio.ink).lineLimit(1).minimumScaleFactor(0.7)
                    Text(unit).font(.system(size: 9, weight: .bold)).foregroundStyle(Studio.muted)
                }
                Capsule().fill(wash).frame(height: 5)
            }
        }
    }

    private func metricCard(_ title: String, value: String, unit: String, icon: String, wash: Color, ink: Color) -> some View {
        Card {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(ink)
                    .frame(width: 33, height: 33).background(wash, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(Studio.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value).font(.system(size: 16, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Studio.ink).lineLimit(1).minimumScaleFactor(0.65)
                        Text(unit).font(.system(size: 7, weight: .heavy)).foregroundStyle(Studio.muted)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func modeButton(_ title: String, detail: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(selected ? Studio.violetInk : Studio.muted)
                Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(Studio.ink)
                Text(detail).font(.system(size: 8, weight: .medium)).foregroundStyle(Studio.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(11)
                .background(selected ? Studio.lilac : Studio.neutral, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Studio.violet.opacity(0.45) : Studio.line, lineWidth: 1))
        }.buttonStyle(.plain).disabled(bluetooth.isBusy)
    }

    private func actionPill(_ title: String, icon: String = "checkmark") -> some View {
        Label(title, systemImage: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 9).background(Studio.ink, in: Capsule())
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(Studio.muted)
            Spacer(minLength: 10)
            Text(value).font(.system(size: 9, weight: .semibold)).foregroundStyle(Studio.ink).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum AppTab: CaseIterable {
    case overview, controls, devices, diagnostics
    var title: String {
        switch self {
        case .overview: return "总览"
        case .controls: return "控制"
        case .devices: return "设备"
        case .diagnostics: return "诊断"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .controls: return "slider.horizontal.3"
        case .devices: return "dot.radiowaves.left.and.right"
        case .diagnostics: return "waveform.path.ecg"
        }
    }
    var selectedIcon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .controls: return "slider.horizontal.3"
        case .devices: return "dot.radiowaves.left.and.right"
        case .diagnostics: return "waveform.path.ecg"
        }
    }
    var tint: Color {
        switch self {
        case .overview: return Studio.sky
        case .controls: return Studio.lilac
        case .devices: return Studio.mint
        case .diagnostics: return Studio.peach
        }
    }
}

private struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(15)
            .background(.white, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(Studio.line, lineWidth: 1))
            .shadow(color: Studio.shadow, radius: 12, x: 0, y: 5)
    }
}

private struct SpeedDial: View {
    let actual: Int
    let target: Int
    private var progress: CGFloat { CGFloat(min(max(Double(actual) / 6000.0, 0), 1)) }
    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: 280 / 360).stroke(Studio.track, style: StrokeStyle(lineWidth: 12, lineCap: .round)).rotationEffect(.degrees(130))
            Circle().trim(from: 0, to: 280 / 360 * progress)
                .stroke(AngularGradient(colors: [Studio.blue, Studio.violet, Studio.pink, Studio.blue], center: .center), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(130)).shadow(color: Studio.blue.opacity(0.25), radius: 6)
            VStack(spacing: 4) {
                Text("ACTUAL SPEED").font(.system(size: 8, weight: .heavy, design: .rounded)).tracking(1.4).foregroundStyle(Studio.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(actual > 0 ? actual.formatted() : "—").font(.system(size: 38, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Studio.ink)
                    Text("RPM").font(.system(size: 9, weight: .heavy)).foregroundStyle(Studio.blueInk)
                }
                Text("目标 \(target.formatted()) RPM").font(.system(size: 10, weight: .semibold)).foregroundStyle(Studio.muted).padding(.top, 2)
                Text("设定上限 6,000 RPM").font(.system(size: 8, weight: .medium)).foregroundStyle(Studio.muted)
            }
        }.frame(width: 210, height: 210)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("实际转速 \(actual) RPM，目标 \(target) RPM，设定上限 6000 RPM")
    }
}

private enum Studio {
    static let canvas = Color(red: 0.965, green: 0.965, blue: 0.949)
    static let ink = Color(red: 0.19, green: 0.23, blue: 0.31)
    static let muted = Color(red: 0.51, green: 0.55, blue: 0.62)
    static let line = Color(red: 0.90, green: 0.91, blue: 0.92)
    static let track = Color(red: 0.90, green: 0.91, blue: 0.94)
    static let shadow = Color(red: 0.24, green: 0.30, blue: 0.43).opacity(0.07)
    static let stone = Color(red: 0.68, green: 0.70, blue: 0.73)
    static let neutral = Color(red: 0.96, green: 0.96, blue: 0.95)
    static let sky = Color(red: 0.86, green: 0.94, blue: 0.99)
    static let blue = Color(red: 0.47, green: 0.74, blue: 0.88)
    static let blueInk = Color(red: 0.25, green: 0.53, blue: 0.69)
    static let lilac = Color(red: 0.93, green: 0.90, blue: 0.98)
    static let violet = Color(red: 0.70, green: 0.61, blue: 0.86)
    static let violetInk = Color(red: 0.48, green: 0.39, blue: 0.66)
    static let mint = Color(red: 0.87, green: 0.95, blue: 0.89)
    static let green = Color(red: 0.52, green: 0.75, blue: 0.61)
    static let greenInk = Color(red: 0.28, green: 0.55, blue: 0.40)
    static let peach = Color(red: 0.99, green: 0.91, blue: 0.86)
    static let coral = Color(red: 0.88, green: 0.57, blue: 0.54)
    static let pink = Color(red: 0.92, green: 0.67, blue: 0.77)
    static let butter = Color(red: 0.99, green: 0.95, blue: 0.82)
    static let goldInk = Color(red: 0.66, green: 0.52, blue: 0.22)
}
