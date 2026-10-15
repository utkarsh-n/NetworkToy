import Foundation

// A bounded discrete-event teaching probe, separate from the bulk forecast.
// 32 independently compressible 1,200-byte application chunks are packetized.
// Every data/ACK hop occupies a link queue, serializes bits, propagates, and
// either arrives or drops. No sockets, real interfaces, or cryptography are used.
// IPv4 addresses are TEST-NET documentation addresses (RFC 5737).
// TCP byte sequences / cumulative ACK + SACK, and QUIC stream offsets / packet
// ACKs are modeled; congestion windows, fast recovery, adaptive RTO/PTO, routing
// convergence, encryption bytes and an actual codec are outside this probe.
// https://www.rfc-editor.org/rfc/rfc5737.html
// https://www.rfc-editor.org/rfc/rfc9293.html
// https://www.rfc-editor.org/rfc/rfc6298.html
// https://www.rfc-editor.org/rfc/rfc9000.html

enum SnifferEventKind: String, CaseIterable, Identifiable, Sendable {
    case setup, compress, queued, transmit, arrive, drop, retry, deliver, ack, duplicate, exhausted, complete
    var id: String { rawValue }
    var title: String {
        switch self {
        case .setup: "Setup"
        case .compress: "Codec"
        case .queued: "Queued"
        case .transmit: "Transmit"
        case .arrive: "Arrive"
        case .drop: "Dropped"
        case .retry: "Retry"
        case .deliver: "Delivered"
        case .ack: "Acknowledged"
        case .duplicate: "Duplicate"
        case .exhausted: "Retry limit"
        case .complete: "Complete"
        }
    }
}

struct SnifferEvent: Identifiable, Equatable, Sendable {
    let id: Int
    let packetID: Int?
    let timeMs: Double
    let kind: SnifferEventKind
    let hopIndex: Int?
    let hopTitle: String
    let byteCount: Int
    let detail: String
    let attempt: Int
    let isAcknowledgment: Bool
    let acknowledgmentNumber: Int?
    let packetNumber: Int?
    // An actual modeled link occupation, useful for packet movement in a view.
    let durationMs: Double
    let medium: LinkMedium?
}

struct SnifferPacket: Identifiable, Equatable, Sendable {
    let id: Int
    let transport: TransportProtocol
    let sourceAddress: String
    let destinationAddress: String
    let sourcePort: Int
    let destinationPort: Int
    let sequenceNumber: Int
    let flags: String
    let originalLength: Int
    let payloadLength: Int
    let headerLength: Int
    let totalLength: Int
    let path: [String]
    let attemptCount: Int
    let received: Bool
    let delivered: Bool
    let acknowledged: Bool
    let ledger: [SnifferEvent]

    var ipProtocolNumber: Int { transport == .tcp ? 6 : 17 }
    var sequenceLabel: String {
        switch transport {
        case .tcp: "TCP byte sequence"
        case .quic: "QUIC stream byte offset"
        case .udp: "Application chunk ID (not a UDP field)"
        }
    }
    var status: String {
        if received && !delivered { return acknowledged ? "Buffered; transport acknowledged" : "Buffered behind a stream gap" }
        if acknowledged { return "Delivered + ACK received" }
        if delivered { return transport == .udp ? "Delivered without ACK" : "Delivered; ACK unconfirmed" }
        if attemptCount > 0 { return "Not delivered" }
        return "Waiting to send"
    }
}

struct SnifferStats: Equatable, Sendable {
    let elapsedMs: Double
    let receivedCount: Int
    let deliveredCount: Int
    let droppedAttempts: Int
    let retryCount: Int
    let ackCount: Int
    let wireBytes: Int
    let goodputMbps: Double
}

struct SnifferResult: Equatable, Sendable {
    let schedule: [SnifferEvent]
    let packets: [SnifferPacket]
    let config: NetworkConfig
    let route: [NetworkRouteSegment]
    let durationMs: Double
    let deliveredCount: Int
    let droppedAttempts: Int
    let retryCount: Int
    let ackCount: Int
    let failedCount: Int
    let originalBytes: Int
    let compressedBytes: Int
    // Sum of every data and ACK transmission on EVERY traversed link. This
    // differs from bulk forecast wireBytes, which counts the data direction once.
    // Abstract DNS/handshake exchanges do not contribute bytes to this sum.
    let wireBytes: Int
    let bytesSaved: Int
    let goodputMbps: Double
    let seed: UInt64
    let assumptions: [String]

