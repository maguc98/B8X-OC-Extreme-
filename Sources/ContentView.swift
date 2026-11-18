import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var bluetooth = B8XBluetoothManager()
    @State private var tab: AppTab = .overview
    @State private var fanTarget = 4200.0
    @State private var coldTarget = 110.0
    @State private var fanDirty = false
    @State private var coldDirty = false
    @State private var isAdjustingFan = false
    @State private var isAdjustingCold = false
    @State private var lastSliderHapticTime = 0.0
    @State private var logsCopied = false
    @AppStorage("B8X.lowTemperatureProtectionEnabled") private var lowTemperatureProtectionEnabled = true
    @AppStorage("B8X.highTemperatureProtectionEnabled") private var highTemperatureProtectionEnabled = true

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
                        case .lighting: LightStudioView(bluetooth: bluetooth)
                        }
                    }
                    .id(tab)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
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
        .onAppear { bluetooth.configureThermalProtection(lowEnabled: lowTemperatureProtectionEnabled, highEnabled: highTemperatureProtectionEnabled) }
        .onChange(of: fanTarget) { _ in if isAdjustingFan { emitSliderHaptic() } }
        .onChange(of: coldTarget) { _ in if isAdjustingCold { emitSliderHaptic() } }
        .onChange(of: lowTemperatureProtectionEnabled) { _ in bluetooth.configureThermalProtection(lowEnabled: lowTemperatureProtectionEnabled, highEnabled: highTemperatureProtectionEnabled) }
        .onChange(of: highTemperatureProtectionEnabled) { _ in bluetooth.configureThermalProtection(lowEnabled: lowTemperatureProtectionEnabled, highEnabled: highTemperatureProtectionEnabled) }
        .onChange(of: bluetooth.status) { value in
            guard let value else { fanDirty = false; coldDirty = false; return }
            if !fanDirty { fanTarget = min(max(Double(value.windLevel), 1), 6000) }
            if !coldDirty { coldTarget = (1...255).contains(value.coldLevel) ? Double(value.coldLevel) : 1 }
        }
        .onChange(of: bluetooth.lastCommandText) { message in
            guard message == "设备已回报确认，控制成功", let value = bluetooth.status else { return }
            fanTarget = min(max(Double(value.windLevel), 1), 6000)
            coldTarget = min(max(Double(value.coldLevel), 1), 255)
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
                    VStack(alignment: .leading, spacing: 13) {
                        section("温度安全保护", note: "THERMAL SAFETY")
                        HStack(spacing: 10) {
                            Image(systemName: "snowflake").foregroundStyle(Studio.blueInk)
                                .frame(width: 36, height: 36).background(Studio.sky, in: RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("低温保护").font(.system(size: 11, weight: .bold)).foregroundStyle(Studio.ink)
                                Text("自动模式生效；手动模式不会覆盖你设定的制冷档位").font(.system(size: 9, weight: .medium)).foregroundStyle(Studio.muted)
                            }
                            Spacer()
                            Toggle("低温保护", isOn: $lowTemperatureProtectionEnabled).labelsHidden().tint(Studio.blue)
                        }
                        Divider().overlay(Studio.line)
                        HStack(spacing: 10) {
                            Image(systemName: "thermometer.high").foregroundStyle(Studio.coral)
                                .frame(width: 36, height: 36).background(Studio.peach, in: RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("高温保护").font(.system(size: 11, weight: .bold)).foregroundStyle(Studio.ink)
                                Text("热端 ≥ 45°C：自动将风扇提升至 6000 RPM").font(.system(size: 9, weight: .medium)).foregroundStyle(Studio.muted)
                            }
                            Spacer()
                            Toggle("高温保护", isOn: $highTemperatureProtectionEnabled).labelsHidden().tint(Studio.coral)
                        }
                        Text(bluetooth.thermalProtectionText + " · 恢复阈值：低温 > 7°C / 高温 < 42°C")
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(Studio.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            section("智能档位", note: "SMART MODE")
                            Spacer()
                            Text(s.modeRaw == 0 ? "AUTO" : "MANUAL")
                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                                .tracking(1).foregroundStyle(Studio.violetInk)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Studio.lilac, in: Capsule())
                        }
                        HStack(spacing: 8) {
                            modeButton("智能自动", detail: "由设备动态调节风扇", icon: "sparkles", selected: s.modeRaw == 0) { bluetooth.setMode(0) }
                            modeButton("手动控制", detail: "按下方目标运行", icon: "slider.horizontal.3", selected: s.modeRaw == 1) { bluetooth.setMode(1) }
                        }
                        Text(s.modeRaw == 0 ? "当前由 B8X 自动管理风扇转速；写入自定义转速时会切换为手动模式。" : "当前为手动模式；统一写入会同时应用风扇转速和制冷档位。")
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(Studio.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack(alignment: .center) {
                            HStack(spacing: 9) {
                                Image(systemName: "fanblades.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Studio.blueInk)
                                    .frame(width: 38, height: 38)
                                    .background(Studio.sky, in: RoundedRectangle(cornerRadius: 12))
                                section("风扇转速", note: "FAN SPEED")
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(Int(fanTarget.rounded()).formatted()).font(.system(size: 27, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Studio.blueInk)
                                Text("RPM · 目标").font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(Studio.muted)
                            }
                        }
                        HStack(spacing: 8) {
                            miniMetric("设备回报", value: s.windLevel.formatted(), unit: "RPM", tint: Studio.ink)
                            miniMetric("实际转速", value: s.fanRPM.formatted(), unit: "RPM", tint: Studio.blueInk)
                        }
                        Slider(value: $fanTarget, in: 1...6000) { editing in
                            isAdjustingFan = editing
                            if editing { fanDirty = true; emitSliderHaptic() }
                        }.tint(Studio.blue)
                        HStack {
                            Text("1 RPM"); Spacer(); Text("连续调节 · 1 RPM 精度"); Spacer(); Text("6,000 RPM")
                        }.font(.system(size: 9, weight: .semibold)).foregroundStyle(Studio.muted)
                        if s.windLevel > 6000 {
                            Text("设备当前回报 \(s.windLevel) RPM，高于设定上限；写入时会调整到所选目标。")
                                .font(.system(size: 9, weight: .medium)).foregroundStyle(Studio.goldInk)
                                .padding(9).frame(maxWidth: .infinity, alignment: .leading).background(Studio.butter, in: RoundedRectangle(cornerRadius: 11))
                        }
                        Text("控制范围为 1–6,000 RPM，按 1 RPM 精度调节。参考项目验证范围为 4,000–4,500 RPM；其余区间请以实机表现为准。")
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(Studio.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                section("制冷档位", note: "COOLING LEVEL")
                                HStack(spacing: 5) {
                                    Circle().fill(Studio.green).frame(width: 6, height: 6)
                                    Text("设备实时回报：\(s.coldLevel)")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(Studio.greenInk)
                                    Text("· 随蓝牙状态帧更新")
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundStyle(Studio.muted)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(Int(coldTarget.rounded()))").font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Studio.greenInk)
                                Text("设定目标").font(.system(size: 8, weight: .bold)).foregroundStyle(Studio.muted)
                            }
                        }
                        Slider(value: $coldTarget, in: 1...255) { editing in
                            isAdjustingCold = editing
                            if editing { coldDirty = true; emitSliderHaptic() }
                        }.tint(Studio.green)
                        HStack {
                            Text("1"); Spacer(); Text("连续调节 · 1 档精度"); Spacer(); Text("255")
                        }.font(.system(size: 9, weight: .semibold)).foregroundStyle(Studio.muted)
                        Text("范围 1–255，按 1 档精度调节；原始档位值不代表瓦数或温度。")
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(Studio.muted)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            section("统一写入", note: "APPLY SETTINGS")
                            Spacer()
                            Label(bluetooth.isBusy ? "正在发送" : "一次应用", systemImage: bluetooth.isBusy ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(bluetooth.isBusy ? Studio.goldInk : Studio.greenInk)
                        }
                        HStack(spacing: 8) {
                            applySummary(icon: "fanblades.fill", title: "风扇目标", value: "\(Int(fanTarget.rounded()).formatted())", unit: "RPM", wash: Studio.sky, ink: Studio.blueInk)
                            applySummary(icon: "snowflake", title: "制冷目标", value: "\(Int(coldTarget.rounded()))", unit: "档", wash: Studio.mint, ink: Studio.greenInk)
                        }
                        Button {
                            bluetooth.applySettings(wind: Int(fanTarget.rounded()), cold: Int(coldTarget.rounded()))
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: bluetooth.isBusy ? "hourglass" : "arrow.down.to.line")
                                Text(bluetooth.isBusy ? "正在等待设备确认…" : "写入设备")
                                Spacer()
                                Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 15)
                            .frame(maxWidth: .infinity)
                            .background(bluetooth.isBusy ? Studio.muted : Studio.blueInk, in: RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(.plain)
                        .disabled(bluetooth.isBusy)
                        Text("将两个目标一起写入，并切换到手动模式；界面会以设备回报作为最终状态。")
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(Studio.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if s.coldLevel < 1 || s.coldLevel > 255 {
                            Text("设备当前制冷原始值 \(s.coldLevel) 超出 1–255；本次写入将替换为上方目标档位。")
                                .font(.system(size: 9, weight: .medium)).foregroundStyle(Studio.goldInk)
                                .fixedSize(horizontal: false, vertical: true)
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
                    HStack {
                        section("原始状态帧", note: "RAW TELEMETRY")
                        Spacer()
                        Button {
                            copyDiagnosticLogs()
                        } label: {
                            Label(logsCopied ? "已复制" : "一键复制日志",
                                  systemImage: logsCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(logsCopied ? Studio.greenInk : Studio.blueInk)
                        }
                        ShareLink(item: bluetooth.captureExportText) {
                            Label("导出抓包", systemImage: "square.and.arrow.up")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Studio.blueInk)
                        }
                        .disabled(bluetooth.rawFrameHistory.isEmpty && bluetooth.physicalActionMarkers.isEmpty)
                    }
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
                        diagnosticRow(
                            "灯效编号（候选）",
                            String(format: "0x%02X · %@", s.raw[15],
                                   s.candidateLightingEffectName ?? "未匹配")
                        )
                        Text("byte[15] 与已公开的飞智灯效编号相符，目前仅作只读观察，尚未验证按键对应关系。")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Studio.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("连接设备后，这里会显示原始数据帧。").font(.system(size: 10, weight: .medium)).foregroundStyle(Studio.muted)
                    }
                    HStack {
                        Text("最近 \(bluetooth.rawFrameHistory.count) 条状态通知（最多保留 64 条）")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Studio.muted)
                        Spacer()
                        Button { bluetooth.clearRawFrameHistory() } label: {
                            Text("清空样本")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Studio.muted)
                        }
                        .disabled(bluetooth.rawFrameHistory.isEmpty)
                        Button { bluetooth.markPhysicalDoublePress() } label: { actionPill("标记并自动抓取", icon: "hand.tap") }
                            .disabled(bluetooth.connectedName == nil || bluetooth.isCapturingLightingAction)
                        Button { bluetooth.refreshStatus() } label: { actionPill("读取最新状态", icon: "arrow.clockwise") }
                            .disabled(bluetooth.connectedName == nil || bluetooth.isBusy)
                    }
                    Text(bluetooth.lightingCaptureText)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(bluetooth.isCapturingLightingAction ? Studio.coral : Studio.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button { bluetooth.probeLightingProtocol() } label: {
                            actionPill("只读查询当前灯效（51 + 编号）", icon: "magnifyingglass")
                        }
                        .disabled(bluetooth.connectedName == nil || bluetooth.isBusy)
                        Spacer(minLength: 0)
                    }
                    Text(bluetooth.lightingProtocolProbeText)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Studio.goldInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if let probeFrame = bluetooth.lightingProtocolProbeRawFrame {
                        Text("候选回包：\(probeFrame)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Studio.violetInk)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !bluetooth.physicalActionMarkers.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("实体按键动作标记（点击标记按钮后立即双击）")
                                .font(.system(size: 8, weight: .bold)).foregroundStyle(Studio.muted)
                            ForEach(bluetooth.physicalActionMarkers.prefix(5), id: \.self) { marker in
                                Text(marker).font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Studio.coral).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("与上一帧的字节差异（索引从 0 开始）")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Studio.muted)
                        Text(bluetooth.statusFrameDeltaSummary)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Studio.violetInk)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if bluetooth.rawFrameHistory.isEmpty {
                        Text("暂无历史帧。读取状态或切换散热器实体灯效后，可再次读取并导出前后数据。")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Studio.muted)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(bluetooth.rawFrameHistory.prefix(8).enumerated()), id: \.offset) { _, frame in
                                Text(frame)
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Studio.violetInk)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(10)
                        .background(Studio.neutral, in: RoundedRectangle(cornerRadius: 11))
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    section("设备服务与固件信息", note: "GATT / DEVICE INFORMATION")
                    diagnosticRow("型号", bluetooth.modelNumber ?? "设备未公开")
                    diagnosticRow("制造商", bluetooth.manufacturerName ?? "设备未公开")
                    diagnosticRow("固件版本", bluetooth.firmwareRevision ?? "设备未公开")
                    Divider().overlay(Studio.line)
                    Text(bluetooth.gattInventory)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Studio.muted)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("仅枚举服务并读取标准设备信息特征值；不会向未知服务发送命令。发现升级服务也不代表已经掌握安全刷写流程。")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Studio.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    section("控制范围", note: "APP CONTROL RANGE")
                    diagnosticRow("风扇设定", "1–6,000 RPM · 1 RPM 精度")
                    diagnosticRow("制冷原始档位", "1–255 · 1 档精度")
                    Text("滑块连续调节并提供触觉反馈。范围描述的是应用可编码的目标值，并不代表设备已验证支持所有档位；制冷原始值不代表瓦数或温度。")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(Studio.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func copyDiagnosticLogs() {
        let status = bluetooth.status
        let currentFrame = status?.raw.map { String(format: "%02X", $0) }.joined(separator: " ") ?? "无"
        let deviceName = bluetooth.connectedName ?? "未连接"
        let model = bluetooth.modelNumber ?? "设备未公开"
        let manufacturer = bluetooth.manufacturerName ?? "设备未公开"
        let firmware = bluetooth.firmwareRevision ?? "设备未公开"
        let mode = status.map { String($0.modeRaw) } ?? "无"
        let wind = status.map { String($0.windLevel) } ?? "无"
        let rpm = status.map { String($0.fanRPM) } ?? "无"
        let cold = status.map { String($0.coldLevel) } ?? "无"
        let history = bluetooth.rawFrameHistory.isEmpty ? "无" : bluetooth.rawFrameHistory.joined(separator: "\n")
        let actionMarkers = bluetooth.physicalActionMarkers.isEmpty ? "无" : bluetooth.physicalActionMarkers.reversed().joined(separator: "\n")
        let lines = [
            "B8X OC Extreme 诊断日志",
            "导出时间：\(Date().formatted(date: .numeric, time: .standard))",
            "设备：\(deviceName)",
            "连接状态：\(bluetooth.stateText)",
            "设备详情：\(bluetooth.detailText)",
            "最后指令：\(bluetooth.lastCommandText)",
            "",
            "【设备信息】",
            "型号：\(model)",
            "制造商：\(manufacturer)",
            "固件版本：\(firmware)",
            "",
            "【当前状态】",
            "原始帧：\(currentFrame)",
            "数据长度：\(status?.raw.count ?? 0) bytes",
            "模式：\(mode)",
            "风扇设定：\(wind)",
            "实际转速：\(rpm)",
            "制冷原始值：\(cold)",
            "帧差异：\(bluetooth.statusFrameDeltaSummary)",
            "",
            "【实体按键动作标记】",
            actionMarkers,
            "",
            "【最近状态帧】",
            history,
            "",
            "【GATT 服务与特征值】",
            bluetooth.gattInventory,
            "",
            "【温度保护】",
            bluetooth.thermalProtectionText
        ]
        UIPasteboard.general.string = lines.joined(separator: "\n")
        logsCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            logsCopied = false
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

    private func emitSliderHaptic() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSliderHapticTime >= 0.085 else { return }
        lastSliderHapticTime = now
        let feedback = UISelectionFeedbackGenerator()
        feedback.prepare()
        feedback.selectionChanged()
    }

    private func miniMetric(_ title: String, value: String, unit: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 8, weight: .medium)).foregroundStyle(Studio.muted)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
                    Text(unit).font(.system(size: 7, weight: .bold)).foregroundStyle(Studio.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Studio.neutral, in: RoundedRectangle(cornerRadius: 11))
    }

    private func applySummary(icon: String, title: String, value: String, unit: String, wash: Color, ink: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                .frame(width: 30, height: 30).background(wash, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 8, weight: .medium)).foregroundStyle(Studio.muted)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 15, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Studio.ink)
                    Text(unit).font(.system(size: 8, weight: .bold)).foregroundStyle(Studio.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
        .background(wash.opacity(0.48), in: RoundedRectangle(cornerRadius: 13))
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
    case overview, controls, devices, diagnostics, lighting
    var title: String {
        switch self {
        case .overview: return "总览"
        case .controls: return "控制"
        case .devices: return "设备"
        case .diagnostics: return "诊断"
        case .lighting: return "灯光"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .controls: return "slider.horizontal.3"
        case .devices: return "dot.radiowaves.left.and.right"
        case .diagnostics: return "waveform.path.ecg"
        case .lighting: return "lightbulb"
        }
    }
    var selectedIcon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .controls: return "slider.horizontal.3"
        case .devices: return "dot.radiowaves.left.and.right"
        case .diagnostics: return "waveform.path.ecg"
        case .lighting: return "lightbulb.fill"
        }
    }
    var tint: Color {
        switch self {
        case .overview: return Studio.sky
        case .controls: return Studio.lilac
        case .devices: return Studio.mint
        case .diagnostics: return Studio.peach
        case .lighting: return Studio.butter
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
