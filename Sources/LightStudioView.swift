import SwiftUI

/// Lighting controls are deliberately split into verified hardware control
/// and local-only preview controls. Only the on/off command is currently
/// known to be valid for the B8X BLE protocol.
struct LightStudioView: View {
    @ObservedObject var bluetooth: B8XBluetoothManager

    @State private var selectedMode = "多色旋转"
    @State private var selectedTheme = "极光"
    @State private var selectedColor = Color.cyan
    @State private var selectedFavoriteIndex: Int? = 0
    @State private var favoriteColors: [Color] = [.cyan, .teal, .green]
    @State private var previewSpeed = 0.52
    @State private var previewBrightness = 0.92
    @State private var isAnimating = false

    private let modes = [
        "变频旋转", "流光", "呼吸", "渐变",
        "切换", "多色旋转", "跳动", "常亮"
    ]

    private var isConnected: Bool {
        bluetooth.connectedName != nil && bluetooth.status != nil
    }

    private var hardwareLightOn: Bool {
        bluetooth.status?.lightEnabled ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading

            previewCard

            powerCard

            effectCard

            themeCard

            colorCard

            previewTuningCard

            firmwareCard

            protocolNote
        }
        .onAppear { isAnimating = true }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("LIGHT STUDIO")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(LightPalette.blueInk)
            Text("灯光工作室")
                .font(.system(size: 27, weight: .heavy, design: .rounded))
                .tracking(-0.6)
                .foregroundStyle(LightPalette.ink)
            Text("打造属于你的 B8X 灯光氛围。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(LightPalette.muted)
        }
        .padding(.bottom, 1)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("灯光预览")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(LightPalette.ink)
                    Text("LIVE STYLE PREVIEW")
                        .font(.system(size: 7, weight: .heavy, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(LightPalette.muted)
                }
                Spacer()
                Text("本地预览")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(LightPalette.violetInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(LightPalette.lilac, in: Capsule())
            }

            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: previewColors,
                            center: .center
                        )
                    )
                    .frame(width: 190, height: 190)
                    .blur(radius: 22)
                    .opacity(0.25 + previewBrightness * 0.55)

                Circle()
                    .fill(
                        AngularGradient(
                            colors: previewColors,
                            center: .center
                        )
                    )
                    .frame(width: 148, height: 148)
                    .overlay {
                        Circle().stroke(.white.opacity(0.72), lineWidth: 4)
                            .padding(9)
                        Circle().stroke(.white.opacity(0.34), lineWidth: 1)
                            .padding(19)
                    }
                    .shadow(color: selectedColor.opacity(0.28), radius: 24, x: 0, y: 8)
                    .rotationEffect(.degrees(isAnimating && isRotatingEffect ? 360 : 0))
                    .animation(
                        .linear(duration: max(3, 12 - previewSpeed * 9))
                            .repeatForever(autoreverses: false),
                        value: isAnimating
                    )

                Image(systemName: "fanblades.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            HStack {
                Label(selectedMode, systemImage: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LightPalette.ink)
                Spacer()
                Text("效果预览，不代表设备已应用")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(LightPalette.muted)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [.white, LightPalette.previewWash],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(LightPalette.line, lineWidth: 1)
        }
    }

    private var powerCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: "lightbulb.2.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LightPalette.goldInk)
                    .frame(width: 40, height: 40)
                    .background(LightPalette.butter, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("设备灯效")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LightPalette.ink)
                    Text(bluetooth.connectedName == nil
                         ? "连接 B8X 后可切换灯光"
                         : (hardwareLightOn ? "设备当前已开启" : "设备当前已关闭"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(LightPalette.muted)
                }
                Spacer()
                Toggle(
                    "设备灯效",
                    isOn: Binding(
                        get: { hardwareLightOn },
                        set: { bluetooth.setLight($0) }
                    )
                )
                .labelsHidden()
                .tint(LightPalette.green)
                .disabled(!isConnected || bluetooth.isBusy)
            }

            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(LightPalette.greenInk)
                Text("开关控制已接入 B8X；状态以设备回报为准。")
                    .foregroundStyle(LightPalette.muted)
                Spacer(minLength: 0)
            }
            .font(.system(size: 8, weight: .medium))

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "waveform.path")
                    .foregroundStyle(LightPalette.blueInk)
                Text("最近控制反馈：\\(bluetooth.lastCommandText)")
                    .foregroundStyle(LightPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 8, weight: .medium))
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(LightPalette.line, lineWidth: 1)
        }
    }

    private var effectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("灯效模式", note: "EFFECT MODES")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(modes, id: \.self) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: modeIcon(mode))
                                .font(.system(size: 11, weight: .semibold))
                            Text(mode)
                                .font(.system(size: 10, weight: .bold))
                            Spacer(minLength: 0)
                            if selectedMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                        }
                        .foregroundStyle(selectedMode == mode ? LightPalette.violetInk : LightPalette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                        .background(
                            selectedMode == mode ? LightPalette.lilac : LightPalette.neutral,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selectedMode == mode ? LightPalette.violet.opacity(0.35) : .clear, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            protocolPendingCaption
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(LightPalette.line, lineWidth: 1)
        }
    }

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("主题皮肤", note: "THEME SKINS")
            HStack(spacing: 9) {
                themeOption(
                    "极光",
                    subtitle: "清透渐彩",
                    colors: [.cyan, .mint, .purple, .pink]
                )
                themeOption(
                    "Pandaer 联名",
                    subtitle: "黑白限定预览",
                    colors: [.black, .white, Color(red: 0.92, green: 0.88, blue: 0.79), .black]
                )
            }
            protocolPendingCaption
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(LightPalette.line, lineWidth: 1)
        }
    }

    private func themeOption(_ title: String, subtitle: String, colors: [Color]) -> some View {
        Button {
            selectedTheme = title
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(maxWidth: .infinity).frame(height: 23)
                    }
                }
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 9, weight: .bold))
                    Spacer(minLength: 0)
                    if selectedTheme == title {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 10))
                    }
                }
                Text(subtitle).font(.system(size: 8, weight: .medium))
            }
            .foregroundStyle(selectedTheme == title ? LightPalette.violetInk : LightPalette.ink)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedTheme == title ? LightPalette.lilac : LightPalette.neutral,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionTitle("颜色搭配", note: "COLOR PALETTE")
                Spacer()
                Text("\(favoriteColors.count) 个收藏")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(LightPalette.muted)
            }

            HStack(spacing: 10) {
                ForEach(Array(favoriteColors.enumerated()), id: \.offset) { index, color in
                    Button {
                        selectedColor = color
                        selectedFavoriteIndex = index
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 34, height: 34)
                            .overlay {
                                Circle().stroke(.white, lineWidth: selectedFavoriteIndex == index ? 3 : 1)
                                    .padding(selectedFavoriteIndex == index ? 2 : 0)
                            }
                            .overlay {
                                Circle().stroke(LightPalette.line, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .onLongPressGesture {
                        guard favoriteColors.count > 1 else { return }
                        favoriteColors.remove(at: index)
                    }
                    .accessibilityLabel("选择颜色，长按移除")
                }

                ColorPicker("自定义颜色", selection: Binding(get: { selectedColor }, set: { selectedColor = $0; selectedFavoriteIndex = nil }), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 35, height: 35)
                    .overlay {
                        Circle().stroke(LightPalette.line, lineWidth: 1)
                    }

                Button {
                    favoriteColors.append(selectedColor)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(LightPalette.ink)
                        .frame(width: 34, height: 34)
                        .background(LightPalette.neutral, in: Circle())
                        .overlay(Circle().stroke(LightPalette.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(favoriteColors.count >= 8)
            }

            HStack {
                Text("长按收藏色块可移除；加号可收藏当前颜色。")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(LightPalette.muted)
                Spacer()
                Button("重置预览") {
                    selectedMode = "多色旋转"
                    selectedTheme = "极光"
                    selectedColor = .cyan
                    selectedFavoriteIndex = 0
                    favoriteColors = [.cyan, .teal, .green]
                    previewSpeed = 0.52
                    previewBrightness = 0.92
                }
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(LightPalette.violetInk)
            }

            protocolPendingCaption
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(LightPalette.line, lineWidth: 1)
        }
    }

    private var previewTuningCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("动态参数", note: "PREVIEW TUNING")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("效果速度", systemImage: "speedometer")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LightPalette.ink)
                    Spacer()
                    Text(speedLabel)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(LightPalette.violetInk)
                }
                Slider(value: $previewSpeed, in: 0...1)
                    .tint(LightPalette.violet)
                HStack {
                    Text("慢速")
                    Spacer()
                    Text("快速")
                }
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(LightPalette.muted)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("灯光亮度", systemImage: "sun.max")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LightPalette.ink)
                    Spacer()
                    Text("\(Int(previewBrightness * 100))%")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(LightPalette.blueInk)
                }
                Slider(value: $previewBrightness, in: 0...1)
                    .tint(LightPalette.blueInk)
                HStack {
                    Text("柔和")
                    Spacer()
                    Text("明亮")
                }
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(LightPalette.muted)
            }

            protocolPendingCaption
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(LightPalette.line, lineWidth: 1)
        }
    }

    private var firmwareCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LightPalette.blueInk)
                    .frame(width: 37, height: 37)
                    .background(LightPalette.sky, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("设备固件")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LightPalette.ink)
                    Text("固件版本读取与升级协议待验证")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(LightPalette.muted)
                }
                Spacer()
                Text("研究中")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(LightPalette.goldInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(LightPalette.butter, in: Capsule())
            }

            Text("目前没有可靠的 B8X 专用固件包、校验规则和恢复流程。此处暂不开放刷写，避免错误固件导致设备无法启动。")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(LightPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {} label: {
                HStack {
                    Text("检查固件更新")
                    Spacer()
                    Image(systemName: "lock.fill")
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(LightPalette.muted)
                .padding(11)
                .frame(maxWidth: .infinity)
                .background(LightPalette.neutral, in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            .disabled(true)
        }
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(LightPalette.line, lineWidth: 1)
        }
    }

    private var protocolNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(LightPalette.blueInk)
            Text("B8X 实体按键双击也可切换灯效。现在只有灯效开关会真正控制设备；模式、主题、颜色、速度和亮度均为本机预览，协议验证完成后才会开放同步。")
                .foregroundStyle(LightPalette.muted)
        }
        .font(.system(size: 8, weight: .medium))
        .padding(.horizontal, 3)
    }

    private var protocolPendingCaption: some View {
        HStack(spacing: 5) {
            Image(systemName: "hourglass")
            Text("硬件控制协议待验证 · 当前仅本地预览")
        }
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(LightPalette.goldInk)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(LightPalette.butter.opacity(0.72), in: Capsule())
    }

    private var previewColors: [Color] {
        if selectedTheme == "Pandaer 联名" {
            return [Color.black, .white, Color(red: 0.92, green: 0.88, blue: 0.79), .black]
        }
        if selectedMode == "常亮" {
            return [selectedColor.opacity(0.5), selectedColor, selectedColor.opacity(0.85)]
        }
        if selectedMode == "呼吸" || selectedMode == "渐变" {
            return [selectedColor.opacity(0.45), selectedColor, .white, selectedColor]
        }
        return [
            selectedColor,
            .cyan,
            .mint,
            .purple,
            .pink,
            .orange,
            selectedColor
        ]
    }

    private var isRotatingEffect: Bool {
        ["变频旋转", "流光", "多色旋转", "切换"].contains(selectedMode)
    }

    private var speedLabel: String {
        previewSpeed < 0.34 ? "慢速" : previewSpeed > 0.67 ? "快速" : "中速"
    }

    private func sectionTitle(_ title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LightPalette.ink)
            Text(note)
                .font(.system(size: 7, weight: .heavy, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(LightPalette.muted)
        }
    }

    private func modeIcon(_ mode: String) -> String {
        switch mode {
        case "变频旋转": return "arrow.triangle.2.circlepath"
        case "流光": return "wind"
        case "呼吸": return "waveform"
        case "渐变": return "circle.lefthalf.filled"
        case "切换": return "shuffle"
        case "多色旋转": return "rainbow"
        case "跳动": return "dot.radiowaves.left.and.right"
        default: return "sun.max.fill"
        }
    }
}

private enum LightPalette {
    static let ink = Color(red: 0.19, green: 0.23, blue: 0.31)
    static let muted = Color(red: 0.51, green: 0.55, blue: 0.62)
    static let line = Color(red: 0.90, green: 0.91, blue: 0.92)
    static let neutral = Color(red: 0.96, green: 0.96, blue: 0.95)
    static let previewWash = Color(red: 0.95, green: 0.94, blue: 0.99)
    static let sky = Color(red: 0.86, green: 0.94, blue: 0.99)
    static let blueInk = Color(red: 0.25, green: 0.53, blue: 0.69)
    static let lilac = Color(red: 0.93, green: 0.90, blue: 0.98)
    static let violet = Color(red: 0.70, green: 0.61, blue: 0.86)
    static let violetInk = Color(red: 0.48, green: 0.39, blue: 0.66)
    static let mint = Color(red: 0.87, green: 0.95, blue: 0.89)
    static let green = Color(red: 0.52, green: 0.75, blue: 0.61)
    static let greenInk = Color(red: 0.28, green: 0.55, blue: 0.40)
    static let butter = Color(red: 0.99, green: 0.95, blue: 0.82)
    static let goldInk = Color(red: 0.66, green: 0.52, blue: 0.22)
}
