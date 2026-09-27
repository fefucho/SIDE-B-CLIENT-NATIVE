import SwiftUI
import AppKit
import SideBCore

struct GeniusPanelView: View {
    @Bindable var model: GeniusViewModel
    @State private var section: Section = .lyrics
    @State private var showingCandidates = false
    @State private var manualQuery = ""
    @State private var lyricPopoverAnchorRect: CGRect = .zero
    @State private var isShowingLyricPopover = false
    @AppStorage("genius_show_debug_controls") private var showsDebugControls = false

    private enum Section: String, CaseIterable {
        case lyrics = "Letras"
        case story = "Información"
        case annotations = "Anotaciones"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsDebugControls {
                debugControls
            }

            if let song = model.resolution?.song, !showingCandidates {
                Group {
                    switch section {
                    case .lyrics: lyricContent
                    case .story: storyContent(song)
                    case .annotations: annotationContent
                    }
                }
                .overlay(alignment: .topTrailing) { optionsMenu }
            } else {
                candidateContent
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { model.ensureNow() }
    }

    private var optionsMenu: some View {
        Menu {
            if model.resolution?.song != nil {
                Button("Letras", systemImage: section == .lyrics ? "checkmark" : "text.alignleft") {
                    showingCandidates = false
                    section = .lyrics
                }
                Button("Información", systemImage: section == .story ? "checkmark" : "info.circle") {
                    showingCandidates = false
                    section = .story
                }
                Button("Anotaciones", systemImage: section == .annotations ? "checkmark" : "text.bubble") {
                    showingCandidates = false
                    section = .annotations
                }
                Divider()
                Button("Cambiar coincidencia…", systemImage: "magnifyingglass") {
                    showingCandidates = true
                    if manualQuery.isEmpty, let song = model.resolution?.song {
                        manualQuery = "\(song.title) \(song.artist)"
                    }
                }
                if let urlText = model.resolution?.song?.url, let url = URL(string: urlText) {
                    Link("Ver en Genius", destination: url)
                }
            }
            Button("Actualizar datos", systemImage: "arrow.clockwise") { model.refresh() }
            Divider()
            Toggle("Buscar automáticamente al reproducir", isOn: automaticFetchBinding)
            Toggle("Mostrar controles de diagnóstico", isOn: $showsDebugControls)
        } label: {
            SideBEllipsisLabel()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Opciones de Genius")
        .accessibilityLabel("Opciones de Genius")
    }

    private var automaticFetchBinding: Binding<Bool> {
        Binding(
            get: { model.automaticFetchEnabled },
            set: { model.setAutomaticFetchEnabled($0) }
        )
    }

    private var debugControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Diagnóstico de Genius")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(String(describing: model.phase))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Toggle("Buscar automáticamente al reproducir", isOn: automaticFetchBinding)
                .font(.caption)
                .toggleStyle(.checkbox)
            Picker("Información de Genius", selection: $section) {
                ForEach(Section.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private var candidateContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    switch model.phase {
                    case .loading:
                        Text("Buscando en Genius").font(.headline)
                    case .ambiguous:
                        Text("Varias versiones posibles").font(.headline)
                        Text("Elegí la que corresponde a esta pista.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .notFound:
                        Text("Sin coincidencia segura").font(.headline)
                        Text("Probá otra búsqueda o guardá la pista para revisarla después.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .error:
                        Text("Genius no está disponible").font(.headline)
                        Text("Podés intentar de nuevo más tarde.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    default:
                        Text("Buscar otra versión").font(.headline)
                    }
                }
                Spacer(minLength: 0)
                optionsMenu
            }

            if showingCandidates, model.resolution?.song != nil {
                Button("Volver a las letras") { showingCandidates = false }
                    .buttonStyle(.plain)
                    .font(.caption)
            }

            if model.phase == .loading {
                ProgressView("Buscando información en Genius...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 10) {
                    TextField("Título y artista", text: $manualQuery)
                        .onSubmit { model.search(manualQuery) }
                    Button("Buscar") { model.search(manualQuery) }
                        .disabled(manualQuery.trimmingCharacters(in: .whitespaces).count < 2 || model.isSearching)
                }
                if model.isSearching { ProgressView().controlSize(.small) }

                if model.phase == .ambiguous || model.phase == .notFound {
                    Button {
                        model.reportCurrentMiss()
                    } label: {
                        Label(
                            model.missReportSaved ? "Guardada para revisar" : "Guardar esta pista para revisar",
                            systemImage: model.missReportSaved ? "checkmark.circle.fill" : "tray.and.arrow.down"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isReportingMiss || model.missReportSaved)
                    if let reportError = model.missReportError {
                        Text(reportError).font(.caption).foregroundStyle(.orange)
                    }
                }

                let candidates = model.searchResults.isEmpty ? (model.resolution?.candidates ?? []) : model.searchResults
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(candidates, id: \.id) { candidate in
                            Button {
                                model.choose(candidate)
                                showingCandidates = false
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.title).font(.subheadline.weight(.medium))
                                    Text(candidate.artist).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Usar esta canción de Genius para la pista actual")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var lyricContent: some View {
        Group {
            if model.isLoadingLyrics && model.lyrics.isEmpty {
                ProgressView("Cargando letras de Genius...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.isLoadingLyrics && model.lyrics.isEmpty {
                Text("No hay letras de Genius disponibles para esta canción.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeniusLyricsTextView(
                    lyrics: model.lyrics,
                    selectedReferentId: model.selectedAnnotation?.referentId ?? model.selectedAnnotation?.id,
                    isScrollLocked: (isShowingLyricPopover && model.selectedAnnotation != nil),
                    onSelectAnnotation: { id, rect in
                        if let annotation = model.annotation(for: id) {
                            model.selectedAnnotation = annotation
                            lyricPopoverAnchorRect = rect
                            isShowingLyricPopover = true
                        }
                    }
                )
                .popover(
                    isPresented: Binding(
                        get: { isShowingLyricPopover && model.selectedAnnotation != nil },
                        set: { if !$0 { isShowingLyricPopover = false; model.selectedAnnotation = nil } }
                    ),
                    attachmentAnchor: lyricPopoverAnchorRect == .zero ? .rect(.bounds) : .rect(.rect(lyricPopoverAnchorRect)),
                    arrowEdge: .trailing
                ) {
                    if let annotation = model.selectedAnnotation {
                        annotationBubble(annotation)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func storyContent(_ song: GeniusSongRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(song.title).font(.title3.weight(.semibold))
                Text(song.artist).foregroundStyle(.secondary)
                if let date = song.releaseDate, !date.isEmpty {
                    Label(date, systemImage: "calendar").font(.caption)
                }
                if let description = song.description, !description.isEmpty {
                    Text(description).textSelection(.enabled)
                } else {
                    Text("Genius no tiene descripción para esta canción.")
                        .foregroundStyle(.secondary)
                }
                if !song.producers.isEmpty { creditRow("Producción", names: song.producers) }
                if !song.writers.isEmpty { creditRow("Composición", names: song.writers) }
                ForEach(Array(song.performances.enumerated()), id: \.offset) { _, performance in
                    creditRow(performance.label, names: performance.artists)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func creditRow(_ title: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(names.joined(separator: ", ")).font(.subheadline)
        }
    }

    private var annotationContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if model.isLoadingAnnotations && model.annotations.isEmpty {
                    ProgressView("Cargando anotaciones...")
                }
                ForEach(model.annotations, id: \.id) { annotation in
                    Button {
                        isShowingLyricPopover = false
                        model.selectedAnnotation = annotation
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(annotation.fragment).font(.subheadline.weight(.medium)).lineLimit(2)
                            Text(annotation.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: Binding(
                        get: { !isShowingLyricPopover && model.selectedAnnotation?.id == annotation.id },
                        set: { if !$0 { model.selectedAnnotation = nil } }
                    ), arrowEdge: .trailing) {
                        annotationBubble(annotation)
                    }
                }
                if model.nextAnnotationPage != nil {
                    Button("Cargar más anotaciones") { model.loadMoreAnnotations() }
                        .disabled(model.isLoadingAnnotations)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func annotationBubble(_ annotation: GeniusAnnotationRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                if annotation.verified {
                    Label("Anotación verificada", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                } else if let author = annotation.author, !author.isEmpty {
                    Label("Por \(author)", systemImage: "note.text")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Label("Anotación", systemImage: "note.text")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    model.selectedAnnotation = nil
                    isShowingLyricPopover = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Cerrar anotación")
            }
            .padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(styledAnnotationBody(annotation))
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .tint(.white)
                        .textSelection(.enabled)
                    ForEach(annotation.imageUrls, id: \.self) { imageURL in
                        if let url = URL(string: imageURL), url.scheme == "https" {
                            CachedAsyncImage(url: url, targetSize: CGSize(width: 640, height: 440)) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(Color.white.opacity(0.07))
                                    .frame(height: 100)
                            }
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                    }
                    if let urlText = annotation.shareUrl, let url = URL(string: urlText) {
                        Link("Abrir anotación en Genius", destination: url)
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(minWidth: 300, idealWidth: 400, maxWidth: 480, maxHeight: 520)
    }

    private func styledAnnotationBody(_ annotation: GeniusAnnotationRecord) -> AttributedString {
        var result = AttributedString()
        let spans = annotation.bodySpans.isEmpty
            ? [GeniusAnnotationSpanRecord(text: annotation.body, url: nil)]
            : annotation.bodySpans
        for span in spans {
            var piece = AttributedString(span.text)
            if let rawURL = span.url, let url = URL(string: rawURL),
               url.scheme == "https" || url.scheme == "http" {
                piece.link = url
                piece.foregroundColor = .white
                piece.underlineStyle = .single
            }
            result += piece
        }
        return result
    }
}

// MARK: - Native Lyrics View with Live Annotation Hover and Precise Boundaries

struct GeniusLyricsTextView: NSViewRepresentable {
    let lyrics: [GeniusLyricLineRecord]
    let selectedReferentId: Int64?
    let isScrollLocked: Bool
    let onSelectAnnotation: (Int64, CGRect) -> Void

    func makeNSView(context: Context) -> GeniusLyricsScrollView {
        let scrollView = GeniusLyricsScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let textView = GeniusLyricsNSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 2

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        textView.onSelectAnnotation = onSelectAnnotation
        context.coordinator.update(lyrics: lyrics, selectedReferentId: selectedReferentId, isScrollLocked: isScrollLocked)

        return scrollView
    }

    func updateNSView(_ scrollView: GeniusLyricsScrollView, context: Context) {
        guard let textView = scrollView.documentView as? GeniusLyricsNSTextView else { return }
        textView.onSelectAnnotation = onSelectAnnotation
        context.coordinator.update(lyrics: lyrics, selectedReferentId: selectedReferentId, isScrollLocked: isScrollLocked)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        weak var textView: GeniusLyricsNSTextView?
        weak var scrollView: GeniusLyricsScrollView?
        private var lastLyricsHash: Int = 0
        private var lastSelectedReferentId: Int64?
        private var lastScrollLocked: Bool = false

        func update(lyrics: [GeniusLyricLineRecord], selectedReferentId: Int64?, isScrollLocked: Bool) {
            guard let textView, let scrollView else { return }

            if isScrollLocked != lastScrollLocked {
                lastScrollLocked = isScrollLocked
                scrollView.isScrollLocked = isScrollLocked
                textView.isScrollLocked = isScrollLocked
                scrollView.verticalScroller?.isEnabled = !isScrollLocked
            }

            var hasher = Hasher()
            for line in lyrics {
                hasher.combine(line.text)
                hasher.combine(line.referentId)
                hasher.combine(line.isHeader)
                for span in line.spans {
                    hasher.combine(span.text)
                    hasher.combine(span.referentId)
                }
            }
            let lyricsHash = hasher.finalize()

            if lyricsHash != lastLyricsHash {
                lastLyricsHash = lyricsHash
                lastSelectedReferentId = selectedReferentId
                textView.setLyrics(lyrics, selectedReferentId: selectedReferentId)
            } else if selectedReferentId != lastSelectedReferentId {
                lastSelectedReferentId = selectedReferentId
                textView.updateSelectedReferent(selectedReferentId)
            }
        }
    }
}

@MainActor
final class GeniusLyricsScrollView: NSScrollView {
    var isScrollLocked: Bool = false

    override func scrollWheel(with event: NSEvent) {
        if isScrollLocked {
            return
        }
        super.scrollWheel(with: event)
    }
}

@MainActor
final class GeniusLyricsNSTextView: NSTextView {
    var onSelectAnnotation: ((Int64, CGRect) -> Void)?
    var isScrollLocked: Bool = false
    private(set) var hoveredReferentId: Int64?
    private(set) var selectedReferentId: Int64?
    private var trackingArea: NSTrackingArea?
    private var referentRanges: [Int64: [NSRange]] = [:]

    override func scrollWheel(with event: NSEvent) {
        if isScrollLocked {
            return
        }
        super.scrollWheel(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        checkHover(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateHoverHighlight(nil)
    }

    private func checkHover(at point: NSPoint) {
        if isScrollLocked {
            return
        }
        // NSTextView owns the selection cursor. Only update annotation styling here;
        // setting NSCursor on every move races AppKit's cursor rectangles and flickers.
        guard let layoutManager,
              let textContainer,
              let textStorage else {
            updateHoverHighlight(nil)
            return
        }

        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)

        guard glyphRect.contains(point), charIndex < textStorage.length else {
            updateHoverHighlight(nil)
            return
        }

        for (referentId, ranges) in referentRanges {
            for range in ranges {
                if NSLocationInRange(charIndex, range) {
                    updateHoverHighlight(referentId)
                    return
                }
            }
        }
        updateHoverHighlight(nil)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let (referentId, rect) = hitTestReferent(at: point) {
            let convertedRect: CGRect
            if let scrollView = enclosingScrollView {
                convertedRect = convert(rect, to: scrollView)
            } else {
                convertedRect = rect
            }
            onSelectAnnotation?(referentId, convertedRect)
            return
        }
        super.mouseDown(with: event)
    }

    private func hitTestReferent(at point: NSPoint) -> (Int64, NSRect)? {
        guard let layoutManager,
              let textContainer,
              let textStorage else { return nil }

        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
        guard glyphRect.contains(point), charIndex < textStorage.length else { return nil }

        for (referentId, ranges) in referentRanges {
            for range in ranges {
                if NSLocationInRange(charIndex, range) {
                    let rect = layoutManager.boundingRect(forGlyphRange: range, in: textContainer)
                    return (referentId, rect)
                }
            }
        }
        return nil
    }

    func setLyrics(_ lyrics: [GeniusLyricLineRecord], selectedReferentId: Int64?) {
        self.selectedReferentId = selectedReferentId
        self.hoveredReferentId = nil
        self.referentRanges.removeAll()

        let fullString = NSMutableAttributedString()

        for (index, line) in lyrics.enumerated() {
            if line.isHeader {
                let paragraph = NSMutableParagraphStyle()
                paragraph.paragraphSpacingBefore = (index == 0) ? 4 : 18
                paragraph.paragraphSpacing = 6

                let headerAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: paragraph
                ]
                fullString.append(NSAttributedString(string: line.text + "\n", attributes: headerAttrs))
            } else {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 5
                paragraph.paragraphSpacing = 7

                let spans = line.spans.isEmpty
                    ? [GeniusLyricSpanRecord(text: line.text, referentId: line.referentId)]
                    : line.spans

                for span in spans {
                    guard !span.text.isEmpty else { continue }
                    let startLoc = fullString.length
                    var spanAttrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
                        .paragraphStyle: paragraph
                    ]

                    if let id = span.referentId {
                        let isSelected = (id == selectedReferentId)
                        spanAttrs[.backgroundColor] = isSelected
                            ? NSColor.sidebAccent.withAlphaComponent(0.48)
                            : NSColor.sidebAccent.withAlphaComponent(0.12)
                        spanAttrs[.foregroundColor] = isSelected
                            ? NSColor.white
                            : NSColor.white.withAlphaComponent(0.92)

                        fullString.append(NSAttributedString(string: span.text, attributes: spanAttrs))
                        let spanRange = NSRange(location: startLoc, length: fullString.length - startLoc)
                        self.referentRanges[id, default: []].append(spanRange)
                    } else {
                        spanAttrs[.foregroundColor] = NSColor.white.withAlphaComponent(0.85)
                        fullString.append(NSAttributedString(string: span.text, attributes: spanAttrs))
                    }
                }
                fullString.append(NSAttributedString(string: "\n", attributes: [
                    .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
                    .paragraphStyle: paragraph
                ]))
            }
        }

        textStorage?.setAttributedString(fullString)
        needsDisplay = true
    }

    func updateSelectedReferent(_ newSelectedId: Int64?) {
        let oldSelectedId = self.selectedReferentId
        self.selectedReferentId = newSelectedId
        refreshReferentStyle(oldSelectedId)
        refreshReferentStyle(newSelectedId)
    }

    private func updateHoverHighlight(_ newHoverId: Int64?) {
        guard newHoverId != hoveredReferentId else { return }
        let oldHoverId = self.hoveredReferentId
        self.hoveredReferentId = newHoverId
        refreshReferentStyle(oldHoverId)
        refreshReferentStyle(newHoverId)
    }

    private func refreshReferentStyle(_ id: Int64?) {
        guard let id, let ranges = referentRanges[id], let storage = textStorage else { return }
        let isSelected = (id == selectedReferentId)
        let isHovered = (id == hoveredReferentId)

        let bgColor: NSColor
        let fgColor: NSColor

        if isSelected {
            bgColor = NSColor.sidebAccent.withAlphaComponent(0.48)
            fgColor = NSColor.white
        } else if isHovered {
            bgColor = NSColor.sidebAccent.withAlphaComponent(0.38)
            fgColor = NSColor.white
        } else {
            bgColor = NSColor.sidebAccent.withAlphaComponent(0.12)
            fgColor = NSColor.white.withAlphaComponent(0.92)
        }

        storage.beginEditing()
        for range in ranges {
            guard range.location + range.length <= storage.length else { continue }
            storage.addAttributes([
                .backgroundColor: bgColor,
                .foregroundColor: fgColor
            ], range: range)
        }
        storage.endEditing()
        needsDisplay = true
    }
}
