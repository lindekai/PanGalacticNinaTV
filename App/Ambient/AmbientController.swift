import Observation
import PanGalacticCore
import SwiftUI
import UIKit

/// Tracks remote input and decides when the ambient view covers the overview
/// (spec: "Ambient mode"). The decision itself lives in `AmbientPolicy`.
@MainActor
@Observable
final class AmbientController {
    static let enabledKey = "ambient.enabled"
    static let delayKey = "ambient.delayMinutes"

    private(set) var isShowing = false
    @ObservationIgnored private var lastInput = Date()
    @ObservationIgnored private var monitor: InputMonitor?

    var policy: AmbientPolicy {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        let minutes = defaults.object(forKey: Self.delayKey) as? Int ?? AmbientPolicy.defaultDelayMinutes
        return AmbientPolicy(enabled: enabled, delayMinutes: minutes)
    }

    /// Any press or touch on the remote; leaves the ambient view at once.
    func registerInput() {
        lastInput = Date()
        if isShowing { isShowing = false }
    }

    func evaluate(now: Date, alarm: Bool, eligible: Bool) {
        let show = eligible && policy.showsAmbient(lastInput: lastInput, now: now, alarm: alarm)
        if show != isShowing { isShowing = show }
    }

    /// While the overview is on screen and ambient mode is enabled, the system screensaver
    /// stays off; this is the only place the idle timer is touched.
    func overviewVisible(_ visible: Bool) {
        UIApplication.shared.isIdleTimerDisabled = visible && policy.enabled
        if visible {
            lastInput = Date()
            installMonitor()
        }
    }

    private func installMonitor() {
        guard monitor == nil,
              let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow) else { return }
        let monitor = InputMonitor { [weak self] in self?.registerInput() }
        window.addGestureRecognizer(monitor)
        self.monitor = monitor
    }
}

/// Observes every press and touch that reaches the window without taking part in
/// gesture recognition: it fails immediately, so buttons and focus behave as before.
private final class InputMonitor: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private let onInput: @MainActor () -> Void

    init(onInput: @escaping @MainActor () -> Void) {
        self.onInput = onInput
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        allowedPressTypes = [UIPress.PressType.select, .menu, .playPause, .upArrow, .downArrow, .leftArrow, .rightArrow,
                             .pageUp, .pageDown].map { NSNumber(value: $0.rawValue) }
        delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onInput()
        state = .failed
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        onInput()
        state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
