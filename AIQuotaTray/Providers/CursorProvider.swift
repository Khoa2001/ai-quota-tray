import Foundation
import Security
import SQLite3

struct CursorProvider: QuotaProvider {

    func fetch() async throws -> QuotaSnapshot {
        let token = try readToken()

        async let usageResp = rpc("GetCurrentPeriodUsage", token: token)
        async let planResp   = rpc("GetPlanInfo",          token: token)

        let (usage, plan) = try await (usageResp, planResp)

        let planUsage = usage["planUsage"] as? [String: Any]
        let planInfo  = plan["planInfo"]   as? [String: Any]

        // Percentage of the billing period's included budget consumed.
        let pct = (planUsage?["totalPercentUsed"] as? Double) ?? 0

        // Reset date comes directly from the response — no more +1 month arithmetic.
        var resetsAt: Date?
        if let msStr = (usage["billingCycleEnd"] as? String) ?? (planInfo?["billingCycleEnd"] as? String),
           let ms = Double(msStr) {
            resetsAt = Date(timeIntervalSince1970: ms / 1000)
        }

        return QuotaSnapshot(
            provider: .cursor,
            used: pct,
            cap: 100,
            unit: "%",
            resetsAt: resetsAt,
            fetchedAt: Date(),
            error: nil
        )
    }

    // MARK: - ConnectRPC helper

    private func rpc(_ method: String, token: String) async throws -> [String: Any] {
        let url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/\(method)")!
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)",  forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1",                forHTTPHeaderField: "Connect-Protocol-Version")
        req.httpBody = Data("{}".utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw CursorError.noResponse }

        if http.statusCode == 401 {
            // Try refreshing the token once and retry.
            if let fresh = try? await refreshedToken(expired: token) {
                var req2 = req
                req2.setValue("Bearer \(fresh)", forHTTPHeaderField: "Authorization")
                let (data2, _) = try await URLSession.shared.data(for: req2)
                guard let obj = try? JSONSerialization.jsonObject(with: data2) as? [String: Any] else {
                    throw CursorError.badResponse
                }
                return obj
            }
            throw CursorError.httpError(401)
        }

        guard http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CursorError.httpError(http.statusCode)
        }
        return obj
    }

    // MARK: - Token sources

    /// Reads the access token: state.vscdb (preferred) → Keychain fallback.
    private func readToken() throws -> String {
        if let token = tokenFromSQLite() { return token }
        return try tokenFromKeychain()
    }

    private func tokenFromSQLite() -> String? {
        let dbPath = "\(NSHomeDirectory())/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cursor_state_\(UUID().uuidString).db")
        guard (try? FileManager.default.copyItem(
            at: URL(fileURLWithPath: dbPath), to: tmp)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: tmp) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        let sql = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW,
              let cstr = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cstr)
    }

    private func tokenFromKeychain() throws -> String {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: "cursor-access-token",
            kSecAttrAccount: "cursor-user",
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw CursorError.noToken(status)
        }
        return token
    }

    // MARK: - Token refresh

    private func refreshedToken(expired: String) async throws -> String? {
        let dbPath = "\(NSHomeDirectory())/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cursor_state_\(UUID().uuidString).db")
        guard (try? FileManager.default.copyItem(at: URL(fileURLWithPath: dbPath), to: tmp)) != nil else {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        let sql = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/refreshToken' LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let cstr = sqlite3_column_text(stmt, 0) else { return nil }
        let refresh = String(cString: cstr)

        var req = URLRequest(url: URL(string: "https://api2.cursor.sh/oauth/token")!, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type":    "refresh_token",
            "client_id":     "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB",
            "refresh_token": refresh,
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["access_token"] as? String, !token.isEmpty else { return nil }
        return token
    }

    // MARK: - Errors

    enum CursorError: Error, LocalizedError {
        case noToken(OSStatus)
        case noResponse
        case httpError(Int)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noToken(let s):
                return s == errSecItemNotFound
                    ? "Not signed in to Cursor — open Cursor and sign in"
                    : "Keychain read failed (OSStatus \(s))"
            case .noResponse:        return "No response from Cursor API"
            case .httpError(let c):  return "Cursor API returned HTTP \(c)"
            case .badResponse:       return "Unexpected Cursor API response"
            }
        }
    }
}
