# PodStick

Turn an AirPod into a tiny two-axis joystick.

PodStick is a macOS experiment that reads the orientation sensor inside motion-capable AirPods and maps a single bud's physical movement to a conventional analog-stick vector. The current prototype includes a live visualizer, a steering playground, guided data capture, and a grip-specific mapping learned from a real AirPods Pro 3 calibration.

The wonderfully strange physical setup is an AirPod held by its body or stem with the silicone ear tip inverted against a tabletop. The folded tip acts like a soft joystick base while the AirPod's IMU supplies the motion.

> [!NOTE]
> PodStick is not a system-wide controller and does not present a virtual HID gamepad. It can directly control FlightGear over a localhost connection, in addition to its built-in motion playgrounds.

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

The first end-to-end simulator test also succeeded with FlightGear 2024.1.7 on Apple Silicon. PodStick established a localhost TCP connection after the simulator entered a running flight, streamed the learned analog mapping into the Cessna's aileron and elevator controls, and produced responsive flight control from the tabletop AirPod. The FlightGear Launcher by itself does not open the property-server port; the flight must finish loading before PodStick can connect.

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
- A built-in arcade flight target test with tap-to-fire
- Direct analog aileron/elevator control of FlightGear over localhost
- FlightGear sensitivity, inversion, tap-action, connection, and packet diagnostics
- Neutral-on-disconnect, motion-stop, AirPod error, window-close, and app-quit safety
- An opt-in Stem Lab for volume-swipe throttle and press/tap trigger experiments

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

## Experiment with stem controls

Click **Stem Lab** to open three independent experiments:

- **Volume swipe → virtual throttle** observes changes to the default output device's Core Audio volume through both property notifications and a 20 Hz polling fallback, then mirrors the scalar as a 0–100% throttle. It does not restore the old value, so the swipe still changes actual system volume.
- **IMU tap → trigger** detects user-acceleration impulses at an adjustable threshold with a short cooldown. It does not claim or alter media controls, but aggressive stick movement can create false positives.
- **Force press → media command** starts silent playback and makes PodStick the Now Playing app so it can observe play/pause, next, and previous commands. This is explicitly opt-in because it temporarily takes those controls away from other media apps.

The public APIs do not expose raw AirPods touch position or force-sensor state. These experiments observe system volume changes, motion impulses, and media-command side effects instead.

In the first AirPods Pro 3 Stem Lab run, the IMU trigger produced clear 0.36–1.03 g impulses against a ~0.026 g median background. Neither property notifications nor 20 Hz polling observed volume changes from stem swipes, and the Now Playing experiment received no media commands. The volume and media-command panels remain diagnostic experiments; the IMU trigger is the only validated stem-adjacent input so far.

Opening Stem Lab automatically creates a timestamped `podstick-stem-lab_*.csv` in `~/Documents/PodStick Captures`. It continuously records motion and stick values plus separate rows for volume changes, detected impulses, and media commands. Closing Stem Lab writes a final session row and closes the file.

## Fly with FlightGear

