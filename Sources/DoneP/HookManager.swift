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
    var isSupported: Bool = true // 门能否被勾 (false = 按钮置灰, 比如 CodeFuse UI 模式被 --settings 覆盖)
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
    AgentDef(id: "claude",   name: "Claude Code",  configPath: "~/.claude/settings.json", note: "官方 Claude Code CLI"),
    AgentDef(id: "codex",    name: "Codex",        configPath: "~/.codex/hooks.json",      note: "OpenAI Codex CLI"),
    AgentDef(id: "codefuse", name: "CodeFuse",     configPath: "~/.claude/settings.json", note: "antcc 模式 (与 Claude 共用 settings.json)"),
    AgentDef(id: "openclaw", name: "OpenClaw",     configPath: "(plugin)",                  note: "真插件, 开启后需 openclaw restart", kind: .openclaw),
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

        # 从 stdin 的 hook JSON 里取 transcript_path, 读最后一条 assistant 回复全文。
        # 同时兼容两种格式:
        #   Claude: 行 {type:"assistant", message:{content:[{type:"text",text}]}} 或 {role:"assistant",content:...}
        #   Codex : 行 {type:"response_item", payload:{type:"message",role:"assistant",content:[{type:"output_text",text}]}}
        # 不截断 — 手表/手机端自己会截。拿不到就降级(不报错不阻塞)。
        REPLY=""
        if [ ! -t 0 ]; then
          STDIN_JSON="$(cat 2>/dev/null)"
          if [ -n "$STDIN_JSON" ] && command -v python3 >/dev/null 2>&1; then
            REPLY="$(printf '%s' "$STDIN_JSON" | python3 -c '
        import sys,json,os
        def texts_from_content(c):
            out=[]
            if isinstance(c,list):
                for b in c:
                    if isinstance(b,dict) and b.get("type") in ("text","output_text") and isinstance(b.get("text"),str):
                        out.append(b["text"])
            elif isinstance(c,str):
                out.append(c)
            return "".join(out)
        try:
            d=json.load(sys.stdin)
            tp=d.get("transcript_path") or d.get("transcriptPath") or d.get("TranscriptPath") or ""
            txt=""
            if tp and os.path.exists(os.path.expanduser(tp)):
                last=""
                for line in open(os.path.expanduser(tp)):
                    line=line.strip()
                    if not line: continue
                    try: o=json.loads(line)
                    except: continue
                    # Codex: payload 包一层
                    p=o.get("payload") if isinstance(o.get("payload"),dict) else None
                    if p is not None:
                        if p.get("type")=="message" and p.get("role")=="assistant":
                            t=texts_from_content(p.get("content"))
                            if t.strip(): last=t
                        continue
                    # Claude: 顶层 type=assistant 或 message.role=assistant
                    m=o.get("message") if isinstance(o.get("message"),dict) else o
                    if o.get("type")=="assistant" or m.get("role")=="assistant":
                        t=texts_from_content(m.get("content"))
                        if t.strip(): last=t
                txt=last
            txt=" ".join(txt.split())
            print(txt)
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
          # A) 智能生成: 标题=哪个端, 正文=回复全文(拿不到才降级到项目名)
          TITLE="✅ ${AGENT:-Agent}"
          if [ -n "$REPLY" ]; then MSG="${REPLY}"
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
        // 先序列化出目标 data
        let data = try JSONSerialization.data(withJSONObject: obj,
                                              options: [.prettyPrinted, .withoutEscapingSlashes])
        // ★ 与已有内容对比: 一致就不写。
        //   不这么做会自反馈: 写文件 → kqueue 事件 → reinstall → 再写 → 死循环
        //   2700+ 能量消耗就是这么来的。
        if fm.fileExists(atPath: path),
           let existing = try? Data(contentsOf: URL(fileURLWithPath: path)),
           existing == data {
            return
        }
        // 备份
        if fm.fileExists(atPath: path) {
            let bak = path + ".bak-donep-" + Self.timestamp()
            try? fm.copyItem(atPath: path, toPath: bak)
        } else {
            try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                   withIntermediateDirectories: true)
        }
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
            // 插件文件都在 && openclaw.json 里 entries.donep.enabled == true → 已装
            let extDir = ("~/.openclaw/extensions/donep" as NSString).expandingTildeInPath
            let hasFiles = fm.fileExists(atPath: (extDir as NSString).appendingPathComponent("index.js"))
                && fm.fileExists(atPath: (extDir as NSString).appendingPathComponent("openclaw.plugin.json"))
            guard hasFiles,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: ("~/.openclaw/openclaw.json" as NSString).expandingTildeInPath)),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let entries = (obj["plugins"] as? [String: Any])?["entries"] as? [String: Any],
                  let entry = entries["donep"] as? [String: Any],
                  let enabled = entry["enabled"] as? Bool
            else { return false }
            return enabled
        }
        // 不支持的 Agent (如 CodeFuse UI 模式): 一直返回 false, 开关是置灰的。
        if !agent.isSupported { return false }
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
        if !agent.isSupported { return }  // 不支持的 (如 CodeFuse UI 模式): 什么都不做
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
        if !agent.isSupported { return }  // 不支持的: 不用卸
        if agent.kind == .openclaw {
            // 1) 删插件文件
            let extDir = ("~/.openclaw/extensions/donep" as NSString).expandingTildeInPath
            try? fm.removeItem(atPath: extDir)
            // 2) 删 openclaw.json 里 entries.donep
            let cfgPath = ("~/.openclaw/openclaw.json" as NSString).expandingTildeInPath
            if let data = try? Data(contentsOf: URL(fileURLWithPath: cfgPath)),
               var cfg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               var plugins = cfg["plugins"] as? [String: Any],
               var entries = plugins["entries"] as? [String: Any] {
                entries.removeValue(forKey: "donep")
                plugins["entries"] = entries
                cfg["plugins"] = plugins
                if let out = try? JSONSerialization.data(withJSONObject: cfg,
                                                          options: [.prettyPrinted, .withoutEscapingSlashes]) {
                    try? out.write(to: URL(fileURLWithPath: cfgPath))
                }
            }
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

    // MARK: - OpenClaw 特殊安装
    /// OpenClaw 不走 file-based HOOK.md(那套不派发 agent_end), 走真插件 `api.on("agent_end", ...)`。
    /// toggle ON 时做两件事:
    ///   1) 把 bundled 插件复制到 `~/.openclaw/extensions/donep/` (免用户手跳 openclaw plugins install)
    ///   2) 在 `~/.openclaw/openclaw.json` 里给 donep entry 加上
    ///      `hooks.allowConversationAccess: true` (OpenClaw 默认拒绝第三方 plugin 监听
    ///      会接 conversation 内容的事件, 必须显式 opt-in; 写完需 `openclaw restart` 才生效)
    ///   3) `~/.openclaw/openclaw.json` 里 `plugins.entries.donep.enabled: true`
    private func installOpenClaw(_ agent: AgentDef) throws {
        // 1) bundled 插件源码 — 在 app bundle 里(我们 build 时 copy 进去)。
        // 2) 不依赖 build process: 这几个常量代码与 openclaw-plugin/index.js 一致
        // 3) 源码嵌入, 不需访问 bundle 资源。
        let extDir = ("~/.openclaw/extensions/donep" as NSString).expandingTildeInPath
        try fm.createDirectory(atPath: extDir, withIntermediateDirectories: true)
        let pluginJson = #"""
        {
          "id": "donep",
          "name": "DoneP",
          "description": "Agent 跑完一轮 (agent_end) 时推一条通知到 ntfy/手表。",
          "activation": { "onStartup": true },
          "enabledByDefault": true,
          "configSchema": {
            "type": "object",
            "additionalProperties": false,
            "properties": {}
          }
        }
        """#
        let pluginJs = #"""
        // DoneP OpenClaw 插件: 监听 agent_end (一轮真正结束), 推送通知到 ntfy。
        // 不用 child_process (OpenClaw 安全扫描拦 shell 执行), 直接 fetch。
        // ntfy 的 server/topic 从 DoneP 生成的 donep-notify 脚本里解析 (同源, 无需重复配置)。
        import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
        import os from "node:os";
        import path from "node:path";
        import fs from "node:fs";

        const NOTIFY_SCRIPT = path.join(
          os.homedir(),
          "Library/Application Support/DoneP/donep-notify"
        );

        function readNtfyConfig() {
          try {
            const s = fs.readFileSync(NOTIFY_SCRIPT, "utf8");
            const server = (s.match(/NTFY_SERVER="([^"]+)"/) || [])[1];
            const topic = (s.match(/NTFY_TOPIC="([^"]+)"/) || [])[1];
            if (server && topic) return { server, topic };
          } catch (_) {}
          return null;
        }

        // 从 event.messages 尾部找最后一条 assistant 消息, 抽纯文本。
        // content 可能是字符串, 也可能是 [{type:"text",text}, ...] 块数组。
        function extractReply(messages) {
          if (!Array.isArray(messages)) return "";
          for (let i = messages.length - 1; i >= 0; i--) {
            const m = messages[i];
            if (!m || m.role !== "assistant") continue;
            const c = m.content;
            if (typeof c === "string") return c.trim();
            if (Array.isArray(c)) {
              const txt = c
                .filter((b) => b && (b.type === "text" || typeof b.text === "string"))
                .map((b) => b.text || "")
                .join("")
                .trim();
              if (txt) return txt;
            }
          }
          return "";
        }

        // ntfy 的 Title header 只接 latin-1, emoji (UTF-16 surrogate) 会 fetch throw,
        // 所以 Title 用纯 ASCII; body 无此限制, 直接放完整中文回复 (不截断,
        // 手表端会自己截)。
        export default definePluginEntry({
          id: "donep",
          name: "DoneP",
          register(api) {
            api.on("agent_end", async (event) => {
              try {
                if (event && event.success === false) return;
                const c = readNtfyConfig();
                if (!c) return;
                const reply = extractReply(event && event.messages);
                const body = reply && reply.length > 0 ? reply : "done";
                await fetch(c.server + "/" + c.topic, {
                  method: "POST",
                  headers: { Title: "OpenClaw done", Tags: "bell" },
                  body,
                }).catch(() => {});
              } catch (_) {}
            }, { priority: 10 });
          },
        });
        """#
        let packageJson = #"""
        {
          "name": "donep-openclaw",
          "version": "0.1.0",
          "type": "module",
          "main": "index.js",
          "openclaw": { "extensions": ["./index.js"] }
        }
        """#
        try pluginJson.write(toFile: (extDir as NSString).appendingPathComponent("openclaw.plugin.json"),
                             atomically: true, encoding: .utf8)
        try pluginJs.write(toFile: (extDir as NSString).appendingPathComponent("index.js"),
                           atomically: true, encoding: .utf8)
        try packageJson.write(toFile: (extDir as NSString).appendingPathComponent("package.json"),
                              atomically: true, encoding: .utf8)

        // 2) 3) 修改 openclaw.json
        let cfgPath = ("~/.openclaw/openclaw.json" as NSString).expandingTildeInPath
        var cfg: [String: Any]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: cfgPath)),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            cfg = obj
        } else {
            cfg = [:]
        }
        var plugins = (cfg["plugins"] as? [String: Any]) ?? [:]
        var entries = (plugins["entries"] as? [String: Any]) ?? [:]
        var entry = (entries["donep"] as? [String: Any]) ?? [:]
        entry["enabled"] = true
        var hooks = (entry["hooks"] as? [String: Any]) ?? [:]
        hooks["allowConversationAccess"] = true
        entry["hooks"] = hooks
        entries["donep"] = entry
        plugins["entries"] = entries
        cfg["plugins"] = plugins

        if let data = try? JSONSerialization.data(withJSONObject: cfg,
                                                  options: [.prettyPrinted, .withoutEscapingSlashes]) {
            try? data.write(to: URL(fileURLWithPath: cfgPath))
        }
    }
}
