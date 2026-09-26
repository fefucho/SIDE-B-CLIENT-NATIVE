import AppKit
import SwiftUI
import SideBCore

/// Un solo viewport vertical; los estantes horizontales son secciones del layout nativo.
struct HomeFeedCollectionView: NSViewRepresentable {
    let sections: [HomeSectionPresentation]
    let revision: UInt64
    let selectedChip: String?
    let hasMore: Bool
    let isLoadingMore: Bool
    let currentTrackID: String?
    let isPlaying: Bool
    let player: PlayerViewModel
    let router: NavigationRouter?
    let onNavigate: (PageDestination) -> Void
    let onLoadMore: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let layout = NSCollectionViewCompositionalLayout { [weak coordinator] index, environment in
            coordinator?.layoutSection(at: index, width: environment.container.effectiveContentSize.width)
        }
        let collection = HomeNativeCollectionView()
        collection.collectionViewLayout = layout
        collection.backgroundColors = [.clear]
        collection.isSelectable = true
        collection.allowsMultipleSelection = false
        collection.delegate = coordinator
        collection.register(HomeCollectionItem.self, forItemWithIdentifier: HomeCollectionItem.identifier)
        collection.register(HomeLoadMoreItem.self, forItemWithIdentifier: HomeLoadMoreItem.identifier)
        collection.register(
            HomeSectionHeaderView.self,
            forSupplementaryViewOfKind: Coordinator.headerKind,
            withIdentifier: HomeSectionHeaderView.identifier
        )
        collection.setAccessibilityLabel("Recomendaciones de Inicio")
        collection.onActivateSelection = { [weak coordinator] indexPath in
            coordinator?.activate(at: indexPath)
        }
        collection.onHoverPosition = { [weak coordinator] point in
            coordinator?.updateHover(at: point)
        }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .allowed
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 10, left: 0, bottom: 120, right: 0)
        scroll.documentView = collection
        scroll.contentView.postsBoundsChangedNotifications = true
        coordinator.collection = collection
        coordinator.installDataSource(on: collection)
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.clipBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )
        coordinator.applyContent()
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        if let collection = scroll.documentView as? HomeNativeCollectionView {
            collection.delegate = nil
            collection.onActivateSelection = nil
            collection.onHoverPosition = nil
        }
        coordinator.collection = nil
        coordinator.dataSource = nil
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let old = coordinator.parent
        coordinator.parent = self
        guard let collection = scroll.documentView as? HomeNativeCollectionView else { return }
        if old.revision != revision || old.hasMore != hasMore {
            coordinator.applyContent()
            if old.selectedChip != selectedChip {
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        } else {
            if old.currentTrackID != currentTrackID || old.isPlaying != isPlaying {
                coordinator.updateVisiblePlayback()
            }
            if old.isLoadingMore != isLoadingMore {
                coordinator.updateLoadMore()
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDelegate {
        static let headerKind = "HomeSectionHeader"
        static let footerSection = "__home_pagination__"
        static let footerItem = "__home_load_more__"

        var parent: HomeFeedCollectionView
        fileprivate weak var collection: HomeNativeCollectionView?
        var dataSource: NSCollectionViewDiffableDataSource<String, String>?
        private var itemByID: [String: HomeItemPresentation] = [:]
        private var sectionByID: [String: HomeSectionPresentation] = [:]
        private weak var hoveredItem: HomeCollectionItem?

        init(parent: HomeFeedCollectionView) { self.parent = parent }
        deinit { NotificationCenter.default.removeObserver(self) }

        fileprivate func installDataSource(on collection: HomeNativeCollectionView) {
            let source = NSCollectionViewDiffableDataSource<String, String>(collectionView: collection) { [weak self] collection, indexPath, identifier in
                guard let self else { return nil }
                if identifier == Self.footerItem {
                    let item = collection.makeItem(withIdentifier: HomeLoadMoreItem.identifier, for: indexPath) as! HomeLoadMoreItem
                    item.configure(loading: self.parent.isLoadingMore) { [weak self] in self?.parent.onLoadMore() }
                    return item
                }
                guard let payload = self.itemByID[identifier] else { return nil }
                let item = collection.makeItem(withIdentifier: HomeCollectionItem.identifier, for: indexPath) as! HomeCollectionItem
                self.configure(item, payload: payload, style: payload.style)
                return item
            }
            source.supplementaryViewProvider = { [weak self] collection, kind, indexPath in
                guard let self, kind == Self.headerKind else { return nil }
                let header = collection.makeSupplementaryView(
                    ofKind: kind, withIdentifier: HomeSectionHeaderView.identifier, for: indexPath
                ) as! HomeSectionHeaderView
                let sectionIDs = self.dataSource?.snapshot().sectionIdentifiers ?? []
                if indexPath.section < sectionIDs.count,
                   let section = self.sectionByID[sectionIDs[indexPath.section]] {
                    header.configure(title: section.title, showsMore: section.isNavigableMore) { [weak self] in
                        self?.navigateMore(in: section.id)
                    }
                }
                return header
            }
            dataSource = source
        }

        func applyContent() {
            guard let dataSource, let collection else { return }
            sectionByID = Dictionary(uniqueKeysWithValues: parent.sections.map { ($0.id, $0) })
            itemByID = Dictionary(uniqueKeysWithValues: parent.sections.flatMap { $0.items.map { ($0.id, $0) } })

            var snapshot = NSDiffableDataSourceSnapshot<String, String>()
            for section in parent.sections {
                snapshot.appendSections([section.id])
                snapshot.appendItems(section.items.map(\.id), toSection: section.id)
            }
            if parent.hasMore {
                snapshot.appendSections([Self.footerSection])
                snapshot.appendItems([Self.footerItem], toSection: Self.footerSection)
            }
            dataSource.apply(snapshot, animatingDifferences: false)
            for indexPath in collection.indexPathsForVisibleItems() {
                guard let identifier = dataSource.itemIdentifier(for: indexPath),
                      let payload = itemByID[identifier],
                      let item = collection.item(at: indexPath) as? HomeCollectionItem else { continue }
                configure(item, payload: payload, style: payload.style)
            }
            updateLoadMore()
        }

        func layoutSection(at index: Int, width: CGFloat) -> NSCollectionLayoutSection? {
            guard parent.sections.indices.contains(index) || (parent.hasMore && index == parent.sections.count) else { return nil }
            if index == parent.sections.count {
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(64))
                let item = NSCollectionLayoutItem(layoutSize: size)
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 28, bottom: 0, trailing: 28)
                return section
            }
            let spec = parent.sections[index]
            let compact = width < 760
            let item: NSCollectionLayoutItem
            let group: NSCollectionLayoutGroup
            let section: NSCollectionLayoutSection
            if spec.style == .quickPicks {
                let row = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(56))
                item = NSCollectionLayoutItem(layoutSize: row)
                let groupSize = NSCollectionLayoutSize(
                    widthDimension: .absolute(compact ? 286 : 330), heightDimension: .absolute(172)
                )
                group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitem: item, count: 3)
                group.interItemSpacing = .fixed(2)
            } else {
                let cardWidth: CGFloat = compact ? 136 : 156
                let height: CGFloat = compact ? 188 : 208
                let size = NSCollectionLayoutSize(widthDimension: .absolute(cardWidth), heightDimension: .absolute(height))
                item = NSCollectionLayoutItem(layoutSize: size)
                group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
            }
            section = NSCollectionLayoutSection(group: group)
            section.orthogonalScrollingBehavior = .continuous
            section.interGroupSpacing = 16
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 28, bottom: 24, trailing: 28)
            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(46))
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize, elementKind: Self.headerKind, alignment: .top
            )
            section.boundarySupplementaryItems = [header]
            return section
        }

        private func sectionID(at indexPath: IndexPath) -> String {
            dataSource?.snapshot().sectionIdentifiers[safe: indexPath.section] ?? ""
        }

        private func configure(_ cell: HomeCollectionItem, payload: HomeItemPresentation, style: HomeSectionStyle) {
            let id = payload.id
            cell.content.configure(
                record: payload.record,
                style: style,
                currentTrackID: parent.currentTrackID,
                isPlaying: parent.isPlaying,
                onCard: { [weak self] in self?.activate(itemID: id, fromCover: true) },
                onCover: { [weak self] in self?.activate(itemID: id, fromCover: true) },
                onTitle: { [weak self] in self?.activate(itemID: id, fromCover: true) },
                onArtist: { [weak self] in self?.navigateArtist(itemID: id) },
                onAlbum: { [weak self] in self?.navigateAlbum(itemID: id) },
                // El menú debe usar el mismo valor inmutable que pintó esta celda. Consultar
                // itemByID más tarde puede leer otro snapshot si Inicio se actualiza entretanto.
                menuProvider: { [weak self, record = payload.record] in self?.menu(record: record) }
            )
        }

        func activate(at indexPath: IndexPath) {
            guard let id = dataSource?.itemIdentifier(for: indexPath) else { return }
            activate(itemID: id, fromCover: true)
        }

        private func activate(itemID: String, fromCover: Bool) {
            guard let record = itemByID[itemID]?.record else { return }
            if record.kind == "song" {
                if fromCover && parent.currentTrackID == record.id && parent.isPlaying {
                    parent.player.togglePlayPause()
                } else {
                    parent.player.playWithRadio(SongItemRecord(fromHomeItem: record))
                }
                return
            }
            switch record.kind {
            case "album": parent.onNavigate(.album(browseId: record.id))
            case "artist": parent.onNavigate(.artist(browseId: record.id))
            default: parent.onNavigate(.playlist(browseId: record.id))
            }
        }

        private func navigateArtist(itemID: String) {
            guard let record = itemByID[itemID]?.record else { return }
            if let id = record.artistId, !id.isEmpty {
                parent.onNavigate(.artist(browseId: id))
            } else {
                let artistQuery = HomeItemView.cleanArtistName(from: record)
                parent.onNavigate(.search(query: artistQuery))
            }
        }

        private func navigateAlbum(itemID: String) {
            guard let record = itemByID[itemID]?.record else { return }
            if let id = record.albumId, !id.isEmpty {
                parent.onNavigate(.album(browseId: id))
            } else if let album = record.album, !album.isEmpty {
                parent.onNavigate(.search(query: album))
            } else if let albumQuery = HomeItemView.cleanAlbumName(from: record) {
                parent.onNavigate(.search(query: albumQuery))
            }
        }

        private func navigateMore(in sectionID: String) {
            guard let section = sectionByID[sectionID], let id = section.moreBrowseId else { return }
            if id.hasPrefix("MPRE") {
                parent.onNavigate(.album(browseId: id))
            } else if id.hasPrefix("UC") {
                parent.onNavigate(.artist(browseId: id))
            } else if id.hasPrefix("FE") {
                print("[HomeFeed] moreBrowseId de categoría \(id) no es navegable como playlist.")
            } else {
                parent.onNavigate(.playlist(browseId: id))
            }
        }

        private func menu(record: HomeItemRecord) -> NSMenu? {
            let factory = AppContextMenuFactory.shared
            let core = parent.player.rustCore
            switch record.kind {
            case "song":
                return factory.buildSongNSMenu(
                    song: SongItemRecord(fromHomeItem: record),
                    player: parent.player,
                    router: parent.router,
                    core: core,
                    origin: .home
                )
            case "album":
                return factory.buildAlbumNSMenu(
                    browseId: record.id,
                    playlistId: nil,
                    title: record.title,
                    artist: record.subtitle,
                    thumbnail: record.thumbnail,
                    inLibrary: nil,
                    origin: .home,
                    player: parent.player,
                    router: parent.router,
                    core: core
                )
            case "artist":
                return factory.buildArtistNSMenu(
                    channelId: record.id,
                    name: record.title,
                    thumbnail: record.thumbnail,
                    radioPlaylistId: nil,
                    origin: .home,
                    player: parent.player,
                    router: parent.router,
                    core: core
                )
            default:
                return factory.buildPlaylistNSMenu(
                    id: record.id,
                    title: record.title,
                    subtitle: record.subtitle,
                    thumbnail: record.thumbnail,
                    origin: .home,
                    player: parent.player,
                    router: parent.router,
                    core: core
                )
            }
        }

        func updateVisiblePlayback() {
            guard let collection else { return }
            for indexPath in collection.indexPathsForVisibleItems() {
                (collection.item(at: indexPath) as? HomeCollectionItem)?.content.updatePlayback(
                    currentTrackID: parent.currentTrackID, isPlaying: parent.isPlaying
                )
            }
        }

        func updateLoadMore() {
            guard let collection, let dataSource,
                  let path = dataSource.indexPath(for: Self.footerItem),
                  collection.indexPathsForVisibleItems().contains(path) else { return }
            (collection.item(at: path) as? HomeLoadMoreItem)?.configure(loading: parent.isLoadingMore) { [weak self] in
                self?.parent.onLoadMore()
            }
        }

        @objc func clipBoundsChanged(_ notification: Notification) {
            guard let collection, let window = collection.window else { return }
            let point = window.mouseLocationOutsideOfEventStream
            let collectionPoint = collection.convert(point, from: nil)
            updateHover(at: collectionPoint)
        }

        func updateHover(at point: NSPoint?) {
            guard let collection else { return }
            var next: HomeCollectionItem?
            var pointInItem: NSPoint?
            if let point, collection.visibleRect.contains(point) {
                for indexPath in collection.indexPathsForVisibleItems() {
                    guard let item = collection.item(at: indexPath) as? HomeCollectionItem else { continue }
                    if item.view.convert(item.view.bounds, to: collection).contains(point) {
                        next = item
                        pointInItem = item.view.convert(point, from: collection)
                        break
                    }
                }
            }
            if hoveredItem !== next {
                hoveredItem?.content.setHovered(false, localPoint: nil)
                next?.content.setHovered(true, localPoint: pointInItem)
                hoveredItem = next
            } else if let next, let pointInItem {
                next.content.updateHoverLocation(pointInItem)
            }
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

private final class HomeNativeCollectionView: NSCollectionView {
    var onActivateSelection: ((IndexPath) -> Void)?
    var onHoverPosition: ((NSPoint?) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        guard let scroll = subview as? NSScrollView else { return }
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.horizontalScrollElasticity = .allowed
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(shelfBoundsChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }

    override func willRemoveSubview(_ subview: NSView) {
        if let scroll = subview as? NSScrollView {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification,
                                                      object: scroll.contentView)
        }
        super.willRemoveSubview(subview)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func shelfBoundsChanged(_ notification: Notification) {
        guard let window else { return }
        onHoverPosition?(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard hoverTrackingArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverPosition?(convert(event.locationInWindow, from: nil))
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverPosition?(nil)
        super.mouseExited(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 49 || event.keyCode == 36), let selected = selectionIndexPaths.first {
            onActivateSelection?(selected)
            return
        }
        super.keyDown(with: event)
    }
}

private final class HomeCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("HomeFeedItem")
    var content: HomeItemView { view as! HomeItemView }
    override func loadView() { view = HomeItemView(frame: NSRect(x: 0, y: 0, width: 156, height: 208)) }
    override var isSelected: Bool { didSet { content.isSelectedInFeed = isSelected } }
    override func prepareForReuse() { super.prepareForReuse(); content.prepareForReuse() }
}

private final class HomeSectionHeaderView: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("HomeFeedHeader")
    private let title = NSTextField(labelWithString: "")
    private let more = NSButton(title: "Ver todo", target: nil, action: nil)
    private var action: (() -> Void)?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = .systemFont(ofSize: 19, weight: .bold)
        title.textColor = .labelColor
        addSubview(title)
        more.isBordered = false
        more.font = .systemFont(ofSize: 13, weight: .semibold)
        more.contentTintColor = NSColor.controlAccentColor
        more.target = self
        more.action = #selector(openMore)
        more.setAccessibilityLabel("Ver todo")
        addSubview(more)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }
    override func prepareForReuse() { super.prepareForReuse(); action = nil }
    override func layout() {
        super.layout()
        title.frame = NSRect(x: 0, y: 6, width: max(0, bounds.width - 100), height: 28)
        more.frame = NSRect(x: max(0, bounds.width - 90), y: 8, width: 90, height: 25)
    }
    func configure(title: String, showsMore: Bool, action: @escaping () -> Void) {
        self.title.stringValue = title
        self.more.isHidden = !showsMore
        self.more.setAccessibilityLabel("Ver todo: \(title)")
        self.action = action
    }
    @objc private func openMore() { action?() }
}

