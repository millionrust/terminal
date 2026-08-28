import Foundation
import SwiftUI

enum ControllerPresentation {
    static func isolated(_ value: String) -> String {
        "\u{2068}\(value)\u{2069}"
    }

    static func fingerprintForSpeech(_ fingerprint: String) -> String {
        fingerprint.map(String.init).joined(separator: " ")
    }

    static func unreadDescription(_ count: UInt32) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString("session.unread.count", comment: "Unread session activity count"),
            Int64(count)
        )
    }

    static func capabilityLabels(bits: UInt16) -> [LocalizedStringKey] {
        let known: [(UInt16, LocalizedStringKey)] = [
            (1 << 0, "View session list"),
            (1 << 1, "Attach to session output"),
            (1 << 2, "Send terminal input"),
            (1 << 3, "Resize terminal"),
            (1 << 4, "Respond to approvals"),
        ]
        return known.compactMap { bit, label in bits & bit == bit ? label : nil }
    }
}
