import AppKit
import SwiftUI
import SideBCore

// MARK: - Native Track Table View (AppKit Bridge)

/// Representa una sección dentro de `NativeTrackTableView`, con un título opcional para encabezados nativos.
public struct TrackTableSection: Sendable, Equatable {
    public let id: String
    public let title: String?
    public let tracks: [SongItemRecord]

    public init(id: String = UUID().uuidString, title: String? = nil, tracks: [SongItemRecord]) {
        self.id = id
        self.title = title
        self.tracks = tracks
    }
}

enum TableRowItem: Equatable {
    case header(title: String, sectionIndex: Int)
    case track(track: SongItemRecord, overallIndex: Int, sectionIndex: Int, itemIndex: Int)
}

/// Componente universal de lista de canciones de ultra-alto rendimiento respaldado por `NSTableView` de AppKit.
/// - Soporte de secciones nativas con encabezados sticky/separadores sin overhead (`isGroupRow`).
/// - Reciclaje estricto de celdas (`makeView(withIdentifier:owner:)`): solo ~15 vistas físicas creadas en memoria RAM.
/// - Carga de imágenes desacoplada directamente en `NSImageView` sin mutar `@State` en SwiftUI ni saturar el hilo principal.
/// - Hover de fuente única de verdad (`hoveredRowIndex`): solo una fila puede estar resaltada a la vez, a 120 FPS.
/// - Soporte nativo para Drag & Drop (reordenamiento en la cola), botones Like/Dislike y cero scroll horizontal.
struct NativeTrackTableView: NSViewRepresentable {
    @Environment(\.sideBMenuContext) private var menuContext
    let sections: [TrackTableSection]
    let tracks: [SongItemRecord]
    let rowItems: [TableRowItem]
    let currentTrackVideoId: String?
    let isPlaying: Bool
    let playerViewModel: PlayerViewModel?
    let router: NavigationRouter?
    let rustCore: SideBCore?
    let hideAlbumColumn: Bool
    let showAlbumInSubtitle: Bool
    let isReorderable: Bool
    let rowHeight: CGFloat
    let likedVideoIds: Set<String>
    let onPlayTrack: (Int) -> Void
    let onLikeTrack: ((SongItemRecord) -> Void)?
    let onDislikeTrack: ((SongItemRecord) -> Void)?
    let playlistContext: (playlistId: String, isOwned: Bool)?
    let onRemoveTrackFromPlaylist: (@MainActor @Sendable (SongItemRecord) -> Void)?
    let menuOrigin: ((Int) -> MenuOrigin)?
    let onMoveTrack: ((Int, Int) -> Void)?
    let onNearBottom: (() -> Void)?
    let contentInsets: NSEdgeInsets

