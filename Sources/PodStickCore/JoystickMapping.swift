import Foundation

public struct StickVector: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public static let zero = StickVector(x: 0, y: 0)

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public var magnitude: Double {
        hypot(x, y)
    }
}

public struct MotionQuaternion: Equatable, Sendable {
    public var w: Double
    public var x: Double
    public var y: Double
    public var z: Double

    public init(w: Double, x: Double, y: Double, z: Double) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    public static let identity = MotionQuaternion(w: 1, x: 0, y: 0, z: 0)

    public var normalized: MotionQuaternion {
        let length = sqrt(w * w + x * x + y * y + z * z)
        guard length > .ulpOfOne else { return .identity }
        return MotionQuaternion(w: w / length, x: x / length, y: y / length, z: z / length)
    }

    public var inverse: MotionQuaternion {
        let q = normalized
        return MotionQuaternion(w: q.w, x: -q.x, y: -q.y, z: -q.z)
    }

    public func multiplied(by rhs: MotionQuaternion) -> MotionQuaternion {
        MotionQuaternion(
            w: w * rhs.w - x * rhs.x - y * rhs.y - z * rhs.z,
            x: w * rhs.x + x * rhs.w + y * rhs.z - z * rhs.y,
            y: w * rhs.y - x * rhs.z + y * rhs.w + z * rhs.x,
            z: w * rhs.z + x * rhs.y - y * rhs.x + z * rhs.w
        ).normalized
    }

    public static func fromEuler(roll: Double, pitch: Double, yaw: Double) -> MotionQuaternion {
        let cr = cos(roll / 2)
        let sr = sin(roll / 2)
        let cp = cos(pitch / 2)
        let sp = sin(pitch / 2)
        let cy = cos(yaw / 2)
        let sy = sin(yaw / 2)

        return MotionQuaternion(
            w: cr * cp * cy + sr * sp * sy,
            x: sr * cp * cy - cr * sp * sy,
            y: cr * sp * cy + sr * cp * sy,
            z: cr * cp * sy - sr * sp * cy
        ).normalized
    }

    public static func fromRotationVector(x: Double, y: Double, z: Double) -> MotionQuaternion {
        let angle = sqrt(x * x + y * y + z * z)
        guard angle > .ulpOfOne else { return .identity }
        let scale = sin(angle / 2) / angle
        return MotionQuaternion(
            w: cos(angle / 2),
            x: x * scale,
            y: y * scale,
            z: z * scale
        ).normalized
    }

    public var rotationVectorRadians: (x: Double, y: Double, z: Double) {
        var q = normalized
        if q.w < 0 {
            q = MotionQuaternion(w: -q.w, x: -q.x, y: -q.y, z: -q.z)
        }
        let halfSine = sqrt(q.x * q.x + q.y * q.y + q.z * q.z)
        guard halfSine > .ulpOfOne else { return (0, 0, 0) }
        let angle = 2 * atan2(halfSine, q.w)
        let scale = angle / halfSine
        return (q.x * scale, q.y * scale, q.z * scale)
    }

    public var rollAndPitch: (roll: Double, pitch: Double) {
        let q = normalized
        let roll = atan2(
            2 * (q.w * q.x + q.y * q.z),
            1 - 2 * (q.x * q.x + q.y * q.y)
        )
        let sinPitch = 2 * (q.w * q.y - q.z * q.x)
        let pitch = asin(max(-1, min(1, sinPitch)))
        return (roll, pitch)
    }
}

public struct GripCalibratedMapper: Sendable {
    public var deadzone: Double

    // Least-squares fit from the first physical PodStick capture. Inputs are
    // relative quaternion rotation-vector components expressed in degrees.
    // Targets were neutral (0,0), forward (0,-1), backward (0,1), left (-1,0),
    // and right (1,0).
    private let xCoefficients = (x: 0.02076468, y: -0.01998259, z: 0.01849727)
    private let yCoefficients = (x: 0.04204659, y: 0.02003173, z: 0.01806356)

    public init(deadzone: Double = 0.08) {
        self.deadzone = deadzone
    }

    public func map(
        attitude: MotionQuaternion,
        relativeTo reference: MotionQuaternion
    ) -> StickVector {
        let rotation = reference.inverse.multiplied(by: attitude).rotationVectorRadians
        let radiansToDegrees = 180 / Double.pi
        let rx = rotation.x * radiansToDegrees
        let ry = rotation.y * radiansToDegrees
        let rz = rotation.z * radiansToDegrees

        var vector = StickVector(
            x: rx * xCoefficients.x + ry * xCoefficients.y + rz * xCoefficients.z,
            y: rx * yCoefficients.x + ry * yCoefficients.y + rz * yCoefficients.z
        )

        let length = vector.magnitude
        if length > 1 {
            vector = StickVector(x: vector.x / length, y: vector.y / length)
        }

        let zone = max(0, min(deadzone, 0.95))
        let clampedLength = vector.magnitude
        guard clampedLength > zone else { return .zero }
        let scaledLength = min(1, (clampedLength - zone) / (1 - zone))
        return StickVector(
            x: vector.x / clampedLength * scaledLength,
            y: vector.y / clampedLength * scaledLength
        )
    }
}

public struct JoystickMapper: Sendable {
    public var fullDeflectionRadians: Double
    public var deadzone: Double

    public init(fullDeflectionRadians: Double = .pi / 6, deadzone: Double = 0.08) {
        self.fullDeflectionRadians = fullDeflectionRadians
        self.deadzone = deadzone
    }

    public func map(
        attitude: MotionQuaternion,
        relativeTo reference: MotionQuaternion,
        invertX: Bool = false,
        invertY: Bool = true
    ) -> StickVector {
        let relative = reference.inverse.multiplied(by: attitude)
        let angles = relative.rollAndPitch
        let range = max(fullDeflectionRadians, .ulpOfOne)

        var vector = StickVector(
            x: angles.roll / range * (invertX ? -1 : 1),
            y: angles.pitch / range * (invertY ? -1 : 1)
        )
        vector = clampToUnitCircle(vector)
        return applyRadialDeadzone(vector)
    }

    private func clampToUnitCircle(_ vector: StickVector) -> StickVector {
        let length = vector.magnitude
        guard length > 1 else { return vector }
        return StickVector(x: vector.x / length, y: vector.y / length)
    }

    private func applyRadialDeadzone(_ vector: StickVector) -> StickVector {
        let zone = max(0, min(deadzone, 0.95))
        let length = vector.magnitude
        guard length > zone else { return .zero }

        let scaledLength = min(1, (length - zone) / (1 - zone))
        return StickVector(
            x: vector.x / length * scaledLength,
            y: vector.y / length * scaledLength
        )
    }
}

public struct ExponentialStickSmoother: Sendable {
    public var timeConstant: TimeInterval
    private var value = StickVector.zero
    private var lastTimestamp: TimeInterval?

    public init(timeConstant: TimeInterval = 0.04) {
        self.timeConstant = timeConstant
    }

    public mutating func reset(to value: StickVector = .zero, at timestamp: TimeInterval? = nil) {
        self.value = value
        lastTimestamp = timestamp
    }

    public mutating func update(_ input: StickVector, at timestamp: TimeInterval) -> StickVector {
        guard let lastTimestamp else {
            self.lastTimestamp = timestamp
            value = input
            return input
        }

        let delta = max(0, timestamp - lastTimestamp)
        self.lastTimestamp = timestamp
        let tau = max(timeConstant, .ulpOfOne)
        let alpha = 1 - exp(-delta / tau)
        value.x += alpha * (input.x - value.x)
        value.y += alpha * (input.y - value.y)
        return value
    }
}
