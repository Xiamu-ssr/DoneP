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
    }
}
