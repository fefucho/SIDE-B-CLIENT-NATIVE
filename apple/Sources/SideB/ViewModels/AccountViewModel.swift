import Foundation
import Observation
import SideBCore

@MainActor
@Observable
final class AccountViewModel {
    var account: AccountInfoRecord?
    var isLoggedIn: Bool = false
    var isLoading: Bool = false
    var errorMessage: String?

    init() {}

    /// Instala la sesión antes de que Inicio haga su primera consulta.
    @discardableResult
    func restoreSession(core: SideBCore, storage: CookieStorage) -> Bool {
        if let cookie = storage.getSessionCookie(), !cookie.isEmpty {
            core.setCookie(cookie: cookie)
            self.isLoggedIn = true
            return true
        } else {
            core.setCookie(cookie: nil)
            self.isLoggedIn = false
            self.account = nil
            return false
        }
    }

    /// Obtiene la información del perfil del usuario logueado mediante InnerTube account_menu.
    func fetchAccount(core: SideBCore) async {
        self.isLoading = true
        self.errorMessage = nil
        do {
            let info = try await core.getAccountInfo()
            self.account = info
            self.isLoggedIn = true
        } catch {
            print("[AccountViewModel] Error al obtener información de cuenta: \(error)")
            self.errorMessage = error.localizedDescription
            // Si la llamada falla porque la sesión caducó, marcamos como deslogueado
            if !core.isLoggedIn() {
                self.isLoggedIn = false
                self.account = nil
            }
        }
        self.isLoading = false
    }

    /// Cierra la sesión: purga el Keychain de Apple, limpia cookies en Rust Core y resetea la UI.
    func logout(core: SideBCore, storage: CookieStorage, onLoggedOut: (() -> Void)? = nil) {
        storage.removeSessionCookie()
        core.setCookie(cookie: nil)
        self.account = nil
        self.isLoggedIn = false
        self.errorMessage = nil
        onLoggedOut?()
    }
}