    /// Inicializador principal que soporta múltiples secciones con encabezados de fecha/categoría.
    init(
        sections: [TrackTableSection],
        currentTrackVideoId: String? = nil,
        isPlaying: Bool = false,
        playerViewModel: PlayerViewModel? = nil,
        router: NavigationRouter? = nil,
        rustCore: SideBCore? = nil,
        hideAlbumColumn: Bool = false,
        showAlbumInSubtitle: Bool = false,
        isReorderable: Bool = false,
        rowHeight: CGFloat = 52.0,
        likedVideoIds: Set<String> = [],
        playlistContext: (playlistId: String, isOwned: Bool)? = nil,
        menuOrigin: ((Int) -> MenuOrigin)? = nil,
        onPlayTrack: @escaping (Int) -> Void,
        onLikeTrack: ((SongItemRecord) -> Void)? = nil,
        onDislikeTrack: ((SongItemRecord) -> Void)? = nil,
        onRemoveTrackFromPlaylist: (@MainActor @Sendable (SongItemRecord) -> Void)? = nil,
        onMoveTrack: ((Int, Int) -> Void)? = nil,
        onNearBottom: (() -> Void)? = nil,
        contentInsets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 120, right: 0)
    ) {
        self.sections = sections
        var allTracks: [SongItemRecord] = []
        var items: [TableRowItem] = []
        for (sIdx, section) in sections.enumerated() {
            if let title = section.title, !title.isEmpty {
                items.append(.header(title: title, sectionIndex: sIdx))
            }
            for (tIdx, track) in section.tracks.enumerated() {
                let overallIdx = allTracks.count
                allTracks.append(track)
                items.append(.track(track: track, overallIndex: overallIdx, sectionIndex: sIdx, itemIndex: tIdx))
            }
        }
        self.tracks = allTracks
        self.rowItems = items
        self.currentTrackVideoId = currentTrackVideoId
        self.isPlaying = isPlaying
        self.playerViewModel = playerViewModel
        self.router = router
        self.rustCore = rustCore
        self.hideAlbumColumn = hideAlbumColumn
        self.showAlbumInSubtitle = showAlbumInSubtitle
        self.isReorderable = isReorderable
        self.rowHeight = rowHeight
        self.likedVideoIds = likedVideoIds
        self.playlistContext = playlistContext
        self.menuOrigin = menuOrigin
        self.onPlayTrack = onPlayTrack
        self.onLikeTrack = onLikeTrack
        self.onDislikeTrack = onDislikeTrack
        self.onRemoveTrackFromPlaylist = onRemoveTrackFromPlaylist
        self.onMoveTrack = onMoveTrack
        self.onNearBottom = onNearBottom
        self.contentInsets = contentInsets
    }

    /// Inicializador de conveniencia para listas planas continuas (Playlists, Álbumes, Búsqueda, Cola).
    init(
        tracks: [SongItemRecord],
        currentTrackVideoId: String? = nil,
        isPlaying: Bool = false,
        playerViewModel: PlayerViewModel? = nil,
        router: NavigationRouter? = nil,
        rustCore: SideBCore? = nil,
        hideAlbumColumn: Bool = false,
        showAlbumInSubtitle: Bool = false,
        isReorderable: Bool = false,
        rowHeight: CGFloat = 52.0,
        likedVideoIds: Set<String> = [],
        playlistContext: (playlistId: String, isOwned: Bool)? = nil,
        menuOrigin: ((Int) -> MenuOrigin)? = nil,
        onPlayTrack: @escaping (Int) -> Void,
        onLikeTrack: ((SongItemRecord) -> Void)? = nil,
        onDislikeTrack: ((SongItemRecord) -> Void)? = nil,
        onRemoveTrackFromPlaylist: (@MainActor @Sendable (SongItemRecord) -> Void)? = nil,
        onMoveTrack: ((Int, Int) -> Void)? = nil,
        onNearBottom: (() -> Void)? = nil,
        contentInsets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 120, right: 0)
    ) {
        self.init(
            sections: [TrackTableSection(title: nil, tracks: tracks)],
            currentTrackVideoId: currentTrackVideoId,
            isPlaying: isPlaying,
            playerViewModel: playerViewModel,
            router: router,
            rustCore: rustCore,
            hideAlbumColumn: hideAlbumColumn,
            showAlbumInSubtitle: showAlbumInSubtitle,
            isReorderable: isReorderable,
            rowHeight: rowHeight,
            likedVideoIds: likedVideoIds,
            playlistContext: playlistContext,
            menuOrigin: menuOrigin,
            onPlayTrack: onPlayTrack,
            onLikeTrack: onLikeTrack,
            onDislikeTrack: onDislikeTrack,
            onRemoveTrackFromPlaylist: onRemoveTrackFromPlaylist,
            onMoveTrack: onMoveTrack,
            onNearBottom: onNearBottom,
            contentInsets: contentInsets
        )
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .allowed
        scrollView.autoresizingMask = [.width, .height]
        scrollView.translatesAutoresizingMaskIntoConstraints = true

        let tableView = NativeTrackTableViewInternal()
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowHeight = rowHeight
        tableView.usesAutomaticRowHeights = false
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.wantsLayer = true
        tableView.layer?.masksToBounds = false
        tableView.autoresizingMask = [.width]
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        // Configuración de Drag & Drop para reordenamiento si está habilitado
        if isReorderable {
            tableView.registerForDraggedTypes([NSPasteboard.PasteboardType("com.fefucho.sideb.trackRow")])
            tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        }

        // Columna única a ancho completo
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TrackColumn"))
        column.minWidth = 200
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.target = context.coordinator
        tableView.coordinator = context.coordinator
        tableView.doubleAction = #selector(Coordinator.onTableRowDoubleClicked(_:))
        tableView.action = #selector(Coordinator.onTableRowClicked(_:))

        scrollView.documentView = tableView
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = contentInsets
        context.coordinator.tableView = tableView

        // Notificación de scroll para actualizar el hover con precisión milimétrica a 120 FPS
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.onClipViewBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        tableView.reloadData()
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        let oldParent = context.coordinator.parent
        let rowsChanged = oldParent.rowItems.count != rowItems.count ||
                          oldParent.rowItems != rowItems
        if rowsChanged,
           let selected = menuContext?.selectedSong,
           oldParent.tracks.contains(where: { $0.videoId == selected.videoId }),
           !tracks.contains(where: { $0.videoId == selected.videoId }) {
            menuContext?.clearSelection()
        }
        let activeTrackChanged = oldParent.currentTrackVideoId != currentTrackVideoId
        let isPlayingChanged = oldParent.isPlaying != isPlaying
        let likedChanged = oldParent.likedVideoIds != likedVideoIds
        let rowHeightChanged = oldParent.rowHeight != rowHeight

        context.coordinator.update(parent: self)
        nsView.contentInsets = contentInsets

        if let tableView = nsView.documentView as? NativeTrackTableViewInternal {
            if rowHeightChanged {
                tableView.rowHeight = rowHeight
            }

            // Sincronizar columna para bloqueo total de scroll horizontal
            if let column = tableView.tableColumns.first {
                let targetWidth = nsView.contentView.bounds.width
                if targetWidth > 0 && abs(column.width - targetWidth) > 1 {
                    column.width = targetWidth
                }
            }

            if rowsChanged || likedChanged || rowHeightChanged {
                tableView.reloadData()
            } else if activeTrackChanged || isPlayingChanged {
                tableView.enumerateAvailableRowViews { rowView, row in
                    guard row < self.rowItems.count else { return }
                    if case .track(let track, let overallIndex, _, let itemIndex) = self.rowItems[row] {
                        if let trackRow = rowView as? NativeTrackRowView {
                            trackRow.isCurrentTrack = (track.videoId == self.currentTrackVideoId)
                        }
                        if rowView.numberOfColumns > 0, let cellView = rowView.view(atColumn: 0) as? NativeTrackCellView {
                            let isCurrent = (track.videoId == self.currentTrackVideoId)
                            let isLiked = self.likedVideoIds.contains(track.videoId)
                            let displayIndex = (self.sections.count > 1 && self.sections.contains(where: { $0.title != nil })) ? itemIndex : overallIndex
                            cellView.configure(
                                track: track,
                                index: displayIndex,
                                isCurrentTrack: isCurrent,
                                isPlaying: isCurrent && self.isPlaying,
                                isLiked: isLiked,
                                hideAlbum: self.hideAlbumColumn,
                                showAlbumInSubtitle: self.showAlbumInSubtitle,
                                isReorderable: self.isReorderable,
                                rowHeight: self.rowHeight
                            )
                        }
                    }
                }
            }
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? 800,
            height: proposal.height ?? 600
        )
    }

    // MARK: - Coordinator

    @MainActor
    public class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NativeTrackTableView
        weak var tableView: NativeTrackTableViewInternal?

        init(parent: NativeTrackTableView) {
            self.parent = parent
        }

        func update(parent: NativeTrackTableView) {
            self.parent = parent
        }

        @objc func onClipViewBoundsChanged(_ notification: Notification) {
            tableView?.updateHover()
        }

        // MARK: - NSTableViewDataSource

        public func numberOfRows(in tableView: NSTableView) -> Int {
            parent.rowItems.count
        }

        // MARK: - NSTableViewDelegate

        public func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            guard row >= 0 && row < parent.rowItems.count else { return false }
            if case .header = parent.rowItems[row] { return true }
            return false
        }

        public func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            guard row >= 0 && row < parent.rowItems.count else { return false }
            if case .header = parent.rowItems[row] { return false }
            return true
        }

        public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard row >= 0 && row < parent.rowItems.count else { return parent.rowHeight }
            switch parent.rowItems[row] {
            case .header:
                return 38.0
            case .track:
                return parent.rowHeight
            }
        }

        public func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView, tableView.selectedRow >= 0,
                  tableView.selectedRow < parent.rowItems.count else { return }
            if case .track(let track, _, _, _) = parent.rowItems[tableView.selectedRow] {
                parent.menuContext?.select(track)
            }
        }

        public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard row >= 0 && row < parent.rowItems.count else { return nil }
            switch parent.rowItems[row] {
            case .header:
                let identifier = NSUserInterfaceItemIdentifier("NativeTrackGroupRowView")
                var rowView = tableView.makeView(withIdentifier: identifier, owner: self) as? NativeTrackGroupRowView
                if rowView == nil {
                    rowView = NativeTrackGroupRowView()
                    rowView?.identifier = identifier
                }
                return rowView

            case .track(let track, _, _, _):
                let identifier = NSUserInterfaceItemIdentifier("NativeTrackRowView")
                var rowView = tableView.makeView(withIdentifier: identifier, owner: self) as? NativeTrackRowView
                if rowView == nil {
                    rowView = NativeTrackRowView()
                    rowView?.identifier = identifier
                }
                rowView?.isCurrentTrack = (track.videoId == parent.currentTrackVideoId)
                if let customTable = tableView as? NativeTrackTableViewInternal {
                    rowView?.isHovered = (row == customTable.hoveredRowIndex)
                } else {
                    rowView?.isHovered = false
                }
                return rowView
            }
        }

        public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row >= 0 && row < parent.rowItems.count else { return nil }
            switch parent.rowItems[row] {
            case .header(let title, _):
                let identifier = NSUserInterfaceItemIdentifier("NativeTrackSectionHeaderCellView")
                var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NativeTrackSectionHeaderCellView
                if cell == nil {
                    cell = NativeTrackSectionHeaderCellView()
                    cell?.identifier = identifier
                }
                cell?.configure(title: title)
                return cell

            case .track(let track, let overallIndex, _, let itemIndex):
                let identifier = NSUserInterfaceItemIdentifier("NativeTrackCellView")
                var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NativeTrackCellView
                if cell == nil {
                    cell = NativeTrackCellView()
                    cell?.identifier = identifier
                }

                let isCurrent = (track.videoId == parent.currentTrackVideoId)
                let isLiked = parent.likedVideoIds.contains(track.videoId)
                let isHovered = (tableView as? NativeTrackTableViewInternal)?.hoveredRowIndex == row

                cell?.onLike = { [weak self] t in
                    self?.parent.onLikeTrack?(t)
                }
                cell?.onDislike = { [weak self] t in
                    self?.parent.onDislikeTrack?(t)
                }

                let displayIndex = (parent.sections.count > 1 && parent.sections.contains(where: { $0.title != nil })) ? itemIndex : overallIndex

                cell?.configure(
                    track: track,
                    index: displayIndex,
                    isCurrentTrack: isCurrent,
                    isPlaying: isCurrent && parent.isPlaying,
                    isLiked: isLiked,
                    hideAlbum: parent.hideAlbumColumn,
                    showAlbumInSubtitle: parent.showAlbumInSubtitle,
                    isReorderable: parent.isReorderable,
                    rowHeight: parent.rowHeight
                )
                cell?.updateHover(isHovered: isHovered)

                // Centinela de paginación predictiva (15 items antes del final)
                if overallIndex >= parent.tracks.count - 15 {
                    parent.onNearBottom?()
                }

                return cell
            }
        }

        // MARK: - Drag & Drop (Reordenamiento de Cola)

        public func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard parent.isReorderable, row >= 0 && row < parent.rowItems.count else { return nil }
            guard case .track(_, let overallIndex, _, _) = parent.rowItems[row] else { return nil }
            let item = NSPasteboardItem()
            item.setString("\(overallIndex)", forType: NSPasteboard.PasteboardType("com.fefucho.sideb.trackRow"))
            return item
        }

        public func tableView(
            _ tableView: NSTableView,
            validateDrop info: any NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard parent.isReorderable, parent.onMoveTrack != nil else { return [] }
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }

        public func tableView(
            _ tableView: NSTableView,
            acceptDrop info: any NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            guard parent.isReorderable,
                  let pasteboard = info.draggingPasteboard.pasteboardItems?.first,
                  let str = pasteboard.string(forType: NSPasteboard.PasteboardType("com.fefucho.sideb.trackRow")),
                  let sourceRow = Int(str) else {
                return false
            }

            var destRow = row
            if sourceRow < destRow {
                destRow -= 1
            }
            guard sourceRow != destRow, sourceRow >= 0, sourceRow < parent.tracks.count,
                  destRow >= 0, destRow < parent.tracks.count else {
                return false
            }

            parent.onMoveTrack?(sourceRow, destRow)
            return true
        }

        // MARK: - Context Menu

        func menuForRow(_ row: Int) -> NSMenu? {
            guard row >= 0 && row < parent.rowItems.count else { return nil }
            guard case .track(let track, let overallIndex, _, _) = parent.rowItems[row] else { return nil }
            parent.menuContext?.select(track)
            guard let player = parent.playerViewModel else { return nil }
            let origin = parent.menuOrigin?(overallIndex)
            return AppContextMenuFactory.shared.buildSongNSMenu(
                song: track,
                player: player,
                router: parent.router,
                core: parent.rustCore,
                origin: origin,
                playlistContext: parent.playlistContext,
                onRemoveFromPlaylist: parent.onRemoveTrackFromPlaylist
            )
        }

        func isHeaderRow(_ row: Int) -> Bool {
            guard row >= 0 && row < parent.rowItems.count else { return false }
            if case .header = parent.rowItems[row] { return true }
            return false
        }

        // MARK: - Actions

        @objc func onTableRowDoubleClicked(_ sender: NSTableView) {
            let clickedRow = sender.clickedRow
            guard clickedRow >= 0 && clickedRow < parent.rowItems.count else { return }
            if case .track(let track, let overallIndex, _, _) = parent.rowItems[clickedRow] {
                parent.menuContext?.select(track)
                parent.onPlayTrack(overallIndex)
            }
        }

        @objc func onTableRowClicked(_ sender: NSTableView) {
            let clickedRow = sender.clickedRow
            guard clickedRow >= 0 && clickedRow < parent.rowItems.count else { return }
            if case .track(let track, let overallIndex, _, _) = parent.rowItems[clickedRow] {
                parent.menuContext?.select(track)
                parent.onPlayTrack(overallIndex)
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

// MARK: - Native Track Table View Internal (Single Source of Truth for Hover)

final class NativeTrackTableViewInternal: NSTableView {
    weak var coordinator: NativeTrackTableView.Coordinator?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let r = row(at: point)
        guard r >= 0, let coordinator = self.coordinator, !coordinator.isHeaderRow(r) else {
            return super.menu(for: event)
        }
        hoveredRowIndex = r
        return coordinator.menuForRow(r)
    }

    var hoveredRowIndex: Int = -1 {
        didSet {
            guard oldValue != hoveredRowIndex else { return }
            if oldValue >= 0 && oldValue < numberOfRows, let oldRow = rowView(atRow: oldValue, makeIfNecessary: false) as? NativeTrackRowView {
                oldRow.isHovered = false
            }
            if hoveredRowIndex >= 0 && hoveredRowIndex < numberOfRows, let newRow = rowView(atRow: hoveredRowIndex, makeIfNecessary: false) as? NativeTrackRowView {
                newRow.isHovered = true
            }
        }
    }

    override func reloadData() {
        if hoveredRowIndex >= numberOfRows {
            hoveredRowIndex = -1
        }
        super.reloadData()
        updateHover()
    }

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredRowIndex = -1
    }

    func updateHover(at locationInWindow: NSPoint? = nil) {
        guard let window = self.window else {
            hoveredRowIndex = -1
            return
        }
        let loc = locationInWindow ?? window.mouseLocationOutsideOfEventStream
        let pointInTable = convert(loc, from: nil)
        if bounds.contains(pointInTable) {
            let r = row(at: pointInTable)
            if r >= 0 && r < numberOfRows {
                if let coordinator = self.coordinator, coordinator.isHeaderRow(r) {
                    hoveredRowIndex = -1
                } else {
                    hoveredRowIndex = r
                }
            } else {
                hoveredRowIndex = -1
            }
        } else {
            hoveredRowIndex = -1
        }
    }
}

