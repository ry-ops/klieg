import SwiftUI
import AppKit
import KliegKit

@main
struct KliegApp: App {
    @ViewState private var app = AppState()

    init() {
        // Behave like a normal app even when launched as a bare executable (swift run).
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApp.activate() }
    }

    var body: some Scene {
        WindowGroup("Klieg", id: "main") {
            RootView()
                .environment(app)
                .frame(minWidth: 900, minHeight: 520)
        }
        .commands {
            CommandMenu("Terminal") {
                Button("New Terminal") { app.terminal.newTab() }.keyboardShortcut("`", modifiers: [.control, .shift])
                Button("Toggle Terminal") { app.terminal.toggle() }.keyboardShortcut("`", modifiers: [.control])
            }
        }
    }
}

enum Section: String, CaseIterable, Identifiable {
    case board = "Board", timeline = "Timeline", needsYou = "Needs You", pullRequests = "Pull Requests", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .board: return "square.grid.2x2"
        case .timeline: return "clock.arrow.circlepath"
        case .needsYou: return "hand.raised"
        case .pullRequests: return "arrow.triangle.pull"
        case .settings: return "gearshape"
        }
    }
}

@Observable @MainActor
final class AppState {
    var section: Section = .board
    var config = KliegConfig.load()
    let terminal = TerminalStore()
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            List(Section.allCases, selection: $app.section) { s in
                Label(s.rawValue, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    if !(app.terminal.visible && app.terminal.maximized) {
                        SectionView(section: app.section)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if app.terminal.visible {
                        @Bindable var term = app.terminal
                        PanelResizeHandle(height: $term.height, maxHeight: geo.size.height - 80)
                        TerminalPanel()
                            .frame(height: app.terminal.maximized ? nil : app.terminal.height)
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button { app.terminal.toggle() } label: { Label("Terminal", systemImage: "terminal") }
                        .help("Show or hide the terminal (⌃`)")
                }
            }
        }
    }
}

/// Placeholder content until each milestone fills its section in (see ROADMAP.md).
struct SectionView: View {
    let section: Section
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: section.icon).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(section.rawValue).font(.title2.bold())
            Text(blurb).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .padding()
    }
    var blurb: String {
        switch section {
        case .board: return "Every herdr agent and OpenRig seat, with its state. (M3)"
        case .timeline: return "Claims, handoffs, verdicts, PRs and CI, in order. (M3)"
        case .needsYou: return "Agents waiting on you: approvals, questions, credit prompts. (M3)"
        case .pullRequests: return "PRs the agents opened, with CI and signing status. (M3)"
        case .settings: return "Machines, rigs and repos Klieg watches. (M3)"
        }
    }
}
