import CoreMotion
import Foundation
import PodStickCore

@MainActor
final class BaselineCapture: ObservableObject {
    struct Stage {
        let instruction: String
        let duration: TimeInterval
    }

    static let stages = [
        Stage(instruction: "Hold neutral", duration: 2),
        Stage(instruction: "Pitch forward and hold", duration: 2),
        Stage(instruction: "Return to center", duration: 1),
        Stage(instruction: "Pitch backward and hold", duration: 2),
        Stage(instruction: "Return to center", duration: 1),
        Stage(instruction: "Tilt left and hold", duration: 2),
        Stage(instruction: "Return to center", duration: 1),
        Stage(instruction: "Tilt right and hold", duration: 2)
    ]

    @Published private(set) var isCapturing = false
    @Published private(set) var instruction = "Ready to record"
    @Published private(set) var progress = 0.0
    @Published private(set) var capturedSamples = 0
    @Published private(set) var lastCapturePath: String?
    @Published private(set) var errorMessage: String?

    private var startTime: TimeInterval?
    private var rows: [String] = []
    private var clockTask: Task<Void, Never>?

    private static let header = [
        "capture_elapsed_s", "motion_timestamp_s", "stage",
        "quaternion_w", "quaternion_x", "quaternion_y", "quaternion_z",
        "relative_roll_deg", "relative_pitch_deg",
        "rotation_x_rad_s", "rotation_y_rad_s", "rotation_z_rad_s",
        "acceleration_x_g", "acceleration_y_g", "acceleration_z_g",
        "gravity_x_g", "gravity_y_g", "gravity_z_g",
        "raw_stick_x", "raw_stick_y", "smoothed_stick_x", "smoothed_stick_y"
    ].joined(separator: ",")

    var totalDuration: TimeInterval {
        Self.stages.reduce(0) { $0 + $1.duration }
    }

    func start() {
        rows = [Self.header]
        capturedSamples = 0
        progress = 0
        instruction = Self.stages[0].instruction
        lastCapturePath = nil
        errorMessage = nil
        startTime = ProcessInfo.processInfo.systemUptime
        isCapturing = true
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.isCapturing, let startTime = self.startTime else { return }
                let elapsed = ProcessInfo.processInfo.systemUptime - startTime
                if elapsed >= self.totalDuration {
                    self.finish()
                    return
                }
                self.instruction = self.stage(at: elapsed).instruction
                self.progress = elapsed / self.totalDuration
            }
        }
    }

    func cancel() {
        clockTask?.cancel()
        clockTask = nil
        isCapturing = false
        startTime = nil
        rows = []
        progress = 0
        instruction = "Capture cancelled"
    }

    func record(
        motion: CMDeviceMotion,
        attitude: MotionQuaternion,
        reference: MotionQuaternion,
        raw: StickVector,
        smoothed: StickVector
    ) {
        guard isCapturing, let startTime else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - startTime
        guard elapsed < totalDuration else { return }

        let stage = stage(at: elapsed)
        instruction = stage.instruction
        progress = elapsed / totalDuration

        let relativeAngles = reference.inverse.multiplied(by: attitude).rollAndPitch
        let rate = motion.rotationRate
        let acceleration = motion.userAcceleration
        let gravity = motion.gravity
        let values = [
            format(elapsed), format(motion.timestamp), csv(stage.instruction),
            format(attitude.w), format(attitude.x), format(attitude.y), format(attitude.z),
            format(relativeAngles.roll * 180 / .pi), format(relativeAngles.pitch * 180 / .pi),
            format(rate.x), format(rate.y), format(rate.z),
            format(acceleration.x), format(acceleration.y), format(acceleration.z),
            format(gravity.x), format(gravity.y), format(gravity.z),
            format(raw.x), format(raw.y), format(smoothed.x), format(smoothed.y)
        ]
        rows.append(values.joined(separator: ","))
        capturedSamples += 1
    }

    private func stage(at elapsed: TimeInterval) -> Stage {
        var boundary = 0.0
        for stage in Self.stages {
            boundary += stage.duration
            if elapsed < boundary { return stage }
        }
        return Self.stages[Self.stages.count - 1]
    }

    private func finish() {
        guard isCapturing else { return }
        clockTask?.cancel()
        clockTask = nil
        isCapturing = false
        startTime = nil
        progress = 1

        do {
            let fileManager = FileManager.default
            let documents = try fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = documents.appendingPathComponent("PodStick Captures", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let filename = "podstick-baseline_\(formatter.string(from: Date())).csv"
            let file = directory.appendingPathComponent(filename)
            try (rows.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
            lastCapturePath = file.path
            instruction = "Saved \(capturedSamples) samples"
        } catch {
            errorMessage = error.localizedDescription
            instruction = "Could not save capture"
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func csv(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
