import Foundation
import Testing
@testable import PanGalacticCore

@Suite("Ambient mode")
struct AmbientPolicyTests {
    let input = Date(timeIntervalSince1970: 1_000_000)

    @Test func entersAfterTheDelayWithoutInput() {
        let policy = AmbientPolicy(delayMinutes: 5)
        #expect(!policy.showsAmbient(lastInput: input, now: input + 299, alarm: false))
        #expect(policy.showsAmbient(lastInput: input, now: input + 300, alarm: false))
    }

    @Test func neverWhileSwitchedOffOrDuringAnAlarm() {
        #expect(!AmbientPolicy(enabled: false).showsAmbient(lastInput: input, now: input + 3600, alarm: false))
        #expect(!AmbientPolicy().showsAmbient(lastInput: input, now: input + 3600, alarm: true))
    }

    @Test func defaultsAndBounds() {
        #expect(AmbientPolicy().delay == 300)
        #expect(AmbientPolicy(delayMinutes: 0).delay == 60, "at least one minute")
        #expect(AmbientPolicy.delayChoices.contains(AmbientPolicy.defaultDelayMinutes))
    }

    @Test func alarmsAreOfflineOrOverdue() {
        #expect(AmbientPolicy.isAlarm(phase: .offline, exposure: .unknown))
        #expect(AmbientPolicy.isAlarm(phase: .live, exposure: .overdue))
        #expect(!AmbientPolicy.isAlarm(phase: .live, exposure: .running(secondsLeft: 30)))
        #expect(!AmbientPolicy.isAlarm(phase: .stale, exposure: .unknown), "stale is labelled, not an alarm")
    }

    @Test func stripMovesEveryThreeMinutes() {
        let start = Date(timeIntervalSince1970: 0)
        let first = AmbientPolicy.stripShift(at: start)
        let same = AmbientPolicy.stripShift(at: start + 179)
        let next = AmbientPolicy.stripShift(at: start + 180)
        #expect(first == same)
        #expect(first != next)
        #expect(abs(next.x) <= 40 && next.y <= 0 && next.y >= -48)
    }
}
