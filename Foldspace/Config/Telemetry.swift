import Foundation
#if canImport(Sentry)
import Sentry
#endif

/// Thin wrapper over Sentry for crash / error monitoring.
///
/// Every call is a no-op when `Secrets.hasSentry` is false (or the Sentry package is not linked),
/// so gameplay code can sprinkle breadcrumbs freely without ever depending on telemetry being set up.
/// `SentrySDK.start` itself happens in `FoldspaceApp.init`.
enum Telemetry {
    /// Records a breadcrumb — a timeline entry attached to any later crash or error report.
    /// `GameStore.log(_:_:)` calls this with the log kind as the category.
    static func breadcrumb(_ msg: String, category: String) {
        #if canImport(Sentry)
        guard Secrets.hasSentry else { return }
        let crumb = Breadcrumb()
        crumb.level = .info
        crumb.category = category
        crumb.message = msg
        SentrySDK.addBreadcrumb(crumb)
        #endif
    }

    /// Reports a handled error (network failures excepted — those are breadcrumbs, not bugs).
    static func capture(_ error: Error, context: String) {
        #if canImport(Sentry)
        guard Secrets.hasSentry else { return }
        if error is URLError {
            breadcrumb("\(context): \(error.localizedDescription)", category: "network")
            return
        }
        breadcrumb(context, category: "error")
        SentrySDK.capture(error: error)
        #endif
    }

    /// Sends a plain informational message (used once per launch for the sponsor-stack summary).
    static func message(_ text: String) {
        #if canImport(Sentry)
        guard Secrets.hasSentry else { return }
        SentrySDK.capture(message: text)
        #endif
    }
}
