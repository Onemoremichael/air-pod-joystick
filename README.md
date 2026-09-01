# PodStick

Turn an AirPod into a tiny two-axis joystick.

PodStick is a macOS experiment that reads the orientation sensor inside motion-capable AirPods and maps a single bud's physical movement to a conventional analog-stick vector. The current prototype includes a live visualizer, a steering playground, guided data capture, and a grip-specific mapping learned from a real AirPods Pro 3 calibration.

The wonderfully strange physical setup is an AirPod held by its body or stem with the silicone ear tip inverted against a tabletop. The folded tip acts like a soft joystick base while the AirPod's IMU supplies the motion.

> [!NOTE]
> PodStick is currently a motion playground, not a system-wide controller. It proves the physical interaction and mapping, but does not yet emit keyboard events or present a virtual HID gamepad to other applications.

## What has been proven

The first tabletop calibration was recorded on AirPods Pro 3 connected to macOS 26.5.2. The held AirPod remained active outside the ear after Automatic Ear Detection was disabled.

| Measurement | Result |
| --- | ---: |
| Samples | 640 |
| Capture duration | 12.97 seconds |
| Effective update rate | 49.13 Hz |
| Median sample interval | 20 ms |
| Largest observed gap | 134 ms |
| Gaps over 30 ms | 2 |
| Neutral roll noise | ~0.01° standard deviation |
| Neutral pitch noise | ~0.02° standard deviation |
| Observed roll range | −2.1° to +14.6° |
| Observed pitch range | −29.5° to +23.8° |

The measured ~49 Hz stream is substantially better than the project's original 25 Hz assumption. Treat these figures as one-device experimental results, not guarantees from Apple.

The calibration also demonstrated why ordinary Euler roll/pitch mapping is insufficient for this grip. Tabletop forward, backward, left, and right movements rotate the diagonally oriented AirPod across all three quaternion components. PodStick therefore uses the full relative rotation vector and a learned projection rather than assigning roll and pitch directly to X and Y.

## Features

- Live `CMHeadphoneMotionManager` capture
- Automatic retry when AirPods connect after the app launches
- Motion permission, device availability, sample-rate, count, and gap diagnostics
- One-click neutral calibration with `Shift-Command-R`
- Full 3D relative-quaternion mapping for the tested tabletop grip
- Conventional forward/backward and left/right output orientation
- Circular output clamping and a radial deadzone
- Time-based smoothing that remains consistent across sample rates
- Raw and processed stick visualization
- Original roll/pitch mapper for comparison
- Guided forward/backward/left/right calibration recording
- Local CSV export containing attitude, acceleration, gravity, rotation rate, and mapped output
- A tiny built-in slalom for testing steering feel

## Requirements

- macOS 14 or newer
- Motion-capable AirPods
- Swift 6.1 or newer through Xcode or the Apple Command Line Tools
- Motion & Fitness permission for PodStick

The learned default mapping was fitted specifically with AirPods Pro 3 and the inverted-tip tabletop grip. Other AirPods models and grips can use the generic mapper, but have not yet been physically validated in this repository.

## Quick start

Clone the repository, then build and launch the signed app bundle:

```sh
git clone https://github.com/Onemoremichael/air-pod-joystick.git
cd air-pod-joystick
make test
make run
```

`make run` builds an ad-hoc-signed `.build/PodStick.app`, adds the required `NSMotionUsageDescription`, and opens it. Do not run the bare `.build/debug/PodStick` executable: a raw Swift Package executable has no application-bundle privacy metadata.

If Xcode was just installed, open it once and accept its license and setup prompts before running the commands.

## Connect the AirPods correctly

A Bluetooth or Find My connection alone is not enough. The AirPods must be active as a Mac audio device before Core Motion exposes headphone motion.

1. Put the AirPods in your ears so macOS fully connects them.
2. Open **Control Center → Sound** and choose the AirPods as the output device.
3. Confirm that audio actually plays through them.
4. Open **System Settings**, select the AirPods in the sidebar, and disable **Automatic Ear Detection**.
5. Remove the bud you want to use as the joystick.
6. Return to PodStick; it retries automatically until the motion source becomes available.

The header should progress from **Waiting for AirPods** to **Starting motion stream** and finally **Streaming**. The bottom diagnostics should show **AirPods available**, an authorized permission state, and a nonzero update rate.

## Use the learned tabletop grip

1. Invert the silicone ear tip so it can rest against the tabletop.
2. Hold the AirPod in the same comfortable orientation you intend to use while playing.
3. Keep **Learned grip** enabled.
4. Click **Zero** or press `Shift-Command-R`.
5. Move the top of the AirPod forward, backward, left, and right.

The blue output dot should behave like a normal stick:

| Physical movement | Output |
| --- | --- |
| Forward | Up |
| Backward | Down |
| Left | Left |
| Right | Right |

The default learned mode uses a 5% radial deadzone and 40 ms smoothing. The measured neutral signal was clean enough that heavier smoothing only added unnecessary lag.

Uncheck **Learned grip** to compare the generic mapper. In generic mode, the range and axis inversion controls become available.

## Record a calibration

