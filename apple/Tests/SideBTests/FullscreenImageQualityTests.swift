import Testing
import Foundation
@testable import SideB

@Suite("Tests de Calidad de Imagen y Fullscreen")
struct FullscreenImageQualityTests {

    @Test("Fullscreen puede solicitar el original de Google y conserva un respaldo de 1200px")
    func testOriginalArtworkURL() {
        let input = "https://lh3.googleusercontent.com/cover=w544-h544-l90-rj"
        #expect(ImageURLHelper.originalArtworkURL(from: input)?.absoluteString == "https://lh3.googleusercontent.com/cover=s0?imgmax=0")
        #expect(ImageURLHelper.maxQualityArtworkURL(from: input)?.absoluteString == "https://lh3.googleusercontent.com/cover=w1200-h1200-l90-rj")

        let avatar = "https://yt3.ggpht.com/avatar=s576-c-k-c0x00ffffff-no-rj"
        #expect(ImageURLHelper.originalArtworkURL(from: avatar)?.absoluteString == "https://yt3.ggpht.com/avatar=s0?imgmax=0")
        #expect(ImageURLHelper.originalArtworkURL(from: "https://i.ytimg.com/vi/id/hqdefault.jpg") == nil)
    }

    @Test("Google CDN con sufijo w-h se escala a 1200x1200px para Fullscreen")
    func testGoogleCDNWidthHeightUpscaling() {
        let input = "https://lh3.googleusercontent.com/abc123xyz=w544-h544-l90-rj"
        let result = ImageURLHelper.maxQualityArtworkURL(from: input)
        #expect(result?.absoluteString == "https://lh3.googleusercontent.com/abc123xyz=w1200-h1200-l90-rj")
    }

    @Test("Google CDN con sufijo =s se escala a s1200 para Fullscreen")
    func testGoogleCDNSingleSizeUpscaling() {
        let input = "https://yt3.ggpht.com/avatar_hash=s576-c-k-c0x00ffffff-no-rj"
        let result = ImageURLHelper.maxQualityArtworkURL(from: input)
        #expect(result?.absoluteString == "https://yt3.ggpht.com/avatar_hash=s1200-c-k-c0x00ffffff-no-rj")
    }

    @Test("Miniaturas públicas de YouTube i.ytimg.com se transforman a maxresdefault")
    func testYouTubeThumbnailMaxResUpgrade() {
        let hq = "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
        #expect(ImageURLHelper.maxQualityArtworkURL(from: hq)?.absoluteString == "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg")

        let sd = "https://i.ytimg.com/vi/dQw4w9WgXcQ/sddefault.jpg"
        #expect(ImageURLHelper.maxQualityArtworkURL(from: sd)?.absoluteString == "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg")

        let mq = "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg"
        #expect(ImageURLHelper.maxQualityArtworkURL(from: mq)?.absoluteString == "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg")
    }

    @Test("Rutas locales conservan su URL intacta")
    func testLocalFilePathsPreserved() {
        let localPath = "/Users/test/Music/cover.jpg"
        let fileURL = ImageURLHelper.maxQualityArtworkURL(from: localPath)
        #expect(fileURL?.isFileURL == true)
        #expect(fileURL?.path == localPath)

        let fileScheme = "file:///Users/test/Music/cover.png"
        let fileSchemeURL = ImageURLHelper.maxQualityArtworkURL(from: fileScheme)
        #expect(fileSchemeURL?.isFileURL == true)
    }

    @Test("Strings nulos o vacíos retornan nil")
    func testNilAndEmptyStrings() {
        #expect(ImageURLHelper.maxQualityArtworkURL(from: nil) == nil)
        #expect(ImageURLHelper.maxQualityArtworkURL(from: "") == nil)
    }

    @Test("Vistas que no son Fullscreen continúan usando miniaturas compactas y optimizadas")
    func testNonFullscreenViewsRemainCompact() {
        let input = "https://lh3.googleusercontent.com/sample=w544-h544-l90-rj"
        
        // PlayerBarView solicita 92px
        let playerBarURL = ImageURLHelper.optimizedThumbnailURL(from: input, targetPixelSize: 92)
        #expect(playerBarURL?.absoluteString == "https://lh3.googleusercontent.com/sample=w92-h92-l90-rj")

        // SidebarView solicita 48px
        let sidebarURL = ImageURLHelper.optimizedThumbnailURL(from: input, targetPixelSize: 48)
        #expect(sidebarURL?.absoluteString == "https://lh3.googleusercontent.com/sample=w48-h48-l90-rj")

        // NativeTrackTableView solicita ~80-92px
        let tableURL = ImageURLHelper.optimizedThumbnailURL(from: input, targetPixelSize: 80)
        #expect(tableURL?.absoluteString == "https://lh3.googleusercontent.com/sample=w80-h80-l90-rj")
    }

    @Test("Fallback thumbnail produce la resolución de respaldo estándar")
    func testFallbackThumbnailURL() {
        let input = "https://lh3.googleusercontent.com/sample=w120-h120-l90-rj"
        let fallback = ImageURLHelper.fallbackThumbnailURL(from: input, targetPixelSize: 544)
        #expect(fallback?.absoluteString == "https://lh3.googleusercontent.com/sample=w544-h544-l90-rj")
    }
}