// MARK: - Native Track Section Header & Group Row Views

final class NativeTrackGroupRowView: NSTableRowView {
    override var isOpaque: Bool { false }

    override func drawBackground(in dirtyRect: NSRect) {
        // Fondo transparente para grupo nativo
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // Encabezados no seleccionables
    }
}

final class NativeTrackSectionHeaderCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let dividerLine = NSBox()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.stringValue = ""
    }

    private func setupViews() {
        wantsLayer = true

        titleLabel.font = .systemFont(ofSize: 11.5, weight: .bold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        dividerLine.boxType = .separator
        dividerLine.alphaValue = 0.15
        dividerLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dividerLine)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            dividerLine.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
            dividerLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            dividerLine.centerYAnchor.constraint(equalTo: centerYAnchor),
            dividerLine.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    func configure(title: String) {
        titleLabel.stringValue = title.uppercased()
    }
}

// MARK: - Native Track Row View (Zero-Desync Hover)

final class NativeTrackRowView: NSTableRowView {
    var isCurrentTrack: Bool = false {
        didSet {
            if oldValue != isCurrentTrack {
                needsDisplay = true
            }
        }
    }

    var isHovered: Bool = false {
        didSet {
            guard oldValue != isHovered else { return }
            needsDisplay = true
            if numberOfColumns > 0, let cell = view(atColumn: 0) as? NativeTrackCellView {
                cell.updateHover(isHovered: isHovered)
            }
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let rect = bounds.insetBy(dx: 10, dy: 1)
        let cornerRadius: CGFloat = bounds.height <= 48.0 ? 6 : (bounds.height >= 60.0 ? 8 : 7)
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        if isCurrentTrack {
            context.addPath(path)
            context.setFillColor(NSColor.sidebActiveRowBackground.cgColor)
            context.fillPath()

            context.addPath(path)
            context.setStrokeColor(NSColor.sidebActiveRowBorder.cgColor)
            context.setLineWidth(AppTheme.cardBorderWidth)
            context.strokePath()
        } else if isHovered {
            context.addPath(path)
            context.setFillColor(NSColor.white.withAlphaComponent(0.045).cgColor)
            context.fillPath()
        }
    }
}

// MARK: - Native Track Cell View (Pure AppKit Cell Recycling)

final class NativeTrackCellView: NSTableCellView {
    private let indexLabel = NSTextField(labelWithString: "")
    private let playingIconView = NSImageView()
    private let artworkImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let albumLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let reorderHandleImageView = NSImageView()
    
