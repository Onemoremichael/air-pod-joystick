# AirPods Motion Joystick — Technical Spec

**Working name:** PodStick
**One line:** Turn an AirPod's built-in IMU into a two-axis analog joystick that any macOS game can read.

---

## 1. Concept

AirPods Pro (1st gen and later), AirPods (3rd gen), and AirPods Max contain a 6-axis IMU used for spatial audio head tracking. Apple exposes this stream through `CMHeadphoneMotionManager`. If you hold a single bud between finger and thumb rather than wearing it, its orientation becomes a direct proxy for a thumbstick: tilt forward/back is one axis, tilt left/right is the other.

The bud is roughly the size and weight of a joystick cap, has a natural stem for grip orientation, and already pairs with everything. The whole product is the mapping layer between orientation and game input.

The bud also carries a force sensor and, on Pro 2 and later, a stem swipe surface. Neither is directly readable, but both may be observable indirectly — see §6, which treats them as an unresolved investigation rather than a committed feature.

**Non-goal:** this is not a replacement for a real controller. The binding constraints are the measured motion latency and a single fused motion stream that rules out dual-stick. It's a novelty input device that should feel good for slow-to-medium-paced games and be honest about not working for fast ones. Discrete inputs, if they prove viable at all, will be few and slow — a fire button, not a trigger you can hold analog.

---

## 2. Hardware constraints (measured limits, not guesses to design around)

| Property | Value | Consequence |
|---|---|---|
| Update rate | ~49 Hz observed on AirPods Pro 3 | ~20 ms median between samples in the first capture. Treat as model-specific until tested more broadly. |
| Streams available | attitude (quaternion + Euler), rotationRate, userAcceleration, gravity | Attitude is the useful one. Acceleration is too noisy for position. |
| Devices per session | One fused stream only | **Cannot** use two buds as two independent sticks. Hard blocker on dual-stick. |
| Yaw stability | Drifts over minutes | Only roll and pitch are usable as absolute axes. |
| Ear detection | Motion may stop when bud is not in an ear | Must disable Automatic Ear Detection in Bluetooth settings. |
| Latency | ~50–90 ms end to end, measured | Fine for driving/flying, unplayable for fighting games. |
| Force sensor | Present on all stemmed models. No public API. | Reachable only indirectly, via media remote commands. See §6.1. |
| Stem swipe (Pro 2+) | Present. No public API. Bound to system volume. | Reachable only by observing volume deltas. See §6.2. |

The single-stream limit is the most important line in this table. Every design decision downstream follows from it.

---

## 3. Architecture

Four stages, each independently testable.

```
[AirPod IMU] → Source → Filter → Mapper → Emitter → [Game]
```

### 3.1 Source
Wraps `CMHeadphoneMotionManager`. Responsibilities: authorization, availability checks, connect/disconnect handling, and publishing a `MotionSample` struct at whatever rate the hardware gives.

```swift
struct MotionSample {
    let timestamp: TimeInterval
    let roll: Double      // radians
    let pitch: Double     // radians
    let yaw: Double       // radians, drifts — use with caution
    let rotationRate: CMRotationRate
}

final class MotionSource {
    private let manager = CMHeadphoneMotionManager()
    var onSample: ((MotionSample) -> Void)?

    func start() throws {
        guard manager.isDeviceMotionAvailable else { throw PodStickError.noDevice }
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let m = motion else { return }
            self?.onSample?(MotionSample(
                timestamp: m.timestamp,
                roll: m.attitude.roll,
                pitch: m.attitude.pitch,
                yaw: m.attitude.yaw,
                rotationRate: m.rotationRate
            ))
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}
```

Requires macOS 14 or later and `NSMotionUsageDescription` in Info.plist. Current Apple documentation says starting motion updates without the usage description crashes the app.

### 3.2 Filter
Raw attitude benefits from filtering even though the first AirPods Pro 3 capture arrived at ~49 Hz. Two operations, in order:

1. **One Euro filter** on each axis. Preferred over a plain low-pass because it adapts: heavy smoothing when the bud is nearly still (kills jitter at rest), light smoothing during fast motion (preserves responsiveness). Starting parameters: `minCutoff = 1.0`, `beta = 0.007`, `dCutoff = 1.0`. Tune `beta` upward if it feels laggy during flicks.
2. **Resample to 120 Hz** by linear interpolation between the last two filtered samples, driven by a `CVDisplayLink` or timer. This does not add information, but it makes the emitted stream smooth enough that games with their own input smoothing don't stutter.

### 3.3 Mapper
Converts filtered angles to a normalized stick vector in `[-1, 1]²`.

- **Calibration / zeroing.** Store a reference quaternion `q₀` captured on user command. Every subsequent sample is expressed as the relative rotation `q₀⁻¹ · q`. This makes the neutral position wherever the user's hand happened to be, and sidesteps absolute yaw drift entirely. Re-zero on hotkey, on app focus, and automatically after 3 seconds of near-zero rotation rate.
- **Range.** Default full deflection at ±30° of tilt. User-adjustable 15°–60°. Smaller range = twitchier, less wrist travel.
- **Deadzone.** Radial (not per-axis), default 8%, with the remaining range rescaled so output is continuous at the deadzone boundary. Per-axis deadzones produce the classic "sticky cross" feel and should not be used.
- **Response curve.** `output = sign(x) · |x|^γ`, default `γ = 1.8`. Exposed as a slider labeled by feel (Linear → Precise) rather than by gamma value.
- **Clamp** to the unit circle, not the unit square, so diagonal magnitude doesn't exceed 1.

### 3.4 Emitter
Two backends behind one protocol.

```swift
protocol StickEmitter {
    func emit(x: Double, y: Double)
}
```

