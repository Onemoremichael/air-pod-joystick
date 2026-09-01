import PodStickCore
import SwiftUI

struct FlightGearView: View {
    @ObservedObject var motion: MotionController
    @ObservedObject var bridge: FlightGearBridge
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FlightGear Bridge")
                        .font(.largeTitle.bold())
                    Text(bridge.status)
                        .foregroundStyle(bridge.isConnected ? .green : .secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
            }

            GroupBox("1. Start FlightGear") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add these options in FlightGear Launcher → Settings → Additional Settings:")
                    Text("--telnet=\(bridge.port)\n--timeofday=noon")
                        .font(.title3.monospaced().bold())
                        .textSelection(.enabled)
                    Link("Download FlightGear", destination: URL(string: "https://www.flightgear.org/download/")!)
                    Text("Press Fly and wait for the flight to finish loading before connecting. The launcher alone does not open the port. To skip takeoff, choose Location → On final approach.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("2. Connect PodStick") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Host")
                        Text("127.0.0.1 (this Mac)")
                            .foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("Port")
                        TextField("5500", value: $bridge.port, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack {
                    Button(bridge.isConnected ? "Disconnect safely" : "Connect") {
                        if bridge.isConnected {
                            motion.disconnectFlightGear()
                        } else {
                            motion.connectFlightGear()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Re-zero") { motion.zero() }
                    Spacer()
                    Text("\(bridge.packetsSent) packets")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 10)
            }

            GroupBox("Mapping") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        Text("Sensitivity")
                        Slider(value: $bridge.sensitivity, in: 0.25...1.5, step: 0.05)
                        Text(bridge.sensitivity, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                    }
                    GridRow {
                        Text("Stem tap")
                        Picker("Stem tap", selection: $bridge.tapAction) {
                            ForEach(FlightGearTapAction.allCases, id: \.self) { action in
                                Text(action.title).tag(action)
                            }
                        }
                        .labelsHidden()
                        Text(bridge.tapAction == .brakes ? "Useful for the Cessna" : "Aircraft-dependent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Toggle("Invert aileron", isOn: $bridge.invertX)
                    Toggle("Invert elevator", isOn: $bridge.invertY)
                }
                .toggleStyle(.checkbox)
                .padding(.top, 8)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "AILERON %+0.2f", flightX))
                    Text(String(format: "ELEVATOR %+0.2f", flightY))
                }
                .font(.title3.monospaced())
                Spacer()
                Text("Closing or disconnecting sends neutral controls before the socket closes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(22)
        .frame(width: 650)
        .onDisappear {
            if bridge.isConnected { motion.disconnectFlightGear() }
        }
    }

    private var flightX: Double {
        max(-1, min(1, motion.outputVector.x * bridge.sensitivity * (bridge.invertX ? -1 : 1)))
    }

    private var flightY: Double {
        max(-1, min(1, motion.outputVector.y * bridge.sensitivity * (bridge.invertY ? -1 : 1)))
    }
}