    private let likeButton = NSButton()
    private let dislikeButton = NSButton()

    private var currentVideoId: String?
    private var imageFetchTask: Task<Void, Never>?
    private var boundTrack: SongItemRecord?
    private var isReorderable: Bool = false
    private var isLiked: Bool = false

    var onLike: ((SongItemRecord) -> Void)?
    var onDislike: ((SongItemRecord) -> Void)?

    private var artworkWidthConstraint: NSLayoutConstraint?
    private var artworkHeightConstraint: NSLayoutConstraint?
    private var likeButtonWidthConstraint: NSLayoutConstraint?
    private var likeButtonHeightConstraint: NSLayoutConstraint?
    private var dislikeButtonWidthConstraint: NSLayoutConstraint?
    private var dislikeButtonHeightConstraint: NSLayoutConstraint?
    private var reorderHandleWidthConstraint: NSLayoutConstraint?
    private var reorderHandleHeightConstraint: NSLayoutConstraint?
    private var playingIconWidthConstraint: NSLayoutConstraint?
    private var playingIconHeightConstraint: NSLayoutConstraint?
    private var titleTrailingWithAlbum: NSLayoutConstraint?
    private var titleTrailingNoAlbum: NSLayoutConstraint?
    private var subtitleTrailingWithAlbum: NSLayoutConstraint?
    private var subtitleTrailingNoAlbum: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageFetchTask?.cancel()
        imageFetchTask = nil
        currentVideoId = nil
        boundTrack = nil
        artworkImageView.image = nil
        likeButton.alphaValue = 0.0
        dislikeButton.alphaValue = 0.0
        reorderHandleImageView.isHidden = true
        durationLabel.isHidden = false
    }

