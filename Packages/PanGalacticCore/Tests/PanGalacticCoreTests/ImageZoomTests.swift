import Foundation
import Testing
@testable import PanGalacticCore

@Suite("Viewer zoom")
struct ImageZoomTests {
    /// IMX571 frame on a 4K screen (pixels).
    let image = CGSize(width: 6248, height: 4176)
    let screen = CGSize(width: 3840, height: 2160)

    @Test func clickCyclesFitHalfFullAndBack() {
        var zoom = ImageZoom()
        #expect(zoom.level == .fit && !zoom.needsFullResolution)
        zoom.cycle()
        #expect(zoom.level == .closer && zoom.needsFullResolution)
        let fit = ImageZoom.fitScale(image: image, screen: screen)
        #expect(abs(zoom.scale(image: image, screen: screen) - fit.squareRoot()) < 1e-9, "between fit and 1:1")
        zoom.cycle()
        #expect(zoom.level == .full)
        #expect(zoom.scale(image: image, screen: screen) == 1)
        zoom.cycle()
        #expect(zoom.level == .fit && zoom.centerX == 0.5 && zoom.centerY == 0.5)
    }

    @Test func fitScaleUsesTheTighterAxis() {
        #expect(abs(ImageZoom.fitScale(image: image, screen: screen) - 2160.0 / 4176) < 1e-9)
    }

    @Test func smallFramesNeverZoomBelowFit() {
        var zoom = ImageZoom()
        zoom.cycle()
        let small = CGSize(width: 1000, height: 600)
        #expect(zoom.scale(image: small, screen: screen) == ImageZoom.fitScale(image: small, screen: screen))
    }

    @Test func panMovesHalfAScreenAndStopsAtTheEdge() {
        var zoom = ImageZoom()
        zoom.cycle()
        zoom.cycle() // 1:1: 3840 of 6248 px visible
        let visibleX = 3840.0 / 6248
        for _ in 0..<10 { zoom.pan(.left, image: image, screen: screen) }
        #expect(abs(zoom.centerX - visibleX / 2) < 1e-9, "left edge of the image meets the screen edge")
        zoom.pan(.right, image: image, screen: screen)
        #expect(abs(zoom.centerX - visibleX) < 1e-9, "half a screen to the right")
        for _ in 0..<10 { zoom.pan(.right, image: image, screen: screen) }
        #expect(abs(zoom.centerX - (1 - visibleX / 2)) < 1e-9, "right edge of the image meets the screen edge")
        for _ in 0..<10 { zoom.pan(.up, image: image, screen: screen) }
        #expect(abs(zoom.centerY - (2160.0 / 4176) / 2) < 1e-9)
    }

    @Test func noPanningWhileFitted() {
        var zoom = ImageZoom()
        zoom.pan(.left, image: image, screen: screen)
        #expect(zoom.centerX == 0.5)
    }
}
