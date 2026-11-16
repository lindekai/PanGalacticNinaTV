import Foundation
import CoreGraphics

/// Zoom and pan state of the full-screen viewer. Step 0 fits the whole frame; each
/// further step is a fixed magnification from `magnifications` that is noticeably
/// larger than fitting. The server cannot crop, so zoomed views pan across the
/// full-resolution render on the TV (source review 2026-11-16).
public struct ImageZoom: Equatable, Sendable {
    public enum Direction: Sendable { case left, right, up, down }

    /// Screen pixels per image pixel; 1 is 1:1.
    public static let magnifications: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4]
    /// A step must magnify at least this much more than fitting, so no step looks like "fit".
    static let minimumGainOverFit = 1.2
    /// Share of the visible width or height one arrow click moves.
    static let arrowStep = 0.25

    /// 0 fits the frame; higher values index `scales(image:screen:)`.
    public private(set) var step = 0
    /// Centre of the visible part in image coordinates, 0…1 on each axis.
    public private(set) var centerX = 0.5
    public private(set) var centerY = 0.5

    public init() {}

    public var isFitted: Bool { step == 0 }
    /// Needs the full-resolution render.
    public var needsFullResolution: Bool { step > 0 }

    /// Fitting first, then every magnification sufficiently above it.
    public static func scales(image: CGSize, screen: CGSize) -> [Double] {
        let fit = fitScale(image: image, screen: screen)
        return [fit] + magnifications.filter { $0 >= fit * minimumGainOverFit }
    }

    public static func fitScale(image: CGSize, screen: CGSize) -> Double {
        guard image.width > 0, image.height > 0 else { return 1 }
        return min(screen.width / image.width, screen.height / image.height)
    }

    /// Screen pixels per image pixel at the current step.
    public func scale(image: CGSize, screen: CGSize) -> Double {
        let scales = Self.scales(image: image, screen: screen)
        return scales[min(step, scales.count - 1)]
    }

    /// Steps available for this image, including fitting.
    public static func stepCount(image: CGSize, screen: CGSize) -> Int {
        scales(image: image, screen: screen).count
    }

    /// One step closer. Without a known image size only the first step is allowed:
    /// it starts the full-resolution render that tells the real number of steps.
    @discardableResult
    public mutating func zoomIn(image: CGSize?, screen: CGSize) -> Bool {
        let count = image.map { Self.stepCount(image: $0, screen: screen) } ?? 2
        guard step + 1 < count else { return false }
        step += 1
        if let image { clamp(image: image, screen: screen) }
        return true
    }

    /// One step back; returns false when already fitted.
    @discardableResult
    public mutating func zoomOut(image: CGSize?, screen: CGSize) -> Bool {
        guard step > 0 else { return false }
        step -= 1
        if step == 0 {
            reset()
        } else if let image {
            clamp(image: image, screen: screen)
        }
        return true
    }

    public mutating func reset() {
        step = 0
        centerX = 0.5
        centerY = 0.5
    }

    /// Arrow click: moves a quarter of the visible width or height.
    public mutating func pan(_ direction: Direction, image: CGSize, screen: CGSize) {
        let visible = visibleRect(image: image, screen: screen)
        switch direction {
        case .left: move(dx: -visible.width * Self.arrowStep, dy: 0, image: image, screen: screen)
        case .right: move(dx: visible.width * Self.arrowStep, dy: 0, image: image, screen: screen)
        case .up: move(dx: 0, dy: -visible.height * Self.arrowStep, image: image, screen: screen)
        case .down: move(dx: 0, dy: visible.height * Self.arrowStep, image: image, screen: screen)
        }
    }

    /// Swipe: moves the visible part by a distance in screen pixels. The caller decides
    /// the sign; the viewer passes the negated swipe so the picture follows the finger.
    public mutating func drag(by screenDelta: CGSize, image: CGSize, screen: CGSize) {
        let scale = scale(image: image, screen: screen)
        guard image.width > 0, image.height > 0, scale > 0 else { return }
        move(dx: screenDelta.width / scale / image.width, dy: screenDelta.height / scale / image.height,
             image: image, screen: screen)
    }

    /// Visible part in image coordinates (0…1), for the overview map.
    public func visibleRect(image: CGSize, screen: CGSize) -> CGRect {
        let scale = scale(image: image, screen: screen)
        guard image.width > 0, image.height > 0, scale > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let width = min(1, screen.width / scale / image.width)
        let height = min(1, screen.height / scale / image.height)
        return CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
    }

    private mutating func move(dx: Double, dy: Double, image: CGSize, screen: CGSize) {
        guard step > 0 else { return }
        centerX += dx
        centerY += dy
        clamp(image: image, screen: screen)
    }

    /// Keeps the view inside the image; an axis that fits entirely stays centred.
    private mutating func clamp(image: CGSize, screen: CGSize) {
        let visible = visibleRect(image: image, screen: screen)
        centerX = min(max(centerX, visible.width / 2), 1 - visible.width / 2)
        centerY = min(max(centerY, visible.height / 2), 1 - visible.height / 2)
    }
}
