import AppKit
import SwiftUI
import SideBCore

private struct SideBMenuContextKey: FocusedValueKey {
    typealias Value = AppMenuContext
}

extension FocusedValues {
    var sideBMenuContext: AppMenuContext? {
        get { self[SideBMenuContextKey.self] }
        set { self[SideBMenuContextKey.self] = newValue }
    }
}

private struct AppMenuContextEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppMenuContext? = nil
}

extension EnvironmentValues {
    var sideBMenuContext: AppMenuContext? {
        get { self[AppMenuContextEnvironmentKey.self] }
        set { self[AppMenuContextEnvironmentKey.self] = newValue }
    }
}

/// Estado de comandos perteneciente a una ventana, incluso cuando hay varias ventanas abiertas.
@MainActor
@Observable
final class AppMenuContext {
    var selectedSong: SongItemRecord?
    var player: PlayerViewModel?
    var router: NavigationRouter?
    var core: SideBCore?
    var account: AccountViewModel?
    var library: LibraryViewModel?
    var cookieStorage: CookieStorage?
    var sidebar: Binding<Bool>?
    var search: Binding<Bool>?
    var loginSheet: Binding<Bool>?
    var createPlaylistSheet: Binding<Bool>?
    var onLogout: (() -> Void)?

    var song: SongItemRecord? { selectedSong ?? player?.currentTrack }
    var isLoggedIn: Bool { account?.isLoggedIn == true }

    func select(_ song: SongItemRecord) { selectedSong = song }
    func clearSelection() { selectedSong = nil }

    func executeSong(_ action: MenuActionId) {
        guard let song, let player else { return }
        let facts = songFacts(for: song)
        MenuActionExecutor(player: player, router: router, core: core)
            .execute(action: action, target: .song(song), facts: facts)
    }

    func songFacts(for song: SongItemRecord) -> MenuFacts {
        MenuFacts(
            isLoggedIn: isLoggedIn,
            isCurrentPlayingTrack: player?.currentTrack?.videoId == song.videoId,
            isLiked: player?.likedVideoIds.contains(song.videoId) == true,
            userPlaylists: isLoggedIn ? (library?.playlists ?? []) : []
        )
    }

    func canExecuteSong(_ action: MenuActionId) -> Bool {
        switch action {
        case .toggleLike, .toggleLibrary, .addToPlaylist, .createPlaylistAndAdd:
            return isLoggedIn
        default:
            return true
        }
    }

    func logout() {
        guard let account, let core, let cookieStorage else { return }
        account.logout(core: core, storage: cookieStorage) { self.onLogout?() }
    }
}

