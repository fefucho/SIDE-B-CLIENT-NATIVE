import Testing
import Foundation
import SideBCore
@testable import SideB

@Suite("Tests de Menús Contextuales (PLAN-007)")
@MainActor
struct ContextMenuPolicyTests {

    // MARK: - 1. MenuIDNormalizer Tests

    @Test("MenuIDNormalizer limpia prefijos VL correctamente")
    func testNormalizerStripsVLPrefix() {
        #expect(MenuIDNormalizer.canonicalPlaylistId("VLPL12345") == "PL12345")
        #expect(MenuIDNormalizer.canonicalPlaylistId("VLRDAMPL123") == "RDAMPL123")
        #expect(MenuIDNormalizer.canonicalPlaylistId("VLLM") == "LM")
        #expect(MenuIDNormalizer.canonicalPlaylistId("PL98765") == "PL98765")
    }

    @Test("MenuIDNormalizer detecta radios continuas sin confundirlas con playlists finitas")
    func testDynamicRadioDetection() {
        #expect(MenuIDNormalizer.isDynamicRadioMix(id: "RDTK123"))
        #expect(MenuIDNormalizer.isDynamicRadioMix(id: "VLRDCLAK5uy"))
        #expect(MenuIDNormalizer.isDynamicRadioMix(id: "RDAMPLPL123"))
        #expect(!MenuIDNormalizer.isDynamicRadioMix(id: "PL123456789"))
        #expect(!MenuIDNormalizer.isDynamicRadioMix(id: "VLPLMyCustomMix"))
    }

    @Test("MenuIDNormalizer nunca genera prefijos dobles como RDAMPLVLRD...")
    func testRadioPrefixResolution() {
        let cleanRadio = MenuIDNormalizer.radioPlaylistId(forCollectionId: "VLRDCLAK5uy", prefix: "RDAMPL")
        #expect(cleanRadio == "RDCLAK5uy")
        #expect(!cleanRadio.hasPrefix("RDAMPL"))

        let direct = MenuIDNormalizer.radioPlaylistId(forCollectionId: "PL123", directRadioId: "RDDIRECT")
        #expect(direct == "RDDIRECT")

        let plRadio = MenuIDNormalizer.radioPlaylistId(forCollectionId: "PL987", prefix: "RDAMPL")
        #expect(plRadio == "RDAMPLPL987")
    }

    // MARK: - 2. Regla 1: Ocultar acciones redundantes según origen

    @Test("Canción en la vista de su propio álbum oculta 'Ir al álbum'")
    func testSongInOwnAlbumHidesGoToAlbum() {
        let song = SongItemRecord(
            videoId: "v123",
            title: "Bohemian Rhapsody",
            artists: "Queen",
            album: "A Night at the Opera",
            duration: "354",
            thumbnail: nil,
            artistId: "UCqueen",
            albumId: "MPREb_album1",
            setVideoId: nil,
            isVideo: false,
            isUpload: false,
            library: nil
        )

        // Origen en el mismo álbum
        let sectionsInAlbum = MenuPolicy.resolveSections(
            target: .song(song),
            origin: .album(browseId: "MPREb_album1"),
            facts: MenuFacts()
        )
        let navItemsInAlbum = sectionsInAlbum.first(where: { $0.kind == .navigation })?.items ?? []
        #expect(!navItemsInAlbum.contains(where: { $0.id == .goToAlbum(browseId: "MPREb_album1") }))
        #expect(navItemsInAlbum.contains(where: { $0.id == .goToArtist(channelId: "UCqueen") }))

        // Origen en Inicio (debe mostrar ambas opciones)
        let sectionsInHome = MenuPolicy.resolveSections(
            target: .song(song),
            origin: .home,
            facts: MenuFacts()
        )
        let navItemsInHome = sectionsInHome.first(where: { $0.kind == .navigation })?.items ?? []
        #expect(navItemsInHome.contains(where: { $0.id == .goToAlbum(browseId: "MPREb_album1") }))
        #expect(navItemsInHome.contains(where: { $0.id == .goToArtist(channelId: "UCqueen") }))
    }

    @Test("Álbum en su propia página oculta 'Ver álbum'")
    func testAlbumInOwnPageHidesViewAlbum() {
        let sections = MenuPolicy.resolveSections(
            target: .album(
                browseId: "MPREb_1",
                playlistId: "OLAK5uy_1",
                title: "Test Album",
                artist: "Artist",
                artistId: "UC1",
                thumbnail: nil
            ),
            origin: .album(browseId: "MPREb_1"),
            facts: MenuFacts()
        )
        let navItems = sections.first(where: { $0.kind == .navigation })?.items ?? []
        #expect(!navItems.contains(where: { $0.id == .goToAlbum(browseId: "MPREb_1") }))
        #expect(navItems.contains(where: { $0.id == .goToArtist(channelId: "UC1") }))
    }

