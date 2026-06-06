import Foundation

/// 简单的设置持久化 (UserDefaults)
final class DonePSettings: ObservableObject {
    static let shared = DonePSettings()

    private let d = UserDefaults.standard
    private let kServer = "donep.server"
    private let kTopic  = "donep.topic"

    @Published var server: String {
        didSet { d.set(server, forKey: kServer) }
    }
    @Published var topic: String {
        didSet { d.set(topic, forKey: kTopic) }
    }

    private init() {
        server = d.string(forKey: kServer) ?? "https://ntfy.sh"
        // 首次启动: 自动生成一个难猜的专属 topic (只生成一次, 之后永久复用)
        if let saved = d.string(forKey: kTopic), !saved.isEmpty {
            topic = saved
        } else {
            let generated = Self.makeDefaultTopic()
            topic = generated
            d.set(generated, forKey: kTopic)
        }
    }

    /// 生成形如 donep-XXXXXXXXXXXX 的随机 topic (带足够熵, 防被猜中)
    static func makeDefaultTopic() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let rand = (0..<14).map { _ in chars.randomElement()! }
        return "donep-" + String(rand)
    }

    var isConfigured: Bool {
        !server.trimmingCharacters(in: .whitespaces).isEmpty &&
        !topic.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
