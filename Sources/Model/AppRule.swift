import AppKit
import Foundation

enum AppRuleAction: Codable, Equatable, Sendable {
    case assignWorkspace(UUID)
    case keepOnAllWorkspaces
    case excludeFromLayout
    case floatSecondaryWindows
}

struct ResolvedAppRule: Equatable, Sendable {
    var assignedWorkspaceID: UUID?
    var keepsOnAllWorkspaces: Bool
    var excludesFromLayout: Bool
    var floatsSecondaryWindows: Bool

    init(
        assignedWorkspaceID: UUID?,
        keepsOnAllWorkspaces: Bool,
        excludesFromLayout: Bool,
        floatsSecondaryWindows: Bool = false
    ) {
        self.assignedWorkspaceID = assignedWorkspaceID
        self.keepsOnAllWorkspaces = keepsOnAllWorkspaces
        self.excludesFromLayout = excludesFromLayout
        self.floatsSecondaryWindows = floatsSecondaryWindows
    }

    static let none = ResolvedAppRule(
        assignedWorkspaceID: nil,
        keepsOnAllWorkspaces: false,
        excludesFromLayout: false,
        floatsSecondaryWindows: false
    )
}

struct AppRule: Codable, Equatable, Identifiable, Sendable {
    var bundleIdentifier: String
    var displayName: String
    var actions: [AppRuleAction]
    var isEnabled: Bool

    var id: String { bundleIdentifier.lowercased() }

    init(
        bundleIdentifier: String,
        displayName: String,
        actions: [AppRuleAction] = [],
        isEnabled: Bool = true
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.actions = actions
        self.isEnabled = isEnabled
    }

    var keepsOnAllWorkspaces: Bool {
        get { actions.contains(.keepOnAllWorkspaces) }
        set { setFlag(.keepOnAllWorkspaces, enabled: newValue) }
    }

    var excludesFromLayout: Bool {
        get { actions.contains(.excludeFromLayout) }
        set { setFlag(.excludeFromLayout, enabled: newValue) }
    }

    var floatsSecondaryWindows: Bool {
        get { actions.contains(.floatSecondaryWindows) }
        set { setFlag(.floatSecondaryWindows, enabled: newValue) }
    }

    var assignedWorkspaceID: UUID? {
        get {
            actions.compactMap { action in
                if case let .assignWorkspace(workspaceID) = action { return workspaceID }
                return nil
            }.first
        }
        set {
            actions.removeAll {
                if case .assignWorkspace = $0 { return true }
                return false
            }
            if let newValue {
                actions.append(.assignWorkspace(newValue))
            }
        }
    }

    func resolved(validWorkspaceIDs: Set<UUID>) -> ResolvedAppRule {
        guard isEnabled else { return .none }
        let keepEverywhere = keepsOnAllWorkspaces
        return ResolvedAppRule(
            assignedWorkspaceID: keepEverywhere
                ? nil
                : assignedWorkspaceID.flatMap { validWorkspaceIDs.contains($0) ? $0 : nil },
            keepsOnAllWorkspaces: keepEverywhere,
            excludesFromLayout: excludesFromLayout,
            floatsSecondaryWindows: floatsSecondaryWindows
        )
    }

    private mutating func setFlag(_ action: AppRuleAction, enabled: Bool) {
        actions.removeAll { $0 == action }
        if enabled { actions.append(action) }
    }

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case displayName
        case actions
        case isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        displayName = try container.decode(String.self, forKey: .displayName)
        actions = try container.decodeIfPresent([AppRuleAction].self, forKey: .actions) ?? []
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(actions, forKey: .actions)
        try container.encode(isEnabled, forKey: .isEnabled)
    }
}

struct InstalledApplication: Identifiable, Equatable, Sendable {
    let bundleIdentifier: String
    let displayName: String
    let bundleURL: URL?
    let isRunning: Bool

    var id: String { bundleIdentifier.lowercased() }
}

struct InstalledApplicationGroups: Equatable, Sendable {
    let openApplications: [InstalledApplication]
    let otherApplications: [InstalledApplication]

    var isEmpty: Bool { openApplications.isEmpty && otherApplications.isEmpty }
}

enum InstalledApplicationPickerPolicy {
    static func groups(
        applications: [InstalledApplication],
        search: String
    ) -> InstalledApplicationGroups {
        let filtered = search.isEmpty ? applications : applications.filter {
            $0.displayName.localizedCaseInsensitiveContains(search) ||
                $0.bundleIdentifier.localizedCaseInsensitiveContains(search)
        }
        let sorted = filtered.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        return InstalledApplicationGroups(
            openApplications: sorted.filter(\.isRunning),
            otherApplications: sorted.filter { !$0.isRunning }
        )
    }
}

enum AppRuleDefaultWorkspacePolicy {
    static func resolve(
        applicationIsRunning: Bool,
        liveWorkspaceIDs: [UUID]
    ) -> UUID? {
        guard applicationIsRunning else { return nil }
        let uniqueWorkspaceIDs = Set(liveWorkspaceIDs)
        return uniqueWorkspaceIDs.count == 1 ? uniqueWorkspaceIDs.first : nil
    }
}

enum InstalledApplicationCatalog {
    static func discover() -> [InstalledApplication] {
        var applications: [String: InstalledApplication] = [:]

        func add(bundleIdentifier: String?, displayName: String?, bundleURL: URL?, isRunning: Bool) {
            guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return }
            let key = bundleIdentifier.lowercased()
            let fallbackName = bundleURL?.deletingPathExtension().lastPathComponent
                ?? bundleIdentifier.components(separatedBy: ".").last
                ?? bundleIdentifier
            let resolvedName = displayName.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
            let candidate = InstalledApplication(
                bundleIdentifier: bundleIdentifier,
                displayName: resolvedName,
                bundleURL: bundleURL,
                isRunning: isRunning
            )
            if let existing = applications[key] {
                applications[key] = InstalledApplication(
                    bundleIdentifier: existing.bundleIdentifier,
                    displayName: existing.displayName,
                    bundleURL: existing.bundleURL ?? candidate.bundleURL,
                    isRunning: existing.isRunning || candidate.isRunning
                )
            } else {
                applications[key] = candidate
            }
        }

        for application in NSWorkspace.shared.runningApplications
        where application.activationPolicy == .regular && !application.isTerminated {
            add(
                bundleIdentifier: application.bundleIdentifier,
                displayName: application.localizedName,
                bundleURL: application.bundleURL,
                isRunning: true
            )
        }

        let fileManager = FileManager.default
        var searchRoots = fileManager.urls(for: .applicationDirectory, in: [.userDomainMask, .localDomainMask, .systemDomainMask])
        searchRoots.append(URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true))
        for root in Set(searchRoots) where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                enumerator.skipDescendants()
                guard let bundle = Bundle(url: url) else { continue }
                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                add(
                    bundleIdentifier: bundle.bundleIdentifier,
                    displayName: name,
                    bundleURL: url,
                    isRunning: false
                )
            }
        }

        return applications.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}
