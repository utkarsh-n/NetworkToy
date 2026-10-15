import Foundation

// A deterministic teaching model, not a measurement or a full protocol stack.
// Units: decimal MB and Mbps, milliseconds, kilometers, percentages in 0...100.
// One bottleneck serializes the transfer; packets pipeline across other links.
// Loss is an end-to-end probability, not independently reapplied at every hop.
// Representative particles are visual samples, not one particle per IP packet.
// Sources: RFC 9293 (TCP), RFC 768 / 8085 (UDP), RFC 9000 / 9002 (QUIC),
// RFC 8446 (TLS 1.3), RFC 9110 (HTTP content compression).
// https://www.rfc-editor.org/rfc/rfc9293.html
// https://www.rfc-editor.org/rfc/rfc8085.html
// https://www.rfc-editor.org/rfc/rfc9000.html
// https://www.rfc-editor.org/rfc/rfc9002.html
// https://www.rfc-editor.org/rfc/rfc8446.html
// https://www.rfc-editor.org/rfc/rfc9110.html

enum LinkMedium: String, CaseIterable, Identifiable, Sendable {
    case fiber, wireless, hybrid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fiber: "Fiber"
        case .wireless: "Wireless"
        case .hybrid: "Hybrid"
        }
    }
    var detail: String {
        switch self {
        case .fiber: "Light through fiber, with a modeled cable path and 200,000 km/s propagation."
        case .wireless: "An abstract radio/space relay network. Long globe arcs do not represent ordinary Wi-Fi range."
        case .hybrid: "A wireless local access link feeds the fiber backbone."
        }
    }
}

enum TransportProtocol: String, CaseIterable, Identifiable, Sendable {
    case tcp, udp, quic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tcp: "TCP"
        case .udp: "UDP"
        case .quic: "QUIC"
        }
    }
    var detail: String {
        switch self {
        case .tcp: "Reliable, ordered bytes. This example adds a separate TLS 1.3 handshake."
        case .udp: "Independent datagrams. No built-in handshake, encryption, acknowledgment, or retransmission."
        case .quic: "Reliable streams over UDP. Transport and TLS setup are combined; lost data is recovered."
        }
    }
    var isReliable: Bool { self != .udp }
}

struct NetworkNode: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let city: String
    let latitude: Double
    let longitude: Double
    let role: String
}

struct NetworkConfig: Equatable, Sendable {
    var sourceID = "san-francisco"
    var destinationID = "london"
    var medium: LinkMedium = .hybrid
    var transport: TransportProtocol = .quic
    var bandwidthMbps = 100.0
    var latencyMs = 0.0
    var lossPct = 0.0
    var compressionPct = 35.0
    var payloadMB = 5.0
    var congestionPct = 0.0
    static let `default` = NetworkConfig()
}

struct NetworkRouteSegment: Equatable, Sendable {
    let from: String
    let to: String
    let medium: LinkMedium
    let distanceKm: Double
    let propagationMs: Double
}

struct NetworkPhase: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let detail: String
    let startMs: Double
    let endMs: Double
    let durationMs: Double
}

struct NetworkMetrics: Equatable, Sendable {
    let route: [NetworkRouteSegment]
    let routeNodes: [NetworkNode]
    let distanceKm: Double
    let oneWayMs: Double
    let rttMs: Double
    let payloadBytes: Double
    let compressedBytes: Double
    let packetCount: Int
    let expectedRetransmissions: Double
    let deliveredPct: Double
    let effectiveMbps: Double
    let transferMs: Double
    let totalMs: Double
    let phases: [NetworkPhase]

    // Extra detail for inspectable explanations. These are modeled values.
    let config: NetworkConfig
    let propagationMs: Double
    let queueMs: Double
    let serializationMs: Double
    let compressionMs: Double
    let decompressionMs: Double
    let lossRecoveryMs: Double
    // Data-direction IP bytes including modeled headers/retries. Setup, ACK,
    // link-layer framing and TLS record overhead are not included in this sum.
    let wireBytes: Double
    // UDP assumes independently usable application chunks. A monolithic file
    // could be unusable after even one lost datagram; delivery is not file success.
    let deliveredBytes: Double
    let headerBytes: Double
    var savedBytes: Double { payloadBytes - compressedBytes }
    var goodputMbps: Double { deliveredBytes * 8 / max(totalMs, 0.001) / 1_000 }
}