    private func setupViews() {
        wantsLayer = true

        // 1. Índice / Icono
        indexLabel.font = .systemFont(ofSize: 12, weight: .regular)
        indexLabel.textColor = .secondaryLabelColor
        indexLabel.alignment = .right
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indexLabel)

        playingIconView.imageScaling = .scaleProportionallyDown
        playingIconView.contentTintColor = .white
        playingIconView.translatesAutoresizingMaskIntoConstraints = false
        playingIconView.isHidden = true
        addSubview(playingIconView)

        let playW = playingIconView.widthAnchor.constraint(equalToConstant: 14)
        let playH = playingIconView.heightAnchor.constraint(equalToConstant: 14)
        self.playingIconWidthConstraint = playW
        self.playingIconHeightConstraint = playH

        // 2. Artwork (Dinámico: 36x36, 40x40 o 48x48)
        artworkImageView.wantsLayer = true
        artworkImageView.layer?.cornerRadius = 8
        artworkImageView.layer?.masksToBounds = true
        artworkImageView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        artworkImageView.imageScaling = .scaleProportionallyUpOrDown
        artworkImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(artworkImageView)

        // 3. Título y Subtítulo
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        // 4. Álbum (Columna separada opcional para vistas de Playlist/Álbum)
        albumLabel.font = .systemFont(ofSize: 12, weight: .regular)
        albumLabel.textColor = .secondaryLabelColor
        albumLabel.lineBreakMode = .byTruncatingTail
        albumLabel.maximumNumberOfLines = 1
        albumLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(albumLabel)

