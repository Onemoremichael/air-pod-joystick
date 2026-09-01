import SwiftUI

struct StemLabView: View {
    @ObservedObject var lab: StemInputLab

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stem Lab")
                .font(.largeTitle.bold())
            Text("Observe AirPods stem swipes and presses before mapping them to game output.")
                .foregroundStyle(.secondary)

            GroupBox("Automatic recording") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle()
                            .fill(lab.isTrackingSession ? .red : .secondary)
                            .frame(width: 9, height: 9)
                        Text(lab.isTrackingSession ? "Recording every event and motion sample" : "Recording stopped")
                        Spacer()
                        Text("\(lab.trackedRowCount) rows")
                            .monospacedDigit()
                    }
                    if let path = lab.trackingPath {
                        Text(path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 3)
            }

            GroupBox("Volume swipe → virtual throttle") {
                VStack(alignment: .leading, spacing: 9) {
                    ProgressView(value: lab.throttle)
                    HStack {
                        Text("Throttle \(Int(lab.throttle * 100))%")
                        Spacer()
                        Text("Δ \(lab.lastVolumeDelta, format: .number.precision(.fractionLength(3)))")
                        Text("\(lab.volumeEventCount) events")
                    }
                    .font(.callout.monospacedDigit())
                    Text(lab.volumeStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(lab.isWatchingVolume ? "Stop watching" : "Watch volume") {
                            lab.isWatchingVolume ? lab.stopVolumeMonitoring() : lab.startVolumeMonitoring()
                        }
                        Button("Reset counters") { lab.resetThrottle() }
                    }
                    Text("This experiment observes the real Mac output volume; AirPods swipes will still change it.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(.vertical, 3)
            }

            GroupBox("IMU tap → trigger") {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle("Detect acceleration impulses", isOn: $lab.impulseDetectionEnabled)
                    HStack {
                        Text("Threshold")
                        Slider(value: $lab.impulseThreshold, in: 0.10...1.00, step: 0.05)
                        Text("\(lab.impulseThreshold, format: .number.precision(.fractionLength(2))) g")
                            .monospacedDigit()
                            .frame(width: 55, alignment: .trailing)
                    }
                    HStack {
                        Text("Now \(lab.latestAcceleration, format: .number.precision(.fractionLength(3))) g")
                        Text("Peak \(lab.peakAcceleration, format: .number.precision(.fractionLength(3))) g")
                        Spacer()
                        Text("Triggers: \(lab.impulseCount)")
                            .font(.headline.monospacedDigit())
                    }
                    Button("Reset tap stats") { lab.resetImpulseStats() }
                }
                .padding(.vertical, 3)
            }

            GroupBox("Force press → media command") {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle(
                        "Take over Now Playing controls",
                        isOn: Binding(
                            get: { lab.mediaCommandsEnabled },
                            set: { lab.setMediaCommandsEnabled($0) }
                        )
                    )
                    Text(lab.mediaStatus)
                        .font(.caption)
                        .foregroundStyle(lab.mediaCommandsEnabled ? .orange : .secondary)
                    HStack {
                        Text("Last: \(lab.lastRemoteCommand)")
                        Spacer()
                        Text("Commands: \(lab.remotePressCount)")
                            .font(.headline.monospacedDigit())
                    }
                    Text("While enabled, single/double/triple presses may replace play, next, and previous controls for other media apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(22)
        .frame(width: 580, height: 735)
        .onAppear { lab.startTrackingSession() }
        .onDisappear {
            lab.stopAllExperiments()
            lab.stopTrackingSession()
        }
    }
}
