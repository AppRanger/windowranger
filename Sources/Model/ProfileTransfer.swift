import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct PortableProfileArchive: Codable, Equatable, Sendable {
    static let formatIdentifier = "window-manager-profile-export"
    static let currentVersion = 1

    let format: String
    let version: Int
    let profiles: [PortableProfileDefinition]

    init(
        format: String = formatIdentifier,
        version: Int = currentVersion,
        profiles: [PortableProfileDefinition]
    ) {
        self.format = format
        self.version = version
        self.profiles = profiles
    }
}

struct PortableProfileDefinition: Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var workspaces: [PortableWorkspaceDefinition]
    var displayMode: MultiDisplayMode
    var displayRoles: [ProfileDisplayRole]
    var workspaceRoleAssignments: [UUID: UUID]
    var appRules: [AppRule]
    var dropDownApp: DropDownAppConfiguration?

    init(profile: WindowManagerProfile) {
        id = profile.id
        name = profile.name
        workspaces = profile.workspaces.map(PortableWorkspaceDefinition.init)
        displayMode = profile.displayMode
        displayRoles = profile.displayRoles
        workspaceRoleAssignments = profile.workspaceRoleAssignments
        appRules = profile.appRules
        dropDownApp = profile.dropDownApp
    }
}

struct PortableWorkspaceDefinition: Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var key: String
    var layout: WorkspaceLayout
    var layoutConfiguration: WorkspaceLayoutConfiguration?

    init(_ workspace: WorkspaceDefinition) {
        id = workspace.id
        name = workspace.name
        key = workspace.key
        layout = workspace.layout
        layoutConfiguration = workspace.layoutConfiguration
    }

    func materialized(id: UUID) -> WorkspaceDefinition {
        WorkspaceDefinition(
            id: id,
            name: name,
            key: key,
            layout: layout,
            layoutConfiguration: layoutConfiguration
        )
    }
}

struct ProfileImportSummary: Equatable, Identifiable, Sendable {
    let importedProfileID: UUID
    let sourceName: String
    let resultingName: String
    let workspaceCount: Int
    let displayRoleCount: Int
    let appRuleCount: Int

    var id: UUID { importedProfileID }
}

struct ProfileImportPlan: Equatable, Identifiable, Sendable {
    let id: UUID
    let formatVersion: Int
    let summaries: [ProfileImportSummary]
    let importedProfiles: [WindowManagerProfile]
    let destinationSnapshot: [WindowManagerProfile]

    init(
        id: UUID = UUID(),
        formatVersion: Int,
        summaries: [ProfileImportSummary],
        importedProfiles: [WindowManagerProfile],
        destinationSnapshot: [WindowManagerProfile]
    ) {
        self.id = id
        self.formatVersion = formatVersion
        self.summaries = summaries
        self.importedProfiles = importedProfiles
        self.destinationSnapshot = destinationSnapshot
    }
}

enum ProfileImportApplyResult: Equatable, Sendable {
    case applied(profileCount: Int)
    case stalePreview
    case invalidPlan
}

enum ProfileTransferError: Error, Equatable, LocalizedError, Sendable {
    case documentTooLarge(maximumBytes: Int)
    case malformedDocument
    case invalidFormat
    case unsupportedVersion(Int)
    case emptyDocument
    case limitExceeded(String)
    case duplicateIdentity(String)
    case invalidReference(String)
    case invalidValue(String)
    case unableToCreateUniqueIdentity

    var errorDescription: String? {
        switch self {
        case let .documentTooLarge(maximumBytes):
            "The profile file is larger than the supported \(maximumBytes / 1_048_576) MiB limit."
        case .malformedDocument:
            "This is not a valid WindowRanger profile file."
        case .invalidFormat:
            "This JSON document is not a WindowRanger profile export."
        case let .unsupportedVersion(version):
            "Profile export version \(version) is not supported by this build."
        case .emptyDocument:
            "The profile file does not contain any profiles."
        case let .limitExceeded(detail):
            "The profile file exceeds a safety limit: \(detail)."
        case let .duplicateIdentity(detail):
            "The profile file contains a duplicate identity: \(detail)."
        case let .invalidReference(detail):
            "The profile file contains an invalid relationship: \(detail)."
        case let .invalidValue(detail):
            "The profile file contains an invalid value: \(detail)."
        case .unableToCreateUniqueIdentity:
            "WindowRanger could not create unique identities for the imported profiles."
        }
    }

