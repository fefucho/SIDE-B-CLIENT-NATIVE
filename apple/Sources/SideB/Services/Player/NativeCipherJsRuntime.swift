import Foundation
import JavaScriptCore
import SideBCore

/// Executes the fetched YouTube player script for signature and n transforms. JavaScriptCore has
/// no network bridge here; the small browser shims let the player's pure cipher functions load.
final class NativeCipherJsRuntime: CipherJsRuntime, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.sideb.cipher-js")
    private var context: JSContext?

    func load(script: String) -> Bool {
        queue.sync {
            let context = JSContext()
            context?.exceptionHandler = { _, error in
                if let error { print("[Cipher] JavaScript error: \(error.toString() ?? "unknown")") }
            }
            context?.evaluateScript("""
                var window=this; var self=this; var _yt_player={};
                var location={href:'https://www.youtube.com/',hostname:'www.youtube.com',protocol:'https:'};
                window.location=location;
                var navigator={userAgent:'Mozilla/5.0'};
                var document={createElement:function(){return {style:{},setAttribute:function(){},appendChild:function(){}}},
                    documentElement:{appendChild:function(){}},body:{appendChild:function(){}},addEventListener:function(){}};
                var XMLHttpRequest=function(){this.open=function(){};this.send=function(){};this.setRequestHeader=function(){}};
                """)
            context?.evaluateScript(script)
            guard context?.evaluateScript("typeof window._cipherSigFunc")?.toString() == "function" else {
                self.context = nil
                return false
            }
            self.context = context
            return true
        }
    }

    func evaluate(expression: String) -> String? {
        queue.sync {
            guard let context else { return nil }
            let result = context.evaluateScript(expression)
            guard let result, !result.isUndefined, !result.isNull else { return nil }
            return result.toString()
        }
    }
}
