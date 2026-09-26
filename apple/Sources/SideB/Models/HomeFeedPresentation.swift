import Foundation
import SideBCore

enum HomeSectionStyle: Equatable {
    case quickPicks
    case mixes
    case cards
}

struct HomeItemPresentation: Identifiable, Equatable {
    let id: String
    let sectionID: String
    let style: HomeSectionStyle
    let record: HomeItemRecord
}

struct HomeSectionPresentation: Identifiable, Equatable {
    let id: String
    let title: String
    let style: HomeSectionStyle
    let items: [HomeItemPresentation]
    let moreBrowseId: String?
    let moreParams: String?

    var isNavigableMore: Bool {
        guard let id = moreBrowseId, !id.isEmpty else { return false }
        return !id.hasPrefix("FE")
    }
}

enum HomePresentationFactory {
    static func sections(from records: [HomeSectionRecord], chip: String?) -> [HomeSectionPresentation] {
        var titleOccurrences: [String: Int] = [:]
        let rawSections = records.compactMap { section -> HomeSectionPresentation? in
            guard !section.items.isEmpty else { return nil }
            let titleKey = section.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let sectionOccurrence = titleOccurrences[titleKey, default: 0]
            titleOccurrences[titleKey] = sectionOccurrence + 1
            let sectionID = "\(chip ?? "all")|\(titleKey)|\(sectionOccurrence)"
            let sectionStyle = style(for: section)
            var itemOccurrences: [String: Int] = [:]
            let items = section.items.map { record in
                let key = "\(record.kind)|\(record.id)"
                let occurrence = itemOccurrences[key, default: 0]
                itemOccurrences[key] = occurrence + 1
                return HomeItemPresentation(
                    id: "\(sectionID)|\(key)|\(occurrence)",
                    sectionID: sectionID,
                    style: sectionStyle,
                    record: record
                )
            }
            return HomeSectionPresentation(
                id: sectionID,
                title: section.title,
                style: sectionStyle,
                items: items,
                moreBrowseId: section.moreBrowseId,
                moreParams: section.moreParams
            )
        }

        // Orden de categorías en el feed principal (chip == nil):
        // 1. Listen again / Volver a escuchar
        // 2. Álbumes para ti / Albums
        // 3. Quick picks / Elecciones rápidas
        // 4. Demás secciones en su orden relativo original
        guard chip == nil else { return rawSections }

        return rawSections.enumerated().sorted { a, b in
            let pA = sectionPriority(for: a.element)
            let pB = sectionPriority(for: b.element)
            if pA != pB {
                return pA < pB
            }
            return a.offset < b.offset
        }.map(\.element)
    }

    private static func sectionPriority(for section: HomeSectionPresentation) -> Int {
        let title = section.title.lowercased()
        if title.contains("listen again") || title.contains("volver a escuchar") ||
           title.contains("forgotten") || title.contains("favoritos olvidados") {
            return 0
        }
        if title.contains("album") || title.contains("álbum") || section.items.allSatisfy({ $0.record.kind == "album" }) {
            return 1
        }
        if title.contains("quick pick") || title.contains("elecciones") {
            return 2
        }
        return 3
    }

    private static func style(for section: HomeSectionRecord) -> HomeSectionStyle {
        let title = section.title.lowercased()
        let songCount = section.items.lazy.filter { $0.kind == "song" }.count

        // Quick picks: requiere al menos 6 items para llenar apropiadamente un layout de 3 filas
        if section.items.count >= 6 && (
            title.contains("quick pick") || title.contains("elecciones") ||
            title.contains("forgotten") || title.contains("favoritos olvidados") ||
            (songCount * 4 >= section.items.count * 3)
        ) {
            return .quickPicks
        }

        // Mixes: listas de mezclas automáticas o radios personalizadas (excluyendo álbumes y artistas)
        let isAlbumOrArtist = title.contains("album") || title.contains("álbum") ||
            title.contains("artist") || title.contains("artista") ||
            section.items.allSatisfy { $0.kind == "album" || $0.kind == "artist" }

        if !isAlbumOrArtist && (title.contains("mix") || title.contains("para ti") || title.contains("mixed for you")) {
            return .mixes
        }

        return .cards
    }
}

