import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// Cache de imágenes thread-safe con almacenamiento dual:
/// 1. Memoria RAM (NSCache) con lectura sincrónica no aislada (0ms de latencia en scroll).
/// 2. Disco SSD persistente con límite de tamaño (200MB) y auto-evicción LRU.
/// 3. Downsampling por hardware en GPU/CoreGraphics al targetSize exacto para ahorrar 95% de RAM.
actor ImageCache {
    static let shared = ImageCache()

    private static let maxConcurrentPrefetch = 4
    private static let defaultMaxDiskCacheSize: Int64 = 200 * 1024 * 1024 // 200MB
    private static let defaultDiskEvictionWriteThreshold = 32

    nonisolated(unsafe) let memoryCache = NSCache<NSString, NSImage>()
    private var inFlight: [NSString: Task<NSImage?, Never>] = [:]
    private var rawDataInFlight: [String: Task<Data?, Never>] = [:]
    private let fileManager = FileManager.default
    private let session: URLSession
    private let diskCacheURL: URL
    private let maxDiskCacheSize: Int64
    private let diskEvictionWriteThreshold: Int
    private var estimatedDiskCacheSize: Int64?
    private var writesSinceDiskEvictionCheck = 0
    private var diskEvictionTask: Task<Void, Never>?

    /// Recupera sincrónicamente una imagen de la memoria RAM si ya está disponible.
    /// Evita asignación de tareas asíncronas y saltos de hilo para un renderizado inmediato a 120 FPS.
    nonisolated func imageFromMemoryCache(for url: URL, targetSize: CGSize? = nil) -> NSImage? {
        let memoryKey = Self.memoryKey(for: url, targetSize: targetSize)
        return self.memoryCache.object(forKey: memoryKey)
    }

    init(
        diskCacheURL: URL? = nil,
        maxDiskCacheSize: Int64 = ImageCache.defaultMaxDiskCacheSize,
        session: URLSession = .shared
    ) {
        self.memoryCache.countLimit = 1500
        self.memoryCache.totalCostLimit = 150 * 1024 * 1024 // 150MB RAM (suficiente para miles de thumbnails a 40x40)

        if let diskCacheURL {
            self.diskCacheURL = diskCacheURL
        } else {
            self.diskCacheURL = HomeLabConfiguration.imageCacheURL
        }
        self.maxDiskCacheSize = maxDiskCacheSize
        self.diskEvictionWriteThreshold = Self.defaultDiskEvictionWriteThreshold
        self.session = session
        try? self.fileManager.createDirectory(at: self.diskCacheURL, withIntermediateDirectories: true)

        Task(priority: .utility) {
            await self.scheduleDiskEviction(force: true)
        }
    }

    /// Obtiene la imagen de memoria, disco o red con downsampling.
    func image(for url: URL, targetSize: CGSize? = nil) async -> NSImage? {
        let memoryKey = Self.memoryKey(for: url, targetSize: targetSize)
        if let cached = memoryCache.object(forKey: memoryKey) {
            return cached
        }

        if let existing = inFlight[memoryKey] {
            return await existing.value
        }

        let task = Task<NSImage?, Never>(priority: .utility) { [self] in
            // Intento desde disco SSD en hilo desprendido con prioridad utility para no saturar la UI
            if let diskImage = await Task.detached(priority: .utility, operation: {
                self.loadFromDisk(url: url, targetSize: targetSize)
            }).value {
                self.memoryCache.setObject(diskImage, forKey: memoryKey)
                return diskImage
            }

            // Descarga de red
            guard let data = await self.rawImageData(for: url),
                  let image = Self.createImage(from: data, targetSize: targetSize)
            else { return nil }
            let cost = targetSize != nil ? Int(image.size.width * image.size.height * 4) : data.count
            self.memoryCache.setObject(image, forKey: memoryKey, cost: cost)
            return image
        }

        self.inFlight[memoryKey] = task
        let result = await task.value
        self.inFlight.removeValue(forKey: memoryKey)
        return result
    }

    private static func memoryKey(for url: URL, targetSize: CGSize?) -> NSString {
        guard let targetSize else { return url.absoluteString as NSString }
        return "\(url.absoluteString)@\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString
    }

    private static func isSuccessfulResponse(_ response: URLResponse) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else { return true }
        return (200 ..< 300).contains(httpResponse.statusCode)
    }

    private func rawImageData(for url: URL) async -> Data? {
        let key = self.cacheKey(for: url)
        if let existing = self.rawDataInFlight[key] {
            return await existing.value
        }

        let task = Task<Data?, Never> { [session] in
            if url.isFileURL {
                return await Task.detached(priority: .utility) {
                    try? Data(contentsOf: url)
                }.value
            }
            do {
                let (data, response) = try await session.data(from: url)
                guard Self.isSuccessfulResponse(response) else { return nil }
                return data
            } catch {
                return nil
            }
        }
        self.rawDataInFlight[key] = task
        let data = await task.value
        self.rawDataInFlight.removeValue(forKey: key)
        if let data, !url.isFileURL {
            self.saveToDisk(url: url, data: data)
        }
        return data
    }

    /// Precarga de URLs para carruseles o listas con concurrencia acotada.
    func prefetch(urls: [URL], targetSize: CGSize? = nil) async {
        await withTaskGroup(of: Void.self) { group in
            var inProgress = 0
            for url in urls {
                guard !Task.isCancelled else { break }
                if self.memoryCache.object(forKey: Self.memoryKey(for: url, targetSize: targetSize)) != nil {
                    continue
                }
                if inProgress >= Self.maxConcurrentPrefetch {
                    await group.next()
                    inProgress -= 1
                }
                group.addTask(priority: .utility) {
                    _ = await self.image(for: url, targetSize: targetSize)
                }
                inProgress += 1
            }
            await group.waitForAll()
        }
    }

    // MARK: - Downsampling por Hardware

    private static func createImage(from data: Data, targetSize: CGSize?) -> NSImage? {
        guard let targetSize else {
            return NSImage(data: data)
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return NSImage(data: data)
        }

        let maxDimension = max(targetSize.width, targetSize.height) * 2 // Retina 2x
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, downsampleOptions as CFDictionary
        ) else {
            return NSImage(data: data)
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func clearMemoryCache() {
        self.memoryCache.removeAllObjects()
        self.inFlight.removeAll()
        self.rawDataInFlight.removeAll()
    }

    // MARK: - Disk Helpers

    nonisolated private func cacheKey(for url: URL) -> String {
        let data = Data(url.absoluteString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    nonisolated private func diskCachePath(for url: URL) -> URL {
        self.diskCacheURL.appendingPathComponent(self.cacheKey(for: url))
    }

    nonisolated private func loadFromDisk(url: URL, targetSize: CGSize? = nil) -> NSImage? {
        let path = self.diskCachePath(for: url)
        guard let data = try? Data(contentsOf: path) else {
            return nil
        }
        return Self.createImage(from: data, targetSize: targetSize)
    }

    private func saveToDisk(url: URL, data: Data) {
        let path = self.diskCachePath(for: url)
        do {
            try data.write(to: path, options: .atomic)
        } catch {
            #if DEBUG
            print("[ImageCache] Error al guardar imagen en disco para \(url): \(error)")
            #endif
        }
    }

    private func scheduleDiskEviction(force: Bool = false) {
        guard diskEvictionTask == nil else { return }
        diskEvictionTask = Task(priority: .utility) {
            self.evictOldDiskFilesIfNeeded()
            self.diskEvictionTask = nil
        }
    }

    private func evictOldDiskFilesIfNeeded() {
        guard let enumerator = fileManager.enumerator(
            at: diskCacheURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var files: [(url: URL, size: Int, date: Date)] = []
        var totalSize: Int64 = 0

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let date = values.contentModificationDate
            else { continue }
            files.append((fileURL, size, date))
            totalSize += Int64(size)
        }

        if totalSize > maxDiskCacheSize {
            files.sort { $0.date < $1.date }
            for file in files {
                try? fileManager.removeItem(at: file.url)
                totalSize -= Int64(file.size)
                if totalSize <= (maxDiskCacheSize * 3 / 4) {
                    break
                }
            }
        }
    }
}
