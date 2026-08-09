import CoreGraphics
import Foundation

enum SplitAxis: String, Codable, CaseIterable, Sendable {
    /// First child is left, second child is right.
    case horizontal
    /// First child is above, second child is below in the app's top-left AX coordinate space.
    case vertical
}

enum VisualPlacement: String, Codable, CaseIterable, Identifiable, Sendable {
    case topLeft = "top-left"
    case top
    case topRight = "top-right"
    case left
    case right
    case bottomLeft = "bottom-left"
    case bottom
    case bottomRight = "bottom-right"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: "Top Left"
        case .top: "Top"
        case .topRight: "Top Right"
        case .left: "Left"
        case .right: "Right"
        case .bottomLeft: "Bottom Left"
        case .bottom: "Bottom"
        case .bottomRight: "Bottom Right"
        }
    }

    var systemImage: String {
        switch self {
        case .topLeft: "arrow.up.left"
        case .top: "arrow.up"
        case .topRight: "arrow.up.right"
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .bottomLeft: "arrow.down.left"
        case .bottom: "arrow.down"
        case .bottomRight: "arrow.down.right"
        }
    }

    /// Compass ordering starts at twelve o'clock and proceeds clockwise. The deliberately
    /// absent centre slot is the wheel's neutral/cancel region.
    static let compassOrder: [Self] = [
        .top, .topRight, .right, .bottomRight,
        .bottom, .bottomLeft, .left, .topLeft,
    ]
}

indirect enum TiledNode: Codable, Equatable, Sendable {
    case window(WindowKey)
    case split(axis: SplitAxis, ratio: Double, first: TiledNode, second: TiledNode)

    private enum CodingKeys: String, CodingKey { case kind, window, axis, ratio, first, second }
    private enum Kind: String, Codable { case window, split }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .window:
            self = .window(try values.decode(WindowKey.self, forKey: .window))
        case .split:
            self = .split(
                axis: try values.decode(SplitAxis.self, forKey: .axis),
                ratio: try values.decode(Double.self, forKey: .ratio),
                first: try values.decode(TiledNode.self, forKey: .first),
                second: try values.decode(TiledNode.self, forKey: .second)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .window(key):
            try values.encode(Kind.window, forKey: .kind)
            try values.encode(key, forKey: .window)
        case let .split(axis, ratio, first, second):
            try values.encode(Kind.split, forKey: .kind)
            try values.encode(axis, forKey: .axis)
            try values.encode(ratio, forKey: .ratio)
            try values.encode(first, forKey: .first)
            try values.encode(second, forKey: .second)
        }
    }

    var windowKeys: [WindowKey] {
        switch self {
        case let .window(key): [key]
        case let .split(_, _, first, second): first.windowKeys + second.windowKeys
        }
    }

    func contains(_ key: WindowKey) -> Bool {
        switch self {
        case let .window(candidate): candidate == key
        case let .split(_, _, first, second): first.contains(key) || second.contains(key)
        }
    }

    /// Removing a leaf also collapses the now-redundant parent. `nil` means no leaf remains.
    func removing(_ key: WindowKey) -> TiledNode? {
        switch self {
        case let .window(candidate):
            return candidate == key ? nil : self
        case let .split(axis, ratio, first, second):
            let newFirst = first.removing(key)
            let newSecond = second.removing(key)
            switch (newFirst, newSecond) {
            case let (.some(first), .some(second)):
                return .split(axis: axis, ratio: ratio, first: first, second: second)
            case let (.some(only), .none), let (.none, .some(only)):
                return only
            case (.none, .none):
                return nil
            }
        }
    }
}

struct TiledLayoutPartitionKey: Codable, Equatable, Hashable, Sendable {
    let workspaceID: UUID
    let displayIdentifier: String
}

struct PersistedTiledTree: Codable, Equatable, Sendable {
    let partition: TiledLayoutPartitionKey
    let tree: TiledNode
}

struct TiledPlacementPreview: Equatable, Sendable {
    let placement: VisualPlacement
    let focusedWindow: WindowKey
    let proposedTree: TiledNode
    let frames: [WindowKey: WindowFrame]
    let fingerprint: String
}

enum TiledLayoutError: Error, Equatable {
    case emptyTree
    case missingFocusedWindow
    case duplicateWindow
    case participantMismatch
    case invalidRatio
    case invalidBounds
}

