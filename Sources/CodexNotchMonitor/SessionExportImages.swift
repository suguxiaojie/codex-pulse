import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Readable-export assets only. Never mutates session logs or recoverable backups.
final class SessionExportImages {
    private struct Asset {
        let data: Data
        let width: Int
        let height: Int
        let filename: String
    }
    private enum Resolution { case available(Asset), unavailable(String) }
    private let outputURL: URL
    private let embedded: Bool
    private var cache: [String: Resolution] = [:]
    private var pending: [String: Data] = [:]
    private var totalBytes = 0
    private var createdFiles: [URL] = []
    private var createdDirectory = false
    private var committed = false
    private var assetDirectory: URL {
        outputURL.deletingLastPathComponent().appendingPathComponent(
            outputURL.deletingPathExtension().lastPathComponent + ".assets", isDirectory: true
        )
    }

    init(outputURL: URL, embedded: Bool) { self.outputURL = outputURL; self.embedded = embedded }
    deinit {
        if !committed {
            for file in createdFiles { try? FileManager.default.removeItem(at: file) }
            if createdDirectory,
               (try? FileManager.default.contentsOfDirectory(atPath: assetDirectory.path).isEmpty) == true {
                try? FileManager.default.removeItem(at: assetDirectory)
            }
        }
    }

    static func sources(from object: [String: Any]) -> [String] {
        guard let payload = object["payload"] as? [String: Any] else { return [] }
        let eventUser = object["type"] as? String == "event_msg" && payload["type"] as? String == "user_message"
        let responseUser = object["type"] as? String == "response_item" && payload["type"] as? String == "message" && payload["role"] as? String == "user"
        guard eventUser || responseUser else { return [] }
        var structured: [String] = []
        for part in payload["content"] as? [[String: Any]] ?? [] {
            guard ["input_image", "image", "localImage", "local_image"].contains(part["type"] as? String ?? "") else { continue }
            let value = part["image_url"] ?? part["url"] ?? part["path"]
            if let source = value as? String { structured.append(source) }
            else if let source = (value as? [String: Any])?["url"] as? String { structured.append(source) }
            else { structured.append("") }
        }
        if structured.isEmpty {
            for field in ["images", "local_images"] {
                for value in payload[field] as? [Any] ?? [] {
                    if let source = value as? String { structured.append(source) }
                    else if let item = value as? [String: Any], let source = (item["url"] ?? item["path"]) as? String { structured.append(source) }
                }
            }
        }
        // Embedded/structured images take precedence over stale paths in the text envelope.
        if !structured.isEmpty { return structured }
        let text = ([payload["message"] as? String] + (payload["content"] as? [[String: Any]] ?? []).map { $0["text"] as? String })
            .compactMap { $0 }.joined(separator: "\n")
        guard let regex = try? NSRegularExpression(pattern: #"<image\b[^>]*?\bpath="([^"]+)""#) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    func markup(_ sources: [String]) -> String {
        var seen = Set<String>()
        var parts: [String] = []
        for (index, source) in sources.enumerated() {
            switch resolve(source) {
            case let .unavailable(reason):
                let label = "图片 \(index + 1) 不可用：\(reason)"
                parts.append(embedded ? "<span class=\"image-missing\">\(label)</span>" : "> \(label)")
            case let .available(asset):
                guard seen.insert(asset.filename).inserted else { continue }
                let label = "引用图片 \(index + 1)（\(asset.width) × \(asset.height)）"
                if embedded {
                    let uri = "data:image/png;base64," + asset.data.base64EncodedString()
                    parts.append("<button type=\"button\" class=\"image-thumbnail\" aria-label=\"查看\(label)\"><img src=\"\(uri)\" alt=\"\(label)\" width=\"\(asset.width)\" height=\"\(asset.height)\" loading=\"lazy\"><span>\(asset.width) × \(asset.height)</span></button>")
                } else {
                    pending[asset.filename] = asset.data
                    let relative = assetDirectory.lastPathComponent + "/" + asset.filename
                    var allowed = CharacterSet.urlPathAllowed; allowed.remove(charactersIn: "#?%")
                    let encoded = relative.addingPercentEncoding(withAllowedCharacters: allowed) ?? relative
                    parts.append("![\(label)](\(encoded))")
                }
            }
        }
        if embedded { return parts.isEmpty ? "" : "<div class=\"user-images\">" + parts.joined() + "</div>" }
        return parts.joined(separator: "\n\n")
    }

    func writeAssets() throws {
        guard !pending.isEmpty else { return }
        let fm = FileManager.default
        if fm.fileExists(atPath: assetDirectory.path) {
            let values = try assetDirectory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw SessionExportService.ExportError(message: "图片素材目录不可用，请更换导出文件名")
            }
        } else {
            try fm.createDirectory(at: assetDirectory, withIntermediateDirectories: false)
            createdDirectory = true
        }
        for (name, data) in pending {
            let destination = assetDirectory.appendingPathComponent(name)
            if fm.fileExists(atPath: destination.path) {
                let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true,
                      values.fileSize == data.count, try Data(contentsOf: destination) == data else {
                    throw SessionExportService.ExportError(message: "已有同名素材不一致，请更换导出文件名；未覆盖已有素材")
                }
            } else {
                try data.write(to: destination, options: .withoutOverwriting)
                createdFiles.append(destination)
            }
        }
    }
    func commit() { committed = true }

