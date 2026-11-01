import Foundation

// ScreenFeed: keeps one agent's terminal text fresh for a live pane in the app. It polls on a background
// queue (herdr `agent read` or `rig capture`, chosen from the agent's source) and calls the handler only
// when the text changed.

public final class ScreenFeed: @unchecked Sendable {
    public typealias Handler = @Sendable (String) -> Void
    public typealias ErrorHandler = @Sendable (Error) -> Void
    /// Reads the screen once. Its text goes through `normalize` before comparing.
    public typealias Reader = @Sendable () throws -> String

    public let interval: TimeInterval
    public let lines: Int
    let read: Reader
    let handler: Handler
    let onError: ErrorHandler?
    let queue: DispatchQueue

    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var generation = 0
    private var last: String?
    private var lastError: String?

    /// A feed over any reader. `onError` is called when a read fails, once per distinct error.
    public init(interval: TimeInterval = 1, lines: Int = 200, queue: DispatchQueue? = nil,
                read: @escaping Reader, onError: ErrorHandler? = nil, handler: @escaping Handler) {
        self.interval = max(0.01, interval); self.lines = max(1, lines)
        self.read = read; self.onError = onError; self.handler = handler
        self.queue = queue ?? DispatchQueue(label: "klieg.screenfeed", qos: .utility)
    }

    /// A feed for an agent: herdr agents through `herdr`, OpenRig seats through `openrig`.
    public convenience init(agent: Agent, herdr: HerdrClient?, openrig: OpenRigClient?, interval: TimeInterval = 1,
                            lines: Int = 200, queue: DispatchQueue? = nil, onError: ErrorHandler? = nil,
                            handler: @escaping Handler) throws {
        self.init(interval: interval, lines: lines, queue: queue,
                  read: try ScreenFeed.reader(for: agent, herdr: herdr, openrig: openrig, lines: lines),
                  onError: onError, handler: handler)
    }

    public static func reader(for agent: Agent, herdr: HerdrClient?, openrig: OpenRigClient?, lines: Int) throws -> Reader {
        switch agent.source {
        case .herdr:
            guard let herdr else { throw KliegError("No herdr client to read \(agent.id).") }
            let id = agent.id
            return { try herdr.read(id, lines: lines, source: "recent-unwrapped") }
        case .openrig:
            guard let openrig else { throw KliegError("No OpenRig client to read \(agent.id).") }
            let session = agent.id.hasPrefix("openrig:") ? String(agent.id.dropFirst("openrig:".count)) : agent.name
            return { try openrig.capture(session: session, lines: lines) }
        case .github:
            throw KliegError("\(agent.id) has no screen.")
        }
    }

    public var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return timer != nil }

    /// Starts polling now and every `interval` seconds. Does nothing if already running.
    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard timer == nil else { return }
        generation += 1
        let gen = generation
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in self?.tick(generation: gen) }
        timer = t
        t.resume()
    }

    /// Stops polling. Safe to call any number of times, from any thread, including from the handler.
    /// No new read starts after it returns; a handler call already under way may still finish.
    public func stop() {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        timer?.cancel()
        timer = nil
    }

    /// One read now, on the caller's thread (for a manual refresh, and the self-test). Returns true when
    /// the handler was called. Timer reads never overlap each other; a poll() can overlap one.
    @discardableResult
    public func poll() -> Bool {
        lock.lock(); let gen = generation; lock.unlock()
        return tick(generation: gen)
    }

    @discardableResult
    func tick(generation gen: Int) -> Bool {
        let text: String
        do {
            text = ScreenFeed.normalize(try read(), lines: lines)
        } catch {
            lock.lock()
            let fresh = lastError != "\(error)" && generation == gen
            if fresh { lastError = "\(error)" }
            lock.unlock()
            if fresh { onError?(error) }
            return false
        }
        lock.lock()
        // A stop() (or restart) since this read began means nobody wants this result.
        guard generation == gen, text != last else { lock.unlock(); return false }
        last = text
        lastError = nil
        lock.unlock()
        // Outside the lock, so a handler may call stop() or hop to the main thread safely.
        handler(text)
        return true
    }

    /// Makes screen text comparable: CRLF to LF, trailing spaces off each line, trailing blank lines
    /// dropped, and only the last `lines` lines kept.
    public static func normalize(_ text: String, lines: Int = 200) -> String {
        var rows = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { row -> Substring in
                var r = row[...]
                while let last = r.last, last == " " || last == "\t" { r = r.dropLast() }
                return r
            }
        while let last = rows.last, last.isEmpty { rows.removeLast() }
        return rows.suffix(max(0, lines)).joined(separator: "\n")
    }
}
