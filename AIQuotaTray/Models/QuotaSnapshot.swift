import Foundation

struct QuotaSnapshot: Sendable {
    let provider: Provider
    let used: Double
    let cap: Double?
    let unit: String
    let resetsAt: Date?
    let fetchedAt: Date
    let error: String?

    var fraction: Double? {
        guard let cap, cap > 0, error == nil else { return nil }
        return min(used / cap, 1.0)
    }

    static func error(_ provider: Provider, _ message: String) -> QuotaSnapshot {
        QuotaSnapshot(
            provider: provider,
            used: 0, cap: nil, unit: "",
            resetsAt: nil,
            fetchedAt: Date(),
            error: message
        )
    }
}
