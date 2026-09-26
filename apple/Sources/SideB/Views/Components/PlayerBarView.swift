import SwiftUI
import SideBCore

// MARK: - PlayerBarView (Apple Music macOS 26 Style - Isla Rediseñada)

struct PlayerBarView: View {
    @Bindable var viewModel: PlayerViewModel
    var router: NavigationRouter?

    @State private var isHoveringScrubber: Bool = false
    @State private var isSeeking: Bool = false
    @State private var seekFraction: Double = 0.0

    // Estados de interacción
    @State private var isHoveringVolume: Bool = false
    @State private var isDraggingVolume: Bool = false
    @State private var isHoveringArtist: Bool = false
    @State private var isHoveringAlbum: Bool = false

    init(viewModel: PlayerViewModel, router: NavigationRouter? = nil) {
        self.viewModel = viewModel
        self.router = router
    }

    public var body: some View {
        VStack(spacing: 5) {
            // MARK: - 1. Barra de Progreso Superior (Diseño Foto 3 con Playhead Vertical)
            if viewModel.currentTrack != nil {
                scrubberBarSection
                    .padding(.horizontal, 24)
                    .padding(.top, 2)
            }

            // MARK: - 2. Fila Principal de Controles
            HStack(spacing: 14) {
                // (a) Controles de Transporte (100% sin reborde)
                transportControlsSection

                Divider()
                    .frame(height: 22)
                    .opacity(0.18)

                // (b) Información de la Pista + Corazón para Likear + Opciones
                trackInfoSection

                Spacer(minLength: 12)

                // (c) Atajos (Letras y Cola), AirPlay, Volumen Adaptativo y Flecha Fullscreen
                rightControlsSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 2)
        }
        .frame(maxWidth: 820)
        .frame(height: 74)
        .compatGlass(interactive: true, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
    }

    // MARK: - 1. Barra de Estado / Scrubber (Foto 3)
    private var scrubberBarSection: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let activeFraction = isSeeking ? seekFraction : viewModel.progressFraction
            let clampedFraction = max(0.0, min(1.0, activeFraction))
            let fillWidth = width * clampedFraction

            ZStack(alignment: .leading) {
                // Rail no transcurrido (gris translúcido ultra fino)
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: isHoveringScrubber ? 3.5 : 2.5)

                // Rail transcurrido (Acento Side B calibrado)
                Capsule()
                    .fill(Color.sidebAccent)
                    .frame(width: max(0, fillWidth), height: isHoveringScrubber ? 3.5 : 2.5)

                // Cabezal Playhead Vertical (píldora vertical de precisión)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.white)
                    .frame(width: isHoveringScrubber ? 3.0 : 2.5, height: isHoveringScrubber ? 10.5 : 9.0)
                    .shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 0.5)
                    .offset(x: max(0, min(width - 2.5, fillWidth - 1.25)))
            }
            .frame(height: proxy.size.height, alignment: .center)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHoveringScrubber = hovering
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isSeeking = true
                        let fraction = max(0.0, min(1.0, value.location.x / width))
                        seekFraction = fraction
                    }
                    .onEnded { value in
                        let fraction = max(0.0, min(1.0, value.location.x / width))
                        viewModel.seek(toFraction: fraction)
                        isSeeking = false
                    }
            )
        }
        .frame(height: 8)
    }

    // MARK: - 2. Controles de Transporte (Izquierda - Sin rebordes, botones más amplios y proporcionados)
    private var transportControlsSection: some View {
        HStack(spacing: 10) {
            // Shuffle
            Button {
                viewModel.queueManager.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(viewModel.queueManager.isShuffle ? Color.sidebAccent : Color.white.opacity(0.60))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(viewModel.queueManager.isShuffle ? "Desactivar aleatorio" : "Activar aleatorio")

            // Anterior
            Button {
                if viewModel.currentTime > 3.0 {
                    viewModel.seek(toFraction: 0)
                } else {
                    viewModel.playPrevious()
                }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(viewModel.currentTrack == nil ? Color.white.opacity(0.25) : Color.white.opacity(0.85))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentTrack == nil)
            .help("Anterior")

            // Play / Pause Principal (Limpio, directo, tamaño prominente)
            Button {
                if viewModel.errorMessage != nil {
                    viewModel.retryPlayback()
                } else {
                    viewModel.togglePlayPause()
                }
            } label: {
                Group {
                    if viewModel.isBuffering {
                        ProgressView()
                            .scaleEffect(0.70)
                    } else if viewModel.errorMessage != nil {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.yellow)
                    } else {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(viewModel.currentTrack == nil ? Color.white.opacity(0.30) : Color.white)
                            .offset(x: viewModel.isPlaying ? 0 : 1)
                    }
                }
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentTrack == nil)
            .help(viewModel.errorMessage != nil ? "Reintentar reproducción" : (viewModel.isPlaying ? "Pausar" : "Reproducir"))

            // Siguiente
            Button {
                viewModel.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(viewModel.queueManager.hasNext ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.queueManager.hasNext)
            .help("Siguiente")

            // Repeat
            Button {
                viewModel.queueManager.isRepeat.toggle()
            } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(viewModel.queueManager.isRepeat ? Color.sidebAccent : Color.white.opacity(0.60))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(viewModel.queueManager.isRepeat ? "Desactivar repetición" : "Repetir tema")
        }
    }

    // MARK: - 3. Track Info (Centro: Carátula 46x46, Título + Corazón, Subtítulo Artista • Álbum y Menú ...)
    private var trackInfoSection: some View {
        HStack(spacing: 12) {
            // Carátula (46x46 para balance vertical exacto)
            if let thumbnailUrl = viewModel.currentTrack?.thumbnail,
               let url = ImageURLHelper.optimizedThumbnailURL(from: thumbnailUrl, targetPixelSize: 92) {
                CachedAsyncImage(url: url, targetSize: CGSize(width: 92, height: 92)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    fallbackArtwork
                }
                .id(viewModel.currentTrack?.videoId ?? url.absoluteString)
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            } else {
                fallbackArtwork
            }

            // Título con Corazón y Subtítulo Artista • Álbum (sin subrayado)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(viewModel.currentTrack?.title ?? "Sin reproducción")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let _ = viewModel.currentTrack {
                        Button {
                            viewModel.toggleCurrentTrackLike()
                        } label: {
                            Image(systemName: viewModel.isCurrentTrackLiked ? "heart.fill" : "heart")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(viewModel.isCurrentTrackLiked ? Color.sidebAccent : Color.white.opacity(0.60))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.isCurrentTrackLiked ? "Quitar de Me Gusta" : "Me Gusta")
                    }
                }

                if let error = viewModel.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.yellow)

                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.yellow.opacity(0.95))
                            .lineLimit(1)

                        Button {
                            viewModel.retryPlayback()
                        } label: {
                            Text("Reintentar")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.white.opacity(0.18))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Reintentar reproducción")
                    }
                } else {
                    HStack(spacing: 6) {
                        if let track = viewModel.currentTrack, !track.displayArtist.isEmpty {
                            Button {
                                navigateToArtist(track: track)
                            } label: {
                                Text(track.displayArtist)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(isHoveringArtist ? Color.primary : Color.secondary)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .onHover { isHoveringArtist = $0 }
                            .help("Ver artista: \(track.displayArtist)")
                        } else {
                            Text("Selecciona una pista")
                                .font(.system(size: 11.5, weight: .regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let track = viewModel.currentTrack, let album = track.displayAlbum, !album.isEmpty {
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary.opacity(0.50))

                            Button {
                                navigateToAlbum(track: track)
                            } label: {
                                Text(album)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(isHoveringAlbum ? Color.primary : Color.secondary)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .onHover { isHoveringAlbum = $0 }
                            .help("Ver álbum: \(album)")
                        }
                    }
                }
            }
            .frame(maxWidth: 340, alignment: .leading)
            .contextMenu {
                if let track = viewModel.currentTrack {
                    SongMenuItems(song: track, player: viewModel, router: router, core: viewModel.rustCore, origin: .nowPlaying)
                }
            }

            // Menú contextual de opciones "..."
            if let track = viewModel.currentTrack {
                Menu {
                    SongMenuItems(song: track, player: viewModel, router: router, core: viewModel.rustCore, origin: .nowPlaying)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 26, height: 26)
            }
        }
    }

    // MARK: - 4. Controles Derechos (Shortcuts Letras/Cola, AirPlay, Volumen y Flecha)
    private var rightControlsSection: some View {
        let isVolumeExpanded = isHoveringVolume || isDraggingVolume
        let expandedCapsuleWidth: CGFloat = 152

        return HStack(spacing: 8) {
            // (a) Shortcut a Letras Sincronizadas
            lyricsShortcutButton
                .opacity(isVolumeExpanded ? 0 : 1)
                .allowsHitTesting(!isVolumeExpanded)

            // (b) Shortcut a Cola de Reproducción
            queueShortcutButton
                .opacity(isVolumeExpanded ? 0 : 1)
                .allowsHitTesting(!isVolumeExpanded)

            // (c) AirPlay (100% nativo y sin rebordes)
            AirPlayButton()
                .opacity(isVolumeExpanded ? 0 : 1)
                .allowsHitTesting(!isVolumeExpanded)

            // (d) Control de Volumen Adaptativo en Overlay Flotante
            volumeControlSection(isExpanded: isVolumeExpanded, capsuleWidth: expandedCapsuleWidth)

            // (e) Flecha Fullscreen Grande Estilizada (Sin círculo)
            fullscreenArrowButton
        }
    }

    // MARK: - Atajos a Paneles
    private var lyricsShortcutButton: some View {
        Button {
            viewModel.toggleFullscreenPanel(.lyrics)
        } label: {
            Image(systemName: (viewModel.isFullscreenPresented && viewModel.selectedFullscreenPanel == .lyrics) ? "quote.bubble.fill" : "quote.bubble")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle((viewModel.isFullscreenPresented && viewModel.selectedFullscreenPanel == .lyrics) ? Color.sidebAccent : Color.white.opacity(0.70))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Letras sincronizadas")
    }

    private var queueShortcutButton: some View {
        Button {
            viewModel.toggleFullscreenPanel(.queue)
        } label: {
            Image(systemName: (viewModel.isFullscreenPresented && viewModel.selectedFullscreenPanel == .queue) ? "list.bullet.indent" : "list.bullet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle((viewModel.isFullscreenPresented && viewModel.selectedFullscreenPanel == .queue) ? Color.sidebAccent : Color.white.opacity(0.70))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Cola de reproducción")
    }

    // MARK: - Volumen Adaptativo (Overlay Flotante hacia la izquierda)
    private func volumeControlSection(isExpanded: Bool, capsuleWidth: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            // Huella de layout fija de 32x32: garantiza que el HStack NUNCA cambie de ancho
            Color.clear
                .frame(width: 32, height: 32)

            // Icono en reposo (cuando no está expandido)
            if !isExpanded {
                Button {
                    viewModel.toggleMute()
                } label: {
                    Image(systemName: volumeIcon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.70))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(viewModel.volume <= 0.01 ? "Activar sonido" : "Silenciar")
                .onHover { hovering in
                    if hovering {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            isHoveringVolume = true
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(width: 32, height: 32)
        .overlay(alignment: .trailing) {
            if isExpanded {
                expandedVolumeCapsule(width: capsuleWidth)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)),
                        removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .trailing))
                    ))
            }
        }
        .zIndex(isExpanded ? 25 : 1)
    }

    // MARK: - Cápsula de Volumen Expandida (Overlay Flotante estilo Liquid Glass Apple Music)
    private func expandedVolumeCapsule(width: CGFloat) -> some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                let sliderWidth = proxy.size.width
                let currentVolume = Double(viewModel.volume)
                let fillWidth = max(0, min(sliderWidth, sliderWidth * currentVolume))

                ZStack(alignment: .leading) {
                    // Rail translúcido suave
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .frame(height: 11)

                    // Píldora blanca sólida prominente (Estilo Apple Music)
                    Capsule()
                        .fill(Color.white)
                        .frame(width: fillWidth, height: 11)
                }
                .clipShape(Capsule())
                .frame(height: proxy.size.height, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDraggingVolume = true
                            let fraction = max(0.0, min(1.0, value.location.x / sliderWidth))
                            viewModel.volume = Float(fraction)
                        }
                        .onEnded { _ in
                            isDraggingVolume = false
                        }
                )
            }
            .frame(height: 18)

            // Icono de altavoz blanco nítido dentro de la cápsula
            Button {
                viewModel.toggleMute()
            } label: {
                Image(systemName: volumeIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 22, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(viewModel.volume <= 0.01 ? "Activar sonido" : "Silenciar")
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(width: width, height: 36)
        .background {
            // Fondo translúcido sutil para contraste con Liquid Glass sobrepuesto
            Capsule()
                .fill(Color.black.opacity(0.20))
        }
        .compatGlass(interactive: true, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
        .contentShape(Capsule())
        .onHover { hovering in
            if !isDraggingVolume {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                    isHoveringVolume = hovering
                }
            }
        }
    }

    // MARK: - Flecha Fullscreen Grande (Sin reborde circular tosco)
    private var fullscreenArrowButton: some View {
        Button {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.82)) {
                viewModel.isFullscreenPresented.toggle()
            }
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 16.5, weight: .bold))
                .foregroundStyle(viewModel.isFullscreenPresented ? Color.sidebAccent : Color.white.opacity(0.75))
                .rotationEffect(.degrees(viewModel.isFullscreenPresented ? 180 : 0))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(viewModel.isFullscreenPresented ? "Cerrar pantalla completa" : "Abrir pantalla completa")
    }

    // MARK: - Navegación
    private func navigateToArtist(track: SongItemRecord) {
        if viewModel.isFullscreenPresented {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                viewModel.isFullscreenPresented = false
            }
        }
        if let browseId = track.artistId ?? viewModel.currentArtistBrowseId {
            router?.navigate(to: .artist(browseId: browseId))
        } else {
            router?.navigate(to: .search(query: track.artists))
        }
    }

    private func navigateToAlbum(track: SongItemRecord) {
        if viewModel.isFullscreenPresented {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                viewModel.isFullscreenPresented = false
            }
        }
        if let browseId = track.albumId ?? viewModel.currentAlbumBrowseId {
            router?.navigate(to: .album(browseId: browseId))
        } else if let albumName = track.displayAlbum {
            router?.navigate(to: .search(query: "\(albumName) \(track.displayArtist)"))
        }
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.secondary.opacity(0.18))
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            )
            .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
    }

    private var volumeIcon: String {
        if viewModel.volume <= 0.01 {
            return "speaker.slash.fill"
        } else if viewModel.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if viewModel.volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}
