import SwiftUI
import SideBCore

// MARK: - FullscreenPanel

public enum FullscreenPanel: String, CaseIterable, Identifiable {
    case queue = "Cola"
    case lyrics = "Letras"
    case recommended = "Relacionado"
    
    public var id: String { self.rawValue }
    
    public var icon: String {
        switch self {
        case .queue: return "list.bullet"
        case .lyrics: return "quote.bubble"
        case .recommended: return "music.note.list"
        }
    }
}

// MARK: - FullscreenNowPlayingView (Proporcional 60/40, Sólido y Resistente a Resizing)

struct FullscreenNowPlayingView: View {
    @Bindable var viewModel: PlayerViewModel
    @Binding var isSidebarExpanded: Bool
    var router: NavigationRouter? = nil
    
    private var selectedPanel: FullscreenPanel {
        get { viewModel.selectedFullscreenPanel }
        nonmutating set { viewModel.selectedFullscreenPanel = newValue }
    }
    @State private var isHoveringArtwork: Bool = false
    @State private var isHoveringArtist: Bool = false
    @State private var isHoveringAlbum: Bool = false
    @State private var currentLyricIndex: Int? = nil
    @State private var failedMaxQualityURL: URL? = nil
    
    @Namespace private var tabNamespace
    
    var body: some View {
        GeometryReader { proxy in
            let windowWidth = proxy.size.width
            let windowHeight = proxy.size.height
            
            // 1. Zonas de seguridad vertical
            // Mantener las pestañas bajo los traffic lights nativos, mientras
            // el fondo se extiende detrás de ellos.
            let topPadding: CGFloat = 52
            // Espacio inferior reservado para la PlayerBar fija de Capa 3 (74pt de cápsula + 20pt padding + 18pt respiro = 112pt)
            let bottomReservedHeight: CGFloat = 112
            
            // Altura vertical disponible para el contenido (Cola / Letras / Artwork)
            let availableContentHeight = max(200, windowHeight - topPadding - bottomReservedHeight)
            
            // 2. Márgenes horizontales y distribución entre columnas (52/48 adaptativo)
            let horizontalPadding: CGFloat = max(24, min(48, windowWidth * 0.035))
            let columnSpacing: CGFloat = max(24, min(40, windowWidth * 0.028))
            let totalAvailableWidth = max(0, windowWidth - (horizontalPadding * 2) - columnSpacing)
            
            // Proporción adaptativa entre Columna Izquierda (Artwork) y Columna Derecha (Queue / Lyrics / Recommended)
            // Se garantiza al menos 340pt para la cola/recomendados con un techo amplio de hasta 600pt para máxima amplitud
            let idealRightWidth = totalAvailableWidth * 0.52
            let maxAllowedRightWidth = max(300, totalAvailableWidth * 0.56)
            let minRightWidth: CGFloat = min(340, maxAllowedRightWidth)
            let rightWidth = min(maxAllowedRightWidth, max(minRightWidth, min(600, idealRightWidth)))
            
            // Ancho de la Columna Izquierda (restante)
            let leftWidth = max(100, totalAvailableWidth - rightWidth)
            
            // 3. Dimensionamiento del Artwork (1:1 Cuadrado) y Metadata agrandada
            let metadataSpacing: CGFloat = 16
            let metadataHeight: CGFloat = 68
            
            // Altura máxima que puede tener la imagen sin desbordar verticalmente
            let maxArtHeight = max(100, availableContentHeight - metadataSpacing - metadataHeight - 16)
            
            // El Artwork es 1:1: ligeramente más contenido (90% del ancho izquierdo) para dar respiro visual
            let maxArtWidth = leftWidth * 0.90
            let artworkSize = max(100, min(maxArtWidth, maxArtHeight))
            
            // 4. Altura del Panel de Contenido Derecho (Cola / Letras / Relacionado)
            // Selector de pestañas cápsula (40pt) + spacing (14pt) = 54pt
            let contentPanelHeight = max(80, availableContentHeight - 40 - 14)
            
            ZStack(alignment: .top) {
                // 1. Fondo Dinámico 100% Sólido (Sin bordes transparentes ni difuminado hacia las puntas)
                backgroundArtworkBlur(width: windowWidth, height: windowHeight)
                
                // 2. Contenedor de Contenido con Geometría Rígida
                VStack(spacing: 0) {
                    // Margen superior para los semáforos de macOS
                    Color.clear.frame(height: topPadding)
                    
                    // Fila Principal con las 2 Columnas
                    HStack(alignment: .top, spacing: columnSpacing) {
                        // COLUMNA IZQUIERDA: Bloque Integrado Artwork + Metadata
                        // Centrado verticalmente dentro de availableContentHeight para armonía visual
                        VStack(alignment: .leading, spacing: metadataSpacing) {
                            artworkView(size: artworkSize)
                            trackInfoView(width: artworkSize)
                        }
                        .frame(width: artworkSize)
                        .frame(maxWidth: leftWidth, maxHeight: availableContentHeight, alignment: .center)
                        
                        // COLUMNA DERECHA: Selector Centrado Arriba + Cola/Letras a Toda la Altura
                        VStack(alignment: .center, spacing: 14) {
                            // Selector de Pestañas Compacto Centrado (Estilo Cápsula)
                            compactTabBar
                            
                            // Panel de Contenido Transparente
                            contentPanelView(height: contentPanelHeight)
                                .frame(width: rightWidth, height: contentPanelHeight)
                        }
                        .frame(width: rightWidth, height: availableContentHeight, alignment: .top)
                    }
                    .frame(height: availableContentHeight)
                    .padding(.horizontal, horizontalPadding)
                    
                    Spacer(minLength: 0)
                    
                    // Espacio reservado para la PlayerBar fija de Capa 3
                    Color.clear.frame(height: bottomReservedHeight)
                }
                .frame(width: windowWidth, height: windowHeight)
            }
            .frame(width: windowWidth, height: windowHeight)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .compositingGroup()
        .onExitCommand {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                viewModel.isFullscreenPresented = false
            }
        }
        .onChange(of: viewModel.currentTrack?.videoId) { _, _ in
            failedMaxQualityURL = nil
        }
    }
    
