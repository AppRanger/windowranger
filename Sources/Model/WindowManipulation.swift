import CoreGraphics
import Foundation

enum WindowDirection: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case left
    case down
    case up
    case right

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .left: "arrow.left"
        case .down: "arrow.down"
        case .up: "arrow.up"
        case .right: "arrow.right"
        }
    }

    var axis: WorkspaceLayoutOrientation {
        switch self {
        case .left, .right: .horizontal
        case .up, .down: .vertical
        }
    }

    var orderOffset: Int {
        switch self {
        case .left, .up: -1
        case .right, .down: 1
        }
    }
}

enum DirectionalMoveGestureInput: Equatable, Sendable {
    case pressed(WindowDirection, correlationID: String)
    case released(WindowDirection)
    case timeout(correlationID: String)
    case cancel(reason: String, awaitRelease: Bool)
}

enum DirectionalMoveGestureEffect: Equatable, Sendable {
    case capture(correlationID: String, firstDirection: WindowDirection)
    case commitSingle(correlationID: String, direction: WindowDirection, reason: String)
    case commitCorner(correlationID: String, placement: VisualPlacement)
    case cancel(correlationID: String, reason: String)
}

enum DirectionalMoveGestureResolution: Hashable, Sendable {
    case single(WindowDirection)
    case corner(VisualPlacement)

    var diagnosticValue: String {
        switch self {
        case let .single(direction): "single-\(direction.rawValue)"
        case let .corner(placement): "corner-\(placement.rawValue)"
        }
    }
}

/// Pure recognizer for the four configurable directional-move shortcuts. The first press only
/// captures context; no layout command is emitted until a perpendicular partner arrives, the key
/// is released, or the bounded missing-release timeout fires.
struct DirectionalMoveGestureStateMachine: Equatable, Sendable {
    private enum Phase: Equatable, Sendable {
        case idle
        case pending(correlationID: String, firstDirection: WindowDirection)
        case awaitingRelease(Set<WindowDirection>)
    }

    private var phase: Phase = .idle

    var isPending: Bool {
        if case .pending = phase { return true }
        return false
    }

    var isIdle: Bool { phase == .idle }

    var pendingCorrelationID: String? {
        guard case let .pending(correlationID, _) = phase else { return nil }
        return correlationID
    }

    var pendingDirection: WindowDirection? {
        guard case let .pending(_, direction) = phase else { return nil }
        return direction
    }

    mutating func handle(_ input: DirectionalMoveGestureInput) -> [DirectionalMoveGestureEffect] {
        switch input {
        case let .pressed(direction, correlationID):
            switch phase {
            case .idle:
                phase = .pending(correlationID: correlationID, firstDirection: direction)
                return [.capture(correlationID: correlationID, firstDirection: direction)]
            case let .pending(activeCorrelationID, firstDirection):
                // Carbon may repeat a registered hot key while it remains down. Repeats must not
                // resolve a second gesture or extend the chord deadline.
                guard direction != firstDirection else { return [] }
                if let placement = VisualPlacement.corner(firstDirection, direction) {
                    phase = .awaitingRelease([firstDirection, direction])
                    return [.commitCorner(
                        correlationID: activeCorrelationID,
                        placement: placement
                    )]
                }
                phase = .awaitingRelease([firstDirection, direction])
                return [.cancel(
                    correlationID: activeCorrelationID,
                    reason: "same-axis-pair"
                )]
            case .awaitingRelease:
                return []
            }

        case let .released(direction):
            switch phase {
            case .idle:
                return []
            case let .pending(correlationID, firstDirection):
                guard direction == firstDirection else { return [] }
                phase = .idle
                return [.commitSingle(
                    correlationID: correlationID,
                    direction: firstDirection,
                    reason: "key-release"
                )]
            case let .awaitingRelease(heldDirections):
                var remaining = heldDirections
                remaining.remove(direction)
                phase = remaining.isEmpty ? .idle : .awaitingRelease(remaining)
                return []
            }

        case let .timeout(correlationID):
            guard case let .pending(activeCorrelationID, firstDirection) = phase,
                  activeCorrelationID == correlationID
            else { return [] }
            phase = .awaitingRelease([firstDirection])
            return [.commitSingle(
                correlationID: activeCorrelationID,
                direction: firstDirection,
                reason: "missing-release-timeout"
            )]

        case let .cancel(reason, awaitRelease):
            switch phase {
            case .idle:
                return []
            case let .pending(correlationID, firstDirection):
                phase = awaitRelease ? .awaitingRelease([firstDirection]) : .idle
                return [.cancel(correlationID: correlationID, reason: reason)]
            case .awaitingRelease:
                if !awaitRelease { phase = .idle }
                return []
            }
        }
    }
}

struct DirectionalWindowCandidate<Key: Hashable>: Hashable {
    let key: Key
    let frame: CGRect
}

enum SmartResizeResult: Equatable, Sendable {
    case resized(String)
    case noMeaning(String)
}

enum TiledDirectionalMoveStrategy: String, Equatable, Sendable {
    case directSiblingBranch = "direct-sibling-branch"
    case visualNeighbourLeaf = "visual-neighbour-leaf"
}
