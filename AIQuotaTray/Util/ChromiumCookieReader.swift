import Foundation
import SQLite3
import Security
import CommonCrypto

/// Reads and decrypts a named cookie from a Chromium-based browser's SQLite cookie store.
enum ChromiumCookieReader {

    static func readCursorSessionToken() throws -> String {
        let dbPath = "\(NSHomeDirectory())/Library/Application Support/Cursor/Cookies"
        let encrypted = try readEncryptedCookie(dbPath: dbPath, name: "WorkosCursorSessionToken")
        let password  = try keychainPassword(service: "Cursor Safe Storage", account: "Cursor")
        return try decryptV10(encrypted: encrypted, password: password)
    }

    // MARK: - SQLite

    private static func readEncryptedCookie(dbPath: String, name: String) throws -> Data {
        // Copy to temp so we don't hit Cursor's exclusive lock.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cursor_cookies_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: dbPath), to: tmp
        )

        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw CookieError.sqliteOpen
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT encrypted_value FROM cookies WHERE name = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CookieError.sqlitePrepare
        }
        defer { sqlite3_finalize(stmt) }

        name.withCString { sqlite3_bind_text(stmt, 1, $0, -1, nil) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw CookieError.cookieNotFound(name)
        }
        guard let blob = sqlite3_column_blob(stmt, 0) else {
            throw CookieError.emptyValue
        }
        let length = Int(sqlite3_column_bytes(stmt, 0))
        return Data(bytes: blob, count: length)
    }

    // MARK: - Keychain

    private static func keychainPassword(service: String, account: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw CookieError.keychainRead(status)
        }
        return password
    }

    // MARK: - Decryption

    /// Chromium macOS v10 format: "v10" prefix + AES-128-CBC(key=PBKDF2, iv=16×0x20)
    private static func decryptV10(encrypted: Data, password: String) throws -> String {
        let prefixBytes = 3 // "v10"
        guard encrypted.count > prefixBytes,
              encrypted.prefix(prefixBytes).elementsEqual("v10".utf8) else {
            return String(data: encrypted, encoding: .utf8) ?? ""
        }

        let ciphertext = encrypted.dropFirst(prefixBytes)
        let key = try pbkdf2(password: password, salt: "saltysalt", iterations: 1003, keyLength: 16)
        let iv  = Data(repeating: 0x20, count: 16) // 16 ASCII spaces

        var decrypted   = Data(count: ciphertext.count + kCCBlockSizeAES128)
        var decryptedLen = 0

        let status: CCCryptorStatus = key.withUnsafeBytes { keyBuf in
            iv.withUnsafeBytes { ivBuf in
                ciphertext.withUnsafeBytes { cipherBuf in
                    decrypted.withUnsafeMutableBytes { outBuf in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuf.baseAddress,    key.count,
                            ivBuf.baseAddress,
                            cipherBuf.baseAddress, ciphertext.count,
                            outBuf.baseAddress,    outBuf.count,
                            &decryptedLen
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { throw CookieError.decryptionFailed }
        guard let result = String(data: decrypted.prefix(decryptedLen), encoding: .utf8) else {
            throw CookieError.decodingFailed
        }
        return result
    }

    private static func pbkdf2(
        password: String, salt: String, iterations: Int, keyLength: Int
    ) throws -> Data {
        var key = Data(count: keyLength)
        let pwData   = password.data(using: .utf8)!
        let saltData = salt.data(using: .utf8)!

        let status: CCCryptorStatus = key.withUnsafeMutableBytes { keyBuf in
            pwData.withUnsafeBytes { pwBuf in
                saltData.withUnsafeBytes { saltBuf in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwBuf.baseAddress!.assumingMemoryBound(to: CChar.self),
                        pwData.count,
                        saltBuf.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        UInt32(iterations),
                        keyBuf.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        guard status == kCCSuccess else { throw CookieError.pbkdf2Failed }
        return key
    }

    // MARK: - Errors

    enum CookieError: Error, LocalizedError {
        case sqliteOpen
        case sqlitePrepare
        case cookieNotFound(String)
        case emptyValue
        case keychainRead(OSStatus)
        case decryptionFailed
        case decodingFailed
        case pbkdf2Failed

        var errorDescription: String? {
            switch self {
            case .sqliteOpen:           return "Cannot open Cursor cookie DB — grant Full Disk Access"
            case .sqlitePrepare:        return "SQLite prepare failed"
            case .cookieNotFound(let n):return "Cookie '\(n)' not found — log in to cursor.com"
            case .emptyValue:           return "Cookie value is empty"
            case .keychainRead(let s):  return "Keychain read failed (OSStatus \(s))"
            case .decryptionFailed:     return "Cookie decryption failed"
            case .decodingFailed:       return "Cookie UTF-8 decode failed"
            case .pbkdf2Failed:         return "PBKDF2 key derivation failed"
            }
        }
    }
}
