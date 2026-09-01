import Combine
@preconcurrency import CoreMotion
import Foundation
import PodStickCore

@MainActor
final class MotionController: ObservableObject {
    let baselineCapture = BaselineCapture()
    let stemLab = StemInputLab()
    @Published private(set) var rawVector = StickVector.zero
    @Published private(set) var smoothedVector = StickVector.zero
    @Published private(set) var sampleRate = 0.0
    @Published private(set) var sampleCount = 0
    @Published private(set) var longestGapMilliseconds = 0.0
    @Published private(set) var status = "Not started"
    @Published private(set) var isRunning = false
    @Published private(set) var authorization = "Unknown"
    @Published private(set) var deviceAvailable = false
    @Published private(set) var motionActive = false
    @Published var useSmoothing = true
    @Published var useGripCalibration = true
    @Published var rangeDegrees = 30.0
    @Published var deadzone = 0.05
    @Published var invertX = false
    @Published var invertY = true

    var outputVector: StickVector {
        useSmoothing ? smoothedVector : rawVector
    }

    private let manager = CMHeadphoneMotionManager()
    private var reference: MotionQuaternion?
    private var latestAttitude: MotionQuaternion?
    private var smoother = ExponentialStickSmoother()
    private var recentArrivals: [TimeInterval] = []
    private var lastArrival: TimeInterval?
    private var monitorTask: Task<Void, Never>?
    private var wantsMotion = false

    func start() {
        wantsMotion = true
        refreshDiagnostics()
        attemptStart()
        startMonitoring()
    }

    private func attemptStart() {
        guard wantsMotion, !isRunning else { return }

        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied, .restricted:
            status = "Motion access denied — enable PodStick in Privacy & Security"
            return
        default:
            break
        }

        guard manager.isDeviceMotionAvailable else {
            status = "Waiting for AirPods — choose them in Control Center → Sound"
            return
        }

        status = "Starting motion stream…"
        isRunning = true
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            MainActor.assumeIsolated {
                if let error {
                    self.status = "Motion error: \(error.localizedDescription)"
                    self.stop()
                    return
                }
                guard let motion else { return }
                self.consume(motion)
            }
        }
    }

    func stop() {
        wantsMotion = false
        monitorTask?.cancel()
        monitorTask = nil
        manager.stopDeviceMotionUpdates()
        isRunning = false
        refreshDiagnostics()
        status = "Stopped"
    }

    func zero() {
        guard let latestAttitude else {
            status = "Waiting for the first motion sample"
            return
        }
        reference = latestAttitude
        rawVector = .zero
        smoothedVector = .zero
        smoother.reset(to: .zero)
        status = "Streaming — zeroed"
    }

    func startBaselineCapture() {
        guard sampleCount > 0, latestAttitude != nil else {
            status = "Cannot record yet — waiting for motion samples"
            return
        }
        zero()
        baselineCapture.start()
    }

    private func consume(_ motion: CMDeviceMotion) {
        let source = motion.attitude.quaternion
        let attitude = MotionQuaternion(w: source.w, x: source.x, y: source.y, z: source.z)
        latestAttitude = attitude
        if reference == nil {
            reference = attitude
        }

        guard let reference else { return }
        let mapped: StickVector
        if useGripCalibration {
            mapped = GripCalibratedMapper(deadzone: deadzone).map(
                attitude: attitude,
                relativeTo: reference
            )
        } else {
            let mapper = JoystickMapper(
                fullDeflectionRadians: rangeDegrees * .pi / 180,
                deadzone: deadzone
            )
            mapped = mapper.map(
                attitude: attitude,
                relativeTo: reference,
                invertX: invertX,
                invertY: invertY
            )
        }
        rawVector = mapped
        smoothedVector = smoother.update(mapped, at: motion.timestamp)
        stemLab.consumeMotion(
            motion,
            rawStick: rawVector,
            smoothedStick: smoothedVector
        )
        baselineCapture.record(
            motion: motion,
            attitude: attitude,
            reference: reference,
            raw: rawVector,
            smoothed: smoothedVector
        )
        updateTelemetry()
        status = "Streaming"
        refreshDiagnostics()
    }

    private func updateTelemetry() {
        let now = ProcessInfo.processInfo.systemUptime
        sampleCount += 1

        if let lastArrival {
            longestGapMilliseconds = max(longestGapMilliseconds, (now - lastArrival) * 1_000)
        }
        lastArrival = now

        recentArrivals.append(now)
        recentArrivals.removeAll { now - $0 > 2 }
        if let first = recentArrivals.first, now > first {
            sampleRate = Double(recentArrivals.count - 1) / (now - first)
        }
    }

    private func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.wantsMotion else { return }
                self.refreshDiagnostics()
                self.attemptStart()
            }
        }
    }

    private func refreshDiagnostics() {
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .notDetermined: authorization = "Not requested"
        case .restricted: authorization = "Restricted"
        case .denied: authorization = "Denied"
        case .authorized: authorization = "Authorized"
        @unknown default: authorization = "Unknown"
        }
        deviceAvailable = manager.isDeviceMotionAvailable
        motionActive = manager.isDeviceMotionActive
    }
}
