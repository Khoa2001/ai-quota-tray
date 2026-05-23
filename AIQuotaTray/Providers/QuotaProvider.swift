protocol QuotaProvider: Sendable {
    func fetch() async throws -> QuotaSnapshot
}