    func observedStats(at timeMs: Double) -> SnifferStats {
        let elapsed = timeMs.isFinite ? min(durationMs, max(0, timeMs)) : 0
        let visible = schedule.filter { $0.timeMs <= elapsed }
        let received = Set(visible.filter {
            $0.kind == .arrive && !$0.isAcknowledgment && $0.hopIndex == route.count - 1
        }.compactMap(\.packetID)).count
        let delivered = Set(visible.filter { $0.kind == .deliver }.compactMap(\.packetID)).count
        return .init(elapsedMs: elapsed, receivedCount: received, deliveredCount: delivered,
                     droppedAttempts: visible.filter { $0.kind == .drop }.count,
                     retryCount: visible.filter { $0.kind == .retry }.count,
                     ackCount: visible.filter { $0.kind == .ack }.count,
                     wireBytes: observedWireBytes(at: elapsed),
                     goodputMbps: elapsed > 0 ? Double(delivered * PacketSnifferEngine.chunkBytes) * 8 / elapsed / 1_000 : 0)
    }

    // A transmission-start event knows its complete frame length, but a live
    // wire counter must include only bytes serialized by the observation time.
    func observedWireBytes(at timeMs: Double, packetID: Int? = nil) -> Int {
        let time = timeMs.isFinite ? min(durationMs, max(0, timeMs)) : 0
        return schedule.reduce(0) { total, event in
            guard event.kind == .transmit, event.timeMs <= time,
                  packetID == nil || packetID == event.packetID else { return total }
            let fraction = event.durationMs > 0 ? min(1, max(0, (time - event.timeMs) / event.durationMs)) : 1
            return total + Int((Double(event.byteCount) * fraction).rounded(.down))
        }
    }

    func packet(id: Int) -> SnifferPacket? { packets.first { $0.id == id } }

    // An observed decoder view prevents a live capture from revealing future
    // attempts, outcome, or ledger entries stored in the precomputed schedule.
    func packet(id: Int, at timeMs: Double) -> SnifferPacket? {
        guard let packet = packet(id: id) else { return nil }
        let time = timeMs.isFinite ? min(durationMs, max(0, timeMs)) : 0
        let ledger = packet.ledger.filter { $0.timeMs <= time }
        let acknowledged = schedule.contains {
            guard $0.timeMs <= time, $0.kind == .ack else { return false }
            if $0.packetID == id { return true }
            return packet.transport == .tcp && ($0.acknowledgmentNumber ?? 0) >= packet.sequenceNumber + packet.payloadLength
        }
        return .init(id: packet.id, transport: packet.transport,
                     sourceAddress: packet.sourceAddress, destinationAddress: packet.destinationAddress,
                     sourcePort: packet.sourcePort, destinationPort: packet.destinationPort,
                     sequenceNumber: packet.sequenceNumber, flags: packet.flags,
                     originalLength: packet.originalLength, payloadLength: packet.payloadLength,
                     headerLength: packet.headerLength, totalLength: packet.totalLength,
                     path: packet.path,
                     attemptCount: ledger.filter { $0.kind == .transmit && !$0.isAcknowledgment && $0.hopIndex == 0 }.count,
                     received: ledger.contains { $0.kind == .arrive && !$0.isAcknowledgment && $0.hopIndex == route.count - 1 },
                     delivered: ledger.contains { $0.kind == .deliver },
                     acknowledged: acknowledged, ledger: ledger)
    }
}

enum PacketSnifferEngine {
    static let chunkCount = 32
    static let chunkBytes = 1_200
    static let maximumRetries = 8
    static let defaultSeed: UInt64 = 1984

    static func simulate(config: NetworkConfig, seed: UInt64 = defaultSeed) -> SnifferResult {
        var probe = SnifferProbe(configuration: config, seed: seed)
        return probe.run()
    }
}

