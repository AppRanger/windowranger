import Foundation
import XCTest

final class CLIIPCTransportTests: XCTestCase {
    func testRoundTripUsesBoundedLengthPrefixedMessages() throws {
        let socketPath = temporarySocketPath()
        let server = CLIIPCServer(
            socketPath: socketPath,
            peerVerifier: { _ in },
            handler: { Data($0.reversed()) }
        )
        try server.start()
        defer { server.stop() }

        let client = CLIIPCClient(
            socketPath: socketPath,
            timeout: 1,
            peerVerifier: { _ in }
        )
        let request = Data("windowranger".utf8)

        XCTAssertEqual(try client.send(request), Data(request.reversed()))
    }

    func testConfigurationSizedMessageRoundTripsAboveLegacyLimit() throws {
        let socketPath = temporarySocketPath()
        let server = CLIIPCServer(
            socketPath: socketPath,
            peerVerifier: { _ in },
            handler: { $0 }
        )
        try server.start()
        defer { server.stop() }
        let client = CLIIPCClient(
            socketPath: socketPath,
            timeout: 1,
            peerVerifier: { _ in }
        )
        let request = Data(repeating: 65, count: 128 * 1_024)

        XCTAssertEqual(try client.send(request), request)
    }

    func testAsyncHandlerKeepsConnectionOpenUntilCompletion() throws {
        let socketPath = temporarySocketPath()
        let server = CLIIPCServer(
            socketPath: socketPath,
            peerVerifier: { _ in },
            asyncHandler: { request, completion in
                DispatchQueue.global().async {
                    completion(Data(request.reversed()))
                }
            }
        )
        try server.start()
        defer { server.stop() }
        let client = CLIIPCClient(
            socketPath: socketPath,
            timeout: 1,
            peerVerifier: { _ in }
        )
        let request = Data("asynchronous".utf8)

        XCTAssertEqual(try client.send(request), Data(request.reversed()))
    }

    func testClientRejectsOversizedRequestBeforeConnecting() {
        let client = CLIIPCClient(
            socketPath: temporarySocketPath(),
            timeout: 1,
            peerVerifier: { _ in }
        )

        XCTAssertThrowsError(
            try client.send(Data(count: CLIIPCTransport.maximumMessageBytes + 1))
        ) { error in
            XCTAssertEqual(error as? CLIIPCTransportError, .messageTooLarge)
        }
    }

    func testServerDoesNotReplaceForeignFilesystemEntry() throws {
        let socketPath = temporarySocketPath()
        try Data("keep".utf8).write(to: URL(fileURLWithPath: socketPath))
        let server = CLIIPCServer(
            socketPath: socketPath,
            peerVerifier: { _ in },
            handler: { $0 }
        )
        defer { try? FileManager.default.removeItem(atPath: socketPath) }

        XCTAssertThrowsError(try server.start()) { error in
            XCTAssertEqual(error as? CLIIPCTransportError, .invalidSocketPath)
        }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: socketPath)), Data("keep".utf8))
    }

    func testPeerRejectionClosesWithoutReturningDetails() throws {
        let socketPath = temporarySocketPath()
        let server = CLIIPCServer(
            socketPath: socketPath,
            peerVerifier: { _ in throw CLIIPCTransportError.peerSignatureRejected },
            handler: { _ in XCTFail("Rejected peer reached handler"); return Data() }
        )
        try server.start()
        defer { server.stop() }
        let client = CLIIPCClient(
            socketPath: socketPath,
            timeout: 1,
            peerVerifier: { _ in }
        )

        XCTAssertThrowsError(try client.send(Data("request".utf8)))
    }

    private func temporarySocketPath() -> String {
        "/tmp/wr-cli-test-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString.prefix(8)).sock"
    }
}
