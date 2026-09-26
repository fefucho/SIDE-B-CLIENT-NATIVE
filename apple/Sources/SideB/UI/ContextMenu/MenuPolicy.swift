import Foundation
import SideBCore

// MARK: - MenuPolicy

/// Motor puro de decisión de menús contextuales (PLAN-007).
/// No tiene estado mutable ni dependencias de UI: recibe Target, Origin y Facts,
/// y construye la lista ordenada de secciones con acciones filtradas.
@MainActor
public enum MenuPolicy {

    public static func resolveSections(
        target: MenuTarget,
        origin: MenuOrigin,
        facts: MenuFacts
    ) -> [MenuSection] {
        switch target {
        case .song(let song):
            return resolveSongSections(song: song, origin: origin, facts: facts)
        case .album(let browseId, let playlistId, let title, let artist, let artistId, let thumbnail):
            return resolveAlbumSections(
                browseId: browseId,
                playlistId: playlistId,
                title: title,
                artist: artist,
                artistId: artistId,
                thumbnail: thumbnail,
                origin: origin,
                facts: facts
            )
        case .playlist(let id, let title, let subtitle, let thumbnail, let isRadioMix):
            if isRadioMix || MenuIDNormalizer.isDynamicRadioMix(id: id) {
                return resolveRadioMixSections(id: id, title: title, subtitle: subtitle, thumbnail: thumbnail, origin: origin, facts: facts)
            } else {
                return resolvePlaylistSections(id: id, title: title, subtitle: subtitle, thumbnail: thumbnail, origin: origin, facts: facts)
            }
        case .radioMix(let id, let title, let subtitle, let thumbnail):
            return resolveRadioMixSections(id: id, title: title, subtitle: subtitle, thumbnail: thumbnail, origin: origin, facts: facts)
        case .artist(let channelId, let name, let thumbnail, let radioPlaylistId):
            return resolveArtistSections(channelId: channelId, name: name, thumbnail: thumbnail, radioPlaylistId: radioPlaylistId, origin: origin, facts: facts)
        }
    }

    // MARK: - 1. Canción

