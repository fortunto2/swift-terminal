import Foundation
#if canImport(UIKit)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// One place for "put this on the clipboard".
///
/// The two-line AppKit dance (`clearContents()` then `setString(_:forType:)`) was copied into
/// every view that offers a copy button, each behind its own `#if`, and the iOS half was drifting
/// separately. Copying a public key is the app's most-used affordance — it deserves one function.
public enum Pasteboard {
    public static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
