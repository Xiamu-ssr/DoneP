import SwiftUI
import AppKit

@main
struct DonePApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 菜单栏 app: 用 MenuBarExtra, 点击展开一个面板
        MenuBarExtra("DoneP", systemImage: "bell.badge.fill") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

/// 让 app 不在 Dock 显示 (纯菜单栏)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // 启动时安装/更新 skill 到 ~/.donep/skill/SKILL.md
        DonePSkill.install()
        // 启动时直接 idempotent 重注所有已装的内置 agent (不等用户点开面板)。
        // 原因: CodeFuse 自身 cleanup 会覆写 hooks.json, 启动即补, 防护最稳。
        ContentView.reinstallAllEnabledBuiltins()
    }
}
