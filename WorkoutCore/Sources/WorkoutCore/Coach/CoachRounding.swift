import Foundation

/// Every number the Coach emits passes through here.
///
/// The real anti-drift property is structural rather than numeric: the Coach never
/// accumulates. Each proposal is computed fresh from the slot's stored target as
/// `canonical(current + n × step)` for an integer `n`, so there is no running total to
/// drift. `canonical` is the belt to that pair of braces — it is a no-op on a clean grid
/// like 60 kg in steps of 2.5, and load-bearing on a micro-loading step of 0.3, where ten
/// naive additions from 20.0 reach 23.000000000000007 and compare unequal to 23.0.
public enum CoachRounding {
    /// Canonicalize to three decimals — one gram, one millimetre, one millisecond, which is
    /// below any granularity this app can mean.
    public static func canonical(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (value * 1000).rounded() / 1000
    }

    /// Whole number of steps nearest to `magnitude`, never fewer than one.
    ///
    /// Nearest, not up: a deload is specified as "~10%", and rounding up turns a 60 kg
    /// target into 52.5 (−12.5%) and a 5-rep target into 4 (−20%), both presented to the
    /// lifter as ten percent. Nearest lands on 55 kg (−8.3%) and keeps the climb back
    /// retracing numbers the lifter already owns.
    public static func stepsNearest(_ magnitude: Double, step: Double) -> Int {
        guard step > 0, magnitude.isFinite, magnitude > 0 else { return 1 }
        let n = (magnitude / step).rounded()
        guard n.isFinite else { return 1 }
        return max(1, Int(n))
    }

    /// Zero-anchored floor onto the step grid. Used for the e1RM seed and nowhere else:
    /// every other number the Coach emits is relative and inherits the lifter's own grid,
    /// but a seed has no prior grid to inherit and must land on a weight that can actually
    /// be loaded.
    public static func snapDown(_ value: Double, step: Double) -> Double {
        guard step > 0, value.isFinite, value > 0 else { return 0 }
        return canonical((value / step).rounded(.down) * step)
    }

    /// Converts an axis value back to the `Int` the model stores. Total: a non-finite or
    /// out-of-range result falls back to the current value rather than trapping.
    public static func integer(_ value: Double, fallback: Int?) -> Int? {
        let c = canonical(value).rounded()
        guard c.isFinite, c >= Double(Int.min), c <= Double(Int.max) else { return fallback }
        return Int(c)
    }
}
