import Foundation

enum ModelPricing {
    typealias Rates = CatalogRates

    struct Multipliers: Equatable {
        let inputAndCache: Double
        let output: Double

        static let standard = Multipliers(inputAndCache: 1, output: 1)
    }

    /// OpenAI Docs prices verified on 2026-10-29; cache writes use the 30m rate. These entries take
    /// precedence over the community catalog so an older third-party value
    /// cannot override a current first-party rate. The catalog still fills in
    /// models that are not represented in this official snapshot.
    private static let official: [String: Rates] = [
        "gpt-6-astra": rates(10, 50, 12.5, 1),
        "gpt-6.1-sol": rates(2, 10, 2.5, 0.1),
        "gpt-6.1-terra": rates(1, 5, 1.25, 0.05),
        "gpt-6-sol": rates(2, 10, 2.5, 0.2),
        "gpt-6-luna": rates(0.1, 0.5, 0.125, 0.01),
        "gpt-5.6": rates(4, 20, 5, 0.4),
        "gpt-5.6-sol": rates(4, 20, 5, 0.4),
        "gpt-5.6-terra": rates(2, 12, 2.5, 0.2),
        "gpt-5.6-luna": rates(0.2, 1.2, 0.25, 0.02),
    ]

    private static let longContextModels: Set<String> = [
        "gpt-6-astra",
        "gpt-6.1-sol",
        "gpt-6.1-terra",
        "gpt-6-sol",
        "gpt-6-luna",
        "gpt-5.6",
        "gpt-5.6-sol",
        "gpt-5.6-terra",
        "gpt-5.6-luna",
    ]

    static let longContextThreshold = 272_000
    static let officialRateVerifiedAt = "2026-10-29"

    /// Codex-only build-time fallback. The daily catalog takes precedence and
    /// can add or update models without requiring an app release.
    private static let seed: [String: Rates] = [
        "gpt-5.6": rates(5, 30, 6.25, 0.50),
        "gpt-5.6-sol": rates(5, 30, 6.25, 0.50),
        "gpt-5.6-terra": rates(2.5, 15, 3.125, 0.25),
        "gpt-5.6-luna": rates(1, 6, 1.25, 0.10),
        "gpt-5.5": rates(5, 30, 5, 0.50),
        "gpt-5.4": rates(2.5, 15, 2.5, 0.25),
        "gpt-5.2": rates(1.75, 14, 1.75, 0.175),
        "gpt-5.1": rates(1.25, 10, 1.25, 0.125),
        "gpt-5": rates(1.25, 10, 1.25, 0.125),
        "gpt-5.3-codex": rates(1.75, 14, 1.75, 0.175),
        "gpt-5.2-codex": rates(1.75, 14, 1.75, 0.175),
        "gpt-5.1-codex": rates(1.25, 10, 1.25, 0.125),
        "gpt-5.1-codex-max": rates(1.25, 10, 1.25, 0.125),
        "gpt-5.1-codex-mini": rates(0.25, 2, 0.25, 0.025),
        "gpt-5-codex": rates(1.25, 10, 1.25, 0.125),
        "gpt-5.4-mini": rates(0.75, 4.5, 0.75, 0.075),
        "gpt-5.4-nano": rates(0.2, 1.25, 0.2, 0.02),
        "gpt-5-mini": rates(0.25, 2, 0.25, 0.025),
        "gpt-5-nano": rates(0.05, 0.4, 0.05, 0.005),
        "gpt-5.5-pro": rates(30, 180, 30, 3),
        "gpt-5.4-pro": rates(30, 180, 30, 3),
        "gpt-5.2-pro": rates(21, 168, 21, 0),
        "gpt-5-pro": rates(15, 120, 15, 0),
    ]

    static func resolvedRates(for rawModel: String) -> Rates? {
        let canonical = canonicalModelName(rawModel)
        return OfficialPricingCatalog.rates(for: canonical) ?? official[canonical] ?? PricingCatalog.rates(for: canonical) ?? seed[canonical]
    }

    static func multipliers(for rawModel: String, totalInputTokens: Int) -> Multipliers {
        let canonical = canonicalModelName(rawModel)
        if let refreshed = OfficialPricingCatalog.multipliers(for: canonical, totalInputTokens: totalInputTokens) { return refreshed }
        guard totalInputTokens > longContextThreshold,
              longContextModels.contains(canonical)
        else { return .standard }
        return Multipliers(inputAndCache: 2, output: 1.5)
    }

    static func isInternalAutomaticModel(_ rawModel: String) -> Bool {
        canonicalModelName(rawModel) == "codex-auto-review"
    }

