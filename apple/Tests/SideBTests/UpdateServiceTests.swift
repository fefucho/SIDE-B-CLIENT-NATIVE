import Testing
@testable import SideB

@Suite("Tests de Auto-Actualizador (UpdateService)")
struct UpdateServiceTests {

    @Test("Limpieza de prefijos de versión (v / V / espacios)")
    func testCleanVersion() {
        #expect(UpdateService.cleanVersion("v1.0.1") == "1.0.1")
        #expect(UpdateService.cleanVersion("V2.3.4") == "2.3.4")
        #expect(UpdateService.cleanVersion("  v1.5.0  \n") == "1.5.0")
        #expect(UpdateService.cleanVersion("1.0.0") == "1.0.0")
    }

    @Test("Comparación SemVer: versión mayor")
    func testMajorVersion() {
        #expect(UpdateService.isVersion("2.0.0", newerThan: "1.9.9"))
        #expect(!UpdateService.isVersion("1.0.0", newerThan: "2.0.0"))
    }

    @Test("Comparación SemVer: versión menor")
    func testMinorVersion() {
        #expect(UpdateService.isVersion("1.2.0", newerThan: "1.1.9"))
        #expect(!UpdateService.isVersion("1.1.0", newerThan: "1.2.0"))
    }

    @Test("Comparación SemVer: versión patch")
    func testPatchVersion() {
        #expect(UpdateService.isVersion("1.0.1", newerThan: "1.0.0"))
        #expect(UpdateService.isVersion("v1.0.2", newerThan: "1.0.1"))
        #expect(!UpdateService.isVersion("1.0.0", newerThan: "1.0.1"))
    }

    @Test("Comparación SemVer: igualdad")
    func testEqualVersion() {
        #expect(!UpdateService.isVersion("1.0.0", newerThan: "1.0.0"))
        #expect(!UpdateService.isVersion("v1.0.0", newerThan: "1.0.0"))
        #expect(!UpdateService.isVersion("1.0", newerThan: "1.0.0"))
    }

    @Test("Comparación SemVer: longitud de segmentos heterogénea")
    func testUnequalSegmentLength() {
        #expect(UpdateService.isVersion("1.0.1", newerThan: "1.0"))
        #expect(!UpdateService.isVersion("1.0", newerThan: "1.0.1"))
        #expect(UpdateService.isVersion("1.1", newerThan: "1.0.5"))
    }
}
