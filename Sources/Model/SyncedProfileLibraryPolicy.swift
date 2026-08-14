import Foundation

enum SyncedProfileLibraryRejection: Equatable, Sendable {
    case documentTooLarge(actualBytes: Int, maximumBytes: Int)
    case malformedDocument
    case unsupportedVersion(Int)
    case profileCount(actual: Int, maximum: Int)
    case workspaceCount(profileIndex: Int, actual: Int, maximum: Int)
    case displayRoleCount(profileIndex: Int, actual: Int, maximum: Int)
    case appRuleCount(profileIndex: Int, actual: Int, maximum: Int)
    case nameTooLong(kind: String, maximumCharacters: Int)
    case invalidLibrary

    var userMessage: String {
        switch self {
        case let .documentTooLarge(actual, maximum):
            "The synced profile library is \(actual) bytes; WindowRanger accepts up to \(maximum) bytes so other iCloud preferences retain quota space."
        case .malformedDocument:
            "The synced profile library is not a readable WindowRanger document."
        case let .unsupportedVersion(version):
            "The synced profile library uses unsupported version \(version). Update WindowRanger before applying it."
        case let .profileCount(actual, maximum):
            "The synced library contains \(actual) profiles; the supported maximum is \(maximum)."
        case let .workspaceCount(profileIndex, actual, maximum):
            "Synced profile \(profileIndex + 1) contains \(actual) workspaces; the supported maximum is \(maximum)."
        case let .displayRoleCount(profileIndex, actual, maximum):
            "Synced profile \(profileIndex + 1) contains \(actual) display roles; the supported maximum is \(maximum)."
        case let .appRuleCount(profileIndex, actual, maximum):
            "Synced profile \(profileIndex + 1) contains \(actual) app rules; the supported maximum is \(maximum)."
        case let .nameTooLong(kind, maximum):
            "A synced \(kind) name exceeds the supported maximum of \(maximum) characters."
        case .invalidLibrary:
            "The synced profile library has no valid profiles after structural normalization."
        }
    }
}

enum SyncedProfileLibraryValidation: Equatable, Sendable {
    case absent
    case accepted(ProfileLibrary)
    case rejected(SyncedProfileLibraryRejection)
}

enum SyncedProfileLibraryPolicy {
    // NSUbiquitousKeyValueStore provides 1 MB across all values. Keeping the atomic library below
    // 750 KB leaves explicit headroom for the other supported global preferences.
    static let maximumDocumentBytes = 750_000
    static let maximumProfiles = 128
    static let maximumWorkspacesPerProfile = 128
    static let maximumDisplayRolesPerProfile = 64
    static let maximumAppRulesPerProfile = 512
    static let maximumNameCharacters = 256

    static func validate(_ data: Data?) -> SyncedProfileLibraryValidation {
        guard let data else { return .absent }
        guard data.count <= maximumDocumentBytes else {
            return .rejected(.documentTooLarge(
                actualBytes: data.count,
                maximumBytes: maximumDocumentBytes
            ))
        }
        guard let decoded = try? JSONDecoder().decode(ProfileLibrary.self, from: data) else {
            return .rejected(.malformedDocument)
        }
        guard decoded.version == ProfileLibrary.currentVersion else {
            return .rejected(.unsupportedVersion(decoded.version))
        }
        guard decoded.profiles.count <= maximumProfiles else {
            return .rejected(.profileCount(
                actual: decoded.profiles.count,
                maximum: maximumProfiles
            ))
        }
        for (profileIndex, profile) in decoded.profiles.enumerated() {
            guard profile.workspaces.count <= maximumWorkspacesPerProfile else {
                return .rejected(.workspaceCount(
                    profileIndex: profileIndex,
                    actual: profile.workspaces.count,
                    maximum: maximumWorkspacesPerProfile
                ))
            }
            guard profile.displayRoles.count <= maximumDisplayRolesPerProfile else {
                return .rejected(.displayRoleCount(
                    profileIndex: profileIndex,
                    actual: profile.displayRoles.count,
                    maximum: maximumDisplayRolesPerProfile
                ))
            }
            guard profile.appRules.count <= maximumAppRulesPerProfile else {
                return .rejected(.appRuleCount(
                    profileIndex: profileIndex,
                    actual: profile.appRules.count,
                    maximum: maximumAppRulesPerProfile
                ))
            }
            guard isValidName(profile.name) else {
                return .rejected(.nameTooLong(kind: "profile", maximumCharacters: maximumNameCharacters))
            }
            guard profile.workspaces.allSatisfy({ isValidName($0.name) }) else {
                return .rejected(.nameTooLong(kind: "workspace", maximumCharacters: maximumNameCharacters))
            }
            guard profile.displayRoles.allSatisfy({ isValidName($0.name) }) else {
                return .rejected(.nameTooLong(kind: "display role", maximumCharacters: maximumNameCharacters))
            }
            guard profile.appRules.allSatisfy({ isValidName($0.displayName) }) else {
                return .rejected(.nameTooLong(kind: "application rule", maximumCharacters: maximumNameCharacters))
            }
            if let dropDownApp = profile.dropDownApp,
               !isValidName(dropDownApp.displayName) {
                return .rejected(.nameTooLong(
                    kind: "Quick App",
                    maximumCharacters: maximumNameCharacters
                ))
            }
        }
        guard let normalized = decoded.normalized() else {
            return .rejected(.invalidLibrary)
        }
        return .accepted(normalized)
    }

    private static func isValidName(_ name: String) -> Bool {
        name.count <= maximumNameCharacters
    }
}
