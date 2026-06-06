import Foundation

/// 一个受支持的 Agent 的定义
/// 安装方式
enum AgentKind {
    case claudeStyle   // Claude/Codex/CodeFuse: 注入 hooks.Stop[]
    case openclaw      // OpenClaw: 写 ~/.openclaw/hooks/donep/ (HOOK.md+handler)
}

struct AgentDef: Identifiable {
    let id: String          // 稳定标识, 如 "claude"
    let name: String        // 展示名
    let configPath: String  // 绝对路径的 hooks/settings json (claudeStyle 用)
    let note: String        // 说明
    var beta: Bool = false  // 是否 beta (不一定起作用, 如被托管的 CodeFuse)
    var isCustom: Bool = false  // 是否用户自定义
    var kind: AgentKind = .claudeStyle
    var agentLabel: String { name }   // 注入 --agent 的标识 (手表上显示哪个端)

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
    /// 带 --agent 标识的命令 (区分哪个端触发)
    static func notifyCommand(agentLabel: String) -> String {
        "'\(notifyScriptPath)' --agent '\(agentLabel)'"
    }
}

/// 受支持的 Agent 列表 (都是 Claude Code 内核的 hooks.json / settings.json 结构)
let BUILTIN_AGENTS: [AgentDef] = [
    AgentDef(id: "claude",   name: "Claude Code", configPath: "~/.claude/settings.json",            note: "官方 Claude Code CLI"),
    AgentDef(id: "codex",    name: "Codex",       configPath: "~/.codex/hooks.json",                 note: "OpenAI Codex CLI"),
    AgentDef(id: "codefuse", name: "CodeFuse",    configPath: "~/.codefuse/engine/cc/settings.json", note: "蚂蚁 CodeFuse / antcc (托管 Claude 内核)", beta: true),
    AgentDef(id: "openclaw", name: "OpenClaw",    configPath: "~/.openclaw/hooks/donep",             note: "OpenClaw (agent_end 事件, 开启后需 gateway restart)", kind: .openclaw),
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
        let script = #"""
        #!/usr/bin/env bash
        # 由 DoneP 自动生成, 请勿手改 (改 ntfy 地址请在 DoneP 设置里改)
        #
        # 【对外契约 / 自定义 Agent 调用方式】
        #   A) 省心: 只报身份, 内容由 DoneP 生成(项目名+回复摘要)
        #        donep-notify --agent 'MyBot'
        #   B) 自定义: 自己写标题和正文
        #        donep-notify --agent 'MyBot' "标题" "正文"
        NTFY_SERVER="__SERVER__"
        NTFY_TOPIC="__TOPIC__"

        # 解析 --agent <名> (区分哪个端)
        AGENT=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --agent) AGENT="$2"; shift 2 ;;
            --agent=*) AGENT="${1#--agent=}"; shift ;;
            *) break ;;
          esac
        done

        # 项目名: 优先各 Agent 传的项目目录环境变量, 后退 PWD
        PROJ_DIR="${CLAUDE_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}"
        PROJ="$(basename "$PROJ_DIR" 2>/dev/null)"

        # 尝试从 stdin 的 Claude 风格 JSON 里捡最后一条 assistant 回复摘要
        # 拿不到就降级(不报错, 不阻塞), 符合健壮性原则
        REPLY=""
        if [ ! -t 0 ]; then
          STDIN_JSON="$(cat 2>/dev/null)"
          if [ -n "$STDIN_JSON" ] && command -v python3 >/dev/null 2>&1; then
            REPLY="$(printf '%s' "$STDIN_JSON" | python3 -c '
        import sys,json,os
        try:
            d=json.load(sys.stdin)
            tp=d.get("transcript_path","")
            txt=""
            if tp and os.path.exists(os.path.expanduser(tp)):
                last=""
                for line in open(os.path.expanduser(tp)):
                    line=line.strip()
                    if not line: continue
                    try: o=json.loads(line)
                    except: continue
                    m=o.get("message") or o
                    if (o.get("type")=="assistant") or (m.get("role")=="assistant"):
                        c=m.get("content")
                        if isinstance(c,list):
                            for b in c:
                                if isinstance(b,dict) and b.get("type")=="text":
                                    last=b.get("text","") or last
                        elif isinstance(c,str):
                            last=c or last
                txt=last
            txt=" ".join(txt.split())
            print(txt[:24])
        except Exception:
            print("")
        ' 2>/dev/null)"
          fi
        fi

        # 组装消息
        if [ "$#" -ge 2 ]; then
          # B) 显式传入标题+正文
          TITLE="$1"; MSG="$2"
        elif [ "$#" -eq 1 ]; then
          # 只传一个参数 -> 当正文
          TITLE="✅ ${AGENT:-Agent}"; MSG="$1"
        else
          # A) 智能生成: 标题=哪个端, 正文=项目 + 回复摘要(无时间, 省空间)
          TITLE="✅ ${AGENT:-Agent}"
          if [ -n "$REPLY" ] && [ -n "$PROJ" ]; then MSG="${PROJ} · ${REPLY}…"
          elif [ -n "$REPLY" ]; then MSG="${REPLY}…"
          elif [ -n "$PROJ" ]; then MSG="${PROJ}"
          else MSG="完成"; fi
        fi

        nohup curl -s -m 5 -H "Title: ${TITLE}" -H "Tags: bell" \
          -d "${MSG}" "${NTFY_SERVER}/${NTFY_TOPIC}" >/dev/null 2>&1 &
        exit 0
        """#
        .replacingOccurrences(of: "__SERVER__", with: server)
        .replacingOccurrences(of: "__TOPIC__", with: topic)
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
        if agent.kind == .openclaw {
            return fm.fileExists(atPath: (agent.expandedPath as NSString).appendingPathComponent("HOOK.md"))
        }
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
        if agent.kind == .openclaw { try installOpenClaw(agent); return }
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
                    ["command": DonePConst.notifyCommand(agentLabel: agent.agentLabel), "type": "command", "timeout": 10]
                ]
            ])
        }
        hooks["Stop"] = stop
        obj["hooks"] = hooks
        try saveJSON(obj, to: agent.expandedPath)
    }

    /// 卸载: 移除指向 donep-notify 的 hook (保留其它钩子)
    func uninstall(_ agent: AgentDef) throws {
        if agent.kind == .openclaw {
            try? fm.removeItem(atPath: agent.expandedPath)
            return
        }
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

    // MARK: - OpenClaw 特殊安装 (file-based hook: HOOK.md + handler.ts)
    /// 监听 agent_end, 调 donep-notify --agent 'OpenClaw'
    private func installOpenClaw(_ agent: AgentDef) throws {
        let dir = agent.expandedPath
        try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let hookMd = #"""
        ---
        name: donep
        description: "DoneP: agent 跑完一轮后震你一下 (推送到 ntfy/手表)"
        metadata:
          { "openclaw": { "emoji": "\#("\u{1F514}")", "events": ["agent_end"] } }
        ---
        # DoneP Hook
        Agent 一轮结束(agent_end)时调用 donep-notify。
        """#
        let handler = #"""
        // DoneP 自动生成: 监听 agent_end, 调 donep-notify
        import { spawn } from "node:child_process";
        const SCRIPT = "__SCRIPT__";
        const handler = async (event) => {
          if (event?.type !== "agent_end") return;
          try {
            spawn(SCRIPT, ["--agent", "OpenClaw"], { detached: true, stdio: "ignore" }).unref();
          } catch (_) {}
        };
        export default handler;
        """#
        .replacingOccurrences(of: "__SCRIPT__", with: DonePConst.notifyScriptPath)
        try hookMd.write(toFile: (dir as NSString).appendingPathComponent("HOOK.md"),
                         atomically: true, encoding: .utf8)
        try handler.write(toFile: (dir as NSString).appendingPathComponent("handler.ts"),
                          atomically: true, encoding: .utf8)
    }
}
