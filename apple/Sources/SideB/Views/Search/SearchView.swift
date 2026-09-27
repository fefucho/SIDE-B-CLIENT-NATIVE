import SwiftUI
import SideBCore

// MARK: - SearchView

struct SearchView: View {
    let initialQuery: String
    let rustCore: SideBCore
    var playerViewModel: PlayerViewModel
    @Bindable var router: NavigationRouter
    @Bindable var searchViewModel: SearchViewModel
    @FocusState private var isSearchBarFocused: Bool
    
    init(
        initialQuery: String,
        rustCore: SideBCore,
        playerViewModel: PlayerViewModel,
        router: NavigationRouter,
        searchViewModel: SearchViewModel
    ) {
        self.initialQuery = initialQuery
        self.rustCore = rustCore
        self.playerViewModel = playerViewModel
        self.router = router
        self.searchViewModel = searchViewModel
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Fondo oscuro uniforme de Side B
            Color.sidebDarkBackground
                .ignoresSafeArea()
                .onTapGesture {
                    // Cerrar dropdown topdown y retirar foco si se hace clic en el fondo
                    isSearchBarFocused = false
                    searchViewModel.isTopdownVisible = false
                }
            
            VStack(spacing: 0) {
                // MARK: - 1. Cabecera Fija con Barra Superior y Chips
                VStack(spacing: 12) {
                    topSearchBar
                        .zIndex(20)
                    
                    filterChipsBar
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 12)
                .background(
                    Color.sidebDarkBackground.opacity(0.85)
                        .background(.ultraThinMaterial)
                )
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.15)
                }
                .zIndex(10)
                
                // MARK: - 2. Contenido de la Página de Búsqueda
                ZStack {
                    if searchViewModel.isCommittedLoading || searchViewModel.isFilterLoading {
                        loadingStateView
                    } else {
                        switch searchViewModel.selectedFilter {
                        case .all:
                            allResultsView
                        case .songs:
                            songsFilterView
                        case .albums:
                            cardsGridView(cards: searchViewModel.filteredCards, kind: "album")
                        case .artists:
                            cardsGridView(cards: searchViewModel.filteredCards, kind: "artist")
                        case .playlists:
                            cardsGridView(cards: searchViewModel.filteredCards, kind: "playlist")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if !initialQuery.isEmpty {
                if searchViewModel.committedQuery != initialQuery || searchViewModel.committedResults == nil {
                    searchViewModel.query = initialQuery
                    searchViewModel.commitSearch(query: initialQuery, core: rustCore)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideBSongLibraryChanged)) { _ in
            if !searchViewModel.committedQuery.isEmpty {
                searchViewModel.commitSearch(query: searchViewModel.committedQuery, core: rustCore, force: true)
            }
        }
    }
    
    // MARK: - Barra Superior de Búsqueda con Topdown Dropdown
    
    private var topSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            
            TextField("Buscar en YouTube Music...", text: $searchViewModel.query)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .focused($isSearchBarFocused)
                .onSubmit {
                    isSearchBarFocused = false
                    searchViewModel.isTopdownVisible = false
                    searchViewModel.commitSearch(query: searchViewModel.query, core: rustCore, force: true)
                }
                .onChange(of: searchViewModel.query) { _, newText in
                    // Solo disparar debounce rápido si el usuario está interactuando activamente con el campo
                    if isSearchBarFocused {
                        searchViewModel.onQueryChanged(newText, core: rustCore)
                    }
                }
                .onChange(of: isSearchBarFocused) { _, isFocused in
                    if isFocused {
                        let trimmed = searchViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            searchViewModel.onQueryChanged(trimmed, core: rustCore)
                        }
                    } else {
                        searchViewModel.isTopdownVisible = false
                    }
                }
                .onKeyPress(.escape) {
                    isSearchBarFocused = false
                    searchViewModel.isTopdownVisible = false
                    return .handled
                }
            
            if searchViewModel.isQuickSearching {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            } else if !searchViewModel.query.isEmpty {
                Button {
                    searchViewModel.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .compatGlass(interactive: true, in: Capsule())
        .frame(maxWidth: 520)
        // MARK: - Topdown Dropdown Flotante Anclado Debajo de la Barra
        .overlay(alignment: .top) {
            if isSearchBarFocused && searchViewModel.isTopdownVisible && !searchViewModel.query.isEmpty {
                if let results = searchViewModel.quickResults,
                   searchViewModel.associatedQuickQuery == searchViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines) {
                    topdownDropdownView(results: results)
                        .padding(.top, 42)
                } else if searchViewModel.isQuickSearching {
                    topdownLoadingView
                        .padding(.top, 42)
                }
            }
        }
    }
    
    // MARK: - Dropdown Topdown de Carga
    
    private var topdownLoadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Buscando respuestas rápidas...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 520)
        .compatGlass(interactive: true, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 8)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
    
