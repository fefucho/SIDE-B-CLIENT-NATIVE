import SwiftUI
import SideBCore

@main
struct SideBApp: App {
    @State private var rustCore: SideBCore?
    @State private var playerViewModel = PlayerViewModel()
    @State private var cookieStorage = CookieStorage()
    @State private var initError: String?
    @State private var showLoginSheet = false
    @State private var accountViewModel = AccountViewModel()
    @State private var libraryViewModel = LibraryViewModel()
    @State private var homeViewModel = HomeViewModel()
    @State private var homeSessionRevision = 0
    @State private var hasBootstrappedSession = false

    init() {
        do {
            let appSupport = HomeLabConfiguration.appSupportURL
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let core = try SideBCore(dataDir: appSupport.path)
            _rustCore = State(initialValue: core)
            _playerViewModel = State(initialValue: PlayerViewModel(rustCore: core))
        } catch {
            _initError = State(initialValue: "Error al iniciar Rust Core: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if let error = initError {
                ContentUnavailableView {
                    Label("Error al iniciar Side B", systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text(error)
                } actions: {
                    Button("Cerrar aplicación") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(minWidth: 600, minHeight: 400)
                .preferredColorScheme(.dark)
            } else if let core = rustCore {
                WindowRootView(
                    rustCore: core,
                    playerViewModel: playerViewModel,
                    cookieStorage: cookieStorage,
                    accountViewModel: accountViewModel,
                    libraryViewModel: libraryViewModel,
                    homeViewModel: homeViewModel,
                    showLoginSheet: $showLoginSheet,
                    homeSessionRevision: $homeSessionRevision
                )
                .ignoresSafeArea(.container, edges: .top)
                .task {
                    guard !hasBootstrappedSession else { return }
                    hasBootstrappedSession = true
                    playerViewModel.rustCore = core
                    let hasSession = accountViewModel.restoreSession(core: core, storage: cookieStorage)
                    homeViewModel.prepareSession(identity: cookieStorage.homeCacheIdentity(), purgePrevious: false)
                    homeSessionRevision &+= 1
                    if hasSession {
                        await accountViewModel.fetchAccount(core: core)
                        playerViewModel.switchPlaybackSession(to: PlaybackStateStore.identity(for: accountViewModel.account, cookieStorage: cookieStorage))
                        if accountViewModel.isLoggedIn {
                            await libraryViewModel.loadLibrary(core: core)
                        }
                    } else {
                        playerViewModel.switchPlaybackSession(to: "guest")
                    }
                    Task {
                        await UpdateService.shared.checkForUpdates(manual: false)
                    }
                }
                .sheet(isPresented: $showLoginSheet) {
                    LoginSheet(cookieStorage: cookieStorage, rustCore: core) {
                        let loginIdentity = PlaybackStateStore.identity(for: nil, cookieStorage: cookieStorage)
                        playerViewModel.switchPlaybackSession(to: loginIdentity)
                        libraryViewModel.clear()
                        homeViewModel.prepareSession(identity: cookieStorage.homeCacheIdentity())
                        homeSessionRevision &+= 1
                        Task {
                            await accountViewModel.fetchAccount(core: core)
                            guard PlaybackStateStore.identity(for: nil, cookieStorage: cookieStorage) == loginIdentity else { return }
                            playerViewModel.switchPlaybackSession(to: PlaybackStateStore.identity(for: accountViewModel.account, cookieStorage: cookieStorage))
                            await libraryViewModel.loadLibrary(core: core)
                        }
                    }
                }
                .sheet(isPresented: Bindable(UpdateService.shared).isSheetPresented) {
                    UpdateModalSheet()
                }
            }
        }
        .commands {
            SideBMenuCommands()
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
    }
}

// MARK: - WindowRootView (Ámbito de Estado por Ventana - A26)

struct WindowRootView: View {
    let rustCore: SideBCore
    var playerViewModel: PlayerViewModel
    var cookieStorage: CookieStorage
    var accountViewModel: AccountViewModel
    var libraryViewModel: LibraryViewModel
    var homeViewModel: HomeViewModel
    @Binding var showLoginSheet: Bool
    @Binding var homeSessionRevision: Int

    // Estado de Navegación y Shell específico por ventana
    @State private var isSidebarExpanded: Bool = true
    @State private var router = NavigationRouter()
    @State private var isSpotlightPresented: Bool = false
    @State private var searchViewModel = SearchViewModel()
    @State private var isCreatePlaylistPresented = false
    @State private var pendingPlaylistVideoId: String?
    @State private var playlistCreationError: String?
    @State private var menuContext = AppMenuContext()

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - CAPA 0: Barra Lateral Colapsable
            if isSidebarExpanded {
                SidebarView(
                    isExpanded: $isSidebarExpanded,
                    router: router,
                    accountViewModel: accountViewModel,
                    libraryViewModel: libraryViewModel,
                    rustCore: rustCore,
                    cookieStorage: cookieStorage,
                    playerViewModel: playerViewModel,
                    onOpenSearch: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            isSpotlightPresented.toggle()
                        }
                    },
                    onOpenLogin: {
                        showLoginSheet = true
                    },
                    onLogout: {
                        playerViewModel.switchPlaybackSession(to: "guest")
                        libraryViewModel.clear()
                        homeViewModel.prepareSession(identity: cookieStorage.homeCacheIdentity())
                        homeSessionRevision &+= 1
                        router.navigate(to: .home)
                    }
                )
                .ignoresSafeArea(.container, edges: .top)
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(50)
            }

            // MARK: - ÁREA DE CONTENIDO (Capa 1 Navegador / Capa 2 Fullscreen / Capa 3 PlayerBar Fija)
            ZStack(alignment: .bottom) {
                // Capa 1: Navegador de Páginas
                ZStack(alignment: .topTrailing) {
                    // Contenido de la Página según router.currentPage
                    Group {
                        switch router.currentPage {
                        case .home:
                            HomeView(
                                playerViewModel: playerViewModel,
                                homeViewModel: homeViewModel,
                                sessionRevision: homeSessionRevision,
                                router: router,
                                onNavigate: { dest in
                                    router.navigate(to: dest)
                                }
                            )
                        case .playlist(let id):
                            PlaylistDetailView(
                                playlistId: id,
                                rustCore: rustCore,
                                playerViewModel: playerViewModel,
                                router: router
                            )
                            .id(id)
                        case .album(let id):
                            AlbumDetailView(
                                browseId: id,
                                rustCore: rustCore,
                                playerViewModel: playerViewModel,
                                router: router
                            )
                            .id(id)
                        case .artist(let id):
                            ArtistDetailView(
                                browseId: id,
                                rustCore: rustCore,
                                playerViewModel: playerViewModel,
                                router: router
                            )
                            .id(id)
                        case .history:
                            HistoryView(
                                rustCore: rustCore,
                                playerViewModel: playerViewModel,
                                libraryViewModel: libraryViewModel,
                                router: router
                            )
                        case .library:
                            LibraryView(
                                rustCore: rustCore,
                                playerViewModel: playerViewModel,
                                libraryViewModel: libraryViewModel,
                                accountViewModel: accountViewModel,
                                router: router
                            )
                        case .search(let query):
                            SearchView(
                                initialQuery: query ?? "",
                                rustCore: rustCore,
                                playerViewModel: playerViewModel,
                                router: router,
                                searchViewModel: searchViewModel
                            )
                            .id(query ?? "empty_search")
                        default:
                            HomeView(
                                playerViewModel: playerViewModel,
                                homeViewModel: homeViewModel,
                                sessionRevision: homeSessionRevision,
                                router: router,
                                onNavigate: { dest in
                                    router.navigate(to: dest)
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Cápsula Flotante de Navegación (Refresh + Back / Forward) en la DERECHA
                    FloatingNavigationCapsule(router: router)
                        .padding(.trailing, 24)
                        .padding(.top, 16)
                        .zIndex(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(playerViewModel.isFullscreenPresented ? 0 : 1)
                .allowsHitTesting(!playerViewModel.isFullscreenPresented)

                // Capa 2: Overlay Fullscreen Cinematográfico
                if playerViewModel.isFullscreenPresented {
                    FullscreenNowPlayingView(
                        viewModel: playerViewModel,
                        isSidebarExpanded: $isSidebarExpanded,
                        router: router
                    )
                    .ignoresSafeArea(.container, edges: .top)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .zIndex(20)
                }

                // Capa 3: Isla de Reproducción Flotante
                PlayerBarView(viewModel: playerViewModel, router: router)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .zIndex(100)

                // MARK: - SPOTLIGHT MODAL (CAPA 4: MODAL GLOBAL SOBRE TODO EL CONTENIDO)
                if isSpotlightPresented {
                    SpotlightSearchModal(
                        isPresented: $isSpotlightPresented,
                        searchViewModel: searchViewModel,
                        router: router,
                        playerViewModel: playerViewModel,
                        rustCore: rustCore
                    )
                    .zIndex(200)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea(.container, edges: isSidebarExpanded ? .top : [])
        }
        .background {
            Button("") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isSpotlightPresented.toggle()
                }
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        }
        .frame(minWidth: 960, minHeight: 640)
        .background(Color.sidebDarkBackground)
        .background(WindowConfigurator(isFullscreenPresented: playerViewModel.isFullscreenPresented))
        .environment(\.sideBMenuContext, menuContext)
        .focusedSceneValue(\.sideBMenuContext, menuContext)
        .onAppear {
            menuContext.player = playerViewModel
            menuContext.router = router
            menuContext.core = rustCore
            menuContext.account = accountViewModel
            menuContext.library = libraryViewModel
            menuContext.cookieStorage = cookieStorage
            menuContext.sidebar = $isSidebarExpanded
            menuContext.search = $isSpotlightPresented
            menuContext.loginSheet = $showLoginSheet
            menuContext.createPlaylistSheet = $isCreatePlaylistPresented
            let sessionRevision = $homeSessionRevision
            menuContext.onLogout = { [libraryViewModel, homeViewModel, cookieStorage, router] in
                playerViewModel.switchPlaybackSession(to: "guest")
                libraryViewModel.clear()
                homeViewModel.prepareSession(identity: cookieStorage.homeCacheIdentity())
                sessionRevision.wrappedValue &+= 1
                router.navigate(to: .home)
            }
            DispatchQueue.main.async { AppMenuBarOrganizer.normalize() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            DispatchQueue.main.async { AppMenuBarOrganizer.normalize() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            playerViewModel.flushPlaybackState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            playerViewModel.flushPlaybackState()
        }
        .preferredColorScheme(.dark)
        .tint(Color.sidebAccent)
        .overlay(alignment: .topLeading) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    isSidebarExpanded.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .help(isSidebarExpanded ? "Ocultar barra lateral" : "Mostrar barra lateral")
            .padding(.leading, 92)
            .padding(.top, 10)
            .ignoresSafeArea(.container, edges: .top)
        }
        .sheet(isPresented: $isCreatePlaylistPresented) {
            PlaylistEditorSheet(core: rustCore, playlist: nil) { id in
                let videoId = pendingPlaylistVideoId
                pendingPlaylistVideoId = nil
                router.navigate(to: .playlist(browseId: id))
                if let videoId {
                    Task {
                        do {
                            try await rustCore.addToPlaylist(playlistId: id, videoId: videoId)
                            NotificationCenter.default.post(name: .sideBPlaylistsChanged, object: nil)
                        } catch {
                            playlistCreationError = error.localizedDescription
                        }
                    }
                }
            }
        }
        .alert("No se pudo añadir la canción", isPresented: Binding(
            get: { playlistCreationError != nil },
            set: { if !$0 { playlistCreationError = nil } }
        )) {
            Button("Aceptar", role: .cancel) { playlistCreationError = nil }
        } message: {
            Text(playlistCreationError ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideBRequestCreatePlaylist)) { notification in
            guard accountViewModel.isLoggedIn else {
                showLoginSheet = true
                return
            }
            pendingPlaylistVideoId = notification.userInfo?["videoId"] as? String
            isCreatePlaylistPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideBPlaylistsChanged)) { _ in
            Task { await libraryViewModel.loadLibrary(core: rustCore) }
        }
        .onChange(of: router.currentPage) { _, _ in
            playerViewModel.dismissFullscreen()
            menuContext.clearSelection()
        }
    }
}
