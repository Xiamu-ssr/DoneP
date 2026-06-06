import SwiftUI

struct ContentView: View {
    @StateObject private var settings = DonePSettings.shared
    @State private var installed: [String: Bool] = [:]
    @State private var status: String = ""
    @State private var lastTestOK: Bool? = nil
    @State private var showDonate = false

    private let hook = HookManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 标题
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(
                        LinearGradient(colors: [Color(red: 0.09, green: 0.39, blue: 1.0),
                                                Color(red: 0.0, green: 0.75, blue: 1.0)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                Text("DoneP").font(.headline)
                Spacer()
                Text("任务完成 · 震你手表").font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            // ntfy 设置
            VStack(alignment: .leading, spacing: 6) {
                Text("推送地址 (ntfy)").font(.subheadline).bold()
                TextField("服务器, 如 https://ntfy.sh", text: $settings.server)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("topic (你的专属频道名)", text: $settings.topic)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        settings.topic = DonePSettings.makeDefaultTopic()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("重新生成一个随机 topic")
                    Button("测试") { sendTest() }
                        .disabled(!settings.isConfigured)
                }
                Text("首次已自动生成专属 topic, 手机 ntfy 订阅同名即可").font(.caption2).foregroundStyle(.secondary)
                if let ok = lastTestOK {
                    Text(ok ? "✅ 已发送, 看手机/手表" : "❌ 发送失败")
                        .font(.caption).foregroundStyle(ok ? .green : .red)
                }
            }

            Divider()

            // Agent 开关
            VStack(alignment: .leading, spacing: 8) {
                Text("Agent 完成提醒开关").font(.subheadline).bold()
                ForEach(SUPPORTED_AGENTS) { agent in
                    Toggle(isOn: bindingFor(agent)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.name)
                            Text(agent.note).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(!settings.isConfigured)
                }
                if !settings.isConfigured {
                    Text("先填好上面的推送地址, 才能开启开关").font(.caption2).foregroundStyle(.orange)
                }
            }

            if !status.isEmpty {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button {
                    showDonate.toggle()
                } label: {
                    Label("请我喝咖啡", systemImage: "cup.and.saucer.fill")
                }
                .controlSize(.small)
                .popover(isPresented: $showDonate, arrowEdge: .top) {
                    DonateView()
                }
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }

            Text("OpenClaw 无需开关 (内部直接调脚本)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 340)
        .background(
            ZStack {
                // 主体背景
                Color(nsColor: .windowBackgroundColor)
                // 火山引擎蓝渐变光晕 (与图标同主题色)
                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.39, blue: 1.0).opacity(0.18),
                        Color(red: 0.0, green: 0.75, blue: 1.0).opacity(0.06),
                        Color.clear
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                // 右下角青蓝辉光
                RadialGradient(
                    colors: [Color(red: 0.0, green: 0.75, blue: 1.0).opacity(0.12), Color.clear],
                    center: .bottomTrailing, startRadius: 4, endRadius: 260
                )
            }
            .ignoresSafeArea()
        )
        .onAppear { refresh() }
    }

    private func bindingFor(_ agent: AgentDef) -> Binding<Bool> {
        Binding(
            get: { installed[agent.id] ?? false },
            set: { newVal in toggle(agent, on: newVal) }
        )
    }

    private func refresh() {
        for a in SUPPORTED_AGENTS { installed[a.id] = hook.isInstalled(a) }
    }

    private func toggle(_ agent: AgentDef, on: Bool) {
        do {
            // 确保脚本是最新的 (烤入当前地址)
            try hook.writeNotifyScript(server: settings.server, topic: settings.topic)
            if on { try hook.install(agent) } else { try hook.uninstall(agent) }
            installed[agent.id] = on
            status = "\(agent.name) 已\(on ? "开启" : "关闭")"
        } catch {
            status = "操作失败: \(error.localizedDescription)"
            refresh()
        }
    }

    private func sendTest() {
        do {
            try hook.writeNotifyScript(server: settings.server, topic: settings.topic)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [DonePConst.notifyScriptPath, "DoneP 测试", "✅ 链路通了, 这就是完成提醒"]
            try p.run()
            lastTestOK = true
        } catch {
            lastTestOK = false
        }
    }
}