enum TiledLayoutEngine {
    static let initialSplitRatio = 0.5
    static let minimumSplitRatio = 0.1
    static let maximumSplitRatio = 0.9

    /// Converts the existing stable flat order into nested same-axis splits. Ratios are derived
    /// from the existing weights so the first tree solve reproduces the flat layout instead of
    /// visually rearranging an upgraded workspace.
    static func flatTree(
        windowKeys: [WindowKey],
        weights: [CGFloat]? = nil,
        orientation: WorkspaceLayoutOrientation
    ) -> TiledNode? {
        guard let first = windowKeys.first else { return nil }
        guard windowKeys.count > 1 else { return .window(first) }
        let axis: SplitAxis = orientation == .vertical ? .vertical : .horizontal
        let sanitized: [Double]
        if let weights, weights.count == windowKeys.count {
            sanitized = weights.map { $0.isFinite && $0 > 0 ? Double($0) : 1 }
        } else {
            sanitized = Array(repeating: 1, count: windowKeys.count)
        }
        func build(_ index: Int) -> TiledNode {
            guard index < windowKeys.count - 1 else { return .window(windowKeys[index]) }
            let remainingWeight = sanitized[index...].reduce(0, +)
            let ratio = remainingWeight > 0 ? sanitized[index] / remainingWeight : 1 / Double(windowKeys.count - index)
            return .split(
                axis: axis,
                ratio: ratio,
                first: .window(windowKeys[index]),
                second: build(index + 1)
            )
        }
        return build(0)
    }

    static func validated(_ tree: TiledNode, participants: Set<WindowKey>) throws {
        let keys = tree.windowKeys
        guard !keys.isEmpty else { throw TiledLayoutError.emptyTree }
        guard Set(keys).count == keys.count else { throw TiledLayoutError.duplicateWindow }
        guard Set(keys) == participants else { throw TiledLayoutError.participantMismatch }
        try validateRatios(in: tree)
    }

    static func frames(
        for tree: TiledNode,
        in displayBounds: CGRect,
        configuration: WorkspaceLayoutConfiguration
    ) throws -> [WindowKey: WindowFrame] {
        guard displayBounds.width.isFinite, displayBounds.height.isFinite,
              displayBounds.width > 0, displayBounds.height > 0
        else { throw TiledLayoutError.invalidBounds }
        try validateRatios(in: tree)
        let bounds = inset(displayBounds, gaps: configuration.clamped().gaps)
        var result: [WindowKey: WindowFrame] = [:]
        solve(tree, in: bounds, gaps: configuration.clamped().gaps, result: &result)
        return result
    }

    static func placing(
        _ window: WindowKey,
        at placement: VisualPlacement,
        in tree: TiledNode,
        bounds: CGRect,
        configuration: WorkspaceLayoutConfiguration
    ) throws -> TiledPlacementPreview {
        guard tree.contains(window) else { throw TiledLayoutError.missingFocusedWindow }
        let participants = Set(tree.windowKeys)
        guard let remainder = tree.removing(window) else {
            let frames = try frames(for: tree, in: bounds, configuration: configuration)
            return TiledPlacementPreview(
                placement: placement,
                focusedWindow: window,
                proposedTree: tree,
                frames: frames,
                fingerprint: fingerprint(tree)
            )
        }

        let proposed: TiledNode
        switch placement {
        case .left:
            proposed = .split(axis: .horizontal, ratio: initialSplitRatio, first: .window(window), second: remainder)
        case .right:
            proposed = .split(axis: .horizontal, ratio: initialSplitRatio, first: remainder, second: .window(window))
        case .top:
            proposed = .split(axis: .vertical, ratio: initialSplitRatio, first: .window(window), second: remainder)
        case .bottom:
            proposed = .split(axis: .vertical, ratio: initialSplitRatio, first: remainder, second: .window(window))
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let remainderFrames = try frames(for: remainder, in: bounds, configuration: configuration)
            guard let destination = cornerLeaf(
                placement,
                frames: remainderFrames,
                bounds: inset(bounds, gaps: configuration.clamped().gaps)
            ) else { throw TiledLayoutError.emptyTree }
            let focusedFirst = placement == .topLeft || placement == .topRight
            let replacement: TiledNode = .split(
                axis: .vertical,
                ratio: initialSplitRatio,
                first: focusedFirst ? .window(window) : .window(destination),
                second: focusedFirst ? .window(destination) : .window(window)
            )
            proposed = replacing(destination, with: replacement, in: remainder)
        }
        try validated(proposed, participants: participants)
        let proposedFrames = try frames(for: proposed, in: bounds, configuration: configuration)
        return TiledPlacementPreview(
            placement: placement,
            focusedWindow: window,
            proposedTree: proposed,
            frames: proposedFrames,
            fingerprint: fingerprint(proposed)
        )
    }