    // MARK: - Dropdown Topdown de Resultados Rápidos
    
    private func topdownDropdownView(results: SearchResultsRecord) -> some View {
        let categories = searchViewModel.dynamicCategories(for: results)
        let totalItems = (results.top.isEmpty ? 0 : 1)
            + min(results.artists.count, 2)
            + min(results.songs.count, 3)
            + min(results.albums.count, 2)
            + min(results.playlists.count, 2)
        
        let calculatedHeight: CGFloat = categories.isEmpty 
            ? 44 
            : min(CGFloat(totalItems * 48 + categories.count * 26 + 12), 340)
        
        return VStack(alignment: .leading, spacing: 8) {
            if categories.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("No se encontraron respuestas rápidas")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(categories) { category in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    Image(systemName: category.icon)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(category == .topResult ? .primary : .secondary)
                                    
                                    Text(category.rawValue.uppercased())
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(category == .topResult ? .primary : .secondary)
                                        .tracking(0.5)
                                }
                                .padding(.horizontal, 8)
                                
                                switch category {
                                case .topResult:
                                    if let hero = results.top.first {
                                        QuickResultCardRow(card: hero, isHero: true) {
                                            isSearchBarFocused = false
                                            handleQuickSelect(hero)
                                        }
                                        .browseCardContextMenu(card: hero, player: playerViewModel, router: router, core: rustCore, origin: .search)
                                    }
                                case .artists:
                                    ForEach(Array(results.artists.prefix(2)), id: \.id) { a in
                                        QuickResultCardRow(card: a) {
                                            isSearchBarFocused = false
                                            searchViewModel.isTopdownVisible = false
                                            router.navigate(to: .artist(browseId: a.id))
                                        }
                                        .browseCardContextMenu(card: a, player: playerViewModel, router: router, core: rustCore, origin: .search)
                                    }
                                case .songs:
                                    ForEach(Array(results.songs.prefix(3)), id: \.videoId) { s in
                                        QuickResultSongRow(song: s) {
                                            isSearchBarFocused = false
                                            searchViewModel.isTopdownVisible = false
                                            playerViewModel.playWithRadio(s)
                                        }
                                        .songContextMenu(song: s, player: playerViewModel, router: router, core: rustCore, origin: .search)
                                    }
                                case .albums:
                                    ForEach(Array(results.albums.prefix(2)), id: \.id) { alb in
                                        QuickResultCardRow(card: alb) {
                                            isSearchBarFocused = false
                                            searchViewModel.isTopdownVisible = false
                                            router.navigate(to: .album(browseId: alb.id))
                                        }
                                        .browseCardContextMenu(card: alb, player: playerViewModel, router: router, core: rustCore, origin: .search)
                                    }
                                case .playlists:
                                    ForEach(Array(results.playlists.prefix(2)), id: \.id) { pl in
                                        QuickResultCardRow(card: pl) {
                                            isSearchBarFocused = false
                                            searchViewModel.isTopdownVisible = false
                                            router.navigate(to: .playlist(browseId: pl.id))
                                        }
                                        .browseCardContextMenu(card: pl, player: playerViewModel, router: router, core: rustCore, origin: .search)
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(height: calculatedHeight)
            }
            
            Divider().opacity(0.15)
            
            // Botón para Confirmar y Actualizar la Página Completa
            Button {
                isSearchBarFocused = false
                searchViewModel.isTopdownVisible = false
                searchViewModel.commitSearch(query: searchViewModel.query, core: rustCore, force: true)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text("Presiona Enter para ver todos los resultados")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .padding(.top, 2)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .compatGlass(interactive: true, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 8)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
    
    private func handleQuickSelect(_ card: BrowseCardRecord) {
        searchViewModel.isTopdownVisible = false
        switch card.kind.lowercased() {
        case "artist":
            router.navigate(to: .artist(browseId: card.id))
        case "album":
            router.navigate(to: .album(browseId: card.id))
        case "playlist":
            router.navigate(to: .playlist(browseId: card.id))
        case "song":
            let song = SongItemRecord(fromCard: card)
            playerViewModel.playWithRadio(song)
        default:
            searchViewModel.commitSearch(query: card.title, core: rustCore, force: true)
        }
    }
    
    // MARK: - Barra de Chips de Filtro
    
    private var filterChipsBar: some View {
        HStack(spacing: 8) {
            ForEach(SearchFilter.allCases) { filter in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        searchViewModel.selectFilter(filter, core: rustCore)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: filter.icon)
                            .font(.system(size: 11, weight: .semibold))
                        
                        Text(filter.rawValue)
                            .font(.system(size: 11.5, weight: searchViewModel.selectedFilter == filter ? .semibold : .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        searchViewModel.selectedFilter == filter
                            ? Color.white.opacity(0.16)
                            : Color.white.opacity(0.08),
                        in: Capsule()
                    )
                    .foregroundStyle(searchViewModel.selectedFilter == filter ? Color.white : Color.primary.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Vista "Todo" (Resultados Mixtos)
    
    private var allResultsView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                if let results = searchViewModel.committedResults {
                    // 1. Top Result / Hero Card si existe
                    if let hero = results.top.first {
                        heroCardView(hero)
                    }
                    
                    // 2. Sección Canciones (Hasta 5 pistas destacadas)
                    if !results.songs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Canciones")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                Button("Ver todas") {
                                    searchViewModel.selectFilter(.songs, core: rustCore)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .buttonStyle(.plain)
                            }
                            
                            let topSongs: [SongItemRecord] = Array(results.songs.prefix(5))
                            VStack(spacing: 4) {
                                ForEach(topSongs, id: \.videoId) { song in
                                    let row = songInlineRow(song: song)
                                    row.songContextMenu(
                                        song: song,
                                        player: playerViewModel,
                                        router: router,
                                        core: rustCore,
                                        origin: .search
                                    )
                                }
                            }
                        }
                    }
                    
                    // 3. Sección Álbumes
                    if !results.albums.isEmpty {
                        cardsSection(title: "Álbumes", cards: results.albums, kind: "album")
                    }
                    
                    // 4. Sección Artistas
                    if !results.artists.isEmpty {
                        cardsSection(title: "Artistas", cards: results.artists, kind: "artist")
                    }
                    
                    // 5. Sección Playlists
                    if !results.playlists.isEmpty {
                        cardsSection(title: "Playlists", cards: results.playlists, kind: "playlist")
                    }
                } else if !searchViewModel.committedQuery.isEmpty {
                    noResultsView
                } else {
                    initialEmptyStateView
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .padding(.bottom, 120) // Margen para la PlayerBar flotante
        }
    }
    
    // MARK: - Tarjeta Hero / Top Result
    
    private func heroCardView(_ card: BrowseCardRecord) -> some View {
        let isArtist = card.kind.lowercased() == "artist"
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("Mejor resultado")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
            
            Button {
                handleCardClick(card)
            } label: {
                HStack(spacing: 16) {
                    if let thumb = card.thumbnail,
                       let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: 180) {
                        CachedAsyncImage(url: url, targetSize: CGSize(width: 80, height: 80)) { img in
                            img
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.secondary.opacity(0.12)
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous)))
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Text(isArtist ? "Artista" : (card.subtitle ?? card.kind.capitalized))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Text(isArtist ? "Ver discografía completa" : "Reproducir ahora")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isArtist ? "arrow.right.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.primary)
                        .padding(.trailing, 8)
                }
                .padding(16)
                .compatGlass(interactive: true, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .browseCardContextMenu(card: card, player: playerViewModel, router: router, core: rustCore, origin: .search)
        }
    }
    
    // MARK: - Filtro de Canciones (NativeTrackTableView a 120 FPS)
    
    private var songsFilterView: some View {
        Group {
            if searchViewModel.filteredSongs.isEmpty {
                noResultsView
            } else {
                NativeTrackTableView(
                    tracks: searchViewModel.filteredSongs,
                    currentTrackVideoId: playerViewModel.currentTrack?.videoId,
                    isPlaying: playerViewModel.isPlaying,
                    playerViewModel: playerViewModel,
                    router: router,
                    rustCore: rustCore,
                    hideAlbumColumn: false,
                    showAlbumInSubtitle: true,
                    rowHeight: 52.0,
                    likedVideoIds: playerViewModel.likedVideoIds,
                    menuOrigin: { _ in .search },
                    onPlayTrack: { index in
                        if index >= 0 && index < searchViewModel.filteredSongs.count {
                            playerViewModel.playWithRadio(searchViewModel.filteredSongs[index])
                        }
                    },
                    onLikeTrack: { track in
                        playerViewModel.toggleTrackLike(track)
                    },
                    onDislikeTrack: { track in
                        playerViewModel.dislikeTrack(track)
                    },
                    contentInsets: NSEdgeInsets(top: 10, left: 24, bottom: 120, right: 24)
                )
            }
        }
    }
    
    // MARK: - Secciones Horizontales de Tarjetas
    
    private func cardsSection(title: String, cards: [BrowseCardRecord], kind: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(cards.prefix(12), id: \.id) { card in
                        browseCardItem(card: card)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    // MARK: - Grilla Completa de Tarjetas para Filtros Específicos
    
    private func cardsGridView(cards: [BrowseCardRecord], kind: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            if cards.isEmpty {
                noResultsView
            } else {
                let isArtist = kind == "artist"
                let columns = [GridItem(.adaptive(minimum: isArtist ? 130 : 150, maximum: 180), spacing: 20)]
                
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(cards, id: \.id) { card in
                        browseCardItem(card: card)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .padding(.bottom, 120)
            }
        }
    }
    
    // MARK: - Item de Tarjeta Individual con Clic Derecho Universal
    
    @ViewBuilder
    private func browseCardItem(card: BrowseCardRecord) -> some View {
        let isArtist = card.kind.lowercased() == "artist"
        let cardSize: CGFloat = isArtist ? 130 : 144
        
        let cardButton = Button {
            handleCardClick(card)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .bottomTrailing) {
                    if let thumb = card.thumbnail,
                       let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: 288) {
                        CachedAsyncImage(url: url, targetSize: CGSize(width: cardSize, height: cardSize)) { img in
                            img
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.secondary.opacity(0.12)
                        }
                        .frame(width: cardSize, height: cardSize)
                        .clipShape(isArtist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous)))
                        .overlay(
                            isArtist
                                ? AnyView(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                                : AnyView(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                        )
                    } else {
                        RoundedRectangle(cornerRadius: isArtist ? cardSize / 2 : 10, style: .continuous)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: cardSize, height: cardSize)
                            .overlay(Image(systemName: isArtist ? "person.crop.circle" : "music.note").font(.system(size: 28)))
                    }
                    
                    // Botón de reproducción flotante
                    Image(systemName: isArtist ? "arrow.right.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.4), radius: 4)
                        .padding(6)
                }
                
                Text(card.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if let subtitle = card.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: cardSize)
        }
        .buttonStyle(.plain)
        
        cardButton.browseCardContextMenu(card: card, player: playerViewModel, router: router, core: rustCore, origin: .search)
    }
    
    // MARK: - Fila de Canción Inline (para Vista "Todo")
    
    private func songInlineRow(song: SongItemRecord) -> some View {
        Button {
            playerViewModel.playWithRadio(song)
        } label: {
            HStack(spacing: 12) {
                if let thumb = song.thumbnail,
                   let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: 96) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 40, height: 40)) { img in
                        img
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.06))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.system(size: 13, weight: playerViewModel.currentTrack?.videoId == song.videoId ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(song.artists)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if let dur = song.duration {
                    Text(dur)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                
                Image(systemName: playerViewModel.currentTrack?.videoId == song.videoId && playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.trailing, 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .songContextMenu(song: song, player: playerViewModel, router: router, core: rustCore, origin: .search)
    }
    
    // MARK: - Navegación de Tarjeta
    
    private func handleCardClick(_ card: BrowseCardRecord) {
        switch card.kind.lowercased() {
        case "artist":
            router.navigate(to: .artist(browseId: card.id))
        case "album":
            router.navigate(to: .album(browseId: card.id))
        case "playlist":
            router.navigate(to: .playlist(browseId: card.id))
        case "song":
            let song = SongItemRecord(fromCard: card)
            playerViewModel.playWithRadio(song)
        default:
            searchViewModel.commitSearch(query: card.title, core: rustCore, force: true)
        }
    }
    
    // MARK: - Estados Vacíos y de Carga
    
    private var loadingStateView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Buscando en el catálogo...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
                .padding(.top, 40)
            
            Text("No se encontraron resultados para \"\(searchViewModel.committedQuery)\"")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            
            Text("Verifica la ortografía o intenta buscar por otro artista o título.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }
    
    private var initialEmptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary.opacity(0.4))
                .padding(.top, 60)
            
            Text("Explora el catálogo de música")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            
            Text("Escribe en la barra superior para buscar canciones, artistas o álbumes.")
                .font(.system(size: 12.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