**Backend A — Synthetic keys (`CGEvent`).** Ships first. Crosses each axis against a threshold (default 0.5, with 0.1 hysteresis to prevent chatter at the boundary) and posts key down/up for WASD or arrows. Works with literally any game that reads the keyboard, including browser games. Loses all analog nuance, which is the entire point of the project, so treat it as the compatibility fallback rather than the flagship.

Requires Accessibility permission under Privacy & Security. The app must detect denial and link the user directly to the settings pane rather than failing silently.

**Backend B — Virtual HID gamepad (DriverKit / `HIDDriverKit`).** The real version. Publishes a virtual HID device with a standard gamepad descriptor exposing one analog stick. Games see a genuine controller and apply their own curves and deadzones on top — which means the mapper defaults should be gentle to avoid double-processing.

Costs: requires a paid developer account, the `com.apple.developer.driverkit.family.hid.device` entitlement (a manual request to Apple), and a system extension approval flow the user has to click through. Budget a week for the entitlement round trip alone. Ship A while waiting on B.

---

## 4. Interface

Menu bar app. No dock icon, no main window.

- **Menu bar glyph** doubles as a live indicator: filled dot when connected and streaming, hollow when disconnected, animated ring during calibration.
- **Dropdown** contains: on/off toggle, current profile picker, "Re-zero" item with its hotkey shown, and Settings.
- **Settings window**, three tabs:
  - *Stick* — a live 2D visualization of the current output vector inside the deadzone circle, plus range, deadzone, and curve controls. The visualization is the most important element in the app; it makes an invisible input stream debuggable by feel.
  - *Output* — backend picker, key bindings for the CGEvent backend, permission status with repair links.
  - *Profiles* — named parameter sets, optionally auto-switching on frontmost application bundle ID.
- **Global hotkeys** for re-zero and emergency disable. Emergency disable matters: a stuck synthetic key with no way to release it is genuinely disruptive, and the app should also drop all held keys on focus loss and on quit.

---

## 5. Milestones

1. **Spike (half a day).** Console app, print roll and pitch. Confirms hardware, permissions, and rate on the actual buds before any architecture exists.
2. **Filter + visualizer (1 day).** SwiftUI view showing the raw and filtered vectors side by side. Tune One Euro parameters here, by eye, before writing any emitter.
3. **CGEvent backend (1 day).** Playable end to end. Test against a browser driving game.
4. **Menu bar shell and profiles (2 days).**
5. **DriverKit backend (1–2 weeks, gated on entitlement).**

Stages 1–3 produce something you can hand to someone and watch them laugh at, which is the actual deliverable for a project like this.

---

## 6. Open questions

### 6.1 Discrete inputs — the force sensor

The stem's force sensor handles single, double, and triple press, plus press-and-hold. None of it is exposed by a public API; the system consumes the gesture before any third-party app sees it. Three possible routes, none committed to:

**Route A — media remote commands.** Presses are dispatched as transport controls: single = play/pause, double = next track, triple = previous. An app that owns the Now Playing session can register `MPRemoteCommandCenter` handlers and receive them as callbacks. This is the most promising route and effectively yields three buttons.

Downsides: requires holding an audio session (silent looping audio) for the app's whole lifetime, which hijacks media control system-wide — the user's actual music becomes uncontrollable while PodStick runs, and any other player may fight for the session. Remote-command latency is worse than the motion stream and unmeasured. Press-and-hold is bound to noise-control cycling and probably never arrives. Triple-press may be remapped to Accessibility Shortcut on some users' devices. Nothing here is contractual; Apple could re-route these at any point.

**Route B — accelerometer spike detection.** A press is a physical impulse on a body whose IMU we're already reading, so it should appear as a spike in `userAcceleration`.

Downsides: even at the observed ~49 Hz a press may span only a few samples, so detection will be marginal. It cannot distinguish press count reliably, and it fires on any knock or hand tremor. Worst of all it does not suppress the underlying media action, so every "button press" also pauses the user's music — Route B is strictly additive to Route A's problems, not an alternative to them.

**Route C — motion gestures as buttons.** Ignore the sensor entirely; detect a sharp flick or a shake in the attitude stream and treat it as a discrete event.

Downsides: any gesture large enough to detect also moves the stick, so the axes must be gated during and after a gesture, which produces a visible hitch. Realistically limited to one or two events.

**Recommended investigation order:** A, spiked for one day to measure latency and confirm which press counts survive. If latency is above roughly 150 ms, discrete input is not worth building at all and the project stays motion-only.

### 6.2 Discrete inputs — the stem swipe (Pro 2 and later)

The swipe adjusts system output volume and has no API. The only observation route is to watch output volume via CoreAudio, treat deltas as input events, and immediately restore the previous level.

Downsides: it's a relative encoder, not an absolute slider — no position, only direction and rate. The restore loop risks audible volume flutter and will fight any other app or the user's own volume keys. It's Pro 2+ only, splitting the feature across hardware. And the failure mode is loud: a missed restore leaves output at an unexpected level. Low priority; documented mainly so the option isn't lost.

### 6.3 Other

- **Can the second bud be used at all?** Not concurrently through this API. Possible workaround: second bud paired to a second machine relaying over the network. Almost certainly not worth it.
- **iOS version.** Same API, but no way to inject input into other apps. On iOS this only makes sense as a control scheme inside a game you write yourself.
- **AirPods Max** report the same stream and would work identically, which is very funny and should be supported for free.

---

## 7. Success criteria

Someone picks up a single AirPod, tilts it, and a car on screen turns proportionally with no perceptible lag on a slow game. They can re-zero without opening a window. Nothing gets stuck when they quit.
