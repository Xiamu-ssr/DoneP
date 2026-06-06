import SwiftUI
import AppKit

/// 「请我喝咖啡」弹窗: 显示微信收款码
struct DonateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("☕ 请作者喝杯咖啡")
                .font(.headline)
            Text("如果 DoneP 帮你少盯了几次屏幕,\n欢迎微信扫码请杯咖啡 🙏")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let img = Self.loadQR() {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .cornerRadius(8)
            } else {
                Text("(收款码图片缺失)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(width: 220, height: 220)
            }

            Text("感谢支持 · DoneP is free & open source")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 260)
    }

    /// 从 app bundle 的 Resources 里加载收款码
    static func loadQR() -> NSImage? {
        // 优先 bundle 资源
        if let url = Bundle.main.url(forResource: "donate-wechat", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        // 兜底: 同目录 Resources (开发态)
        let devPath = Bundle.main.bundlePath + "/Contents/Resources/donate-wechat.png"
        return NSImage(contentsOfFile: devPath)
    }
}
