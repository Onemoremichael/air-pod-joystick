import Foundation
import Testing
@testable import PodStickCore

@Test func neutralMapsToZero() {
    let mapper = JoystickMapper(deadzone: 0)
    let attitude = MotionQuaternion.fromEuler(roll: 0.4, pitch: -0.2, yaw: 0.8)

    #expect(mapper.map(attitude: attitude, relativeTo: attitude).magnitude < 0.000_001)
}

@Test func fullRollMapsToFullX() {
    let mapper = JoystickMapper(fullDeflectionRadians: .pi / 6, deadzone: 0)
    let attitude = MotionQuaternion.fromEuler(roll: .pi / 6, pitch: 0, yaw: 0)
    let output = mapper.map(attitude: attitude, relativeTo: .identity, invertY: false)

    #expect(abs(output.x - 1) < 0.000_001)
    #expect(abs(output.y) < 0.000_001)
}

@Test func radialDeadzoneIsContinuousAndRescaled() {
    let mapper = JoystickMapper(fullDeflectionRadians: 1, deadzone: 0.1)
    let inside = MotionQuaternion.fromEuler(roll: 0.09, pitch: 0, yaw: 0)
    let halfway = MotionQuaternion.fromEuler(roll: 0.55, pitch: 0, yaw: 0)

    #expect(mapper.map(attitude: inside, relativeTo: .identity).magnitude == 0)
    #expect(abs(mapper.map(attitude: halfway, relativeTo: .identity).magnitude - 0.5) < 0.000_001)
}

@Test func diagonalOutputIsClampedToCircle() {
    let mapper = JoystickMapper(fullDeflectionRadians: 0.2, deadzone: 0)
    let attitude = MotionQuaternion.fromEuler(roll: 0.4, pitch: 0.4, yaw: 0)

    #expect(abs(mapper.map(attitude: attitude, relativeTo: .identity).magnitude - 1) < 0.000_001)
}

@Test func smootherUsesElapsedTime() {
    var smoother = ExponentialStickSmoother(timeConstant: 0.1)
    _ = smoother.update(.zero, at: 0)
    let output = smoother.update(StickVector(x: 1, y: 0), at: 0.1)

    #expect(abs(output.x - (1 - exp(-1))) < 0.000_001)
}

@Test(arguments: [
    (vector: (-3.80, -23.72, -23.63), expected: StickVector(x: 0, y: -1)),
    (vector: (14.03, 16.82, -0.80), expected: StickVector(x: 0, y: 1)),
    (vector: (4.64, 22.93, -31.08), expected: StickVector(x: -1, y: 0)),
    (vector: (7.46, -28.16, 18.04), expected: StickVector(x: 1, y: 0))
])
func learnedGripMapsRecordedPoses(
    vector: (Double, Double, Double),
    expected: StickVector
) {
    let radians = Double.pi / 180
    let attitude = MotionQuaternion.fromRotationVector(
        x: vector.0 * radians,
        y: vector.1 * radians,
        z: vector.2 * radians
    )
    let output = GripCalibratedMapper(deadzone: 0).map(
        attitude: attitude,
        relativeTo: .identity
    )

    #expect(abs(output.x - expected.x) < 0.11)
    #expect(abs(output.y - expected.y) < 0.11)
}