private struct SnifferProbe {
    let metrics: NetworkMetrics
    let seed: UInt64
    let payloadLength: Int
    let headerLength: Int
    let frameLength: Int
    let compressionMs: Double
    let decompressionPerChunkMs: Double
    let hopLossProbability: Double
    let perHopWaitMs: Double
    let initialRecoveryMs: Double
    var actions = SnifferActionHeap()
    var nextOrder = 0
    var entries: [SnifferEvent] = []
    var linkReady: [Int: Double] = [:]
    var activeAttempt: [Int: Int] = [:]
    var transmittedAttempts: [Int: Int] = [:]
    var received: Set<Int> = []
    var delivered: Set<Int> = []
    var acknowledged: Set<Int> = []
    var cumulativeReceived = 0
    var nextOrderedDelivery = 1
    var applicationReadyMs = 0.0
    var quicPacketNumber = 0

    var config: NetworkConfig { metrics.config }
    var route: [NetworkRouteSegment] { metrics.route }
    var isReliable: Bool { config.transport.isReliable }
    static let initialSequence = 100_001

    init(configuration: NetworkConfig, seed: UInt64) {
        let metrics = NetworkEngine.calculate(configuration)
        self.metrics = metrics
        self.seed = seed
        let ratio = 1 - metrics.config.compressionPct / 100
        let payload = max(1, Int(ceil(Double(PacketSnifferEngine.chunkBytes) * ratio)))
        payloadLength = payload
        // IPv4(20) + TCP(20) + illustrative TLS record/tag/type(22), or
        // IPv4(20) + UDP(8), or IPv4/UDP(28) + short QUIC header(12) +
        // STREAM envelope(8) + authentication tag(16). No fragmentation.
        switch metrics.config.transport {
        case .tcp: headerLength = 62
        case .udp: headerLength = 28
        case .quic: headerLength = 64
        }
        frameLength = payload + headerLength
        let originalMB = Double(PacketSnifferEngine.chunkCount * PacketSnifferEngine.chunkBytes) / 1_000_000
        let compression = metrics.config.compressionPct / 100
        compressionMs = originalMB * 28 * compression * compression
        decompressionPerChunkMs = Double(PacketSnifferEngine.chunkBytes) / 1_000_000 * 2 * compression
        let hops = max(1, metrics.route.count)
        // Convert the selected end-to-end loss probability into equal per-link
        // probabilities. ACKs face the same independent link conditions.
        hopLossProbability = 1 - pow(1 - metrics.config.lossPct / 100, 1 / Double(hops))
        let radioAccessMs = metrics.config.medium == .fiber ? 0.0 : (metrics.config.medium == .hybrid ? 3.0 : 8.0)
        perHopWaitMs = (metrics.config.latencyMs + metrics.queueMs + radioAccessMs) / Double(hops)
        let packetSerialization = Double(frameLength) * 8 / (metrics.effectiveMbps * 1_000)
        let baselineRoundTrip = metrics.rttMs + packetSerialization * Double(hops) * 2
        // Fixed initial teaching timers with exponential backoff. TCP's floor
        // follows the conservative RFC 6298 initial RTO; QUIC uses a simplified
        // RTT-derived PTO. No adaptive estimation or fast retransmit is claimed.
        initialRecoveryMs = metrics.config.transport == .tcp
            ? max(1_000, baselineRoundTrip * 2) : max(50, baselineRoundTrip * 2)
    }

