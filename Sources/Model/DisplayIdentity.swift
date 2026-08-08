import Foundation

/// Durable, privacy-safe monitor characteristics. The live Core Graphics UUID remains the
/// strongest identity; hardware fields are a conservative reconnect fallback when macOS or a dock
/// presents the same physical panel under a different runtime UUID.
struct DisplayFingerprint: Codable, Equatable, Hashable, Sendable {
    let displayUUID: String?
    let vendorID: UInt32?
    let modelID: UInt32?
    let serialNumber: String?
    let displayName: String?
    let widthPoints: Int?
    let heightPoints: Int?

    init(
        displayUUID: String? = nil,
        vendorID: UInt32? = nil,
        modelID: UInt32? = nil,
        serialNumber: String? = nil,
        displayName: String? = nil,
        widthPoints: Int? = nil,
        heightPoints: Int? = nil
    ) {
        self.displayUUID = displayUUID
        self.vendorID = vendorID
        self.modelID = modelID
        self.serialNumber = serialNumber
        self.displayName = displayName
        self.widthPoints = widthPoints
        self.heightPoints = heightPoints
    }

    /// Name or size alone is deliberately insufficient: it would silently conflate common panels.
    var hasPortableHardwareIdentity: Bool {
        serialNumber?.isEmpty == false || (vendorID != nil && modelID != nil)
    }

    func portableMatches(_ candidate: DisplayFingerprint) -> Bool {
        guard hasPortableHardwareIdentity else { return false }
        if let vendorID, candidate.vendorID != vendorID { return false }
        if let modelID, candidate.modelID != modelID { return false }
        if let serialNumber, !serialNumber.isEmpty {
            return candidate.serialNumber == serialNumber
        }
        // Without a serial, vendor/model identify only a product line. Name and point dimensions
        // narrow the candidate set, while the resolver still refuses two identical live matches.
        if let displayName, !displayName.isEmpty,
           candidate.displayName?.localizedCaseInsensitiveCompare(displayName) != .orderedSame {
            return false
        }
        if let widthPoints, candidate.widthPoints != widthPoints { return false }
        if let heightPoints, candidate.heightPoints != heightPoints { return false }
        return true
    }
}

struct WorkspaceDisplayPin: Codable, Equatable, Sendable {
    let lastKnownIdentifier: String
    let fingerprint: DisplayFingerprint?
}

enum DisplayPinResolution: Equatable, Sendable {
    case exactIdentifier(String)
    case exactUUID(String)
    case portableFingerprint(String)
    case ambiguous
    case disconnected

    var displayIdentifier: String? {
        switch self {
        case let .exactIdentifier(identifier),
             let .exactUUID(identifier),
             let .portableFingerprint(identifier):
            identifier
        case .ambiguous, .disconnected:
            nil
        }
    }
}

enum DisplayIdentityResolver {
    static func resolve(
        _ pin: WorkspaceDisplayPin,
        among displays: [DisplaySnapshot]
    ) -> DisplayPinResolution {
        if displays.contains(where: { $0.identifier == pin.lastKnownIdentifier }) {
            return .exactIdentifier(pin.lastKnownIdentifier)
        }
        guard let fingerprint = pin.fingerprint else { return .disconnected }
        if let uuid = fingerprint.displayUUID,
           let exact = displays.first(where: {
               $0.fingerprint?.displayUUID?.caseInsensitiveCompare(uuid) == .orderedSame
           }) {
            return .exactUUID(exact.identifier)
        }
        guard fingerprint.hasPortableHardwareIdentity else { return .disconnected }
        let candidates = displays.filter { display in
            display.fingerprint.map(fingerprint.portableMatches) == true
        }
        if candidates.count == 1, let match = candidates.first {
            return .portableFingerprint(match.identifier)
        }
        return candidates.isEmpty ? .disconnected : .ambiguous
    }
}

struct WorkspaceDisplayMovePlan: Equatable, Sendable {
    let movingWorkspaceID: UUID
    let replacementWorkspaceID: UUID
    let sourceDisplayIdentifier: String
    let destinationDisplayIdentifier: String
    let changedAssignments: [UUID: String]
    let activeWorkspaceIDByDisplay: [String: UUID]
}
