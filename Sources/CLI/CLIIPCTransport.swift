import Darwin
import Foundation
import Security

enum CLIIPCTransport {
    static let maximumMessageBytes = WindowRangerCLIProtocol.maximumMessageBytes
    static let defaultTimeout: TimeInterval = 3

    static func socketPath(userID: uid_t = getuid()) -> String {
        "/tmp/dev.appranger.WindowRanger.cli.v1.\(userID).sock"
    }
}

enum CLIIPCTransportError: Error, Equatable, LocalizedError {
    case invalidSocketPath
    case addressInUse
    case unavailable
    case timedOut
    case messageTooLarge
    case malformedFrame
    case disconnected
    case systemCall(String, Int32)
    case peerUserMismatch
    case peerProcessUnavailable
    case peerSignatureRejected
    case peerPathRejected

    var errorDescription: String? {
        switch self {
        case .invalidSocketPath: "The WindowRanger command socket path is invalid."
        case .addressInUse: "Another WindowRanger command service is already running."
        case .unavailable: "WindowRanger is not available."
        case .timedOut: "WindowRanger did not reply before the deadline."
        case .messageTooLarge: "The WindowRanger command message exceeds the supported limit."
        case .malformedFrame: "WindowRanger returned a malformed command message."
        case .disconnected: "The WindowRanger command connection closed unexpectedly."
        case let .systemCall(name, code): "\(name) failed with error \(code)."
        case .peerUserMismatch: "The WindowRanger command peer belongs to another user."
        case .peerProcessUnavailable: "The WindowRanger command peer process could not be verified."
        case .peerSignatureRejected: "The WindowRanger command peer has an unexpected code signature."
        case .peerPathRejected: "The WindowRanger command peer is not the bundled executable."
        }
    }
}

struct CLIIPCPeerPolicy: Sendable {
    static let teamIdentifier = "44NAD22AK6"

    let codeIdentifier: String
    let executableURL: URL
    let teamIdentifier: String

    init(
        codeIdentifier: String,
        executableURL: URL,
        teamIdentifier: String = Self.teamIdentifier
    ) {
        self.codeIdentifier = codeIdentifier
        self.executableURL = executableURL
        self.teamIdentifier = teamIdentifier
    }

    func verify(socket: Int32) throws {
        var peerUserID: uid_t = 0
        var peerGroupID: gid_t = 0
        guard getpeereid(socket, &peerUserID, &peerGroupID) == 0 else {
            throw CLIIPCTransportError.systemCall("getpeereid", errno)
        }
        guard peerUserID == getuid() else {
            throw CLIIPCTransportError.peerUserMismatch
        }

        var peerProcessIdentifier: pid_t = 0
        var peerProcessIdentifierLength = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(
            socket,
            SOL_LOCAL,
            LOCAL_PEERPID,
            &peerProcessIdentifier,
            &peerProcessIdentifierLength
        ) == 0, peerProcessIdentifier > 0 else {
            throw CLIIPCTransportError.peerProcessUnavailable
        }

        let attributes = [
            kSecGuestAttributePid as String: NSNumber(value: peerProcessIdentifier),
        ] as CFDictionary
        var dynamicCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &dynamicCode) == errSecSuccess,
              let dynamicCode else {
            throw CLIIPCTransportError.peerProcessUnavailable
        }

        let requirementText = "identifier \"\(codeIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            requirementText as CFString,
            [],
            &requirement
        ) == errSecSuccess,
              let requirement,
              SecCodeCheckValidity(dynamicCode, [], requirement) == errSecSuccess else {
            throw CLIIPCTransportError.peerSignatureRejected
        }

        var staticCode: SecStaticCode?
        var codeURL: CFURL?
        guard SecCodeCopyStaticCode(dynamicCode, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecCodeCopyPath(staticCode, [], &codeURL) == errSecSuccess,
              let codeURL else {
            throw CLIIPCTransportError.peerProcessUnavailable
        }
        let observedURL = (codeURL as URL).standardizedFileURL.resolvingSymlinksInPath()
        let expectedURL = executableURL.standardizedFileURL.resolvingSymlinksInPath()
        guard observedURL == expectedURL else {
            throw CLIIPCTransportError.peerPathRejected
        }
    }
}

final class CLIIPCServer {
    typealias PeerVerifier = @Sendable (Int32) throws -> Void
    typealias Handler = @Sendable (Data) -> Data
    typealias AsyncHandler = @Sendable (Data, @escaping @Sendable (Data) -> Void) -> Void

    private let socketPath: String
    private let peerVerifier: PeerVerifier
    private let handler: AsyncHandler
    private let queue: DispatchQueue
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?

