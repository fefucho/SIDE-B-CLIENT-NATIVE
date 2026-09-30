import SwiftUI
import SideBCore

// MARK: - SearchFilter

public enum SearchFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "Todo"
    case songs = "Canciones"
    case albums = "Álbumes"
    case artists = "Artistas"
    case playlists = "Playlists"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .all: return "sparkles"
        case .songs: return "music.note"
        case .albums: return "opticaldisc"
        case .artists: return "person.2.fill"
        case .playlists: return "music.note.list"
        }
    }
}

// MARK: - SearchCategory

public enum SearchCategory: String, Identifiable, Sendable {
    case topResult = "Mejor resultado"
    case artists = "Artistas"
    case songs = "Canciones"
    case albums = "Álbumes"
    case playlists = "Playlists"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .topResult: return "star.fill"
        case .artists: return "person.crop.circle.fill"
        case .songs: return "music.note"
        case .albums: return "opticaldisc"
        case .playlists: return "music.note.list"
        }
    }
}

// MARK: - SearchViewModel

@MainActor
@Observable
public final class SearchViewModel {
    // MARK: - Estado de Consulta
    public var query: String = ""
    public var committedQuery: String = ""
    
    // MARK: - Resultados Rápidos (Spotlight & Topdown Dropdown)
    public var quickResults: SearchResultsRecord? = nil
    public private(set) var associatedQuickQuery: String = ""
    public var isQuickSearching: Bool = false
    public var isTopdownVisible: Bool = false
    
    // MARK: - Resultados Comprometidos (Página Completa SearchView)
    public var committedResults: SearchResultsRecord? = nil
    public var isCommittedLoading: Bool = false
    
    // MARK: - Filtros de Categoría
    public var selectedFilter: SearchFilter = .all
    public var filteredSongs: [SongItemRecord] = []
    public var filteredCards: [BrowseCardRecord] = []
    public var isFilterLoading: Bool = false
    
    // MARK: - Tareas y Cancelación Atómica
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration: UInt = 0
    @ObservationIgnored private var commitGeneration: UInt = 0
    @ObservationIgnored private var filterGeneration: UInt = 0
    
    public init() {}
    
    // MARK: - Búsqueda Rápida Dinámica (Debounce 250ms)
    
    public func onQueryChanged(_ newQuery: String, core: SideBCore) {
        query = newQuery
        debounceTask?.cancel()
        searchGeneration &+= 1
        let currentGen = searchGeneration
        
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            quickResults = nil
            associatedQuickQuery = ""
            isQuickSearching = false
            isTopdownVisible = false
            return
        }
        
        // Si ya tenemos resultados cacheados para esta consulta exacta, mostrarlos inmediatamente
        if trimmed == associatedQuickQuery && quickResults != nil {
            isQuickSearching = false
            isTopdownVisible = true
            return
        }
        
        // Si el texto cambió respecto a los resultados cacheados, invalidar inmediatamente
        if trimmed != associatedQuickQuery {
            quickResults = nil
        }
        
        isQuickSearching = true
        isTopdownVisible = true
        
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, currentGen == self.searchGeneration else { return }
            
