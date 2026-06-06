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
        topic  = d.string(forKey: kTopic)  ?? ""
    }

    var isConfigured: Bool {
        !server.trimmingCharacters(in: .whitespaces).isEmpty &&
        !topic.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
