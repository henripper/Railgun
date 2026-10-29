import AVFoundation
import SwiftUI

@main
struct RailgunApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            Image(nsImage: MenuBarGlyph.image(active: model.settings.enabled))
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel

    private static let reverbPresets: [(name: String, preset: AVAudioUnitReverbPreset)] = [
        ("Small Room", .smallRoom), ("Medium Room", .mediumRoom), ("Large Room", .largeRoom),
        ("Medium Hall", .mediumHall), ("Large Hall", .largeHall), ("Plate", .plate),
        ("Medium Chamber", .mediumChamber), ("Large Chamber", .largeChamber), ("Cathedral", .cathedral),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Railgun").font(.headline)
                Spacer()
                Toggle("Enabled", isOn: $model.settings.enabled).toggleStyle(.switch).labelsHidden()
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary)

            Divider()
            Toggle("Equalizer", isOn: $model.settings.eqEnabled)
            Group {
                HStack {
                    Text("Preamp").font(.caption)
                    Slider(value: $model.settings.preamp, in: -24...12)
                    Text(String(format: "%+.1f dB", model.settings.preamp))
                        .font(.caption.monospacedDigit()).frame(width: 56, alignment: .trailing)
                }
                HStack(spacing: 2) {
                    ForEach(EQSettings.frequencies.indices, id: \.self) { index in
                        VStack(spacing: 4) {
                            Text(String(format: "%+.1f", model.settings.gains[index]))
                                .font(.system(size: 9).monospacedDigit())
                            VerticalSlider(value: $model.settings.gains[index], range: -24...24)
                                .frame(height: 130)
                            Text(Self.label(EQSettings.frequencies[index])).font(.system(size: 9))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .disabled(!model.settings.eqEnabled)
            .opacity(model.settings.eqEnabled ? 1 : 0.4)

            Divider()
            Toggle("Room (reverb)", isOn: $model.settings.reverbEnabled)
            Group {
                Picker("Environment", selection: $model.settings.reverbPreset) {
                    ForEach(Self.reverbPresets, id: \.preset.rawValue) { Text($0.name).tag($0.preset.rawValue) }
                }
                HStack {
                    Text("Dry/Wet").font(.caption)
                    Slider(value: $model.settings.reverbMix, in: 0...100)
                    Text("\(Int(model.settings.reverbMix))%")
                        .font(.caption.monospacedDigit()).frame(width: 56, alignment: .trailing)
                }
            }
            .disabled(!model.settings.reverbEnabled)
            .opacity(model.settings.reverbEnabled ? 1 : 0.4)

            Divider()
            Toggle("Visuals", isOn: $model.visualsEnabled)
            Picker("Effect", selection: $model.visualEffect) {
                ForEach(VisualEffectKind.allCases) { Text($0.title).tag($0) }
            }
            Text("Double-click the visuals window for full screen, Esc to exit.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()
            Toggle("Peak limiter (prevents clipping from bass boost)", isOn: $model.settings.limiterEnabled)
            Toggle("Launch at login", isOn: $model.launchAtLogin)

            HStack {
                Button("Restore defaults") { model.restoreDefaults() }
                Spacer()
                Button("Quit Railgun") { model.quit() }
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    private static func label(_ frequency: Float) -> String {
        frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"
    }
}

struct VerticalSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let span = range.upperBound - range.lowerBound
            let position = CGFloat((value - range.lowerBound) / span)
            let zero = CGFloat((0 - range.lowerBound) / span)
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.secondary.opacity(0.25)).frame(width: 4)
                Rectangle().fill(Color.accentColor)
                    .frame(width: 4, height: abs(position - zero) * height)
                    .offset(y: -min(position, zero) * height)
                Circle().fill(Color.white).shadow(radius: 1).frame(width: 14, height: 14)
                    .offset(y: -position * height + 7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let fraction = Float(1 - min(max(drag.location.y / height, 0), 1))
                value = ((range.lowerBound + fraction * span) * 10).rounded() / 10
            })
        }
    }
}
