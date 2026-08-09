import Foundation

enum MultiDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case unified
    case independent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unified: "Unified"
        case .independent: "Independent Displays"
        }
    }
}

enum WorkspaceLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case tiled
    case accordion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Freeform"
        case .tiled: "Tiled"
        case .accordion: "Accordion"
        }
    }

    func cycled(by offset: Int) -> WorkspaceLayout {
        let layouts = Self.allCases
        guard let index = layouts.firstIndex(of: self), !layouts.isEmpty else { return self }
        let count = layouts.count
        return layouts[(index + offset % count + count) % count]
    }
}

enum WorkspaceLayoutOrientation: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case horizontal
    case vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        }
    }

    func resolved(for bounds: CGRect) -> WorkspaceLayoutOrientation {
        guard self == .automatic else { return self }
        return bounds.width >= bounds.height ? .horizontal : .vertical
    }
}

struct WorkspaceLayoutGaps: Codable, Equatable, Sendable {
    var innerHorizontal: Double
    var innerVertical: Double
    var outerTop: Double
    var outerRight: Double
    var outerBottom: Double
    var outerLeft: Double

    static let aeroSpaceUserDefaults = WorkspaceLayoutGaps(
        innerHorizontal: 5,
        innerVertical: 5,
        outerTop: 0,
        outerRight: 0,
        outerBottom: 0,
        outerLeft: 0
    )

    func clamped() -> WorkspaceLayoutGaps {
        WorkspaceLayoutGaps(
            innerHorizontal: innerHorizontal.clamped(to: 0...200),
            innerVertical: innerVertical.clamped(to: 0...200),
            outerTop: outerTop.clamped(to: 0...400),
            outerRight: outerRight.clamped(to: 0...400),
            outerBottom: outerBottom.clamped(to: 0...400),
            outerLeft: outerLeft.clamped(to: 0...400)
        )
    }
}

/// Settings are optional for migration. A decoded workspace without this object keeps the exact
/// pre-layout-controls geometry until the user explicitly changes its layout or geometry. Newly
/// created workspaces use WindowManager's built-in defaults. Their initial values were informed
/// by the user's prior configuration, but they are now owned by this product.
struct WorkspaceLayoutConfiguration: Codable, Equatable, Sendable {
    var orientation: WorkspaceLayoutOrientation
    var accordionPadding: Double
    var gaps: WorkspaceLayoutGaps

    static let aeroSpaceUserDefaults = WorkspaceLayoutConfiguration(
        orientation: .automatic,
        accordionPadding: 250,
        gaps: .aeroSpaceUserDefaults
    )

    func clamped() -> WorkspaceLayoutConfiguration {
        WorkspaceLayoutConfiguration(
            orientation: orientation,
            accordionPadding: accordionPadding.clamped(to: 0...800),
            gaps: gaps.clamped()
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(isFinite ? self : range.lowerBound, range.lowerBound), range.upperBound)
    }
}

struct WorkspaceDefinition: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var key: String
    var layout: WorkspaceLayout
    var layoutConfiguration: WorkspaceLayoutConfiguration?

    init(
        id: UUID = UUID(),
        name: String,
        key: String,
        layout: WorkspaceLayout = .none,
        layoutConfiguration: WorkspaceLayoutConfiguration? = .aeroSpaceUserDefaults
    ) {
        self.id = id
        self.name = name
        self.key = key.lowercased()
        self.layout = layout
        self.layoutConfiguration = layoutConfiguration?.clamped()
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, key, layout, layoutConfiguration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        key = try container.decode(String.self, forKey: .key).lowercased()
        layout = try container.decodeIfPresent(WorkspaceLayout.self, forKey: .layout) ?? .none
        layoutConfiguration = try container.decodeIfPresent(
            WorkspaceLayoutConfiguration.self,
            forKey: .layoutConfiguration
        )?.clamped()
    }

    static let defaults: [WorkspaceDefinition] = [
        WorkspaceDefinition(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "1", key: "1"),
        WorkspaceDefinition(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "2", key: "2"),
        WorkspaceDefinition(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "3", key: "3"),
        WorkspaceDefinition(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "4", key: "4"),
    ]

    static func freshDefaults(makeUUID: () -> UUID = UUID.init) -> [WorkspaceDefinition] {
        defaults.map {
            WorkspaceDefinition(
                id: makeUUID(),
                name: $0.name,
                key: $0.key,
                layout: $0.layout,
                layoutConfiguration: $0.layoutConfiguration
            )
        }
    }
}
