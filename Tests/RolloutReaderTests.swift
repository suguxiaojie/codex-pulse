import Foundation

@main
struct RolloutReaderTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ reason: String) {
        checks += 1; if !condition() { fatalError(reason) }
    }
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".tmp/rollout-reader-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = URL(fileURLWithPath: "Tests/Fixtures/CompressedRollouts/user.jsonl.zst")
        let bytes = try Data(contentsOf: fixture)
        var decoded = Data()
        try RolloutReader.stream(at: fixture) { decoded.append($0) }
        expect(String(data: decoded, encoding: .utf8)?.contains("Compressed user fixture") == true, "unknown-size frame streams correctly")
        let plain = root.appendingPathComponent("user.jsonl")
        try decoded.write(to: plain)
        let zipped = root.appendingPathComponent("user.jsonl.zst")
        try bytes.write(to: zipped)
        expect(RolloutReader.preferredFiles([zipped, plain]) == [plain], "plain mirror wins without decoding twice")
        var lines: [Data] = []
        try RolloutReader.forEachLine(at: fixture) { lines.append($0) }
        expect(lines.count == 3, "decoded line boundaries preserved")
        let concatenated = root.appendingPathComponent("joined.jsonl.zst")
        try (bytes + bytes).write(to: concatenated)
        var total = 0
        try RolloutReader.stream(at: concatenated) { total += $0.count }
        expect(total == decoded.count * 2, "concatenated frames are consumed")
        let truncated = root.appendingPathComponent("truncated.jsonl.zst")
        try bytes.dropLast(4).write(to: truncated)
        do { try RolloutReader.stream(at: truncated) { _ in }; fatalError("truncated frame accepted") } catch { checks += 1 }
        let corrupt = root.appendingPathComponent("corrupt.jsonl.zst")
        try Data("not zstd".utf8).write(to: corrupt)
        do { try RolloutReader.stream(at: corrupt) { _ in }; fatalError("corrupt frame accepted") } catch { checks += 1 }
        do { try RolloutReader.stream(at: fixture, maximumDecodedBytes: 10) { _ in }; fatalError("decoded size limit ignored") } catch { checks += 1 }
        let long = URL(fileURLWithPath: "Tests/Fixtures/CompressedRollouts/long.jsonl.zst")
        let sample = try RolloutReader.headAndTail(at: long, headLimit: 512 * 1024, tailLimit: 1024 * 1024)
        expect(sample.head.count + sample.tail.count <= 1536 * 1024 && sample.total > 2_000_000, "large preview retains only bounded head and tail")
        var kept = 0
        try RolloutReader.forEachLine(at: long) { _ in kept += 1 }
        expect(kept == 3, "oversized record skipped without losing trailing line")
        do { try RolloutReader.forEachLine(at: long, skipOversized: false) { _ in }; fatalError("strict export silently skipped a large record") } catch { checks += 1 }
        let copy = root.appendingPathComponent("export.jsonl")
        try RolloutReader.copyDecoded(from: fixture, to: copy)
        expect(try! Data(contentsOf: copy) == decoded, "explicit export copy contains decoded bytes")
        do { try RolloutReader.copyDecoded(from: fixture, to: copy); fatalError("copy overwrote destination") } catch { checks += 1 }
        expect(try! Data(contentsOf: fixture) == bytes, "source compressed bytes unchanged")
        print("Rollout reader: \(checks) checks passed")
    }
}