            do {
                let results = try await core.searchAll(query: trimmed, recordHistory: false)
                guard !Task.isCancelled, currentGen == self.searchGeneration else { return }
                self.quickResults = results
                self.associatedQuickQuery = trimmed
                self.isQuickSearching = false
                self.isTopdownVisible = true
            } catch {
                guard !Task.isCancelled, currentGen == self.searchGeneration else { return }
                self.isQuickSearching = false
            }
        }
    }
    
    // MARK: - Confirmar Búsqueda (Enter / Navegación a SearchView)
    
    public func commitSearch(query text: String, core: SideBCore, force: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Ocultar dropdown flotante y cancelar debounce al confirmar
        debounceTask?.cancel()
        isQuickSearching = false
        isTopdownVisible = false
        
        if committedQuery == trimmed && !force && committedResults != nil {
            return
        }
        
        committedQuery = trimmed
        query = trimmed
        isCommittedLoading = true
        
        // Si el filtro actual es .all y ya tenemos quickResults verificados para esta misma query exacta
        if selectedFilter == .all, let cached = quickResults, associatedQuickQuery == trimmed && !force {
            committedResults = cached
            isCommittedLoading = false
            return
        }
        
        commitTask?.cancel()
        commitGeneration &+= 1
        let currentCommitGen = commitGeneration
        
        commitTask = Task {
            switch selectedFilter {
            case .all:
                do {
                    let results = try await core.searchAll(query: trimmed, recordHistory: false)
                    guard !Task.isCancelled, currentCommitGen == self.commitGeneration, self.committedQuery == trimmed else { return }
                    self.committedResults = results
                    self.quickResults = results
                    self.associatedQuickQuery = trimmed
                } catch {
                    // Manejo silencioso o estado vacío
                }
            case .songs:
                await fetchFilteredSongs(query: trimmed, core: core, generation: currentCommitGen)
            case .albums:
                await fetchFilteredCards(query: trimmed, category: "albums", core: core, expectedFilter: .albums, generation: currentCommitGen)
            case .artists:
                await fetchFilteredCards(query: trimmed, category: "artists", core: core, expectedFilter: .artists, generation: currentCommitGen)
            case .playlists:
                await fetchFilteredCards(query: trimmed, category: "playlists", core: core, expectedFilter: .playlists, generation: currentCommitGen)
            }
            guard !Task.isCancelled, currentCommitGen == self.commitGeneration, self.committedQuery == trimmed else { return }
            self.isCommittedLoading = false
        }
    }
    
    // MARK: - Cambio de Filtro de Categoría
    
    public func selectFilter(_ filter: SearchFilter, core: SideBCore) {
        guard selectedFilter != filter else { return }
        selectedFilter = filter
        
        // Limpiar resultados anteriores de categoría para evitar flasheos de tarjetas discordantes
        switch filter {
        case .all: break
        case .songs: filteredSongs = []
        case .albums, .artists, .playlists: filteredCards = []
        }
        
        guard !committedQuery.isEmpty else { return }
        
        filterTask?.cancel()
        filterGeneration &+= 1
        let currentFilterGen = filterGeneration
        let targetQuery = committedQuery
        
        filterTask = Task {
            isFilterLoading = true
            switch filter {
            case .all:
                if committedResults == nil {
                    do {
                        let res = try await core.searchAll(query: targetQuery, recordHistory: false)
                        guard !Task.isCancelled, currentFilterGen == self.filterGeneration, self.selectedFilter == .all, self.committedQuery == targetQuery else { return }
                        self.committedResults = res
                    } catch {}
                }
            case .songs:
                await fetchFilteredSongs(query: targetQuery, core: core, generation: currentFilterGen)
            case .albums:
                await fetchFilteredCards(query: targetQuery, category: "albums", core: core, expectedFilter: .albums, generation: currentFilterGen)
            case .artists:
                await fetchFilteredCards(query: targetQuery, category: "artists", core: core, expectedFilter: .artists, generation: currentFilterGen)
            case .playlists:
                await fetchFilteredCards(query: targetQuery, category: "playlists", core: core, expectedFilter: .playlists, generation: currentFilterGen)
            }
            guard !Task.isCancelled, currentFilterGen == self.filterGeneration, self.selectedFilter == filter else { return }
            isFilterLoading = false
        }
    }
    
    private func fetchFilteredSongs(query text: String, core: SideBCore, generation: UInt) async {
        do {
            let songs = try await core.searchSongs(query: text, recordHistory: false)
            guard !Task.isCancelled, (generation == self.filterGeneration || generation == self.commitGeneration), self.selectedFilter == .songs, self.committedQuery == text else { return }
            filteredSongs = songs
        } catch {
            guard !Task.isCancelled, (generation == self.filterGeneration || generation == self.commitGeneration), self.selectedFilter == .songs, self.committedQuery == text else { return }
            filteredSongs = []
        }
    }
    
    private func fetchFilteredCards(query text: String, category: String, core: SideBCore, expectedFilter: SearchFilter, generation: UInt) async {
        do {
            let cards = try await core.searchCards(query: text, category: category)
            guard !Task.isCancelled, (generation == self.filterGeneration || generation == self.commitGeneration), self.selectedFilter == expectedFilter, self.committedQuery == text else { return }
            filteredCards = cards
        } catch {
            guard !Task.isCancelled, (generation == self.filterGeneration || generation == self.commitGeneration), self.selectedFilter == expectedFilter, self.committedQuery == text else { return }
            filteredCards = []
        }
    }
    
    // MARK: - Reordenamiento Dinámico Adaptativo de Categorías
    
    public func dynamicCategories(for results: SearchResultsRecord) -> [SearchCategory] {
        var order: [SearchCategory] = []
        
        let primaryKind = results.top.first?.kind.lowercased()
        
        if !results.top.isEmpty {
            order.append(.topResult)
        }
        
        switch primaryKind {
        case "artist":
            if !results.artists.isEmpty { order.append(.artists) }
            if !results.songs.isEmpty { order.append(.songs) }
            if !results.albums.isEmpty { order.append(.albums) }
            if !results.playlists.isEmpty { order.append(.playlists) }
        case "song":
            if !results.songs.isEmpty { order.append(.songs) }
            if !results.artists.isEmpty { order.append(.artists) }
            if !results.albums.isEmpty { order.append(.albums) }
            if !results.playlists.isEmpty { order.append(.playlists) }
        case "album":
            if !results.albums.isEmpty { order.append(.albums) }
            if !results.songs.isEmpty { order.append(.songs) }
            if !results.artists.isEmpty { order.append(.artists) }
            if !results.playlists.isEmpty { order.append(.playlists) }
        default:
            if !results.artists.isEmpty { order.append(.artists) }
            if !results.songs.isEmpty { order.append(.songs) }
            if !results.albums.isEmpty { order.append(.albums) }
            if !results.playlists.isEmpty { order.append(.playlists) }
        }
        
        return order
    }
    
    // MARK: - Limpieza
    
    public func clear() {
        query = ""
        associatedQuickQuery = ""
        quickResults = nil
        isQuickSearching = false
        isTopdownVisible = false
        debounceTask?.cancel()
        commitTask?.cancel()
        filterTask?.cancel()
    }
}
