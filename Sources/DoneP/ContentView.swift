import SwiftUI

struct ContentView: View {
    @StateObject private var settings = DonePSettings.shared
    @State private var installed: [String: Bool] = [:]
    @State private var status: String = ""
    @State private var lastTestOK: Bool? = nil

    private let hook = HookManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 标题
            HStack {
                Image(systemName: "bell.badge.fill")
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
                    Button("测试") { sendTest() }
                        .disabled(!settings.isConfigured)
                }
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
                Text("OpenClaw 无需开关 (内部直接调脚本)")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 340)
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