    // MARK: - 3. Regla 2: Desconocimiento de biblioteca y permisos de edición

    @Test("Biblioteca desconocida no asume inLibrary == false ni muestra Guardar/Quitar erróneo")
    func testUnknownLibraryStatusHidesLibraryToggle() {
        let factsUnknown = MenuFacts(inLibrary: .unknown)
        let sections = MenuPolicy.resolveSections(
            target: .album(
                browseId: "MPREb_1",
                playlistId: nil,
                title: "Test",
                artist: nil,
                artistId: nil,
                thumbnail: nil
            ),
            origin: .home,
            facts: factsUnknown
        )
        let collectionSection = sections.first(where: { $0.kind == .collection })
        #expect(collectionSection == nil)

        let factsKnown = MenuFacts(inLibrary: .known(false))
        let sectionsKnown = MenuPolicy.resolveSections(
            target: .album(
                browseId: "MPREb_1",
                playlistId: nil,
                title: "Test",
                artist: nil,
                artistId: nil,
                thumbnail: nil
            ),
            origin: .home,
            facts: factsKnown
        )
        let toggleItem = sectionsKnown.first(where: { $0.kind == .collection })?.items.first
        #expect(toggleItem?.id == .toggleLibrary(inLibrary: false))
        #expect(toggleItem?.title == "Guardar álbum en la biblioteca")
    }

    @Test("Playlist ajena oculta Editar, Eliminar y Ordenar")
    func testForeignPlaylistHidesEditingActions() {
        let factsForeign = MenuFacts(isOwned: .known(false), sortEditable: false)
        let sections = MenuPolicy.resolveSections(
            target: .playlist(id: "PLforeign", title: "Top 50", subtitle: nil, thumbnail: nil, isRadioMix: false),
            origin: .home,
            facts: factsForeign
        )
        let destructiveSection = sections.first(where: { $0.kind == .destructive })
        #expect(destructiveSection == nil)
    }

    @Test("Playlist propia muestra Editar, Eliminar y Ordenar si sortEditable es true")
    func testOwnedPlaylistShowsEditingAndSorting() {
        let factsOwned = MenuFacts(isOwned: .known(true), sortEditable: true)
        let sections = MenuPolicy.resolveSections(
            target: .playlist(id: "PLowned", title: "Mis Favoritas", subtitle: nil, thumbnail: nil, isRadioMix: false),
            origin: .playlist(id: "PLowned"),
            facts: factsOwned
        )
        let destructive = sections.first(where: { $0.kind == .destructive })?.items ?? []
        #expect(destructive.contains(where: { $0.id == .editDetails }))
        #expect(destructive.contains(where: { $0.id == .deletePlaylist }))

        let sortItem = destructive.first(where: { $0.title == "Ordenar" })
        #expect(sortItem != nil)
        #expect(sortItem?.subitems?.count == 6)
    }

    // MARK: - 4. Regla 4: Cola y NowPlaying

    @Test("Canción en la cola muestra 'Quitar de la cola' con su índice de ocurrencia exacto")
    func testSongInQueueShowsRemoveWithIndex() {
        let song = SongItemRecord(
            videoId: "vRepeated",
            title: "Track",
            artists: "Artist",
            album: nil,
            duration: "180",
            thumbnail: nil,
            artistId: nil,
            albumId: nil,
            setVideoId: nil,
            isVideo: false,
            isUpload: false,
            library: nil
        )

        let facts = MenuFacts(isCurrentPlayingTrack: false)
        let sections = MenuPolicy.resolveSections(
            target: .song(song),
            origin: .queue(occurrenceIndex: 3),
            facts: facts
        )
        let destructive = sections.first(where: { $0.kind == .destructive })?.items ?? []
        let removeItem = destructive.first(where: { $0.id == .removeFromQueue(index: 3) })
        #expect(removeItem != nil)
        #expect(removeItem?.isDestructive == true)
    }

    @Test("Pista actualmente activa en reproducción oculta acciones redundantes y no permite quitarse de la cola")
    func testActiveTrackSuppressesRedundantPlaybackAndRemoval() {
        let song = SongItemRecord(
            videoId: "vActive",
            title: "Active Track",
            artists: "Artist",
            album: nil,
            duration: "180",
            thumbnail: nil,
            artistId: nil,
            albumId: nil,
            setVideoId: nil,
            isVideo: false,
            isUpload: false,
            library: nil
        )

        let facts = MenuFacts(isCurrentPlayingTrack: true)
        let sections = MenuPolicy.resolveSections(
            target: .song(song),
            origin: .nowPlaying,
            facts: facts
        )
        let playback = sections.first(where: { $0.kind == .playback })?.items ?? []
        #expect(!playback.contains(where: { $0.id == .play }))
        #expect(!playback.contains(where: { $0.id == .playNext }))
        #expect(playback.contains(where: { $0.id == .addToQueue }))

        // En la cola siendo activa tampoco debe ofrecer quitarse
        let queueSections = MenuPolicy.resolveSections(
            target: .song(song),
            origin: .queue(occurrenceIndex: 0),
            facts: facts
        )
        let queueDestructive = queueSections.first(where: { $0.kind == .destructive })?.items ?? []
        #expect(!queueDestructive.contains(where: { $0.id == .removeFromQueue(index: 0) }))
    }

