# DoneP 🔔

**让你的 AI coding agent 干完活，震你一下手表。**

DoneP 是一个极简的 macOS 菜单栏小工具：当 Claude Code / Codex / CodeFuse 等 Agent **完成一轮任务、停下来等你输入**的那一刻，自动推一条通知。配合手机上的 [ntfy](https://ntfy.sh) App，再让手机把通知同步到手表，你就能**离开屏幕也被叫回来**。

> 没有灵动岛、没有花哨监控。就两件事：填一个推送地址，给每个 Agent 拨一个开关。

## 它怎么工作

```
Agent 完成任务 (Stop hook)
   → DoneP 注入的脚本 donep-notify
   → ntfy 服务器
   → 手机 ntfy App (横幅)
   → 手机灭屏时同步到手表 → 震一下
```

DoneP 只做一件事：**把 `donep-notify` 脚本安全地注入/移除到各 Agent 的 `Stop` 钩子里**，并保留你已有的其它钩子（每次修改都会自动备份成 `*.bak-donep-*`）。

## 支持的 Agent

| Agent | 配置文件 | 说明 |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | 也覆盖 antcc（它实际跑的是 claude） |
| Codex | `~/.codex/hooks.json` | OpenAI Codex CLI |
| CodeFuse | `~/.codefuse/hooks.json` | 蚂蚁内部，Claude 内核 |

> `Stop` 钩子 = Agent 答完整轮、停下等用户输入那一刻触发，**不是**每次模型推理/工具调用，所以不会过程中狂震。

## 使用

1. 手机装 [ntfy](https://github.com/binwiederhier/ntfy-android/releases)（**国内务必用 F-Droid/GitHub 版并开启「Instant delivery / 及时交付」**，Play 版走 FCM 国内收不到被动推送）。
2. 在 ntfy App 里订阅一个**只有你知道的** topic，例如 `my-agent-done-9f3k2x7q`。
3. 打开 DoneP，菜单栏点开铃铛图标：
   - 填服务器（默认 `https://ntfy.sh`）和你的 topic
   - 点「测试」确认手机/手表能收到
   - 给想要提醒的 Agent 拨开开关
4. 想让手表同步：在手机「运动健康」类 App 里，只勾选 ntfy 同步到手表 —— 手表就变成纯净的专属信号通道。

## 隐私 / 安全

- DoneP 不收集任何数据，全部本地运行。
- topic 没有所有权，靠"名字猜不到"保证私密 —— **请用带随机串的 topic 名**。
- 想更安全可自建 ntfy 服务器，把地址填进 DoneP 即可。

## 构建

需要 Swift 6 工具链（Command Line Tools 即可，无需完整 Xcode）。

```bash
./scripts/build-app.sh 0.1.0   # 编译 + 组装 DoneP.app (ad-hoc 签名)
./scripts/make-dmg.sh 0.1.0    # 打包 DMG
```

产物在 `dist/`。

## 安装未签名 App

DoneP 目前只做 ad-hoc 签名（未经 Apple 公证）。首次打开如被 Gatekeeper 拦截：
右键 App → 打开，或在「系统设置 → 隐私与安全性」里点「仍要打开」。

## License

MIT
