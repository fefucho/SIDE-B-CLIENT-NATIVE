import SwiftUI
import SideBCore

// MARK: - QueueContext

/// Describe el origen y naturaleza de la cola activa de reproducción.
public enum QueueContext: Equatable {
    case radio(seedVideoId: String, title: String, seedName: String)
    case album(browseId: String, title: String)
    case playlist(browseId: String, title: String)
    case custom(title: String)
    
    public var iconName: String {
        switch self {
        case .radio:
            return "dot.radiowaves.left.and.right"
        case .album:
            return "record.circle"
        case .playlist:
            return "music.note.list"
        case .custom:
            return "list.bullet"
        }
    }
}

// MARK: - QueueManager

@MainActor
@Observable
public final class QueueManager {
    // MARK: - Estado de Cola
    public var queue: [SongItemRecord] = []
    public var currentIndex: Int = 0
    public var context: QueueContext? = nil
    public var contextTitle: String = "Cola de reproducción"
    public var radioSeed: String? = nil
    public var continuationToken: String? = nil
    public private(set) var queueToken: UUID = UUID()
    
    // MARK: - Modos y Banderas
    public var isShuffle: Bool = false
    public var isRepeat: Bool = false
    public var isLoadingRadio: Bool = false
    public var isLoadingAutoplay: Bool = false
    
    public init() {}

    public func toggleShuffle() {
        isShuffle.toggle()
        if isShuffle && currentIndex + 1 < queue.count {
            let nextPart = queue[(currentIndex + 1)...].shuffled()
            let prevPart = Array(queue[0...currentIndex])
            self.queue = prevPart + nextPart
        }
    }
    
    // MARK: - Propiedades Computadas
    
    public var tracks: [SongItemRecord] {
        queue
    }

    public var currentTrack: SongItemRecord? {
        guard currentIndex >= 0, currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }
    
    public var upNextTracks: [SongItemRecord] {
        guard currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }
    
    public var previousTracks: [SongItemRecord] {
        guard currentIndex > 0, !queue.isEmpty else { return [] }
        return Array(queue[0..<currentIndex])
    }
    
    public var hasNext: Bool {
        if isRepeat { return !queue.isEmpty }
        return currentIndex < queue.count - 1
    }
    
    public var hasPrevious: Bool {
        currentIndex > 0
    }
    
    /// Indica si la reproducción se acerca al final de la cola activa (<= 2 pistas restantes)
    public var isNearTail: Bool {
        guard !queue.isEmpty else { return false }
        return (queue.count - 1 - currentIndex) <= 2
    }

    /// Sincroniza el índice de la cola buscando la pista por videoId, preservando la ocurrencia activa ante duplicados.
    @discardableResult
    public func syncCurrentIndex(for videoId: String) -> Int? {
        if currentIndex >= 0, currentIndex < queue.count, queue[currentIndex].videoId == videoId {
            return currentIndex
        }
        if let idx = queue.firstIndex(where: { $0.videoId == videoId }) {
            self.currentIndex = idx
            return idx
        }
        return nil
    }
    
    // MARK: - Métodos de Ciclo de Vida y Reemplazo de Cola
    
    /// Reemplaza la cola previa de forma atómica con un nuevo lote de temas y contexto.
    public func replaceQueue(
        with items: [SongItemRecord],
        startingAt index: Int = 0,
        context: QueueContext? = nil,
        contextTitle: String? = nil,
        radioSeed: String? = nil,
        continuation: String? = nil
    ) {
        self.queueToken = UUID()
        self.queue = items
        self.currentIndex = max(0, min(items.count - 1, index))
        self.context = context
        if let title = contextTitle {
            self.contextTitle = title
        } else {
            switch context {
            case .radio(_, let title, _):
                self.contextTitle = title
            case .album(_, let title):
                self.contextTitle = "Álbum: \(title)"
            case .playlist(_, let title):
                self.contextTitle = "Lista: \(title)"
            case .custom(let title):
                self.contextTitle = title
            case .none:
                self.contextTitle = "Cola de reproducción"
            }
        }
        self.radioSeed = radioSeed
        self.continuationToken = continuation
    }
    
    /// Añade temas recomendados de radio o automix deduplicando contra las pistas existentes.
    public func appendRadioTracks(_ tracks: [SongItemRecord], continuation: String? = nil) {
        let existingIds = Set(queue.map(\.videoId))
        let fresh = tracks.filter { !existingIds.contains($0.videoId) }
        guard !fresh.isEmpty else {
            if let c = continuation { self.continuationToken = c }
            return
        }
        self.queue.append(contentsOf: fresh)
        if let c = continuation {
            self.continuationToken = c
        }
    }

    /// Añade temas de continuación de una playlist preservando el orden y actualizando el token siguiente.
    public func appendPlaylistTracks(_ tracks: [SongItemRecord], nextContinuation: String? = nil) {
        let existingIds = Set(queue.map(\.videoId))
        let fresh = tracks.filter { !existingIds.contains($0.videoId) }
        guard !fresh.isEmpty else {
            self.continuationToken = nextContinuation
            return
        }
        self.queue.append(contentsOf: fresh)
        self.continuationToken = nextContinuation
    }
    
