import SwiftUI
import AppKit
import KliegKit

/// herdr-style look: dark terminal surfaces, monospace text, thin borders, lavender accent.
enum Theme {
    static let bg = Color(hex: 0x131418)
    static let panel = Color(hex: 0x17181d)
    static let raised = Color(hex: 0x1d1e25)
    static let border = Color(hex: 0x2b2d38)
    static let text = Color(hex: 0xe4e4ea)
    static let dim = Color(hex: 0x8b8d9b)
    static let faint = Color(hex: 0x555867)
    static let accent = Color(hex: 0xc3a6ff)          // herdr's lavender
    static let accentInk = Color(hex: 0x1a1426)       // text on the accent

    static let nsBg = NSColor(red: 0x13 / 255, green: 0x14 / 255, blue: 0x18 / 255, alpha: 1)

    static func mono(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Status colours as dots, like herdr: working yellow, blocked pink, done green, idle hollow.
    static func color(_ s: AgentStatus) -> Color {
        switch s {
        case .working: return Color(hex: 0xf2c94c)
        case .blocked: return Color(hex: 0xf06292)
        case .done: return Color(hex: 0x6fdc8c)
        case .idle: return Color(hex: 0x9aa0ad)
        case .unknown: return Color(hex: 0xb48cff)
        case .stopped: return Color(hex: 0x555867)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

/// herdr's status dot: filled for active states, hollow ring for idle, ringed for blocked.
struct StatusDot: View {
    let status: AgentStatus
    var size: CGFloat = 9
    var body: some View {
        let c = Theme.color(status)
        ZStack {
            switch status {
            case .idle, .stopped:
                Circle().stroke(c, lineWidth: 1.5)
            case .blocked:
                Circle().stroke(c, lineWidth: 1.5)
                Circle().fill(c).padding(size * 0.25)
            default:
                Circle().fill(c)
            }
        }
        .frame(width: size, height: size)
    }
}

/// A box with a title cut into its top border, like herdr's pane frame.
struct TitledFrame<Content: View>: View {
    let title: String
    var color: Color = Theme.accent
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.top, 10)
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2).stroke(color, lineWidth: 1.5)
            }
            .overlay(alignment: .topLeading) {
                Text(" \(title) ").font(Theme.mono(13, .semibold)).foregroundStyle(color)
                    .background(Theme.bg).offset(x: 12, y: -9)
            }
    }
}

extension Theme {
    static let ok = Color(hex: 0x6fdc8c)
    static let warn = Color(hex: 0xf2c94c)
    static let bad = Color(hex: 0xf06292)
    static let model = Color(hex: 0xc3e88d)
}

/// Applies a keyboard shortcut when there is one.
struct OptionalShortcut: ViewModifier {
    let shortcut: KeyboardShortcut?
    @ViewBuilder func body(content: Content) -> some View {
        if let shortcut { content.keyboardShortcut(shortcut) } else { content }
    }
}

/// A button that is a word, with its key first in the accent: `[esc] cancel`, `[y] stop`.
struct TermButton: View {
    let title: String
    let key: String?
    let color: Color
    let enabled: Bool
    let shortcut: KeyboardShortcut?
    let action: () -> Void
    @ViewState private var hover = false

    init(_ title: String, key: String? = nil, color: Color = Theme.text, enabled: Bool = true,
         shortcut: KeyboardShortcut? = nil, action: @escaping () -> Void) {
        self.title = title; self.key = key; self.color = color; self.enabled = enabled
        self.shortcut = shortcut; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let key { Text("[\(key)]").foregroundStyle(enabled ? Theme.accent : Theme.faint) }
                Text(title).foregroundStyle(enabled ? color : Theme.faint)
            }
            .font(Theme.mono(13))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(hover && enabled ? Theme.raised : Color.clear, in: RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .modifier(OptionalShortcut(shortcut: shortcut))
        .onHover { hover = $0 }
    }
}

/// A one-line field: plain mono text with a rule under it.
struct TermField: View {
    let placeholder: String
    @Binding var text: String
    let rule: Color

    init(_ placeholder: String, text: Binding<String>, rule: Color = Theme.accent) {
        self.placeholder = placeholder; self._text = text; self.rule = rule
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.mono(13)).foregroundStyle(Theme.text)
                .padding(.vertical, 6)
            Rectangle().fill(rule).frame(height: 1)
        }
    }
}

/// A multi-line field: mono text between two rules.
struct TermEditor: View {
    @Binding var text: String
    var rule: Color = Theme.accent
    var height: CGFloat = 160

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(rule).frame(height: 1)
            TextEditor(text: $text)
                .font(Theme.mono(13)).foregroundStyle(Theme.text)
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
                .frame(height: height)
                .padding(.vertical, 4)
            Rectangle().fill(rule).frame(height: 1)
        }
    }
}

/// A toggle as text: `[x] read-only`.
struct TermToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) { self.title = title; self._isOn = isOn }

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 8) {
                Text(isOn ? "[x]" : "[ ]").foregroundStyle(Theme.accent)
                Text(title).foregroundStyle(Theme.text)
            }
            .font(Theme.mono(13))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A box drawn over the window on a dimmed backdrop, like the command palette. Klieg never opens a
/// macOS sheet or alert. The content ends with its own row of TermButtons; `esc` is one of them.
struct Modal<Content: View>: View {
    let title: String
    var width: CGFloat = 660
    let onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title).font(Theme.mono(14, .semibold)).foregroundStyle(Theme.accent)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                Rectangle().fill(Theme.border).frame(height: 1)
                content.padding(14)
            }
            .frame(width: width)
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(.top, 70)
        }
        .font(Theme.mono(13)).foregroundStyle(Theme.text)
    }
}