    mutating func run() -> SnifferResult {
        var ready = 0.0
        for phase in metrics.phases where ["dns", "tcp", "tls", "quic"].contains(phase.id) {
            record(time: ready, kind: .setup, detail: "\(phase.label): \(phase.detail) These setup exchanges are timing placeholders, not decoded data frames.", duration: phase.durationMs)
            ready += phase.durationMs
        }
        if compressionMs > 0 {
            record(time: ready, kind: .compress, bytes: PacketSnifferEngine.chunkCount * payloadLength,
                   detail: "Independently compress 32 × 1,200 B chunks to \(payloadLength) B each. Ratio is assumed achievable; CPU time is modeled and no codec runs.", duration: compressionMs)
            ready += compressionMs
        }
        applicationReadyMs = ready
        for id in 1...PacketSnifferEngine.chunkCount {
            activeAttempt[id] = 1
            enqueue(.init(time: ready, order: 0, kind: .requestHop, packetID: id, attempt: 1, hop: 0))
        }
        while let action = actions.pop() { process(action) }
        let finish = max(ready, entries.map(\.timeMs).max() ?? ready)
        let retries = entries.filter { $0.kind == .retry }.count
        let drops = entries.filter { $0.kind == .drop }.count
        let ackCount = entries.filter { $0.kind == .ack }.count
        let wire = entries.filter { $0.kind == .transmit }.reduce(0) { $0 + $1.byteCount }
        record(time: finish, kind: .complete,
               detail: "Probe complete: \(delivered.count)/32 application chunks delivered, \(drops) data/ACK drops, \(retries) repeated data attempts. \(isReliable ? "Recovery is bounded to eight retries per chunk." : "Raw UDP does not retransmit or acknowledge.")")
        let schedule = entries.sorted { $0.timeMs == $1.timeMs ? $0.id < $1.id : $0.timeMs < $1.timeMs }
            .enumerated().map { index, event in
                SnifferEvent(id: index, packetID: event.packetID, timeMs: event.timeMs,
                             kind: event.kind, hopIndex: event.hopIndex, hopTitle: event.hopTitle,
                             byteCount: event.byteCount, detail: event.detail, attempt: event.attempt,
                             isAcknowledgment: event.isAcknowledgment, acknowledgmentNumber: event.acknowledgmentNumber,
                             packetNumber: event.packetNumber, durationMs: event.durationMs, medium: event.medium)
            }
        let sourceIndex = NetworkEngine.nodes.firstIndex { $0.id == config.sourceID } ?? 0
        let destinationIndex = NetworkEngine.nodes.firstIndex { $0.id == config.destinationID } ?? 0
        let path = metrics.routeNodes.map(\.city)
        let packets = (1...PacketSnifferEngine.chunkCount).map { id in
            SnifferPacket(id: id, transport: config.transport,
                          sourceAddress: "192.0.2.\(10 + sourceIndex)",
                          destinationAddress: "198.51.100.\(10 + destinationIndex)",
                          sourcePort: 49_152, destinationPort: config.transport == .udp ? 9_000 : 443,
                          sequenceNumber: sequence(for: id),
                          flags: config.transport == .tcp ? "PSH ACK" : config.transport == .quic ? "STREAM" : "DATAGRAM",
                          originalLength: PacketSnifferEngine.chunkBytes, payloadLength: payloadLength,
                          headerLength: headerLength, totalLength: frameLength, path: path,
                          attemptCount: transmittedAttempts[id, default: 0], received: received.contains(id),
                          delivered: delivered.contains(id), acknowledged: acknowledged.contains(id),
                          ledger: schedule.filter { $0.packetID == id })
        }
        let original = PacketSnifferEngine.chunkCount * PacketSnifferEngine.chunkBytes
        let compressed = PacketSnifferEngine.chunkCount * payloadLength
        return .init(schedule: schedule, packets: packets, config: config, route: route,
                     durationMs: finish, deliveredCount: delivered.count, droppedAttempts: drops,
                     retryCount: retries, ackCount: ackCount,
                     failedCount: PacketSnifferEngine.chunkCount - delivered.count,
                     originalBytes: original, compressedBytes: compressed,
                     wireBytes: wire, bytesSaved: original - compressed,
                     goodputMbps: Double(delivered.count * PacketSnifferEngine.chunkBytes) * 8 / max(finish, 0.001) / 1_000,
                     seed: seed, assumptions: [
                        "A separate 32 × 1,200 B (38.4 KB) probe; the bulk payload setting does not resize it.",
                        "Each chunk is independently compressible and decodable; ratios and CPU cost are assumptions.",
                        "IPv4 documentation addresses, 1,280 B nominal MTU, fixed illustrative transport envelopes; no fragmentation.",
                        "All-hop wire bytes count data/retry/ACK transmissions, excluding abstract DNS and handshake bytes.",
                        "Fiber uses separate directional queues; wireless and mixed access share airtime in both directions.",
                        "Loss is seeded per link from the selected end-to-end probability; ACKs can also drop.",
                        "TCP uses cumulative ACK with simplified SACK feedback; QUIC uses packet ACK and one ordered stream.",
                        "A 32-chunk eager flight, fixed initial timeout/PTO and backoff replace full congestion-window algorithms.",
                        "At most eight retries per chunk. Reliable transports can finish with unconfirmed or undelivered data."
                     ])
    }

