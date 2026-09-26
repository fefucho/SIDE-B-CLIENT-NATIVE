import Foundation

/// Aísla el ejecutable de medición de los datos de la app instalada.
enum HomeLabConfiguration {
    static let enabled = ProcessInfo.processInfo.environment["SIDEB_HOME_LAB"] == "1" ||
        (Bundle.main.bundleIdentifier?.hasPrefix("com.fefucho.SideB.HomeLab") ?? false)
    static let usesFixture = enabled && (
        ProcessInfo.processInfo.environment["SIDEB_HOME_FIXTURE"] == "1" ||
        Bundle.main.bundleIdentifier == "com.fefucho.SideB.HomeLabFixture"
    )

    static var appSupportURL: URL {
        if enabled {
            if let override = ProcessInfo.processInfo.environment["SIDEB_HOME_LAB_ROOT"], !override.isEmpty {
                return URL(fileURLWithPath: override, isDirectory: true)
            }
            return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("SideBHomeLab", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SideB", isDirectory: true)
    }

    static var imageCacheURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(
            enabled ? "com.fefucho.sideb.homelab.imagecache" : "com.fefucho.sideb.imagecache",
            isDirectory: true
        )
    }
}
