import AVFoundation
import AudioToolbox
import CoreAudio
import CoreMotion
import Foundation
import MediaPlayer
import PodStickCore

@MainActor
final class StemInputLab: ObservableObject {
    @Published private(set) var isWatchingVolume = false
    @Published private(set) var volumeStatus = "Not monitoring"
    @Published private(set) var systemVolume = 0.0
    @Published private(set) var throttle = 0.0
    @Published private(set) var volumeEventCount = 0
    @Published private(set) var lastVolumeDelta = 0.0

    @Published var impulseDetectionEnabled = false {
        didSet { impulseDetector.reset() }
    }
    @Published var impulseThreshold = 0.35
    @Published private(set) var impulseCount = 0
    @Published private(set) var latestAcceleration = 0.0
    @Published private(set) var peakAcceleration = 0.0
    @Published private(set) var lastImpulseAt: Date?

    @Published private(set) var mediaCommandsEnabled = false
    @Published private(set) var mediaStatus = "Off"
    @Published private(set) var remotePressCount = 0
    @Published private(set) var lastRemoteCommand = "None"
    @Published private(set) var lastRemoteCommandAt: Date?
    @Published private(set) var isTrackingSession = false
    @Published private(set) var trackingPath: String?
    @Published private(set) var trackedRowCount = 0

    private var impulseDetector = TapImpulseDetector()
    private var outputDevice = AudioObjectID(kAudioObjectUnknown)
    private var volumeAddress: AudioObjectPropertyAddress?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var volumePollingTask: Task<Void, Never>?

    private let audioEngine = AVAudioEngine()
    private let silentPlayer = AVAudioPlayerNode()
    private var didPrepareSilentPlayer = false
    private var remoteTargets: [(command: MPRemoteCommand, token: Any)] = []
    private var trackingHandle: FileHandle?
    private var trackingStartTime: TimeInterval?

    private static let trackingHeader = [
        "wall_time", "elapsed_s", "event_type", "detail", "motion_timestamp_s",
        "acceleration_x_g", "acceleration_y_g", "acceleration_z_g", "acceleration_magnitude_g",
        "rotation_x_rad_s", "rotation_y_rad_s", "rotation_z_rad_s",
        "raw_stick_x", "raw_stick_y", "smoothed_stick_x", "smoothed_stick_y",
        "system_volume", "virtual_throttle", "volume_delta",
        "impulse_threshold_g", "impulse_detected", "impulse_count",
        "remote_command", "remote_command_count"
    ].joined(separator: ",")

