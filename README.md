<p align="center">
  <img src="Resources/logo-transparent.png" width="140" alt="DoneP" />
</p>

<h1 align="center">DoneP 🔔</h1>

<p align="center"><b>AI agent 干完活，震你一下。无需任何新 AI 硬件，随时随地知道它跑完没、结果如何。</b></p>

---

你挂着 Claude Code / Codex 跑长任务，却得时不时回去瞄一眼它停了没？
DoneP 让 agent **干完一轮停下等你**的那一刻，把通知推到你手机/手表上 —— 你大可去喝咖啡、开会、遛弯，它好了自然叫你。

```mermaid
flowchart LR
    A["🤖 Agent 干完活<br/>(Stop hook)"] --> B["DoneP<br/>donep-notify"]
    B --> C["☁️ ntfy 推送"]
    C --> D["📱 手机"]
    D --> E["⌚ 手表震一下"]
    style A fill:#1664ff,color:#fff
    style B fill:#0ea5ff,color:#fff
    style C fill:#00bfff,color:#fff
    style D fill:#e8f2ff,color:#0b3d91
    style E fill:#e8f2ff,color:#0b3d91
```

> 关键点：**用你已有的手机/手表就行**，不用买灵动岛配件、不用新 AI 设备。

## 用起来（3 步）

1. **手机装 [ntfy](https://github.com/binwiederhier/ntfy-android/releases)**，订阅 DoneP 给你的 topic
   （国内务必用 F-Droid/GitHub 版并开启「Instant delivery / 及时交付」，Play 版走 FCM 收不到）
2. **打开 DoneP**，菜单栏点铃铛 → topic 已自动生成好，点「测试」确认手机收到
3. **给想提醒的 Agent 拨开开关** —— 完事

| 内置支持 | 配置位置 |
|---|---|
| Claude Code（含 antcc） | `~/.claude/settings.json` |
| Codex | `~/.codex/hooks.json` |
| CodeFuse（beta） | `~/.codefuse/engine/cc/settings.json` |
| OpenClaw（beta） | `~/.openclaw/hooks/donep/`（`agent_end` 事件） |

> DoneP 只把 `donep-notify` 安全注入/移除到各 Agent 的结束钩子，**保留你已有的其它钩子**并自动备份 `*.bak-donep-*`。结束钩子 = 整轮结束停下等输入那一刻，不会过程中狂震。
>
> 标 **beta** 的 Agent 被其客户端托管，hook 不一定生效；改后需重启该 Agent。

### 接入你自己的 Agent（Agent 时代玩法）

不需要 DoneP 源码。把 DoneP 面板上显示的 skill 路径（`~/.donep/skill/SKILL.md`）发给你的 AI，让它读完自动接入。约定很简单：

- **注册**：往 `~/.donep/agents/<id>.json` 写 `{ "name": "MyBot" }`，DoneP 面板自动出现开关（目录监听，零轮询）。
- **通知**：干完活时调 `'~/Library/Application Support/DoneP/donep-notify' --agent 'MyBot'`（或再跟标题/正文自定义）。你不需要知道 ntfy 地址。
- **卸载**（可选）：注册文件里写 `uninstall` 命令，用户在面板关开关时 DoneP 代为清理。

## 安装

下载 [Release](../../releases) 里的 DMG，拖进 Applications。未公证，首次**右键 → 打开**，或「系统设置 → 隐私与安全性」点「仍要打开」。

## 隐私

全部本地运行，不收集任何数据。topic 靠"名字猜不到"保证私密，首次已自动生成带随机串的专属名。想更稳可自建 ntfy 服务器，地址填进 DoneP 即可。

## 构建

```bash
./scripts/build-app.sh 0.6.0   # 编译 + 组装 DoneP.app
./scripts/make-dmg.sh 0.6.0    # 打包 DMG
```

## ☕ 请我喝咖啡

DoneP 永久免费开源。如果它帮你少盯了几次屏幕，欢迎扫码请杯咖啡 🙏（App 里也有按钮）

<img src="Resources/donate-wechat.png" width="200" alt="微信收款码" />

## License

MIT