enum PacketKind: String, Sendable {
    case data, ack, lost, retry
}

struct NetworkPacket: Identifiable, Equatable, Sendable {
    let id: Int
    // A position along the whole route: 0 is source, 1 is destination.
    // ACKs move from 1 back to 0. Lost particles stop before the destination.
    let progress: Double
    let kind: PacketKind
    let sizeBytes: Double
}

struct NetworkEvent: Identifiable, Equatable, Sendable {
    let id: Int
    let timeMs: Double
    let type: String
    let label: String
    let detail: String
}

struct NetworkState: Equatable, Sendable {
    let elapsedMs: Double
    let totalMs: Double
    let progress: Double
    let phase: String
    let phaseLabel: String
    let complete: Bool
    let metrics: NetworkMetrics
    let packets: [NetworkPacket]
    let events: [NetworkEvent]
}

enum NetworkEngine {
    static let nodes: [NetworkNode] = [
        .init(id: "san-francisco", label: "SFO", city: "San Francisco", latitude: 37.77, longitude: -122.42, role: "Client / edge"),
        .init(id: "los-angeles", label: "LAX", city: "Los Angeles", latitude: 34.05, longitude: -118.24, role: "Cable gateway"),
        .init(id: "honolulu", label: "HNL", city: "Honolulu", latitude: 21.31, longitude: -157.86, role: "Pacific relay"),
        .init(id: "tokyo", label: "TYO", city: "Tokyo", latitude: 35.68, longitude: 139.69, role: "Server / exchange"),
        .init(id: "new-york", label: "NYC", city: "New York", latitude: 40.71, longitude: -74.01, role: "Atlantic gateway"),
        .init(id: "london", label: "LHR", city: "London", latitude: 51.51, longitude: -0.13, role: "Internet exchange"),
        .init(id: "frankfurt", label: "FRA", city: "Frankfurt", latitude: 50.11, longitude: 8.68, role: "Internet exchange"),
        .init(id: "mumbai", label: "BOM", city: "Mumbai", latitude: 19.08, longitude: 72.88, role: "Cable gateway"),
        .init(id: "singapore", label: "SIN", city: "Singapore", latitude: 1.35, longitude: 103.82, role: "Asia exchange"),
        .init(id: "sydney", label: "SYD", city: "Sydney", latitude: -33.87, longitude: 151.21, role: "Server / exchange")
    ]

    // Fictional teaching topology, not a map of named providers or live cables.
    static let backboneLinks: [(String, String)] = [
        ("san-francisco", "los-angeles"), ("san-francisco", "new-york"),
        ("los-angeles", "honolulu"), ("honolulu", "tokyo"),
        ("new-york", "london"), ("london", "frankfurt"),
        ("frankfurt", "mumbai"), ("mumbai", "singapore"),
        ("singapore", "tokyo"), ("singapore", "sydney"), ("tokyo", "sydney")
    ]

