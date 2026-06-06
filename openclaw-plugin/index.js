// DoneP OpenClaw 插件: 监听 agent_end (一轮真正结束), 推送通知到 ntfy。
// 直接用 fetch 发 HTTP, 不用 child_process (OpenClaw 安全扫描会拦 shell 执行)。
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

export default definePluginEntry({
  id: "donep",
  name: "DoneP",
  register(api) {
    const agentLabel = "OpenClaw";

    api.on(
      "agent_end",
      async (event) => {
        try {
          if (event && event.success === false) return;
          const c = readNtfyConfig();
          if (!c) return; // DoneP 没装/没配置, 静默跳过
          const title = `✅ ${agentLabel}`;
          const body = "完成";
          await fetch(`${c.server}/${c.topic}`, {
            method: "POST",
            headers: { Title: title, Tags: "bell" },
            body,
          }).catch(() => {});
        } catch (_) {}
      },
      { priority: 10 }
    );
  },
});