    func startTrackingSession() {
        guard !isTrackingSession else { return }
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
            let file = directory.appendingPathComponent(
                "podstick-stem-lab_\(formatter.string(from: Date())).csv"
            )
            fileManager.createFile(atPath: file.path, contents: nil)
            let handle = try FileHandle(forWritingTo: file)
            trackingHandle = handle
            trackingStartTime = ProcessInfo.processInfo.systemUptime
            trackingPath = file.path
            trackedRowCount = 0
            isTrackingSession = true
            writeTrackingLine(Self.trackingHeader)
            logEvent(type: "session_start", detail: "Stem Lab opened")
        } catch {
            trackingPath = "Tracking error: \(error.localizedDescription)"
            isTrackingSession = false
        }
    }

    func stopTrackingSession() {
        guard isTrackingSession else { return }
        logEvent(type: "session_end", detail: "Stem Lab closed")
        try? trackingHandle?.synchronize()
        try? trackingHandle?.close()
        trackingHandle = nil
        trackingStartTime = nil
        isTrackingSession = false
    }

    func startVolumeMonitoring() {
        guard !isWatchingVolume else { return }
        installDefaultDeviceListener()
        attachToDefaultOutput()
    }

    func stopVolumeMonitoring() {
        volumePollingTask?.cancel()
        volumePollingTask = nil
        removeVolumeListener()
        removeDefaultDeviceListener()
        isWatchingVolume = false
        volumeStatus = "Not monitoring"
    }

    func resetThrottle() {
        throttle = 0
        volumeEventCount = 0
        lastVolumeDelta = 0
    }

    func resetImpulseStats() {
        impulseCount = 0
        peakAcceleration = 0
        lastImpulseAt = nil
        impulseDetector.reset()
    }

    @discardableResult
    func consumeMotion(
        _ motion: CMDeviceMotion,
        rawStick: StickVector,
        smoothedStick: StickVector
    ) -> Bool {
        let a = motion.userAcceleration
        let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
        latestAcceleration = magnitude
        peakAcceleration = max(peakAcceleration, magnitude)

        var detected = false
        if impulseDetectionEnabled {
            impulseDetector.thresholdG = impulseThreshold
            detected = impulseDetector.update(
                accelerationMagnitudeG: magnitude,
                timestamp: motion.timestamp
            )
        }
        if detected {
            impulseCount += 1
            lastImpulseAt = Date()
        }

        logMotion(
            motion,
            magnitude: magnitude,
            rawStick: rawStick,
            smoothedStick: smoothedStick,
            impulseDetected: detected
        )
        return detected
    }

    func setMediaCommandsEnabled(_ enabled: Bool) {
        enabled ? enableMediaCommands() : disableMediaCommands()
    }

    func stopAllExperiments() {
        stopVolumeMonitoring()
        impulseDetectionEnabled = false
        disableMediaCommands()
    }

    private func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private func attachToDefaultOutput() {
        removeVolumeListener()
        guard let device = defaultOutputDevice() else {
            volumeStatus = "No default output device"
            isWatchingVolume = false
            return
        }

        let candidates = [
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: 1
            )
        ]

        guard var selected = candidates.first(where: { candidate in
            var candidate = candidate
            return AudioObjectHasProperty(device, &candidate)
        }) else {
            volumeStatus = "Output has no observable volume property"
            isWatchingVolume = false
            return
        }

        outputDevice = device
        volumeAddress = selected
        guard let initial = readVolume(device: device, address: &selected) else {
            volumeStatus = "Could not read output volume"
            isWatchingVolume = false
            return
        }
        systemVolume = initial
        throttle = initial

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.handleVolumeChange()
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            device,
            &selected,
            .main,
            listener
        )
        guard status == noErr else {
            volumeStatus = "Could not install volume listener (\(status))"
            isWatchingVolume = false
            return
        }
        volumeAddress = selected
        volumeListener = listener
        isWatchingVolume = true
        volumeStatus = "Watching system volume (listener + 20 Hz polling)"
        startVolumePolling()
    }

    private func readVolume(
        device: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) -> Double? {
        var value = Float32.zero
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &size,
            &value
        )
        guard status == noErr else { return nil }
        return Double(value)
    }

    private func handleVolumeChange() {
        guard var address = volumeAddress,
              let value = readVolume(device: outputDevice, address: &address) else { return }
        applyVolume(value)
    }

    private func startVolumePolling() {
        volumePollingTask?.cancel()
        volumePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.isWatchingVolume,
                      var address = self.volumeAddress,
                      let value = self.readVolume(device: self.outputDevice, address: &address) else {
                    continue
                }
                self.applyVolume(value)
            }
        }
    }

    private func applyVolume(_ value: Double) {
        let delta = value - systemVolume
        systemVolume = value
        throttle = value
        guard abs(delta) > 0.000_1 else { return }
        lastVolumeDelta = delta
        volumeEventCount += 1
        logEvent(type: "volume_change", detail: delta >= 0 ? "swipe_up" : "swipe_down")
    }

    private func installDefaultDeviceListener() {
        guard defaultDeviceListener == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.isWatchingVolume else { return }
                self.attachToDefaultOutput()
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            .main,
            listener
        )
        if status == noErr { defaultDeviceListener = listener }
    }

    private func removeVolumeListener() {
        guard var address = volumeAddress, let volumeListener else { return }
        AudioObjectRemovePropertyListenerBlock(
            outputDevice,
            &address,
            .main,
            volumeListener
        )
        self.volumeListener = nil
        volumeAddress = nil
        outputDevice = AudioObjectID(kAudioObjectUnknown)
    }

    private func removeDefaultDeviceListener() {
        guard let defaultDeviceListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            .main,
            defaultDeviceListener
        )
        self.defaultDeviceListener = nil
    }

    private func enableMediaCommands() {
        guard !mediaCommandsEnabled else { return }
        do {
            try startSilentPlayback()
        } catch {
            mediaStatus = "Could not start silent playback: \(error.localizedDescription)"
            return
        }

        let center = MPRemoteCommandCenter.shared()
        register(center.togglePlayPauseCommand, name: "Toggle play/pause")
        register(center.playCommand, name: "Play / single press")
        register(center.pauseCommand, name: "Pause / single press")
        register(center.nextTrackCommand, name: "Next / double press")
        register(center.previousTrackCommand, name: "Previous / triple press")

        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "PodStick Stem Lab",
            MPMediaItemPropertyArtist: "Testing AirPods press controls",
            MPMediaItemPropertyPlaybackDuration: 86_400,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
            MPNowPlayingInfoPropertyPlaybackRate: 1
        ]
        info.playbackState = .playing
        mediaCommandsEnabled = true
        mediaStatus = "Listening — media controls belong to PodStick"
    }

    private func register(_ command: MPRemoteCommand, name: String) {
        command.isEnabled = true
        let token = command.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.recordRemoteCommand(name)
            }
            return .success
        }
        remoteTargets.append((command, token))
    }

    private func recordRemoteCommand(_ name: String) {
        remotePressCount += 1
        lastRemoteCommand = name
        lastRemoteCommandAt = Date()
        logEvent(type: "media_command", detail: name)
        MPNowPlayingInfoCenter.default().playbackState = .playing
    }

    private func startSilentPlayback() throws {
        if !didPrepareSilentPlayer {
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
            buffer.frameLength = 44_100
            audioEngine.attach(silentPlayer)
            audioEngine.connect(silentPlayer, to: audioEngine.mainMixerNode, format: format)
            silentPlayer.volume = 0
            silentPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
            didPrepareSilentPlayer = true
        }
        if !audioEngine.isRunning { try audioEngine.start() }
        if !silentPlayer.isPlaying { silentPlayer.play() }
    }

    private func disableMediaCommands() {
        for target in remoteTargets {
            target.command.removeTarget(target.token)
        }
        remoteTargets.removeAll()
        silentPlayer.stop()
        audioEngine.stop()
        let info = MPNowPlayingInfoCenter.default()
        info.playbackState = .stopped
        info.nowPlayingInfo = nil
        mediaCommandsEnabled = false
        mediaStatus = "Off"
    }

    private func logMotion(
        _ motion: CMDeviceMotion,
        magnitude: Double,
        rawStick: StickVector,
        smoothedStick: StickVector,
        impulseDetected: Bool
    ) {
        guard isTrackingSession else { return }
        let a = motion.userAcceleration
        let r = motion.rotationRate
        writeTrackingRow([
            isoTimestamp(), elapsed(), "motion", "", format(motion.timestamp),
            format(a.x), format(a.y), format(a.z), format(magnitude),
            format(r.x), format(r.y), format(r.z),
            format(rawStick.x), format(rawStick.y), format(smoothedStick.x), format(smoothedStick.y),
            format(systemVolume), format(throttle), format(lastVolumeDelta),
            format(impulseThreshold), impulseDetected ? "1" : "0", "\(impulseCount)",
            csv(lastRemoteCommand), "\(remotePressCount)"
        ])
    }

    private func logEvent(type: String, detail: String) {
        guard isTrackingSession else { return }
        writeTrackingRow([
            isoTimestamp(), elapsed(), type, csv(detail), "",
            "", "", "", format(latestAcceleration),
            "", "", "", "", "", "", "",
            format(systemVolume), format(throttle), format(lastVolumeDelta),
            format(impulseThreshold), "0", "\(impulseCount)",
            csv(lastRemoteCommand), "\(remotePressCount)"
        ])
    }

    private func writeTrackingRow(_ fields: [String]) {
        writeTrackingLine(fields.joined(separator: ","))
        trackedRowCount += 1
    }

    private func writeTrackingLine(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        try? trackingHandle?.write(contentsOf: data)
    }

    private func elapsed() -> String {
        guard let trackingStartTime else { return "0.00000000" }
        return format(ProcessInfo.processInfo.systemUptime - trackingStartTime)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func csv(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func isoTimestamp() -> String {
        csv(ISO8601DateFormatter().string(from: Date()))
    }
}
