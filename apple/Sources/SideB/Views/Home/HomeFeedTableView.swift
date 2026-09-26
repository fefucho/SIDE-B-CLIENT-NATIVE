import AppKit
import SwiftUI
import SideBCore

/// El scroll vertical recicla estantes completos; cada estante recicla sus tarjetas en horizontal.
/// Así las categorías agregadas por paginación no mantienen scrollers ortogonales fuera de pantalla.
struct HomeFeedTableView: NSViewRepresentable {
    let sections: [HomeSectionPresentation]
    let isObscured: Bool
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
        let scroll = NSScrollView()
        scroll.isHidden = isObscured
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .allowed
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 10, left: 0, bottom: 120, right: 0)

        let table = NSTableView()
        table.headerView = nil
        table.style = .plain
        table.usesAutomaticRowHeights = false
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.setAccessibilityLabel("Recomendaciones de Inicio")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("HomeShelfColumn"))
        column.minWidth = 260
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        scroll.documentView = table
        context.coordinator.table = table
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.boundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )
        table.reloadData()
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        if let table = scroll.documentView as? NSTableView {
            table.delegate = nil
            table.dataSource = nil
        }
        coordinator.table = nil
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let old = coordinator.parent
        coordinator.parent = self
        if old.isObscured != isObscured {
            if isObscured { coordinator.clearHover() }
            // AppKit tooltips and tracking areas outlive SwiftUI's opacity/hit-testing state.
            scroll.isHidden = isObscured
        }
        guard let table = scroll.documentView as? NSTableView else { return }
        let compact = scroll.contentView.bounds.width < 760
        if old.revision != revision || old.hasMore != hasMore || old.selectedChip != selectedChip ||
            coordinator.wasCompact != compact {
            coordinator.wasCompact = compact
            table.reloadData()
            if old.selectedChip != selectedChip {
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            coordinator.scheduleHoverUpdate()
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
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: HomeFeedTableView
        weak var table: NSTableView?
        var wasCompact = false
        private var horizontalOffsets: [String: CGFloat] = [:]
        private weak var hoveredShelf: HomeShelfRowView?
        private var hoverUpdateScheduled = false

        init(parent: HomeFeedTableView) { self.parent = parent }
        deinit { NotificationCenter.default.removeObserver(self) }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.sections.count + (parent.hasMore ? 1 : 0)
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard row < parent.sections.count else { return 68 }
            if parent.sections[row].style == .compactSong { return 300 }
            return (tableView.bounds.width < 760 ? 140 : 160) + HomeItemView.largeCardTextHeight + 70
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            if row == parent.sections.count {
                let view = (tableView.makeView(withIdentifier: HomeLoadMoreRowView.identifier, owner: nil) as? HomeLoadMoreRowView)
                    ?? HomeLoadMoreRowView()
                view.configure(loading: parent.isLoadingMore) { [weak self] in self?.parent.onLoadMore() }
                return view
            }

            let section = parent.sections[row]
            let view = (tableView.makeView(withIdentifier: HomeShelfRowView.identifier, owner: nil) as? HomeShelfRowView)
                ?? HomeShelfRowView()
            view.configure(
                section: section,
                horizontalOffset: horizontalOffsets[section.id] ?? 0,
                onHorizontalOffset: { [weak self, id = section.id] offset in self?.horizontalOffsets[id] = offset },
                onMore: { [weak self, id = section.id] in self?.navigateMore(sectionID: id) },
                onActivate: { [weak self] item in self?.activate(itemID: item.id, fromCover: true) },
                onConfigure: { [weak self] cell, item in self?.configure(cell, item: item) }
            )
            return view
        }

        func updateVisiblePlayback() {
            guard let table else { return }
            let visible = table.rows(in: table.visibleRect)
            guard visible.location != NSNotFound else { return }
            for row in visible.location..<NSMaxRange(visible) where row < parent.sections.count {
                (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? HomeShelfRowView)?
                    .updateVisiblePlayback(trackID: parent.currentTrackID, isPlaying: parent.isPlaying)
            }
        }

        func updateLoadMore() {
            guard let table, parent.hasMore else { return }
            (table.view(atColumn: 0, row: parent.sections.count, makeIfNecessary: false) as? HomeLoadMoreRowView)?
                .configure(loading: parent.isLoadingMore) { [weak self] in self?.parent.onLoadMore() }
        }

        @objc func boundsChanged(_ notification: Notification) { scheduleHoverUpdate() }

        func scheduleHoverUpdate() {
            guard !hoverUpdateScheduled else { return }
            hoverUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.hoverUpdateScheduled = false
                self.updateHoverAtPointer()
            }
        }

        private func updateHoverAtPointer() {
            guard !parent.isObscured else { clearHover(); return }
            guard let table, let window = table.window else { return }
            let point = table.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            let row = table.visibleRect.contains(point) ? table.row(at: point) : -1
            let next = row >= 0 && row < parent.sections.count
                ? table.view(atColumn: 0, row: row, makeIfNecessary: false) as? HomeShelfRowView
                : nil
            if hoveredShelf !== next { hoveredShelf?.clearHover() }
            hoveredShelf = next
            next?.updateHoverAtPointer()
        }

        func clearHover() {
            hoveredShelf?.clearHover()
            hoveredShelf = nil
        }

        private func item(for id: String) -> HomeItemPresentation? {
            for section in parent.sections {
                if let item = section.items.first(where: { $0.id == id }) { return item }
            }
            return nil
        }

        private func configure(_ cell: HomeCollectionItem, item: HomeItemPresentation) {
            let id = item.id
            cell.content.configure(
                record: item.record,
                style: item.style,
                currentTrackID: parent.currentTrackID,
                isPlaying: parent.isPlaying,
                onCard: { [weak self] in self?.activate(itemID: id, fromCover: true) },
                onCover: { [weak self] in self?.activate(itemID: id, fromCover: true) },
                onTitle: { [weak self] in self?.activate(itemID: id, fromCover: true) },
                onArtist: { [weak self] in self?.navigateArtist(itemID: id) },
                onAlbum: { [weak self] in self?.navigateAlbum(itemID: id) },
                menuProvider: { [weak self, record = item.record] in self?.menu(record: record) }
            )
        }

        private func activate(itemID: String, fromCover: Bool) {
            guard let record = item(for: itemID)?.record else { return }
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
            guard let record = item(for: itemID)?.record,
                  let id = record.artistId ?? record.artistRuns.first(where: { $0.id?.isEmpty == false })?.id,
                  !id.isEmpty else { return }
            parent.onNavigate(.artist(browseId: id))
        }

        private func navigateAlbum(itemID: String) {
            guard let record = item(for: itemID)?.record, let id = record.albumId, !id.isEmpty else { return }
            parent.onNavigate(.album(browseId: id))
        }

        private func navigateMore(sectionID: String) {
            guard let section = parent.sections.first(where: { $0.id == sectionID }),
                  let id = section.moreBrowseId else { return }
            if id.hasPrefix("MPRE") {
                parent.onNavigate(.album(browseId: id))
            } else if id.hasPrefix("UC") {
                parent.onNavigate(.artist(browseId: id))
            } else if !id.hasPrefix("FE") {
                parent.onNavigate(.playlist(browseId: id))
            }
        }

        private func menu(record: HomeItemRecord) -> NSMenu? {
            let factory = AppContextMenuFactory.shared
            let core = parent.player.rustCore
            switch record.kind {
            case "song":
                return factory.buildSongNSMenu(song: SongItemRecord(fromHomeItem: record), player: parent.player,
                                               router: parent.router, core: core, origin: .home)
            case "album":
                return factory.buildAlbumNSMenu(browseId: record.id, playlistId: nil, title: record.title,
                                                artist: record.subtitle, thumbnail: record.thumbnail, inLibrary: nil,
                                                origin: .home, player: parent.player, router: parent.router, core: core)
            case "artist":
                return factory.buildArtistNSMenu(channelId: record.id, name: record.title,
                                                 thumbnail: record.thumbnail, radioPlaylistId: nil, origin: .home,
                                                 player: parent.player, router: parent.router, core: core)
            default:
                return factory.buildPlaylistNSMenu(id: record.id, title: record.title, subtitle: record.subtitle,
                                                   thumbnail: record.thumbnail, origin: .home, player: parent.player,
                                                   router: parent.router, core: core)
            }
        }
    }
}

