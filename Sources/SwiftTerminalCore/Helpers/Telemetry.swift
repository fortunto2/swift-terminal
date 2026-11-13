import Foundation

/// The seam between the library and the analytics client. The core target does not link the
/// analytics package; the app installs a sink at launch. Whatever goes through here is a fixed
/// event name plus values from a closed set (an enum raw value or a duration bucket). Never a
/// host, an address, a user name, a port, a key name, a path, or anything shown or typed in
/// the terminal.
public enum Telemetry {
    nonisolated(unsafe) public static var sink: (@Sendable (String, [String: String]) -> Void)?

    public static func track(_ name: String, _ props: [String: String] = [:]) {
        sink?(name, props)
    }

    public enum FailureReason: String, Sendable {
        case auth, network, timeout, other
    }

    /// Coarse class of a connection failure. Looks only at the error's type and domain.
    public static func failureReason(_ error: Error) -> FailureReason {
        if let ssh = error as? SSHServiceError {
            switch ssh {
            case .authenticationFailed: return .auth
            case .connectionTimeout: return .timeout
            default: return .other
            }
        }
        let raw = "\(type(of: error)) \((error as NSError).domain) \(error)"
        if raw.contains("connectTimeout") { return .timeout }
        if raw.contains("NIOConnectionError") || raw.contains("ChannelError") { return .network }
        if raw.localizedCaseInsensitiveContains("authentication") { return .auth }
        return .other
    }

    /// Length of a connected session, in buckets so no exact timing leaves the device.
    public static func durationBucket(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: "lt_1m"
        case ..<600: "1_10m"
        case ..<3600: "10_60m"
        default: "gt_1h"
        }
    }
}