    init(
        socketPath: String = CLIIPCTransport.socketPath(),
        peerPolicy: CLIIPCPeerPolicy,
        handler: @escaping Handler
    ) {
        self.socketPath = socketPath
        peerVerifier = { try peerPolicy.verify(socket: $0) }
        self.handler = { request, completion in completion(handler(request)) }
        queue = DispatchQueue(label: "dev.appranger.WindowRanger.cli-server", qos: .userInitiated)
    }

    init(
        socketPath: String = CLIIPCTransport.socketPath(),
        peerPolicy: CLIIPCPeerPolicy,
        asyncHandler: @escaping AsyncHandler
    ) {
        self.socketPath = socketPath
        peerVerifier = { try peerPolicy.verify(socket: $0) }
        handler = asyncHandler
        queue = DispatchQueue(label: "dev.appranger.WindowRanger.cli-server", qos: .userInitiated)
    }

    init(
        socketPath: String,
        peerVerifier: @escaping PeerVerifier,
        handler: @escaping Handler
    ) {
        self.socketPath = socketPath
        self.peerVerifier = peerVerifier
        self.handler = { request, completion in completion(handler(request)) }
        queue = DispatchQueue(label: "dev.appranger.WindowRanger.cli-server", qos: .userInitiated)
    }

    init(
        socketPath: String,
        peerVerifier: @escaping PeerVerifier,
        asyncHandler: @escaping AsyncHandler
    ) {
        self.socketPath = socketPath
        self.peerVerifier = peerVerifier
        handler = asyncHandler
        queue = DispatchQueue(label: "dev.appranger.WindowRanger.cli-server", qos: .userInitiated)
    }

    func start() throws {
        guard listener < 0 else { return }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw CLIIPCTransportError.systemCall("socket", errno)
        }
        do {
            try Self.prepareSocketPath(socketPath)
            try Self.bind(descriptor, to: socketPath)
            guard chmod(socketPath, S_IRUSR | S_IWUSR) == 0 else {
                throw CLIIPCTransportError.systemCall("chmod", errno)
            }
            guard listen(descriptor, 16) == 0 else {
                throw CLIIPCTransportError.systemCall("listen", errno)
            }
        } catch {
            close(descriptor)
            throw error
        }