    var diagnosticCode: String {
        switch self {
        case .documentTooLarge: "document-too-large"
        case .malformedDocument: "malformed-document"
        case .invalidFormat: "invalid-format"
        case .unsupportedVersion: "unsupported-version"
        case .emptyDocument: "empty-document"
        case .limitExceeded: "limit-exceeded"
        case .duplicateIdentity: "duplicate-identity"
        case .invalidReference: "invalid-reference"
        case .invalidValue: "invalid-value"
        case .unableToCreateUniqueIdentity: "identity-generation-failed"
        }
    }
}

enum ProfileTransferCodec {
    static let maximumDocumentBytes = 2 * 1_048_576
    static let maximumProfiles = 64
    static let maximumWorkspacesPerProfile = 128
    static let maximumDisplayRolesPerProfile = 32
    static let maximumAppRulesPerProfile = 256
    static let maximumNameLength = 120
    static let maximumBundleIdentifierLength = 255
    static let maximumAppDisplayNameLength = 200

    static func encode(profiles: [WindowManagerProfile]) throws -> Data {
        let archive = PortableProfileArchive(
            profiles: profiles.map(PortableProfileDefinition.init)
        )
        try validate(archive)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(archive)
        guard data.count <= maximumDocumentBytes else {
            throw ProfileTransferError.documentTooLarge(maximumBytes: maximumDocumentBytes)
        }
        return data
    }

