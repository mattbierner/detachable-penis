import Foundation

public func clamp(_ value: Float, _ minValue: Float, _ maxValue: Float) -> Float {
    return max(minValue, min(maxValue, value));
}

public func clamp(_ value: UInt32, _ minValue: UInt32, _ maxValue: UInt32) -> UInt32 {
    return max(minValue, min(maxValue, value));
}