    /// Codex writes automatic review work under a routing name rather than a
    /// public billable model id. Attribute that work to the primary model in
    /// effect beside it in the local timeline, as requested by the user.
    static func billingModel(for rawModel: String, currentPrimaryModel: String?) -> String {
        guard isInternalAutomaticModel(rawModel), let currentPrimaryModel else {
            return rawModel
        }
        return currentPrimaryModel
    }

    static func canonicalModelName(_ rawModel: String) -> String {
        let raw = rawModel.lowercased()
        guard raw.count > 9 else { return raw }
        let suffixStart = raw.index(raw.endIndex, offsetBy: -9)
        let suffix = raw[suffixStart...]
        guard suffix.first == "-", suffix.dropFirst().allSatisfy(\.isNumber) else {
            return raw
        }
        return String(raw[..<suffixStart])
    }

    private static func rates(_ input: Double, _ output: Double, _ create: Double, _ read: Double) -> Rates {
        Rates(
            displayName: nil,
            inputPerMillion: input,
            outputPerMillion: output,
            cacheCreationPerMillion: create,
            cacheReadPerMillion: read
        )
    }
}


/// Reads only the Standard table from OpenAI's public Markdown pricing page.
/// A failed download or a changed schema never replaces the last usable rates.
enum OfficialPricingCatalog {
    static let endpoint = URL(string: "https://developers.openai.com/api/docs/pricing.md")!
    static let requiredModels: Set<String> = ["gpt-6-astra", "gpt-6.1-sol", "gpt-6-sol", "gpt-6-luna", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]

    struct Snapshot: Equatable {
        let rates: [String: CatalogRates]
        let multipliers: [String: ModelPricing.Multipliers]
        let threshold: Int
    }

    private struct Cache: Codable {
        let document: String
        let fetchedAt: Date
        let etag: String?
    }

    private static let lock = NSLock()
    private static var snapshot: Snapshot?
    private static var cached: Cache?
    private static var loaded = false
    private static var refreshing = false
    private static var lastAttempt: Date?
    private static var failed = false

    static func cacheURL() -> URL? {
        PricingCatalog.cacheURL()?.deletingLastPathComponent().appendingPathComponent("official-model-prices.json")
    }

    static func prepare(cache: URL? = cacheURL()) {
        lock.lock()
        defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true
        guard let cache, let data = try? Data(contentsOf: cache), data.count <= 1_024 * 1_024,
              let restored = try? JSONDecoder().decode(Cache.self, from: data),
              let parsed = parse(restored.document)
        else { return }
        cached = restored
        snapshot = parsed
    }

    static func rates(for model: String) -> CatalogRates? {
        lock.lock(); defer { lock.unlock() }
        return snapshot?.rates[model == "gpt-5.6" ? "gpt-5.6-sol" : model]
    }

    static func multipliers(for model: String, totalInputTokens: Int) -> ModelPricing.Multipliers? {
        lock.lock(); defer { lock.unlock() }
        let model = model == "gpt-5.6" ? "gpt-5.6-sol" : model
        guard let snapshot, snapshot.rates[model] != nil else { return nil }
        return totalInputTokens > snapshot.threshold ? snapshot.multipliers[model] : .standard
    }

    static var syncStatus: (date: Date?, failed: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (cached?.fetchedAt, failed)
    }

    static var statusText: String {
        lock.lock(); defer { lock.unlock() }
        if let stamp = cached?.fetchedAt {
            return "OpenAI 官方 Standard 费率 · 同步于 " + dateLabel(stamp)
                + (failed ? " · 更新失败，沿用上次费率" : "")
        }
        return "内置官方费率 · 核验于 " + ModelPricing.officialRateVerifiedAt
            + (failed ? " · 在线更新失败" : " · 等待在线同步")
    }

