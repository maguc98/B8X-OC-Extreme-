import SwiftUI
import GameController

private struct ControllerSnapshot: Identifiable {
    let id: String
    let name: String
    let profile: String
    let leftX: Float
    let leftY: Float
    let rightX: Float
    let rightY: Float
    let buttons: [String: Float]
}

private final class ControllerMonitor: ObservableObject {
    @Published private(set) var snapshots: [ControllerSnapshot] = []
    private var observers: [NSObjectProtocol] = []
    private var observed = Set<String>()
    init() {
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        refresh()
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    func refresh() {
        let connected = GCController.controllers()
        for controller in connected { installHandler(controller) }
        snapshots = connected.map(makeSnapshot)
    }
    private func installHandler(_ controller: GCController) {
        let id = String(describing: ObjectIdentifier(controller))
        guard observed.insert(id).inserted else { return }
        if let pad = controller.extendedGamepad {
            pad.valueChangedHandler = { [weak self] _, _ in DispatchQueue.main.async { self?.refresh() } }
        } else if let pad = controller.gamepad {
            pad.valueChangedHandler = { [weak self] _, _ in DispatchQueue.main.async { self?.refresh() } }
        }
    }
    private func makeSnapshot(_ controller: GCController) -> ControllerSnapshot {
        let id = String(describing: ObjectIdentifier(controller))
        if let pad = controller.extendedGamepad {
            return ControllerSnapshot(id: id, name: controller.vendorName ?? "兼容手柄", profile: "扩展手柄",
                leftX: pad.leftThumbstick.xAxis.value, leftY: pad.leftThumbstick.yAxis.value,
                rightX: pad.rightThumbstick.xAxis.value, rightY: pad.rightThumbstick.yAxis.value,
                buttons: ["A": pad.buttonA.value, "B": pad.buttonB.value, "X": pad.buttonX.value, "Y": pad.buttonY.value,
                    "LB": pad.leftShoulder.value, "RB": pad.rightShoulder.value, "LT": pad.leftTrigger.value, "RT": pad.rightTrigger.value,
                    "↑": pad.dpad.up.value, "↓": pad.dpad.down.value, "←": pad.dpad.left.value, "→": pad.dpad.right.value])
        }
        if let pad = controller.gamepad {
            return ControllerSnapshot(id: id, name: controller.vendorName ?? "兼容手柄", profile: "标准手柄",
                leftX: pad.dpad.xAxis.value, leftY: pad.dpad.yAxis.value, rightX: 0, rightY: 0,
                buttons: ["A": pad.buttonA.value, "B": pad.buttonB.value, "X": pad.buttonX.value, "Y": pad.buttonY.value,
                    "LB": pad.leftShoulder.value, "RB": pad.rightShoulder.value, "↑": pad.dpad.up.value, "↓": pad.dpad.down.value,
                    "←": pad.dpad.left.value, "→": pad.dpad.right.value])
        }
        return ControllerSnapshot(id: id, name: controller.vendorName ?? "未知控制器", profile: "其他控制器", leftX: 0, leftY: 0, rightX: 0, rightY: 0, buttons: [:])
    }
}

struct FlydigiCenterView: View {
    let bluetooth: B8XBluetoothManager
    @StateObject private var controllers = ControllerMonitor()
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 4) {
                Text("FLYDIGI GAME CENTER").font(.system(size: 8, weight: .heavy)).tracking(1.5).foregroundStyle(.secondary)
                Text("飞智功能中心").font(.system(size: 25, weight: .heavy, design: .rounded))
                Text("B8X 设备、手柄检测与官方资源集中管理。").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            card {
                title("B8X 外设管理", "COOLER DEVICE")
                HStack {
                    Image(systemName: "fanblades.fill").font(.system(size: 19)).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bluetooth.connectedName ?? "飞智 B8X").font(.system(size: 12, weight: .bold))
                        Text(bluetooth.connectedName == nil ? "尚未连接 · 请到设备页搜索" : bluetooth.stateText).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(bluetooth.connectedName == nil ? "离线" : "在线").font(.system(size: 9, weight: .bold)).foregroundStyle(bluetooth.connectedName == nil ? Color.secondary : Color.green)
                }
                Text("已接入自动识别、重连、状态读取、自动/手动模式、风扇、制冷、灯光与诊断。").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            card {
                HStack { title("手柄连接与测试", "GAME CONTROLLER"); Spacer()
                    Button { controllers.refresh() } label: { Image(systemName: "arrow.clockwise").padding(8).background(Color.blue.opacity(0.1), in: Circle()) }.buttonStyle(.plain)
                }
                if controllers.snapshots.isEmpty {
                    Text("暂未发现兼容手柄。先在 iPhone「设置 → 蓝牙」连接支持 iOS Game Controller 的手柄，再回来刷新。B8X 散热器本身不是游戏手柄。")
                        .font(.system(size: 9)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(controllers.snapshots) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(item.name).font(.system(size: 11, weight: .bold)); Spacer(); Text(item.profile).font(.system(size: 8, weight: .bold)).foregroundStyle(.green) }
                            HStack(spacing: 5) { axis("左 X", item.leftX); axis("左 Y", item.leftY); axis("右 X", item.rightX); axis("右 Y", item.rightY) }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 38), spacing: 5)], spacing: 5) {
                                ForEach(item.buttons.keys.sorted(), id: \.self) { key in
                                    let value = item.buttons[key] ?? 0
                                    Text(key).font(.system(size: 9, weight: .bold)).foregroundStyle(value > 0.2 ? Color.green : Color.secondary)
                                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                                        .background(value > 0.2 ? Color.green.opacity(0.12) : Color.gray.opacity(0.08), in: Capsule())
                                }
                            }
                        }
                    }
                }
                Text("此处使用 Apple Game Controller 接口读取本 App 收到的手柄输入，不会向其他游戏注入触控事件。").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            card {
                title("官方游戏与攻略", "GAMES & GUIDES")
                HStack { Label("飞智游戏厅", systemImage: "app.fill").font(.system(size: 11, weight: .bold)); Spacer(); Link("App Store", destination: URL(string: "https://apps.apple.com/cn/app/id1454210823")!).font(.system(size: 10, weight: .bold)) }
                Divider()
                HStack { Label("飞智帮助中心", systemImage: "book.closed.fill").font(.system(size: 11, weight: .bold)); Spacer(); Link("打开", destination: URL(string: "https://help.flydigi.com/")!).font(.system(size: 10, weight: .bold)) }
            }
            card {
                title("功能接入状态", "FEATURE STATUS")
                status("B8X 设备管理与控制", "已接入", true)
                status("兼容手柄发现与测试", "已接入本机检测", true)
                status("官方按键云映射与推荐配置", "需要官方云端接口及对应手柄协议", false)
                status("跨游戏触控映射与悬浮窗", "受 iOS 应用沙盒和系统权限限制", false)
                status("云端同步与社区发布", "需要官方授权接口或独立后端", false)
                Text("未接通的服务不会伪装成可用功能；取得接口与硬件协议后可继续扩展。") .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11, content: content).padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.gray.opacity(0.12), lineWidth: 1))
    }
    private func title(_ text: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(text).font(.system(size: 12, weight: .bold)); Text(note).font(.system(size: 7, weight: .heavy)).tracking(1.2).foregroundStyle(.secondary) }
    }
    private func axis(_ name: String, _ value: Float) -> some View {
        VStack(spacing: 3) { Text(name).font(.system(size: 7)).foregroundStyle(.secondary); Text(String(format: "%.2f", value)).font(.system(size: 9, weight: .bold, design: .monospaced)) }
            .frame(maxWidth: .infinity).padding(.vertical, 7).background(Color.gray.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }
    private func status(_ name: String, _ detail: String, _ available: Bool) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: available ? "checkmark.circle.fill" : "info.circle").foregroundStyle(available ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) { Text(name).font(.system(size: 10, weight: .semibold)); Text(detail).font(.system(size: 8)).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
    }
}