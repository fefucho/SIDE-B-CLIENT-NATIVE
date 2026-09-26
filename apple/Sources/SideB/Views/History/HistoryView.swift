import SwiftUI
import SideBCore

struct HistoryView: View {
    let rustCore: SideBCore
    @Bindable var playerViewModel: PlayerViewModel
    @Bindable var libraryViewModel: LibraryViewModel
    var router: NavigationRouter? = nil

    private var allHistoryTracks: [SongItemRecord] {
        libraryViewModel.historyGroups.flatMap(\.items)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("COLECCIÓN")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)

                Text("Historial")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Tus reproducciones recientes en YouTube Music")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 14)

            Divider()
                .opacity(0.2)
                .padding(.horizontal, 32)
                .padding(.bottom, 8)

            if (libraryViewModel.isLoading || libraryViewModel.isHistoryLoading) && libraryViewModel.historyGroups.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let error = libraryViewModel.historyErrorMessage, allHistoryTracks.isEmpty {
                DetailErrorStateView(
                    title: "No se pudo cargar el historial",
                    message: error,
                    onRetry: {
                        Task {
                            await libraryViewModel.loadHistory(core: rustCore)
                        }
                    }
                )
            } else if allHistoryTracks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No hay reproducciones recientes")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NativeTrackTableView(
                    tracks: allHistoryTracks,
                    currentTrackVideoId: playerViewModel.currentTrack?.videoId,
                    isPlaying: playerViewModel.isPlaying,
                    playerViewModel: playerViewModel,
                    router: router,
                    rustCore: rustCore,
                    likedVideoIds: playerViewModel.likedVideoIds,
                    onPlayTrack: { index in
                        playerViewModel.queueManager.replaceQueue(
                            with: allHistoryTracks,
                            startingAt: index,
                            context: .custom(title: "Historial"),
                            contextTitle: "Historial"
                        )
                        playerViewModel.playQueueIndex(index)
                    },
                    onLikeTrack: { track in
                        playerViewModel.toggleTrackLike(track)
                    },
                    onDislikeTrack: { track in
                        playerViewModel.dislikeTrack(track)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await libraryViewModel.loadHistory(core: rustCore)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideBPlaybackRecorded)) { notification in
            if let track = notification.userInfo?["track"] as? SongItemRecord {
                libraryViewModel.prependPlayedTrack(track)
            }
        }
    }
}
