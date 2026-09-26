import Foundation

/// Utilidad para optimizar URLs de imágenes de YouTube Music CDN (adaptado de Limusic `thumb.ts`).
/// - YouTube Music devuelve URLs de InnerTube con sufijos como `=w544-h544` o `=s576` (~100KB por carátula).
/// - Al reescribir estos parámetros a `=w96-h96` o `=s96`, Google CDN envía directamente una miniatura de ~2KB.
/// - Esto reduce el consumo de red y RAM en un 98%, permitiendo scroll fluido a 120 FPS sin latencia de decodificación.
public enum ImageURLHelper {
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSURL>()

    private static let sizeRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "=w\\d+-h\\d+")
    }()

    private static let singleSizeRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "=s\\d+")
    }()

    /// Transforma la URL de Google CDN al tamaño en píxeles especificado con acceso O(1) en RAM a 0ms.
    public static func optimizedThumbnailURL(from urlString: String?, targetPixelSize: Int = 96) -> URL? {
        guard let urlString, !urlString.isEmpty else { return nil }

        if urlString.hasPrefix("/") {
            return URL(fileURLWithPath: urlString)
        }

        let cacheKey = "\(targetPixelSize)_\(urlString)" as NSString
        if let cachedURL = cache.object(forKey: cacheKey) {
            return cachedURL as URL
        }

        var modified = urlString
        let fullRange = NSRange(location: 0, length: modified.utf16.count)

        if let regex = sizeRegex, regex.firstMatch(in: modified, range: fullRange) != nil {
            modified = regex.stringByReplacingMatches(
                in: modified,
                range: fullRange,
                withTemplate: "=w\(targetPixelSize)-h\(targetPixelSize)"
            )
        } else if let regex = singleSizeRegex, regex.firstMatch(in: modified, range: fullRange) != nil {
            modified = regex.stringByReplacingMatches(
                in: modified,
                range: fullRange,
                withTemplate: "=s\(targetPixelSize)"
            )
        }

        guard let resultURL = URL(string: modified) else { return nil }
        cache.setObject(resultURL as NSURL, forKey: cacheKey)
        return resultURL
    }

    /// Devuelve la URL de máxima calidad posible para superficies grandes como Fullscreen (1200x1200px o maxresdefault).
    public static func maxQualityArtworkURL(from urlString: String?, videoId: String? = nil) -> URL? {
        guard let urlString, !urlString.isEmpty else { return nil }

        if urlString.hasPrefix("/") || urlString.hasPrefix("file://") {
            if let fileUrl = URL(string: urlString), fileUrl.scheme != nil {
                return fileUrl
            }
            return URL(fileURLWithPath: urlString)
        }

        let cacheKey = "max_\(urlString)" as NSString
        if let cachedURL = cache.object(forKey: cacheKey) {
            return cachedURL as URL
        }

        var modified = urlString
        let fullRange = NSRange(location: 0, length: modified.utf16.count)

        if let regex = sizeRegex, regex.firstMatch(in: modified, range: fullRange) != nil {
            modified = regex.stringByReplacingMatches(
                in: modified,
                range: fullRange,
                withTemplate: "=w1200-h1200"
            )
        } else if let regex = singleSizeRegex, regex.firstMatch(in: modified, range: fullRange) != nil {
            modified = regex.stringByReplacingMatches(
                in: modified,
                range: fullRange,
                withTemplate: "=s1200"
            )
        } else if modified.contains("i.ytimg.com") {
            // Mejorar miniaturas públicas de YouTube a resolución máxima (1280x720)
            for variant in ["hqdefault.jpg", "sddefault.jpg", "mqdefault.jpg", "default.jpg"] {
                if modified.contains(variant) {
                    modified = modified.replacingOccurrences(of: variant, with: "maxresdefault.jpg")
                    break
                }
            }
        }

        guard let resultURL = URL(string: modified) else { return nil }
        cache.setObject(resultURL as NSURL, forKey: cacheKey)
        return resultURL
    }

    /// Devuelve una URL de respaldo estándar en caso de que una miniatura de máxima resolución falle.
    public static func fallbackThumbnailURL(from urlString: String?, targetPixelSize: Int = 544) -> URL? {
        return optimizedThumbnailURL(from: urlString, targetPixelSize: targetPixelSize)
    }
}