    static func decodeAndPlan(
        _ data: Data,
        existingProfiles: [WindowManagerProfile],
        makeUUID: () -> UUID = UUID.init
    ) throws -> ProfileImportPlan {
        guard data.count <= maximumDocumentBytes else {
            throw ProfileTransferError.documentTooLarge(maximumBytes: maximumDocumentBytes)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { throw ProfileTransferError.malformedDocument }
        guard dictionary["format"] as? String == PortableProfileArchive.formatIdentifier else {
            throw ProfileTransferError.invalidFormat
        }
        guard let version = dictionary["version"] as? Int else {
            throw ProfileTransferError.malformedDocument
        }
        guard version == PortableProfileArchive.currentVersion else {
            throw ProfileTransferError.unsupportedVersion(version)
        }
        let archive: PortableProfileArchive
        do {
            archive = try JSONDecoder().decode(PortableProfileArchive.self, from: data)
        } catch {
            throw ProfileTransferError.malformedDocument
        }
        try validate(archive)
        return try makeImportPlan(
            archive: archive,
            existingProfiles: existingProfiles,
            makeUUID: makeUUID
        )
    }

    static func validate(_ archive: PortableProfileArchive) throws {
        guard archive.format == PortableProfileArchive.formatIdentifier else {
            throw ProfileTransferError.invalidFormat
        }
        guard archive.version == PortableProfileArchive.currentVersion else {
            throw ProfileTransferError.unsupportedVersion(archive.version)
        }
        guard !archive.profiles.isEmpty else { throw ProfileTransferError.emptyDocument }
        guard archive.profiles.count <= maximumProfiles else {
            throw ProfileTransferError.limitExceeded("more than \(maximumProfiles) profiles")
        }

        var allProfileIDs = Set<UUID>()
        var allWorkspaceIDs = Set<UUID>()
        var allRoleIDs = Set<UUID>()
        for profile in archive.profiles {
            guard allProfileIDs.insert(profile.id).inserted else {
                throw ProfileTransferError.duplicateIdentity("profile")
            }
            try validateLabel(profile.name, field: "profile name")
            guard !profile.workspaces.isEmpty else {
                throw ProfileTransferError.invalidValue("a profile has no workspaces")
            }
            guard profile.workspaces.count <= maximumWorkspacesPerProfile else {
                throw ProfileTransferError.limitExceeded(
                    "more than \(maximumWorkspacesPerProfile) workspaces in one profile"
                )
            }
            guard !profile.displayRoles.isEmpty else {
                throw ProfileTransferError.invalidValue("a profile has no display roles")
            }
            guard profile.displayRoles.count <= maximumDisplayRolesPerProfile else {
                throw ProfileTransferError.limitExceeded(
                    "more than \(maximumDisplayRolesPerProfile) display roles in one profile"
                )
            }
            guard profile.appRules.count <= maximumAppRulesPerProfile else {
                throw ProfileTransferError.limitExceeded(
                    "more than \(maximumAppRulesPerProfile) application rules in one profile"
                )
            }
            if let dropDownApp = profile.dropDownApp {
                let bundleIdentifier = dropDownApp.bundleIdentifier
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !bundleIdentifier.isEmpty,
                      bundleIdentifier.count <= maximumBundleIdentifierLength,
                      bundleIdentifier.rangeOfCharacter(from: .newlines) == nil
                else { throw ProfileTransferError.invalidValue("Quick App bundle identifier") }
                try validateLabel(dropDownApp.displayName, field: "Quick App display name")
                let heightRange = ClosedRange(
                    uncheckedBounds: (
                        DropDownAppConfiguration.minimumHeightFraction,
                        DropDownAppConfiguration.maximumHeightFraction
                    )
                )
                guard dropDownApp.heightFraction.isFinite,
                      heightRange.contains(dropDownApp.heightFraction)
                else {
                    throw ProfileTransferError.invalidValue("Quick App size")
                }
            }

            var workspaceIDs = Set<UUID>()
            var usedKeys = Set<String>()
            for workspace in profile.workspaces {
                guard workspaceIDs.insert(workspace.id).inserted,
                      allWorkspaceIDs.insert(workspace.id).inserted
                else { throw ProfileTransferError.duplicateIdentity("workspace") }
                try validateLabel(workspace.name, field: "workspace name")
                let normalizedKey = workspace.key.lowercased()
                guard normalizedKey.count <= 1,
                      normalizedKey.isEmpty || HotKeyManager.keyCodes[normalizedKey] != nil
                else { throw ProfileTransferError.invalidValue("unsupported workspace key") }
                if !normalizedKey.isEmpty, !usedKeys.insert(normalizedKey).inserted {
                    throw ProfileTransferError.duplicateIdentity("workspace key")
                }
                try validateLayoutConfiguration(workspace.layoutConfiguration)
            }

            var roleIDs = Set<UUID>()
            for role in profile.displayRoles {
                guard roleIDs.insert(role.id).inserted, allRoleIDs.insert(role.id).inserted else {
                    throw ProfileTransferError.duplicateIdentity("display role")
                }
                try validateLabel(role.name, field: "display role name")
            }

            for (workspaceID, roleID) in profile.workspaceRoleAssignments {
                guard workspaceIDs.contains(workspaceID) else {
                    throw ProfileTransferError.invalidReference("display assignment workspace")
                }
                guard roleIDs.contains(roleID) else {
                    throw ProfileTransferError.invalidReference("display assignment role")
                }
            }

            var appRuleIDs = Set<String>()
            for rule in profile.appRules {
                let bundleID = rule.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !bundleID.isEmpty, bundleID.count <= maximumBundleIdentifierLength,
                      !bundleID.contains(where: { $0.isNewline })
                else { throw ProfileTransferError.invalidValue("application bundle identifier") }
                guard rule.displayName.count <= maximumAppDisplayNameLength,
                      !rule.displayName.contains(where: { $0.isNewline })
                else { throw ProfileTransferError.invalidValue("application display name") }
                guard appRuleIDs.insert(bundleID.lowercased()).inserted else {
                    throw ProfileTransferError.duplicateIdentity("application rule")
                }
                try validateRule(rule, workspaceIDs: workspaceIDs)
            }
        }
    }

    private static func makeImportPlan(
        archive: PortableProfileArchive,
        existingProfiles: [WindowManagerProfile],
        makeUUID: () -> UUID
    ) throws -> ProfileImportPlan {
        var usedIDs = Set(existingProfiles.flatMap { profile in
            [profile.id] + profile.workspaces.map(\.id) + profile.displayRoles.map(\.id)
        })
        for profile in archive.profiles {
            usedIDs.insert(profile.id)
            profile.workspaces.forEach { usedIDs.insert($0.id) }
            profile.displayRoles.forEach { usedIDs.insert($0.id) }
        }

        func freshID() throws -> UUID {
            for _ in 0..<2_048 {
                let candidate = makeUUID()
                if usedIDs.insert(candidate).inserted { return candidate }
            }
            throw ProfileTransferError.unableToCreateUniqueIdentity
        }

        var usedNames = Set(existingProfiles.map { $0.name.lowercased() })
        var imported: [WindowManagerProfile] = []
        var summaries: [ProfileImportSummary] = []
        for source in archive.profiles {
            let profileID = try freshID()
            var workspaceIDMap: [UUID: UUID] = [:]
            for workspace in source.workspaces { workspaceIDMap[workspace.id] = try freshID() }
            var roleIDMap: [UUID: UUID] = [:]
            for role in source.displayRoles { roleIDMap[role.id] = try freshID() }

            let resultingName = uniqueProfileName(source.name, usedNames: &usedNames)
            let workspaces = try source.workspaces.map { workspace -> WorkspaceDefinition in
                guard let id = workspaceIDMap[workspace.id] else {
                    throw ProfileTransferError.invalidReference("workspace remapping")
                }
                return workspace.materialized(id: id)
            }
            let roles = try source.displayRoles.map { role -> ProfileDisplayRole in
                guard let id = roleIDMap[role.id] else {
                    throw ProfileTransferError.invalidReference("display-role remapping")
                }
                return ProfileDisplayRole(
                    id: id,
                    name: role.name,
                    menuBarIconStyle: role.menuBarIconStyle
                )
            }
            let assignments = try Dictionary(uniqueKeysWithValues:
                source.workspaceRoleAssignments.map { workspaceID, roleID -> (UUID, UUID) in
                    guard let remappedWorkspaceID = workspaceIDMap[workspaceID],
                          let remappedRoleID = roleIDMap[roleID]
                    else { throw ProfileTransferError.invalidReference("display assignment remapping") }
                    return (remappedWorkspaceID, remappedRoleID)
                }
            )
            let quickAppBundleIdentifier = source.dropDownApp?.bundleIdentifier.lowercased()
            let rules = try source.appRules.filter { rule in
                rule.bundleIdentifier.lowercased() != quickAppBundleIdentifier
            }.map { rule -> AppRule in
                var remapped = rule
                if let workspaceID = rule.assignedWorkspaceID {
                    guard let importedWorkspaceID = workspaceIDMap[workspaceID] else {
                        throw ProfileTransferError.invalidReference("application rule remapping")
                    }
                    remapped.assignedWorkspaceID = importedWorkspaceID
                }
                return remapped
            }
            let profile = WindowManagerProfile(
                id: profileID,
                name: resultingName,
                workspaces: workspaces,
                displayMode: source.displayMode,
                displayRoles: roles,
                workspaceRoleAssignments: assignments,
                appRules: rules,
                dropDownApp: source.dropDownApp
            )
            guard profile.normalized() == profile else {
                throw ProfileTransferError.invalidValue("profile normalization would discard data")
            }
            imported.append(profile)
            summaries.append(ProfileImportSummary(
                importedProfileID: profileID,
                sourceName: source.name,
                resultingName: resultingName,
                workspaceCount: workspaces.count,
                displayRoleCount: roles.count,
                appRuleCount: rules.count
            ))
        }
        return ProfileImportPlan(
            formatVersion: archive.version,
            summaries: summaries,
            importedProfiles: imported,
            destinationSnapshot: existingProfiles
        )
    }

    private static func validateLabel(_ value: String, field: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, value.count <= maximumNameLength,
              value.rangeOfCharacter(from: .newlines) == nil
        else { throw ProfileTransferError.invalidValue(field) }
    }

    private static func validateLayoutConfiguration(
        _ configuration: WorkspaceLayoutConfiguration?
    ) throws {
        guard let configuration else { return }
        guard configuration.accordionPadding.isFinite,
              (0...800).contains(configuration.accordionPadding)
        else { throw ProfileTransferError.invalidValue("accordion padding") }
        let gaps = configuration.gaps
        let inner = [gaps.innerHorizontal, gaps.innerVertical]
        let outer = [gaps.outerTop, gaps.outerRight, gaps.outerBottom, gaps.outerLeft]
        guard inner.allSatisfy({ $0.isFinite && (0...200).contains($0) }),
              outer.allSatisfy({ $0.isFinite && (0...400).contains($0) })
        else { throw ProfileTransferError.invalidValue("layout gaps") }
    }

    private static func validateRule(_ rule: AppRule, workspaceIDs: Set<UUID>) throws {
        var assignmentCount = 0
        var keepCount = 0
        var excludeCount = 0
        var secondaryCount = 0
        for action in rule.actions {
            switch action {
            case let .assignWorkspace(workspaceID):
                assignmentCount += 1
                guard workspaceIDs.contains(workspaceID) else {
                    throw ProfileTransferError.invalidReference("application rule workspace")
                }
            case .keepOnAllWorkspaces: keepCount += 1
            case .excludeFromLayout: excludeCount += 1
            case .floatSecondaryWindows: secondaryCount += 1
            }
        }
        guard assignmentCount <= 1, keepCount <= 1, excludeCount <= 1, secondaryCount <= 1 else {
            throw ProfileTransferError.invalidValue("duplicate application-rule action")
        }
    }

    private static func uniqueProfileName(_ proposed: String, usedNames: inout Set<String>) -> String {
        let base = String(proposed.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maximumNameLength))
        if usedNames.insert(base.lowercased()).inserted { return base }
        var suffix = 2
        while true {
            let suffixText = " \(suffix)"
            let prefixCount = max(1, maximumNameLength - suffixText.count)
            let candidate = String(base.prefix(prefixCount)) + suffixText
            if usedNames.insert(candidate.lowercased()).inserted { return candidate }
            suffix += 1
        }
    }
}

