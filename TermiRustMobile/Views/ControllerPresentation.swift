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

    static func lifecycleLabel(_ lifecycle: String) -> LocalizedStringKey {
        switch lifecycle {
        case "draft": return "Draft"
        case "validating": return "Validating"
        case "starting": return "Starting"
        case "provisioning": return "Provisioning"
        case "attaching": return "Attaching"
        case "replaying": return "Replaying"
        case "live", "running", "running_app_attached": return "Live"
        case "recording_paused": return "Recording paused"
        case "stopping": return "Stopping"
        case "offline": return "Offline"
        case "orphaned": return "Orphaned"
        case "gap": return "Output gap"
        case "permission_denied": return "Permission denied"
        case "incompatible": return "Incompatible"
        case "failed": return "Failed"
        case "cancelled": return "Cancelled"
        case "exited", "stopped": return "Exited"
        default: return "Unknown"
        }
    }

    static func activityLabel(_ activity: String) -> LocalizedStringKey {
        switch activity {
        case "idle": return "Idle"
        case "busy": return "Busy"
        case "needs_input": return "Needs input"
        case "done": return "Done"
        case "failed": return "Failed"
        default: return "Activity unknown"
        }
    }
}
