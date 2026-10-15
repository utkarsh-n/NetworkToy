import SwiftUI
import LabKitCore
import LabKitFeedback
import LabKitUI

struct TuningSheet: View {
    @Bindable var model: NetworkStore
    @Bindable var haptics: HapticEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Change a variable. See the consequences.")
                        .font(.title3.weight(.medium))
                    Text("Readouts update immediately. Changing the network clears the current transfer; send again to watch the new journey.")
                        .font(.subheadline).foregroundStyle(NetTheme.muted)
                    parameter("Capacity", value: $model.config.bandwidthMbps, range: 1...1000,
                        unit: "Mbps", detail: "The bottleneck's width, not the speed of light.", id: "bandwidthSlider", logarithmic: true)
                    parameter("Extra one-way delay", value: $model.config.latencyMs, range: 0...200,
                        unit: "ms", detail: "Added to travel and queue delay. A round trip pays this twice.", id: "latencySlider")
                    parameter("Packet loss", value: $model.config.lossPct, range: 0...20,
                        unit: "%", detail: "TCP and QUIC recover missing data. Raw UDP leaves holes.", id: "lossSlider")
                    parameter("Compression", value: $model.config.compressionPct, range: 0...90,
                        unit: "%", detail: "Assumed payload reduction. Adds modeled CPU work before encryption.", id: "compressionSlider")
                    parameter("Payload", value: $model.config.payloadMB, range: 2...50,
                        unit: "MB", detail: "Decimal megabytes before compression.", id: "payloadSlider")
                    parameter("Shared capacity", value: $model.config.congestionPct, range: 0...90,
                        unit: "%", detail: "Capacity used by other traffic. Adds a simplified queue delay.", id: "congestionSlider")
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow("Playback")
                        Picker("Animation speed", selection: $model.playbackSpeed) {
                            Text("½×").tag(0.5); Text("1×").tag(1.0); Text("2×").tag(2.0)
                        }.pickerStyle(.segmented)
                        Text("Visual time is fitted to an 8–16 second journey. Every number shows modeled network time.")
                            .font(.caption).foregroundStyle(NetTheme.muted)
                        Toggle("Haptic feedback", isOn: $haptics.enabled)
                            .tint(Color(NetTheme.signature))
                    }
                    Button("Restore default network", systemImage: "arrow.counterclockwise") {
                        model.config = NetworkConfig(); model.playbackSpeed = 1; haptics.play(.reset)
                    }.buttonStyle(.glass).accessibilityIdentifier("defaultNetwork")
                }.padding(24)
            }
            .background(NetTheme.background)
            .navigationTitle("Tune the network").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func parameter(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
        unit: String, detail: String, id: String, logarithmic: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(netNumber(value.wrappedValue, digits: unit == "MB" ? 1 : 0)) \(unit)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(NetTheme.modelled)
                    .accessibilityIdentifier("\(id)Value")
            }
            if logarithmic {
                Slider(value: Binding(get: { log10(value.wrappedValue) }, set: { value.wrappedValue = pow(10, $0) }), in: log10(range.lowerBound)...log10(range.upperBound))
                    .accessibilityLabel(title).accessibilityValue("\(netNumber(value.wrappedValue)) \(unit)")
                    .accessibilityIdentifier(id)
            } else {
                Slider(value: value, in: range, onEditingChanged: { editing in haptics.play(editing ? .grab : .release) })
                    .accessibilityLabel(title).accessibilityIdentifier(id)
            }
            Text(detail).font(.caption).foregroundStyle(NetTheme.muted)
        }
    }
}

struct ExperimentSheet: View {
    let model: NetworkStore
    @Bindable var haptics: HapticEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Try a little what-if.").font(.title2.weight(.medium))
                    ForEach(NetworkExperiment.allCases) { experiment in
                        Button {
                            model.preset(experiment); haptics.play(.select); dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: experiment.icon).font(.title3).foregroundStyle(NetTheme.fiber)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(experiment.title).font(.headline).foregroundStyle(.white)
                                    Text(experiment.detail).font(.subheadline).foregroundStyle(NetTheme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(NetTheme.muted)
                            }.padding(18).background(NetTheme.panel, in: .rect(cornerRadius: 20))
                        }.buttonStyle(.plain).accessibilityIdentifier("experiment-\(experiment.rawValue)")
                    }
                    Text("These are editable scenarios on an illustrative network. Real networks and codecs vary.")
                        .font(.caption).foregroundStyle(NetTheme.muted)
                }.padding(24)
            }
            .background(NetTheme.background)
            .navigationTitle("Experiments").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
