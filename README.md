# Railgun

A system-wide equalizer for macOS that lives in the menu bar. It captures everything your Mac
plays, runs it through a 10-band EQ, a room reverb and a peak limiter, and sends it to your
current output device (AirPods, speakers, anything). There are no time limits, no virtual audio
driver and no server.

It also has an optional visuals window, starting with a beat-reacting Matrix rain.

## Features

- 10-band parametric EQ (32 Hz – 16 kHz) with preamp
- Room reverb with Apple's factory environments and a dry/wet mix
- Peak limiter, so big bass boosts don't clip
- Follows your default output device and restarts itself when it changes
- Visuals window (double-click for full screen, Esc to exit)
- Launch at login

## Requirements

- macOS 14.4 or later (uses the Core Audio process-tap API)
- Apple Silicon Mac
- Xcode Command Line Tools (`xcode-select --install`) to build

## Build and run

```bash
./build.sh
open build/Railgun.app
```

On first launch macOS asks for permission to record system audio. Allow it, otherwise Railgun
has nothing to process. If you rebuild, macOS may ask again because the app is signed ad hoc.
To keep it across rebuilds, allow Railgun in System Settings → Privacy & Security →
Screen & System Audio Recording.

## How it works

1. A Core Audio process tap captures all system audio and mutes the original.
2. The tap and the output device share one private aggregate device, so a single IO callback
   reads the captured audio and writes the processed result on the same clock.
3. The audio goes through `AVAudioEngine` (EQ → reverb → limiter) in manual rendering mode.
4. A copy of the processed audio feeds an FFT and beat detector that drive the visuals.

## Adding a visual effect

Visual effects conform to the `Visualizer` protocol in `Sources/Visuals.swift`. Add a new
class, then add a case to `VisualEffectKind`. See `Sources/MatrixRain.swift` for an example.

## Project layout

| Path | What it does |
| --- | --- |
| `Sources/AudioPipeline.swift` | Tap, aggregate device, EQ / reverb / limiter engine |
| `Sources/AppModel.swift` | Settings, persistence, device-change handling |
| `Sources/RailgunApp.swift` | Menu-bar UI |
| `Sources/AudioAnalyzer.swift` | FFT bands and beat detection |
| `Sources/MatrixRain.swift`, `Sources/Visuals.swift` | Visuals window and effects |
| `tools/make-icon.swift` | Draws the app icon |

See [ROADMAP.md](ROADMAP.md) for planned work.