    private static func resolveSongSections(
        song: SongItemRecord,
        origin: MenuOrigin,
        facts: MenuFacts
    ) -> [MenuSection] {
        var sections: [MenuSection] = []

        // --- 1. Reproducción ---
        var playbackItems: [MenuActionItem] = []
        let isNowPlaying = (origin == .nowPlaying) || facts.isCurrentPlayingTrack

        if !isNowPlaying {
            playbackItems.append(MenuActionItem(
                id: .play,
                title: "Reproducir ahora",
                systemImage: "play.fill"
            ))
        }

        if !song.videoId.isEmpty {
            playbackItems.append(MenuActionItem(
                id: .startMix,
                title: "Iniciar mix",
                systemImage: "dot.radiowaves.left.and.right"
            ))
        }

        if !isNowPlaying {
            playbackItems.append(MenuActionItem(
                id: .playNext,
                title: "Reproducir a continuación",
                systemImage: "text.line.first.and.arrowtriangle.forward"
            ))
        }

        playbackItems.append(MenuActionItem(
            id: .addToQueue,
            title: "Añadir a la cola",
            systemImage: "text.line.last.and.arrowtriangle.forward"
        ))

        if !playbackItems.isEmpty {
            sections.append(MenuSection(kind: .playback, items: playbackItems))
        }

        // --- 2. Colección / Biblioteca ---
        var collectionItems: [MenuActionItem] = []

        // Me gusta
        let likedTitle = facts.isLiked ? "Quitar de Tus Me Gusta" : "Añadir a Tus Me Gusta"
        let likedIcon = facts.isLiked ? "heart.slash" : "heart"
        collectionItems.append(MenuActionItem(
            id: .toggleLike,
            title: likedTitle,
            systemImage: likedIcon
        ))

        // Guardar en Biblioteca (solo si YouTube proveyó tokens válidos de fila)
        if let library = song.library,
           let token = library.inLibrary ? library.removeToken : library.addToken,
           !token.isEmpty {
            let libTitle = library.inLibrary ? "Quitar de Biblioteca" : "Guardar en Biblioteca"
            let libIcon = library.inLibrary ? "bookmark.fill" : "bookmark"
            collectionItems.append(MenuActionItem(
                id: .toggleLibrary(inLibrary: library.inLibrary),
                title: libTitle,
                systemImage: libIcon
            ))
        }

        // Añadir a lista de reproducción (siempre visible si tiene videoId)
        if !song.videoId.isEmpty {
            var playlistSubitems: [MenuActionItem] = []
            for playlist in facts.userPlaylists {
                let isLikes = playlist.id == "LM" || playlist.title.localizedCaseInsensitiveContains("me gusta")
                let plIcon = isLikes ? "heart.fill" : "music.note.list"
                playlistSubitems.append(MenuActionItem(
                    id: .addToPlaylist(playlistId: playlist.id, title: playlist.title),
                    title: playlist.title,
                    systemImage: plIcon
                ))
            }

            playlistSubitems.append(MenuActionItem(
                id: .createPlaylistAndAdd,
                title: "Nueva playlist…",
                systemImage: "plus.circle"
            ))

            collectionItems.append(MenuActionItem(
                id: .addToPlaylist(playlistId: "", title: ""),
                title: "Añadir a lista de reproducción",
                systemImage: "text.badge.plus",
                subitems: playlistSubitems
            ))
        }

        if !collectionItems.isEmpty {
            sections.append(MenuSection(kind: .collection, items: collectionItems))
        }

        // --- 3. Navegación ---
        var navigationItems: [MenuActionItem] = []

        // Ir al álbum (oculto si ya estamos en ese álbum)
        if let albumId = song.albumId, !albumId.isEmpty {
            let isCurrentAlbum: Bool
            if case .album(let currentBrowseId) = origin {
                isCurrentAlbum = MenuIDNormalizer.normalize(currentBrowseId) == MenuIDNormalizer.normalize(albumId)
            } else {
                isCurrentAlbum = false
            }

            if !isCurrentAlbum {
                navigationItems.append(MenuActionItem(
                    id: .goToAlbum(browseId: albumId),
                    title: "Ir al álbum",
                    systemImage: "opticaldisc"
                ))
            }
        }

        // Ir a artista (oculto si ya estamos en esa página de artista)
        if let artistId = song.artistId, !artistId.isEmpty {
            let isCurrentArtist: Bool
            if case .artist(let currentArtistId) = origin {
                isCurrentArtist = MenuIDNormalizer.normalize(currentArtistId) == MenuIDNormalizer.normalize(artistId)
            } else {
                isCurrentArtist = false
            }

            if !isCurrentArtist {
                navigationItems.append(MenuActionItem(
                    id: .goToArtist(channelId: artistId),
                    title: "Ir a artista",
                    systemImage: "person.crop.circle"
                ))
            }
        }

        if !navigationItems.isEmpty {
            sections.append(MenuSection(kind: .navigation, items: navigationItems))
        }

        // --- 4. Compartir ---
        if !song.videoId.isEmpty {
            sections.append(MenuSection(kind: .share, items: [
                MenuActionItem(
                    id: .share,
                    title: "Compartir",
                    systemImage: "square.and.arrow.up"
                )
            ]))
        }

        // --- 5. Edición y Destructivas ---
        var destructiveItems: [MenuActionItem] = []

        // Eliminar de esta playlist (si estamos en playlist propia con callback)
        if case .playlist = origin,
           facts.isOwned.isTrue,
           facts.onRemoveFromPlaylist != nil {
            destructiveItems.append(MenuActionItem(
                id: .removeFromPlaylist,
                title: "Eliminar de esta playlist",
                systemImage: "trash",
                isDestructive: true
            ))
        }

        // Quitar de la cola (si estamos en la cola por índice exacto de ocurrencia)
        if case .queue(let occIndex) = origin {
            if !facts.isCurrentPlayingTrack {
                destructiveItems.append(MenuActionItem(
                    id: .removeFromQueue(index: occIndex),
                    title: "Quitar de la cola",
                    systemImage: "minus.circle",
                    isDestructive: true
                ))
            }
        }

        if !destructiveItems.isEmpty {
            sections.append(MenuSection(kind: .destructive, items: destructiveItems))
        }

        return sections
    }

