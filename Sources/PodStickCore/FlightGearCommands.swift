import Foundation

public enum FlightGearTapAction: String, CaseIterable, Sendable {
    case brakes
    case armament
    case none

    public var title: String {
        switch self {
        case .brakes: "Both brakes"
        case .armament: "Armament trigger"
        case .none: "None"
        }
    }
}

public struct FlightGearCommandEncoder: Sendable {
    public init() {}

    public func controls(
        stick: StickVector,
        sensitivity: Double = 1,
        invertX: Bool = false,
        invertY: Bool = false
    ) -> Data {
        let x = shaped(stick.x, sensitivity: sensitivity) * (invertX ? -1 : 1)
        let y = shaped(stick.y, sensitivity: sensitivity) * (invertY ? -1 : 1)
        return data([
            command("/controls/flight/aileron", value: x),
            command("/controls/flight/elevator", value: y)
        ])
    }

    public func neutral(tapAction: FlightGearTapAction) -> Data {
        var commands = [
            command("/controls/flight/aileron", value: 0),
            command("/controls/flight/elevator", value: 0)
        ]
        commands.append(contentsOf: triggerCommands(action: tapAction, pressed: false))
        return data(commands)
    }

    public func trigger(action: FlightGearTapAction, pressed: Bool) -> Data? {
        let commands = triggerCommands(action: action, pressed: pressed)
        return commands.isEmpty ? nil : data(commands)
    }

    private func shaped(_ value: Double, sensitivity: Double) -> Double {
        let clampedValue = max(-1, min(1, value))
        let clampedSensitivity = max(0.1, min(2, sensitivity))
        return max(-1, min(1, clampedValue * clampedSensitivity))
    }

    private func triggerCommands(action: FlightGearTapAction, pressed: Bool) -> [String] {
        let value = pressed ? 1.0 : 0.0
        switch action {
        case .brakes:
            return [
                command("/controls/gear/brake-left", value: value),
                command("/controls/gear/brake-right", value: value)
            ]
        case .armament:
            return [command("/controls/armament/pickle", value: value)]
        case .none:
            return []
        }
    }

    private func command(_ property: String, value: Double) -> String {
        let formatted = String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), value)
        return "set \(property) \(formatted)"
    }

    private func data(_ commands: [String]) -> Data {
        Data((commands.joined(separator: "\r\n") + "\r\n").utf8)
    }
}