struct SideBMenuCommands: Commands {
    @FocusedValue(\.sideBMenuContext) private var context

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Buscar actualizaciones…") {
                Task {
                    await UpdateService.shared.checkForUpdates(manual: true)
                }
            }
        }

        CommandGroup(replacing: .newItem) {}

        CommandMenu("Archivo") {
            Button("Nueva playlist…") {
                context?.createPlaylistSheet?.wrappedValue = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(context?.isLoggedIn != true)

            Divider()
            Button("Cerrar") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: .command)
        }

        CommandMenu("Canción") {
            songCommands
        }

        CommandMenu("Visualización") {
            Toggle("Barra lateral", isOn: Binding(
                get: { context?.sidebar?.wrappedValue ?? false },
                set: { context?.sidebar?.wrappedValue = $0 }
            ))
            .disabled(context?.sidebar == nil)

            Button("Buscar") { context?.search?.wrappedValue = true }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(context?.search == nil)

            Divider()
            Toggle("Cola", isOn: panelBinding(.queue))
                .disabled(context?.player?.currentTrack == nil)
            Toggle("Letras", isOn: panelBinding(.lyrics))
                .disabled(context?.player?.currentTrack == nil)
            Toggle("Relacionados", isOn: panelBinding(.recommended))
                .disabled(context?.player?.currentTrack == nil)

            Divider()
            Button(NSApp.keyWindow?.styleMask.contains(.fullScreen) == true ? "Salir de pantalla completa" : "Usar pantalla completa") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
        }

        CommandMenu("Controles") {
            Button(context?.player?.isPlaying == true ? "Pausar" : "Reproducir") {
                context?.player?.togglePlayPause()
            }
            .disabled(context?.player?.currentTrack == nil)

            Button("Siguiente pista") { context?.player?.playNext() }
                .disabled(context?.player?.queueManager.hasNext != true)
            Button("Pista anterior") {
                guard let player = context?.player else { return }
                if player.currentTime > 3 { player.seek(toFraction: 0) }
                else { player.playPrevious() }
            }
            .disabled(context?.player?.currentTrack == nil)

            Divider()
            Button("Subir volumen") {
                guard let player = context?.player else { return }
                player.volume = min(1, player.volume + 0.1)
            }
            Button("Bajar volumen") {
                guard let player = context?.player else { return }
                player.volume = max(0, player.volume - 0.1)
            }
            Button(context?.player?.volume == 0 ? "Activar sonido" : "Silenciar") {
                context?.player?.toggleMute()
            }

            Divider()
            Toggle("Aleatorio", isOn: Binding(
                get: { context?.player?.queueManager.isShuffle ?? false },
                set: { _ in context?.player?.queueManager.toggleShuffle() }
            ))
            .disabled(context?.player?.currentTrack == nil)
            Toggle("Repetición", isOn: Binding(
                get: { context?.player?.queueManager.isRepeat ?? false },
                set: { context?.player?.queueManager.isRepeat = $0 }
            ))
            .disabled(context?.player?.currentTrack == nil)
        }

        CommandMenu("Cuenta") {
            if context?.isLoggedIn == true {
                Button("Cerrar sesión") { context?.logout() }
            } else {
                Button("Iniciar sesión…") { context?.loginSheet?.wrappedValue = true }
            }
        }
    }

    private func panelBinding(_ panel: FullscreenPanel) -> Binding<Bool> {
        Binding(
            get: {
                context?.player?.isFullscreenPresented == true &&
                    context?.player?.selectedFullscreenPanel == panel
            },
            set: { enabled in
                guard let player = context?.player else { return }
                if enabled { player.toggleFullscreenPanel(panel) }
                else if player.selectedFullscreenPanel == panel { player.dismissFullscreen() }
            }
        )
    }

    @ViewBuilder
    private var songCommands: some View {
        if let context, let song = context.song {
            let facts = context.songFacts(for: song)
            let origin = context.selectedSong == nil ? MenuOrigin.nowPlaying : (context.router?.currentPage.asMenuOrigin ?? .home)
            let sections = MenuPolicy.resolveSections(target: .song(song), origin: origin, facts: facts)
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                if index > 0 { Divider() }
                ForEach(section.items) { item in
                    if let subitems = item.subitems {
                        Menu(item.title) {
                            ForEach(subitems) { subitem in
                                Button(subitem.title) { context.executeSong(subitem.id) }
                                    .disabled(!subitem.isEnabled || !context.canExecuteSong(subitem.id))
                            }
                        }
                    } else {
                        Button(item.title) { context.executeSong(item.id) }
                            .disabled(!item.isEnabled || !context.canExecuteSong(item.id))
                    }
                }
            }
        } else {
            Button("Sin canción seleccionada") {}
                .disabled(true)
        }
    }
}

/// SwiftUI ubica los CommandMenu detrás de su menú Visualización automático.
/// Normalizamos solo los menús superiores, conservando Edición, Ventana y Ayuda.
@MainActor
enum AppMenuBarOrganizer {
    static func normalize() {
        guard let mainMenu = NSApp.mainMenu,
              mainMenu.items.contains(where: { $0.title == "Archivo" }) else { return }

        let viewItems = mainMenu.items.filter { $0.title == "Visualización" }
        if viewItems.count > 1, let automaticView = viewItems.first {
            mainMenu.removeItem(automaticView)
        }

        let order = ["Archivo", "Edición", "Canción", "Visualización", "Controles", "Cuenta", "Ventana", "Ayuda"]
        for (offset, title) in order.enumerated() {
            guard let item = mainMenu.items.first(where: { $0.title == title }) else { continue }
            let targetIndex = offset + 1 // El menú de la aplicación permanece primero.
            guard mainMenu.index(of: item) != targetIndex else { continue }
            mainMenu.removeItem(item)
            mainMenu.insertItem(item, at: min(targetIndex, mainMenu.items.count))
        }
    }
}
