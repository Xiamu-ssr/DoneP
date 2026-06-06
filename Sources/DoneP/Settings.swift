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

/// 注册目录契约: ~/.donep/agents/<id>.json
/// 用户的 agent 按 SKILL.md 往这里写注册文件, DoneP 自动识别+显示+开关
enum DonePRegistry {
    /// ~/.donep 根目录
static var rootDir: String {
        ("~/.donep" as NSString).expandingTildeInPath
    }
    /// 注册目录 ~/.donep/agents/
    static var agentsDir: String {
        (rootDir as NSString).appendingPathComponent("agents")
    }
    /// skill 文档位置 (UI 展示给用户)
    static var skillPath: String {
        (rootDir as NSString).appendingPathComponent("skill/SKILL.md")
    }

    /// 扫描注册目录, 返回所有自定义 agent
    static func scan() -> [CustomAgent] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: agentsDir) else { return [] }
        var out: [CustomAgent] = []
        for f in files.sorted() where f.hasSuffix(".json") {
            let path = (agentsDir as NSString).appendingPathComponent(f)
            guard let data = fm.contents(atPath: path),
                  var agent = try? JSONDecoder().decode(CustomAgent.self, from: data)
            else { continue }
            agent.fileId = (f as NSString).deletingPathExtension
            out.append(agent)
        }
        return out
    }

    static func ensureDirs() {
        try? FileManager.default.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)
    }
}

/// 注册文件的内容契约 (~/.donep/agents/<id>.json)
/// 只有 name 必填; enabled/uninstall 可选
struct CustomAgent: Codable, Identifiable {
    var name: String              // 显示名 + 通知端名 (Instance Name)
    var enabled: Bool? = nil      // 可选: 注册方自报开关状态
    var uninstall: String? = nil  // 可选: 关闭时 DoneP 代执行的清理命令
    var note: String? = nil       // 可选: 说明文字

    var fileId: String = ""       // 文件名(不含.json), 运行时填, 不序列化
    var id: String { fileId }

    enum CodingKeys: String, CodingKey { case name, enabled, uninstall, note }
}
