import CoreGraphics
import Foundation

/// A pure, no-write proposal for placing one Freeform window inside one display's usable bounds.
/// The focused window is the only affected window; unlike Tiled placement, no layout tree changes.
struct FreeformPlacementPreview: Equatable, Sendable {
    let placement: VisualPlacement
    let focusedWindow: WindowKey
    let displayIdentifier: String
    let displayBounds: CGRect
    let originalFrame: WindowFrame
    let targetFrame: WindowFrame
}

struct FreeformPlacementUndoTransaction: Equatable, Sendable {
    let focusedWindow: WindowKey
    let workspaceID: UUID
    let displayIdentifier: String
    let beforeFrame: WindowFrame
    let afterFrame: WindowFrame
    let actionName: String

    func expectedFrame(for direction: FreeformPlacementHistoryDirection) -> WindowFrame {
        direction == .undo ? afterFrame : beforeFrame
    }

    func targetFrame(for direction: FreeformPlacementHistoryDirection) -> WindowFrame {
        direction == .undo ? beforeFrame : afterFrame
    }
}

enum FreeformPlacementHistoryDirection: String, Equatable, Sendable {
    case undo
    case redo
}

enum FreeformPlacementEngine {
    static func preview(
        focusedWindow: WindowKey,
        displayIdentifier: String,
        originalFrame: WindowFrame,
        placement: VisualPlacement,
        displayBounds: CGRect
    ) -> FreeformPlacementPreview? {
        guard displayBounds.width >= 2, displayBounds.height >= 2 else { return nil }
        return FreeformPlacementPreview(
            placement: placement,
            focusedWindow: focusedWindow,
            displayIdentifier: displayIdentifier,
            displayBounds: displayBounds,
            originalFrame: originalFrame,
            targetFrame: frame(for: placement, in: displayBounds)
        )
    }

    static func frame(for placement: VisualPlacement, in bounds: CGRect) -> WindowFrame {
        let leftWidth = floor(bounds.width / 2)
        let rightWidth = bounds.width - leftWidth
        let topHeight = floor(bounds.height / 2)
        let bottomHeight = bounds.height - topHeight
        let rect: CGRect = switch placement {
        case .topLeft:
            CGRect(x: bounds.minX, y: bounds.minY, width: leftWidth, height: topHeight)
        case .top:
            CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: topHeight)
        case .topRight:
            CGRect(x: bounds.minX + leftWidth, y: bounds.minY, width: rightWidth, height: topHeight)
        case .left:
            CGRect(x: bounds.minX, y: bounds.minY, width: leftWidth, height: bounds.height)
        case .right:
            CGRect(x: bounds.minX + leftWidth, y: bounds.minY, width: rightWidth, height: bounds.height)
        case .bottomLeft:
            CGRect(x: bounds.minX, y: bounds.minY + topHeight, width: leftWidth, height: bottomHeight)
        case .bottom:
            CGRect(x: bounds.minX, y: bounds.minY + topHeight, width: bounds.width, height: bottomHeight)
        case .bottomRight:
            CGRect(
                x: bounds.minX + leftWidth,
                y: bounds.minY + topHeight,
                width: rightWidth,
                height: bottomHeight
            )
        }
        return WindowFrame(
            position: CGPoint(x: rect.minX.rounded(), y: rect.minY.rounded()),
            size: CGSize(width: max(1, rect.width.rounded()), height: max(1, rect.height.rounded()))
        )
    }
}
