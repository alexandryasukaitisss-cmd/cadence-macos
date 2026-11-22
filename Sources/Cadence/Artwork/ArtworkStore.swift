import AppKit
import CadenceCore
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class ArtworkStore: ObservableObject {
    private var service: MusicArtworkProviding?
    /// AppleScript artwork is only requested after Music access has been
    /// granted by a successful library load. Before that, the app shows the
    /// on-disk cache or a placeholder instead of triggering a system prompt
    /// just to paint a grid.
    @Published private(set) var revision = 0
    var allowServiceFetch = false {
        didSet {
            if !oldValue, allowServiceFetch {
                revision += 1
            }
        }
    }
    private let memory = NSCache<NSString, NSImage>()
    private let remoteMemory = NSCache<NSString, NSImage>()
    private let diskDirectory: URL
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        diskDirectory = support
            .appendingPathComponent("Cadence", isDirectory: true)
            .appendingPathComponent("Artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        memory.countLimit = 500
        memory.totalCostLimit = 96 * 1024 * 1024
        remoteMemory.countLimit = 120
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = ["User-Agent": "Cadence/1.0 (Macintosh)"]
        session = URLSession(configuration: configuration)
    }

    func configure(service: MusicArtworkProviding) {
        self.service = service
    }

    func cachedImage(for albumKey: String) -> NSImage? {
        memory.object(forKey: albumKey as NSString)
    }

    func image(for album: MusicAlbum) async -> NSImage? {
        await image(forAlbumKey: album.id, trackID: album.artworkTrackID)
    }

    func image(forAlbumKey key: String, trackID: Int?) async -> NSImage? {
        if let cached = memory.object(forKey: key as NSString) {
            return cached
        }
        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task<NSImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.loadAlbumImage(key: key, trackID: trackID)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            memory.setObject(image, forKey: key as NSString, cost: 600 * 600 * 4)
        }
        return image
    }

    private func loadAlbumImage(key: String, trackID: Int?) async -> NSImage? {
        let diskURL = diskDirectory.appendingPathComponent(Self.fileName(for: key))
        if let data = try? Data(contentsOf: diskURL), let image = NSImage(data: data) {
            return image
        }
        if DebugSupport.disableArtwork { return nil }
        guard allowServiceFetch, let service, let trackID else { return nil }
        guard let raw = try? await service.artworkData(for: trackID), !raw.isEmpty else {
            return nil
        }
        let jpeg = await Task.detached(priority: .utility) {
            Self.downscaledJPEG(from: raw, maxPixel: 900)
        }.value
        guard let jpeg, let image = NSImage(data: jpeg) else {
            return NSImage(data: raw)
        }
        try? jpeg.write(to: diskURL, options: .atomic)
        return image
    }

    func remoteImage(url: URL?) async -> NSImage? {
        guard !DebugSupport.disableRemoteArtwork, let url else { return nil }
        let key = url.absoluteString
        if let cached = remoteMemory.object(forKey: key as NSString) {
            return cached
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let image = NSImage(data: data) else {
            return nil
        }
        remoteMemory.setObject(image, forKey: key as NSString, cost: 320 * 320 * 4)
        return image
    }

    func clearDiskCache() {
        try? FileManager.default.removeItem(at: diskDirectory)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        memory.removeAllObjects()
        remoteMemory.removeAllObjects()
    }

    private static func fileName(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    nonisolated private static func downscaledJPEG(from data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
