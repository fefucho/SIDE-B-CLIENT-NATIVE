import Foundation
import Observation
import os
import SideBCore

@MainActor
@Observable
final class HomeViewModel {
    private struct FeedSnapshot {
        let records: [HomeSectionRecord]
        let continuation: String?
    }

    var chips: [HomeChipRecord] = []
    var selectedChipParams: String?
    var sections: [HomeSectionPresentation] = []
    var continuationToken: String?
    var isLoading = false
    var isLoadingChip = false
    var isRefreshing = false
    var isLoadingMore = false
    var isShowingSavedFeed = false
    var errorMessage: String?
    private(set) var contentRevision: UInt64 = 0

    @ObservationIgnored private let signposter = OSSignposter(subsystem: "com.fefucho.SideB", category: .pointsOfInterest)
    @ObservationIgnored private let cacheStore: HomeFeedCacheStore
    @ObservationIgnored private var cacheTransition: Task<Void, Never>?
    @ObservationIgnored private var priorityPrefetchTask: Task<Void, Never>?
    @ObservationIgnored private var sessionKey = "guest"
    @ObservationIgnored private var sessionToken = UUID().uuidString
    @ObservationIgnored private var didHydrate = false
    @ObservationIgnored private var sectionRecords: [HomeSectionRecord] = []
    @ObservationIgnored private var snapshots: [String: FeedSnapshot] = [:]
    @ObservationIgnored private var snapshotOrder: [String] = []
    @ObservationIgnored private var requestGeneration: UInt64 = 0
    @ObservationIgnored private var lastLoadMoreTimestamp: Date = .distantPast

    init(cacheStore: HomeFeedCacheStore = HomeFeedCacheStore()) {
        self.cacheStore = cacheStore
    }

    /// Se llama después de instalar la cookie en Core y antes de mostrar Inicio.
    func prepareSession(identity: String, purgePrevious: Bool = true) {
        priorityPrefetchTask?.cancel()
        priorityPrefetchTask = nil
        let oldKey = sessionKey
        let oldToken = sessionToken
        let previousTransition = cacheTransition
        sessionKey = identity
        sessionToken = UUID().uuidString
        let newToken = sessionToken
        requestGeneration &+= 1
        didHydrate = false
        snapshots.removeAll()
        snapshotOrder.removeAll()
        sectionRecords = []
        chips = []
        selectedChipParams = nil
        sections = []
        continuationToken = nil
        isLoading = false
        isLoadingChip = false
        isRefreshing = false
        isLoadingMore = false
        isShowingSavedFeed = false
        errorMessage = nil
        lastLoadMoreTimestamp = .distantPast
        contentRevision &+= 1
        cacheTransition = Task { [cacheStore] in
            await previousTransition?.value
            if purgePrevious { await cacheStore.retire(oldKey, token: oldToken) }
            await cacheStore.activate(identity, token: newToken)
        }
    }

    func resetForAccountChange() { prepareSession(identity: "guest") }

