import Foundation
import XCTest
@testable import TermiRustMobile

final class DirectSSHIntegrationTests: XCTestCase {
    func testDirectSSHAttachesToPersistentTmuxSessionAndSurvivesReconnect() async throws {
        let hostName = env("TERMIRUST_MOBILE_TEST_SSH_HOST")
        let port = UInt16(env("TERMIRUST_MOBILE_TEST_SSH_PORT"))
        let username = env("TERMIRUST_MOBILE_TEST_SSH_USER")
        let privateKey = env("TERMIRUST_MOBILE_TEST_SSH_KEY")
        let knownHostKey = env("TERMIRUST_MOBILE_TEST_KNOWN_HOST_KEY")
        guard !hostName.isEmpty,
              let port,
              !username.isEmpty,
              !privateKey.isEmpty,
              !knownHostKey.isEmpty else {
            throw XCTSkip(
                "Set TERMIRUST_MOBILE_TEST_SSH_HOST, TERMIRUST_MOBILE_TEST_SSH_PORT, TERMIRUST_MOBILE_TEST_SSH_USER, TERMIRUST_MOBILE_TEST_SSH_KEY, and TERMIRUST_MOBILE_TEST_KNOWN_HOST_KEY to run this live SSH smoke."
            )
        }

        let sessionName = "mobile-ios-smoke"
        let secretRef = "termirust-mobile-test-private-key"
        let host = MobileHost(
            id: "ios-live-ssh",
            label: "iOS Live SSH",
            vaultId: nil,
            group: "",
            tags: [],
            host: hostName,
            port: port,
            username: username,
            auth: MobileAuthMetadata(
                kind: .privateKey,
                identityId: nil,
                secretRef: secretRef
            ),
            jumpHostId: nil,
            startupDirectory: nil,
            startupCommand: nil,
            startInFiles: false,
            persistentSession: MobilePersistentSession(
                enabled: true,
                sessionName: sessionName,
                detachOthers: false
            ),
            terminalScrollbackRows: nil,
            colorTag: nil,
            environment: [],
            knownHostEndpoint: "\(hostName):\(port)"
        )
        let knownHost = MobileKnownHost(
            endpoint: "\(hostName):\(port)",
            publicKey: knownHostKey,
            algorithm: nil,
            fingerprint: nil
        )

        let firstOutput = OutputCapture()
        let firstClient = DirectSSHSessionClient(
            secretStore: StaticSecretStore(account: secretRef, secret: privateKey)
        )
        do {
            try await firstClient.connect(host: host, knownHost: knownHost) { data in
                firstOutput.append(data)
            }
            try await firstClient.send(Data("tmux display-message -p '#S'\n".utf8))
            try await firstClient.send(Data("echo ios-smoke-first > ~/termirust-ios-smoke\n".utf8))
            let attachedToSession = await firstOutput.waitFor(sessionName)
            XCTAssertTrue(
                attachedToSession,
                "first connection did not attach to the expected tmux session"
            )
        } catch {
            await firstClient.disconnect()
            throw error
        }
        await firstClient.disconnect()

        let secondOutput = OutputCapture()
        let secondClient = DirectSSHSessionClient(
            secretStore: StaticSecretStore(account: secretRef, secret: privateKey)
        )
        do {
            try await secondClient.connect(host: host, knownHost: knownHost) { data in
                secondOutput.append(data)
            }
            try await secondClient.send(Data("cat ~/termirust-ios-smoke\n".utf8))
            let sawPersistentMarker = await secondOutput.waitFor("ios-smoke-first")
            XCTAssertTrue(
                sawPersistentMarker,
                "reconnect did not see marker created inside the persistent tmux session"
            )
        } catch {
            await secondClient.disconnect()
            throw error
        }
        await secondClient.disconnect()
    }

    private func env(_ name: String) -> String {
        ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private final class OutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [Data] = []

    func append(_ data: Data) {
        lock.lock()
        chunks.append(data)
        lock.unlock()
    }

    func text() -> String {
        lock.lock()
        defer { lock.unlock() }
        return chunks
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined()
    }

    func waitFor(_ needle: String, attempts: Int = 80) async -> Bool {
        for _ in 0..<attempts {
            if text().contains(needle) {
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }
}

private final class StaticSecretStore: SecretStoring {
    let account: String
    let secret: String

    init(account: String, secret: String) {
        self.account = account
        self.secret = secret
    }

    func saveSecret(_ secret: String, account: String) throws {}

    func readSecret(account: String) throws -> String? {
        account == self.account ? secret : nil
    }

    func deleteSecret(account: String) throws {}
}