    private mutating func process(_ action: SnifferAction) {
        switch action.kind {
        case .requestHop:
            guard action.isAck || action.hop != 0 || !acknowledged.contains(action.packetID) else { return }
            let link = route[action.hop]
            let key = queueKey(hop: action.hop, ack: action.isAck)
            let eligible = action.time + perHopWaitMs
            let start = max(eligible, linkReady[key, default: 0])
            let bytes = action.isAck ? action.frameBytes : frameLength
            let serialization = Double(bytes) * 8 / (metrics.effectiveMbps * 1_000)
            linkReady[key] = start + serialization
            if start > action.time + 0.000_001 {
                record(action: action, kind: .queued, bytes: bytes,
                       detail: "Wait \(format(start - action.time)) ms: modeled background/extra delay plus this link's occupied transmission queue.",
                       duration: start - action.time)
            }
            var transmission = action
            transmission.kind = .beginTransmission
            transmission.time = start
            transmission.frameBytes = bytes
            transmission.serializationMs = serialization
            transmission.propagationMs = link.propagationMs
            enqueue(transmission)

        case .beginTransmission:
            var arrival = action
            if !action.isAck && action.hop == 0 {
                transmittedAttempts[action.packetID, default: 0] += 1
                if action.attempt > 1 {
                    record(action: action, kind: .retry, bytes: frameLength,
                           detail: "Repeated data attempt \(action.attempt) begins on the first link after missing feedback, preserving its \(config.transport == .tcp ? "TCP sequence" : "stream byte offset").")
                }
                if config.transport == .quic { quicPacketNumber += 1; arrival.packetNumber = quicPacketNumber }
                if isReliable {
                    var timeout = action
                    timeout.kind = .timeout
                    timeout.time = action.time + action.serializationMs + recoveryTimeout(attempt: action.attempt)
                    enqueue(timeout)
                }
            }
            let protocolDescription = action.isAck ? "\(config.transport.title) ACK" : config.transport.title
            let sequenceDescription = config.transport == .udp ? "application chunk \(action.packetID)" : "byte position \(sequence(for: action.packetID))"
            record(action: arrival, kind: .transmit, bytes: action.frameBytes,
                   detail: "\(protocolDescription), attempt \(action.attempt), \(sequenceDescription). Serialize \(action.frameBytes) B in \(format(action.serializationMs)) ms, then propagate \(format(action.propagationMs)) ms.",
                   duration: action.serializationMs)
            arrival.kind = .reachHop
            arrival.time = action.time + action.serializationMs + action.propagationMs
            arrival.shouldDrop = drops(packet: action.packetID, attempt: action.attempt, hop: action.hop, ack: action.isAck)
            enqueue(arrival)

        case .reachHop:
            if action.shouldDrop {
                record(action: action, kind: .drop, bytes: action.frameBytes,
                       detail: "Seeded link loss discards this \(action.isAck ? "ACK" : "data") frame. \(isReliable ? "The sender must await acknowledgment or its recovery timer." : "Raw UDP has no transport recovery.")")
                return
            }
            record(action: action, kind: .arrive, bytes: action.frameBytes,
                   detail: "Frame reaches \(nodeName(action.isAck ? route[action.hop].from : route[action.hop].to)). IPv4 hop limit becomes \(64 - (action.isAck ? route.count - action.hop : action.hop + 1)).")
            let next = action.isAck ? action.hop - 1 : action.hop + 1
            if route.indices.contains(next) {
                var forwarded = action
                forwarded.kind = .requestHop
                forwarded.hop = next
                enqueue(forwarded)
            } else if action.isAck {
                acknowledge(action)
            } else {
                receive(action)
            }

        case .timeout:
            guard isReliable, !acknowledged.contains(action.packetID),
                  activeAttempt[action.packetID] == action.attempt else { return }
            if action.attempt > PacketSnifferEngine.maximumRetries {
                record(action: action, kind: .exhausted,
                       detail: "Eight retries exhausted for chunk \(action.packetID). \(received.contains(action.packetID) ? "The receiver has it but the sender lacks confirming feedback." : "It remains missing; later stream bytes may be buffered.")")
                return
            }
            let next = action.attempt + 1
            activeAttempt[action.packetID] = next
            record(action: action, kind: .queued, bytes: frameLength,
                   detail: "No confirming ACK before the simplified recovery timer. Requeue chunk \(action.packetID) as attempt \(next), preserving its \(config.transport == .tcp ? "TCP sequence" : "stream byte offset").")
            enqueue(.init(time: action.time, order: 0, kind: .requestHop,
                          packetID: action.packetID, attempt: next, hop: 0))

        case .deliverChunk:
            guard delivered.insert(action.packetID).inserted else { return }
            record(action: action, kind: .deliver, bytes: PacketSnifferEngine.chunkBytes,
                   detail: "Application receives \(PacketSnifferEngine.chunkBytes) original bytes after decoding this independently compressed chunk.\(isReliable ? " Ordered-stream gaps are now resolved up to this chunk." : " Other UDP datagrams can remain missing.")")
        }
    }

