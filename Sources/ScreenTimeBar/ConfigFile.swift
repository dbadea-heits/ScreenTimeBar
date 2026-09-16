import Foundation

enum ConfigFile {
    static func path() -> String {
        if let override = UserDefaults.standard.string(forKey: "ScreenTimeConfigPath"), !override.isEmpty {
            return override
        }
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return xdg + "/screentime/scores.ini"
        }
        return NSHomeDirectory() + "/.config/screentime/scores.ini"
    }

    static func load() -> ScoresConfig {
        let text = (try? String(contentsOfFile: path(), encoding: .utf8)) ?? ""
        return ScoresConfig.parse(text)
    }

    static func save(_ cfg: ScoresConfig) throws {
        let url = URL(fileURLWithPath: path())
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = Data(cfg.serialized().utf8)
        try data.write(to: url, options: .atomic)
    }
}
