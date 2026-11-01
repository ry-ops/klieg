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