    private mutating func receive(_ action: SnifferAction) {
        let isNew = received.insert(action.packetID).inserted
        if !isNew {
            record(action: action, kind: .duplicate, bytes: action.frameBytes,
                   detail: "Receiver already holds this chunk; do not deliver a second copy. Generate feedback again.")
        }
        while received.contains(cumulativeReceived + 1) { cumulativeReceived += 1 }
        if isNew {
            if isReliable {
                while received.contains(nextOrderedDelivery) {
                    applicationReadyMs = max(applicationReadyMs, action.time) + decompressionPerChunkMs
                    enqueue(.init(time: applicationReadyMs, order: 0, kind: .deliverChunk,
                                  packetID: nextOrderedDelivery, attempt: action.attempt, hop: route.count - 1))
                    nextOrderedDelivery += 1
                }
            } else {
                applicationReadyMs = max(applicationReadyMs, action.time) + decompressionPerChunkMs
                enqueue(.init(time: applicationReadyMs, order: 0, kind: .deliverChunk,
                              packetID: action.packetID, attempt: action.attempt, hop: route.count - 1))
            }
        }
        if isReliable {
            let ackNumber = config.transport == .tcp ? Self.initialSequence + cumulativeReceived * payloadLength : nil
            let sack = config.transport == .tcp && action.packetID > cumulativeReceived
            // A minimal TCP ACK is 40 B; one SACK block adds 12 B. A modeled
            // QUIC ACK uses IPv4/UDP + short header, ACK frame and 16 B tag.
            let ackLength = config.transport == .tcp ? (sack ? 52 : 40) : 60
            var ack = SnifferAction(time: action.time, order: 0, kind: .requestHop,
                                    packetID: action.packetID, attempt: action.attempt,
                                    hop: route.count - 1, isAck: true)
            ack.frameBytes = ackLength
            ack.ackNumber = ackNumber
            ack.cumulativeChunk = cumulativeReceived
            ack.packetNumber = action.packetNumber
            enqueue(ack)
        }
    }

    private mutating func acknowledge(_ action: SnifferAction) {
        acknowledged.insert(action.packetID)
        if config.transport == .tcp, action.cumulativeChunk > 0 {
            acknowledged.formUnion(1...action.cumulativeChunk)
        }
        let description = config.transport == .tcp
            ? "TCP cumulative ACK \(action.ackNumber ?? Self.initialSequence); SACK feedback also identifies out-of-order chunk \(action.packetID) when needed."
            : "QUIC ACK confirms packet number \(action.packetNumber ?? 0), which carried chunk \(action.packetID). QUIC retransmits stream data in a new packet, not the old packet number."
        record(action: action, kind: .ack, bytes: action.frameBytes, detail: description)
    }

    private func sequence(for id: Int) -> Int {
        switch config.transport {
        case .tcp: Self.initialSequence + (id - 1) * payloadLength
        case .quic: (id - 1) * payloadLength
        case .udp: id
        }
    }

    private func queueKey(hop: Int, ack: Bool) -> Int {
        // Radio access competes for one airtime resource. Fiber directions can
        // pipeline simultaneously, each with its own serialization queue.
        let sharesAirtime = route[hop].medium != .fiber
        return hop * 2 + (ack && !sharesAirtime ? 1 : 0)
    }