private final class HomeLoadMoreItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("HomeLoadMore")
    private let button = NSButton(title: "Cargar más recomendaciones", target: nil, action: nil)
    private var action: (() -> Void)?
    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 64))
        button.isBordered = true
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(loadMore)
        root.addSubview(button)
        view = root
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        button.frame = NSRect(x: max(0, (view.bounds.width - 220) / 2), y: 12, width: 220, height: 32)
    }
    func configure(loading: Bool, action: @escaping () -> Void) {
        self.action = action
        button.title = loading ? "Cargando recomendaciones…" : "Cargar más recomendaciones"
        button.isEnabled = !loading
    }
    @objc private func loadMore() { action?() }
}

private final class HomePassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class HomeInteractiveLinkButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        refusesFirstResponder = true
        focusRingType = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !isHidden && bounds.width > 0 && bounds.height > 0 {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

final class HomeItemView: NSView {
    private struct Appearance: Equatable {
        let hovered: Bool
        let selected: Bool
        let playing: Bool
        let quickPicks: Bool
    }

    let cardButton = NSButton()
    private let cover = NSButton()
    private let playSymbol = HomePassthroughImageView()
    private let playImage = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
    private let waveformImage = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
    private let title = NSButton()
    let artist = HomeInteractiveLinkButton()
    private let album = HomeInteractiveLinkButton()
    private let subtitle = NSTextField(labelWithString: "")
    private let bullet = NSTextField(labelWithString: "•")
    private let mixBadge = NSTextField(labelWithString: "MIX")
    private let more = HomeInteractiveLinkButton()
    private var imageTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var representedID: String?
    private var style: HomeSectionStyle = .cards
    private var playing = false
    private var renderedAppearance: Appearance?
    var hovered = false { didSet { if hovered != oldValue { refreshAppearance() } } }
    var isSelectedInFeed = false { didSet { if isSelectedInFeed != oldValue { refreshAppearance() } } }
    private var onCard: (() -> Void)?
    private var onCover: (() -> Void)?
    private var onTitle: (() -> Void)?
    private var onArtist: (() -> Void)?
    private var onAlbum: (() -> Void)?
    private var menuProvider: (() -> NSMenu?)?
    private var rawArtistTitle: String = ""
    private var rawAlbumTitle: String = ""
    private(set) var isArtistHovered = false
    private var isAlbumHovered = false
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = AppTheme.cardBorderWidth
        layer?.borderColor = NSColor.white.withAlphaComponent(0.06).cgColor

        // Botón base que cubre todo el marco de la tarjeta
        cardButton.title = ""
        cardButton.isTransparent = true
        setup(cardButton, selector: #selector(cardPressed), font: nil)
        cardButton.title = ""
        cardButton.isTransparent = true
        cardButton.refusesFirstResponder = true
        cardButton.focusRingType = .none

        setup(cover, selector: #selector(cardPressed), font: nil)
        cover.imagePosition = .imageOnly
        cover.imageScaling = .scaleProportionallyUpOrDown
        cover.wantsLayer = true
        cover.layer?.masksToBounds = true
        cover.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.12).cgColor
        cover.refusesFirstResponder = true
        cover.focusRingType = .none

        playSymbol.imageScaling = .scaleProportionallyDown
        playSymbol.contentTintColor = .white
        addSubview(playSymbol)

        setup(title, selector: #selector(cardPressed), font: .systemFont(ofSize: 13, weight: .semibold))
        title.alignment = .left
        title.contentTintColor = .labelColor
        title.refusesFirstResponder = true
        title.focusRingType = .none

        setup(artist, selector: #selector(artistPressed), font: .systemFont(ofSize: 11.5, weight: .medium))
        artist.alignment = .left
        artist.contentTintColor = .secondaryLabelColor

        setup(album, selector: #selector(albumPressed), font: .systemFont(ofSize: 11.5, weight: .medium))
        album.alignment = .left
        album.contentTintColor = .secondaryLabelColor

        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        addSubview(subtitle)

        bullet.font = .systemFont(ofSize: 10)
        bullet.textColor = .tertiaryLabelColor
        addSubview(bullet)

        mixBadge.font = .systemFont(ofSize: 10, weight: .bold)
        mixBadge.textColor = .white
        mixBadge.wantsLayer = true
        mixBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        mixBadge.layer?.cornerRadius = 4
        addSubview(mixBadge)

        setup(more, selector: #selector(morePressed), font: nil)
        more.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Más opciones")
        more.imagePosition = .imageOnly
        more.contentTintColor = .secondaryLabelColor
        more.setAccessibilityLabel("Más opciones")

        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    private func setup(_ button: NSButton, selector: Selector, font: NSFont?) {
        button.isBordered = false
        button.target = self
        button.action = selector
        button.lineBreakMode = .byTruncatingTail
        if let font { button.font = font }
        addSubview(button)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardButton.frame = bounds
        if style == .quickPicks {
            layer?.cornerRadius = 14
            cover.frame = NSRect(x: 6, y: 6, width: 44, height: 44)
            playSymbol.frame = NSRect(x: 19, y: 19, width: 18, height: 18)

            let textLeading: CGFloat = 58
            let moreTrailingMargin: CGFloat = 38
            let maxTextWidth = max(0, bounds.width - textLeading - moreTrailingMargin)
            title.frame = NSRect(x: textLeading, y: 8, width: maxTextWidth, height: 19)

            let measureFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            let artistText = rawArtistTitle.isEmpty ? artist.title : rawArtistTitle
            let artistTextWidth = ceil((artistText as NSString).size(withAttributes: [.font: measureFont]).width) + 2

            let artistWidth = min(artistTextWidth, maxTextWidth)
            artist.frame = NSRect(x: textLeading, y: 29, width: artistWidth, height: 17)
            album.isHidden = true
            bullet.isHidden = true

            more.frame = NSRect(x: bounds.width - 34, y: 14, width: 28, height: 28)
            more.layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            layer?.cornerRadius = 14
            let art = bounds.width
            cover.frame = NSRect(x: 0, y: 0, width: art, height: art)
            playSymbol.frame = NSRect(x: art - 36, y: art - 36, width: 28, height: 28)
            title.frame = NSRect(x: 0, y: art + 7, width: art, height: 20)
            subtitle.frame = NSRect(x: 1, y: art + 30, width: art - 2, height: 17)
            mixBadge.frame = NSRect(x: 8, y: 8, width: 34, height: 16)
            more.frame = NSRect(x: art - 34, y: 6, width: 28, height: 28)
            more.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
            more.layer?.cornerRadius = 14
        }
        cover.layer?.cornerRadius = style == .quickPicks ? 8 : (representedKind == "artist" ? bounds.width / 2 : 12)
        CATransaction.commit()
        window?.invalidateCursorRects(for: self)
    }

    static func parseSubtitleComponents(_ rawSubtitle: String?) -> [String] {
        guard let raw = rawSubtitle, !raw.isEmpty else { return [] }
        return raw.components(separatedBy: " • ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func isGenericTypePrefix(_ text: String) -> Bool {
        let lower = text.lowercased()
        let prefixes = ["album", "álbum", "single", "sencillo", "ep", "song", "canción", "video", "vídeo", "playlist", "lista", "mix"]
        return prefixes.contains(lower)
    }

    static func cleanArtistName(from record: HomeItemRecord) -> String {
        if let artists = record.artists, !artists.isEmpty {
            return artists
        }
        let comps = parseSubtitleComponents(record.subtitle)
        if let first = comps.first {
            if isGenericTypePrefix(first) && comps.count > 1 {
                return comps[1]
            } else if !isGenericTypePrefix(first) {
                return first
            }
        }
        return record.subtitle ?? "Varios Artistas"
    }

    static func cleanAlbumName(from record: HomeItemRecord) -> String? {
        if record.kind == "album" || record.kind == "artist" {
            return nil
        }
        if let album = record.album, !album.isEmpty {
            return album
        }
        let comps = parseSubtitleComponents(record.subtitle)
        let startIndex: Int
        if let first = comps.first, isGenericTypePrefix(first) {
            startIndex = 2
        } else {
            startIndex = 1
        }
        if comps.count > startIndex {
            let candidate = comps[startIndex]
            if candidate.range(of: #"^\d{4}$"#, options: .regularExpression) != nil {
                return nil
            }
            if candidate.range(of: #"^\d+:\d{2}$"#, options: .regularExpression) != nil {
                return nil
            }
            let lower = candidate.lowercased()
            if lower.contains("vistas") || lower.contains("views") || lower.contains("reproducciones") {
                return nil
            }
            return candidate
        }
        return nil
    }

    private var representedKind = ""

    func configure(
        record: HomeItemRecord, style: HomeSectionStyle, currentTrackID: String?, isPlaying: Bool,
        onCard: @escaping () -> Void, onCover: @escaping () -> Void, onTitle: @escaping () -> Void,
        onArtist: @escaping () -> Void, onAlbum: @escaping () -> Void,
        menuProvider: @escaping () -> NSMenu?
    ) {
        if representedID != nil { prepareForReuse() }
        self.style = style
        representedID = record.id
        representedKind = record.kind
        self.onCard = onCard
        self.onCover = onCover
        self.onTitle = onTitle
        self.onArtist = onArtist
        self.onAlbum = onAlbum
        self.menuProvider = menuProvider

        cardButton.title = ""
        cardButton.isTransparent = true
        cardButton.toolTip = record.title
        title.title = record.title
        title.toolTip = record.title
        title.setAccessibilityLabel("Abrir \(record.title)")
        subtitle.stringValue = record.subtitle ?? ""

        let artistName = Self.cleanArtistName(from: record)
        rawArtistTitle = artistName
        artist.title = artistName
        artist.setAccessibilityLabel("Ver artista: \(artistName)")

        album.isHidden = true
        bullet.isHidden = true
        artist.isHidden = style != .quickPicks
        subtitle.isHidden = style == .quickPicks

        refreshArtistAppearance()

        let isMix = (record.kind == "mix" ||
                     (record.kind == "playlist" && (record.title.lowercased().contains("mix") || record.subtitle?.lowercased().contains("mix") == true))) &&
                    record.kind != "album" && record.kind != "artist"
        mixBadge.isHidden = !isMix
        updatePlayback(currentTrackID: currentTrackID, isPlaying: isPlaying)
        refreshAppearance()
        needsLayout = true

        guard let url = ImageURLHelper.optimizedThumbnailURL(
            from: record.thumbnail, targetPixelSize: style == .quickPicks ? 112 : 320
        ) else {
            cover.image = NSImage(systemSymbolName: record.kind == "artist" ? "person.crop.circle" : "music.note", accessibilityDescription: nil)
            cover.contentTintColor = .secondaryLabelColor
            return
        }
        let target = style == .quickPicks ? CGSize(width: 48, height: 48) : CGSize(width: 156, height: 156)
        if let cached = ImageCache.shared.imageFromMemoryCache(for: url, targetSize: target) {
            cover.image = cached
            return
        }
        let expectedGeneration = generation
        imageTask = Task(priority: .utility) { [weak self] in
            let image = await ImageCache.shared.image(for: url, targetSize: target)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.generation == expectedGeneration else { return }
                self.cover.image = image
            }
        }
    }

    private func refreshArtistAppearance() {
        guard !artist.isHidden else { return }
        let text = rawArtistTitle.isEmpty ? artist.title : rawArtistTitle
        guard !text.isEmpty else { return }
        let isHovered = isArtistHovered
        let font = NSFont.systemFont(ofSize: 11.5, weight: isHovered ? .semibold : .medium)
        let color: NSColor = isHovered ? .labelColor : .secondaryLabelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .left

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        artist.attributedTitle = NSAttributedString(string: text, attributes: attrs)
    }

    private func refreshAlbumAppearance() {
        guard !album.isHidden else { return }
        let text = rawAlbumTitle.isEmpty ? album.title : rawAlbumTitle
        guard !text.isEmpty else { return }
        let isHovered = isAlbumHovered
        let font = NSFont.systemFont(ofSize: 11.5, weight: isHovered ? .semibold : .medium)
        let color: NSColor = isHovered ? .labelColor : .secondaryLabelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .left

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        album.attributedTitle = NSAttributedString(string: text, attributes: attrs)
    }

    func updatePlayback(currentTrackID: String?, isPlaying: Bool) {
        playing = representedKind == "song" && representedID == currentTrackID && isPlaying
        let actionLabel = playing ? "Pausar \(title.title)" : "Abrir \(title.title)"
        cover.setAccessibilityLabel(actionLabel)
        cardButton.setAccessibilityLabel(actionLabel)
        cardButton.title = ""
        cardButton.isTransparent = true
        refreshAppearance()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        generation &+= 1
        representedID = nil
        representedKind = ""
        cardButton.title = ""
        cardButton.isTransparent = true
        cover.image = nil
        cover.contentTintColor = nil
        hovered = false
        isArtistHovered = false
        isAlbumHovered = false
        rawArtistTitle = ""
        rawAlbumTitle = ""
        renderedAppearance = nil
        onCard = nil
        onCover = nil
        onTitle = nil
        onArtist = nil
        onAlbum = nil
        menuProvider = nil
    }

    func setHovered(_ value: Bool, localPoint: NSPoint? = nil) {
        if hovered != value { hovered = value }
        if !value {
            if isArtistHovered {
                isArtistHovered = false
                refreshArtistAppearance()
            }
            if isAlbumHovered {
                isAlbumHovered = false
                refreshAlbumAppearance()
            }
        } else if let localPoint {
            updateHoverLocation(localPoint)
        }
    }

    func updateHoverLocation(_ point: NSPoint) {
        if !artist.isHidden {
            let overArtist = artist.frame.contains(point)
            if isArtistHovered != overArtist {
                isArtistHovered = overArtist
                refreshArtistAppearance()
            }
        }
        if !album.isHidden {
            let overAlbum = album.frame.contains(point)
            if isAlbumHovered != overAlbum {
                isAlbumHovered = overAlbum
                refreshAlbumAppearance()
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // AppKit entrega el punto en coordenadas del superview. No podemos reclamar un clic
        // fuera de esta celda: en los estantes horizontales otra canción podría abrir su menú.
        guard let hit = super.hitTest(point) else { return nil }
        if let event = NSApp.currentEvent,
           event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            return self
        }
        return hit
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = menuProvider?() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
        else { super.rightMouseDown(with: event) }
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let menu = menuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else { super.mouseDown(with: event) }
    }

    private func refreshAppearance() {
        let next = Appearance(hovered: hovered, selected: isSelectedInFeed,
                              playing: playing, quickPicks: style == .quickPicks)
        guard renderedAppearance != next else { return }
        let previous = renderedAppearance
        renderedAppearance = next
        let isHighlighted = hovered || isSelectedInFeed
        if style == .quickPicks {
            layer?.backgroundColor = (isHighlighted ? NSColor.white.withAlphaComponent(0.08) : NSColor.clear).cgColor
            layer?.borderColor = (isHighlighted ? NSColor.white.withAlphaComponent(0.12) : NSColor.white.withAlphaComponent(0.06)).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderColor = NSColor.clear.cgColor
        }
        playSymbol.isHidden = !(hovered || playing)
        if previous?.playing != playing { playSymbol.image = playing ? waveformImage : playImage }
        more.contentTintColor = hovered ? .labelColor : .secondaryLabelColor
        more.isHidden = (style != .quickPicks && !hovered)
    }

    @objc private func cardPressed() { (onCard ?? onCover ?? onTitle)?() }
    @objc private func coverPressed() { cardPressed() }
    @objc private func titlePressed() { cardPressed() }
    @objc private func artistPressed() { onArtist?() }
    @objc private func albumPressed() { onAlbum?() }
    @objc private func morePressed() {
        menuProvider?()?.popUp(positioning: nil, at: NSPoint(x: 0, y: more.bounds.height), in: more)
    }
}