protocol ProfileTransferFileAccess {
    func read(from url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
}

struct LocalProfileTransferFileAccess: ProfileTransferFileAccess {
    func read(from url: URL) throws -> Data { try Data(contentsOf: url) }
    func write(_ data: Data, to url: URL) throws { try data.write(to: url, options: .atomic) }
}

@MainActor
protocol ProfileTransferPanelPresenting: AnyObject {
    func chooseImportURL() async -> URL?
    func chooseExportURL(suggestedFileName: String) async -> URL?
}

@MainActor
final class AppKitProfileTransferPanelPresenter: ProfileTransferPanelPresenting {
    func chooseImportURL() async -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a WindowRanger profile export to preview."
        return await withCheckedContinuation { continuation in
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
        }
    }

    func chooseExportURL(suggestedFileName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFileName
        panel.message = "Export reusable profile definitions only."
        return await withCheckedContinuation { continuation in
            panel.begin { response in continuation.resume(returning: response == .OK ? panel.url : nil) }
        }
    }
}

@MainActor
final class ProfileTransferCoordinator: ObservableObject {
    private let fileAccess: ProfileTransferFileAccess
    private let panels: ProfileTransferPanelPresenting
    private let diagnostics: DiagnosticLogger
    private let makeUUID: () -> UUID

