import Foundation

public struct TapImpulseDetector: Sendable {
    public var thresholdG: Double
    public var cooldown: TimeInterval
    private var lastTriggerTimestamp: TimeInterval?

    public init(thresholdG: Double = 0.35, cooldown: TimeInterval = 0.22) {
        self.thresholdG = thresholdG
        self.cooldown = cooldown
    }

    public mutating func reset() {
        lastTriggerTimestamp = nil
    }

    public mutating func update(
        accelerationMagnitudeG: Double,
        timestamp: TimeInterval
    ) -> Bool {
        guard accelerationMagnitudeG >= thresholdG else { return false }
        if let lastTriggerTimestamp,
           timestamp - lastTriggerTimestamp < cooldown {
            return false
        }
        lastTriggerTimestamp = timestamp
        return true
    }
}
