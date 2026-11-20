import Foundation

// Degree-based trigonometry for the astronomy engine (Meeus works in degrees).
func sinDeg(_ x: Double) -> Double { sin(x * .pi / 180) }
func cosDeg(_ x: Double) -> Double { cos(x * .pi / 180) }
func tanDeg(_ x: Double) -> Double { tan(x * .pi / 180) }
func asinDeg(_ x: Double) -> Double { asin(max(-1, min(1, x))) * 180 / .pi }
func atan2Deg(_ y: Double, _ x: Double) -> Double { atan2(y, x) * 180 / .pi }

/// 0 ..< 360.
func normalizedDegrees(_ x: Double) -> Double {
    let r = x.truncatingRemainder(dividingBy: 360)
    return r < 0 ? r + 360 : r
}
