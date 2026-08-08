import Foundation

/// A side-effect-free description of one possible focus target after a workspace switch. The
/// engine supplies AX-derived visibility and focusability; this policy only decides precedence.
struct WorkspaceSwitchFocusCandidate<Key: Hashable & Sendable>: Equatable, Sendable {
    let key: Key
    let belongsToWorkspace: Bool
    let keepsOnAllWorkspaces: Bool
    let isVisible: Bool
    let isMeaningfullyVisible: Bool
    let isOnDestinationDisplay: Bool
    let isFocusEligible: Bool
    let isIgnored: Bool
    let isTemporarilyDeferred: Bool

    var isEligible: Bool {
        isVisible && isMeaningfullyVisible && isOnDestinationDisplay && isFocusEligible &&
            !isIgnored && !isTemporarilyDeferred
    }
}

enum WorkspaceSwitchFocusPolicy {
    /// Normal members of the destination workspace always precede keep-on-all windows. The
    /// caller's order is the existing spatial/stable order; a valid local history target is moved
    /// to the front of its group without disturbing the rest.
    static func orderedTargets<Key: Hashable & Sendable>(
        preferred: Key?,
        candidates: [WorkspaceSwitchFocusCandidate<Key>]
    ) -> [Key] {
        let local = candidates.filter {
            $0.isEligible && $0.belongsToWorkspace && !$0.keepsOnAllWorkspaces
        }
        let keepOnAll = candidates.filter {
            $0.isEligible && $0.keepsOnAllWorkspaces
        }

        func preferredFirst(_ candidates: [WorkspaceSwitchFocusCandidate<Key>]) -> [Key] {
            guard let preferred,
                  let index = candidates.firstIndex(where: { $0.key == preferred })
            else { return candidates.map(\.key) }
            var reordered = candidates
            let match = reordered.remove(at: index)
            reordered.insert(match, at: 0)
            return reordered.map(\.key)
        }

        return preferredFirst(local) + preferredFirst(keepOnAll)
    }
}

struct WorkspaceSwitchDestination: Equatable, Sendable {
    let logicalDisplayIdentifier: String
    let physicalDisplayIdentifier: String
    let usedDisconnectedHomeFallback: Bool
}

enum WorkspaceSwitchDestinationPolicy {
    static func resolve(
        logicalHomeDisplayIdentifier: String,
        displays: [DisplaySnapshot]
    ) -> WorkspaceSwitchDestination? {
        guard let fallback = displays.first(where: \.isMain) ?? displays.first else { return nil }
        let homeIsConnected = displays.contains { $0.identifier == logicalHomeDisplayIdentifier }
        return WorkspaceSwitchDestination(
            logicalDisplayIdentifier: logicalHomeDisplayIdentifier,
            physicalDisplayIdentifier: homeIsConnected ? logicalHomeDisplayIdentifier : fallback.identifier,
            usedDisconnectedHomeFallback: !homeIsConnected
        )
    }
}
