import SwiftUI
import UIKit

/// Continuous swipes on the Siri Remote touch surface. SwiftUI on tvOS only reports
/// swipes as discrete move commands, so a pan recognizer on the window reports the
/// finger's movement in points. Enabled only while the viewer is zoomed, so swipes
/// keep driving focus everywhere else.
struct RemotePanSurface: UIViewRepresentable {
    let isEnabled: Bool
    let onPan: @MainActor (CGSize) -> Void

    func makeUIView(context: Context) -> HostView {
        HostView(onPan: onPan)
    }

    func updateUIView(_ view: HostView, context: Context) {
        view.onPan = onPan
        view.recognizer.isEnabled = isEnabled
    }

    static func dismantleUIView(_ view: HostView, coordinator: ()) {
        view.recognizer.view?.removeGestureRecognizer(view.recognizer)
    }

    final class HostView: UIView {
        var onPan: @MainActor (CGSize) -> Void
        let recognizer = UIPanGestureRecognizer()

        init(onPan: @escaping @MainActor (CGSize) -> Void) {
            self.onPan = onPan
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            recognizer.addTarget(self, action: #selector(handle(_:)))
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }

        @objc private func handle(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed, let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            recognizer.setTranslation(.zero, in: view)
            onPan(CGSize(width: translation.x, height: translation.y))
        }
    }
}