    // MARK: - Fondo Difuminado Sólido (Cero transparencias, cero fugas en los bordes)
    @ViewBuilder
    private func backgroundArtworkBlur(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Capa 0: Fondo base totalmente opaco para bloquear la vista subyacente
            Color.sidebDarkBackground
            
            // Capa 1: Carátula expandida y desenfocada
            if let thumb = viewModel.currentTrack?.thumbnail,
               let url = ImageURLHelper.optimizedThumbnailURL(from: thumb, targetPixelSize: 300) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 300, height: 300)) { img in
                    img
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: height)
                        .scaleEffect(1.4) // Expande la imagen un 40% más allá de los bordes para eliminar el feathering transparente
                        .blur(radius: 75)
                        .overlay(Color.black.opacity(0.72))
                } placeholder: {
                    Color.sidebDarkBackground
                }
                .id("blur_\(viewModel.currentTrack?.videoId ?? url.absoluteString)")
            } else {
                LinearGradient(
                    colors: [Color(red: 0.07, green: 0.07, blue: 0.08), Color.sidebDarkBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .ignoresSafeArea(.container, edges: .top)
    }
    
    // MARK: - Módulo Artwork (1:1 Cuadrado con Play/Pause en click y oscurecimiento en hover)
    private func artworkView(size: CGFloat) -> some View {
        let maxQualityUrl = ImageURLHelper.maxQualityArtworkURL(
            from: viewModel.currentTrack?.thumbnail,
            videoId: viewModel.currentTrack?.videoId
        )
        let fallbackUrl = ImageURLHelper.fallbackThumbnailURL(
            from: viewModel.currentTrack?.thumbnail,
            targetPixelSize: 544
        )

        let activeArtworkUrl: URL? = {
            if let maxQualityUrl, failedMaxQualityURL != maxQualityUrl {
                return maxQualityUrl
            }
            return fallbackUrl
        }()

        return ZStack {
            if let activeArtworkUrl {
                CachedAsyncImage(
                    url: activeArtworkUrl,
                    targetSize: CGSize(width: 1200, height: 1200),
                    onFailure: {
                        if activeArtworkUrl == maxQualityUrl {
                            self.failedMaxQualityURL = maxQualityUrl
                        }
                    }
                ) { image in
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                } placeholder: {
                    artworkPlaceholder(size: size)
                }
                .id("art_\(viewModel.currentTrack?.videoId ?? activeArtworkUrl.absoluteString)")
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                fallbackArtwork(size: size)
                    .frame(width: size, height: size)
            }

            // Capa de oscurecimiento sutil en hover
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(isHoveringArtwork ? 0.22 : 0.0))
                .animation(.easeInOut(duration: 0.18), value: isHoveringArtwork)

            // Icono sutil de play/pausa que aparece en hover
            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: max(28, size * 0.14), weight: .bold))
                .foregroundStyle(Color.white.opacity(isHoveringArtwork ? 0.92 : 0.0))
                .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
                .animation(.easeInOut(duration: 0.18), value: isHoveringArtwork)
        }
        .frame(width: size, height: size)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.42), radius: 22, x: 0, y: 10)
        .onHover { isHoveringArtwork = $0 }
        .onTapGesture {
            viewModel.togglePlayPause()
        }
    }

    @ViewBuilder
    private func artworkPlaceholder(size: CGFloat) -> some View {
        if let thumbStr = viewModel.currentTrack?.thumbnail {
            let cachedImage: NSImage? = {
                if let url300 = ImageURLHelper.optimizedThumbnailURL(from: thumbStr, targetPixelSize: 300),
                   let img = ImageCache.shared.imageFromMemoryCache(for: url300, targetSize: CGSize(width: 300, height: 300)) {
                    return img
                }
                if let url92 = ImageURLHelper.optimizedThumbnailURL(from: thumbStr, targetPixelSize: 92),
                   let img = ImageCache.shared.imageFromMemoryCache(for: url92, targetSize: CGSize(width: 92, height: 92)) {
                    return img
                }
                return nil
            }()

            if let cachedImage {
                Image(nsImage: cachedImage)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
            } else {
                fallbackArtwork(size: size)
            }
        } else {
            fallbackArtwork(size: size)
        }
    }
    
    private func fallbackArtwork(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: min(size * 0.25, 60)))
                    .foregroundStyle(.white.opacity(0.3))
            )
    }
    
    // MARK: - Módulo Track Info (Título + Artista • Álbum + Me Gusta, directo sobre el fondo)
    private func trackInfoView(width: CGFloat) -> some View {
        let titleSize: CGFloat = width < 340 ? 21 : (width < 460 ? 25 : 28)
        let subtitleSize: CGFloat = width < 340 ? 14.5 : (width < 460 ? 16 : 17.5)
        
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                // Título de la Canción (Bold prominente estilo cartel Now Playing)
                Text(viewModel.currentTrack?.title ?? "Sin reproducción")
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                // Artista • Álbum con enlaces interactivos (sin subrayado)
                HStack(spacing: 7) {
                    if let track = viewModel.currentTrack, !track.displayArtist.isEmpty {
                        Button {
                            navigateToArtist(track: track)
                        } label: {
                            Text(track.displayArtist)
                                .font(.system(size: subtitleSize, weight: .semibold))
                                .foregroundStyle(isHoveringArtist ? Color.white : Color.white.opacity(0.78))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .onHover { isHoveringArtist = $0 }
                        .help("Ir a la página del artista: \(track.displayArtist)")
                    } else {
                        Text("Selecciona una canción")
                            .font(.system(size: subtitleSize, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    
                    if let track = viewModel.currentTrack, let album = track.displayAlbum, !album.isEmpty {
                        Text("•")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.40))
                        
                        Button {
                            navigateToAlbum(track: track)
                        } label: {
                            Text(album)
                                .font(.system(size: max(12, subtitleSize - 0.5), weight: .medium))
                                .foregroundStyle(isHoveringAlbum ? Color.white : Color.white.opacity(0.60))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .onHover { isHoveringAlbum = $0 }
                        .help("Ir al álbum: \(album)")
                    }
                }
            }
            .contextMenu {
                if let track = viewModel.currentTrack {
                    SongMenuItems(song: track, player: viewModel, router: router, core: viewModel.rustCore, origin: .nowPlaying)
                }
            }
            
            Spacer(minLength: 8)
            
            // Botón Me Gusta (Sutil y sincronizado con PlayerViewModel)
            Button {
                viewModel.toggleCurrentTrackLike()
            } label: {
                Image(systemName: viewModel.isCurrentTrackLiked ? "heart.fill" : "heart")
                    .font(.system(size: width < 340 ? 20 : 22, weight: .semibold))
                    .foregroundStyle(viewModel.isCurrentTrackLiked ? Color.sidebAccent : Color.white.opacity(0.70))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(viewModel.isCurrentTrackLiked ? "Quitar de Me Gusta" : "Me Gusta")
        }
        .frame(width: width, alignment: .leading)
    }
    
    // MARK: - Selector de Pestañas Cápsula (Centrado en su columna, estilo Apple Music / sideb OLD)
    private var compactTabBar: some View {
        HStack(spacing: 0) {
            ForEach(FullscreenPanel.allCases) { panel in
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                        selectedPanel = panel
                    }
                    if panel == .recommended, let track = viewModel.currentTrack {
                        viewModel.fetchRecommendations(for: track)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: panel.icon)
                            .font(.system(size: 12.5, weight: selectedPanel == panel ? .semibold : .medium))
                        Text(panel.rawValue)
                            .font(.system(size: 13, weight: selectedPanel == panel ? .semibold : .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .foregroundStyle(selectedPanel == panel ? Color.white : Color.white.opacity(0.65))
                    .background {
                        if selectedPanel == panel {
                            Capsule()
                                .fill(Color.sidebAccent)
                                .matchedGeometryEffect(id: "fullscreenTabIndicator", in: tabNamespace)
                                .shadow(color: Color.sidebAccent.opacity(0.35), radius: 6, x: 0, y: 2)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }
    
    // MARK: - Panel de Contenido (Sin tarjeta gris ni borde, flotando directo sobre el fondo)
    private func contentPanelView(height: CGFloat) -> some View {
        ZStack {
            switch selectedPanel {
            case .queue:
                queuePanel(height: height)
            case .lyrics:
                lyricsPanel(height: height)
            case .recommended:
                recommendedPanel(height: height)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
    
    // MARK: - Contenido: Cola de Reproducción (120 FPS, transparente, sin columnas innecesarias)
    @ViewBuilder
    private func queuePanel(height: CGFloat) -> some View {
        if viewModel.queueManager.queue.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 38))
                    .foregroundStyle(.white.opacity(0.25))
                Text("No hay pistas en la cola")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                // Cabecera Contextual de la Cola Dinámica
                HStack(spacing: 8) {
                    Image(systemName: viewModel.queueManager.context?.iconName ?? "music.note.list")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.sidebAccent)
                    
                    Text(viewModel.queueManager.contextTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                        .fixedSize()
                    
                    Text("\(viewModel.queueManager.queue.count) canciones")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize()
                    
                    Spacer(minLength: 4)
                    
                    if viewModel.queueManager.isLoadingRadio || viewModel.queueManager.isLoadingAutoplay {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("Cargando...")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .fixedSize()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
                
                NativeTrackTableView(
                    tracks: viewModel.queueManager.queue,
                    currentTrackVideoId: viewModel.currentTrack?.videoId,
                    isPlaying: viewModel.isPlaying,
                    playerViewModel: viewModel,
                    router: router,
                    hideAlbumColumn: true,
                    showAlbumInSubtitle: true,
                    isReorderable: true,
                    rowHeight: 46.0,
                    likedVideoIds: viewModel.likedVideoIds,
                    menuOrigin: { .queue(occurrenceIndex: $0) },
                    onPlayTrack: { index in
                        viewModel.playQueueIndex(index)
                    },
                    onLikeTrack: { track in
                        viewModel.toggleTrackLike(track)
                    },
                    onDislikeTrack: { track in
                        viewModel.dislikeTrack(track)
                    },
                    onMoveTrack: { from, to in
                        viewModel.moveQueueTrack(from: from, to: to)
                    },
                    contentInsets: NSEdgeInsets(top: 2, left: 0, bottom: 4, right: 0)
                )
                .frame(maxWidth: .infinity)
                .frame(height: max(0, height - 28))
            }
            .frame(height: height)
        }
    }
    
    // MARK: - Contenido: Letras Sincronizadas
    @ViewBuilder
    private func lyricsPanel(height: CGFloat) -> some View {
        if viewModel.isLoadingLyrics {
            VStack(spacing: 12) {
                ProgressView()
                Text("Buscando letras sincronizadas...")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let lyrics = viewModel.lyricsInfo, !lyrics.lines.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                            let isCurrentLine = (currentLyricIndex == index)
                            
                            Button {
                                if let ms = line.timeMs {
                                    viewModel.seek(toFraction: Double(ms) / 1000.0 / viewModel.duration)
                                }
                            } label: {
                                Text(line.text.isEmpty ? "•••" : line.text)
                                    .font(.system(size: 21, weight: isCurrentLine ? .bold : .medium))
                                    .foregroundStyle(isCurrentLine ? Color.white : Color.white.opacity(0.35))
                                    .scaleEffect(isCurrentLine ? 1.02 : 1.0, anchor: .leading)
                                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isCurrentLine)
                                    .multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .onChange(of: viewModel.currentTime) { _, _ in
                    let currentTimeMs = UInt64(viewModel.currentTime * 1000)
                    if let activeIndex = lyrics.lines.firstIndex(where: { line in
                        guard let start = line.timeMs else { return false }
                        if let end = line.endTimeMs {
                            return currentTimeMs >= start && currentTimeMs <= end
                        }
                        return currentTimeMs >= start && currentTimeMs <= start + 4000
                    }) {
                        if currentLyricIndex != activeIndex {
                            currentLyricIndex = activeIndex
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(activeIndex, anchor: .center)
                            }
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.25))
                Text("No hay letras disponibles")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text("No se encontraron letras sincronizadas para esta pista")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Contenido: Recomendaciones (Estantes Liquid Glass a 120 FPS)
    @ViewBuilder
    private func recommendedPanel(height: CGFloat) -> some View {
        RecommendedContentView(viewModel: viewModel, router: router, height: height)
    }
    
    // MARK: - Navegación
    private func navigateToArtist(track: SongItemRecord) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            viewModel.isFullscreenPresented = false
        }
        if let browseId = track.artistId ?? viewModel.currentArtistBrowseId {
            router?.navigate(to: .artist(browseId: browseId))
        } else {
            router?.navigate(to: .search(query: track.artists))
        }
    }
    
    private func navigateToAlbum(track: SongItemRecord) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            viewModel.isFullscreenPresented = false
        }
        if let browseId = track.albumId ?? viewModel.currentAlbumBrowseId {
            router?.navigate(to: .album(browseId: browseId))
        } else if let albumName = track.displayAlbum {
            router?.navigate(to: .search(query: "\(albumName) \(track.displayArtist)"))
        }
    }
}
