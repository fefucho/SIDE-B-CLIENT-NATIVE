import Foundation
import AVFoundation
import Testing
import SideBCore
@testable import SideB

@Test func originalFeelNoWaysResolvesWhenLiveTestingIsEnabled() async throws {
    guard ProcessInfo.processInfo.environment["SIDEB_LIVE_CIPHER"] == "1" else { return }
    let dataDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SideB", isDirectory: true)
    let core = try SideBCore(dataDir: dataDirectory.path)
    core.setCipherJsRuntime(runtime: NativeCipherJsRuntime())
    let stream = try await core.resolveStream(videoId: "pMaogWC5TEQ", isUpload: false)
    #expect(stream.videoId == "pMaogWC5TEQ")
    #expect(stream.streamClient == "WEB_REMIX")
    let options: [String: Any] = stream.headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": stream.headers]
    let item = AVPlayerItem(asset: AVURLAsset(url: try #require(URL(string: stream.streamUrl)), options: options))
    let player = AVPlayer(playerItem: item)
    player.play()
    defer { player.pause() }
    for _ in 0..<8 {
        try await Task.sleep(for: .seconds(1))
        if player.currentTime().seconds > 0.5 { break }
    }
    #expect(player.currentTime().seconds > 0.5)
    #expect(item.error == nil)
}
