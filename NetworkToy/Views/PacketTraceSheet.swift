import SwiftUI
import LabKitUI

struct PacketTraceSheet: View {
    let model: NetworkStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    summary
                    stack
                    phases
                    hops
                    if let snapshot = model.snapshot, !snapshot.events.isEmpty { events(snapshot.events) }
                    Text("Dots are symbolic batches with time-scaled motion. Dot counts and loss markers are not exact packet counts or percentages. Routes are illustrative; the app sends no real internet traffic.")
                        .font(.caption).foregroundStyle(NetTheme.muted)
                }.padding(24)
            }
            .background(NetTheme.background)
            .navigationTitle("Packet journey").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("\(model.config.transport.title) · \(model.config.medium.title)")
            Text("\(netNumber(model.config.payloadMB, digits: 1)) MB → \(netNumber(model.metrics.compressedBytes / 1e6, digits: 2)) MB")
                .font(.title2.monospacedDigit()).foregroundStyle(NetTheme.modelled)
            Text("\(model.metrics.packetCount) data packets · \(netTime(model.metrics.totalMs)) modeled total")
                .font(.subheadline).foregroundStyle(NetTheme.muted)
            if model.config.transport == .udp {
                Text("Raw UDP delivers an expected \(netNumber(model.metrics.deliveredPct, digits: 1))% of independently useful chunks. Missing datagrams remain missing; a whole compressed file may be unusable.")
                    .font(.subheadline).foregroundStyle(NetTheme.danger)
            } else {
                Text("Reliable delivery · about \(netNumber(model.metrics.expectedRetransmissions)) retransmissions under this loss setting")
                    .font(.subheadline).foregroundStyle(NetTheme.muted)
            }
            Text("Goodput is useful original bytes divided by total journey time. Compression can make it exceed compressed wire capacity.")
                .font(.caption).foregroundStyle(NetTheme.muted)
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow("Data on wire")
                    Text("\(netNumber(model.metrics.wireBytes / 1e6, digits: 2)) MB").font(.subheadline.monospacedDigit())
                }
                VStack(alignment: .leading, spacing: 5) {
                    Eyebrow("Codec work")
                    Text(netTime(model.metrics.compressionMs + model.metrics.decompressionMs)).font(.subheadline.monospacedDigit())
                }
            }.foregroundStyle(NetTheme.modelled).padding(.top, 6)
            Text("Wire total includes data-direction IP headers and retries; excludes setup, ACKs and link/TLS framing.")
                .font(.caption).foregroundStyle(NetTheme.muted)
        }.accessibilityIdentifier("traceSummary")
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("What's inside a packet?")
            HStack(spacing: 3) {
                envelope("Link", color: NetTheme.wireless)
                envelope("IP", color: NetTheme.fiber)
                if model.config.transport == .quic { envelope("UDP", color: NetTheme.packet) }
                envelope(model.config.transport.title, color: NetTheme.packet)
                envelope("Data", color: NetTheme.modelled)
            }
            Text(packetExplanation)
                .font(.caption).foregroundStyle(NetTheme.muted)
        }
    }

    private var packetExplanation: String {
        switch model.config.transport {
        case .udp: "A raw UDP datagram: link envelope → IP address → UDP ports → payload. Encryption is not implied."
        case .tcp: "Compressed application data is protected with TLS, then carried by TCP, IP and each local link. Routers replace the local link envelope at every hop."
        case .quic: "QUIC uses TLS-derived keys to protect its own packets, carried inside UDP datagrams. It does not use TLS record framing. Routers replace each local link envelope."
        }
    }

    private func envelope(_ title: String, color: Color) -> some View {
        Text(title).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(color).frame(maxWidth: .infinity, minHeight: 42)
            .background(color.opacity(0.10), in: .rect(cornerRadius: 8))
    }

    private var phases: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow("From name to bytes")
            ForEach(model.metrics.phases, id: \.id) { phase in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: phaseSymbol(phase.id)).font(.caption)
                        .foregroundStyle(model.snapshot?.phase == phase.id ? NetTheme.fiber : NetTheme.muted)
                        .frame(width: 20, height: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(phase.label).font(.subheadline.weight(.medium))
                            Spacer()
                            Text(netTime(phase.durationMs)).font(.caption.monospacedDigit()).foregroundStyle(NetTheme.modelled)
                        }
                        Text(phase.detail).font(.caption).foregroundStyle(NetTheme.muted)
                    }
                }
            }
        }
    }

    private var hops: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Hop by hop · \(model.metrics.route.count) links")
            ForEach(Array(model.metrics.route.enumerated()), id: \.offset) { index, segment in
                HStack(alignment: .top, spacing: 12) {
                    Text(String(format: "%02d", index + 1)).font(.caption.monospacedDigit()).foregroundStyle(NetTheme.muted)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(city(segment.from)) → \(city(segment.to))").font(.subheadline)
                        Text("\(segment.medium.title) · \(netNumber(segment.distanceKm)) km · \(netTime(segment.propagationMs)) travel")
                            .font(.caption).foregroundStyle(segment.medium == .wireless ? NetTheme.wireless : NetTheme.fiber)
                    }
                }
            }
            if model.config.medium == .wireless {
                Text("Long radio arcs stand for abstract radio/space backhaul. Ordinary Wi-Fi and cellular links are local; use Mixed for radio access with a fiber backbone.")
                    .font(.caption).foregroundStyle(NetTheme.muted)
            }
        }
    }

    private func events(_ items: [NetworkEvent]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Transfer log")
            ForEach(items.suffix(12)) { event in
                HStack(alignment: .top, spacing: 12) {
                    Text(netTime(event.timeMs)).font(.caption2.monospacedDigit()).foregroundStyle(NetTheme.modelled)
                        .frame(width: 60, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.label).font(.subheadline.weight(.medium))
                        Text(event.detail).font(.caption).foregroundStyle(NetTheme.muted)
                    }
                }
            }
        }
    }

    private func city(_ id: String) -> String { NetworkEngine.nodes.first { $0.id == id }?.city ?? id }
    private func phaseSymbol(_ id: String) -> String {
        switch id {
        case "dns": "magnifyingglass"
        case "compression": "arrow.down.right.and.arrow.up.left"
        case "handshake", "tcp", "tls": "lock.shield"
        case "transfer": "arrow.right"
        default: "checkmark.circle"
        }
    }
}