    func loadHomeFeed(core: SideBCore, chipParams: String? = nil) async {
        priorityPrefetchTask?.cancel()
        priorityPrefetchTask = nil
        isLoadingMore = false
        requestGeneration &+= 1
        let generation = requestGeneration
        let key = chipParams ?? ""
        let previousChip = selectedChipParams
        let changedChip = previousChip != chipParams

        if chipParams == nil, !didHydrate, sections.isEmpty {
            await hydrateSavedFeed(generation: generation)
            guard generation == requestGeneration else { return }
        }

        selectedChipParams = chipParams
        if let cached = snapshots[key] {
            apply(records: cached.records, continuation: cached.continuation, chip: chipParams)
        } else if changedChip {
            continuationToken = nil
            contentRevision &+= 1
        }
        isLoading = sections.isEmpty
        isLoadingChip = changedChip && !sections.isEmpty
        isRefreshing = !changedChip && !sections.isEmpty
        isLoadingMore = false
        errorMessage = nil

        do {
            let page = try await fetchHomePage(core: core, chipParams: chipParams)
            guard generation == requestGeneration, !Task.isCancelled else { return }
            if !HomeLabConfiguration.usesFixture && !core.isLoggedIn() && sessionKey != "guest" {
                let oldKey = sessionKey
                let oldToken = sessionToken
                sessionKey = "guest"
                sessionToken = UUID().uuidString
                let newToken = sessionToken
                snapshots.removeAll()
                snapshotOrder.removeAll()
                cacheTransition = Task { [cacheStore] in
                    await cacheStore.retire(oldKey, token: oldToken)
                    await cacheStore.activate("guest", token: newToken)
                }
            }
            if chipParams == nil && !page.chips.isEmpty { chips = page.chips }
            let interval = signposter.beginInterval("HomeFeedPresent")
            apply(records: page.sections, continuation: page.continuation, chip: chipParams)
            signposter.endInterval("HomeFeedPresent", interval)
            remember(FeedSnapshot(records: page.sections, continuation: page.continuation), for: key)
            isShowingSavedFeed = false
            finishLoading()

            if chipParams == nil {
                await cacheTransition?.value
                guard generation == requestGeneration else { return }
                await cacheStore.save(HomeCachedPage(page), for: sessionKey, token: sessionToken)
                if let token = page.continuation {
                    startPriorityPrefetch(core: core, token: token, generation: generation, chip: chipParams)
                }
            }
        } catch {
            guard generation == requestGeneration else { return }
            if !Task.isCancelled {
                if changedChip && snapshots[key] == nil && !sections.isEmpty {
                    selectedChipParams = previousChip
                    continuationToken = snapshots[previousChip ?? ""]?.continuation
                }
                errorMessage = error.localizedDescription
            }
            finishLoading()
        }
    }

    func loadMoreContent(core: SideBCore) async {
        guard let token = continuationToken,
              !isLoadingMore, !isLoading, !isLoadingChip, !isRefreshing,
              Date().timeIntervalSince(lastLoadMoreTimestamp) > 2 else { return }
        let generation = requestGeneration
        let key = selectedChipParams ?? ""
        lastLoadMoreTimestamp = Date()
        isLoadingMore = true
        do {
            let page = try await fetchContinuation(core: core, token: token)
            guard generation == requestGeneration, continuationToken == token, !Task.isCancelled else { return }
            var existing = Set(sectionRecords.map(Self.sectionSignature))
            let fresh = page.sections.filter { existing.insert(Self.sectionSignature($0)).inserted }
            sectionRecords.append(contentsOf: fresh)
            let next = page.continuation.flatMap { $0.isEmpty || $0 == token ? nil : $0 }
            apply(records: sectionRecords, continuation: next, chip: selectedChipParams)
            remember(FeedSnapshot(records: sectionRecords, continuation: next), for: key)
            isLoadingMore = false
        } catch {
            if generation == requestGeneration { isLoadingMore = false }
        }
    }

    private func hydrateSavedFeed(generation: UInt64) async {
        didHydrate = true
        if let cacheTransition { await cacheTransition.value }
        else { await cacheStore.activate(sessionKey, token: sessionToken) }
        let interval = signposter.beginInterval("HomeFeedHydrate")
        let cached = await cacheStore.load(for: sessionKey, token: sessionToken)
        signposter.endInterval("HomeFeedHydrate", interval)
        guard generation == requestGeneration, let cached else { return }
        let page = cached.page
        chips = page.chips
        apply(records: page.sections, continuation: nil, chip: nil)
        remember(FeedSnapshot(records: page.sections, continuation: nil), for: "")
        isShowingSavedFeed = true
    }

    private func apply(records: [HomeSectionRecord], continuation: String?, chip: String?) {
        sectionRecords = records
        sections = HomePresentationFactory.sections(from: records, chip: chip)
        continuationToken = continuation
        contentRevision &+= 1
    }

    private func finishLoading() {
        isLoading = false
        isLoadingChip = false
        isRefreshing = false
    }

    private func fetchHomePage(core: SideBCore, chipParams: String?) async throws -> HomePageRecord {
        let interval = signposter.beginInterval("HomeFeedFetch")
        defer { signposter.endInterval("HomeFeedFetch", interval) }
        if HomeLabConfiguration.usesFixture {
            try await Task.sleep(for: .milliseconds(700))
            return HomeBenchmarkFixture.page(chipParams: chipParams)
        }
        return try await core.getHomePage(chipParams: chipParams)
    }

