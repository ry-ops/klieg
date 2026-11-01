import Foundation

/// Where Klieg finds herdr, OpenRig and GitHub. Read from ~/.config/klieg/config.json, with
/// environment overrides. The defaults mean "this computer" for OpenRig and the saved machine
/// "herdr" for herdr.
public struct KliegConfig: Codable, Sendable {
    /// herdr machine label for `herdr --machine <label> …` (set up with `herdr machine add`).
    public var herdrMachine: String?
    /// herdr session name on that machine.
    public var herdrSession: String
    /// ssh target of the host running the OpenRig daemon, e.g. "ubuntu@rig.example". nil = local.
    public var openrigHost: String?
    /// GitHub repos to watch for agent PRs, "owner/name".
    public var repos: [String]
    /// Seconds between refreshes.
    public var refreshSeconds: Double
    /// When true, every action (prompt, queue, start/stop, approve, merge) is refused.
    public var readOnly: Bool

    public init(herdrMachine: String? = "herdr", herdrSession: String = "work", openrigHost: String? = nil,
                repos: [String] = [], refreshSeconds: Double = 5, readOnly: Bool = false) {
        self.herdrMachine = herdrMachine; self.herdrSession = herdrSession; self.openrigHost = openrigHost
        self.repos = repos; self.refreshSeconds = refreshSeconds; self.readOnly = readOnly
    }

    public static var file: URL {
        let base = ProcessInfo.processInfo.environment["KLIEG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/klieg")
        return base.appendingPathComponent("config.json")
    }

    public static func load() -> KliegConfig {
        var c = KliegConfig()
        if let data = try? Data(contentsOf: file) {
            do { c = try JSONDecoder().decode(KliegConfig.self, from: data) }
            catch {
                // Say so, instead of quietly running with the defaults (and possibly the wrong hosts).
                FileHandle.standardError.write(Data("klieg: ignoring \(file.path): \(error)\n".utf8))
            }
        }
        let env = ProcessInfo.processInfo.environment
        if let v = env["KLIEG_READ_ONLY"] { c.readOnly = ["1", "true", "yes"].contains(v.lowercased()) }
        if let v = env["KLIEG_OPENRIG_HOST"] { c.openrigHost = v.isEmpty ? nil : v }
        if let v = env["KLIEG_HERDR_MACHINE"] { c.herdrMachine = v.isEmpty ? nil : v }
        return c
    }
}
