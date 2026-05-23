import Foundation

enum JSONLReader {
    /// Lazily parse every line of a JSONL file into dictionaries.
    static func objects(at url: URL) -> [[String: Any]] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> [String: Any]? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
    }
}
