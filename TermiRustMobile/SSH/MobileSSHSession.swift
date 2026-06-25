import Foundation

enum MobileSSHError: Error, LocalizedError {
    case missingCredential(MobileAuthKind)
    case hostKeyNotPinned
    case hostKeyMismatch
    case directClientNotWired

    var errorDescription: String? {
        switch self {
        case .missingCredential(let kind):
            return "Missing \(kind.rawValue) credential for this host."
        case .hostKeyNotPinned:
            return "No known-host pin exists for this endpoint."
        case .hostKeyMismatch:
            return "Host key mismatch. Connection blocked."
        case .directClientNotWired:
            return "Direct SwiftNIO SSH transport is scaffolded but not wired yet."
        }
    }
}

enum TerminalConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

protocol MobileSSHConnecting: Sendable {
    func connect(host: MobileHost, knownHost: MobileKnownHost?) async throws
    func send(_ bytes: Data) async throws
    func resize(columns: Int, rows: Int) async throws
    func disconnect() async
}

final class DirectSSHSessionClient: MobileSSHConnecting, @unchecked Sendable {
    func connect(host: MobileHost, knownHost: MobileKnownHost?) async throws {
        guard knownHost != nil else {
            throw MobileSSHError.hostKeyNotPinned
        }
        _ = TmuxBootstrap(host: host).startupCommand()
        throw MobileSSHError.directClientNotWired
    }

    func send(_ bytes: Data) async throws {
        _ = bytes
        throw MobileSSHError.directClientNotWired
    }

    func resize(columns: Int, rows: Int) async throws {
        _ = (columns, rows)
        throw MobileSSHError.directClientNotWired
    }

    func disconnect() async {}
}
