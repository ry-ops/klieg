import Foundation
import KliegKit
import UserNotifications

/// Polls herdr (and, once M2 lands, OpenRig and GitHub) on a background queue and publishes
/// snapshots and timeline events to the UI.
@Observable @MainActor
final class Monitor {
    private(set) var snapshot = Snapshot()
    private(set) var events: [TimelineEvent] = []
    private(set) var lastRefresh: Date?
    private(set) var refreshing = false
    var config: KliegConfig

    private let store: TimelineStore
    private var loop: Task<Void, Never>?
    private var notified: Set<String> = []

    init(config: KliegConfig) {
        self.config = config
        // The app keeps its own history, separate from the CLI's.
        store = TimelineStore(directory: KliegConfig.file.deletingLastPathComponent().appendingPathComponent("app"))
        events = store.events()
        if let last = store.lastSnapshot() { snapshot = last }
    }

    var herdr: HerdrClient { HerdrClient.fromConfig(config) }

    func start() {
        guard loop == nil else { return }
        requestNotificationPermission()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let wait = max(2, self?.config.refreshSeconds ?? 5)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        let cfg = config
        let store = self.store
        let (snap, fresh) = await Task.detached(priority: .utility) { () -> (Snapshot, [TimelineEvent]) in
            let s = Monitor.collect(cfg)
            let e = (try? store.record(s)) ?? []
            return (Timeline.carryOver(from: store.lastSnapshot(), to: s), e)
        }.value
        snapshot = snap
        if !fresh.isEmpty { events = Array((events + fresh).suffix(500)) }
        lastRefresh = Date()
        refreshing = false
        notifyNewBlocked()
    }

    /// Everything Klieg can see right now. M2 adds OpenRig and GitHub here.
    nonisolated static func collect(_ cfg: KliegConfig) -> Snapshot {
        HerdrClient.fromConfig(cfg).snapshot()
    }

    // MARK: Notifications

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }   // not available under `swift run`
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func notifyNewBlocked() {
        let blocked = Set(snapshot.needingPerson.map(\.id))
        for a in snapshot.needingPerson where !notified.contains(a.id) {
            post(title: "\(a.name) needs you", body: reasonText(a))
        }
        notified = blocked
    }

    private func post(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

/// Plain words for why an agent is waiting.
func reasonText(_ a: Agent) -> String {
    switch a.attentionReason {
    case "trust_prompt": return "Claude is asking whether to trust this folder."
    case "permission_prompt": return "It's asking to approve a command."
    case let r?: return r.replacingOccurrences(of: "_", with: " ")
    case nil: return a.status == .blocked ? "It's waiting for your answer." : a.status.rawValue
    }
}
