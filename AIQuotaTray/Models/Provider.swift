import Foundation

enum Provider: String, CaseIterable, Identifiable, Hashable {
    case claude = "Claude"
    case codex  = "Codex"
    case cursor = "Cursor"

    var id: String { rawValue }
}