    // MARK: - 2. Álbum

    private static func resolveAlbumSections(
        browseId: String,
        playlistId: String?,
        title: String,
        artist: String?,
        artistId: String?,
        thumbnail: String?,
        origin: MenuOrigin,
        facts: MenuFacts
    ) -> [MenuSection] {
        var sections: [MenuSection] = []

        // --- 1. Reproducción ---
        sections.append(MenuSection(kind: .playback, items: [
            MenuActionItem(id: .play, title: "Reproducir", systemImage: "play.fill"),
            MenuActionItem(id: .shuffle, title: "Aleatorio", systemImage: "shuffle"),
            MenuActionItem(id: .startMix, title: "Iniciar mix", systemImage: "dot.radiowaves.left.and.right"),
            MenuActionItem(id: .playNext, title: "Reproducir a continuación", systemImage: "text.line.first.and.arrowtriangle.forward"),
            MenuActionItem(id: .addToQueue, title: "Añadir a la cola", systemImage: "text.line.last.and.arrowtriangle.forward")
        ]))

        // --- 2. Colección ---
        if case .known(let inLib) = facts.inLibrary {
            let libTitle = inLib ? "Quitar álbum de la biblioteca" : "Guardar álbum en la biblioteca"
            let libIcon = inLib ? "bookmark.fill" : "bookmark"
            sections.append(MenuSection(kind: .collection, items: [
                MenuActionItem(id: .toggleLibrary(inLibrary: inLib), title: libTitle, systemImage: libIcon)
            ]))
        }

        // --- 3. Navegación ---
        var navItems: [MenuActionItem] = []
        let isCurrentAlbum: Bool
        if case .album(let currentBrowseId) = origin {
            isCurrentAlbum = MenuIDNormalizer.normalize(currentBrowseId) == MenuIDNormalizer.normalize(browseId)
        } else {
            isCurrentAlbum = false
        }

        if !isCurrentAlbum {
            navItems.append(MenuActionItem(
                id: .goToAlbum(browseId: browseId),
                title: "Ver álbum",
                systemImage: "opticaldisc"
            ))
        }

        if let artistId = artistId, !artistId.isEmpty {
            let isCurrentArtist: Bool
            if case .artist(let currentArtistId) = origin {
                isCurrentArtist = MenuIDNormalizer.normalize(currentArtistId) == MenuIDNormalizer.normalize(artistId)
            } else {
                isCurrentArtist = false
            }

            if !isCurrentArtist {
                navItems.append(MenuActionItem(
                    id: .goToArtist(channelId: artistId),
                    title: "Ir al artista",
                    systemImage: "person.crop.circle"
                ))
            }
        }

        if !navItems.isEmpty {
            sections.append(MenuSection(kind: .navigation, items: navItems))
        }

        // --- 4. Compartir ---
        sections.append(MenuSection(kind: .share, items: [
            MenuActionItem(id: .share, title: "Compartir", systemImage: "square.and.arrow.up")
        ]))

        return sections
    }

    // MARK: - 3. Playlist propia o ajena