    static func reconciled(
        _ tree: TiledNode?,
        windowKeys: [WindowKey],
        weights: [CGFloat]?,
        orientation: WorkspaceLayoutOrientation
    ) -> TiledNode? {
        guard !windowKeys.isEmpty else { return nil }
        let desired = Set(windowKeys)
        guard var result = tree else {
            return flatTree(windowKeys: windowKeys, weights: weights, orientation: orientation)
        }
        for existing in result.windowKeys where !desired.contains(existing) {
            guard let trimmed = result.removing(existing) else {
                return flatTree(windowKeys: windowKeys, weights: weights, orientation: orientation)
            }
            result = trimmed
        }
        for key in windowKeys where !result.contains(key) {
            let axis: SplitAxis = orientation == .vertical ? .vertical : .horizontal
            result = .split(axis: axis, ratio: 0.5, first: result, second: .window(key))
        }
        return (try? validated(result, participants: desired)).map { result }
            ?? flatTree(windowKeys: windowKeys, weights: weights, orientation: orientation)
    }

    /// Applies an explicit workspace orientation to every split while retaining the exact BSP
    /// topology, ratios and window identities. A direct layout shortcut is intentionally a whole-
    /// workspace orientation command: horizontal means a column flow and vertical means a row
    /// flow, including a tree that was originally created from the session-local placement model.
    static func reoriented(
        _ tree: TiledNode,
        orientation: WorkspaceLayoutOrientation
    ) -> TiledNode? {
        guard orientation != .automatic,
              (try? validated(tree, participants: Set(tree.windowKeys))) != nil
        else { return nil }
        let targetAxis: SplitAxis = orientation == .vertical ? .vertical : .horizontal

        func transform(_ node: TiledNode) -> TiledNode {
            switch node {
            case .window:
                return node
            case let .split(_, ratio, first, second):
                return .split(
                    axis: targetAxis,
                    ratio: ratio,
                    first: transform(first),
                    second: transform(second)
                )
            }
        }

        let result = transform(tree)
        return (try? validated(result, participants: Set(tree.windowKeys))).map { result }
    }

    /// Workspace orientation is profile-backed, while placement trees are partitioned by physical
    /// display for the current WindowServer session. Update every retained partition for only the
    /// selected workspace so Unified displays and a disconnected Independent home agree after it
    /// reconnects, without touching another workspace.
    static func reorientedPartitions(
        _ trees: [TiledLayoutPartitionKey: TiledNode],
        workspaceID: UUID,
        orientation: WorkspaceLayoutOrientation
    ) -> [TiledLayoutPartitionKey: TiledNode] {
        guard orientation != .automatic else { return trees }
        return trees.reduce(into: [:]) { result, entry in
            if entry.key.workspaceID == workspaceID,
               let changed = reoriented(entry.value, orientation: orientation) {
                result[entry.key] = changed
            } else {
                result[entry.key] = entry.value
            }
        }
    }

    /// Exchanges the two window leaves without changing any split, ratio, or other leaf. Tiled
    /// directional movement must mutate this placement tree because it is the authoritative
    /// geometry model once a workspace has one; changing only the legacy flat order is invisible
    /// to the tree solver.
    static func swappingWindows(
        _ firstWindow: WindowKey,
        _ secondWindow: WindowKey,
        in tree: TiledNode
    ) -> TiledNode? {
        guard firstWindow != secondWindow,
              tree.contains(firstWindow),
              tree.contains(secondWindow),
              (try? validated(tree, participants: Set(tree.windowKeys))) != nil
        else { return nil }

        func swap(in node: TiledNode) -> TiledNode {
            switch node {
            case let .window(key):
                if key == firstWindow { return .window(secondWindow) }
                if key == secondWindow { return .window(firstWindow) }
                return node
            case let .split(axis, ratio, first, second):
                return .split(
                    axis: axis,
                    ratio: ratio,
                    first: swap(in: first),
                    second: swap(in: second)
                )
            }
        }

        let swapped = swap(in: tree)
        guard (try? validated(swapped, participants: Set(tree.windowKeys))) != nil else { return nil }
        return swapped
    }