        listener = descriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptAvailableConnection() }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }

    func stop() {
        guard listener >= 0 else { return }
        source?.cancel()
        source = nil
        listener = -1
        Self.removeOwnedSocket(at: socketPath)
    }

    deinit {
        stop()
    }

    private func acceptAvailableConnection() {
        guard listener >= 0 else { return }
        let connection = accept(listener, nil, nil)
        guard connection >= 0 else { return }
        Self.applyDeadline(CLIIPCTransport.defaultTimeout, to: connection)
        queue.async { [peerVerifier, handler] in
            do {
                try peerVerifier(connection)
                let request = try Self.readFrame(from: connection)
                let responder = CLIIPCConnectionResponder(descriptor: connection)
                handler(request) { response in responder.finish(response) }
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + CLIIPCTransport.defaultTimeout
                ) {
                    responder.cancel()
                }
            } catch {
                close(connection)
                // The command codec owns user-visible errors. Transport/authentication failures
                // deliberately close the connection without returning attacker-controlled detail.
            }
        }
    }

    private static func applyDeadline(_ timeout: TimeInterval, to descriptor: Int32) {
        var deadline = timeval(
            tv_sec: Int(timeout),
            tv_usec: Int32((timeout - floor(timeout)) * 1_000_000)
        )
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &deadline,
            socklen_t(MemoryLayout<timeval>.size)
        )
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_SNDTIMEO,
            &deadline,
            socklen_t(MemoryLayout<timeval>.size)
        )
    }

    private static func prepareSocketPath(_ path: String) throws {
        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw CLIIPCTransportError.invalidSocketPath
        }
        var status = stat()
        guard lstat(path, &status) == 0 else {
            if errno == ENOENT { return }
            throw CLIIPCTransportError.systemCall("lstat", errno)
        }
        guard status.st_uid == getuid(), status.st_mode & S_IFMT == S_IFSOCK else {
            throw CLIIPCTransportError.invalidSocketPath
        }

        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        if probe >= 0 {
            defer { close(probe) }
            if (try? connect(probe, to: path)) != nil {
                throw CLIIPCTransportError.addressInUse
            }
        }
        guard unlink(path) == 0 else {
            throw CLIIPCTransportError.systemCall("unlink", errno)
        }
    }

    private static func removeOwnedSocket(at path: String) {
        var status = stat()
        guard lstat(path, &status) == 0,
              status.st_uid == getuid(),
              status.st_mode & S_IFMT == S_IFSOCK else { return }
        _ = unlink(path)
    }

    fileprivate static func connect(_ descriptor: Int32, to path: String) throws {
        var address = try socketAddress(path: path)
        let addressLength = socklen_t(address.sun_len)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, addressLength)
            }
        }
        guard result == 0 else {
            if errno == ENOENT || errno == ECONNREFUSED { throw CLIIPCTransportError.unavailable }
            throw CLIIPCTransportError.systemCall("connect", errno)
        }
    }

    private static func bind(_ descriptor: Int32, to path: String) throws {
        var address = try socketAddress(path: path)
        let addressLength = socklen_t(address.sun_len)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, addressLength)
            }
        }
        guard result == 0 else {
            throw CLIIPCTransportError.systemCall("bind", errno)
        }
    }

    private static func socketAddress(path: String) throws -> sockaddr_un {
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw CLIIPCTransportError.invalidSocketPath
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sa_family_t>.size + 1 + bytes.count + 1)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            destination.copyBytes(from: bytes)
        }
        return address
    }

    fileprivate static func readFrame(from descriptor: Int32) throws -> Data {
        let header = try readExactly(MemoryLayout<UInt32>.size, from: descriptor)
        let length = header.withUnsafeBytes { rawBuffer -> UInt32 in
            rawBuffer.loadUnaligned(as: UInt32.self).bigEndian
        }
        guard length <= CLIIPCTransport.maximumMessageBytes else {
            throw CLIIPCTransportError.messageTooLarge
        }
        return try readExactly(Int(length), from: descriptor)
    }

    fileprivate static func writeFrame(_ data: Data, to descriptor: Int32) throws {
        guard data.count <= CLIIPCTransport.maximumMessageBytes else {
            throw CLIIPCTransportError.messageTooLarge
        }
        var length = UInt32(data.count).bigEndian
        try withUnsafeBytes(of: &length) { try writeAll(Data($0), to: descriptor) }
        try writeAll(data, to: descriptor)
    }

    private static func readExactly(_ count: Int, from descriptor: Int32) throws -> Data {
        guard count > 0 else { return Data() }
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let readCount = data.withUnsafeMutableBytes { buffer in
                Darwin.read(descriptor, buffer.baseAddress!.advanced(by: offset), count - offset)
            }
            if readCount == 0 { throw CLIIPCTransportError.disconnected }
            if readCount < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { throw CLIIPCTransportError.timedOut }
                throw CLIIPCTransportError.systemCall("read", errno)
            }
            offset += readCount
        }
        return data
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { buffer in
                Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), data.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { throw CLIIPCTransportError.timedOut }
                throw CLIIPCTransportError.systemCall("write", errno)
            }
            offset += written
        }
    }
}

private final class CLIIPCConnectionResponder: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32?

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    func finish(_ response: Data) {
        guard let descriptor = takeDescriptor() else { return }
        defer { close(descriptor) }
        try? CLIIPCServer.writeFrame(response, to: descriptor)
    }

    func cancel() {
        guard let descriptor = takeDescriptor() else { return }
        close(descriptor)
    }

    private func takeDescriptor() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        defer { descriptor = nil }
        return descriptor
    }
}

struct CLIIPCClient {
    typealias PeerVerifier = (Int32) throws -> Void

    let socketPath: String
    let peerVerifier: PeerVerifier
    let timeout: TimeInterval

    init(
        socketPath: String = CLIIPCTransport.socketPath(),
        peerPolicy: CLIIPCPeerPolicy,
        timeout: TimeInterval = CLIIPCTransport.defaultTimeout
    ) {
        self.socketPath = socketPath
        peerVerifier = { try peerPolicy.verify(socket: $0) }
        self.timeout = timeout
    }

    init(socketPath: String, timeout: TimeInterval, peerVerifier: @escaping PeerVerifier) {
        self.socketPath = socketPath
        self.timeout = timeout
        self.peerVerifier = peerVerifier
    }

    func send(_ request: Data) throws -> Data {
        guard request.count <= CLIIPCTransport.maximumMessageBytes else {
            throw CLIIPCTransportError.messageTooLarge
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw CLIIPCTransportError.systemCall("socket", errno)
        }
        defer { close(descriptor) }
        var deadline = timeval(
            tv_sec: Int(timeout),
            tv_usec: Int32((timeout - floor(timeout)) * 1_000_000)
        )
        _ = setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &deadline, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &deadline, socklen_t(MemoryLayout<timeval>.size))
        try CLIIPCServer.connect(descriptor, to: socketPath)
        try peerVerifier(descriptor)
        try CLIIPCServer.writeFrame(request, to: descriptor)
        return try CLIIPCServer.readFrame(from: descriptor)
    }
}