    /// Inserta una pista inmediatamente a continuación del tema en reproducción ("Reproducir a continuación").
    public func playNext(_ track: SongItemRecord) {
        if queue.isEmpty {
            replaceQueue(with: [track], startingAt: 0, context: .custom(title: "Cola manual"), contextTitle: "Cola manual")
            return
        }
        let insertIndex = min(currentIndex + 1, queue.count)
        self.queue.insert(track, at: insertIndex)
    }
    
    /// Inserta múltiples pistas inmediatamente a continuación del tema en reproducción.
    public func playNext(_ tracks: [SongItemRecord]) {
        guard !tracks.isEmpty else { return }
        if queue.isEmpty {
            replaceQueue(with: tracks, startingAt: 0, context: .custom(title: "Cola manual"), contextTitle: "Cola manual")
            return
        }
        let insertIndex = min(currentIndex + 1, queue.count)
        self.queue.insert(contentsOf: tracks, at: insertIndex)
    }
    
    /// Añade una pista al final de la cola activa ("Añadir a la cola").
    public func addTrackToQueue(_ track: SongItemRecord) {
        if queue.isEmpty {
            replaceQueue(with: [track], startingAt: 0, context: .custom(title: "Cola manual"), contextTitle: "Cola manual")
            return
        }
        self.queue.append(track)
    }
    
    /// Añade múltiples pistas al final de la cola activa.
    public func addTracksToQueue(_ tracks: [SongItemRecord]) {
        guard !tracks.isEmpty else { return }
        if queue.isEmpty {
            replaceQueue(with: tracks, startingAt: 0, context: .custom(title: "Cola manual"), contextTitle: "Cola manual")
            return
        }
        self.queue.append(contentsOf: tracks)
    }
    
    /// Elimina una pista de la cola en el índice especificado de forma segura.
    @discardableResult
    public func removeTrack(at index: Int) -> SongItemRecord? {
        guard index >= 0, index < queue.count else { return nil }
        let removed = self.queue.remove(at: index)
        if index < currentIndex {
            currentIndex = max(0, currentIndex - 1)
        } else if currentIndex >= queue.count {
            currentIndex = max(0, queue.count - 1)
        }
        return removed
    }

    /// Elimina una pista de la cola buscando por su videoId.
    @discardableResult
    public func removeTrack(videoId: String) -> SongItemRecord? {
        guard let index = queue.firstIndex(where: { $0.videoId == videoId }) else { return nil }
        return removeTrack(at: index)
    }

    /// Reordena una pista dentro de la cola conservando el índice activo aritméticamente sin colisionar con duplicados.
    public func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < queue.count,
              destinationIndex >= 0, destinationIndex < queue.count,
              sourceIndex != destinationIndex else { return }

        let item = queue.remove(at: sourceIndex)
        queue.insert(item, at: destinationIndex)

        if currentIndex == sourceIndex {
            currentIndex = destinationIndex
        } else if sourceIndex < currentIndex && destinationIndex >= currentIndex {
            currentIndex = max(0, currentIndex - 1)
        } else if sourceIndex > currentIndex && destinationIndex <= currentIndex {
            currentIndex = min(queue.count - 1, currentIndex + 1)
        }
    }
    
    /// Vacia la cola completa.
    public func clearQueue() {
        self.queue.removeAll()
        self.currentIndex = 0
        self.context = nil
        self.contextTitle = "Cola de reproducción"
        self.radioSeed = nil
        self.continuationToken = nil
    }
    
    // MARK: - Compatibilidad Legada
    
    @available(*, deprecated, renamed: "replaceQueue(with:startingAt:)")
    public func setQueue(_ items: [SongItemRecord], startingAt index: Int = 0) {
        replaceQueue(with: items, startingAt: index)
    }
    
    @available(*, deprecated, renamed: "appendRadioTracks(_:)")
    public func appendTracks(_ tracks: [SongItemRecord]) {
        appendRadioTracks(tracks)
    }
    
    // MARK: - Navegación entre Pistas
    
    /// Devuelve la siguiente pista. Si `isManualSkip` es false y repetir está activo, repite el tema.
    /// Si `isManualSkip` es true (el usuario pulsó Siguiente), avanza a la siguiente pista de la cola.
    public func nextTrack(isManualSkip: Bool = false) -> SongItemRecord? {
        if isRepeat && !isManualSkip {
            return currentTrack
        }
        guard currentIndex + 1 < queue.count else {
            if isRepeat && !queue.isEmpty {
                currentIndex = 0
                return queue[0]
            }
            return nil
        }
        currentIndex += 1
        return queue[currentIndex]
    }
    
    public func previousTrack() -> SongItemRecord? {
        guard currentIndex > 0 else { return nil }
        currentIndex -= 1
        return queue[currentIndex]
    }
    
    public func selectTrack(at index: Int) -> SongItemRecord? {
        guard index >= 0, index < queue.count else { return nil }
        currentIndex = index
        return queue[currentIndex]
    }
}

