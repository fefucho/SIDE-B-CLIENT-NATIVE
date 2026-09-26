import Foundation
import AppKit

/// Representa la información de un release publicado en GitHub.
public struct ReleaseInfo: Equatable, Sendable {
    public let tagName: String
    public let version: String
    public let releaseNotes: String
    public let downloadURL: URL
    public let publishedAt: String?

    public init(tagName: String, version: String, releaseNotes: String, downloadURL: URL, publishedAt: String?) {
        self.tagName = tagName
        self.version = version
        self.releaseNotes = releaseNotes
        self.downloadURL = downloadURL
        self.publishedAt = publishedAt
    }
}

/// Estado del ciclo de vida del actualizador.
public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(ReleaseInfo)
    case downloading(progress: Double)
    case installing
    case failed(String)
}

/// Servicio que gestiona la comprobación, descarga y aplicación de actualizaciones desde GitHub Releases.
@MainActor
@Observable
public final class UpdateService: NSObject, @unchecked Sendable {
    public static let shared = UpdateService()

    public var repoOwner: String = "fefucho"
    public var repoName: String = "SIDE-B-CLIENT-NATIVE"

    public var state: UpdateState = .idle
    public var isSheetPresented: Bool = false

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var downloadTask: URLSessionDownloadTask?
    private var downloadContinuation: CheckedContinuation<URL, Error>?

    public override init() {
        super.init()
        // Cargar repositorios personalizados si están en Info.plist
        if let customOwner = Bundle.main.infoDictionary?["GitHubRepoOwner"] as? String, !customOwner.isEmpty {
            self.repoOwner = customOwner
        }
        if let customRepo = Bundle.main.infoDictionary?["GitHubRepoName"] as? String, !customRepo.isEmpty {
            self.repoName = customRepo
        }
    }