    private func fetchContinuation(core: SideBCore, token: String) async throws -> HomePageRecord {
        let interval = signposter.beginInterval("HomeFeedContinuation")
        defer { signposter.endInterval("HomeFeedContinuation", interval) }
        if HomeLabConfiguration.usesFixture { return HomeBenchmarkFixture.page(continuation: true) }
        return try await core.getHomeContinuation(token: token)
    }

    private static func sectionSignature(_ section: HomeSectionRecord) -> String {
        let first = section.items.first.map { "\($0.kind):\($0.id)" } ?? ""
        let last = section.items.last.map { "\($0.kind):\($0.id)" } ?? ""
        if let browseID = section.moreBrowseId, !browseID.isEmpty {
            return "more|\(browseID)|\(section.moreParams ?? "")|\(first)|\(last)"
        }
        return "items|\(first)|\(last)"
    }

    private func startPriorityPrefetch(core: SideBCore, token: String, generation: UInt64, chip: String?) {
        guard chip == nil, !Self.containsAllNamedPrioritySections(sectionRecords) else { return }
        priorityPrefetchTask = Task { [weak self] in
            await self?.prefetchPrioritySections(core: core, token: token, generation: generation)
        }
    }

    private func prefetchPrioritySections(core: SideBCore, token initialToken: String, generation: UInt64) async {
        guard generation == requestGeneration, !Task.isCancelled else { return }
        let interval = signposter.beginInterval("HomePriorityPrefetch")
        isLoadingMore = true
        defer {
            signposter.endInterval("HomePriorityPrefetch", interval)
            if generation == requestGeneration { isLoadingMore = false }
        }

        // Three continuation requests cap background network work while covering the usual Home
        // response split. Stop sooner when every named priority section has arrived or after 12s.
        let maximumPages = 3
        let timeBudget: TimeInterval = 12
        let startedAt = Date()
        var token = initialToken
        var usedTokens = Set<String>()
        for _ in 0..<maximumPages {
            guard generation == requestGeneration, !Task.isCancelled,
                  Date().timeIntervalSince(startedAt) < timeBudget,
                  usedTokens.insert(token).inserted else { break }
            do {
                let page = try await fetchContinuation(core: core, token: token)
                guard generation == requestGeneration, !Task.isCancelled else { return }
                var existing = Set(sectionRecords.map(Self.sectionSignature))
                let fresh = page.sections.filter { existing.insert(Self.sectionSignature($0)).inserted }
                continuationToken = page.continuation
                if !fresh.isEmpty {
                    sectionRecords.append(contentsOf: fresh)
                    apply(records: sectionRecords, continuation: page.continuation, chip: nil)
                }

                guard let next = page.continuation, !next.isEmpty, next != token,
                      !usedTokens.contains(next) else {
                    continuationToken = nil
                    break
                }
                token = next
                if Self.containsAllNamedPrioritySections(sectionRecords) { break }
            } catch {
                break
            }
        }

        guard generation == requestGeneration, !Task.isCancelled else { return }
        let snapshot = FeedSnapshot(records: sectionRecords, continuation: continuationToken)
        remember(snapshot, for: "")
        await cacheStore.save(
            HomeCachedPage(HomePageRecord(chips: chips, sections: sectionRecords, continuation: nil)),
            for: sessionKey,
            token: sessionToken
        )
    }

    private static func containsAllNamedPrioritySections(_ sections: [HomeSectionRecord]) -> Bool {
        let titles = Set(sections.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let groups: [[String]] = [
            ["listen again", "vuelve a escucharlo", "volver a escuchar", "escuchar de nuevo"],
            ["forgotten favorites", "forgotten favourites", "favoritos olvidados"],
            ["albums for you", "albumes para ti", "álbumes para ti"],
            ["from your library", "de tu biblioteca", "de la biblioteca"],
            ["quick picks", "selecciones rapidas", "selecciones rápidas"],
        ]
        return groups.allSatisfy { names in names.contains(where: titles.contains) }
    }

    private func remember(_ snapshot: FeedSnapshot, for key: String) {
        snapshots[key] = snapshot
        snapshotOrder.removeAll { $0 == key }
        snapshotOrder.append(key)
        if snapshotOrder.count > 4 { snapshots.removeValue(forKey: snapshotOrder.removeFirst()) }
    }
}
