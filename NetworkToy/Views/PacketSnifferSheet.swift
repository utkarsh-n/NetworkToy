import LabKitCore
import LabKitFeedback
import LabKitUI
import SwiftUI

/// An independent, offline probe. Local edits never mutate the playground's network.
struct PacketSnifferSheet: View {
    let haptics: HapticEngine
    @State private var config: NetworkConfig
    @State private var capture: SnifferResult?
    @State private var elapsedMs = 0.0
    @State private var isRunning = false
    @State private var variablesExpanded = false
    @State private var needsRestart = false
    @State private var filter: CaptureFilter = .all
    @State private var previousFinishedProbe: String?
    @State private var selection: SnifferDecodeSelection?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    init(config: NetworkConfig, haptics: HapticEngine) {
        _config = State(initialValue: config)
        self.haptics = haptics
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        introduction
                        statusPanel
                        presets
                        variablePanel
                        capturePanel.id(CaptureScrollTarget.packets)
                    }
                    .padding(20)
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                }
                .background(NetTheme.background.ignoresSafeArea())
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    captureControls {
                        proxy.scrollTo(CaptureScrollTarget.packets, anchor: .top)
                    }
                }
                .navigationTitle("Packet sniffer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("snifferDone")
                    }
                }
                .sheet(item: $selection) { selected in
                    SnifferPacketDecoder(selection: selected)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
        .tint(Color(NetTheme.signalBlue))
        .preferredColorScheme(.dark)
        .onChange(of: config) { _, _ in invalidateProbe() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { isRunning = false }
        }
        .onDisappear { isRunning = false }
        .task(id: isRunning) { await playCapture() }
    }

    private var observed: SnifferStats? { capture?.observedStats(at: elapsedMs) }
    private var visibleEvents: [SnifferEvent] {
        capture?.schedule.filter { $0.timeMs <= elapsedMs + 0.000_001 } ?? []
    }
    private var displayedEvents: [SnifferEvent] {
        visibleEvents.filter { event in
            filter == .all || [.drop, .retry, .queued, .duplicate, .exhausted].contains(event.kind)
        }
    }
    private var sentCount: Int {
        Set(visibleEvents.filter { $0.kind == .transmit && !$0.isAcknowledgment }.compactMap(\.packetID)).count
    }
    private var complete: Bool {
        guard let capture else { return false }
        return elapsedMs >= capture.durationMs
    }
    private var pathRTT: Double { NetworkEngine.calculate(config).rttMs }
    private var status: String {
        if isRunning { return "Capturing simulated traffic" }
        if complete { return "Probe complete" }
        if capture != nil { return "Capture paused" }
        return needsRestart ? "Network changed · start a new capture" : "Ready for a simulated capture"
    }
    private var startTitle: String {
        if isRunning { return "Pause capture" }
        if complete { return "Capture again" }
        if capture != nil { return "Resume capture" }
        return needsRestart ? "Start new capture" : "Start capture"
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("SIMULATED CAPTURE · 32 DATA PACKETS", color: NetTheme.modelled)
            Text("Watch a small probe, one event at a time.")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
            Text("This is generated traffic, not a capture of your device. The probe uses 32 source chunks of 1,200 B each; it is separate from the large globe transfer. Tap a packet event to inspect its teaching headers and byte ledger.")
                .font(.subheadline)
                .foregroundStyle(NetTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(city(config.sourceID)) → \(city(config.destinationID)) · \(config.transport.title) · \(config.medium.title)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color(NetTheme.signalBlue))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isRunning ? "record.circle" : complete ? "stop.circle" : "pause.circle")
                    .foregroundStyle(NetTheme.modelled)
                Text(status)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("snifferStatus")
                Spacer(minLength: 0)
            }
            ProgressView(value: capture.map { min(1, elapsedMs / max($0.durationMs, 0.001)) } ?? 0)
                .tint(Color(NetTheme.signalBlue))
                .accessibilityLabel("Probe progress")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                     count: typeSize.isAccessibilitySize ? 2 : 3),
                      alignment: .leading, spacing: 14) {
                counter("DATA SENT", value: "\(sentCount) / 32")
                counter("DELIVERED", value: "\(observed?.deliveredCount ?? 0) / 32")
                counter("DROP ATTEMPTS", value: "\(observed?.droppedAttempts ?? 0)")
                counter("RETRIES", value: "\(observed?.retryCount ?? 0)")
                counter("ACKS", value: "\(observed?.ackCount ?? 0)")
                counter("BUFFERED", value: "\(max(0, (observed?.receivedCount ?? 0) - (observed?.deliveredCount ?? 0)))")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("MODEL CLOCK  \(preciseTime(elapsedMs)) · RTT \(netTime(pathRTT))")
                Text("ALL-HOP WIRE  \(byteLabel(observed?.wireBytes ?? 0))")
                Text("OBSERVED GOODPUT  \(netNumber(observed?.goodputMbps ?? 0, digits: 2)) Mb/s")
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(NetTheme.modelled)
            .accessibilityElement(children: .combine)
            DisclosureGroup("What the counters mean") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Counters include only revealed events. Drops count failed data or ACK attempts; a retry may still deliver the data. ACKs count returning feedback frames, not unique chunks. Buffered chunks reached the receiver but await decoding or ordered delivery. RTT is a modeled path estimate. Wire bytes count data and ACK transmissions on every hop, including retries; setup bytes, local link framing, and physical coding are excluded.")
                    Text("Goodput counts original useful bytes delivered over modeled elapsed time. Playback fits the probe into 16 visual seconds; its timestamps retain modeled time.")
                    Text("This eager 32-chunk flight uses simplified recovery timers with backoff. Congestion windows, fast recovery, adaptive RTO/PTO, and routing changes are outside the probe. Recovery stops after eight retries per chunk; reliable transport can still fail.")
                }
                .font(.caption)
                .foregroundStyle(NetTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            }
            .font(.caption)
            if let previousFinishedProbe {
                Text("Previous finished probe: \(previousFinishedProbe)")
                    .font(.caption)
                    .foregroundStyle(Color(NetTheme.signalBlue))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(NetTheme.panel, in: .rect(cornerRadius: 18))
    }

    private func counter(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(.caption2, design: .monospaced)).foregroundStyle(NetTheme.muted)
            Text(value).font(LabFont.readoutValue).foregroundStyle(NetTheme.modelled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Conditions")
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { presetButtons }
            } else {
                HStack(spacing: 8) { presetButtons }
            }
            Text("\(netNumber(config.bandwidthMbps)) Mbps · \(netNumber(config.lossPct, digits: 1))% loss · +\(netNumber(config.latencyMs)) ms one way · \(netNumber(config.congestionPct))% shared")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(NetTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var presetButtons: some View {
        Button { applyPreset(.clean) } label: { presetLabel("Clean line") }
            .buttonStyle(.glass)
            .accessibilityIdentifier("sniffPresetClean")
        Button { applyPreset(.busy) } label: { presetLabel("Busy exchange") }
            .buttonStyle(.glass)
            .accessibilityIdentifier("sniffPresetBusy")
        Button { applyPreset(.wireless) } label: { presetLabel("Wireless interference") }
            .buttonStyle(.glass)
            .accessibilityIdentifier("sniffPresetWireless")
    }

    private func presetLabel(_ title: String) -> some View {
        Text(title).font(.caption.weight(.medium)).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4).frame(maxWidth: .infinity, minHeight: 44)
    }

    private var variablePanel: some View {
        DisclosureGroup(isExpanded: $variablesExpanded) {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Transport", selection: $config.transport) {
                    ForEach(TransportProtocol.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("sniffTransportPicker")
                Picker("Medium", selection: $config.medium) {
                    ForEach(LinkMedium.allCases) { Text($0 == .hybrid ? "Mixed" : $0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("sniffMediumPicker")
                variable("Capacity", path: \.bandwidthMbps, range: 1...1000, unit: "Mbps",
                         id: "sniffCapacitySlider", hint: "More room for bits; propagation speed stays the same.", logarithmic: true)
                variable("Packet loss", path: \.lossPct, range: 0...20, unit: "%",
                         id: "sniffLossSlider", hint: "A repeatable drop pattern for this 32-packet probe.")
                variable("Extra one-way delay", path: \.latencyMs, range: 0...200, unit: "ms",
                         id: "sniffDelaySlider", hint: "The trip out and its acknowledgment both pay delay.")
                variable("Shared capacity", path: \.congestionPct, range: 0...90, unit: "%",
                         id: "sniffSharedSlider", hint: "Other traffic uses capacity and adds modeled queue wait.")
                variable("Compression", path: \.compressionPct, range: 0...90, unit: "%",
                         id: "sniffCompressionSlider", hint: "Each source chunk shrinks; modeled CPU work precedes sending.")
                Text("Editing clears this probe and requires a fresh start. The playground's network is unchanged. A 32-packet sample need not lose exactly the percentage selected.")
                    .font(.caption)
                    .foregroundStyle(NetTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 16)
        } label: {
            Label("Degrade the network", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
        }
        .accessibilityIdentifier("snifferVariables")
        .padding(18)
        .background(NetTheme.panel, in: .rect(cornerRadius: 18))
    }

    private func variable(_ title: String, path: WritableKeyPath<NetworkConfig, Double>,
                          range: ClosedRange<Double>, unit: String, id: String,
                          hint: String, logarithmic: Bool = false) -> some View {
        let isLoss = path == \NetworkConfig.lossPct
        let precision = isLoss ? 1 : 0
        let increment = isLoss ? 0.1 : 1.0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text("\(netNumber(config[keyPath: path], digits: precision)) \(unit)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(NetTheme.modelled)
                    .accessibilityIdentifier("\(id)Value")
            }
            Slider(value: Binding(
                get: { logarithmic ? log10(config[keyPath: path]) : config[keyPath: path] },
                set: {
                    let proposed = logarithmic ? pow(10, $0) : $0
                    let accepted = (proposed / increment).rounded() * increment
                    config[keyPath: path] = min(range.upperBound, max(range.lowerBound, accepted))
                }),
                   in: logarithmic ? log10(range.lowerBound)...log10(range.upperBound) : range,
                   onEditingChanged: { editing in haptics.play(editing ? .grab : .release) })
                .accessibilityLabel(title)
                .accessibilityValue("\(netNumber(config[keyPath: path], digits: precision)) \(unit)")
                .accessibilityIdentifier(id)
            Text(hint).font(.caption).foregroundStyle(NetTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var capturePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow("Capture buffer")
                Spacer(minLength: 8)
                Text("\(displayedEvents.count) / \(visibleEvents.count) events")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(NetTheme.modelled)
            }
            Picker("Capture filter", selection: $filter) {
                Text("All").tag(CaptureFilter.all)
                Text("Trouble").tag(CaptureFilter.trouble)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("sniffFilter")
            Text("Latest event first · timestamps are modeled milliseconds")
                .font(.caption).foregroundStyle(NetTheme.muted)
            if filter == .trouble {
                Text("Drops, retries, retry limits, duplicates, and queue waits. A queue wait can be normal; it is not proof of packet loss.")
                    .font(.caption).foregroundStyle(NetTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if displayedEvents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(visibleEvents.isEmpty ? "No packets observed yet." : "No trouble observed yet.")
                        .font(.subheadline.weight(.medium))
                    Text("Start a capture, then try loss or shared capacity and compare. Each row records a hop, delivery, ACK, or retry; a data packet keeps its P01–P32 identity throughout.")
                        .font(.caption).foregroundStyle(NetTheme.muted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(displayedEvents.reversed()) { event in
                        if let packetID = event.packetID {
                            Button {
                                guard let report = capture, let packet = report.packet(id: packetID, at: elapsedMs) else { return }
                                isRunning = false
                                haptics.play(.select)
                                selection = .init(event: event, packet: packet,
                                                  observedLedger: packet.ledger,
                                                  observedWireBytes: report.observedWireBytes(at: elapsedMs, packetID: packetID))
                            } label: {
                                SnifferCaptureRow(event: event, inspectable: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("sniffCaptureRow-\(event.id)")
                            .accessibilityLabel(eventAccessibility(event))
                            .accessibilityValue("Event kind: \(event.kind.rawValue)")
                            .accessibilityHint("Pauses capture and opens the packet decoder")
                        } else {
                            SnifferCaptureRow(event: event, inspectable: false)
                                .accessibilityElement(children: .combine)
                        }
                        Divider().overlay(NetTheme.muted.opacity(0.12))
                    }
                }
            }
        }
        .padding(16)
        .background(NetTheme.screen, in: .rect(cornerRadius: 18))
    }

    private func captureControls(viewPackets: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button {
                invalidateProbe(markChanged: false)
                haptics.play(.reset)
            } label: {
                Image(systemName: "trash").frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Clear simulated capture")
            .accessibilityIdentifier("sniffClear")
            Button {
                if isRunning {
                    isRunning = false
                } else {
                    if capture == nil || complete {
                        rememberCompletedProbe()
                        capture = PacketSnifferEngine.simulate(config: config)
                        elapsedMs = 0
                        needsRestart = false
                    }
                    variablesExpanded = false
                    isRunning = true
                }
                haptics.play(.tap)
            } label: {
                Label(startTitle, systemImage: isRunning ? "pause.fill" : "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(Color(NetTheme.signature))
            .accessibilityIdentifier("sniffStart")
            Button {
                viewPackets()
                haptics.play(.tap)
            } label: {
                Image(systemName: "list.bullet.rectangle").frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .disabled(capture == nil)
            .accessibilityLabel("View live packets")
            .accessibilityHint("Scrolls to the capture buffer")
            .accessibilityIdentifier("sniffViewPackets")
            .accessibilityShowsLargeContentViewer {
                Label("View live packets", systemImage: "list.bullet.rectangle")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(NetTheme.background.opacity(0.96))
    }

    private func invalidateProbe(markChanged: Bool = true) {
        rememberCompletedProbe()
        isRunning = false
        capture = nil
        elapsedMs = 0
        needsRestart = markChanged
    }

    private func rememberCompletedProbe() {
        guard complete, let capture else { return }
        previousFinishedProbe = "\(capture.config.transport.title), \(netNumber(capture.config.lossPct, digits: 1))% loss · \(capture.deliveredCount)/32 delivered · \(capture.droppedAttempts) dropped attempts · \(capture.retryCount) retries · \(preciseTime(capture.durationMs))"
    }

    private func playCapture() async {
        guard isRunning else { return }
        var last = ContinuousClock.now
        while isRunning && !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(80)) }
            catch { return }
            guard isRunning, let capture else { return }
            let now = ContinuousClock.now
            let duration = last.duration(to: now).components
            let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            last = now
            // Visual time is scaled to 16 seconds; event labels retain true modeled time.
            elapsedMs = min(capture.durationMs, elapsedMs + min(0.25, seconds) * capture.durationMs / 16)
            if elapsedMs >= capture.durationMs {
                isRunning = false
                haptics.play(.detent)
            }
        }
    }

    private enum Conditions { case clean, busy, wireless }
    private enum CaptureFilter { case all, trouble }
    private enum CaptureScrollTarget: Hashable { case packets }

    private func applyPreset(_ preset: Conditions) {
        var next = config
        switch preset {
        case .clean:
            next.medium = .fiber
            next.bandwidthMbps = 100
            next.lossPct = 0
            next.latencyMs = 0
            next.congestionPct = 0
        case .busy:
            next.medium = .hybrid
            next.bandwidthMbps = 10
            next.lossPct = 5
            next.latencyMs = 20
            next.congestionPct = 80
        case .wireless:
            next.medium = .hybrid
            next.bandwidthMbps = 25
            next.lossPct = 15
            next.latencyMs = 35
            next.congestionPct = 40
        }
        next.compressionPct = 35
        config = next
        haptics.play(.switchClick)
    }

    private func eventAccessibility(_ event: SnifferEvent) -> String {
        "\(preciseTime(event.timeMs)), packet \(event.packetID.map(String.init) ?? "system"), \(event.kind.title), \(event.hopTitle), \(byteLabel(event.byteCount)), \(event.detail)"
    }
}

private struct SnifferCaptureRow: View {
    let event: SnifferEvent
    let inspectable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(preciseTime(event.timeMs)).foregroundStyle(NetTheme.muted)
                Text(event.packetID.map { String(format: "P%02d", $0) } ?? "SYS")
                    .foregroundStyle(Color(NetTheme.signalBlue))
                Text(event.kind.title).foregroundStyle(eventColor(event.kind))
                Spacer(minLength: 0)
                Text(byteLabel(event.byteCount)).foregroundStyle(NetTheme.packet)
            }
            .font(.system(.caption, design: .monospaced))
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 8) {
                Text(event.hopTitle).foregroundStyle(NetTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(severity(event.kind)).foregroundStyle(eventColor(event.kind))
                if inspectable {
                    Image(systemName: "chevron.right").foregroundStyle(Color(NetTheme.signalBlue))
                        .accessibilityHidden(true)
                }
            }
            .font(.system(.caption2, design: .monospaced))
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

private struct SnifferDecodeSelection: Identifiable {
    let event: SnifferEvent
    let packet: SnifferPacket
    let observedLedger: [SnifferEvent]
    let observedWireBytes: Int
    var id: Int { event.id }
}

private struct SnifferPacketDecoder: View {
    let selection: SnifferDecodeSelection
    @Environment(\.dismiss) private var dismiss

    private var packet: SnifferPacket { selection.packet }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("SIMULATED HEADER DECODE", color: NetTheme.modelled)
                        Text("\(selection.event.kind.title) · \(preciseTime(selection.event.timeMs))")
                            .font(.title3.weight(.medium)).foregroundStyle(.white)
                        Text(selection.event.detail).font(.subheadline).foregroundStyle(NetTheme.muted)
                        Text("\(selection.event.hopTitle) · \(byteLabel(selection.event.byteCount)) in this event")
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(NetTheme.modelled)
                        if selection.event.isAcknowledgment {
                            Text("This ACK refers to the data packet below. Its event byte count is separate from that data packet's illustrated header lengths.")
                                .font(.caption).foregroundStyle(NetTheme.muted)
                        }
                        if let acknowledgment = selection.event.acknowledgmentNumber {
                            Text("ACK number  \(acknowledgment)")
                                .font(.system(.caption, design: .monospaced)).foregroundStyle(NetTheme.modelled)
                        }
                        if let number = selection.event.packetNumber {
                            Text("\(selection.event.isAcknowledgment ? "Acknowledged QUIC packet number" : "QUIC packet number")  \(number)")
                                .font(.system(.caption, design: .monospaced)).foregroundStyle(NetTheme.modelled)
                        }
                    }
                    decodePanel("Associated data packet") {
                        field("Transport", packet.transport.title)
                        field("Observed state", observedState)
                        field("Source IPv4", packet.sourceAddress)
                        field("Destination IPv4", packet.destinationAddress)
                        field("IP protocol number", "\(packet.ipProtocolNumber) · \(packet.transport == .tcp ? "TCP" : "UDP")")
                        field("Source port", String(packet.sourcePort))
                        field("Destination port", String(packet.destinationPort))
                        if packet.transport == .tcp {
                            field(packet.sequenceLabel, String(packet.sequenceNumber))
                            field("Illustrative TCP flags", packet.flags)
                        } else if packet.transport == .quic {
                            field(packet.sequenceLabel, String(packet.sequenceNumber))
                            field("Teaching frame annotation", packet.flags)
                            field("Security", "QUIC packet protection · TLS-derived keys")
                        } else {
                            field(packet.sequenceLabel, String(packet.sequenceNumber))
                            field("UDP message", "Independent datagram · no UDP sequence field")
                        }
                        Text("Addresses come from documentation IPv4 ranges. These are generated teaching fields, not parsed headers. Checksums, actual encrypted bytes, and cryptography are not computed.")
                            .font(.caption).foregroundStyle(NetTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    decodePanel("Byte accounting") {
                        field("Original source chunk", byteLabel(packet.originalLength))
                        field("Compressed payload", byteLabel(packet.payloadLength))
                        field("Headers + security overhead", byteLabel(packet.headerLength))
                        field("Modeled data packet", byteLabel(packet.totalLength))
                        field("Observed hop transmissions", byteLabel(observedWireBytes))
                        Text("Lengths include modeled IPv4, transport, and applicable security overhead. Local link framing and physical coding are excluded. Observed hop bytes include repeated transmissions and associated ACK traffic; they do not count future scheduled events.")
                            .font(.caption).foregroundStyle(NetTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    decodePanel("Path") {
                        ForEach(Array(packet.path.enumerated()), id: \.offset) { index, hop in
                            Text("\(String(format: "%02d", index + 1))  \(city(hop))")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(Color(NetTheme.signalBlue))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("This is the planned synthetic path. The observed ledger below shows how far this packet has traveled.")
                            .font(.caption).foregroundStyle(NetTheme.muted)
                    }
                    decodePanel("Observed byte ledger") {
                        ForEach(selection.observedLedger) { event in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(preciseTime(event.timeMs))
                                    Text(event.kind.title)
                                    Spacer(minLength: 4)
                                    Text(byteLabel(event.byteCount))
                                }
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(eventColor(event.kind))
                                Text(event.hopTitle).font(.caption).foregroundStyle(NetTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(event.detail).font(.caption).foregroundStyle(NetTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 6)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Text("Close this decoder to return to the capture buffer.")
                        .font(.caption).foregroundStyle(NetTheme.muted)
                }
                .padding(20)
                .frame(maxWidth: 780)
                .frame(maxWidth: .infinity)
            }
            .background(NetTheme.background.ignoresSafeArea())
            .navigationTitle(String(format: "Packet P%02d", packet.id))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("snifferDecodeDone")
                }
            }
        }
        .tint(Color(NetTheme.signalBlue))
    }

    private var observedState: String {
        if selection.event.kind == .exhausted && !packet.acknowledged {
            return packet.delivered ? "Delivered · sender unconfirmed" : "Unconfirmed · not delivered to application"
        }
        return packet.status
    }

    private var observedWireBytes: Int {
        selection.observedWireBytes
    }

    private func field(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption).foregroundStyle(NetTheme.muted)
            Text(value).font(.system(.subheadline, design: .monospaced)).foregroundStyle(NetTheme.packet)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private func decodePanel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).foregroundStyle(.white).accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(NetTheme.panel, in: .rect(cornerRadius: 18))
    }
}

private func preciseTime(_ milliseconds: Double) -> String {
    "\(milliseconds.formatted(.number.precision(.fractionLength(3)))) ms"
}

private func byteLabel(_ bytes: Int) -> String { "\(bytes.formatted()) B" }

private func city(_ id: String) -> String { NetworkEngine.nodes.first { $0.id == id }?.city ?? id }

private func eventColor(_ kind: SnifferEventKind) -> Color {
    switch kind {
    case .drop, .exhausted: NetTheme.danger
    case .retry, .duplicate: NetTheme.modelled
    case .deliver: Color(NetTheme.signalBlue)
    case .queued, .ack, .setup, .compress, .complete: NetTheme.muted
    case .transmit, .arrive: NetTheme.packet
    }
}

private func severity(_ kind: SnifferEventKind) -> String {
    switch kind {
    case .drop: "DROP"
    case .exhausted: "LIMIT"
    case .retry: "RECOVERY"
    case .duplicate: "DUPLICATE"
    case .queued: "WAIT"
    case .deliver: "OK"
    case .complete: "END"
    case .ack: "ACK"
    default: "INFO"
    }
}