    /// Comprueba si existe una versión más reciente en GitHub Releases.
    public func checkForUpdates(manual: Bool = false) async {
        state = .checking
        if manual {
            isSheetPresented = true
        }

        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            state = .failed("URL de GitHub no válida.")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("SideB/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                state = manual ? .failed("No se recibió respuesta válida del servidor.") : .idle
                return
            }

            if httpResponse.statusCode == 404 {
                state = manual ? .failed("Aún no hay ningún release publicado en el repositorio \(repoOwner)/\(repoName).") : .idle
                return
            }

            guard httpResponse.statusCode == 200 else {
                state = manual ? .failed("Error al consultar GitHub (código \(httpResponse.statusCode)).") : .idle
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                state = manual ? .failed("Formato de respuesta de release no reconocido.") : .idle
                return
            }

            let remoteVersion = Self.cleanVersion(tagName)
            let body = json["body"] as? String ?? "No se incluyeron notas para este release."
            let publishedAt = json["published_at"] as? String

            // Buscar el asset .zip
            var downloadURL: URL?
            if let assets = json["assets"] as? [[String: Any]] {
                for asset in assets {
                    if let name = asset["name"] as? String, name.hasSuffix(".zip"),
                       let browserDownloadURL = asset["browser_download_url"] as? String,
                       let assetURL = URL(string: browserDownloadURL) {
                        downloadURL = assetURL
                        break
                    }
                }
            }

            guard let finalDownloadURL = downloadURL else {
                state = manual ? .failed("El release \(tagName) no contiene un archivo .zip para macOS.") : .idle
                return
            }

            if Self.isVersion(remoteVersion, newerThan: currentVersion) {
                let release = ReleaseInfo(
                    tagName: tagName,
                    version: remoteVersion,
                    releaseNotes: body,
                    downloadURL: finalDownloadURL,
                    publishedAt: publishedAt
                )
                state = .available(release)
                isSheetPresented = true
            } else {
                state = manual ? .upToDate : .idle
            }
        } catch {
            state = manual ? .failed("Error de conexión: \(error.localizedDescription)") : .idle
        }
    }

    /// Descarga la actualización e inicia el reemplazo en caliente.
    public func downloadAndInstall(release: ReleaseInfo) async {
        state = .downloading(progress: 0.0)

        do {
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            let tempDownloadedURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                self.downloadContinuation = continuation
                let task = session.downloadTask(with: release.downloadURL)
                self.downloadTask = task
                task.resume()
            }

            state = .installing

            let updatesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.fefucho.SideB.v2/Updates", isDirectory: true)
            try? FileManager.default.createDirectory(at: updatesDir, withIntermediateDirectories: true)

            let zipFile = updatesDir.appendingPathComponent("SideB-\(release.version).zip")
            try? FileManager.default.removeItem(at: zipFile)
            try FileManager.default.moveItem(at: tempDownloadedURL, to: zipFile)

            try executeTrampolineUpdate(zipURL: zipFile)
        } catch {
            state = .failed("No se pudo completar la actualización: \(error.localizedDescription)")
        }
    }

    /// Lanza un proceso desacoplado que espera a que la app actual cierre,
    /// reemplaza el `.app` bundle, elimina la cuarentena y reabre la nueva versión.
    private func executeTrampolineUpdate(zipURL: URL) throws {
        let currentAppPath = Bundle.main.bundleURL.path
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let updatesDir = zipURL.deletingLastPathComponent().path
        let extractDir = "\(updatesDir)/extracted"

        let trampolineScript = """
        #!/bin/bash
        set -e
        # 1. Esperar a que la instancia actual de Side B termine
        while kill -0 "\(currentPid)" 2>/dev/null; do
            sleep 0.15
        done

        # 2. Descomprimir el ZIP
        rm -rf "\(extractDir)"
        mkdir -p "\(extractDir)"
        ditto -x -k "\(zipURL.path)" "\(extractDir)"

        # 3. Localizar el nuevo bundle .app
        NEW_APP=$(find "\(extractDir)" -name "*.app" -maxdepth 2 | head -n 1)

        if [ -d "$NEW_APP" ]; then
            # 4. Reemplazar la aplicación existente
            rm -rf "\(currentAppPath)"
            cp -R "$NEW_APP" "\(currentAppPath)"
            
            # 5. Eliminar atributos de cuarentena de Gatekeeper si aplica
            xattr -dr com.apple.quarantine "\(currentAppPath)" 2>/dev/null || true
            
            # 6. Lanzar la aplicación actualizada
            open "\(currentAppPath)"
        fi

        # 7. Limpiar temporales
        rm -rf "\(extractDir)" "\(zipURL.path)"
        """

        let scriptURL = URL(fileURLWithPath: "\(updatesDir)/relaunch_and_update.sh")
        try trampolineScript.write(to: scriptURL, atomically: true, encoding: .utf8)

        // Dar permisos de ejecución
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", scriptURL.path]
        try chmod.run()
        chmod.waitUntilExit()

        // Ejecutar el script desacoplado
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
        launcher.arguments = [scriptURL.path]
        try launcher.run()

        // Terminar limpiamente la app para que el script pueda sustituirla
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Utilidades SemVer

    public nonisolated static func cleanVersion(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
    }

    /// Compara dos cadenas de versión según Semantic Versioning (v1 > v2).
    public nonisolated static func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let clean1 = cleanVersion(v1)
        let clean2 = cleanVersion(v2)

        let parts1 = clean1.split(separator: ".").compactMap { Int($0) }
        let parts2 = clean2.split(separator: ".").compactMap { Int($0) }

        let count = max(parts1.count, parts2.count)
        for i in 0..<count {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        return false
    }
}

// MARK: - URLSessionDownloadDelegate para el progreso

extension UpdateService: URLSessionDownloadDelegate {
    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            self.state = .downloading(progress: progress)
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Mover a un archivo temporal antes de que el sistema lo borre
        let tempDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".zip")
        do {
            try FileManager.default.moveItem(at: location, to: tempDestination)
            Task { @MainActor in
                self.downloadContinuation?.resume(returning: tempDestination)
                self.downloadContinuation = nil
            }
        } catch {
            Task { @MainActor in
                self.downloadContinuation?.resume(throwing: error)
                self.downloadContinuation = nil
            }
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            Task { @MainActor in
                self.downloadContinuation?.resume(throwing: error)
                self.downloadContinuation = nil
            }
        }
    }
}
