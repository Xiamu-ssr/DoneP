import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var settings = DonePSettings.shared
    @State private var installed: [String: Bool] = [:]
    @State private var status: String = ""
    @State private var lastTestOK: Bool? = nil
    @State private var showDonate = false
    @State private var customAgents: [CustomAgent] = []
    @State private var betaPopup: String? = nil
    @State private var skillCopied = false
    @State private var fsWatcher: DispatchSourceFileSystemObject? = nil
    @State private var claudeSettingsWatcher: DispatchSourceFileSystemObject? = nil

    private let hook = HookManager.shared

    /// 内置 + 自定义(注册目录) 合并后的全部 Agent
    private var allAgents: [AgentDef] {
        BUILTIN_AGENTS + customAgents.map {
            AgentDef(id: "custom-\($0.id)", name: $0.name,
                     configPath: "",
                     note: $0.note ?? "自定义 (来自注册目录)", isCustom: true)
        }
    }

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
                ForEach(allAgents) { agent in
                    Toggle(isOn: bindingFor(agent)) {
                        HStack(spacing: 4) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(agent.name)
                                    if agent.beta {
                                        Button {
                                            betaPopup = agent.id
                                        } label: {
                                            HStack(spacing: 2) {
                                                Image(systemName: "exclamationmark.circle.fill")
                                                Text("beta").font(.system(size: 9, weight: .semibold))
                                            }
                                            .foregroundStyle(.orange)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.12))
                                            .clipShape(Capsule())
                                            .shadow(color: .orange.opacity(0.35), radius: 2, y: 1)
                                        }
                                        .buttonStyle(.plain)
                                        .popover(isPresented: Binding(
                                            get: { betaPopup == agent.id },
                                            set: { if !$0 { betaPopup = nil } }
                                        ), arrowEdge: .bottom) {
                                            Text("CodeFuse UI 模式用 --settings 覆盖\nuser/project hooks, 外部 Stop hook 走\n不通。\n• antcc 模式 (走 ~/.claude/settings.json) ✅\n• CodeFuse UI 模式 (走 --settings 注入) ❌\n\nOpenClaw: 开启后自动装插件 +\nallowConversationAccess, 但需\ngateway restart 才生效。")
                                                .font(.caption).padding(10).frame(width: 220)
                                        }
                                    }
                                }
                                Text(agent.note).font(.caption2).foregroundStyle(.secondary)
                                if !agent.isSupported {
                                    Text("已调查: 该 Agent 不支持外部 Stop hook")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(!settings.isConfigured || !agent.isSupported)
                }
                if !settings.isConfigured {
                    Text("先填好上面的推送地址, 才能开启开关").font(.caption2).foregroundStyle(.orange)
                }

                // 接入自定义 Agent: 指向 skill, 让用户的 agent 自己跟着做
                VStack(alignment: .leading, spacing: 4) {
                    Divider().padding(.vertical, 2)
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles").font(.caption2).foregroundStyle(.blue)
                        Text("接入你自己的 Agent").font(.caption).bold()
                    }
                    Text("把下面路径发给你的 AI, 让它读这份 skill 自动接入:")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(DonePRegistry.skillPath)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(DonePRegistry.skillPath, forType: .string)
                            skillCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { skillCopied = false }
                        } label: {
                            Image(systemName: skillCopied ? "checkmark" : "doc.on.doc").font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("复制 skill 路径")
                    }
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

            Text("改了开关后, 请重启对应 Agent 才生效")
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
        .onAppear { reloadAll() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reloadAll()  // 窗口再次激活(点菜单栏)时刷新, 零轮询
        }
    }

    private func bindingFor(_ agent: AgentDef) -> Binding<Bool> {
        Binding(
            get: { installed[agent.id] ?? false },
            set: { newVal in toggle(agent, on: newVal) }
        )
    }

    /// 重新扫描注册目录 + 刷新开关状态
    private func reloadAll() {
        DonePRegistry.ensureDirs()
        customAgents = DonePRegistry.scan()
        startWatchingIfNeeded()
        refresh()
        // 启动 / 重新激活时, 对所有"开着的"内置 agent 重新注入 hook。
        // 原因: CodeFuse 自己的 cleanup 会覆写 hooks.json, 让 DoneP 注入消失;
        // 我们每次激活面板就 idempotent 重注一次, 不依赖用户手动 toggle。
        reinstallEnabledBuiltins()
    }

    private func reinstallEnabledBuiltins() {
        Self.reinstallAllEnabledBuiltins()
    }

    /// 在 app 启动 + 面板重新打开 + 文件被外部改时都调 (kqueue 事件驱动, 不轮询)。
    /// 只重注"用户明确 toggle ON 过"的内置 agent (UserDefaults 记住意图),
    /// 不管文件里现在什么状态 — CodeFuse 自身 cleanup 会随重启 / 切项目
    /// 把我们的 hook 注入抹掉, 这个函数是"防护 + 自愈": 文件被改 → 重注
    /// 用户表达过"要"的 agent。
    static func reinstallAllEnabledBuiltins() {
        let h = HookManager.shared
        try? h.writeNotifyScript(server: DonePSettings.shared.server, topic: DonePSettings.shared.topic)
        let defaults = UserDefaults.standard
        for a in BUILTIN_AGENTS {
            // 不重注 isSupported=false 的 (CodeFuse UI 模式)
            guard a.isSupported else { continue }
            // 遵循用户 toggle 意图: 记过 on 的, 文件被外部改时就重注
            if defaults.bool(forKey: "donep.intent.\(a.id)") {
                try? h.install(a)  // install() 内部 idempotent
            }
        }
    }

    private func refresh() {
        for a in BUILTIN_AGENTS { installed[a.id] = hook.isInstalled(a) }
        // 自定义 agent 的开关状态由注册文件的 enabled 决定(默认开)
        for c in customAgents { installed["custom-\(c.id)"] = c.enabled ?? true }
        // "采纳"现状: 如果文件里已装, 就当作用户意图 (避免首次启动需手 toggle)
        // 不采纳 isSupported=false 的 (CodeFuse UI 模式不该被自愈, 但它本身也不会被装)
        let defaults = UserDefaults.standard
        for a in BUILTIN_AGENTS where a.isSupported {
            let key = "donep.intent.\(a.id)"
            if !defaults.bool(forKey: key) && hook.isInstalled(a) {
                defaults.set(true, forKey: key)
            }
        }
    }

    // MARK: - 目录监听 (零轮询, agent 写入注册文件立即刷新)
    private func startWatchingIfNeeded() {
        guard fsWatcher == nil else { return }
        let dir = DonePRegistry.agentsDir
        let fd = open(dir, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .attrib], queue: .main)
        src.setEventHandler {
            customAgents = DonePRegistry.scan()
            refresh()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        fsWatcher = src

        // 监 CodeFuse / antcc 实际生效的 hooks 文件 (~/.claude/settings.json)。
        // CodeFuse 启动 session / 切项目 / antcc 都会改这个文件。文件一变就重注,
        // 不轮询, 不耗资源 (kqueue 事件驱动)。
        startClaudeSettingsWatcherIfNeeded()
    }

    /// 监听 ~/.claude/settings.json: CodeFuse (antcc)、Claude CLI、任何 Claude
    /// 内核的客户端启动/切项目时都会改这个文件。文件被外部改了就重注所有内置 agent。
    private func startClaudeSettingsWatcherIfNeeded() {
        guard claudeSettingsWatcher == nil else { return }
        let path = ("~/.claude/settings.json" as NSString).expandingTildeInPath
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .attrib], queue: .main)
        src.setEventHandler { Self.reinstallAllEnabledBuiltins() }
        src.setCancelHandler { close(fd) }
        src.resume()
        claudeSettingsWatcher = src
    }

    /// 关闭自定义 agent: 改注册文件 enabled=false, 并执行其 uninstall 命令
    private func setCustomEnabled(_ agent: AgentDef, on: Bool) {
        let cid = agent.id.replacingOccurrences(of: "custom-", with: "")
        let fp = (DonePRegistry.agentsDir as NSString).appendingPathComponent("\(cid).json")
        guard let data = FileManager.default.contents(atPath: fp),
              var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }
        obj["enabled"] = on
        if let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes]) {
            try? out.write(to: URL(fileURLWithPath: fp))
        }
        // 关闭时代执行注册方提供的 uninstall 命令(如果有)
        if !on, let cmd = (obj["uninstall"] as? String), !cmd.isEmpty {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = ["-lc", cmd]
            try? p.run()
        }
        installed[agent.id] = on
    }

    private func toggle(_ agent: AgentDef, on: Bool) {
        // 自定义 agent 走注册文件逻辑, 不由 DoneP 注入 hook
        if agent.isCustom {
            // 确保脚本存在(烤入地址)供注册方调用
            try? hook.writeNotifyScript(server: settings.server, topic: settings.topic)
            setCustomEnabled(agent, on: on)
            return
        }
        do {
            try hook.writeNotifyScript(server: settings.server, topic: settings.topic)
            if on { try hook.install(agent) } else { try hook.uninstall(agent) }
            installed[agent.id] = on
            // 记录用户意图 (供 app 启动 / 60s 自愈用, 不被 CodeFuse cleanup 干扰)
            UserDefaults.standard.set(on, forKey: "donep.intent.\(agent.id)")
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