    /// Moves a focused leaf across the split that directly contains it by exchanging that leaf
    /// with the complete sibling branch. This is the structural BSP interpretation of one arrow:
    /// a compound sibling keeps its internal topology and ratios instead of donating whichever
    /// individual leaf happens to be the closest visual neighbour.
    ///
    /// The search recurses so the direct split may itself be nested under unrelated ancestors.
    /// A result is produced only when the focused leaf is the direct child on the side from which
    /// the requested direction can cross the split. Callers can retain visual leaf swapping as a
    /// fallback when no such boundary exists.
    static func swappingFocusedLeafWithDirectSiblingBranch(
        _ focusedWindow: WindowKey,
        direction: WindowDirection,
        in tree: TiledNode
    ) -> (tree: TiledNode, siblingWindowKeys: [WindowKey])? {
        guard tree.contains(focusedWindow),
              (try? validated(tree, participants: Set(tree.windowKeys))) != nil
        else { return nil }

        let requestedAxis: SplitAxis = direction.axis == .horizontal ? .horizontal : .vertical
        let movesTowardFirst = direction == .left || direction == .up

        func swap(in node: TiledNode) -> (node: TiledNode, siblingWindowKeys: [WindowKey])? {
            guard case let .split(axis, ratio, first, second) = node else { return nil }

            if axis == requestedAxis {
                if movesTowardFirst,
                   case let .window(key) = second,
                   key == focusedWindow {
                    return (
                        .split(axis: axis, ratio: ratio, first: second, second: first),
                        first.windowKeys
                    )
                }
                if !movesTowardFirst,
                   case let .window(key) = first,
                   key == focusedWindow {
                    return (
                        .split(axis: axis, ratio: ratio, first: second, second: first),
                        second.windowKeys
                    )
                }
            }

            if first.contains(focusedWindow), let changed = swap(in: first) {
                return (
                    .split(axis: axis, ratio: ratio, first: changed.node, second: second),
                    changed.siblingWindowKeys
                )
            }
            if second.contains(focusedWindow), let changed = swap(in: second) {
                return (
                    .split(axis: axis, ratio: ratio, first: first, second: changed.node),
                    changed.siblingWindowKeys
                )
            }
            return nil
        }

        guard let changed = swap(in: tree),
              (try? validated(changed.node, participants: Set(tree.windowKeys))) != nil
        else { return nil }
        return (changed.node, changed.siblingWindowKeys)
    }