    private func recoveryTimeout(attempt: Int) -> Double {
        min(60_000, initialRecoveryMs * pow(2, Double(attempt - 1)))
    }

    private func drops(packet: Int, attempt: Int, hop: Int, ack: Bool) -> Bool {
        guard hopLossProbability > 0 else { return false }
        // Stateless keyed draws keep a packet's loss decision stable when only
        // bandwidth or latency changes, independent of event processing order.
        var value = seed
        value ^= UInt64(packet) &* 0x9E3779B97F4A7C15
        value ^= UInt64(attempt) &* 0xBF58476D1CE4E5B9
        value ^= UInt64(hop + 1) &* 0x94D049BB133111EB
        if ack { value ^= 0xD6E8FEB86659FD93 }
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / 9_007_199_254_740_992 < hopLossProbability
    }

    private func nodeName(_ id: String) -> String {
        NetworkEngine.nodes.first { $0.id == id }?.city ?? id
    }

    private func format(_ milliseconds: Double) -> String {
        milliseconds.formatted(.number.precision(.fractionLength(3)))
    }

    private mutating func enqueue(_ action: SnifferAction) {
        var action = action
        action.order = nextOrder
        nextOrder += 1
        actions.push(action)
    }

    private mutating func record(action: SnifferAction, kind: SnifferEventKind,
                                 bytes: Int = 0, detail: String, duration: Double = 0) {
        let link = route[action.hop]
        let from = action.isAck ? link.to : link.from
        let to = action.isAck ? link.from : link.to
        record(time: action.time, kind: kind, packet: action.packetID, hop: action.hop,
               title: "\(nodeName(from)) → \(nodeName(to))", bytes: bytes, detail: detail,
               attempt: action.attempt, ack: action.isAck, ackNumber: action.ackNumber,
               packetNumber: action.packetNumber, duration: duration, medium: link.medium)
    }

    private mutating func record(time: Double, kind: SnifferEventKind, packet: Int? = nil,
                                 hop: Int? = nil, title: String = "Probe endpoints", bytes: Int = 0,
                                 detail: String, attempt: Int = 0, ack: Bool = false,
                                 ackNumber: Int? = nil, packetNumber: Int? = nil,
                                 duration: Double = 0, medium: LinkMedium? = nil) {
        entries.append(.init(id: entries.count, packetID: packet, timeMs: time, kind: kind,
                             hopIndex: hop, hopTitle: title, byteCount: bytes, detail: detail,
                             attempt: attempt, isAcknowledgment: ack,
                             acknowledgmentNumber: ackNumber, packetNumber: packetNumber,
                             durationMs: duration, medium: medium))
    }
}

private enum SnifferActionKind: Sendable {
    case requestHop, beginTransmission, reachHop, timeout, deliverChunk
}

private struct SnifferAction: Sendable {
    var time: Double
    var order: Int
    var kind: SnifferActionKind
    var packetID: Int
    var attempt: Int
    var hop: Int
    var isAck = false
    var frameBytes = 0
    var serializationMs = 0.0
    var propagationMs = 0.0
    var shouldDrop = false
    var ackNumber: Int?
    var cumulativeChunk = 0
    var packetNumber: Int?
}

private struct SnifferActionHeap: Sendable {
    private var values: [SnifferAction] = []
    private func precedes(_ a: SnifferAction, _ b: SnifferAction) -> Bool {
        a.time == b.time ? a.order < b.order : a.time < b.time
    }
    mutating func push(_ value: SnifferAction) {
        values.append(value)
        var index = values.count - 1
        while index > 0 {
            let parent = (index - 1) / 2
            guard precedes(values[index], values[parent]) else { break }
            values.swapAt(index, parent)
            index = parent
        }
    }
    mutating func pop() -> SnifferAction? {
        guard !values.isEmpty else { return nil }
        if values.count == 1 { return values.removeLast() }
        let first = values[0]
        values[0] = values.removeLast()
        var index = 0
        while true {
            let left = index * 2 + 1
            guard left < values.count else { break }
            let right = left + 1
            let next = right < values.count && precedes(values[right], values[left]) ? right : left
            guard precedes(values[next], values[index]) else { break }
            values.swapAt(index, next)
            index = next
        }
        return first
    }
}
