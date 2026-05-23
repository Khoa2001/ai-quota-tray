import Foundation
import Security

struct ClaudeCodeProvider: QuotaProvider {

    private static let windowDuration: TimeInterval = 5 * 3600

    func fetch() async throws -> QuotaSnapshot {
        let windowStart = Date().addingTimeInterval(-Self.windowDuration)

        // Run local parse and API probe concurrently.
        async let localResult   = localTokens(windowStart: windowStart)
        async let apiResult     = apiRateLimitHeaders()

        let (used, localReset) = await localResult
        let headers = try? await apiResult

        // Utilization from API gives us an auto-detected cap and accurate reset time.
        let utilization = headers?.utilization5h   // fraction 0–1
        let apiReset    = headers?.reset5h

        let cap: Double? = (utilization != nil && utilization! > 0)
            ? (used / utilization!)
            : nil

        return QuotaSnapshot(
            provider: .claude,
            used: used,
            cap: cap,
            unit: "tokens",
            resetsAt: apiReset ?? localReset,
            fetchedAt: Date(),
            error: nil
        )
    }

    // MARK: - Local JSONL parsing

    private func localTokens(windowStart: Date) async -> (Double, Date?) {
        let projectsURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/projects")
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsURL.path) else { return (0, nil) }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey]

        var totalTokens: Double = 0
        var oldestInWindow: Date?

        let projectDirs = (try? fm.contentsOfDirectory(
            at: projectsURL, includingPropertiesForKeys: nil
        )) ?? []

        for dir in projectDirs {
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let file = enumerator.nextObject() as? URL {
                guard file.pathExtension == "jsonl" else { continue }
                if let mod = (try? file.resourceValues(forKeys: resourceKeys))?.contentModificationDate,
                   mod < windowStart { continue }

                let (tokens, oldest) = parse(file: file, windowStart: windowStart, formatter: isoFormatter)
                totalTokens += tokens
                if let o = oldest {
                    oldestInWindow = oldestInWindow.map { Swift.min($0, o) } ?? o
                }
            }
        }

        let resetsAt = oldestInWindow.map { $0.addingTimeInterval(Self.windowDuration) }
        return (totalTokens, resetsAt)
    }

    private func parse(
        file: URL, windowStart: Date, formatter: ISO8601DateFormatter
    ) -> (Double, Date?) {
        var tokens: Double = 0
        var oldest: Date?
        for obj in JSONLReader.objects(at: file) {
            guard
                let tsStr = obj["timestamp"] as? String,
                let date  = formatter.date(from: tsStr),
                date >= windowStart
            else { continue }

            if let message = obj["message"] as? [String: Any],
               let usage   = message["usage"] as? [String: Any] {
                let input  = (usage["input_tokens"]                as? Double) ?? 0
                let output = (usage["output_tokens"]               as? Double) ?? 0
                let create = (usage["cache_creation_input_tokens"] as? Double) ?? 0
                tokens += input + output + create
            }
            oldest = oldest.map { Swift.min($0, date) } ?? date
        }
        return (tokens, oldest)
    }

    // MARK: - Anthropic API rate-limit probe

    private struct RateLimitHeaders {
        let utilization5h: Double
        let reset5h: Date?
    }

    private func apiRateLimitHeaders() async throws -> RateLimitHeaders {
        let token = try keychainAccessToken()

        var req = URLRequest(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            timeoutInterval: 8
        )
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)",  forHTTPHeaderField: "Authorization")
        req.setValue("2023-06-01",        forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model":      "claude-haiku-4-5",
            "max_tokens": 1,
            "messages":   [["role": "user", "content": "."]]
        ])

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ClaudeError.noResponse }

        let headers = http.allHeaderFields

        func header(_ key: String) -> String? {
            // Header names are case-insensitive; HTTPURLResponse lowercases them.
            headers[key] as? String ?? headers[key.lowercased()] as? String
        }

        let utilization = header("anthropic-ratelimit-unified-5h-utilization")
            .flatMap(Double.init) ?? 0
        let resetEpoch  = header("anthropic-ratelimit-unified-5h-reset")
            .flatMap(Double.init)
        let reset5h = resetEpoch.map { Date(timeIntervalSince1970: $0) }

        return RateLimitHeaders(utilization5h: utilization, reset5h: reset5h)
    }

    // MARK: - Keychain

    private func keychainAccessToken() throws -> String {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: "Claude Code-credentials",
            kSecAttrAccount: NSUserName(),
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw ClaudeError.noCredentials(status) }
        return token
    }

    enum ClaudeError: Error, LocalizedError {
        case noCredentials(OSStatus)
        case noResponse

        var errorDescription: String? {
            switch self {
            case .noCredentials(let s):
                return s == errSecItemNotFound
                    ? "Claude credentials not found — open Claude Code and sign in"
                    : "Keychain read failed (OSStatus \(s))"
            case .noResponse: return "No response from Anthropic API"
            }
        }
    }
}
