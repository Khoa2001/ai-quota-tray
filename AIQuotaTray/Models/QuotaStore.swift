import Foundation

@MainActor
final class QuotaStore: ObservableObject {

    @Published var snapshots: [Provider: QuotaSnapshot] = [:]
    @Published var isRefreshing = false

    private var autoRefreshTask: Task<Void, Never>?
    private(set) var lastRefreshedAt: Date?

    // MARK: - Lifecycle

    func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.refreshIntervalSeconds * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    // MARK: - Refresh

    private static let refreshIntervalSeconds: Double = 60

    var isStale: Bool {
        guard let last = lastRefreshedAt else { return true }
        return Date().timeIntervalSince(last) >= Self.refreshIntervalSeconds
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let c = fetch(.claude) { try await ClaudeCodeProvider().fetch() }
        async let d = fetch(.codex)  { try await CodexProvider().fetch() }
        async let r = fetch(.cursor) { try await CursorProvider().fetch() }

        let (claude, codex, cursor) = await (c, d, r)

        // Never overwrite a valid snapshot with an error — keep showing stale data instead.
        func apply(_ new: QuotaSnapshot, for provider: Provider) {
            if new.error != nil, let existing = snapshots[provider], existing.error == nil {
                return
            }
            snapshots[provider] = new
        }

        apply(claude, for: .claude)
        apply(codex,  for: .codex)
        apply(cursor, for: .cursor)
        lastRefreshedAt = Date()
    }

    // MARK: - Helpers

    /// Race the operation against a 10-second timeout; errors become error snapshots.
    nonisolated private func fetch(
        _ provider: Provider,
        operation: @escaping @Sendable () async throws -> QuotaSnapshot
    ) async -> QuotaSnapshot {
        await withTaskGroup(of: QuotaSnapshot.self) { group in
            group.addTask {
                do    { return try await operation() }
                catch { return QuotaSnapshot.error(provider, error.localizedDescription) }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                return QuotaSnapshot.error(provider, "Timeout")
            }
            let first = await group.next()!
            group.cancelAll()
            return first
        }
    }

    // MARK: - Tray icon

    var traySystemImage: String {
        let worst = snapshots.values
            .compactMap(\.fraction)
            .max() ?? 0
        if worst >= 0.85 { return "gauge.with.dots.needle.67percent" }
        if worst >= 0.60 { return "gauge.with.dots.needle.33percent" }
        return "gauge.medium"
    }
}
