import CoreGraphics
import Foundation

enum DropDownAppGeometry {
    static let animationStepCount = 8
    static let animationDuration: TimeInterval = 0.18

    static func presentationBounds(
        in usableBounds: CGRect,
        focusedWindowHighlightEnabled: Bool
    ) -> CGRect {
        FocusedWindowHighlightPolicy.reservingScreenEdgeClearance(
            in: usableBounds,
            enabled: focusedWindowHighlightEnabled
        )
    }

    static func presentedFrame(
        in usableBounds: CGRect,
        sizeFraction: Double,
        direction: DropDownAppDirection
    ) -> WindowFrame {
        let fraction = DropDownAppConfiguration.clampedHeightFraction(sizeFraction)
        switch direction {
        case .top:
            return WindowFrame(
                position: usableBounds.origin,
                size: CGSize(width: usableBounds.width, height: usableBounds.height * fraction)
            )
        case .bottom:
            let height = usableBounds.height * fraction
            return WindowFrame(
                position: CGPoint(x: usableBounds.minX, y: usableBounds.maxY - height),
                size: CGSize(width: usableBounds.width, height: height)
            )
        case .left:
            return WindowFrame(
                position: usableBounds.origin,
                size: CGSize(width: usableBounds.width * fraction, height: usableBounds.height)
            )
        case .right:
            let width = usableBounds.width * fraction
            return WindowFrame(
                position: CGPoint(x: usableBounds.maxX - width, y: usableBounds.minY),
                size: CGSize(width: width, height: usableBounds.height)
            )
        }
    }

    static func retractedFrame(
        for presentedFrame: WindowFrame,
        in usableBounds: CGRect,
        direction: DropDownAppDirection
    ) -> WindowFrame {
        switch direction {
        case .top:
            return WindowFrame(
                position: CGPoint(x: presentedFrame.position.x, y: usableBounds.minY),
                size: CGSize(width: presentedFrame.size.width, height: 1)
            )
        case .bottom:
            return WindowFrame(
                position: CGPoint(x: presentedFrame.position.x, y: usableBounds.maxY - 1),
                size: CGSize(width: presentedFrame.size.width, height: 1)
            )
        case .left:
            return WindowFrame(
                position: CGPoint(x: usableBounds.minX, y: presentedFrame.position.y),
                size: CGSize(width: 1, height: presentedFrame.size.height)
            )
        case .right:
            return WindowFrame(
                position: CGPoint(x: usableBounds.maxX - 1, y: presentedFrame.position.y),
                size: CGSize(width: 1, height: presentedFrame.size.height)
            )
        }
    }

    static func animationFrames(
        from start: WindowFrame,
        to end: WindowFrame,
        stepCount: Int = animationStepCount
    ) -> [WindowFrame] {
        guard stepCount > 0 else { return [end] }
        return (1...stepCount).map { step in
            let progress = CGFloat(step) / CGFloat(stepCount)
            let eased = 1 - pow(1 - progress, 3)
            return WindowFrame(
                position: CGPoint(
                    x: start.position.x + ((end.position.x - start.position.x) * eased),
                    y: start.position.y + ((end.position.y - start.position.y) * eased)
                ),
                size: CGSize(
                    width: start.size.width + ((end.size.width - start.size.width) * eased),
                    height: start.size.height + ((end.size.height - start.size.height) * eased)
                )
            )
        }
    }
}