    static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static func parse(_ document: String) -> Snapshot? {
        guard document.utf8.count <= 512 * 1_024,
              let heading = document.range(of: "### Standard pricing data"),
              let end = document.range(of: "### ", range: heading.upperBound..<document.endIndex),
              document.contains("Short context: ≤272K input tokens. Long context: >272K input tokens.")
        else { return nil }
        let table = String(document[heading.upperBound..<end.lowerBound])
        func fields(_ line: Substring) -> [String] {
            line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast()
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let lines = table.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let headerLine = lines.first(where: { $0.hasPrefix("|") && fields(Substring($0)).contains("Model") }) else { return nil }
        let header = fields(Substring(headerLine))
        let common = ["Model", "Short context input", "Short context cached input", "Short context output",
                      "Long context input", "Long context cached input", "Long context output"]
        let legacy = Set(common + ["Short context cache writes", "Long context cache writes"])
        let current = Set(common + ["Short context 30m write", "Long context 30m write",
                                    "Short context 12h write", "Long context 12h write"])
        guard Set(header).count == header.count, Set(header) == legacy || Set(header) == current else { return nil }
        let columns = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset) })
        let write = Set(header) == legacy ? "cache writes" : "30m write"
        let names = ["Short context input", "Short context cached input", "Short context \(write)", "Short context output",
                     "Long context input", "Long context cached input", "Long context \(write)", "Long context output"]
        let supported = requiredModels.union(["gpt-6.1-terra"])
        var rates: [String: CatalogRates] = [:]
        var multipliers: [String: ModelPricing.Multipliers] = [:]
        for line in lines where line.hasPrefix("|") {
            let cells = fields(Substring(line))
            guard let modelIndex = columns["Model"], cells.indices.contains(modelIndex), supported.contains(cells[modelIndex]) else { continue }
            let model = cells[modelIndex]
            guard cells.count == header.count, rates[model] == nil else { return nil }
            func price(_ field: String) -> Double? {
                guard field.first == "$", let value = Double(field.dropFirst()), value.isFinite, value >= 0, value <= 1_000_000 else { return nil }
                return value
            }
            guard cells.enumerated().allSatisfy({ $0.offset == modelIndex || price($0.element) != nil }) else { return nil }
            let values = names.compactMap { columns[$0].flatMap { price(cells[$0]) } }
            guard values.count == 8, values[0] > 0, values[3] > 0 else { return nil }
            let inputRatio = values[4] / values[0]
            let outputRatio = values[7] / values[3]
            guard (1...10).contains(inputRatio), (1...10).contains(outputRatio),
                  abs(values[5] - values[1] * inputRatio) < 0.000_001,
                  abs(values[6] - values[2] * inputRatio) < 0.000_001
            else { return nil }
            let rate = CatalogRates(displayName: nil, inputPerMillion: values[0], outputPerMillion: values[3], cacheCreationPerMillion: values[2], cacheReadPerMillion: values[1])
            guard rate.isValid else { return nil }
            rates[model] = rate
            multipliers[model] = .init(inputAndCache: inputRatio, output: outputRatio)
        }
        guard requiredModels.isSubset(of: Set(rates.keys)) else { return nil }
        return Snapshot(rates: rates, multipliers: multipliers, threshold: 272_000)
    }

    private struct Context { let etag: String? }
    private static func begin(at now: Date) -> Context? {
        lock.lock(); defer { lock.unlock() }
        guard !refreshing else { return nil }
        if let last = cached?.fetchedAt, (0..<PricingCatalog.refreshInterval).contains(now.timeIntervalSince(last)) { return nil }
        if let lastAttempt, (0..<PricingCatalog.retryInterval).contains(now.timeIntervalSince(lastAttempt)) { return nil }
        refreshing = true
        lastAttempt = now
        return Context(etag: cached?.etag)
    }

    private static func finish(success: Bool?) {
        lock.lock(); defer { lock.unlock() }
        refreshing = false
        if let success { failed = !success }
    }

    private static func install(document: String?, etag: String?, at now: Date, cache: URL?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let text = document ?? cached?.document
        guard let text, let parsed = parse(text) else { return false }
        let replacement = Cache(document: text, fetchedAt: now, etag: document == nil ? cached?.etag : etag)
        snapshot = parsed
        cached = replacement
        if let cache, let data = try? JSONEncoder().encode(replacement) { try? data.write(to: cache, options: .atomic) }
        return true
    }

    static func refreshIfNeeded(
        now: Date = Date(),
        cache: URL? = cacheURL(),
        fetch: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) async -> CatalogRefreshResult {
        guard let context = begin(at: now) else { return .notNeeded }
        var succeeded = false
        defer { finish(success: succeeded) }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/markdown", forHTTPHeaderField: "Accept")
        if let etag = context.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        guard let (data, response) = try? await fetch(request), let http = response as? HTTPURLResponse,
              http.url?.host == endpoint.host, http.url?.path == endpoint.path
        else { return .failed }
        if http.statusCode == 304 {
            succeeded = install(document: nil, etag: nil, at: now, cache: cache)
            return succeeded ? .unchanged : .failed
        }
        guard http.statusCode == 200, data.count <= 512 * 1_024, let text = String(data: data, encoding: .utf8) else { return .failed }
        succeeded = install(document: text, etag: http.value(forHTTPHeaderField: "ETag"), at: now, cache: cache)
        return succeeded ? .updated : .failed
    }
}
