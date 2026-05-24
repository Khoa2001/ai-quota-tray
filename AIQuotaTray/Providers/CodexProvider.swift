import Foundation

struct CodexProvider: QuotaProvider {

    func fetch() async throws -> QuotaSnapshot {
        let sessionsURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex/sessions")
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsURL.path) else {
            return QuotaSnapshot(
                provider: .codex, used: 0, cap: nil,
                unit: "tokens", resetsAt: nil, fetchedAt: Date(), error: nil
            )
        }

        // Walk all session files sorted newest-first; stop once we find a token_count event.
        let jsonlFiles = allJSONLFiles(under: sessionsURL, fm: fm)
            .sorted { a, b in
                let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return aDate > bDate
            }

        for file in jsonlFiles {
            if let snap = lastTokenCountSnapshot(in: file) {
                return snap
            }
        }

        return QuotaSnapshot(
            provider: .codex, used: 0, cap: nil,
            unit: "tokens", resetsAt: nil, fetchedAt: Date(), error: nil
        )
    }

    // MARK: - Parsing

    private static let windowDuration: TimeInterval = 5 * 3600

    private func lastTokenCountSnapshot(in file: URL) -> QuotaSnapshot? {
        let fileMod = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate

        let objects = JSONLReader.objects(at: file)
        var best: QuotaSnapshot?

        for obj in objects {
            guard
                let payload = obj["payload"] as? [String: Any],
                (payload["type"] as? String) == "token_count"
            else { continue }

            let rateLimits = payload["rate_limits"] as? [String: Any]
            guard let window = rateLimits?["primary"] as? [String: Any] else { continue }

            let now = Date()

            let resetsEpoch = (window["resets_at"]    as? Double) ?? 0
            let apiReset    = resetsEpoch > 0 ? Date(timeIntervalSince1970: resetsEpoch) : nil
            let windowReset = apiReset.map { $0 > now } ?? false

            let usedPercent = windowReset ? ((window["used_percent"] as? Double) ?? 0) : 0

            // Use the API reset time if still future; otherwise fall back to file-mod + window duration.
            let resetsAt: Date?
            if let r = apiReset, r > now {
                resetsAt = r
            } else if let mod = fileMod, mod > now.addingTimeInterval(-Self.windowDuration) {
                resetsAt = mod.addingTimeInterval(Self.windowDuration)
            } else {
                resetsAt = nil
            }

            best = QuotaSnapshot(
                provider: .codex,
                used: usedPercent,
                cap: 100,
                unit: "%",
                resetsAt: resetsAt,
                fetchedAt: Date(),
                error: nil
            )
        }
        return best
    }

    // MARK: - Helpers

    private func allJSONLFiles(under url: URL, fm: FileManager) -> [URL] {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [URL] = []
        while let file = enumerator.nextObject() as? URL {
            if file.pathExtension == "jsonl" { result.append(file) }
        }
        return result
    }
}
