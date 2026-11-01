import SwiftUI
import AppKit
import SwiftTerm
import KliegKit

// The integrated terminal (adapted from afm-studio). Every agent tab and shell tab in the main area is one
// of these: a real pseudo-terminal (SwiftTerm) running your login shell, so vim, top, ssh and colors all work.

@Observable @MainActor
final class TerminalTab: Identifiable {
    let id = UUID()
    var title: String
    var directory: String?
    let view: LocalProcessTerminalView
    private let bridge = TerminalBridge()

    init(directory: String?, fontSize: CGFloat, command: [String]? = nil, title customTitle: String? = nil,
         onExit: @escaping @MainActor (UUID) -> Void) {
        let shell = TerminalTab.loginShell()
        title = customTitle ?? (shell as NSString).lastPathComponent
        self.directory = directory
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 300))
        view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.nativeBackgroundColor = TerminalTab.background
        view.nativeForegroundColor = NSColor(red: 0.85, green: 0.85, blue: 0.86, alpha: 1)
        view.caretColor = .controlAccentColor
        view.optionAsMetaKey = false     // like Terminal.app: Option types special characters
        bridge.tab = self
        bridge.onExit = onExit
        view.processDelegate = bridge
        if let command, !command.isEmpty {
            // Run through the login shell so PATH and ssh config match the user's own terminal.
            let line = command.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
            view.startProcess(executable: shell, args: ["-l", "-c", line], environment: TerminalTab.environment(shell: shell),
                              execName: (shell as NSString).lastPathComponent,
                              currentDirectory: directory ?? NSHomeDirectory())
        } else {
            view.startProcess(executable: shell, args: [], environment: TerminalTab.environment(shell: shell),
                              execName: "-" + (shell as NSString).lastPathComponent,   // leading "-" makes it a login shell
                              currentDirectory: directory ?? NSHomeDirectory())
        }
    }

    static let background = NSColor(red: 0x13 / 255, green: 0x14 / 255, blue: 0x18 / 255, alpha: 1)

    var label: String {
        if pinnedTitle { return title }
        if let d = directory, !d.isEmpty { return (d as NSString).lastPathComponent }
        return title
    }
    /// Agent tabs keep their agent's name instead of following the shell's title.
    var pinnedTitle = false

    func setFontSize(_ size: CGFloat) { view.font = .monospacedSystemFont(ofSize: size, weight: .regular) }

    func terminate() { view.terminate() }

    /// The selection if there is one, otherwise the last `lines` non-empty lines of output.
    func textForModel(lines: Int = 80) -> (text: String, isSelection: Bool) {
        if let sel = view.getSelection(), !sel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (sel, true)
        }
        let all = String(decoding: view.getBufferAsData(), as: UTF8.self)
        let kept = all.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
            .suffix(lines)
        return (kept.joined(separator: "\n"), false)
    }

    static func loginShell() -> String {
        if let s = ProcessInfo.processInfo.environment["SHELL"], FileManager.default.isExecutableFile(atPath: s) { return s }
        if let pw = getpwuid(getuid()), let p = pw.pointee.pw_shell {
            let s = String(cString: p)
            if FileManager.default.isExecutableFile(atPath: s) { return s }
        }
        return "/bin/zsh"
    }

    /// A clean environment, like Terminal.app's: the login shell's own startup files fill in the rest.
    static func environment(shell: String) -> [String] {
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        let home = NSHomeDirectory()
        env.append("PATH=\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
        env.append("SHELL=\(shell)")
        env.append("TERM_PROGRAM=Klieg")
        env.append("TERM_PROGRAM_VERSION=\(KliegVersion.string)")
        let pe = ProcessInfo.processInfo.environment
        for key in ["TMPDIR", "SSH_AUTH_SOCK", "KLIEG_HOME", "__CF_USER_TEXT_ENCODING"] {
            if let v = pe[key] { env.append("\(key)=\(v)") }
        }
        return env
    }
}

/// SwiftTerm's delegate callbacks, forwarded to the tab on the main actor.
final class TerminalBridge: LocalProcessTerminalViewDelegate {
    weak var tab: TerminalTab?
    var onExit: (@MainActor (UUID) -> Void)?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak self] in
            if !title.isEmpty { self?.tab?.title = title }
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        Task { @MainActor [weak self] in
            guard let d = directory, !d.isEmpty else { return }
            self?.tab?.directory = URL(string: d)?.path ?? d    // OSC 7 sends a file:// URL
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            guard let self, let id = self.tab?.id else { return }
            self.onExit?(id)
        }
    }
}

/// Hosts a tab's long-lived terminal view. The view outlives this wrapper, so hiding
/// the panel or switching tabs never kills a shell.
struct TerminalHost: NSViewRepresentable {
    let tab: TerminalTab

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = TerminalTab.background.cgColor
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if tab.view.superview !== container { attach(to: container) }
    }

    private func attach(to container: NSView) {
        let v = tab.view
        v.removeFromSuperview()
        v.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(v)
        // A little breathing room around the text, like VS Code.
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            v.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            v.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            v.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
        ])
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
    }
}