    static func calculate(_ configuration: NetworkConfig) -> NetworkMetrics {
        let config = normalized(configuration)
        let path = routeNodeIDs(from: config.sourceID, to: config.destinationID)
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let routeNodes = path.compactMap { nodeMap[$0] }
        let route = zip(routeNodes, routeNodes.dropFirst()).enumerated().map { index, pair in
            let straight = greatCircleDistance(pair.0, pair.1)
            let medium: LinkMedium = config.medium == .hybrid ? .fiber : config.medium
            // In hybrid mode the first link contains a 5 km wireless access tail,
            // followed by fiber. It is marked hybrid so the globe can draw both.
            let isHybridAccess = config.medium == .hybrid && index == 0
            let cableKm = straight * 1.22
            let airKm = straight * 1.04
            let distance = medium == .wireless ? airKm : cableKm
            let travelMs: Double
            if isHybridAccess {
                travelMs = max(0, distance - 5) / 200_000 * 1_000 + min(5, distance) / 300_000 * 1_000
            } else {
                travelMs = distance / (medium == .wireless ? 300_000 : 200_000) * 1_000
            }
            return NetworkRouteSegment(from: pair.0.id, to: pair.1.id,
                                       medium: isHybridAccess ? .hybrid : medium,
                                       distanceKm: distance, propagationMs: travelMs)
        }
        let distanceKm = route.reduce(0) { $0 + $1.distanceKm }
        let propagationMs = route.reduce(0) { $0 + $1.propagationMs }
        let congestion = config.congestionPct / 100
        // Shared capacity plus a small queue that increases nonlinearly as full.
        let queueMs = Double(route.count) * 2 * congestion / max(0.1, 1 - congestion)
        let radioAccessMs: Double = config.medium == .fiber ? 0 : (config.medium == .hybrid ? 3 : 8)
        let oneWayMs = propagationMs + config.latencyMs + queueMs + radioAccessMs
        let rttMs = 2 * oneWayMs
        let mediumEfficiency: Double
        switch config.medium {
        case .fiber: mediumEfficiency = 0.96
        case .wireless: mediumEfficiency = 0.65
        case .hybrid: mediumEfficiency = 0.82
        }
        let effectiveMbps = config.bandwidthMbps * mediumEfficiency * (1 - congestion)
        let payloadBytes = config.payloadMB * 1_000_000
        let compression = config.compressionPct / 100
        let compressedBytes = payloadBytes * (1 - compression)
        let packetPayload: Double = config.transport == .tcp ? 1_460 : 1_200
        let packetCount = Int(ceil(compressedBytes / packetPayload))
        let perPacketHeader: Double
        switch config.transport {
        case .tcp: perPacketHeader = 40
        case .udp: perPacketHeader = 28
        case .quic: perPacketHeader = 48
        }
        let headerBytes = Double(packetCount) * perPacketHeader
        let loss = config.lossPct / 100
        let expectedRetransmissions = config.transport.isReliable ? Double(packetCount) * loss / (1 - loss) : 0
        let retryMultiplier = config.transport.isReliable ? 1 / (1 - loss) : 1
        let wireBytes = (compressedBytes + headerBytes) * retryMultiplier
        let serializationMs = wireBytes * 8 / (effectiveMbps * 1_000)
        // CPU costs are explicit teaching assumptions, not a gzip benchmark.
        // At high bandwidth, compression may cost more CPU time than it saves.
        let compressionMs = config.payloadMB * 28 * compression * compression
        let decompressionMs = config.payloadMB * 2 * compression
        // Both reliable transports recover loss. This single-stream model does
        // not claim QUIC is immune to loss or implement Reno/CUBIC/BBR.
        let probabilityOfAnyLoss = 1 - pow(1 - loss, Double(packetCount))
        let lossRecoveryMs = config.transport.isReliable
            ? rttMs * (1 + 2 * sqrt(loss)) * probabilityOfAnyLoss : 0
        let transferMs = serializationMs + oneWayMs + lossRecoveryMs
        let deliveredPct = config.transport.isReliable ? 100.0 : 100 * (1 - loss)
        let deliveredBytes = payloadBytes * deliveredPct / 100
        var phases: [NetworkPhase] = []
        var cursor = 0.0
        func appendPhase(_ id: String, _ label: String, _ detail: String, _ duration: Double) {
            guard duration > 0 else { return }
            phases.append(.init(id: id, label: label, detail: detail, startMs: cursor,
                                endMs: cursor + duration, durationMs: duration))
            cursor += duration
        }
        // A DNS lookup uses a nearby resolver, not an entire destination RTT.
        appendPhase("dns", "Resolve DNS", "A nearby resolver translates the server name into an IP address. One fresh lookup is modeled at 25 ms.", 25)
        if config.transport == .tcp {
            appendPhase("tcp", "Connect TCP", "SYN, SYN-ACK, ACK establish a fresh reliable connection: approximately one round trip.", rttMs)
            appendPhase("tls", "Secure with TLS", "TLS 1.3 authenticates the server and establishes encryption keys: one additional round trip in this example.", rttMs)
        } else if config.transport == .quic {
            appendPhase("quic", "Connect + secure", "QUIC combines transport and TLS setup into one round trip for a fresh connection. No 0-RTT resumption is assumed.", rttMs)
        }
        appendPhase("compress", "Compress payload", "Content compression reduces application bytes before packetization. CPU effort is a modeled tradeoff; the chosen ratio is assumed achievable.", compressionMs)
        appendPhase("transfer", "Move packets", config.transport == .udp
                    ? "Datagrams cross a pipelined route. Lost datagrams are not recovered by UDP itself."
                    : "Packets pipeline through routers. Acknowledgments detect loss and missing data is sent again.", transferMs)
        appendPhase("decompress", "Unpack payload", config.transport == .udp
                    ? "The receiver decodes independently usable chunks. A file compressed as one stream may be unusable after any loss."
                    : "The receiver decodes the compressed content. Real compression results depend on the data.", decompressionMs)
        if config.transport.isReliable {
            appendPhase("ack", "Confirm delivery", "The final acknowledgment returns to the sender. This toy models eventual recovery for every missing byte.", oneWayMs)
        }
        return .init(route: route, routeNodes: routeNodes, distanceKm: distanceKm,
                     oneWayMs: oneWayMs, rttMs: rttMs, payloadBytes: payloadBytes,
                     compressedBytes: compressedBytes, packetCount: packetCount,
                     expectedRetransmissions: expectedRetransmissions, deliveredPct: deliveredPct,
                     effectiveMbps: effectiveMbps, transferMs: transferMs, totalMs: cursor,
                     phases: phases, config: config, propagationMs: propagationMs,
                     queueMs: queueMs, serializationMs: serializationMs,
                     compressionMs: compressionMs, decompressionMs: decompressionMs,
                     lossRecoveryMs: lossRecoveryMs, wireBytes: wireBytes,
                     deliveredBytes: deliveredBytes, headerBytes: headerBytes)
    }

