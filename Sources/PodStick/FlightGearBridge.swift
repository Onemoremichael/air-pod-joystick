@preconcurrency import Network
import PodStickCore
import SwiftUI

@MainActor
final class FlightGearBridge: ObservableObject {
    @Published var port = 5500
    @Published var sensitivity = 1.0
    @Published var invertX = false
    @Published var invertY = false
    @Published var tapAction = FlightGearTapAction.brakes
    @Published private(set) var isConnected = false
    @Published private(set) var status = "Disconnected"
    @Published private(set) var packetsSent = 0

    private let encoder = FlightGearCommandEncoder()
    private let queue = DispatchQueue(label: "com.podstick.flightgear")
    private var connection: NWConnection?
    private var triggerReleaseTask: Task<Void, Never>?

    func connect() {
        disconnect(sendNeutral: false)
        guard (1...65_535).contains(port),
              let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            status = "Invalid port"
            return
        }

        status = "Connecting to 127.0.0.1:\(port)…"
        let connection = NWConnection(host: "127.0.0.1", port: nwPort, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor in
                guard let self, self.connection === connection else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.status = "Connected — sending controls"
                    self.send(self.encoder.neutral(tapAction: self.tapAction))
                case .waiting(let error):
                    self.isConnected = false
                    self.status = "Waiting: \(error.localizedDescription)"
                case .failed(let error):
                    self.isConnected = false
                    self.status = "Connection failed: \(error.localizedDescription)"
                    self.connection = nil
                case .cancelled:
                    self.isConnected = false
                    if self.connection === connection {
                        self.connection = nil
                        self.status = "Disconnected"
                    }
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
    }

    func send(stick: StickVector) {
        guard isConnected else { return }
        send(encoder.controls(
            stick: stick,
            sensitivity: sensitivity,
            invertX: invertX,
            invertY: invertY
        ))
    }

    func fireTrigger() {
        guard isConnected, let pressed = encoder.trigger(action: tapAction, pressed: true) else { return }
        triggerReleaseTask?.cancel()
        send(pressed)
        triggerReleaseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled, let self,
                  let released = self.encoder.trigger(action: self.tapAction, pressed: false) else { return }
            self.send(released)
        }
    }

    func disconnect() {
        disconnect(sendNeutral: true)
    }

    func shutdown() {
        triggerReleaseTask?.cancel()
        triggerReleaseTask = nil
        guard let connection else { return }

        isConnected = false
        self.connection = nil
        let completion = DispatchSemaphore(value: 0)
        connection.send(
            content: encoder.neutral(tapAction: tapAction),
            completion: .contentProcessed { _ in
                connection.cancel()
                completion.signal()
            }
        )
        _ = completion.wait(timeout: .now() + .milliseconds(250))
        connection.cancel()
        status = "Closed — controls neutralized"
    }

    private func disconnect(sendNeutral: Bool) {
        triggerReleaseTask?.cancel()
        triggerReleaseTask = nil
        guard let connection else {
            isConnected = false
            status = "Disconnected"
            return
        }

        isConnected = false
        self.connection = nil
        guard sendNeutral else {
            connection.cancel()
            status = "Disconnected"
            return
        }

        status = "Disconnecting safely…"
        let neutral = encoder.neutral(tapAction: tapAction)
        connection.send(content: neutral, completion: .contentProcessed { _ in
            connection.cancel()
        })
        status = "Disconnected — controls neutralized"
    }

    private func send(_ data: Data) {
        guard let connection else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self, weak connection] error in
            Task { @MainActor in
                guard let self else { return }
                if let error, self.connection === connection {
                    self.status = "Send failed: \(error.localizedDescription)"
                    self.isConnected = false
                } else if error == nil {
                    self.packetsSent += 1
                }
            }
        })
    }
}
