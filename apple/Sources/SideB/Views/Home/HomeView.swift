import SwiftUI
import SideBCore

/// Inicio nuevo: estado y controles ligeros en SwiftUI, feed reciclable en AppKit.
struct HomeView: View {
    @Bindable var playerViewModel: PlayerViewModel
    @Bindable var homeViewModel: HomeViewModel
    let sessionRevision: Int
    var router: NavigationRouter?
    var onNavigate: ((PageDestination) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !homeViewModel.chips.isEmpty { chips }

            if homeViewModel.sections.isEmpty {
                if let error = homeViewModel.errorMessage {
                    errorView(error)
                } else {
                    ProgressView("Cargando recomendaciones…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Cargando Inicio")
                }
            } else {
                HomeFeedTableView(
                    sections: homeViewModel.sections,
                    isObscured: playerViewModel.isFullscreenPresented,
                    revision: homeViewModel.contentRevision,
                    selectedChip: homeViewModel.selectedChipParams,
                    hasMore: homeViewModel.continuationToken != nil,
                    isLoadingMore: homeViewModel.isLoadingMore,
                    currentTrackID: playerViewModel.currentTrack?.videoId,
                    currentAlbumBrowseId: playerViewModel.currentAlbumBrowseId,
                    currentPlaylistBrowseId: playerViewModel.currentPlaylistBrowseId,
                    isPlaying: playerViewModel.isPlaying,
                    player: playerViewModel,
                    router: router,
                    onNavigate: navigate,
                    onLoadMore: loadMore
                )
                .overlay(alignment: .top) { statusBanner }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: sessionRevision) {
            guard sessionRevision > 0, homeViewModel.sections.isEmpty,
                  let core = playerViewModel.rustCore else { return }
            await homeViewModel.loadHomeFeed(core: core)
        }
        .onChange(of: router?.refreshTrigger) { _, _ in refresh() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Inicio")
                    .font(.system(size: 27, weight: .bold))
                Text("Escucha de nuevo y descubre algo nuevo")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Todos", params: nil)
                ForEach(homeViewModel.chips, id: \.params) { value in
                    chip(title: value.title, params: value.params)
                }
            }
            .padding(.horizontal, 28)
        }
        .frame(height: 42)
        .padding(.bottom, 4)
    }

    private func chip(title: String, params: String?) -> some View {
        let selected = homeViewModel.selectedChipParams == params
        return Button(title) {
            guard !selected, let core = playerViewModel.rustCore else { return }
            Task { await homeViewModel.loadHomeFeed(core: core, chipParams: params) }
        }
        .font(.system(size: 13, weight: selected ? .semibold : .medium))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(selected ? Color.sidebAccent : Color.primary.opacity(0.07), in: Capsule())
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder private var statusBanner: some View {
        if homeViewModel.isLoadingChip || homeViewModel.isRefreshing || homeViewModel.isShowingSavedFeed ||
            homeViewModel.errorMessage != nil {
            HStack(spacing: 8) {
                if homeViewModel.isLoadingChip || homeViewModel.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                if homeViewModel.isLoadingChip {
                    Text("Cambiando recomendaciones…")
                } else if let error = homeViewModel.errorMessage {
                    Text(homeViewModel.isShowingSavedFeed ? "No se pudo actualizar · Contenido guardado" : "Sin conexión · se muestran las últimas recomendaciones")
                        .help(error)
                    Button {
                        refresh()
                    } label: {
                        Text("Reintentar")
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                } else if homeViewModel.isShowingSavedFeed {
                    if homeViewModel.isRefreshing {
                        Text("Recomendaciones guardadas · actualizando")
                    } else {
                        Text("Recomendaciones guardadas")
                    }
                } else {
                    Text("Actualizando recomendaciones…")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 8)
            .accessibilityElement(children: .combine)
        }
    }

    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label("No se pudo cargar Inicio", systemImage: "wifi.exclamationmark")
        } description: {
            Text(error)
        } actions: {
            Button("Reintentar") { refresh() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refresh() {
        guard let core = playerViewModel.rustCore else { return }
        Task {
            await homeViewModel.loadHomeFeed(core: core, chipParams: homeViewModel.selectedChipParams)
        }
    }

    private func loadMore() {
        guard let core = playerViewModel.rustCore else { return }
        Task { await homeViewModel.loadMoreContent(core: core) }
    }

    private func navigate(_ destination: PageDestination) {
        if let onNavigate { onNavigate(destination) }
        else { router?.navigate(to: destination) }
    }
}
