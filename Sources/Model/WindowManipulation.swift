import CoreGraphics
import Foundation

enum WindowDirection: String, Codable, CaseIterable, Identifiable, Sendable {
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