@MainActor
private final class HomeShelfScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            var ancestor = superview
            while let view = ancestor {
                if let outerScroll = view as? NSScrollView,
                   outerScroll.documentView is NSTableView {
                    outerScroll.scrollWheel(with: event)
                    return
                }
                ancestor = view.superview
            }
        }
        super.scrollWheel(with: event)
    }
}

@MainActor
private final class HomeShelfRowView: NSView, NSCollectionViewDataSource {
    static let identifier = NSUserInterfaceItemIdentifier("HomeShelfRow")

    private let header = HomeSectionHeaderView()
    private let scroll = HomeShelfScrollView()
    private let collection = HomeNativeCollectionView()
    private let flow = NSCollectionViewFlowLayout()
    private var section: HomeSectionPresentation?
    private var pendingHorizontalOffset: CGFloat?
    private var isApplyingSection = false
    private var onHorizontalOffset: ((CGFloat) -> Void)?
    private var onActivate: ((HomeItemPresentation) -> Void)?
    private var onConfigure: ((HomeCollectionItem, HomeItemPresentation) -> Void)?
    private weak var hoveredItem: HomeCollectionItem?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        addSubview(header)
        flow.scrollDirection = .horizontal
        flow.minimumInteritemSpacing = 1
        flow.minimumLineSpacing = 16
        flow.sectionInset = NSEdgeInsets(top: 0, left: 28, bottom: 0, right: 28)
        collection.collectionViewLayout = flow
        collection.backgroundColors = [.clear]
        collection.isSelectable = true
        collection.dataSource = self
        collection.register(HomeCollectionItem.self, forItemWithIdentifier: HomeCollectionItem.identifier)
        collection.onActivateSelection = { [weak self] indexPath in
            guard let self, let section = self.section,
                  section.items.indices.contains(indexPath.item) else { return }
            self.onActivate?(section.items[indexPath.item])
        }
        collection.onHoverPosition = { [weak self] point in self?.updateHover(at: point) }
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.documentView = collection
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(horizontalBoundsChanged(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func layout() {
        super.layout()
        header.frame = NSRect(x: 28, y: 0, width: max(0, bounds.width - 56), height: 46)
        let shelfHeight: CGFloat = section?.style == .compactSong ? 230 :
            (bounds.width < 760 ? 140 : 160) + HomeItemView.largeCardTextHeight
        scroll.frame = NSRect(x: 0, y: 46, width: bounds.width, height: shelfHeight)
        let itemSize = section?.style == .compactSong
            ? NSSize(width: bounds.width < 760 ? 286 : 330, height: 56)
            : NSSize(width: bounds.width < 760 ? 140 : 160, height: shelfHeight)
        if flow.itemSize != itemSize {
            flow.itemSize = itemSize
            flow.invalidateLayout()
        }
        if let pendingHorizontalOffset {
            self.pendingHorizontalOffset = nil
            scroll.contentView.scroll(to: NSPoint(x: pendingHorizontalOffset, y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            isApplyingSection = false
            onHorizontalOffset?(scroll.contentView.bounds.minX)
        }
    }

    func configure(
        section: HomeSectionPresentation,
        horizontalOffset: CGFloat,
        onHorizontalOffset: @escaping (CGFloat) -> Void,
        onMore: @escaping () -> Void,
        onActivate: @escaping (HomeItemPresentation) -> Void,
        onConfigure: @escaping (HomeCollectionItem, HomeItemPresentation) -> Void
    ) {
        let changed = self.section != section
        let changedIdentity = self.section?.id != section.id
        self.section = section
        self.onHorizontalOffset = onHorizontalOffset
        self.onActivate = onActivate
        self.onConfigure = onConfigure
        header.configure(title: section.title, showsMore: section.isNavigableMore,
                         showsArrows: section.items.count > 4,
                         previous: { [weak self] in self?.scrollShelf(direction: -1) },
                         next: { [weak self] in self?.scrollShelf(direction: 1) },
                         action: onMore)
        if changed {
            clearHover()
            isApplyingSection = true
            if changedIdentity {
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            pendingHorizontalOffset = horizontalOffset
            collection.reloadData()
            needsLayout = true
        }
    }

    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection sectionIndex: Int) -> Int {
        section?.items.count ?? 0
    }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: HomeCollectionItem.identifier, for: indexPath) as! HomeCollectionItem
        if let section, section.items.indices.contains(indexPath.item) {
            onConfigure?(cell, section.items[indexPath.item])
        }
        return cell
    }

    func updateVisiblePlayback(trackID: String?, isPlaying: Bool) {
        for path in collection.indexPathsForVisibleItems() {
            (collection.item(at: path) as? HomeCollectionItem)?.content.updatePlayback(
                currentTrackID: trackID, isPlaying: isPlaying
            )
        }
    }

    func clearHover() {
        hoveredItem?.content.setHovered(false, localPoint: nil)
        hoveredItem = nil
    }

    func updateHoverAtPointer() {
        guard let window else { clearHover(); return }
        let point = collection.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        updateHover(at: point)
    }

    private func updateHover(at point: NSPoint?) {
        var next: HomeCollectionItem?
        var localPoint: NSPoint?
        if let point, collection.visibleRect.contains(point),
           let path = collection.indexPathForItem(at: point),
           let cell = collection.item(at: path) as? HomeCollectionItem {
            next = cell
            localPoint = cell.view.convert(point, from: collection)
        }
        if hoveredItem !== next {
            clearHover()
            next?.content.setHovered(true, localPoint: localPoint)
            hoveredItem = next
        } else if let next, let localPoint {
            next.content.updateHoverLocation(localPoint)
        }
    }

    @objc private func horizontalBoundsChanged(_ notification: Notification) {
        guard section != nil, !isApplyingSection else { return }
        onHorizontalOffset?(scroll.contentView.bounds.minX)
        updateHoverAtPointer()
    }

    private func scrollShelf(direction: Int) {
        guard let section, !section.items.isEmpty else { return }
        let items = collection.indexPathsForVisibleItems().map(\.item)
        let step = section.style == .compactSong ? 4 : 1
        let anchor = direction > 0 ? (items.max() ?? 0) + step : max(0, (items.min() ?? 0) - step)
        let target = min(section.items.count - 1, anchor)
        collection.scrollToItems(at: [IndexPath(item: target, section: 0)],
                                 scrollPosition: direction > 0 ? .right : .left)
    }
}

@MainActor
private final class HomeLoadMoreRowView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("HomeLoadMoreRow")
    private let button = NSButton(title: "Cargar más recomendaciones", target: nil, action: nil)
    private var action: (() -> Void)?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(loadMore)
        addSubview(button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }
    override func layout() {
        super.layout()
        button.frame = NSRect(x: max(0, (bounds.width - 220) / 2), y: 14, width: 220, height: 32)
    }
    func configure(loading: Bool, action: @escaping () -> Void) {
        self.action = action
        button.title = loading ? "Cargando recomendaciones…" : "Cargar más recomendaciones"
        button.isEnabled = !loading
    }
    @objc private func loadMore() { action?() }
}
