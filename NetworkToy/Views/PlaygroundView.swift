import SwiftUI
import LabKitCore
import LabKitUI
import LabKitFeedback

private enum PlaygroundSheet: String, Identifiable {
    case tune, trace, guide, experiments, archive, sniffer
    var id: String { rawValue }
}

struct PlaygroundView: View {
    let haptics: HapticEngine
    @State private var model = NetworkStore()
    @State private var sheet: PlaygroundSheet?
    @State private var showBabyBells = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    header.padding(.horizontal, 20).padding(.top, 8)
                    if typeSize.isAccessibilitySize { heading.padding(.horizontal, 24).padding(.top, 16) }
                    routePicker.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 14)
                    networkDisplay(availableHeight: geometry.size.height).padding(.horizontal, 16).padding(.bottom, 14)
                    transportPicker.padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) { actionDock }
        }
        .background { BellConsoleBackground() }
        .preferredColorScheme(.dark)
        .tint(Color(NetTheme.signalBlue))
        .sheet(item: $sheet) { destination in
            Group {
                switch destination {
                case .tune: TuningSheet(model: model, haptics: haptics)
                case .trace: PacketTraceSheet(model: model)
                case .guide: ProtocolGuide()
                case .experiments: ExperimentSheet(model: model, haptics: haptics)
                case .archive: BellArchiveSheet(isEasterEggActive: $showBabyBells, haptics: haptics)
                case .sniffer: PacketSnifferSheet(config: model.config, haptics: haptics)
                }
            }
            .labPalette(NetTheme.palette)
            .labHaptics(haptics)
            .tint(Color(NetTheme.signalBlue))
            .presentationDetents(destination == .guide || destination == .archive || destination == .sniffer ? [.large] : [.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { haptics.stop(); return }
            haptics.start()
            var last = ContinuousClock.now
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(model.isRunning ? (reduceMotion ? 120 : 33) : 200)) }
                catch { break }
                let now = ContinuousClock.now
                let duration = last.duration(to: now).components
                let delta = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
                model.tick(seconds: min(0.25, delta))
                last = now
            }
        }
        .onChange(of: model.complete) { _, completed in
            if completed { haptics.play(.detent) }
        }
        .onDisappear { haptics.stop() }
    }

    private func globeHeight(_ available: CGFloat) -> CGFloat {
        if typeSize.isAccessibilitySize { return 290 }
        return min(245, max(215, available * 0.25))
    }

    private var header: some View {
        LabTopBar {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    BellStripeMark().fill(Color(NetTheme.signalBlue)).frame(width: 28, height: 28)
                        .shadow(color: NetTheme.globe.opacity(0.55), radius: 5)
                        .accessibilityHidden(true)
                    Text("SnoopyNet").font(.system(.title3).weight(.bold)).tracking(-0.4)
                        .foregroundStyle(NetTheme.ink)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Button {
                        showBabyBells = true; open(.archive)
                    } label: {
                        Text("1984").font(.system(.caption2, design: .monospaced).weight(.bold))
                            .foregroundStyle(Color(NetTheme.signalBlue))
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .overlay(Rectangle().stroke(Color(NetTheme.signalBlue).opacity(0.65), lineWidth: 1))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }.buttonStyle(.plain).accessibilityLabel("Open the Bell Labs archive")
                        .accessibilityHint("Reveals the seven Baby Bells")
                        .accessibilityIdentifier("bellLabsSeal")
                }
                Text("AT&T / BELL LABS · NETWORK RESEARCH")
                    .font(.system(size: 8, design: .monospaced).weight(.medium)).tracking(0.7)
                    .foregroundStyle(NetTheme.paperMuted).lineLimit(1).minimumScaleFactor(0.8)
            }.padding(.leading, 4).frame(minHeight: 56)
        } actions: {
            Button { open(.experiments) } label: { ToolbarGlyph("flask", title: "Experiments", tint: NetTheme.signalBlue) }
                .accessibilityLabel("Experiments").accessibilityIdentifier("experiments")
            Button { open(.guide) } label: { ToolbarGlyph("info", title: "Inside the internet", tint: NetTheme.signalBlue) }
                .accessibilityLabel("Inside the internet").accessibilityIdentifier("guide")
        }
    }

    private var heading: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Eyebrow("A network playground", color: NetTheme.paperMuted)
                Text("Internet, in motion.")
                    .font(.system(.title2, design: .rounded).weight(.medium))
                    .foregroundStyle(NetTheme.ink)
            }
            Spacer(minLength: 4)
            Text("MODEL").font(LabFont.eyebrow).tracking(1)
                .foregroundStyle(Color(NetTheme.signalBlue)).padding(.bottom, 4)
                .accessibilityLabel("Offline educational model")
        }
    }

    private var routePicker: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 10) {
                nodeMenu(isSource: true)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(NetTheme.paperMuted)
                    .accessibilityHidden(true)
                nodeMenu(isSource: false)
            }
        }
    }

    private func nodeMenu(isSource: Bool) -> some View {
        let id = isSource ? model.config.sourceID : model.config.destinationID
        let node = NetworkEngine.nodes.first { $0.id == id }
        return Menu {
            ForEach(NetworkEngine.nodes.filter { $0.id != (isSource ? model.config.destinationID : model.config.sourceID) }) { candidate in
                Button(candidate.city) {
                    haptics.play(.select)
                    if isSource { model.config.sourceID = candidate.id }
                    else { model.config.destinationID = candidate.id }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Color(NetTheme.signalBlue)).frame(width: 5, height: 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isSource ? "FROM" : "TO").font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(NetTheme.paperMuted)
                    Text(node?.city ?? id).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(NetTheme.ink)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.caption2).foregroundStyle(Color(NetTheme.signalBlue))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(NetTheme.paperPanel, in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(NetTheme.ink.opacity(0.14), lineWidth: 1))
        }
        .accessibilityLabel("\(isSource ? "Source" : "Destination"), \(node?.city ?? id)")
        .accessibilityIdentifier(isSource ? "sourcePicker" : "destinationPicker")
    }

    private var globe: some View {
        NetworkGlobe(nodes: NetworkEngine.nodes, route: model.metrics.route,
            packets: model.renderedPackets, sourceID: model.config.sourceID,
            destinationID: model.config.destinationID, isRunning: model.isRunning,
            isEasterEggActive: showBabyBells) { id in
                haptics.play(.poke); model.chooseNode(id)
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 16) {
                    legend("Fiber", color: NetTheme.fiber, dashed: false)
                    legend("Wireless", color: NetTheme.wireless, dashed: true)
                    Text("DRAG TO ORBIT").font(.system(size: 8, design: .monospaced))
                        .tracking(1).foregroundStyle(NetTheme.muted)
                }.padding(.bottom, 12).accessibilityHidden(true)
            }
    }

    private func networkDisplay(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(showBabyBells ? "LONG LINES / FAMILY PLAN" : "LONG LINES / GLOBAL NETWORK")
                    .font(.system(size: 9, design: .monospaced)).tracking(0.8)
                    .foregroundStyle(NetTheme.screenMuted)
                Spacer(minLength: 4)
                Text("MODEL").font(.system(size: 9, design: .monospaced).weight(.bold))
                    .foregroundStyle(NetTheme.modelled)
                    .accessibilityLabel("Offline educational model")
            }.padding(.horizontal, 14).padding(.top, 12)
            globe.frame(height: globeHeight(availableHeight))
            readouts.padding(.horizontal, 16).padding(.bottom, 16)
        }
        .background(NetTheme.screen, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(NetTheme.globe.opacity(0.30), lineWidth: 1))
        .shadow(color: NetTheme.globe.opacity(0.10), radius: 18)
        .overlay(alignment: .bottomTrailing) {
            Text("SN-84").font(.system(size: 6, design: .monospaced)).foregroundStyle(NetTheme.screenMuted)
                .padding(.trailing, 8).padding(.bottom, 4).accessibilityHidden(true)
        }
    }

    private func legend(_ title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: 16, y: 0)) }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 2] : []))
                .frame(width: 16, height: 1)
            Text(title).font(.system(size: 9, design: .monospaced)).foregroundStyle(NetTheme.muted)
        }
    }

    private var readouts: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { readoutItems }
            } else {
                HStack(alignment: .top, spacing: 12) { readoutItems }
            }
        }
    }

    @ViewBuilder private var readoutItems: some View {
            readout("ROUND TRIP", value: netTime(model.metrics.rttMs)).accessibilityIdentifier("roundTripReadout")
            readout("GOODPUT", value: "\(netNumber(model.metrics.goodputMbps, digits: 1)) Mb/s")
            readout("PAYLOAD", value: "\(netNumber(model.metrics.compressedBytes / 1e6, digits: 2)) MB")
    }

    private func readout(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(.caption2, design: .monospaced)).tracking(1).foregroundStyle(NetTheme.muted)
            Text(value).font(LabFont.readoutValue).foregroundStyle(NetTheme.modelled)
                .shadow(color: NetTheme.globe.opacity(0.35), radius: 4)
                .lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }

    private var transportPicker: some View {
        VStack(spacing: 12) {
            Picker("Link medium", selection: Binding(get: { model.config.medium }, set: { model.setMedium($0); haptics.play(.switchClick) })) {
                ForEach(LinkMedium.allCases) { medium in Text(medium == .hybrid ? "Mixed" : medium.title).tag(medium) }
            }.pickerStyle(.segmented).accessibilityIdentifier("mediumPicker")
            HStack(spacing: 8) {
                ForEach(TransportProtocol.allCases) { transport in
                    Button {
                        model.config.transport = transport; haptics.play(.switchClick)
                    } label: {
                        Text(transport.title).font(.caption.weight(.semibold))
                            .foregroundStyle(model.config.transport == transport ? Color(NetTheme.signalBlue) : NetTheme.paperMuted)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(model.config.transport == transport ? NetTheme.paperPanel : .clear,
                                in: .rect(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(model.config.transport == transport ? Color(NetTheme.signalBlue).opacity(0.7) : NetTheme.ink.opacity(0.15)))
                    }.buttonStyle(.plain).accessibilityIdentifier("protocol-\(transport.rawValue)")
                        .accessibilityAddTraits(model.config.transport == transport ? .isSelected : [])
                }
            }
        }
    }

    private var knobDeck: some View {
        GlassEffectContainer(spacing: LabMetrics.Console.glassSpacing) {
            HStack(spacing: 4) {
                GlassKnob(spec: NetTheme.bandwidth, value: binding(\.bandwidthMbps), onPrecision: { open(.tune) })
                GlassKnob(spec: NetTheme.loss, value: binding(\.lossPct), onPrecision: { open(.tune) })
                GlassKnob(spec: NetTheme.compression, value: binding(\.compressionPct), onPrecision: { open(.tune) })
            }
        }.dynamicTypeSize(...LabMetrics.stageChromeTypeCap)
    }

    private var actionDock: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                BellScrew()
                Text("TRANSMISSION CONTROL").font(.system(size: 9, design: .monospaced).weight(.semibold)).tracking(0.8)
                Spacer()
                Text("OPERATOR: YOU").font(.system(size: 8, design: .monospaced))
                BellScrew()
            }.foregroundStyle(NetTheme.paperMuted).padding(.horizontal, 22).padding(.top, 10)
            VStack(spacing: 2) {
            Button { open(.trace) } label: {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Circle().fill(model.isRunning ? NetTheme.fiber : NetTheme.modelled).frame(width: 5, height: 5)
                        Text(model.phaseTitle).font(.caption.weight(.medium)).foregroundStyle(.white)
                        Spacer()
                        Text(model.hasRun ? "\(netNumber(model.progress * 100))%" : netTime(model.metrics.totalMs))
                            .font(.caption.monospacedDigit()).foregroundStyle(NetTheme.modelled)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(NetTheme.muted)
                    }
                    ProgressView(value: model.progress).tint(NetTheme.fiber)
                }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
                    .frame(minHeight: LabMetrics.minHit)
                    .contentShape(.rect)
            }.buttonStyle(.plain).accessibilityIdentifier("packetTrace")
                .accessibilityLabel("Packet journey. \(model.phaseTitle). Inspect trace")
            knobDeck.padding(.horizontal, 2).padding(.bottom, 6)
            }.background(NetTheme.screen, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(NetTheme.globe.opacity(0.22), lineWidth: 1))
                .padding(.horizontal, 16)
            runControls
        }
        .background(NetTheme.paper.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(NetTheme.ink.opacity(0.18)).frame(height: 1) }
    }

    private var runControls: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 10) {
                Button { model.reset(); haptics.play(.reset) } label: {
                    Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
                }.buttonStyle(.glass).foregroundStyle(NetTheme.ink)
                    .accessibilityLabel("Reset transfer").accessibilityIdentifier("reset")
                Button {
                    model.toggleRun(); haptics.play(.tap)
                } label: {
                    Label(compactRunTitle, systemImage: model.isRunning ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.glassProminent).tint(Color(NetTheme.signature)).accessibilityIdentifier("send")
                    .accessibilityLabel(runTitle)
                    .accessibilityValue(model.isRunning ? "running" : model.complete ? "complete" : model.hasRun ? "paused" : "ready")
                Button { open(.sniffer) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "waveform.path.ecg").font(.body)
                        Text("Sniff packets").font(.system(size: 9, design: .monospaced).weight(.medium)).lineLimit(1)
                    }.frame(minWidth: 68, minHeight: 44)
                }.buttonStyle(.glass).foregroundStyle(NetTheme.ink)
                    .accessibilityLabel("Sniff packets").accessibilityIdentifier("sniff")
                Button { open(.tune) } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                }.buttonStyle(.glass).foregroundStyle(NetTheme.ink)
                    .accessibilityLabel("Tune network").accessibilityIdentifier("tune")
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }

    private var runTitle: String {
        if model.isRunning { return "Pause transfer" }
        if model.complete { return "Send again" }
        return model.hasRun ? "Resume transfer" : "Send a packet burst"
    }

    private var compactRunTitle: String {
        if model.isRunning { return "Pause" }
        if model.complete { return "Send again" }
        return model.hasRun ? "Resume" : "Send burst"
    }

    private func binding(_ path: WritableKeyPath<NetworkConfig, Double>) -> Binding<Double> {
        Binding(get: { model.config[keyPath: path] }, set: { model.config[keyPath: path] = $0 })
    }

    private func open(_ target: PlaygroundSheet) { haptics.play(.tap); sheet = target }
}
