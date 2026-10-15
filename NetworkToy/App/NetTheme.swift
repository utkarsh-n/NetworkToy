import SwiftUI
import LabKitCore
import LabKitUI

enum NetTheme {
    static let signature = LabColor(0.0, 0.36, 0.69)
    static let signalBlue = LabColor(0.35, 0.72, 1.0)
    static let fiberHue = LabColor(1.0, 0.75, 0.37)
    static let wirelessHue = LabColor(0.40, 0.81, 0.96)
    static let ground = LabGround(name: "bell-labs-1984",
        stage: LabColor(0.018, 0.028, 0.043), background: LabColor(0.018, 0.030, 0.046),
        panel: LabColor(0.04, 0.065, 0.092), plot: LabColor(0.002, 0.009, 0.016),
        muted: LabColor(0.58, 0.70, 0.78), dim: LabColor(0.23, 0.47, 0.58))
    static let palette = LabPalette(app: "SnoopyNet", ground: ground, signature: signalBlue,
        dataHues: [DataHue("fiber", "Fiber", fiberHue), DataHue("wireless", "Wireless", wirelessHue)])
    static let background = Color(ground.background)
    static let panel = Color(ground.panel)
    static let muted = Color(ground.muted)
    static let screen = Color(ground.plot)
    static let screenMuted = Color(ground.dim)
    static let paper = Color(ground.stage)
    static let paperPanel = Color(red: 0.055, green: 0.093, blue: 0.13)
    static let ink = Color(red: 0.86, green: 0.96, blue: 1.0)
    static let paperMuted = Color(ground.muted)
    static let globe = Color(red: 0.07, green: 0.60, blue: 1.0)
    static let fiber = Color(fiberHue)
    static let wireless = Color(wirelessHue)
    static let packet = Color(red: 0.96, green: 0.96, blue: 0.89)
    static let danger = Color(LabSemantic.warning)
    static let modelled = Color(red: 0.54, green: 0.87, blue: 1.0)

    static let bandwidth = ParamSpec("bandwidth", title: "Capacity", icon: "speedometer",
        tint: signalBlue, range: 1...1000, defaultValue: 100, scale: .logarithmic,
        detents: [Detent(10, "10 Mbps"), Detent(100, "100 Mbps"), Detent(1000, "1 Gbps")],
        hint: "More bytes per second. Travel speed stays the same.",
        detail: "Bottleneck link capacity. More capacity shortens serialization, but cannot remove propagation delay.",
        descriptor: "How wide is the pipe?", provenance: .modelled, format: .number(precision: 0, unit: "Mbps"))
    static let loss = ParamSpec("loss", title: "Loss", icon: "drop.triangle",
        tint: LabSemantic.warning, range: 0...20, defaultValue: 0, step: 0.1,
        hint: "Lost data is retried by TCP and QUIC. Raw UDP leaves gaps.",
        detail: "End-to-end packet loss probability in the teaching model.",
        descriptor: "Packets that go missing", provenance: .modelled, format: .number(precision: 1, unit: "%"))
    static let compression = ParamSpec("compression", title: "Compress", icon: "arrow.down.right.and.arrow.up.left",
        tint: LabSemantic.forecast, range: 0...90, defaultValue: 35, step: 1,
        hint: "Shrink the payload before encryption. Computing takes time too.",
        detail: "The chosen payload reduction is an assumption, not a guarantee for every file type.",
        descriptor: "Fewer bytes on the wire", provenance: .modelled, format: .number(precision: 0, unit: "%"))
}

struct Eyebrow: View {
    let text: String
    var color: Color = NetTheme.muted
    init(_ text: String, color: Color = NetTheme.muted) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(LabFont.eyebrow).tracking(1.7).foregroundStyle(color)
    }
}

func netNumber(_ value: Double, digits: Int = 0) -> String {
    value.formatted(.number.precision(.fractionLength(digits)))
}

func netTime(_ ms: Double) -> String {
    ms < 1000 ? "\(netNumber(ms)) ms" : "\(netNumber(ms / 1000, digits: 2)) s"
}
