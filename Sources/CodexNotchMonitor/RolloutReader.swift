import Foundation
import CZstdDecoder
import Darwin

/// Read-only access to plain and Zstandard rollouts. Decoded bytes stay in memory
/// or an explicit caller-owned export destination, never alongside source files.
enum RolloutReader {
    struct ReadError: LocalizedError {
        let reason: String
        var errorDescription: String? { "会话日志读取失败：" + reason }
    }
    static func isRollout(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(".jsonl") || url.lastPathComponent.hasSuffix(".jsonl.zst")
    }
    static func isCompressed(_ url: URL) -> Bool { url.lastPathComponent.hasSuffix(".jsonl.zst") }
    static func plainFilename(_ url: URL) -> String {
        isCompressed(url) ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
    }
    /// Skip a compressed mirror when its plain file exists; the session/event
    /// identity checks in the services still deduplicate across archive roots.
    static func preferredFiles(_ urls: [URL]) -> [URL] {
        let paths = Set(urls.filter { !isCompressed($0) }.map(\.path))
        return urls.filter { !isCompressed($0) || !paths.contains($0.deletingPathExtension().path) }
    }
    static func stream(at url: URL, maximumDecodedBytes: Int = 8 * 1_024 * 1_024 * 1_024,
                       progress: ((Int64, Int64) -> Void)? = nil, chunk: (Data) throws -> Void) throws {
        guard maximumDecodedBytes >= 0 else { throw ReadError(reason: "读取上限无效") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        var processed: Int64 = 0, decoded = 0
        progress?(0, size)
        guard isCompressed(url) else {
            while try autoreleasepool(invoking: { () throws -> Bool in
                guard let bytes = try handle.read(upToCount: 128 * 1_024), !bytes.isEmpty else { return false }
                guard decoded <= maximumDecodedBytes - bytes.count else { throw ReadError(reason: "解压后数据超过读取上限") }
                decoded += bytes.count; processed += Int64(bytes.count)
                try chunk(bytes); progress?(processed, size)
                return true
            }) {}
            progress?(processed, size)
            return
        }
        guard let context = ZSTD_createDStream() else { throw ReadError(reason: "无法创建解码器") }
        defer { ZSTD_freeDStream(context) }
        // Limit the frame's declared window to 128 MiB, independently of output.
        let configured = ZSTD_DCtx_setParameter(context, ZSTD_d_windowLogMax, 27)
        guard ZSTD_isError(configured) == 0 else { throw ReadError(reason: "无法设置解码窗口") }
        var output = [UInt8](repeating: 0, count: 128 * 1_024)
        var remaining = 1, sawInput = false
        while try autoreleasepool(invoking: { () throws -> Bool in
            guard let bytes = try handle.read(upToCount: 128 * 1_024), !bytes.isEmpty else { return false }
            sawInput = true
            try bytes.withUnsafeBytes { inputBytes in
                var input = ZSTD_inBuffer(src: inputBytes.baseAddress, size: bytes.count, pos: 0)
                var produced = 0
                repeat {
                    let oldPosition = input.pos
                    produced = 0
                    remaining = output.withUnsafeMutableBytes { destination in
                        var out = ZSTD_outBuffer(dst: destination.baseAddress, size: destination.count, pos: 0)
                        let result = ZSTD_decompressStream(context, &out, &input)
                        produced = out.pos
                        return result
                    }
                    guard ZSTD_isError(remaining) == 0 else { throw ReadError(reason: "压缩记录损坏或格式不支持") }
                    guard decoded <= maximumDecodedBytes - produced else { throw ReadError(reason: "解压后数据超过读取上限") }
                    decoded += produced
                    if produced > 0 {
                        // A small compressed block can produce many output blocks.
                        // Drain callback temporaries at the decoded-block boundary too.
                        try autoreleasepool {
                            let data = output.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: produced) }
                            try chunk(data)
                        }
                    }
                    if input.pos == oldPosition && produced == 0 {
                        if input.pos == input.size { break }
                        throw ReadError(reason: "压缩记录无法继续解码")
                    }
                } while input.pos < input.size || (remaining > 0 && produced == output.count)
            }
            processed += Int64(bytes.count); progress?(processed, size)
            return true
        }) {}
        guard sawInput, remaining == 0 else { throw ReadError(reason: "压缩记录为空或未完整写入") }
        progress?(processed, size)
    }

    static func forEachLine(at url: URL, maximumLineBytes: Int = 1 << 20, skipOversized: Bool = true,
                            progress: ((Int64, Int64) -> Void)? = nil, line: (Data) throws -> Void) throws {
        var pending = Data(), dropping = false
        let newline = Data([0x0A])
        try stream(at: url, progress: progress) { bytes in
            var start = bytes.startIndex
            while start < bytes.endIndex {
                let end = bytes.range(of: newline, in: start..<bytes.endIndex)?.lowerBound
                let fragment = bytes[start..<(end ?? bytes.endIndex)]
                if !dropping {
                    if pending.count + fragment.count > maximumLineBytes {
                        guard skipOversized else { throw ReadError(reason: "单条会话记录超过读取上限") }
                        pending.removeAll(keepingCapacity: true); dropping = true
                    } else { pending.append(fragment) }
                }
                if let end {
                    if !dropping && !pending.isEmpty { try line(pending) }
                    pending.removeAll(keepingCapacity: true); dropping = false
                    start = end + 1
                } else { break }
            }
        }
        if !dropping && !pending.isEmpty { try line(pending) }
    }
    static func headAndTail(at url: URL, headLimit: Int, tailLimit: Int) throws -> (head: Data, tail: Data, total: Int) {
        var head = Data(), tail = Data(), total = 0
        try stream(at: url) { bytes in
            total += bytes.count
            if head.count < headLimit { head.append(bytes.prefix(headLimit - head.count)) }
            tail.append(bytes)
            if tail.count > tailLimit { tail = tail.subdata(in: (tail.endIndex - tailLimit)..<tail.endIndex) }
        }
        // Do not parse overlapping chunks twice when the decoded file is small.
        if total <= headLimit + tailLimit {
            let overlap = max(0, head.count + tail.count - total)
            if overlap > 0 { tail.removeFirst(overlap) }
        }
        return (head, tail, total)
    }
    static func copyDecoded(from source: URL, to destination: URL) throws {
        let fd = open(destination.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteFileExists) }
        let target = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? target.close() }
        try stream(at: source) { try target.write(contentsOf: $0) }
    }
}
