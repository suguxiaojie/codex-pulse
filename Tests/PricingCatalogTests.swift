import Foundation

@main
enum PricingCatalogTests {
    static func main() async {
        let rates = CatalogRates(
            displayName: "Test Model",
            inputPerMillion: 1,
            outputPerMillion: 2,
            cacheCreationPerMillion: 1.25,
            cacheReadPerMillion: 0.1
        )
        let payload = CatalogPayload(
            schemaVersion: 1,
            generatedAt: "2026-08-12T00:00:00Z",
            models: [
                "test-model": rates,
                "gpt-6-astra": rates,
                "gpt-6.1-sol": rates,
                "gpt-6-sol": rates,
                "gpt-6-luna": rates,
                "gpt-5.6-sol": rates,
            ]
        )
        let data = try! JSONEncoder().encode(payload)

        check(PricingCatalog.interpret(status: 200, data: data) == .payload(payload), "accept valid catalog")
        check(PricingCatalog.interpret(status: 304, data: Data()) == .unchanged, "accept 304")
        check(PricingCatalog.interpret(status: 500, data: data) == .rejected("HTTP 500"), "reject HTTP error")
        check(PricingCatalog.interpret(status: 200, data: Data("{}".utf8)) == .rejected("malformed JSON"), "reject malformed schema")
        check(ModelPricing.canonicalModelName("GPT-5.3-Codex-20260812") == "gpt-5.3-codex", "strip date suffix")
        check(ModelPricing.canonicalModelName("GPT-6.1-Sol-20260930") == "gpt-6.1-sol", "strip GPT-6.1 snapshot suffix")
        check(
            ModelPricing.resolvedRates(for: "gpt-6-astra")
                == CatalogRates(
                    displayName: nil,
                    inputPerMillion: 10,
                    outputPerMillion: 50,
                    cacheCreationPerMillion: 12.5,
                    cacheReadPerMillion: 1
                ),
            "Astra uses verified official rates"
        )
        check(
            ModelPricing.resolvedRates(for: "gpt-6.1-sol")
                == CatalogRates(
                    displayName: nil,
                    inputPerMillion: 2,
                    outputPerMillion: 10,
                    cacheCreationPerMillion: 2.5,
                    cacheReadPerMillion: 0.1
                ),
            "GPT-6.1 Sol uses verified official rates"
        )
        check(
            ModelPricing.resolvedRates(for: "gpt-6-sol")
                == CatalogRates(
                    displayName: nil,
                    inputPerMillion: 2,
                    outputPerMillion: 10,
                    cacheCreationPerMillion: 2.5,
                    cacheReadPerMillion: 0.2
                ),
            "GPT-6 Sol uses verified official rates"
        )
        check(
            ModelPricing.resolvedRates(for: "gpt-6-luna")
                == CatalogRates(
                    displayName: nil,
                    inputPerMillion: 0.1,
                    outputPerMillion: 0.5,
                    cacheCreationPerMillion: 0.125,
                    cacheReadPerMillion: 0.01
                ),
            "GPT-6 Luna uses verified official rates"
        )
        check(
            ModelPricing.resolvedRates(for: "gpt-5.6-sol")?.inputPerMillion == 4
                && ModelPricing.resolvedRates(for: "gpt-5.6-sol")?.outputPerMillion == 20,
            "Sol uses current official promotional rates"
        )
        check(
            ModelPricing.resolvedRates(for: "gpt-5.6-terra")?.inputPerMillion == 2
                && ModelPricing.resolvedRates(for: "gpt-5.6-terra")?.outputPerMillion == 12,
            "Terra uses current official rates"
        )
        check(
            ModelPricing.resolvedRates(for: "gpt-5.6-luna")?.inputPerMillion == 0.2
                && ModelPricing.resolvedRates(for: "gpt-5.6-luna")?.outputPerMillion == 1.2,
            "Luna uses current official rates"
        )
        check(ModelPricing.resolvedRates(for: "codex-auto-review") == nil, "do not invent unknown price")
        check(
            ModelPricing.billingModel(
                for: "codex-auto-review",
                currentPrimaryModel: "gpt-5.6-sol"
            ) == "gpt-5.6-sol",
            "attribute auto review to current primary model"
        )
        check(
            ModelPricing.billingModel(for: "unknown-model", currentPrimaryModel: "gpt-5.6-sol") == "unknown-model",
            "do not alias unrelated unknown models"
        )

        let temporaryCache = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-notch-catalog-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: temporaryCache) }
        let response = HTTPURLResponse(
            url: PricingCatalog.endpoint,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["ETag": "test-etag"]
        )!
        let firstRefresh = await PricingCatalog.refreshIfNeeded(
            now: Date(timeIntervalSince1970: 1_800_000_000),
            cache: temporaryCache,
            fetch: { _ in (data, response) }
        )
        check(firstRefresh == .updated, "install downloaded catalog")
        check(FileManager.default.fileExists(atPath: temporaryCache.path), "persist catalog cache")
        check(ModelPricing.resolvedRates(for: "test-model") == rates, "remote catalog supplies other models")
        check(
            ModelPricing.resolvedRates(for: "gpt-6-astra")?.inputPerMillion == 10,
            "community catalog cannot override official Astra rates"
        )
        check(
            ModelPricing.resolvedRates(for: "gpt-5.6-sol")?.outputPerMillion == 20,
            "community catalog cannot override official Sol rates"
        )
        check(
            ModelPricing.resolvedRates(for: "gpt-6.1-sol")?.cacheReadPerMillion == 0.1,
            "community catalog cannot override official GPT-6.1 Sol rates"
        )
        check(
            ModelPricing.resolvedRates(for: "gpt-6-sol")?.cacheReadPerMillion == 0.2
                && ModelPricing.resolvedRates(for: "gpt-6-luna")?.outputPerMillion == 0.5,
            "community catalog cannot override official GPT-6 Sol or Luna rates"
        )
        check(
            ModelPricing.multipliers(
                for: "gpt-6-astra",
                totalInputTokens: ModelPricing.longContextThreshold
            ) == .standard,
            "long-context surcharge starts above the threshold"
        )
        check(
            ModelPricing.multipliers(
                for: "gpt-6-astra",
                totalInputTokens: ModelPricing.longContextThreshold + 1
            ) == ModelPricing.Multipliers(inputAndCache: 2, output: 1.5),
            "Astra applies official long-context multipliers"
        )
        check(
            ModelPricing.multipliers(
                for: "gpt-6.1-sol",
                totalInputTokens: ModelPricing.longContextThreshold + 1
            ) == ModelPricing.Multipliers(inputAndCache: 2, output: 1.5),
            "GPT-6.1 Sol applies official long-context multipliers"
        )
        check(
            ModelPricing.multipliers(for: "test-model", totalInputTokens: 1_000_000) == .standard,
            "catalog models do not inherit an undocumented surcharge"
        )

        await testOfficialPricing()
        print("Pricing catalog tests passed (official refresh and fallback checks included).")
    }

    private static func testOfficialPricing() async {
        let currentDocument = try! String(contentsOfFile: "Tests/Fixtures/official-standard-pricing-2026-10.md", encoding: .utf8)
        let current = OfficialPricingCatalog.parse(currentDocument)
        check(current?.rates.count == 8, "accept current official table including GPT-6.1 Terra")
        check(current?.rates["gpt-6.1-sol"]?.inputPerMillion == 2
            && current?.rates["gpt-6.1-sol"]?.outputPerMillion == 10
            && current?.rates["gpt-6.1-sol"]?.cacheReadPerMillion == 0.1
            && current?.rates["gpt-6.1-sol"]?.cacheCreationPerMillion == 2.5,
            "new column order maps correctly and preserves 30m cache-write pricing")
        check(current?.rates["gpt-6.1-terra"]?.outputPerMillion == 5, "new official model has current rates")
        check(current?.multipliers["gpt-6.1-terra"] == .init(inputAndCache: 2, output: 1.5), "new model has documented long-context ratios")
        let reordered = currentDocument.components(separatedBy: "\n").map { line -> String in
            let cells = line.split(separator: "|", omittingEmptySubsequences: false)
            guard line.hasPrefix("|"), cells.count == 13 else { return line }
            let values = Array(cells.dropFirst().dropLast())
            return "|" + ([values[0]] + values.dropFirst().reversed()).joined(separator: "|") + "|"
        }.joined(separator: "\n")
        check(OfficialPricingCatalog.parse(reordered) == current, "column names rather than offsets determine prices")
        check(OfficialPricingCatalog.parse(currentDocument.replacingOccurrences(of: "12h write", with: "30m write")) == nil,
            "ambiguous duplicate headers are rejected")
        check(OfficialPricingCatalog.parse(currentDocument.replacingOccurrences(of: "| $25.00 | $20.00 |", with: "| $NaN | $20.00 |")) == nil,
            "invalid unused 12h prices still reject the document")
        let document = try! String(contentsOfFile: "Tests/Fixtures/official-standard-pricing.md", encoding: .utf8)
        let parsed = OfficialPricingCatalog.parse(document)
        check(parsed?.rates.count == 7, "parse all supported official Standard models")
        check(parsed?.rates["gpt-6.1-sol"]?.inputPerMillion == 2, "Batch data cannot override Standard")
        check(parsed?.multipliers["gpt-6.1-sol"] == .init(inputAndCache: 2, output: 1.5), "read long-context ratios")
        check(OfficialPricingCatalog.parse(document.replacingOccurrences(of: "### Standard pricing data", with: "### Batch pricing data")) == nil, "reject missing Standard section")
        check(OfficialPricingCatalog.parse(document.replacingOccurrences(of: "Short context cached input", with: "Other price")) == nil, "reject changed header schema")
        check(OfficialPricingCatalog.parse(document.replacingOccurrences(of: "| gpt-6-astra |", with: "| missing-model |")) == nil, "reject incomplete official model set")
        check(OfficialPricingCatalog.parse(document.replacingOccurrences(of: "$10.00", with: "$NaN")) == nil, "reject nonfinite prices")
        check(OfficialPricingCatalog.parse(document.replacingOccurrences(of: "$10.00", with: "$-10.00")) == nil, "reject negative prices")
        check(OfficialPricingCatalog.parse(document.replacingOccurrences(of: "≤272K", with: "≤300K")) == nil, "reject unrecognized long-context boundary")
        let line = document.split(separator: "\n").first { $0.hasPrefix("| gpt-6-astra |") }!
        check(OfficialPricingCatalog.parse(document.replacingOccurrences(of: "### Batch", with: String(line) + "\n### Batch")) == nil, "reject duplicate model rows")
        let cache = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".tmp/test-runtime/official-pricing-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cache) }
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        func response(_ status: Int) -> HTTPURLResponse {
            HTTPURLResponse(url: OfficialPricingCatalog.endpoint, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["ETag": "official-test"])!
        }
        let empty304 = await OfficialPricingCatalog.refreshIfNeeded(now: start, cache: cache, fetch: { _ in (Data(), response(304)) })
        check(empty304 == .failed, "304 without a usable official cache is not success")
        let updatedDocument = document.replacingOccurrences(of: "| gpt-6.1-sol | $2.00 | $0.10 | $2.50 | $10.00 | $4.00 | $0.20 | $5.00 | $15.00 |", with: "| gpt-6.1-sol | $3.00 | $0.10 | $2.50 | $10.00 | $9.00 | $0.30 | $7.50 | $15.00 |")
        let updated = await OfficialPricingCatalog.refreshIfNeeded(now: start.addingTimeInterval(6 * 3600), cache: cache, fetch: { _ in (Data(updatedDocument.utf8), response(200)) })
        check(updated == .updated, "install successfully parsed official prices")
        check(ModelPricing.resolvedRates(for: "gpt-6.1-sol")?.inputPerMillion == 3, "online official price overrides bundled snapshot and community")
        check(ModelPricing.multipliers(for: "gpt-6.1-sol", totalInputTokens: 272001).inputAndCache == 3, "updated official long-context ratio affects calculation")
        check(ModelPricing.resolvedRates(for: "gpt-5.6")?.outputPerMillion == 20, "legacy alias retains the supported official Sol mapping")
        let savedStatus = OfficialPricingCatalog.statusText
        let throttled = await OfficialPricingCatalog.refreshIfNeeded(now: start.addingTimeInterval(7 * 3600), cache: cache, fetch: { _ in fatalError("fresh prices must not trigger a network request") })
        check(throttled == .notNeeded, "successful official sync is reused for 24 hours")
        let malformed = await OfficialPricingCatalog.refreshIfNeeded(now: start.addingTimeInterval(31 * 3600), cache: cache, fetch: { _ in (Data("bad document".utf8), response(200)) })
        check(malformed == .failed, "malformed page cannot replace effective rates")
        check(ModelPricing.resolvedRates(for: "gpt-6.1-sol")?.inputPerMillion == 3, "last valid official price survives parse failure")
        check(OfficialPricingCatalog.statusText.hasPrefix(savedStatus), "failure does not advance the successful-sync timestamp")
        let notModified = await OfficialPricingCatalog.refreshIfNeeded(now: start.addingTimeInterval(38 * 3600), cache: cache, fetch: { request in
            check(request.value(forHTTPHeaderField: "If-None-Match") == "official-test", "send conditional ETag")
            return (Data(), response(304))
        })
        check(notModified == .unchanged, "304 revalidates an existing official snapshot")
        check(!OfficialPricingCatalog.statusText.contains("更新失败"), "successful revalidation clears the error status")
        check(FileManager.default.fileExists(atPath: cache.path), "official prices persist outside account/session storage")
        let noETagResponse = HTTPURLResponse(url: OfficialPricingCatalog.endpoint, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        let withoutETag = await OfficialPricingCatalog.refreshIfNeeded(now: start.addingTimeInterval(63 * 3600), cache: cache, fetch: { _ in (Data(updatedDocument.utf8), noETagResponse) })
        check(withoutETag == .updated, "accept valid newer document without an ETag")
        let afterClearedETag = await OfficialPricingCatalog.refreshIfNeeded(now: start.addingTimeInterval(88 * 3600), cache: cache, fetch: { request in
            check(request.value(forHTTPHeaderField: "If-None-Match") == nil, "new 200 response without ETag clears obsolete conditional tag")
            return (Data(updatedDocument.utf8), noETagResponse)
        })
        check(afterClearedETag == .updated, "continue updating after the server drops ETags")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) {
        guard condition() else {
            fputs("FAILED: \(label)\n", stderr)
            exit(1)
        }
    }
}
