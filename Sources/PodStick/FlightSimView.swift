import PodStickCore
import SwiftUI

struct FlightSimView: View {
    @ObservedObject var motion: MotionController
    @ObservedObject var lab: StemInputLab
    @Environment(\.dismiss) private var dismiss

    @State private var shots = 0
    @State private var hits = 0
    @State private var shotFlashUntil = Date.distantPast

    var body: some View {
        ZStack {
            TimelineView(.animation) { timeline in
                FlightCanvas(
                    stick: motion.outputVector,
                    time: timeline.date.timeIntervalSinceReferenceDate,
                    isFiring: timeline.date < shotFlashUntil
                )
            }

            VStack {
                hud
                Spacer()
                controls
            }
            .padding(18)
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(.black)
        .onAppear {
            lab.impulseDetectionEnabled = true
            lab.resetImpulseStats()
            motion.zero()
        }
        .onDisappear {
            lab.impulseDetectionEnabled = false
        }
        .onChange(of: lab.impulseCount) { oldCount, newCount in
            guard newCount > oldCount else { return }
            let addedShots = newCount - oldCount
            shots += addedShots
            shotFlashUntil = Date().addingTimeInterval(0.12)

            let target = targetVector(at: Date().timeIntervalSinceReferenceDate)
            let stick = motion.outputVector
            if hypot(target.x - stick.x, target.y - stick.y) < 0.30 {
                hits += 1
            }
        }
    }

    private var hud: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("PODSTICK FLIGHT TEST")
                    .font(.headline.monospaced().bold())
                Text("Match the reticle to the ring. Tap the stem to fire.")
                    .font(.caption)
            }
            Spacer()
            HStack(spacing: 18) {
                hudValue("SHOTS", shots)
                hudValue("HITS", hits)
                hudValue("RATE", Int(motion.sampleRate.rounded()))
            }
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 12))
    }

    private func hudValue(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.title2.monospacedDigit().bold())
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var controls: some View {
        HStack {
            Button("Re-zero") { motion.zero() }
                .keyboardShortcut("r", modifiers: [])
            Toggle("Smooth", isOn: $motion.useSmoothing)
                .toggleStyle(.checkbox)
            Text("Trigger")
            Slider(value: $lab.impulseThreshold, in: 0.15...0.80, step: 0.05)
                .frame(width: 150)
            Text("\(lab.impulseThreshold, format: .number.precision(.fractionLength(2))) g")
                .monospacedDigit()
            Spacer()
            Text(String(format: "X %+0.2f   Y %+0.2f", motion.outputVector.x, motion.outputVector.y))
                .font(.callout.monospaced())
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct FlightCanvas: View {
    let stick: StickVector
    let time: TimeInterval
    let isFiring: Bool

    var body: some View {
        Canvas { context, size in
            drawBackground(context: &context, size: size)
            drawWorld(context: &context, size: size)
            drawTarget(context: &context, size: size)
            drawReticle(context: &context, size: size)
            drawAircraft(context: &context, size: size)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.35, blue: 0.66), Color(red: 0.53, green: 0.76, blue: 0.91)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .ignoresSafeArea()
    }

    private func drawBackground(context: inout GraphicsContext, size: CGSize) {
        for index in 0..<7 {
            let drift = (time * (8 + Double(index))).truncatingRemainder(dividingBy: size.width + 220)
            let x = CGFloat(drift) - 110
            let y = size.height * (0.12 + CGFloat(index % 3) * 0.10)
            let cloud = CGRect(x: x, y: y, width: 100 + CGFloat(index % 2) * 45, height: 24)
            context.fill(Path(ellipseIn: cloud), with: .color(.white.opacity(0.20)))
        }
    }

    private func drawWorld(context: inout GraphicsContext, size: CGSize) {
        var world = context
        let horizonY = size.height * 0.53 + CGFloat(stick.y) * size.height * 0.20
        world.translateBy(x: size.width / 2, y: horizonY)
        world.rotate(by: .radians(-stick.x * 0.48))

        let ground = CGRect(x: -size.width * 1.5, y: 0, width: size.width * 3, height: size.height * 2)
        world.fill(Path(ground), with: .linearGradient(
            Gradient(colors: [Color(red: 0.32, green: 0.42, blue: 0.18), Color(red: 0.08, green: 0.15, blue: 0.06)]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: size.height)
        ))

        var horizon = Path()
        horizon.move(to: CGPoint(x: -size.width * 1.5, y: 0))
        horizon.addLine(to: CGPoint(x: size.width * 1.5, y: 0))
        world.stroke(horizon, with: .color(.white.opacity(0.75)), lineWidth: 2)

        let scroll = CGFloat((time * 70).truncatingRemainder(dividingBy: 90))
        for index in 0..<12 {
            let y = CGFloat(index * index) * 7 + scroll
            var stripe = Path()
            stripe.move(to: CGPoint(x: -size.width, y: y))
            stripe.addLine(to: CGPoint(x: size.width, y: y))
            world.stroke(stripe, with: .color(.white.opacity(0.10)), lineWidth: 1)
        }
        for x in stride(from: -1.0, through: 1.0, by: 0.25) {
            var ray = Path()
            ray.move(to: .zero)
            ray.addLine(to: CGPoint(x: size.width * x, y: size.height * 1.5))
            world.stroke(ray, with: .color(.white.opacity(0.09)), lineWidth: 1)
        }
    }

    private func drawTarget(context: inout GraphicsContext, size: CGSize) {
        let target = targetVector(at: time)
        let x = size.width / 2 + CGFloat(target.x - stick.x) * size.width * 0.34
        let y = size.height / 2 + CGFloat(target.y - stick.y) * size.height * 0.28
        let pulse = 42 + sin(time * 4) * 4
        let ring = CGRect(x: x - pulse, y: y - pulse, width: pulse * 2, height: pulse * 2)
        context.stroke(Path(ellipseIn: ring), with: .color(.orange), lineWidth: 5)
        context.stroke(Path(ellipseIn: ring.insetBy(dx: 12, dy: 12)), with: .color(.white.opacity(0.8)), lineWidth: 2)
    }

    private func drawReticle(context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var reticle = Path()
        reticle.move(to: CGPoint(x: center.x - 34, y: center.y))
        reticle.addLine(to: CGPoint(x: center.x - 10, y: center.y))
        reticle.move(to: CGPoint(x: center.x + 10, y: center.y))
        reticle.addLine(to: CGPoint(x: center.x + 34, y: center.y))
        reticle.move(to: CGPoint(x: center.x, y: center.y - 34))
        reticle.addLine(to: CGPoint(x: center.x, y: center.y - 10))
        reticle.move(to: CGPoint(x: center.x, y: center.y + 10))
        reticle.addLine(to: CGPoint(x: center.x, y: center.y + 34))
        context.stroke(reticle, with: .color(isFiring ? .red : .white), lineWidth: isFiring ? 5 : 2)

        if isFiring {
            let beam = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: beam), with: .color(.yellow))
        }
    }

    private func drawAircraft(context: inout GraphicsContext, size: CGSize) {
        let centerX = size.width / 2
        let y = size.height * 0.82
        var plane = Path()
        plane.move(to: CGPoint(x: centerX, y: y - 26))
        plane.addLine(to: CGPoint(x: centerX + 12, y: y + 12))
        plane.addLine(to: CGPoint(x: centerX + 76, y: y + 30))
        plane.addLine(to: CGPoint(x: centerX + 18, y: y + 28))
        plane.addLine(to: CGPoint(x: centerX, y: y + 48))
        plane.addLine(to: CGPoint(x: centerX - 18, y: y + 28))
        plane.addLine(to: CGPoint(x: centerX - 76, y: y + 30))
        plane.addLine(to: CGPoint(x: centerX - 12, y: y + 12))
        plane.closeSubpath()
        context.fill(plane, with: .color(.white.opacity(0.92)))
        context.stroke(plane, with: .color(.black.opacity(0.7)), lineWidth: 2)
    }
}

private func targetVector(at time: TimeInterval) -> StickVector {
    StickVector(
        x: sin(time * 0.43) * 0.68,
        y: cos(time * 0.31) * 0.50
    )
}