    private static func resolvePlaylistSections(
        id: String,
        title: String,
        subtitle: String?,
        thumbnail: String?,
        origin: MenuOrigin,
        facts: MenuFacts
    ) -> [MenuSection] {
        var sections: [MenuSection] = []

        // --- 1. Reproducción ---
        var playbackItems: [MenuActionItem] = [
            MenuActionItem(id: .play, title: "Reproducir", systemImage: "play.fill")
        ]

        // El ejecutor resuelve todas las páginas antes de realizar acciones masivas.
        playbackItems.append(MenuActionItem(id: .shuffle, title: "Aleatorio", systemImage: "shuffle"))
        playbackItems.append(MenuActionItem(id: .startMix, title: "Iniciar mix", systemImage: "dot.radiowaves.left.and.right"))
        playbackItems.append(MenuActionItem(id: .playNext, title: "Reproducir a continuación", systemImage: "text.line.first.and.arrowtriangle.forward"))
        playbackItems.append(MenuActionItem(id: .addToQueue, title: "Añadir a la cola", systemImage: "text.line.last.and.arrowtriangle.forward"))

        sections.append(MenuSection(kind: .playback, items: playbackItems))

        // --- 2. Colección ---
        let canonicalId = MenuIDNormalizer.canonicalPlaylistId(id)
        if canonicalId != "LM" {
            // Si es ajena y conocemos el estado de biblioteca
            if !facts.isOwned.isTrue, case .known(let inLib) = facts.inLibrary {
                let libTitle = inLib ? "Quitar lista de reproducción de la biblioteca" : "Guardar lista de reproducción en la biblioteca"
                let libIcon = inLib ? "bookmark.fill" : "bookmark"
                sections.append(MenuSection(kind: .collection, items: [
                    MenuActionItem(id: .toggleLibrary(inLibrary: inLib), title: libTitle, systemImage: libIcon)
                ]))
            }
        }

        // --- 3. Navegación ---
        let isCurrentPlaylist: Bool
        if case .playlist(let currentId) = origin {
            isCurrentPlaylist = MenuIDNormalizer.normalize(currentId) == MenuIDNormalizer.normalize(id)
        } else {
            isCurrentPlaylist = false
        }

        if !isCurrentPlaylist {
            sections.append(MenuSection(kind: .navigation, items: [
                MenuActionItem(id: .goToPlaylist(id: id), title: "Ver playlist", systemImage: "music.note.list")
            ]))
        }

        // --- 4. Compartir ---
        sections.append(MenuSection(kind: .share, items: [
            MenuActionItem(id: .share, title: "Compartir", systemImage: "square.and.arrow.up")
        ]))

        // --- 5. Edición y Destructivas (Playlist propia) ---
        if facts.isOwned.isTrue {
            var destructiveItems: [MenuActionItem] = []

            destructiveItems.append(MenuActionItem(
                id: .editDetails,
                title: "Editar detalles",
                systemImage: "pencil"
            ))

            if facts.sortEditable {
                let sortSubmenu: [MenuActionItem] = [
                    MenuActionItem(id: .sort(value: "default", title: "Orden manual"), title: "Orden manual", systemImage: "line.3.horizontal"),
                    MenuActionItem(id: .sort(value: "newest", title: "Más recientes"), title: "Más recientes", systemImage: "clock.arrow.circlepath"),
                    MenuActionItem(id: .sort(value: "oldest", title: "Más antiguas"), title: "Más antiguas", systemImage: "clock"),
                    MenuActionItem(id: .sort(value: "title", title: "Título"), title: "Título", systemImage: "textformat.abc"),
                    MenuActionItem(id: .sort(value: "artist", title: "Artista"), title: "Artista", systemImage: "person.crop.circle"),
                    MenuActionItem(id: .sort(value: "album", title: "Álbum"), title: "Álbum", systemImage: "opticaldisc")
                ]
                destructiveItems.append(MenuActionItem(
                    id: .sort(value: "", title: ""),
                    title: "Ordenar",
                    systemImage: "arrow.up.arrow.down",
                    subitems: sortSubmenu
                ))
            }

            destructiveItems.append(MenuActionItem(
                id: .deletePlaylist,
                title: "Eliminar playlist",
                systemImage: "trash",
                isDestructive: true
            ))

            sections.append(MenuSection(kind: .destructive, items: destructiveItems))
        }

        return sections
    }

