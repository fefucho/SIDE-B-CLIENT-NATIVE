import Testing
import SideBCore
@testable import SideB

@Suite("Seguimiento de letras sincronizadas")
struct LyricTimingTests {
    private func lyrics(_ times: [UInt64?], synced: Bool = true) -> LyricsInfo {
        LyricsInfo(
            provider: "test",
            isSynced: synced,
            lines: times.enumerated().map { index, time in
                LyricLineInfo(timeMs: time, endTimeMs: nil, text: "Línea \(index)")
            }
        )
    }

    @Test("La primera línea queda centrable antes de empezar y la última persiste en los huecos")
    func firstLastAndGaps() {
        let info = lyrics([1_000, 4_000, 9_000])
        #expect(LyricTiming.activeIndex(in: info, at: 0) == 0)
        #expect(LyricTiming.activeIndex(in: info, at: 1.0) == 0)
        #expect(LyricTiming.activeIndex(in: info, at: 8.5) == 1)
        #expect(LyricTiming.activeIndex(in: info, at: 30) == 2)
    }

    @Test("El seek elige el último inicio y omite líneas sin tiempo")
    func seekAndMissingTimes() {
        let info = lyrics([nil, 5_000, 2_000, nil, 8_000])
        #expect(LyricTiming.activeIndex(in: info, at: 6) == 1)
        #expect(LyricTiming.activeIndex(in: info, at: 3) == 2)
        #expect(LyricTiming.activeIndex(in: info, at: 9) == 4)
    }

    @Test("Las letras sin sincronización no activan el seguimiento")
    func plainLyrics() {
        #expect(LyricTiming.activeIndex(in: lyrics([nil, nil]), at: 2) == nil)
        #expect(LyricTiming.activeIndex(in: lyrics([1_000], synced: false), at: 2) == nil)
    }
}