    /// Resizes only the nearest divider that directly contains the focused leaf. A window in a
    /// top/bottom branch therefore changes height without also changing the width allocated by an
    /// outer left/right branch. The tree topology and every unrelated split ratio stay intact.
    static func resizedNearestSplit(
        _ tree: TiledNode,
        focusedWindow: WindowKey,
        deltaPoints: Double,
        displayBounds: CGRect,
        configuration: WorkspaceLayoutConfiguration,
        minimumWindowLength: Double = 120
    ) -> TiledNode? {
        guard deltaPoints.isFinite, deltaPoints != 0,
              minimumWindowLength.isFinite, minimumWindowLength > 0,
              displayBounds.width.isFinite, displayBounds.height.isFinite,
              displayBounds.width > 0, displayBounds.height > 0,
              tree.contains(focusedWindow),
              (try? validated(tree, participants: Set(tree.windowKeys))) != nil
        else { return nil }
        let gaps = configuration.clamped().gaps
        let rootBounds = inset(displayBounds, gaps: gaps)

        func adjustedRatio(
            _ ratio: Double,
            axis: SplitAxis,
            bounds: CGRect,
            focusedInFirst: Bool
        ) -> Double? {
            let geometry = splitGeometry(axis: axis, ratio: ratio, bounds: bounds, gaps: gaps)
            let available = Double(geometry.availableLength)
            guard available.isFinite, available > 1 else { return nil }
            let minimum = min(max(1 / available, minimumWindowLength / available), 0.4)
            let lower = max(minimumSplitRatio, minimum)
            let upper = min(maximumSplitRatio, 1 - minimum)
            guard lower < upper else { return nil }
            let visibleRatio = min(max(ratio, minimumSplitRatio), maximumSplitRatio)
            let signedDelta = (focusedInFirst ? deltaPoints : -deltaPoints) / available
            if signedDelta > 0, visibleRatio >= upper - 0.000_001 { return nil }
            if signedDelta < 0, visibleRatio <= lower + 0.000_001 { return nil }
            let target = min(max(visibleRatio + signedDelta, lower), upper)
            return abs(target - visibleRatio) > 0.000_001 ? target : nil
        }

        func resize(
            _ node: TiledNode,
            bounds: CGRect
        ) -> (node: TiledNode, foundNearest: Bool, changed: Bool) {
            switch node {
            case .window:
                return (node, false, false)
            case let .split(axis, ratio, first, second):
                let geometry = splitGeometry(axis: axis, ratio: ratio, bounds: bounds, gaps: gaps)
                if first.contains(focusedWindow) {
                    let child = resize(first, bounds: geometry.first)
                    if child.foundNearest {
                        return (
                            .split(axis: axis, ratio: ratio, first: child.node, second: second),
                            true,
                            child.changed
                        )
                    }
                    guard let target = adjustedRatio(
                        ratio,
                        axis: axis,
                        bounds: bounds,
                        focusedInFirst: true
                    ) else { return (node, true, false) }
                    return (.split(axis: axis, ratio: target, first: first, second: second), true, true)
                }
                if second.contains(focusedWindow) {
                    let child = resize(second, bounds: geometry.second)
                    if child.foundNearest {
                        return (
                            .split(axis: axis, ratio: ratio, first: first, second: child.node),
                            true,
                            child.changed
                        )
                    }
                    guard let target = adjustedRatio(
                        ratio,
                        axis: axis,
                        bounds: bounds,
                        focusedInFirst: false
                    ) else { return (node, true, false) }
                    return (.split(axis: axis, ratio: target, first: first, second: second), true, true)
                }
                return (node, false, false)
            }
        }

        let result = resize(tree, bounds: rootBounds)
        guard result.foundNearest, result.changed,
              (try? validated(result.node, participants: Set(tree.windowKeys))) != nil
        else { return nil }
        return result.node
    }

    /// Returns the effective fraction of the tiled area owned by each leaf. The solver clamps
    /// split ratios to the same bounds, so these shares describe the geometry users actually see.
    static func leafShares(_ tree: TiledNode) -> [WindowKey: Double]? {
        guard (try? validated(tree, participants: Set(tree.windowKeys))) != nil else { return nil }
        var shares: [WindowKey: Double] = [:]
        func collect(_ node: TiledNode, share: Double) {
            switch node {
            case let .window(key):
                shares[key] = share
            case let .split(_, rawRatio, first, second):
                let ratio = min(max(rawRatio, minimumSplitRatio), maximumSplitRatio)
                collect(first, share: share * ratio)
                collect(second, share: share * (1 - ratio))
            }
        }
        collect(tree, share: 1)
        return shares
    }

    static func fingerprint(_ tree: TiledNode) -> String {
        switch tree {
        case let .window(key): "w:\(key.processIdentifier):\(key.windowIdentifier)"
        case let .split(axis, ratio, first, second):
            "s:\(axis.rawValue):\(String(format: "%.4f", ratio)):[\(fingerprint(first))]:[\(fingerprint(second))]"
        }
    }

    private static func validateRatios(in tree: TiledNode) throws {
        switch tree {
        case .window:
            return
        case let .split(_, ratio, first, second):
            guard ratio.isFinite, ratio > 0, ratio < 1 else { throw TiledLayoutError.invalidRatio }
            try validateRatios(in: first)
            try validateRatios(in: second)
        }
    }