    // MARK: - 4. Mix dinámico / Radio

    private static func resolveRadioMixSections(
        id: String,
        title: String,
        subtitle: String?,
        thumbnail: String?,
        origin: MenuOrigin,
        facts: MenuFacts
    ) -> [MenuSection] {
        var sections: [MenuSection] = []

        // --- 1. Reproducción (Solo radio continua; sin aleatorio ni añadir toda la cola) ---
        sections.append(MenuSection(kind: .playback, items: [
            MenuActionItem(id: .play, title: "Reproducir mix", systemImage: "dot.radiowaves.left.and.right")
        ]))

        // --- 2. Colección ---
        if case .known(let inLib) = facts.inLibrary {
            let libTitle = inLib ? "Quitar mix de la biblioteca" : "Guardar mix en la biblioteca"
            let libIcon = inLib ? "bookmark.fill" : "bookmark"
            sections.append(MenuSection(kind: .collection, items: [
                MenuActionItem(id: .toggleLibrary(inLibrary: inLib), title: libTitle, systemImage: libIcon)
            ]))
        }

        // --- 3. Navegación ---
        let isCurrent: Bool
        if case .playlist(let currentId) = origin {
            isCurrent = MenuIDNormalizer.normalize(currentId) == MenuIDNormalizer.normalize(id)
        } else {
            isCurrent = false
        }

        // Si no estamos ya en esa página y es navegable
        if !isCurrent {
            sections.append(MenuSection(kind: .navigation, items: [
                MenuActionItem(id: .goToPlaylist(id: id), title: "Ver mix", systemImage: "dot.radiowaves.left.and.right")
            ]))
        }

        // --- 4. Compartir ---
        sections.append(MenuSection(kind: .share, items: [
            MenuActionItem(id: .share, title: "Compartir", systemImage: "square.and.arrow.up")
        ]))

        return sections
    }

    // MARK: - 5. Artista

    private static func resolveArtistSections(
        channelId: String,
        name: String,
        thumbnail: String?,
        radioPlaylistId: String?,
        origin: MenuOrigin,
        facts: MenuFacts
    ) -> [MenuSection] {
        var sections: [MenuSection] = []

        // --- 1. Reproducción ---
        sections.append(MenuSection(kind: .playback, items: [
            MenuActionItem(id: .startMix, title: "Iniciar mix", systemImage: "dot.radiowaves.left.and.right")
        ]))

        // --- 2. Colección (Suscripción si es conocida) ---
        if case .known(let subscribed) = facts.isSubscribed {
            let subTitle = subscribed ? "Cancelar suscripción" : "Suscribirse"
            let subIcon = subscribed ? "bell.slash" : "bell.badge"
            sections.append(MenuSection(kind: .collection, items: [
                MenuActionItem(id: .toggleSubscription(subscribed: subscribed), title: subTitle, systemImage: subIcon)
            ]))
        }

        // --- 3. Navegación ---
        let isCurrentArtist: Bool
        if case .artist(let currentArtistId) = origin {
            isCurrentArtist = MenuIDNormalizer.normalize(currentArtistId) == MenuIDNormalizer.normalize(channelId)
        } else {
            isCurrentArtist = false
        }

        if !isCurrentArtist {
            sections.append(MenuSection(kind: .navigation, items: [
                MenuActionItem(id: .goToArtist(channelId: channelId), title: "Ver artista", systemImage: "person.crop.circle")
            ]))
        }

        // --- 4. Compartir ---
        sections.append(MenuSection(kind: .share, items: [
            MenuActionItem(id: .share, title: "Compartir", systemImage: "square.and.arrow.up")
        ]))

        return sections
    }
}
