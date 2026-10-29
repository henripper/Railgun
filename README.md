# Railgun

A system-wide equalizer for macOS that lives in the menu bar. It captures everything your Mac
plays, runs it through a 10-band EQ, a room reverb and a peak limiter, and sends it to your
current output device (AirPods, speakers, anything). There are no time limits, no virtual audio
driver and no server.

It also has an optional visuals window with beat-reacting effects: Matrix rain, and a
Winamp-style psychedelic fractal with glowing oscilloscope lines.

## Features

- 10-band parametric EQ (32 Hz – 16 kHz) with preamp
- Room reverb with Apple's factory environments and a dry/wet mix
- Peak limiter, so big bass boosts don't clip
- Follows your default output device and restarts itself when it changes
- Visuals window (double-click for full screen, Esc to exit)
- Launch at login

## Install

1. Download the latest `.dmg` from [Releases](../../releases).
2. Open it and drag **Railgun** onto the **Applications** shortcut.
3. Open Railgun from Applications. It lives in the menu bar (no Dock icon).

**First launch:** Railgun isn't notarized by Apple (that needs a paid developer account), so
macOS blocks it the first time. Try to open it once, then go to System Settings →
Privacy & Security, scroll down and click **Open Anyway** next to Railgun. You only do this once.

Then macOS asks for permission to record system audio. Allow it, otherwise Railgun has nothing
to process. If sound ever cuts out, check System Settings → Privacy & Security →
Screen & System Audio Recording and make sure Railgun is on.

Turn on **Launch at login** in the menu once Railgun is in Applications.

## Requirements

- macOS 14.4 or later (uses the Core Audio process-tap API)
- Apple Silicon Mac
- Xcode Command Line Tools (`xcode-select --install`), only if you build it yourself

## Build from source

```bash
./build.sh        # builds build/Railgun.app
./package.sh      # also packs a drag-to-Applications .dmg
```

Rebuilt copies are signed ad hoc, so macOS may ask for the audio permission again.

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
| `Sources/Visuals.swift` | Visuals window and the effect list |
| `Sources/MatrixRain.swift`, `Sources/PsychedelicFractal.swift` | The visual effects |
| `tools/make-icon.swift` | Draws the app icon |

See [ROADMAP.md](ROADMAP.md) for planned work.