    private func resolve(_ source: String) -> Resolution {
        let key = Self.digest(Data(source.utf8))
        if let result = cache[key] { return result }
        let result: Resolution
        do {
            guard totalBytes < 100 * 1_024 * 1_024 else { throw ImageError.limit }
            let data: Data
            if source.hasPrefix("data:image/") {
                guard source.utf8.count <= 36 * 1_024 * 1_024,
                      let comma = source.firstIndex(of: ","), source[..<comma].hasSuffix(";base64"),
                      let decoded = Data(base64Encoded: String(source[source.index(after: comma)...])),
                      decoded.count <= 25 * 1_024 * 1_024 else { throw ImageError.invalid }
                data = decoded
            } else {
                guard !source.hasPrefix("http:") && !source.hasPrefix("https:") else { throw ImageError.remote }
                let url = source.hasPrefix("file:") ? URL(string: source) : (source.hasPrefix("/") ? URL(fileURLWithPath: source) : nil)
                guard let url, url.isFileURL,
                      ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "tif"].contains(url.pathExtension.lowercased()) else { throw ImageError.invalid }
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      let size = attributes[.size] as? NSNumber, size.intValue <= 25 * 1_024 * 1_024 else { throw ImageError.limit }
                data = try Data(contentsOf: url)
            }
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                  let type = CGImageSourceGetType(imageSource),
                  UTType(type as String)?.conforms(to: .image) == true,
                  let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 20_000, height <= 20_000,
                  Int64(width) * Int64(height) <= 40_000_000 else { throw ImageError.invalid }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
            guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { throw ImageError.invalid }
            let buffer = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(buffer, UTType.png.identifier as CFString, 1, nil) else { throw ImageError.invalid }
            // Re-encode pixels without copying EXIF/GPS or other source metadata.
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination), buffer.length <= 32 * 1_024 * 1_024,
                  totalBytes + buffer.length <= 100 * 1_024 * 1_024 else { throw ImageError.limit }
            let png = buffer as Data
            let asset = Asset(data: png, width: image.width, height: image.height, filename: "image-" + Self.digest(png) + ".png")
            totalBytes += png.count
            result = .available(asset)
        } catch let error as ImageError { result = .unavailable(error.description) }
        catch { result = .unavailable("原图文件已不存在或无法读取") }
        cache[key] = result
        return result
    }
    private enum ImageError: Error {
        case invalid, limit, remote
        var description: String {
            switch self {
            case .invalid: return "图片数据损坏或格式不支持"
            case .limit: return "图片超出导出容量或尺寸限制"
            case .remote: return "仅有远程引用，未下载原图"
            }
        }
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