    static func normalized(_ input: NetworkConfig) -> NetworkConfig {
        var config = input
        let ids = Set(nodes.map(\.id))
        if !ids.contains(config.sourceID) { config.sourceID = NetworkConfig.default.sourceID }
        if !ids.contains(config.destinationID) { config.destinationID = NetworkConfig.default.destinationID }
        // Keep this toy an internet journey, even if both pickers select a city.
        if config.sourceID == config.destinationID {
            config.destinationID = config.sourceID == "tokyo" ? "san-francisco" : "tokyo"
        }
        config.bandwidthMbps = clamp(config.bandwidthMbps, 1, 1_000, fallback: 100)
        config.latencyMs = clamp(config.latencyMs, 0, 200, fallback: 0)
        config.lossPct = clamp(config.lossPct, 0, 20, fallback: 0)
        config.compressionPct = clamp(config.compressionPct, 0, 90, fallback: 35)
        config.payloadMB = clamp(config.payloadMB, 2, 50, fallback: 5)
        config.congestionPct = clamp(config.congestionPct, 0, 90, fallback: 0)
        return config
    }

    static func greatCircleDistance(_ first: NetworkNode, _ second: NetworkNode) -> Double {
        let radians = Double.pi / 180
        let a = first.latitude * radians
        let b = second.latitude * radians
        let lat = (second.latitude - first.latitude) * radians
        let lon = (second.longitude - first.longitude) * radians
        let h = pow(sin(lat / 2), 2) + cos(a) * cos(b) * pow(sin(lon / 2), 2)
        return 6_371 * 2 * asin(sqrt(min(1, max(0, h))))
    }

    private static func routeNodeIDs(from source: String, to destination: String) -> [String] {
        let lookup = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var costs = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, Double.infinity) })
        var previous: [String: String] = [:]
        var remaining = Set(nodes.map(\.id))
        costs[source] = 0
        while !remaining.isEmpty {
            // Sorting breaks ties consistently, independent of Set iteration.
            guard let current = remaining.sorted().min(by: { costs[$0, default: .infinity] < costs[$1, default: .infinity] }) else { break }
            remaining.remove(current)
            if current == destination { break }
            for (first, second) in backboneLinks {
                let next: String
                if first == current { next = second }
                else if second == current { next = first }
                else { continue }
                guard remaining.contains(next), let a = lookup[current], let b = lookup[next] else { continue }
                let candidate = costs[current, default: .infinity] + greatCircleDistance(a, b)
                if candidate < costs[next, default: .infinity] {
                    costs[next] = candidate
                    previous[next] = current
                }
            }
        }
        var path = [destination]
        while let parent = previous[path[0]] { path.insert(parent, at: 0) }
        return path.first == source ? path : [source, destination]
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double, fallback: Double) -> Double {
        value.isFinite ? min(high, max(low, value)) : fallback
    }
}

