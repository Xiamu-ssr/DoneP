import Foundation

/// 一个受支持的 Agent 的定义
struct AgentDef: Identifiable {
    let id: String          // 稳定标识, 如 "claude"
    let name: String        // 展示名
    let configPath: String  // 绝对路径的 hooks/settings json
    let note: String        // 说明

    var expandedPath: String {
        (configPath as NSString).expandingTildeInPath
    }
}

enum DonePConst {
    /// 应用数据目录
    static var supportDir: String {
        let base = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!
        return (base as NSString).appendingPathComponent("DoneP")
    }
    /// 由 App 生成、被 hook 调用的脚本绝对路径
    static var notifyScriptPath: String {
        (supportDir as NSString).appendingPathComponent("donep-notify")
    }
    /// 写进 hooks 的命令字符串: 路径含空格, 必须加单引号, 否则 shell 拆词导致 exit 127
    static var notifyCommand: String {
        "'\(notifyScriptPath)'"
    }
}

/// 受支持的 Agent 列表 (都是 Claude Code 内核的 hooks.json / settings.json 结构)
let SUPPORTED_AGENTS: [AgentDef] = [
    AgentDef(id: "claude",   name: "Claude Code", configPath: "~/.claude/settings.json", note: "也覆盖 antcc (它实际跑的是 claude)"),
    AgentDef(id: "codex",    name: "Codex",       configPath: "~/.codex/hooks.json",     note: "OpenAI Codex CLI"),
    AgentDef(id: "codefuse", name: "CodeFuse",    configPath: "~/.codefuse/hooks.json",  note: "蚂蚁内部, Claude 内核"),
]

/// 负责把 donep-notify 注入/移除到各 Agent 的 Stop 钩子
final class HookManager {
    static let shared = HookManager()

    private let fm = FileManager.default

    /// 判断某条命令是否是 DoneP 注入的 (兼容带引号/不带引号两种历史写法)
    static func isDonePCommand(_ cmd: String?) -> Bool {
        guard let cmd = cmd else { return false }
        return cmd.contains(DonePConst.notifyScriptPath)
    }

    // MARK: - 脚本管理

    /// 写入/更新 donep-notify 脚本 (把 ntfy 地址烤进去)
    func writeNotifyScript(server: String, topic: String) throws {
        try fm.createDirectory(atPath: DonePConst.supportDir, withIntermediateDirectories: true)
        let script = """
        #!/usr/bin/env bash
        # 由 DoneP 自动生成, 请勿手改 (改 ntfy 地址请在 DoneP 设置里改)
        NTFY_SERVER="\(server)"
        NTFY_TOPIC="\(topic)"
        if [ "$#" -ge 2 ]; then TITLE="$1"; MSG="$2"
        elif [ "$#" -eq 1 ]; then TITLE="任务完成"; MSG="$1"
        else TITLE="任务完成"; MSG="✅ Agent 任务已完成 ($(hostname -s) · $(date '+%H:%M'))"; fi
        nohup curl -s -m 5 -H "Title: ${TITLE}" -H "Tags: white_check_mark" \\
          -d "${MSG}" "${NTFY_SERVER}/${NTFY_TOPIC}" >/dev/null 2>&1 &
        exit 0
        """
        let path = DonePConst.notifyScriptPath
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        // chmod +x
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    // MARK: - JSON 读写

    private func loadJSON(_ path: String) -> [String: Any] {
        guard let data = fm.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private func saveJSON(_ obj: [String: Any], to path: String) throws {
        // 备份
        if fm.fileExists(atPath: path) {
            let bak = path + ".bak-donep-" + Self.timestamp()
            try? fm.copyItem(atPath: path, toPath: bak)
        } else {
            try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                   withIntermediateDirectories: true)
        }
        let data = try JSONSerialization.data(withJSONObject: obj,
                                              options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: URL(fileURLWithPath: path))
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    // MARK: - 钩子查询/安装/卸载

    /// 该 Agent 的 Stop 钩子里是否已装 DoneP
    func isInstalled(_ agent: AgentDef) -> Bool {
        let obj = loadJSON(agent.expandedPath)
        guard let hooks = obj["hooks"] as? [String: Any],
              let stop = hooks["Stop"] as? [[String: Any]] else { return false }
        for group in stop {
            if let hs = group["hooks"] as? [[String: Any]] {
                for h in hs where Self.isDonePCommand(h["command"] as? String) {
                    return true
                }
            }
        }
        return false
    }

    /// 安装: 往 Stop 追加一条指向 donep-notify 的 hook
    func install(_ agent: AgentDef) throws {
        var obj = loadJSON(agent.expandedPath)
        var hooks = (obj["hooks"] as? [String: Any]) ?? [:]
        var stop = (hooks["Stop"] as? [[String: Any]]) ?? []

        // 去重 (兼容旧的无引号写法)
        let already = stop.contains { group in
            (group["hooks"] as? [[String: Any]])?.contains {
                Self.isDonePCommand($0["command"] as? String)
            } ?? false
        }
        if !already {
            stop.append([
                "hooks": [
                    ["command": DonePConst.notifyCommand, "type": "command", "timeout": 10]
                ]
            ])
        }
        hooks["Stop"] = stop
        obj["hooks"] = hooks
        try saveJSON(obj, to: agent.expandedPath)
    }

    /// 卸载: 移除指向 donep-notify 的 hook (保留其它钩子)
    func uninstall(_ agent: AgentDef) throws {
        var obj = loadJSON(agent.expandedPath)
        guard var hooks = obj["hooks"] as? [String: Any],
              var stop = hooks["Stop"] as? [[String: Any]] else { return }

        stop = stop.compactMap { group -> [String: Any]? in
            guard var hs = group["hooks"] as? [[String: Any]] else { return group }
            hs.removeAll { Self.isDonePCommand($0["command"] as? String) }
            if hs.isEmpty { return nil }  // 整组空了就删掉
            var g = group; g["hooks"] = hs; return g
        }
        hooks["Stop"] = stop
        obj["hooks"] = hooks
        try saveJSON(obj, to: agent.expandedPath)
    }
}
