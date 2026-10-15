import Foundation
import PulseLoomCore

/// Translate at presentation boundaries. Raw SDK descriptions must not appear in user alerts.
enum UserFacingError {
    static func message(_ error: Error, fallback: String = "error.operation") -> String {
        let detail = error.localizedDescription
        if let key = details[detail] { return T(key) }
        // Keep existing localized, actionable messages; never guess a language from arbitrary text.
        for table in ["Localizable", "Recovery"] {
            for language in ["en", "zh-Hans", "ja"] {
                if let path = Bundle.main.path(forResource: table, ofType: "strings", inDirectory: nil, forLocalization: language),
                   let strings = NSDictionary(contentsOfFile: path) as? [String: String],
                   let key = strings.first(where: { $0.value == detail })?.key {
                    return AppLanguage.bundle.localizedString(forKey: key, value: nil, table: table)
                }
            }
        }
        if detail.hasPrefix("Haptic shutdown is not confirmed:") { return T("error.outputStopping") }
        if detail.hasPrefix("Haptic engine stopped:") { return T("error.interruption") }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return T("error.network") }
        if ns.domain == NSCocoaErrorDomain {
            if ns.code == NSUserCancelledError { return T("error.cancelled") }
            if ns.code == NSFileWriteOutOfSpaceError { return T("error.diskFull") }
            return T("error.file")
        }
        if let loom = error as? LoomError {
            switch loom {
            case .entitlement: return T("error.proRequired")
            case .storage: return T("error.storage")
            case .invalid: return T("error.invalidInput")
            case .unavailable: return T(fallback)
            }
        }
        return T(fallback)
    }
    static func isOutputMessage(_ message: String) -> Bool {
        ["error.outputUnavailable", "error.controllerDisconnected", "error.controllerUnsupported",
         "error.outputStart", "error.outputStopping", "error.unsupported", "error.hapticsUnavailable"]
            .contains { T($0) == message }
    }
    private static let details: [String: String] = [
        "No haptic output is available.": "error.outputUnavailable",
        "Output changed. Playback stopped; start again.": "error.interruption",
        "Controller disconnected. Playback stopped; select output and restart.": "error.controllerDisconnected",
        "iPhone Core Haptics unavailable.": "error.outputUnavailable",
        "Selected controller is disconnected.": "error.controllerDisconnected",
        "Controller disconnected before playback.": "error.controllerDisconnected",
        "Selected controller has no public haptic output.": "error.controllerUnsupported",
        "Could not create controller haptic engine.": "error.outputStart",
        "Haptic engine could not be prepared.": "error.outputStart",
        "Haptic engine unavailable.": "error.outputStart",
        "Haptic shutdown is not confirmed.": "error.outputStopping",
        "Haptic shutdown is not confirmed. Stop again before restarting.": "error.outputStopping",
        "Previous output shutdown unconfirmed. Wait before restarting.": "error.outputStopping",
        "Previous output stop could not be confirmed.": "error.outputStopping",
        "Audio could not be prepared.": "error.audioRead",
        "Audio could not start.": "error.audioStart",
        "Audio must be at most 30 MB.": "error.audioSize",
        "Audio must be no longer than 10 minutes.": "error.audioLength",
        "Audio exceeds 10 minutes.": "error.audioLength",
        "Empty audio.": "error.audioRead",
        "Audio buffer allocation failed.": "error.audioRead",
        "Unsupported sample rate.": "error.audioRead",
        "Audio contains invalid samples.": "error.audioRead",
        "Name must contain 1–30 characters.": "error.name",
        "A pattern needs at least one nonzero segment.": "error.emptyPattern",
        "Cloud sync is off.": "error.syncOff",
        "Cloud sync is off. No cloud deletion was requested.": "error.syncOff",
        "CloudKit container is not configured.": "error.syncUnavailable",
        "A sync is already in progress.": "error.syncBusy",
        "No sync conflict is pending.": "error.syncConflict",
        "Remote authorization is not current.": "error.remoteConsent",
        "Stop the local session before granting remote output.": "error.remoteLocal",
        "The remote connection does not own the current output.": "error.remoteConsent",
        "The previous music request is still ending. Try again shortly.": "error.outputStopping",
        "Transaction could not be verified.": "purchase.unavailable"
    ]
}