// Call advance with MODEL milliseconds. The UI may scale animation time, but
// must label displayed duration as simulated time. Pause by not calling advance.
// State is computed from elapsed time, so seeking in uniform or varied steps
// yields the same packet positions and event history.
struct NetworkSimulation: Sendable {
    let metrics: NetworkMetrics
    private(set) var elapsedMs = 0.0
    private let scheduledEvents: [NetworkEvent]

    init(config: NetworkConfig = .default) {
        let metrics = NetworkEngine.calculate(config)
        self.metrics = metrics
        self.scheduledEvents = Self.makeEvents(metrics)
    }

    @discardableResult
    mutating func advance(_ deltaMs: Double) -> NetworkState {
        if deltaMs.isFinite && deltaMs > 0 { elapsedMs = min(metrics.totalMs, elapsedMs + deltaMs) }
        return state
    }

    var state: NetworkState {
        let complete = elapsedMs >= metrics.totalMs
        let phase = metrics.phases.first { elapsedMs < $0.endMs } ?? metrics.phases.last!
        return .init(elapsedMs: elapsedMs, totalMs: metrics.totalMs,
                     progress: min(1, elapsedMs / metrics.totalMs),
                     phase: complete ? "complete" : phase.id,
                     phaseLabel: complete ? "Transfer complete" : phase.label,
                     complete: complete, metrics: metrics,
                     packets: complete ? [] : packets(at: elapsedMs),
                     events: scheduledEvents.filter { $0.timeMs <= elapsedMs })
    }

    // A presentation-only sample. A UI fitting a long transfer into a few
    // seconds can keep symbolic dots visible without changing any metrics,
    // numerical state, event timestamps, or physical state.packets positions.
    func visualPackets(minimumFlightMs: Double) -> [NetworkPacket] {
        guard elapsedMs < metrics.totalMs else { return [] }
        return packets(at: elapsedMs, minimumFlightMs: minimumFlightMs)
    }