        // 5. Botones Interactivos Like & Dislike
        dislikeButton.bezelStyle = .regularSquare
        dislikeButton.isBordered = false
        dislikeButton.imagePosition = .imageOnly
        dislikeButton.imageScaling = .scaleProportionallyDown
        dislikeButton.image = NSImage(systemSymbolName: "hand.thumbsdown", accessibilityDescription: "No me gusta (quitar de la cola)")
        dislikeButton.contentTintColor = NSColor.white.withAlphaComponent(0.65)
        dislikeButton.alphaValue = 0.0
        dislikeButton.target = self
        dislikeButton.action = #selector(onDislikeClicked)
        dislikeButton.toolTip = "No me gusta (quitar de la cola)"
        dislikeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dislikeButton)

        let dislikeW = dislikeButton.widthAnchor.constraint(equalToConstant: 22)
        let dislikeH = dislikeButton.heightAnchor.constraint(equalToConstant: 22)
        self.dislikeButtonWidthConstraint = dislikeW
        self.dislikeButtonHeightConstraint = dislikeH

        likeButton.bezelStyle = .regularSquare
        likeButton.isBordered = false
        likeButton.imagePosition = .imageOnly
        likeButton.imageScaling = .scaleProportionallyDown
        likeButton.image = NSImage(systemSymbolName: "heart", accessibilityDescription: "Me gusta")
        likeButton.contentTintColor = NSColor.white.withAlphaComponent(0.65)
        likeButton.alphaValue = 0.0
        likeButton.target = self
        likeButton.action = #selector(onLikeClicked)
        likeButton.toolTip = "Me gusta"
        likeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(likeButton)

        let likeW = likeButton.widthAnchor.constraint(equalToConstant: 22)
        let likeH = likeButton.heightAnchor.constraint(equalToConstant: 22)
        self.likeButtonWidthConstraint = likeW
        self.likeButtonHeightConstraint = likeH

        // 6. Duración y Grip Handle de Reordenamiento
        durationLabel.font = .systemFont(ofSize: 12, weight: .regular)
        durationLabel.textColor = .tertiaryLabelColor
        durationLabel.alignment = .right
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(durationLabel)

        reorderHandleImageView.imageScaling = .scaleProportionallyDown
        reorderHandleImageView.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Arrastrar para reordenar")
        reorderHandleImageView.contentTintColor = NSColor.white.withAlphaComponent(0.45)
        reorderHandleImageView.translatesAutoresizingMaskIntoConstraints = false
        reorderHandleImageView.isHidden = true
        addSubview(reorderHandleImageView)

        let reorderW = reorderHandleImageView.widthAnchor.constraint(equalToConstant: 18)
        let reorderH = reorderHandleImageView.heightAnchor.constraint(equalToConstant: 16)
        self.reorderHandleWidthConstraint = reorderW
        self.reorderHandleHeightConstraint = reorderH

        // Constraints de tamaño de artwork
        let artW = artworkImageView.widthAnchor.constraint(equalToConstant: 48)
        let artH = artworkImageView.heightAnchor.constraint(equalToConstant: 48)
        self.artworkWidthConstraint = artW
        self.artworkHeightConstraint = artH

        // Constraints condicionales para cuando hay columna de álbum separada vs compacta
        let tWithAlbum = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: albumLabel.leadingAnchor, constant: -14)
        let tNoAlbum = titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: dislikeButton.leadingAnchor, constant: -12)
        let sWithAlbum = subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: albumLabel.leadingAnchor, constant: -14)
        let sNoAlbum = subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: dislikeButton.leadingAnchor, constant: -12)

        self.titleTrailingWithAlbum = tWithAlbum
        self.titleTrailingNoAlbum = tNoAlbum
        self.subtitleTrailingWithAlbum = sWithAlbum
        self.subtitleTrailingNoAlbum = sNoAlbum

        NSLayoutConstraint.activate([
            // Índice
            indexLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            indexLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            indexLabel.widthAnchor.constraint(equalToConstant: 24),

            playingIconView.centerXAnchor.constraint(equalTo: indexLabel.centerXAnchor),
            playingIconView.centerYAnchor.constraint(equalTo: indexLabel.centerYAnchor),
            playW,
            playH,

            // Artwork
            artworkImageView.leadingAnchor.constraint(equalTo: indexLabel.trailingAnchor, constant: 10),
            artworkImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            artW,
            artH,

            // Título
            titleLabel.leadingAnchor.constraint(equalTo: artworkImageView.trailingAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: -1.5),

            // Subtítulo (Artista • Álbum)
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 1.5),

            // Álbum separado (opcional)
            albumLabel.trailingAnchor.constraint(equalTo: dislikeButton.leadingAnchor, constant: -16),
            albumLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            albumLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 160),

            // Botón Dislike
            dislikeButton.trailingAnchor.constraint(equalTo: likeButton.leadingAnchor, constant: -6),
            dislikeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            dislikeW,
            dislikeH,

            // Botón Like
            likeButton.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -8),
            likeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            likeW,
            likeH,

            // Duración
            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 44),

            // Handle Reordenar (mismo centro que la duración)
            reorderHandleImageView.centerXAnchor.constraint(equalTo: durationLabel.centerXAnchor),
            reorderHandleImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            reorderW,
            reorderH,

            // Activación inicial sin álbum separado
            tNoAlbum,
            sNoAlbum
        ])
    }

    @objc private func onLikeClicked() {
        guard let track = boundTrack else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onLike?(track)
        }
    }

    @objc private func onDislikeClicked() {
        guard let track = boundTrack else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onDislike?(track)
        }
    }

    func updateHover(isHovered: Bool) {
        if isReorderable {
            durationLabel.isHidden = isHovered
            reorderHandleImageView.isHidden = !isHovered
        } else {
            durationLabel.isHidden = false
            reorderHandleImageView.isHidden = true
        }

        // Mostrar botones de like y dislike con opacidad suave en hover o si ya tiene like
        dislikeButton.alphaValue = isHovered ? 0.70 : 0.0
        likeButton.alphaValue = (isLiked || isHovered) ? 1.0 : 0.0
    }

    func configure(
        track: SongItemRecord,
        index: Int,
        isCurrentTrack: Bool,
        isPlaying: Bool,
        isLiked: Bool = false,
        hideAlbum: Bool = false,
        showAlbumInSubtitle: Bool = false,
        isReorderable: Bool = false,
        rowHeight: CGFloat = 52.0
    ) {
        self.boundTrack = track
        self.currentVideoId = track.videoId
        self.isReorderable = isReorderable
        self.isLiked = isLiked

        let isCompact = rowHeight <= 48.0
        let isLarge = rowHeight >= 60.0

        let titleFontSize: CGFloat = isCompact ? 13.0 : (isLarge ? 14.0 : 13.5)
        let subtitleFontSize: CGFloat = isCompact ? 11.5 : (isLarge ? 12.0 : 12.0)

        // 1. Estado de reproducción e índice
        if isCurrentTrack {
            indexLabel.isHidden = true
            playingIconView.isHidden = false
            let symbolName = isPlaying ? "speaker.wave.3.fill" : "speaker.fill"
            let iconPtSize: CGFloat = isCompact ? 11.5 : 13.0
            let iconConfig = NSImage.SymbolConfiguration(pointSize: iconPtSize, weight: .semibold)
            playingIconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(iconConfig)
            titleLabel.textColor = .labelColor
            titleLabel.font = .systemFont(ofSize: titleFontSize, weight: .semibold)
        } else {
            indexLabel.isHidden = false
            playingIconView.isHidden = true
            indexLabel.stringValue = "\(index + 1)"
            indexLabel.font = .systemFont(ofSize: subtitleFontSize, weight: .regular)
            titleLabel.textColor = .labelColor
            titleLabel.font = .systemFont(ofSize: titleFontSize, weight: .medium)
        }

        // 2. Metadatos
        titleLabel.stringValue = track.title

        if showAlbumInSubtitle, let album = track.displayAlbum, !album.isEmpty {
            subtitleLabel.stringValue = "\(track.displayArtist) • \(album)"
        } else {
            subtitleLabel.stringValue = track.displayArtist
        }
        subtitleLabel.font = .systemFont(ofSize: subtitleFontSize, weight: .regular)

        let usesSeparateAlbum = !hideAlbum && !showAlbumInSubtitle
        albumLabel.stringValue = usesSeparateAlbum ? (track.displayAlbum ?? "") : ""
        albumLabel.font = .systemFont(ofSize: subtitleFontSize, weight: .regular)
        albumLabel.isHidden = !usesSeparateAlbum

        if usesSeparateAlbum {
            titleTrailingNoAlbum?.isActive = false
            subtitleTrailingNoAlbum?.isActive = false
            titleTrailingWithAlbum?.isActive = true
            subtitleTrailingWithAlbum?.isActive = true
        } else {
            titleTrailingWithAlbum?.isActive = false
            subtitleTrailingWithAlbum?.isActive = false
            titleTrailingNoAlbum?.isActive = true
            subtitleTrailingNoAlbum?.isActive = true
        }

        durationLabel.stringValue = track.duration ?? ""
        durationLabel.font = .systemFont(ofSize: subtitleFontSize, weight: .regular)

        // 3. Botones Like & Dislike adaptativos
        let buttonSize: CGFloat = isCompact ? 18.0 : (isLarge ? 22.0 : 20.0)
        likeButtonWidthConstraint?.constant = buttonSize
        likeButtonHeightConstraint?.constant = buttonSize
        dislikeButtonWidthConstraint?.constant = buttonSize
        dislikeButtonHeightConstraint?.constant = buttonSize

        let buttonSymbolPtSize: CGFloat = isCompact ? 12.0 : (isLarge ? 14.0 : 13.0)
        let buttonSymbolConfig = NSImage.SymbolConfiguration(pointSize: buttonSymbolPtSize, weight: .regular)

        let heartSymbol = isLiked ? "heart.fill" : "heart"
        likeButton.image = NSImage(systemSymbolName: heartSymbol, accessibilityDescription: "Me gusta")?.withSymbolConfiguration(buttonSymbolConfig)
        likeButton.contentTintColor = isLiked ? .white : NSColor.white.withAlphaComponent(0.65)
        likeButton.alphaValue = isLiked ? 1.0 : 0.0

        dislikeButton.image = NSImage(systemSymbolName: "hand.thumbsdown", accessibilityDescription: "No me gusta")?.withSymbolConfiguration(buttonSymbolConfig)
        dislikeButton.contentTintColor = NSColor.white.withAlphaComponent(0.65)
        dislikeButton.alphaValue = 0.0

        // Handle de reordenar
        let handleW: CGFloat = isCompact ? 16.0 : 18.0
        let handleH: CGFloat = isCompact ? 14.0 : 16.0
        reorderHandleWidthConstraint?.constant = handleW
        reorderHandleHeightConstraint?.constant = handleH
        let handleConfig = NSImage.SymbolConfiguration(pointSize: isCompact ? 12.0 : 13.5, weight: .regular)
        reorderHandleImageView.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Arrastrar para reordenar")?.withSymbolConfiguration(handleConfig)

        // Icono de reproducción
        let playIconSize: CGFloat = isCompact ? 12.0 : 14.0
        playingIconWidthConstraint?.constant = playIconSize
        playingIconHeightConstraint?.constant = playIconSize

        // 4. Adaptación de tamaño de carátula según altura de fila
        let artSize: CGFloat = isLarge ? 48.0 : (isCompact ? 36.0 : 40.0)
        artworkWidthConstraint?.constant = artSize
        artworkHeightConstraint?.constant = artSize
        artworkImageView.layer?.cornerRadius = isLarge ? 8 : 6

        // 5. Estado inicial de hover
        durationLabel.isHidden = false
        reorderHandleImageView.isHidden = true

        // 6. Miniatura Desacoplada (0ms de impacto en SwiftUI)
        loadThumbnail(for: track, targetSize: CGSize(width: artSize, height: artSize))
    }

    private func loadThumbnail(for track: SongItemRecord, targetSize: CGSize) {
        guard let thumbUrlString = track.thumbnail,
              let url = ImageURLHelper.optimizedThumbnailURL(from: thumbUrlString, targetPixelSize: Int(targetSize.width * 2))
        else {
            artworkImageView.image = nil
            return
        }

        // Fast-path en RAM: lectura sincrónica de memoria sin esperas ni tareas
        if let cached = ImageCache.shared.imageFromMemoryCache(for: url, targetSize: targetSize) {
            artworkImageView.image = cached
            return
        }

        // Carga en segundo plano fuera de SwiftUI
        let expectedVideoId = track.videoId
        imageFetchTask?.cancel()
        imageFetchTask = Task(priority: .utility) { [weak self] in
            let loaded = await ImageCache.shared.image(for: url, targetSize: targetSize)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self, self.currentVideoId == expectedVideoId else { return }
                self.artworkImageView.image = loaded
            }
        }
    }
}