    init(
        fileAccess: ProfileTransferFileAccess = LocalProfileTransferFileAccess(),
        panels: ProfileTransferPanelPresenting? = nil,
        diagnostics: DiagnosticLogger = .disabled,
        makeUUID: @escaping () -> UUID = UUID.init
    ) {
        self.fileAccess = fileAccess
        self.panels = panels ?? AppKitProfileTransferPanelPresenter()
        self.diagnostics = diagnostics
        self.makeUUID = makeUUID
    }

    func exportProfiles(_ profiles: [WindowManagerProfile]) async throws -> Bool {
        guard let url = await panels.chooseExportURL(
            suggestedFileName: "WindowRanger-Profiles.json"
        ) else {
            diagnostics.log(category: "profile-transfer", event: "export-cancelled")
            return false
        }
        do {
            let data = try ProfileTransferCodec.encode(profiles: profiles)
            try fileAccess.write(data, to: url)
            diagnostics.log(
                category: "profile-transfer",
                event: "export-completed",
                fields: [
                    "version": String(PortableProfileArchive.currentVersion),
                    "profile-count": String(profiles.count),
                    "bytes": String(data.count),
                ]
            )
            return true
        } catch {
            diagnostics.log(
                category: "profile-transfer",
                event: "export-rejected",
                fields: ["reason": (error as? ProfileTransferError)?.diagnosticCode ?? "file-error"]
            )
            throw error
        }
    }

    func prepareImport(existingProfiles: [WindowManagerProfile]) async throws -> ProfileImportPlan? {
        guard let url = await panels.chooseImportURL() else {
            diagnostics.log(category: "profile-transfer", event: "import-cancelled")
            return nil
        }
        do {
            let data = try fileAccess.read(from: url)
            let plan = try ProfileTransferCodec.decodeAndPlan(
                data,
                existingProfiles: existingProfiles,
                makeUUID: makeUUID
            )
            diagnostics.log(
                category: "profile-transfer",
                event: "import-preview-ready",
                fields: [
                    "version": String(plan.formatVersion),
                    "profile-count": String(plan.importedProfiles.count),
                    "workspace-count": String(plan.importedProfiles.reduce(0) { $0 + $1.workspaces.count }),
                    "role-count": String(plan.importedProfiles.reduce(0) { $0 + $1.displayRoles.count }),
                    "rule-count": String(plan.importedProfiles.reduce(0) { $0 + $1.appRules.count }),
                ]
            )
            return plan
        } catch {
            diagnostics.log(
                category: "profile-transfer",
                event: "import-rejected",
                fields: ["reason": (error as? ProfileTransferError)?.diagnosticCode ?? "file-error"]
            )
            throw error
        }
    }
}