    private func packets(at time: Double, minimumFlightMs: Double = 0) -> [NetworkPacket] {
        var visible: [NetworkPacket] = []
        let reliable = metrics.config.transport.isReliable
        let physicalTravel = max(0.5, metrics.oneWayMs)
        let visualMinimum = minimumFlightMs.isFinite ? max(0, minimumFlightMs) : 0
        guard let transfer = metrics.phases.first(where: { $0.id == "transfer" }) else { return [] }
        let travel = visualMinimum > 0
            ? min(max(physicalTravel, visualMinimum), transfer.durationMs - metrics.lossRecoveryMs)
            : physicalTravel
        // Setup messages travel over the route, with ACKs returning in reverse.
        for phase in metrics.phases where ["tcp", "tls", "quic"].contains(phase.id) {
            if time >= phase.startMs && time <= phase.endMs {
                let local = time - phase.startMs
                let id = metrics.phases.firstIndex(of: phase)! * 1_000
                let setupTravel = visualMinimum > 0 ? min(max(physicalTravel, visualMinimum), phase.durationMs / 2) : physicalTravel
                if local <= setupTravel {
                    visible.append(.init(id: id, progress: min(1, local / setupTravel), kind: .data, sizeBytes: 64))
                } else {
                    visible.append(.init(id: id + 1, progress: max(0, 1 - (local - setupTravel) / setupTravel), kind: .ack, sizeBytes: 40))
                }
            }
        }
        // The number of symbolic batches follows the compressed byte fraction:
        // fewer bytes produce visibly fewer dots, with a small visibility floor.
        let byteFraction = metrics.compressedBytes / metrics.payloadBytes
        let sampleCount = min(48, max(6, Int(ceil(48 * byteFraction))))
        let lostCount = metrics.config.lossPct > 0 ? max(1, Int((Double(sampleCount) * metrics.config.lossPct / 100).rounded())) : 0
        // Keep stretched data flights and any retry flight inside the transfer
        // phase. The default numerical sampling keeps its original schedule.
        let launchWindow = visualMinimum > 0
            ? min(metrics.serializationMs, max(0, transfer.durationMs - travel - metrics.lossRecoveryMs))
            : max(0.5, metrics.serializationMs)
        let sampleSize = metrics.compressedBytes / Double(sampleCount)
        // 17 is coprime with every allowed count except its multiples. For those
        // counts, 19 preserves a permutation so no sample ranks are duplicated.
        let lossStride = sampleCount.isMultiple(of: 17) ? 19 : 17
        for index in 0..<sampleCount {
            let launch = transfer.startMs + Double(index) / Double(sampleCount - 1) * launchWindow
            let age = time - launch
            // A coprime permutation scatters missing samples deterministically.
            let isLost = (index * lossStride + 11) % sampleCount < lostCount
            let lossPosition = 0.3 + Double((index * 11) % 7) / 10
            if age >= 0 && age <= travel {
                let progress = age / travel
                if isLost {
                    if progress <= lossPosition + 0.12 {
                        visible.append(.init(id: 10_000 + index, progress: min(progress, lossPosition),
                                             kind: .lost, sizeBytes: sampleSize))
                    }
                } else {
                    visible.append(.init(id: 10_000 + index, progress: progress, kind: .data, sizeBytes: sampleSize))
                }
            }
            if reliable && isLost {
                let retryLaunch = launch + metrics.lossRecoveryMs
                let retryAge = time - retryLaunch
                if retryAge >= 0 && retryAge <= travel {
                    visible.append(.init(id: 20_000 + index, progress: retryAge / travel, kind: .retry, sizeBytes: sampleSize))
                }
            }
            if reliable && !isLost && index.isMultiple(of: 4) {
                let ackAge = time - launch - travel
                if ackAge >= 0 && ackAge <= travel {
                    visible.append(.init(id: 30_000 + index, progress: 1 - ackAge / travel, kind: .ack, sizeBytes: 40))
                }
            }
        }
        if let ack = metrics.phases.first(where: { $0.id == "ack" }), time >= ack.startMs {
            let ackTravel = visualMinimum > 0 ? min(max(physicalTravel, visualMinimum), ack.durationMs) : physicalTravel
            visible.append(.init(id: 40_000, progress: max(0, 1 - (time - ack.startMs) / ackTravel), kind: .ack, sizeBytes: 40))
        }
        return visible
    }

    private static func makeEvents(_ metrics: NetworkMetrics) -> [NetworkEvent] {
        var entries: [(Double, String, String, String)] = []
        for phase in metrics.phases { entries.append((phase.startMs, phase.id, phase.label, phase.detail)) }
        if let transfer = metrics.phases.first(where: { $0.id == "transfer" }) {
            entries.append((transfer.startMs, "packetize", "Split into packets", "\(metrics.packetCount.formatted()) IP packets carry the compressed payload. Each glowing particle represents a batch."))
            if metrics.config.lossPct > 0 {
                let lossTime = transfer.startMs + min(metrics.transferMs * 0.3, metrics.serializationMs * 0.3 + metrics.oneWayMs * 0.5)
                entries.append((lossTime, "loss", "A packet is lost", metrics.config.transport.isReliable
                                ? "The receiver cannot acknowledge missing data. The reliable transport schedules another attempt."
                                : "UDP does not recover this datagram. An application could add its own recovery, but this toy does not."))
                if metrics.config.transport.isReliable {
                    entries.append((min(transfer.endMs - 0.001, lossTime + metrics.lossRecoveryMs), "retry", "Missing data sent again", "Expected extra packet attempts: \(Int(metrics.expectedRetransmissions.rounded()).formatted()). This is a statistical model, not a packet trace."))
                }
            }
        }
        let result = metrics.config.transport.isReliable
            ? "All original bytes are delivered after modeled loss recovery."
            : "Expected usable chunks: \(Int(metrics.deliveredPct.rounded()))%. UDP does not guarantee delivery or a complete file."
        entries.append((metrics.totalMs, "complete", "Transfer complete", result))
        return entries.enumerated().sorted { first, second in
            first.element.0 == second.element.0 ? first.offset < second.offset : first.element.0 < second.element.0
        }.enumerated().map { id, entry in
            .init(id: id, timeMs: entry.element.0, type: entry.element.1,
                  label: entry.element.2, detail: entry.element.3)
        }
    }
}
