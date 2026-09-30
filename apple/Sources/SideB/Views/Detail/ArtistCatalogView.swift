import SwiftUI
import SideBCore

/// The filtered browse page behind an artist carousel's "Ver todo" action.
struct ArtistCatalogView: View {
    let browseId: String
    let params: String?
    let title: String
    let rustCore: SideBCore
    @Bindable var playerViewModel: PlayerViewModel
    var router: NavigationRouter?

    @State private var cards: [BrowseCardRecord] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.system(size: 28, weight: .bold))

                if isLoading {
                    ProgressView("Cargando…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Text("No se pudo cargar el catálogo")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Reintentar") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else if cards.isEmpty {
                    ContentUnavailableView("No hay publicaciones", systemImage: "square.stack")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 18)], alignment: .leading, spacing: 24) {
                        ForEach(cards, id: \.id) { card in
                            CatalogCardView(
                                card: card,
                                rustCore: rustCore,
                                playerViewModel: playerViewModel,
                                router: router,
                                artistBrowseId: browseId
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 120)
        }
        .task(id: "\(browseId)|\(params ?? "")") { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            cards = try await rustCore.getBrowseGrid(browseId: browseId, params: params)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct CatalogCardView: View {
    let card: BrowseCardRecord
    let rustCore: SideBCore
    @Bindable var playerViewModel: PlayerViewModel
    var router: NavigationRouter?
    var artistBrowseId: String? = nil

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 7) {
                if let thumbnail = card.thumbnail,
                   let url = ImageURLHelper.optimizedThumbnailURL(from: thumbnail, targetPixelSize: 360) {
                    CachedAsyncImage(url: url, targetSize: CGSize(width: 180, height: 180)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        placeholder
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    placeholder
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
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
        .browseCardContextMenu(
            card: card,
            player: playerViewModel,
            router: router,
            core: rustCore,
            origin: artistBrowseId.map { .artist(channelId: $0) } ?? .album(browseId: card.id),
            knownArtistId: artistBrowseId
        )
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.secondary.opacity(0.12))
            .overlay(Image(systemName: "opticaldisc").foregroundStyle(.secondary))
    }

    private func open() {
        switch card.kind {
        case "album": router?.navigate(to: .album(browseId: card.id))
        case "artist": router?.navigate(to: .artist(browseId: card.id))
        case "playlist": router?.navigate(to: .playlist(browseId: card.id))
        case "song", "video":
            playerViewModel.playSong(SongItemRecord(fromCard: card, knownArtistId: artistBrowseId))
        default: break
        }
    }
}