[FlightGear](https://www.flightgear.org/) is a free, open-source flight simulator for macOS. PodStick talks directly to its built-in property server over TCP on this Mac, so no virtual controller driver, Accessibility permission, or keyboard emulation is required.

1. [Download and install FlightGear](https://www.flightgear.org/download/).
2. Open the FlightGear Launcher.
3. Under **Settings → Additional Settings**, add:

   ```text
   --telnet=5500
   --timeofday=noon
   ```

4. Start a flight—the launcher alone is not enough. The default Cessna 172 is a friendly first test.
5. In PodStick, click **FlightGear**.
6. Confirm port `5500`, click **Connect**, hold the AirPod at neutral, and click **Re-zero**.
7. Move the AirPod. Left/right drives `/controls/flight/aileron`; forward/backward drives `/controls/flight/elevator`.

The FlightGear panel includes sensitivity and per-axis inversion in case an aircraft or grip feels reversed. Stem taps default to both wheel brakes, which is useful in the Cessna. They can instead drive `/controls/armament/pickle` for a compatible aircraft, or be disabled.

PodStick deliberately connects only to `127.0.0.1`, so motion controls are never sent off the Mac. A connection normally produces about 50 control packets per second, matching the measured AirPods motion rate. Closing the FlightGear panel, disconnecting, stopping motion, losing the motion stream, closing PodStick, or quitting the app sends zero aileron/elevator and releases the selected tap action before closing the socket.

### Skip takeoff and start in the air

In the FlightGear Launcher, open **Location**, choose an airport and runway, and select **On final approach** rather than a parking position. A distance around 10 miles gives enough room to get comfortable with the controls. Turn away from the runway after loading if you just want to explore. The [FlightGear 2024.1 manual](https://flightgear.gitlab.io/getstart/release-2024.1/en/HTML/getstart-ench4.html) documents its airborne and approach starting positions.

Alternatively, add a free-flight preset under **Settings → Additional Settings**:

```text
--in-air
--altitude=3000
--vc=110
```

This starts the Cessna airborne at about 3,000 feet and 110 knots. Keep `--telnet=5500` and `--timeofday=noon` in the same settings box.

### Apple Silicon rendering workaround

FlightGear 2024.1 has known rendering issues on Apple Silicon. A black cockpit with stars, runway lights, or bright outlines can be a combination of a real-time nighttime start and the Atmospheric Light Scattering renderer. Start with `--timeofday=noon`. If the cockpit is still rendered incorrectly, open **View → Rendering Options**, disable **Atmospheric Light Scattering**, and lower **Shader Quality**. [FlightGear's maintainers recommend those settings](https://www.flightgear.org/blog/release-2024-1-2/) for affected Macs.

### FlightGear connection troubleshooting

- **Connection refused:** FlightGear is not running with `--telnet=5500`, the launcher is open but **Fly** has not produced a running flight yet, or its port differs from PodStick's port.
- **Black or outlined cockpit on an Apple Silicon Mac:** Force noon first, then disable Atmospheric Light Scattering and lower Shader Quality.
- **Connected but the aircraft does not move:** Turn off the aircraft autopilot, click **Re-zero**, and verify the live aileron/elevator values change in PodStick.
- **An axis is backward:** Enable **Invert aileron** or **Invert elevator** in the FlightGear panel.
- **Controls feel too aggressive:** Lower FlightGear sensitivity. PodStick clamps both axes to FlightGear's conventional `-1...1` range.
- **Port already in use:** Choose another port in both FlightGear's `--telnet=` option and the PodStick panel.

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
├── FlightGearBridge
├── SwiftUI visualizer
├── Slalom playground
└── Built-in flight playground
```

`MotionController` owns `CMHeadphoneMotionManager`, connection retry, permission state, neutral calibration, telemetry, mapping selection, smoothing, and routing each processed sample. `FlightGearBridge` owns the localhost TCP connection and lifecycle neutralization. `BaselineCapture` labels and persists raw experimental data. The SwiftUI layer presents controls and output.

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

PodStick has one opt-in network client: the FlightGear bridge, hard-coded to the loopback address `127.0.0.1`. It sends only mapped aileron/elevator values and configured tap events to a FlightGear process on the same Mac. It does not transmit raw motion samples or connect to the internet. Live samples remain in memory unless a capture is explicitly started. CSV files are written only to `~/Documents/PodStick Captures`.

## Shutdown behavior

Closing the last PodStick window quits the app and explicitly neutralizes FlightGear, closes its socket, and stops headphone motion, calibration capture, Core Audio listeners and polling, silent playback, Now Playing metadata, remote-command handlers, impulse detection, and Stem Lab recording. Stopping motion or losing the AirPods stream also neutralizes FlightGear. PodStick does not programmatically change system volume, the selected audio output, or Automatic Ear Detection, so those user-controlled settings are left as configured.

## Current limitations

- Only one fused headphone-motion stream is available at a time.
- The tested prototype uses one AirPod as one two-axis stick.
- External control currently targets FlightGear specifically; no virtual gamepad or keyboard emitter exists yet.
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