    private static func solve(
        _ node: TiledNode,
        in bounds: CGRect,
        gaps: WorkspaceLayoutGaps,
        result: inout [WindowKey: WindowFrame]
    ) {
        switch node {
        case let .window(key):
            result[key] = WindowFrame(
                position: CGPoint(x: bounds.minX.rounded(), y: bounds.minY.rounded()),
                size: CGSize(width: max(1, bounds.width.rounded()), height: max(1, bounds.height.rounded()))
            )
        case let .split(axis, rawRatio, first, second):
            let geometry = splitGeometry(
                axis: axis,
                ratio: rawRatio,
                bounds: bounds,
                gaps: gaps
            )
            solve(first, in: geometry.first, gaps: gaps, result: &result)
            solve(second, in: geometry.second, gaps: gaps, result: &result)
        }
    }

    private static func splitGeometry(
        axis: SplitAxis,
        ratio rawRatio: Double,
        bounds: CGRect,
        gaps: WorkspaceLayoutGaps
    ) -> (first: CGRect, second: CGRect, availableLength: CGFloat) {
        let ratio = CGFloat(min(max(rawRatio, minimumSplitRatio), maximumSplitRatio))
        switch axis {
        case .horizontal:
            let gap = min(CGFloat(gaps.innerHorizontal), max(0, bounds.width - 2))
            let available = max(2, bounds.width - gap)
            let firstLength = max(1, (available * ratio).rounded())
            let secondLength = max(1, available - firstLength)
            return (
                CGRect(x: bounds.minX, y: bounds.minY, width: firstLength, height: bounds.height),
                CGRect(
                    x: bounds.minX + firstLength + gap,
                    y: bounds.minY,
                    width: secondLength,
                    height: bounds.height
                ),
                available
            )
        case .vertical:
            let gap = min(CGFloat(gaps.innerVertical), max(0, bounds.height - 2))
            let available = max(2, bounds.height - gap)
            let firstLength = max(1, (available * ratio).rounded())
            let secondLength = max(1, available - firstLength)
            return (
                CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: firstLength),
                CGRect(
                    x: bounds.minX,
                    y: bounds.minY + firstLength + gap,
                    width: bounds.width,
                    height: secondLength
                ),
                available
            )
        }
    }

    private static func inset(_ bounds: CGRect, gaps: WorkspaceLayoutGaps) -> CGRect {
        let gaps = gaps.clamped()
        let left = min(CGFloat(gaps.outerLeft), max(0, bounds.width - 1))
        let right = min(CGFloat(gaps.outerRight), max(0, bounds.width - left - 1))
        let top = min(CGFloat(gaps.outerTop), max(0, bounds.height - 1))
        let bottom = min(CGFloat(gaps.outerBottom), max(0, bounds.height - top - 1))
        return CGRect(
            x: bounds.minX + left,
            y: bounds.minY + top,
            width: max(1, bounds.width - left - right),
            height: max(1, bounds.height - top - bottom)
        )
    }

    private static func cornerLeaf(
        _ placement: VisualPlacement,
        frames: [WindowKey: WindowFrame],
        bounds: CGRect
    ) -> WindowKey? {
        let corner: CGPoint
        switch placement {
        case .topLeft: corner = CGPoint(x: bounds.minX, y: bounds.minY)
        case .topRight: corner = CGPoint(x: bounds.maxX, y: bounds.minY)
        case .bottomLeft: corner = CGPoint(x: bounds.minX, y: bounds.maxY)
        case .bottomRight: corner = CGPoint(x: bounds.maxX, y: bounds.maxY)
        default: return nil
        }
        return frames.min { lhs, rhs in
            distance(from: corner, to: lhs.value) < distance(from: corner, to: rhs.value)
        }?.key
    }

    private static func distance(from point: CGPoint, to frame: WindowFrame) -> CGFloat {
        let rect = CGRect(origin: frame.position, size: frame.size)
        let x = min(max(point.x, rect.minX), rect.maxX)
        let y = min(max(point.y, rect.minY), rect.maxY)
        return hypot(point.x - x, point.y - y)
    }

    private static func replacing(_ key: WindowKey, with replacement: TiledNode, in tree: TiledNode) -> TiledNode {
        switch tree {
        case let .window(candidate):
            candidate == key ? replacement : tree
        case let .split(axis, ratio, first, second):
            .split(
                axis: axis,
                ratio: ratio,
                first: replacing(key, with: replacement, in: first),
                second: replacing(key, with: replacement, in: second)
            )
        }
    }
}
