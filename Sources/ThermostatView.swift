import SwiftUI

struct ThermostatView: View {
    @ObservedObject var bluetooth: B8XBluetoothManager
    @AppStorage("B8X.dualTemperature.coldTarget") private var coldTarget = 15.0
    @AppStorage("B8X.dualTemperature.hotTarget") private var hotTarget = 40.0

    private var connected: Bool {
        bluetooth.connectedName != nil && bluetooth.status != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            header
            temperatureTargetsCard
            liveStatusCard
            controlCard
            safetyNote
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("DUAL TEMPERATURE")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(ThermostatPalette.blueInk)
            Text("双温度恒温")
                .font(.system(size: 27, weight: .heavy, design: .rounded))
                .tracking(-0.6)
                .foregroundStyle(ThermostatPalette.ink)
            Text("同时监测冷端与热端，自动协调制冷档位和风扇转速。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ThermostatPalette.muted)
        }
        .padding(.bottom, 1)
    }

    private var temperatureTargetsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("目标温度", note: "TEMPERATURE TARGETS")

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Image(systemName: "snowflake")
                        .foregroundStyle(ThermostatPalette.blueInk)
                        .frame(width: 35, height: 35)
                        .background(ThermostatPalette.sky, in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("冷端目标").font(.system(size: 11, weight: .bold)).foregroundStyle(ThermostatPalette.ink)
                        Text("控制制冷档位").font(.system(size: 8, weight: .medium)).foregroundStyle(ThermostatPalette.muted)
                    }
                    Spacer()
                    Text(String(format: "%.1f°C", coldTarget))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.48, dampingFraction: 0.72), value: coldTarget)
                        .foregroundStyle(ThermostatPalette.blueInk)
                }
                Slider(value: $coldTarget, in: 10...25, step: 0.5)
                    .tint(ThermostatPalette.blueInk)
                    .disabled(bluetooth.isDualTemperatureControlEnabled)
                HStack {
                    Text("10°C")
                    Spacer()
                    Text("25°C")
                }
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(ThermostatPalette.muted)
            }

            Divider().overlay(ThermostatPalette.line)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    Image(systemName: "thermometer.high")
                        .foregroundStyle(ThermostatPalette.coral)
                        .frame(width: 35, height: 35)
                        .background(ThermostatPalette.peach, in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("热端目标").font(.system(size: 11, weight: .bold)).foregroundStyle(ThermostatPalette.ink)
                        Text("控制散热风扇").font(.system(size: 8, weight: .medium)).foregroundStyle(ThermostatPalette.muted)
                    }
                    Spacer()
                    Text(String(format: "%.0f°C", hotTarget))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.48, dampingFraction: 0.72), value: hotTarget)
                        .foregroundStyle(ThermostatPalette.coral)
                }
                Slider(value: $hotTarget, in: 30...42, step: 1)
                    .tint(ThermostatPalette.coral)
                    .disabled(bluetooth.isDualTemperatureControlEnabled)
                HStack {
                    Text("30°C")
                    Spacer()
                    Text("42°C")
                }
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(ThermostatPalette.muted)
            }

            Text("目标范围为冷端 10–25°C、热端 30–42°C。两个目标相互影响，实际温度会在缓冲区内波动，不承诺精确锁定单一数值。")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(ThermostatPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(ThermostatPalette.line, lineWidth: 1)
        }
    }

    private var liveStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("实时温度", note: "LIVE TELEMETRY")
            if let status = bluetooth.status {
                HStack(spacing: 10) {
                    liveMetric(
                        title: "冷端实测",
                        value: String(format: "%.1f", status.coldTemperature),
                        target: String(format: "%.1f°C", coldTarget),
                        icon: "snowflake",
                        tint: ThermostatPalette.blueInk,
                        wash: ThermostatPalette.sky
                    )
                    liveMetric(
                        title: "热端实测",
                        value: "\(status.hotTemperature)",
                        target: String(format: "%.0f°C", hotTarget),
                        icon: "thermometer.high",
                        tint: ThermostatPalette.coral,
                        wash: ThermostatPalette.peach
                    )
                }
                Divider().overlay(ThermostatPalette.line)
                HStack(spacing: 10) {
                    compactMetric("当前风扇设定", value: "\(status.windLevel)", unit: "RPM")
                    compactMetric("实际转速", value: "\(status.fanRPM)", unit: "RPM")
                    compactMetric("制冷档位", value: "\(status.coldLevel)", unit: "LEVEL")
                }
            } else {
                Text("连接 B8X 后显示冷端与热端实时温度。")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ThermostatPalette.muted)
            }
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(ThermostatPalette.line, lineWidth: 1)
        }
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("自动调节", note: "CLOSED-LOOP CONTROL")
                Spacer()
                Text(bluetooth.isDualTemperatureControlEnabled ? "运行中" : "已停止")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(bluetooth.isDualTemperatureControlEnabled ? ThermostatPalette.greenInk : ThermostatPalette.muted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(bluetooth.isDualTemperatureControlEnabled ? ThermostatPalette.mint : ThermostatPalette.neutral, in: Capsule())
            }

            Button {
                if bluetooth.isDualTemperatureControlEnabled {
                    bluetooth.stopDualTemperatureControl()
                } else {
                    bluetooth.startDualTemperatureControl(coldTarget: coldTarget, hotTarget: hotTarget)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: bluetooth.isDualTemperatureControlEnabled ? "pause.fill" : "play.fill")
                    Text(bluetooth.isDualTemperatureControlEnabled ? "停止恒温控制" : "启动双温度恒温")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(
                    bluetooth.isDualTemperatureControlEnabled ? ThermostatPalette.coral : ThermostatPalette.blueInk,
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!bluetooth.isDualTemperatureControlEnabled && (!connected || bluetooth.isBusy))

            Text(bluetooth.dualTemperatureControlText)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ThermostatPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Circle().fill(connected ? ThermostatPalette.green : ThermostatPalette.coral).frame(width: 6, height: 6)
                Text(connected ? "B8X 已连接" : "等待连接 B8X")
                Spacer()
                Text(bluetooth.isBusy ? "设备指令处理中" : "蓝牙空闲")
            }
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(ThermostatPalette.muted)

            Text("启动后 App 会读取温度并小步调整组合参数；停止后保留最后一次风扇和制冷设定，不会自动恢复设备原生 AUTO。")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(ThermostatPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(ThermostatPalette.line, lineWidth: 1)
        }
    }

    private var safetyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ThermostatPalette.goldInk)
            Text("请保持 B8X 蓝牙连接，并让本 App 保持在前台运行。iOS 挂起 App 或蓝牙断开时，自动调节会暂停。冷端过低、热端过高时仍优先执行保护策略；避免低于环境露点运行，以免冷凝。")
                .foregroundStyle(ThermostatPalette.muted)
        }
        .font(.system(size: 8, weight: .medium))
        .padding(.horizontal, 3)
    }

    private func liveMetric(
        title: String,
        value: String,
        target: String,
        icon: String,
        tint: Color,
        wash: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 27, weight: .heavy, design: .rounded)).monospacedDigit().contentTransition(.numericText()).animation(.spring(response: 0.52, dampingFraction: 0.70), value: value)
                Text("°C").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(ThermostatPalette.ink)
            Text("目标 \(target)")
                .font(.system(size: 8, weight: .semibold))
                .contentTransition(.numericText()).animation(.spring(response: 0.48, dampingFraction: 0.72), value: target)
                .foregroundStyle(ThermostatPalette.muted)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(wash.opacity(0.65), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func compactMetric(_ title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 7, weight: .medium)).foregroundStyle(ThermostatPalette.muted)
            Text(value).font(.system(size: 12, weight: .heavy, design: .rounded)).monospacedDigit().contentTransition(.numericText()).animation(.spring(response: 0.48, dampingFraction: 0.72), value: value).foregroundStyle(ThermostatPalette.ink)
            Text(unit).font(.system(size: 7, weight: .bold)).foregroundStyle(ThermostatPalette.blueInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(ThermostatPalette.ink)
            Text(note).font(.system(size: 7, weight: .heavy, design: .rounded)).tracking(1.3).foregroundStyle(ThermostatPalette.muted)
        }
    }
}

private enum ThermostatPalette {
    static let ink = Color(red: 0.19, green: 0.23, blue: 0.31)
    static let muted = Color(red: 0.51, green: 0.55, blue: 0.62)
    static let line = Color(red: 0.90, green: 0.91, blue: 0.92)
    static let neutral = Color(red: 0.96, green: 0.96, blue: 0.95)
    static let sky = Color(red: 0.86, green: 0.94, blue: 0.99)
    static let blueInk = Color(red: 0.25, green: 0.53, blue: 0.69)
    static let peach = Color(red: 0.99, green: 0.91, blue: 0.86)
    static let coral = Color(red: 0.88, green: 0.57, blue: 0.54)
    static let mint = Color(red: 0.87, green: 0.95, blue: 0.89)
    static let green = Color(red: 0.52, green: 0.75, blue: 0.61)
    static let greenInk = Color(red: 0.28, green: 0.55, blue: 0.40)
    static let goldInk = Color(red: 0.66, green: 0.52, blue: 0.22)
}