    // MARK: - 5. Regla 5: Mix dinámico vs Playlist finita

    @Test("Mix dinámico omite Aleatorio y Añadir a la cola, y ofrece Reproducir mix")
    func testDynamicMixOmitsShuffleAndAddToQueue() {
        let sections = MenuPolicy.resolveSections(
            target: .radioMix(id: "RDTK123", title: "My Mix", subtitle: nil, thumbnail: nil),
            origin: .home,
            facts: MenuFacts()
        )
        let playback = sections.first(where: { $0.kind == .playback })?.items ?? []
        #expect(playback.contains(where: { $0.id == .play }))
        #expect(playback.first?.title == "Reproducir mix")
        #expect(!playback.contains(where: { $0.id == .shuffle }))
        #expect(!playback.contains(where: { $0.id == .addToQueue }))
        #expect(!playback.contains(where: { $0.id == .startMix }))
    }

    // MARK: - 6. Orden Visual Estricto

    @Test("El orden de las secciones respeta la jerarquía visual del PLAN-007")
    func testVisualSectionsHierarchy() {
        let song = SongItemRecord(
            videoId: "vOrder",
            title: "Title",
            artists: "Artist",
            album: "Album",
            duration: "200",
            thumbnail: nil,
            artistId: "art1",
            albumId: "alb1",
            setVideoId: "set1",
            isVideo: false,
            isUpload: false,
            library: nil
        )

        let facts = MenuFacts(
            isOwned: .known(true),
            onRemoveFromPlaylist: { }
        )
        let sections = MenuPolicy.resolveSections(
            target: .song(song),
            origin: .playlist(id: "PLmy"),
            facts: facts
        )

        let sectionKinds = sections.map(\.kind)
        let expectedOrder: [MenuSection.SectionKind] = [
            .playback,
            .collection,
            .navigation,
            .share,
            .destructive
        ]
        #expect(sectionKinds == expectedOrder)
    }

    // MARK: - 7. Estandarización de Iconos y Visibilidad (macOS)

    @Test("menuSymbol genera un lienzo template uniforme de 16x16pt")
    func testMenuSymbolStandardization() {
        let playImg = AppKitMenuAdapter.menuSymbol(named: "play.fill")
        #expect(playImg != nil)
        #expect(playImg?.size == NSSize(width: 16, height: 16))
        #expect(playImg?.isTemplate == true)

        let wideImg = AppKitMenuAdapter.menuSymbol(named: "text.line.first.and.arrowtriangle.forward")
        #expect(wideImg != nil)
        #expect(wideImg?.size == NSSize(width: 16, height: 16))
        #expect(wideImg?.isTemplate == true)

        let emptyImg = AppKitMenuAdapter.menuSymbol(named: "")
        #expect(emptyImg == nil)
    }

    @Test("buildNSMenu asigna imágenes y activa visibilidad visible en macOS 27+")
    func testAppKitMenuAdapterImageVisibility() {
        let song = SongItemRecord(
            videoId: "v123",
            title: "Test Track",
            artists: "Test Artist",
            album: "Test Album",
            duration: "180",
            thumbnail: nil,
            artistId: "art1",
            albumId: "alb1",
            setVideoId: nil,
            isVideo: false,
            isUpload: false,
            library: nil
        )

        let facts = MenuFacts(
            isLoggedIn: true,
            isOwned: .known(false),
            isCurrentPlayingTrack: false,
            isLiked: false,
            userPlaylists: []
        )
        let sections = MenuPolicy.resolveSections(
            target: .song(song),
            origin: .home,
            facts: facts
        )

        let executor = MenuActionExecutor(player: nil, router: nil, core: nil)
        let menu = AppKitMenuAdapter.buildNSMenu(
            sections: sections,
            target: .song(song),
            facts: facts,
            executor: executor
        )

        #expect(!menu.items.isEmpty)
        for item in menu.items where !item.isSeparatorItem {
            if item.image != nil {
                #expect(item.image?.size == NSSize(width: 16, height: 16))
                #expect(item.image?.isTemplate == true)
                if #available(macOS 27.0, *) {
                    #expect(item.preferredImageVisibility == .visible)
                }
            }
        }
    }
}
