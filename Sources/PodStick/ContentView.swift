import PodStickCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var motion: MotionController
    @State private var showsStemLab = false

    var body: some View {
        VStack(spacing: 18) {
            header

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 16) {
                    JoystickView(
                        output: motion.outputVector,
                        raw: motion.rawVector,
                        deadzone: motion.deadzone
                    )
                    .frame(minHeight: 320)

                    Text("Tilt the AirPod. The blue dot is output; the faint dot is raw input.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 16) {
                    SlalomView(steering: motion.outputVector.x)
                        .frame(height: 190)
                    BaselineCaptureView(capture: motion.baselineCapture)
                    controls
                }
                .frame(width: 360)
            }

            telemetry
        }
        .padding(22)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("PodStick")
                    .font(.largeTitle.bold())
                Text(motion.status)
                    .foregroundStyle(motion.isRunning ? .green : .secondary)
            }
            Spacer()
            Button(motion.isRunning ? "Stop" : "Start") {
                motion.isRunning ? motion.stop() : motion.start()
            }
            Button("Stem Lab") { showsStemLab = true }
            Button("Zero") { motion.zero() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showsStemLab) {
            StemLabView(lab: motion.stemLab)
        }
    }

    private var controls: some View {
        GroupBox("Feel") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Range")
                    Slider(value: $motion.rangeDegrees, in: 15...60, step: 1)
                        .disabled(motion.useGripCalibration)
                    Text("\(Int(motion.rangeDegrees))°")
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
                GridRow {
                    Text("Deadzone")
                    Slider(value: $motion.deadzone, in: 0...0.25, step: 0.01)
                    Text("\(Int(motion.deadzone * 100))%")
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Toggle("Learned grip", isOn: $motion.useGripCalibration)
                    Toggle("Smooth", isOn: $motion.useSmoothing)
                }
                HStack {
                    Toggle("Flip X", isOn: $motion.invertX)
                    Toggle("Flip Y", isOn: $motion.invertY)
                }
                .disabled(motion.useGripCalibration)
            }
            .toggleStyle(.checkbox)
        }
    }

    private var telemetry: some View {
        HStack(spacing: 24) {
            Label(String(format: "%.1f Hz", motion.sampleRate), systemImage: "waveform.path.ecg")
            Label("\(motion.sampleCount) samples", systemImage: "number")
            Label(String(format: "largest gap %.0f ms", motion.longestGapMilliseconds), systemImage: "clock")
            Label("permission: \(motion.authorization)", systemImage: "hand.raised")
            Label(motion.deviceAvailable ? "AirPods available" : "AirPods unavailable", systemImage: "airpodspro")
            Spacer()
            Text("Re-zero: ⇧⌘R")
                .foregroundStyle(.secondary)
        }
        .font(.system(.callout, design: .monospaced))
    }
}

private struct BaselineCaptureView: View {
    @EnvironmentObject private var motion: MotionController
    @ObservedObject var capture: BaselineCapture

    var body: some View {
        GroupBox("Baseline capture") {
            VStack(alignment: .leading, spacing: 9) {
                Text(capture.instruction)
                    .font(.headline)
                    .foregroundStyle(capture.isCapturing ? .orange : .primary)

                ProgressView(value: capture.progress)

                HStack {
                    if capture.isCapturing {
                        Button("Cancel") { capture.cancel() }
                    } else {
                        Button("Record forward / backward / left / right") {
                            motion.startBaselineCapture()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    Text("\(capture.capturedSamples) samples")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let path = capture.lastCapturePath {
                    Text(path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 3)
        }
    }
}

private struct JoystickView: View {
    let output: StickVector
    let raw: StickVector
    let deadzone: Double

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let radius = side * 0.42
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                Circle()
                    .fill(.quaternary)
                    .overlay(Circle().stroke(.secondary, lineWidth: 2))
                    .frame(width: radius * 2, height: radius * 2)

                Circle()
                    .stroke(.orange.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .frame(width: radius * 2 * deadzone, height: radius * 2 * deadzone)

                Path { path in
                    path.move(to: CGPoint(x: center.x - radius, y: center.y))
                    path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                    path.move(to: CGPoint(x: center.x, y: center.y - radius))
                    path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                }
                .stroke(.secondary.opacity(0.35), lineWidth: 1)

                Circle()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 13, height: 13)
                    .position(point(for: raw, center: center, radius: radius))

                Circle()
                    .fill(.blue)
                    .shadow(color: .blue.opacity(0.45), radius: 8)
                    .frame(width: 22, height: 22)
                    .position(point(for: output, center: center, radius: radius))
            }
        }
        .accessibilityLabel("Joystick output")
        .accessibilityValue(String(format: "x %.2f, y %.2f", output.x, output.y))
    }

    private func point(for vector: StickVector, center: CGPoint, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + CGFloat(vector.x) * radius,
            y: center.y + CGFloat(vector.y) * radius
        )
    }
}

private struct SlalomView: View {
    let steering: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let road = CGRect(x: size.width * 0.08, y: 0, width: size.width * 0.84, height: size.height)
                context.fill(Path(roundedRect: road, cornerRadius: 14), with: .color(.black.opacity(0.8)))

                for index in 0..<7 {
                    let phase = (time * 0.42 + Double(index) / 7).truncatingRemainder(dividingBy: 1)
                    let y = size.height * (1 - phase)
                    let centerOffset = sin((time * 0.8) + Double(index) * 1.7) * size.width * 0.22
                    let gateCenter = size.width / 2 + centerOffset
                    let gateHalfWidth = size.width * 0.12

                    var line = Path()
                    line.move(to: CGPoint(x: road.minX, y: y))
                    line.addLine(to: CGPoint(x: gateCenter - gateHalfWidth, y: y))
                    line.move(to: CGPoint(x: gateCenter + gateHalfWidth, y: y))
                    line.addLine(to: CGPoint(x: road.maxX, y: y))
                    context.stroke(line, with: .color(.orange), lineWidth: 4)
                }

                let carX = size.width / 2 + CGFloat(steering) * size.width * 0.34
                let car = CGRect(x: carX - 13, y: size.height - 54, width: 26, height: 40)
                context.fill(Path(roundedRect: car, cornerRadius: 7), with: .color(.blue))
                context.stroke(Path(roundedRect: car, cornerRadius: 7), with: .color(.white.opacity(0.8)), lineWidth: 2)
            }
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .topLeading) {
            Text("STEERING TEST")
                .font(.caption.bold().monospaced())
                .padding(10)
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}
