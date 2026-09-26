import SwiftUI
import SideBCore

struct LibraryView: View {
    let rustCore: SideBCore
    @Bindable var playerViewModel: PlayerViewModel
    @Bindable var libraryViewModel: LibraryViewModel
    @Bindable var accountViewModel: AccountViewModel
    @Bindable var router: NavigationRouter

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 18)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COLECCIÓN")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)
                    Text("Biblioteca")
                        .font(.system(size: 32, weight: .bold))
                }
                Spacer()
                if accountViewModel.isLoggedIn {
                    Button {
                        NotificationCenter.default.post(name: .sideBRequestCreatePlaylist, object: nil)
                    } label: {
                        Label("Nueva playlist", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .help("Crear una playlist")
                }
            }
            .padding(.horizontal, 32)
            .padding(.trailing, 110)
            .padding(.top, 24)
            .padding(.bottom, 18)

            HStack(spacing: 8) {
                ForEach(LibraryPageTab.allCases) { tab in
                    Button {
                        libraryViewModel.selectedPageTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .foregroundStyle(libraryViewModel.selectedPageTab == tab ? Color.white : Color.primary)
                            .background(
                                libraryViewModel.selectedPageTab == tab ? Color.sidebAccent : Color.primary.opacity(0.08),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(libraryViewModel.selectedPageTab == tab ? .isSelected : [])
                }
                Spacer()
                Button {
                    Task { await reloadSelectedTab() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Actualizar biblioteca")
                .accessibilityLabel("Actualizar biblioteca")
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 14)

            Divider().opacity(0.2).padding(.horizontal, 32)

            Group {
                if !accountViewModel.isLoggedIn {
                    emptyState("Iniciá sesión para ver tu biblioteca", icon: "person.crop.circle")
                } else {
                    switch libraryViewModel.selectedPageTab {
                    case .songs: songsContent
                    case .playlists: cardsContent(libraryViewModel.playlists, icon: "music.note.list", title: "No tenés playlists")
                    case .albums: cardsContent(libraryViewModel.albums, icon: "opticaldisc", title: "No tenés álbumes guardados")
                    case .artists: cardsContent(libraryViewModel.artists, icon: "person.crop.circle", title: "No tenés artistas en tu biblioteca")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: libraryViewModel.selectedPageTab) {
            await loadSelectedTabIfNeeded()
        }
        .onChange(of: accountViewModel.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                Task { await loadSelectedTabIfNeeded() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideBSongLibraryChanged)) { _ in
            if libraryViewModel.selectedPageTab == .songs {
                Task { await libraryViewModel.loadSongs(core: rustCore) }
            }
        }
    }

    @ViewBuilder
    private var songsContent: some View {
        if libraryViewModel.isSongsLoading && libraryViewModel.songs.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = libraryViewModel.songsErrorMessage, libraryViewModel.songs.isEmpty {
            DetailErrorStateView(title: "No se pudieron cargar las canciones", message: error) {
                Task { await libraryViewModel.loadSongs(core: rustCore) }
            }
        } else if libraryViewModel.songs.isEmpty {
            emptyState("No hay canciones en tu biblioteca", icon: "music.note")
        } else {
            VStack(spacing: 0) {
                NativeTrackTableView(
                    tracks: libraryViewModel.songs,
                    currentTrackVideoId: playerViewModel.currentTrack?.videoId,
                    isPlaying: playerViewModel.isPlaying,
                    playerViewModel: playerViewModel,
                    router: router,
                    rustCore: rustCore,
                    likedVideoIds: playerViewModel.likedVideoIds,
                    menuOrigin: { _ in .library },
                    onPlayTrack: { index in
                        playerViewModel.playPlaylist(
                            browseId: "FEmusic_liked_videos", title: "Biblioteca",
                            tracks: libraryViewModel.songs, startingAt: index,
                            continuation: libraryViewModel.songsContinuation
                        )
                    },
                    onLikeTrack: { playerViewModel.toggleTrackLike($0) },
                    onDislikeTrack: { playerViewModel.dislikeTrack($0) },
                    onNearBottom: {
                        Task { await libraryViewModel.loadMoreSongs(core: rustCore) }
                    }
                )
                if let error = libraryViewModel.songsErrorMessage {
                    HStack(spacing: 10) {
                        Text("No se pudo actualizar Canciones: \(error)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Button("Reintentar") {
                            Task { await libraryViewModel.loadSongs(core: rustCore) }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.sidebAccent)
                    }
                    .padding(.horizontal, 32)
                }
                if libraryViewModel.isSongsLoadingMore {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .padding(.bottom, 110)
                } else if libraryViewModel.songsContinuation != nil {
                    Button("Cargar más canciones") {
                        Task { await libraryViewModel.loadMoreSongs(core: rustCore) }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .padding(8)
                    .padding(.bottom, 110)
                }
            }
        }
    }

    @ViewBuilder
    private func cardsContent(_ cards: [BrowseCardRecord], icon: String, title: String) -> some View {
        if libraryViewModel.isLoading && cards.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if libraryViewModel.selectedPageTab == .artists && libraryViewModel.isArtistsLoading && cards.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = cardError, cards.isEmpty {
            DetailErrorStateView(title: "No se pudo cargar la biblioteca", message: error) {
                Task { await reloadSelectedTab() }
            }
        } else if cards.isEmpty {
            emptyState(title, icon: icon)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(cards, id: \.id) { card in
                        Button {
                            switch libraryViewModel.selectedPageTab {
                            case .playlists: router.navigate(to: .playlist(browseId: card.id))
                            case .albums: router.navigate(to: .album(browseId: card.id))
                            case .artists: router.navigate(to: .artist(browseId: card.id))
                            case .songs: break
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                if let thumbnail = card.thumbnail, let url = URL(string: thumbnail) {
                                    CachedAsyncImage(url: url, targetSize: CGSize(width: 200, height: 200)) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        artworkPlaceholder(icon)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: libraryViewModel.selectedPageTab == .artists ? 100 : 10))
                                } else {
                                    artworkPlaceholder(icon)
                                        .frame(maxWidth: .infinity)
                                        .aspectRatio(1, contentMode: .fit)
                                }
                                Text(card.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(2)
                                if let subtitle = card.subtitle {
                                    Text(subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .browseCardContextMenu(card: card, player: playerViewModel, router: router, core: rustCore, origin: .library)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)
                .padding(.bottom, 130)
            }
        }
    }

    private var cardError: String? {
        switch libraryViewModel.selectedPageTab {
        case .playlists: libraryViewModel.playlistsErrorMessage
        case .albums: libraryViewModel.albumsErrorMessage
        case .artists: libraryViewModel.artistsErrorMessage
        case .songs: nil
        }
    }

    private func artworkPlaceholder(_ icon: String) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .overlay { Image(systemName: icon).font(.system(size: 36)).foregroundStyle(.secondary) }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func emptyState(_ title: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 38)).foregroundStyle(.tertiary)
            Text(title).font(.headline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadSelectedTabIfNeeded() async {
        guard accountViewModel.isLoggedIn else { return }
        switch libraryViewModel.selectedPageTab {
        case .songs:
            if libraryViewModel.songs.isEmpty { await libraryViewModel.loadSongs(core: rustCore) }
        case .artists:
            if libraryViewModel.artists.isEmpty { await libraryViewModel.loadArtists(core: rustCore) }
        case .playlists, .albums:
            if libraryViewModel.playlists.isEmpty && libraryViewModel.albums.isEmpty {
                await libraryViewModel.loadLibrary(core: rustCore)
            }
        }
    }

    private func reloadSelectedTab() async {
        guard accountViewModel.isLoggedIn else { return }
        switch libraryViewModel.selectedPageTab {
        case .songs: await libraryViewModel.loadSongs(core: rustCore)
        case .artists: await libraryViewModel.loadArtists(core: rustCore)
        case .playlists, .albums: await libraryViewModel.loadLibrary(core: rustCore)
        }
    }
}