Once motion is streaming, click **Record forward / backward / left / right**. PodStick automatically re-zeros and guides a 13-second sequence:

1. Hold neutral
2. Pitch forward and hold
3. Return to center
4. Pitch backward and hold
5. Return to center
6. Tilt left and hold
7. Return to center
8. Tilt right and hold

Every callback is labeled with its current stage and saved to:

```text
~/Documents/PodStick Captures/
```

Each CSV contains:

- Capture time and Core Motion timestamp
- Absolute quaternion
- Relative roll and pitch
- Three-axis rotation rate
- Three-axis user acceleration
- Gravity vector
- Raw stick output
- Smoothed stick output

Captures stay local and are not added to the repository.

## How the learned mapping works

The processing path is:

```text
AirPod IMU
    → CMHeadphoneMotionManager
    → relative quaternion (neutral⁻¹ × current)
    → shortest 3D rotation vector
    → learned 3×2 grip projection
    → radial deadzone
    → circular clamp
    → time-based smoothing
    → visualizer / slalom
```

The first capture supplied stable neutral, forward, backward, left, and right poses. A least-squares projection fitted their 3D rotation vectors to the desired stick targets `(0,0)`, `(0,-1)`, `(0,1)`, `(-1,0)`, and `(1,0)`. On the recorded poses, the fitted mapping produced approximately:

| Pose | Fitted X | Fitted Y |
| --- | ---: | ---: |
| Forward | −0.04 | −1.00 |
| Backward | −0.06 | +0.91 |
| Left | −0.94 | +0.09 |
| Right | +1.00 | +0.08 |

This reduces directional cross-talk while preserving the AirPod's natural diagonal orientation. The implementation and coefficients are in `Sources/PodStickCore/JoystickMapping.swift` and are covered by deterministic tests.

## Architecture

The code is split so the platform-independent math can be tested without AirPods:

```text
PodStickCore
├── MotionQuaternion
├── JoystickMapper
├── GripCalibratedMapper
└── ExponentialStickSmoother

PodStick macOS app
├── MotionController
├── BaselineCapture
├── SwiftUI visualizer
└── Slalom playground
```

`MotionController` owns `CMHeadphoneMotionManager`, connection retry, permission state, neutral calibration, telemetry, mapping selection, and smoothing. `BaselineCapture` labels and persists raw experimental data. The SwiftUI layer only presents controls and output.

## Development

Run the tests:

```sh
swift test
```

Build the Swift Package executable:

```sh
swift build
```

Create the signed application bundle:

```sh
./scripts/package-app.sh
```

The test suite covers:

- Quaternion-relative neutral behavior
- Euler mapping at full deflection
- Radial deadzone continuity and rescaling
- Circular diagonal clamping
- Time-based smoothing
- All four poses from the first learned-grip calibration

## Troubleshooting

### “Waiting for AirPods” or “AirPods unavailable”

Select the AirPods under **Control Center → Sound**. Seeing them connected under Bluetooth or Find My does not necessarily establish the Core Audio connection needed for motion.

### Motion stops when removing the bud

Disable **Automatic Ear Detection** while the AirPods are worn and connected. After changing the setting, confirm the AirPods remain selected as the audio output when removed.

### Motion permission is denied

Open **System Settings → Privacy & Security → Motion & Fitness**, enable PodStick, then quit and reopen it.

### The app launches but never requests permission

Use the packaged `.build/PodStick.app`. The executable produced directly by Swift Package Manager does not contain `NSMotionUsageDescription` because it is not an application bundle.

### Directions feel wrong

First click **Zero** in the intended neutral grip. The learned mapping assumes the inverted-tip orientation from the original AirPods Pro 3 test. For a different model or grip, disable **Learned grip** and use the generic range and inversion controls until per-user learned calibration is implemented.

## Privacy

PodStick has no network client and sends no motion data anywhere. Live samples remain in memory unless a baseline capture is explicitly started. Baseline CSV files are written only to `~/Documents/PodStick Captures`.

## Current limitations

- Only one fused headphone-motion stream is available at a time.
- The tested prototype uses one AirPod as one two-axis stick.
- No virtual gamepad or keyboard emitter exists yet.
- The learned coefficients are tied to the first tested grip rather than a saved per-user profile.
- Stem presses and swipes are not exposed through the public motion API.
- Long-term drift, battery behavior, and behavior across AirPods generations need broader testing.

## Roadmap

- Turn the guided recording into automatic per-user grip calibration
- Save and switch calibration profiles
- Add an emergency-disable shortcut and robust lifecycle cleanup
- Add a keyboard output backend for quick compatibility testing
- Investigate a standard virtual HID gamepad backend
- Validate more AirPods models and macOS versions
- Measure motion-to-photon and motion-to-game latency with high-speed video

## Repository layout

```text
.
├── Package.swift
├── Resources/Info.plist
├── Sources/
│   ├── PodStick/
│   └── PodStickCore/
├── Tests/PodStickCoreTests/
├── scripts/package-app.sh
├── airpods-joystick-spec.md
└── README.md
```

The broader product thinking, emitter options, and unresolved input ideas are documented in `airpods-joystick-spec.md`.
