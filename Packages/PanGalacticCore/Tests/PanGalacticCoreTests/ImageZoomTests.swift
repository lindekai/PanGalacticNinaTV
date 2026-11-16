import Foundation
import Testing
@testable import PanGalacticCore

@Suite("Viewer zoom")
struct ImageZoomTests {
    /// IMX571 frame on a 4K screen (pixels).
    let image = CGSize(width: 6248, height: 4176)
    let screen = CGSize(width: 3840, height: 2160)

    @Test func stepsStartAtFitAndSkipMagnificationsCloseToIt() {
        let fit = 2160.0 / 4176 // ≈ 0.52: 0.25 and 0.5 are below or too close
        let scales = ImageZoom.scales(image: image, screen: screen)
        #expect(abs(scales[0] - fit) < 1e-9)
        #expect(Array(scales.dropFirst()) == [0.75, 1, 1.5, 2, 3, 4])
    }

    @Test func aHDScreenGetsMoreStepsThanA4KScreen() {
        let hd = CGSize(width: 1920, height: 1080) // fit ≈ 0.26
        #expect(Array(ImageZoom.scales(image: image, screen: hd).dropFirst()) == [0.5, 0.75, 1, 1.5, 2, 3, 4])
    }

    @Test func zoomInStopsAtTheLastStepAndZoomOutReturnsToFit() {
        var zoom = ImageZoom()
        #expect(zoom.isFitted && !zoom.needsFullResolution)
        var clicks = 0
        while zoom.zoomIn(image: image, screen: screen) { clicks += 1 }
        #expect(clicks == 6)
        #expect(zoom.scale(image: image, screen: screen) == 4)
        while zoom.zoomOut(image: image, screen: screen) {}
        #expect(zoom.isFitted && zoom.centerX == 0.5 && zoom.centerY == 0.5)
        let steppedOut = zoom.zoomOut(image: image, screen: screen)
        #expect(!steppedOut, "fitted: the caller closes the viewer")
    }

    @Test func withoutTheImageSizeOnlyTheFirstStepIsAllowed() {
        var zoom = ImageZoom()
        let first = zoom.zoomIn(image: nil, screen: screen)
        let second = zoom.zoomIn(image: nil, screen: screen)
        #expect(first && !second)
        #expect(zoom.needsFullResolution)
    }

    @Test func smallFramesNeverZoomBelowFit() {
        let small = CGSize(width: 1000, height: 600) // fit 3.6: no step above it
        var zoom = ImageZoom()
        let zoomed = zoom.zoomIn(image: small, screen: screen)
        #expect(!zoomed)
        #expect(ImageZoom.stepCount(image: small, screen: screen) == 1)
    }

    @Test func arrowMovesAQuarterScreenAndStopsAtTheEdge() {
        var zoom = ImageZoom()
        zoom.zoomIn(image: image, screen: screen)
        zoom.zoomIn(image: image, screen: screen) // 1:1: 3840 of 6248 px visible
        let visibleX = 3840.0 / 6248
        for _ in 0..<20 { zoom.pan(.left, image: image, screen: screen) }
        #expect(abs(zoom.centerX - visibleX / 2) < 1e-9, "left edge of the image meets the screen edge")
        zoom.pan(.right, image: image, screen: screen)
        #expect(abs(zoom.centerX - visibleX * 0.75) < 1e-9, "a quarter screen to the right")
        for _ in 0..<20 { zoom.pan(.up, image: image, screen: screen) }
        #expect(abs(zoom.centerY - (2160.0 / 4176) / 2) < 1e-9)
    }

    @Test func dragMovesByScreenPixelsAtTheCurrentMagnification() {
        var zoom = ImageZoom()
        for _ in 0..<3 { zoom.zoomIn(image: image, screen: screen) } // 150 %
        zoom.drag(by: CGSize(width: 300, height: -150), image: image, screen: screen)
        #expect(abs(zoom.centerX - (0.5 + 300 / 1.5 / 6248)) < 1e-9)
        #expect(abs(zoom.centerY - (0.5 - 150 / 1.5 / 4176)) < 1e-9)
    }

    @Test func zoomingOutKeepsTheViewInsideTheImage() {
        var zoom = ImageZoom()
        while zoom.zoomIn(image: image, screen: screen) {}
        for _ in 0..<40 { zoom.pan(.right, image: image, screen: screen) }
        zoom.zoomOut(image: image, screen: screen)
        zoom.zoomOut(image: image, screen: screen)
        zoom.zoomOut(image: image, screen: screen) // 150 %
        let visible = zoom.visibleRect(image: image, screen: screen)
        #expect(abs(visible.maxX - 1) < 1e-9)
    }

    @Test func visibleRectCoversTheWholeImageWhenFitted() {
        let visible = ImageZoom().visibleRect(image: image, screen: screen)
        #expect(visible.height == 1 && visible.minY == 0)
        #expect(visible.width <= 1)
    }

    @Test func noPanningWhileFitted() {
        var zoom = ImageZoom()
        zoom.pan(.left, image: image, screen: screen)
        zoom.drag(by: CGSize(width: 500, height: 0), image: image, screen: screen)
        #expect(zoom.centerX == 0.5)
    }
}
