import Foundation

/// Zoom and pan state of the full-screen viewer. A click cycles fit → closer → 1:1;
/// a swipe moves the visible part by half a screen. The server cannot crop, so the
/// 1:1 view pans across the full-resolution render on the TV (source review 2026-11-16).
public struct ImageZoom: Equatable, Sendable {
    public enum Level: Equatable, Sendable, CaseIterable {
        /// Whole frame on screen.
        case fit
        /// Halfway between fit and 1:1 (geometric mean): a fixed 50 % would equal "fit"
        /// for a 26 MP frame on a 4K screen.
        case closer
        /// One image pixel per screen pixel.
        case full
    }

    public enum Direction: Sendable { case left, right, up, down }

    public private(set) var level: Level = .fit
    /// Centre of the visible part in image coordinates, 0…1 on each axis.
    public private(set) var centerX = 0.5
    public private(set) var centerY = 0.5

    public init() {}

    /// Needs the full-resolution render.
    public var needsFullResolution: Bool { level != .fit }

    /// Screen pixels per image pixel; never smaller than fitting, so a small frame
    /// does not get a level that shows less than the whole image.
    public func scale(image: CGSize, screen: CGSize) -> Double {
        let fit = Self.fitScale(image: image, screen: screen)
        switch level {
        case .fit: return fit
        case .closer: return fit >= 1 ? fit : fit.squareRoot()
        case .full: return max(fit, 1)
        }
    }

    public static func fitScale(image: CGSize, screen: CGSize) -> Double {
        guard image.width > 0, image.height > 0 else { return 1 }
        return min(screen.width / image.width, screen.height / image.height)
    }

    public mutating func cycle() {
        switch level {
        case .fit: level = .closer
        case .closer: level = .full
        case .full: reset()
        }
    }

    public mutating func reset() {
        level = .fit
        centerX = 0.5
        centerY = 0.5
    }

    /// Moves by half the visible width or height and keeps the view inside the image.
    public mutating func pan(_ direction: Direction, image: CGSize, screen: CGSize) {
        guard level != .fit, image.width > 0, image.height > 0 else { return }
        let scale = scale(image: image, screen: screen)
        let visibleX = min(1, screen.width / scale / image.width)
        let visibleY = min(1, screen.height / scale / image.height)
        switch direction {
        case .left: centerX -= visibleX / 2
        case .right: centerX += visibleX / 2
        case .up: centerY -= visibleY / 2
        case .down: centerY += visibleY / 2
        }
        centerX = min(max(centerX, visibleX / 2), 1 - visibleX / 2)
        centerY = min(max(centerY, visibleY / 2), 1 - visibleY / 2)
    }
}
