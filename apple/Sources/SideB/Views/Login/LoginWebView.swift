import SwiftUI
import WebKit

struct LoginWebView: NSViewRepresentable {
    var onLoginSuccess: (String) -> Void

    // Safari macOS User Agent (WebKit compatible, evita el bloqueo de Google "disallowed_useragent")
    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    // URL oficial de inicio de sesión de YouTube Music con redirección completa
    static let loginURLString = "https://accounts.google.com/ServiceLogin?service=youtube&uilel=3&passive=true&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop%26hl%3Den%26next%3Dhttps%253A%252F%252Fmusic.youtube.com%252F"

    func makeNSView(context: Context) -> WKWebView {
        let dataStore = WKWebsiteDataStore.default()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore

        // Suprimir WebAuthn Passkeys para que Google pida password/autenticación normal
        configuration.userContentController.addUserScript(LoginPasskeySuppression.makeUserScript())

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.safariUserAgent
        webView.navigationDelegate = context.coordinator

        #if DEBUG
        webView.isInspectable = true
        #endif

        // Cargar URL de login de Google / YouTube Music
        if let url = URL(string: Self.loginURLString) {
            var request = URLRequest(url: url)
            request.setValue(Self.safariUserAgent, forHTTPHeaderField: "User-Agent")
            webView.load(request)
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LoginWebView
        private var hasExtractedCookies = false

        init(_ parent: LoginWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }
            // Solo intentamos extraer cuando la redirección llega a music.youtube.com
            if url.host?.contains("music.youtube.com") == true {
                // Esperar un breve instante para que todas las cookies de sesión se asienten
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(800))
                    self?.extractYouTubeMusicCookies(from: webView.configuration.websiteDataStore.httpCookieStore)
                }
            }
        }

        private func extractYouTubeMusicCookies(from cookieStore: WKHTTPCookieStore) {
            guard !hasExtractedCookies else { return }

            cookieStore.getAllCookies { [weak self] cookies in
                guard let self = self, !self.hasExtractedCookies else { return }

                // Filtrar exclusivamente cookies de youtube.com (idéntico a sideb OLD)
                let youtubeCookies = cookies.filter { cookie in
                    let domain = cookie.domain.lowercased()
                    return domain == "youtube.com" || domain.hasSuffix(".youtube.com")
                }

                let hasAuthCookie = youtubeCookies.contains { $0.name == "__Secure-3PAPISID" || $0.name == "SAPISID" }
                let hasSessionCookie = youtubeCookies.contains { $0.name == "LOGIN_INFO" || $0.name.contains("PSID") }

                if hasAuthCookie && hasSessionCookie {
                    self.hasExtractedCookies = true

                    // Usar requestHeaderFields estándar de Foundation para formatear el Cookie header idéntico al navegador
                    let headerFields = HTTPCookie.requestHeaderFields(with: youtubeCookies)
                    let cookieHeader = headerFields["Cookie"] ?? youtubeCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")

                    Task { @MainActor in
                        self.parent.onLoginSuccess(cookieHeader)
                    }
                } else if hasAuthCookie {
                    // Si ya tiene SAPISID pero aún falta LOGIN_INFO, reintentar en 1 segundo
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(1))
                        self?.extractYouTubeMusicCookies(from: cookieStore)
                    }
                }
            }
        }
    }
}
