import WebKit

// MARK: - LoginPasskeySuppression

/// Oculta el soporte de passkeys WebAuthn en las páginas de inicio de sesión de Google cargadas en el WebView.
///
/// WKWebView expone `window.PublicKeyCredential`, pero sin el entitlement restringido de navegador
/// general de Apple, el sistema rechaza las ceremonias de passkey antes de mostrar UI.
/// Google detecta la API, ofrece passkey y se bloquea con error en lugar de solicitar la contraseña.
/// Ocultar esta API hace que Google use el flujo estándar de inicio de sesión por contraseña/2FA.
enum LoginPasskeySuppression {
    static let scriptSource = """
    (function () {
        "use strict";
        try {
            delete window.PublicKeyCredential;
            Object.defineProperty(window, "PublicKeyCredential", {
                value: undefined,
                writable: false,
                configurable: false,
            });
        } catch (error) {}
        try {
            var credentials = window.navigator && window.navigator.credentials;
            if (!credentials) {
                return;
            }
            var prototype = Object.getPrototypeOf(credentials);
            var wrap = function (original) {
                if (typeof original !== "function") {
                    return original;
                }
                return function (options) {
                    if (options && options.publicKey) {
                        return Promise.reject(new DOMException(
                            "Passkeys are not available in this app.",
                            "NotAllowedError"
                        ));
                    }
                    return original.apply(this, arguments);
                };
            };
            prototype.get = wrap(prototype.get);
            prototype.create = wrap(prototype.create);
        } catch (error) {}
    })();
    """

    @MainActor
    static func makeUserScript() -> WKUserScript {
        WKUserScript(
            source: self.scriptSource,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }
}
