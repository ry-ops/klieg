import Foundation

/// Runs a command and captures its output. Used for `herdr`, `ssh … rig …` and `gh`.
public struct CommandResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
    public var ok: Bool { status == 0 }

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status; self.stdout = stdout; self.stderr = stderr
    }
}

public enum ShellError: Error, CustomStringConvertible {
    case notFound(String)
    case timedOut([String], seconds: Double)
    case failed([String], CommandResult)

    public var description: String {
        switch self {
        case .notFound(let c): return "command not found: \(c)"
        case .timedOut(let a, let s): return "timed out after \(Int(s))s: \(a.joined(separator: " "))"
        case .failed(let a, let r):
            let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(a.joined(separator: " ")) exited \(r.status)" + (msg.isEmpty ? "" : ": \(msg)")
        }
    }
}

public enum Shell {
    /// Extra places to look for tools, since apps launched from Finder get a bare PATH.
    public static let searchPath: [String] = {
        let home = NSHomeDirectory()
        let env = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        return env + ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
    }()

    public static func which(_ tool: String) -> String? {
        if tool.contains("/") { return FileManager.default.isExecutableFile(atPath: tool) ? tool : nil }
        for dir in searchPath {
            let p = (dir as NSString).appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Runs `args[0]` with the rest as arguments, no shell involved. Throws on timeout or a missing tool;
    /// a non-zero exit is returned, not thrown, unless `check` is true.
    @discardableResult
    public static func run(_ args: [String], stdin: String? = nil, timeout: Double = 20, check: Bool = false) throws -> CommandResult {
        guard let first = args.first, let exe = which(first) else { throw ShellError.notFound(args.first ?? "") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = Array(args.dropFirst())
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out; p.standardError = err; p.standardInput = inp
        try p.run()
        if let stdin { inp.fileHandleForWriting.write(Data(stdin.utf8)) }
        try? inp.fileHandleForWriting.close()

        // Read both pipes concurrently so a chatty command can't fill a pipe and stall.
        let outBox = DataBox(), errBox = DataBox()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { outBox.set(out.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        group.enter(); DispatchQueue.global().async { errBox.set(err.fileHandleForReading.readDataToEndOfFile()); group.leave() }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            throw ShellError.timedOut(args, seconds: timeout)
        }
        p.waitUntilExit()
        let r = CommandResult(status: p.terminationStatus, stdout: String(decoding: outBox.get(), as: UTF8.self),
                              stderr: String(decoding: errBox.get(), as: UTF8.self))
        if check && !r.ok { throw ShellError.failed(args, r) }
        return r
    }
}

/// A thread-safe holder for bytes read on a background queue.
final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}
