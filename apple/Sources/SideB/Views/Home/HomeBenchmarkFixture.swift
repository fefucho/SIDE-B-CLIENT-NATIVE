import Foundation
import SideBCore

/// Feed fijo para comparar dos implementaciones de Inicio en Release, sin depender de la red.
enum HomeBenchmarkFixture {
    static func page(chipParams: String? = nil, continuation: Bool = false) -> HomePageRecord {
        let names: [(String, String, Int)] = continuation
            ? [("Más para escuchar", "playlist", 24), ("Más artistas", "artist", 24)]
            : [
                ("Quick picks", "song", 42),
                ("New releases", "album", 24),
                ("Mixed for you", "playlist", 24),
                ("Listen again", "playlist", 24),
                ("Similar artists", "artist", 24),
                ("Songs for today", "song", 36),
                ("Featured playlists", "playlist", 24),
                ("Albums for you", "album", 24),
            ]
        let sections = names.enumerated().map { sectionIndex, spec in
            HomeSectionRecord(
                title: spec.0,
                format: spec.1 == "song" ? .compactSongs : .largeCards,
                items: (0..<spec.2).map { index in
                    let number = sectionIndex * 100 + index
                    let imageDirectory = ProcessInfo.processInfo.environment["SIDEB_HOME_FIXTURE_IMAGE_DIR"]
                        ?? "/private/tmp/sideb-home-lab-images"
                    let artPath = "\(imageDirectory)/\(number % 16).png"
                    return HomeItemRecord(
                        kind: spec.1,
                        id: "fixture-\(chipParams ?? "all")-\(number)",
                        title: "\(spec.1.capitalized) \(number) — una canción de prueba",
                        subtitle: "Artista \(number % 20) • Álbum \(number % 12)",
                        thumbnail: artPath,
                        duration: "3:24",
                        artists: "Artista \(number % 20)",
                        artistId: nil,
                        album: "Álbum \(number % 12)",
                        albumId: nil,
                        artistRuns: [],
                        explicit: false
                    )
                },
                moreBrowseId: "VLfixture-\(sectionIndex)",
                moreParams: nil
            )
        }
        return HomePageRecord(
            chips: continuation ? [] : [
                HomeChipRecord(title: "Relax", params: "relax"),
                HomeChipRecord(title: "Focus", params: "focus"),
                HomeChipRecord(title: "Workout", params: "workout"),
            ],
            sections: sections,
            continuation: continuation ? nil : "fixture-next"
        )
    }
}
