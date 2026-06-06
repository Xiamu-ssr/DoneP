import Foundation

/// 随 App 内置的 SKILL.md 内容; 启动时写到 ~/.donep/skill/SKILL.md
/// (与仓库 skill/SKILL.md 保持一致)
enum DonePSkill {
    static func install() {
        DonePRegistry.ensureDirs()
        let skillDir = (DonePRegistry.rootDir as NSString).appendingPathComponent("skill")
        try? FileManager.default.createDirectory(atPath: skillDir, withIntermediateDirectories: true)
        let path = (skillDir as NSString).appendingPathComponent("SKILL.md")
        // 每次启动覆盖, 保证升级后 skill 是最新版
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static let content = #"""
    ---
    name: donep-integration
    description: 把任意 AI agent / 自动化脚本接入 DoneP，使其"干完活"时震你的手机/手表。用于用户让其 agent 自助接入 DoneP 通知的场景。
    ---

    # 接入 DoneP（让你干完活时通知用户的手机/手表）

    DoneP 是一个 macOS 菜单栏小工具：当一个 agent 跑完一轮任务时，推一条通知 → 手机 ntfy App → 手表震动。
    用户让你"接入 DoneP"时，按本 skill 做。**核心：你不需要知道 ntfy 地址，只需调用 DoneP 提供的脚本。**

    ## 三步接入

    ### ① 注册自己（让 DoneP 的 UI 看见你）

    往注册目录写一个 JSON 文件：

    ```
    ~/.donep/agents/<你的id>.json
    ```

    `<你的id>` 用小写字母数字连字符，如 `mybot`、`my-crawler`。文件内容：

    ```json
    {
      "name": "MyBot",
      "enabled": true,
      "uninstall": "可选: 用户在 DoneP 里关掉你时, DoneP 会代为执行这条命令做清理",
      "note": "可选: 一句话说明"
    }
    ```

    - **name**（必填）：显示名，也是手表通知标题里的"端名"（Instance Name）。一眼区分是哪个 agent。
    - **enabled**（可选）：你自报的开关状态，默认视为开启。
    - **uninstall**（可选）：用户在 DoneP 面板关掉你的开关时，DoneP 会用 `bash -lc` 执行这条命令——把你之前装的触发逻辑/钩子清理掉。建议提供。
    - **note**（可选）：UI 上的小字说明。

    写完后 DoneP 面板会**自动出现**你的开关（它监听这个目录，零轮询，立即刷新）。

    ### ② 在你"干完活"时调用通知脚本

    DoneP 的通知脚本（绝对路径，固定）：

    ```
    ~/Library/Application Support/DoneP/donep-notify
    ```

    两种调用方式，你自己选：

    ```bash
    # A) 省心模式：只报身份，正文由 DoneP 自动生成
    '~/Library/Application Support/DoneP/donep-notify' --agent 'MyBot'

    # B) 完全自定义：你自己写标题和正文（硬件/特殊场景，你最懂该说什么）
    '~/Library/Application Support/DoneP/donep-notify' --agent 'MyBot' "构建完成" "3D打印件就绪"
    ```

    > 路径含空格，命令里**必须加单引号**，否则 shell 拆词导致命令找不到。
    >
    > **省心模式的正文怎么来的**：若你是 Claude / Codex 内核的 agent，Stop hook 会通过 stdin 传一个含 `transcript_path` 的 JSON，donep-notify 自动读出你**最后一条 assistant 回复全文**作为正文（不截断，手表/手机端自己截断显示），同时兼容 Claude 与 Codex 两种 transcript 格式。拿不到才降级为项目名 / "完成"。
    >
    > 若你是自定义脚本/硬件（不走 stdin transcript），想要正文就用 B) 自己传。

    **怎么触发**由你决定（这是你最懂的部分，DoneP 不干预）：
    - 你是 Claude/Codex 风格的 agent → 把上面命令注入自己的 `Stop` hook（`hooks.json` 的 `Stop[].hooks[].command`）。
    - 你是自定义脚本/硬件 → 在你的流程结束处直接调这条命令。
    - 你是别的事件驱动系统 → 在"完成"事件回调里调它。

    ### ③ 提供卸载（可选但推荐）

    把 ② 里"怎么触发"的反操作写进注册文件的 `uninstall` 字段。这样用户在 DoneP 面板关你开关时，DoneP 帮你清理，无需用户手动改文件。

    ## 验证

    ```bash
    # 直接发一条测试，看手机/手表收没收到
    '~/Library/Application Support/DoneP/donep-notify' --agent 'MyBot' "DoneP 测试" "接入成功"
    ```

    收到了就接好了。注意：若你是 Claude 内核 agent，hook 是**会话启动时快照**的——改完 hook 配置要**新开一个会话**才生效。

    ## 约定速查

    | 项 | 值 |
    |---|---|
    | 注册目录 | `~/.donep/agents/<id>.json` |
    | 必填字段 | `name` |
    | 通知脚本 | `~/Library/Application Support/DoneP/donep-notify` |
    | 报身份 | `--agent '<name>'` |
    | 自定义内容 | `--agent '<name>' "<标题>" "<正文>"` |
    | ntfy 地址 | **你不需要知道**，脚本内置 |
    """#
}
