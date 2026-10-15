import XCTest
@testable import NetworkToyCore

final class PacketSnifferTests: XCTestCase {
    func testZeroLossUDPProbeHasExactly32IndependentChunksAndNoACKs() {
        var config = NetworkConfig.default
        config.transport = .udp
        let probe = PacketSnifferEngine.simulate(config: config)
        XCTAssertEqual(probe.packets.count, 32)
        XCTAssertEqual(probe.originalBytes, 38_400)
        XCTAssertEqual(probe.deliveredCount, 32)
        XCTAssertEqual(probe.droppedAttempts, 0)
        XCTAssertEqual(probe.retryCount, 0)
        XCTAssertEqual(probe.ackCount, 0)
        XCTAssertTrue(probe.packets.allSatisfy { $0.attemptCount == 1 && $0.delivered && !$0.acknowledged })
        XCTAssertFalse(probe.schedule.contains { $0.isAcknowledgment })
        // Each actual data frame occupies every link exactly once.
        XCTAssertEqual(probe.wireBytes, probe.packets.reduce(0) { $0 + $1.totalLength } * probe.route.count)
    }

    func testPacketHeadersUseDocumentationAddressesAndProtocolSpecificPositions() {
        var config = NetworkConfig.default
        config.compressionPct = 50
        for transport in TransportProtocol.allCases {
            config.transport = transport
            let probe = PacketSnifferEngine.simulate(config: config)
            let first = probe.packets[0]
            let second = probe.packets[1]
            XCTAssertTrue(first.sourceAddress.hasPrefix("192.0.2."))
            XCTAssertTrue(first.destinationAddress.hasPrefix("198.51.100."))
            XCTAssertEqual(first.payloadLength, 600)
            XCTAssertEqual(first.totalLength, first.payloadLength + first.headerLength)
            XCTAssertLessThanOrEqual(first.totalLength, 1_280)
            XCTAssertEqual(first.path.first, "San Francisco")
            XCTAssertEqual(first.path.last, "London")
            XCTAssertEqual(first.ipProtocolNumber, transport == .tcp ? 6 : 17)
            XCTAssertEqual(second.sequenceNumber - first.sequenceNumber, transport == .udp ? 1 : 600)
            XCTAssertEqual(first.destinationPort, transport == .udp ? 9_000 : 443)
        }
    }

    func testEveryHopSerializesThenPropagatesWithoutOverlappingItsQueue() {
        var config = NetworkConfig.default
        config.transport = .udp
        config.medium = .fiber
        config.compressionPct = 0
        config.bandwidthMbps = 1
        let probe = PacketSnifferEngine.simulate(config: config)
        for hop in probe.route.indices {
            let transmissions = probe.schedule.filter { $0.kind == .transmit && $0.hopIndex == hop }
            for (previous, next) in zip(transmissions, transmissions.dropFirst()) {
                XCTAssertGreaterThanOrEqual(next.timeMs + 0.000_001, previous.timeMs + previous.durationMs)
            }
            let first = transmissions.first!
            let arrival = probe.schedule.first { $0.kind == .arrive && $0.hopIndex == hop && $0.packetID == first.packetID }!
            XCTAssertEqual(arrival.timeMs - first.timeMs, first.durationMs + probe.route[hop].propagationMs, accuracy: 0.000_001)
        }
        for packet in probe.packets {
            for hop in 1..<probe.route.count {
                let previousArrival = packet.ledger.first { $0.kind == .arrive && $0.hopIndex == hop - 1 }!
                let nextTransmit = packet.ledger.first { $0.kind == .transmit && $0.hopIndex == hop }!
                XCTAssertGreaterThanOrEqual(nextTransmit.timeMs, previousArrival.timeMs)
            }
        }
    }

    func testMoreCapacityShortensSerializationWithoutChangingPropagation() {
        var config = NetworkConfig.default
        config.transport = .udp
        config.medium = .fiber
        config.bandwidthMbps = 1
        let slow = PacketSnifferEngine.simulate(config: config)
        config.bandwidthMbps = 1_000
        let fast = PacketSnifferEngine.simulate(config: config)
        let slowTransmission = slow.schedule.first { $0.kind == .transmit }!
        let fastTransmission = fast.schedule.first { $0.kind == .transmit }!
        XCTAssertEqual(slowTransmission.durationMs / fastTransmission.durationMs, 1_000, accuracy: 0.000_001)
        XCTAssertEqual(slow.route.map(\.propagationMs), fast.route.map(\.propagationMs))
        XCTAssertEqual(slow.wireBytes, fast.wireBytes)
        XCTAssertLessThan(fast.durationMs, slow.durationMs)
    }

    func testCongestionConsumesCapacityAndCreatesLongerActualQueues() {
        var config = NetworkConfig.default
        config.transport = .udp
        config.bandwidthMbps = 10
        let idle = PacketSnifferEngine.simulate(config: config)
        config.congestionPct = 80
        let busy = PacketSnifferEngine.simulate(config: config)
        XCTAssertGreaterThan(busy.durationMs, idle.durationMs)
        let idleTx = idle.schedule.first { $0.kind == .transmit }!
        let busyTx = busy.schedule.first { $0.kind == .transmit }!
        XCTAssertEqual(busyTx.durationMs / idleTx.durationMs, 5, accuracy: 0.000_001)
        let idleQueue = idle.schedule.filter { $0.kind == .queued }.reduce(0) { $0 + $1.durationMs }
        let busyQueue = busy.schedule.filter { $0.kind == .queued }.reduce(0) { $0 + $1.durationMs }
        XCTAssertGreaterThan(busyQueue, idleQueue)
    }

    func testSeededLossLeavesUDPGapsAndReliableTransportsRecoverWithACKs() {
        var config = NetworkConfig.default
        config.lossPct = 20
        config.transport = .udp
        let udp = PacketSnifferEngine.simulate(config: config)
        XCTAssertGreaterThan(udp.droppedAttempts, 0)
        XCTAssertLessThan(udp.deliveredCount, 32)
        XCTAssertEqual(udp.deliveredCount + udp.droppedAttempts, 32)
        XCTAssertEqual(udp.retryCount, 0)
        XCTAssertEqual(udp.ackCount, 0)
        XCTAssertTrue(udp.packets.allSatisfy { $0.attemptCount == 1 })
        for transport in [TransportProtocol.tcp, .quic] {
            config.transport = transport
            let reliable = PacketSnifferEngine.simulate(config: config)
            XCTAssertGreaterThan(reliable.retryCount, 0)
            XCTAssertGreaterThan(reliable.ackCount, 0)
            XCTAssertGreaterThan(reliable.deliveredCount, udp.deliveredCount)
            XCTAssertTrue(reliable.packets.allSatisfy { $0.attemptCount <= 9 })
            XCTAssertEqual(reliable.retryCount, reliable.packets.reduce(0) { $0 + max(0, $1.attemptCount - 1) })
            XCTAssertTrue(reliable.schedule.contains { $0.kind == .transmit && $0.isAcknowledgment })
            XCTAssertTrue(reliable.schedule.filter { $0.isAcknowledgment && $0.kind == .transmit }.allSatisfy { $0.byteCount > 0 })
        }
    }

    func testACKsReturnAlongRouteAndQUICRetriesUseNewPacketNumbers() {
        var config = NetworkConfig.default
        config.transport = .quic
        config.lossPct = 20
        let probe = PacketSnifferEngine.simulate(config: config)
        let starts = probe.schedule.filter { $0.kind == .transmit && !$0.isAcknowledgment && $0.hopIndex == 0 }
        let numbers = starts.compactMap(\.packetNumber)
        XCTAssertEqual(numbers.count, starts.count)
        XCTAssertEqual(Set(numbers).count, numbers.count)
        XCTAssertEqual(numbers, numbers.sorted())
        XCTAssertTrue(starts.contains { $0.attempt > 1 })
        let ack = probe.schedule.first { $0.kind == .ack }!
        let returnPath = probe.packet(id: ack.packetID!)!.ledger.filter {
            $0.kind == .transmit && $0.isAcknowledgment && $0.attempt == ack.attempt
        }
        XCTAssertEqual(returnPath.map(\.hopIndex), Array(probe.route.indices.reversed()).map(Optional.some))
    }

    func testRecoveryBudgetCanExhaustWithoutClaimingConfirmation() {
        var config = NetworkConfig.default
        config.medium = .fiber
        config.transport = .quic
        config.lossPct = 20
        // This fixed seed loses all nine round trips for chunk 21, including
        // ACK losses. A received chunk must not become falsely confirmed.
        let probe = PacketSnifferEngine.simulate(config: config, seed: 22)
        let packet = probe.packet(id: 21)!
        XCTAssertEqual(packet.attemptCount, 9)
        XCTAssertFalse(packet.acknowledged)
        XCTAssertTrue(packet.ledger.contains { $0.kind == .exhausted && $0.detail.contains("Eight retries exhausted") })
        XCTAssertEqual(probe.schedule.filter { $0.kind == .complete }.count, 1)
        XCTAssertNil(probe.schedule.last?.packetID)
        XCTAssertTrue(probe.durationMs.isFinite)
        XCTAssertTrue(probe.packets.allSatisfy { $0.attemptCount <= 9 })
    }

    func testCompressionChangesActualPacketBytesAndCanTradeAgainstCPUTime() {
        var config = NetworkConfig.default
        config.transport = .udp
        config.medium = .fiber
        config.compressionPct = 0
        config.bandwidthMbps = 1
        let rawSlow = PacketSnifferEngine.simulate(config: config)
        config.compressionPct = 90
        let compressedSlow = PacketSnifferEngine.simulate(config: config)
        XCTAssertEqual(compressedSlow.packets.count, 32)
        XCTAssertEqual(compressedSlow.compressedBytes, 3_840)
        XCTAssertEqual(compressedSlow.bytesSaved, 34_560)
        XCTAssertLessThan(compressedSlow.wireBytes, rawSlow.wireBytes)
        XCTAssertLessThan(compressedSlow.durationMs, rawSlow.durationMs)
        config.bandwidthMbps = 1_000
        config.compressionPct = 0
        let rawFast = PacketSnifferEngine.simulate(config: config)
        config.compressionPct = 90
        let compressedFast = PacketSnifferEngine.simulate(config: config)
        XCTAssertGreaterThan(compressedFast.durationMs, rawFast.durationMs)
        XCTAssertTrue(compressedFast.schedule.contains { $0.kind == .compress && $0.durationMs > 0 })
    }

    func testProbeIsIndependentOfTheBulkPayloadSettingAndDoesNotMutateConfig() {
        var config = NetworkConfig.default
        let original = config
        let small = PacketSnifferEngine.simulate(config: config)
        XCTAssertEqual(config, original)
        config.payloadMB = 50
        let large = PacketSnifferEngine.simulate(config: config)
        XCTAssertEqual(small.originalBytes, large.originalBytes)
        XCTAssertEqual(small.schedule, large.schedule)
        XCTAssertEqual(small.durationMs, large.durationMs)
    }

    func testObservedCountersAndDecoderDoNotRevealFutureResults() {
        let probe = PacketSnifferEngine.simulate(config: .default)
        let initial = probe.observedStats(at: 0)
        XCTAssertEqual(initial.deliveredCount, 0)
        XCTAssertEqual(initial.receivedCount, 0)
        XCTAssertEqual(initial.wireBytes, 0)
        let initialPacket = probe.packet(id: 1, at: 0)!
        XCTAssertEqual(initialPacket.attemptCount, 0)
        XCTAssertFalse(initialPacket.delivered)
        XCTAssertTrue(initialPacket.ledger.isEmpty)
        let firstTransmission = probe.schedule.first { $0.kind == .transmit }!
        let midTransmission = firstTransmission.timeMs + firstTransmission.durationMs * 0.5
        XCTAssertEqual(probe.observedWireBytes(at: firstTransmission.timeMs), 0)
        XCTAssertEqual(probe.observedStats(at: midTransmission).wireBytes, firstTransmission.byteCount / 2)
        XCTAssertEqual(probe.observedWireBytes(at: midTransmission, packetID: firstTransmission.packetID), firstTransmission.byteCount / 2)
        let final = probe.observedStats(at: probe.durationMs)
        XCTAssertEqual(final.deliveredCount, probe.deliveredCount)
        XCTAssertEqual(final.droppedAttempts, probe.droppedAttempts)
        XCTAssertEqual(final.retryCount, probe.retryCount)
        XCTAssertEqual(final.ackCount, probe.ackCount)
        XCTAssertEqual(final.wireBytes, probe.wireBytes)
        XCTAssertEqual(final.goodputMbps, probe.goodputMbps, accuracy: 0.000_001)
        let halfway = probe.durationMs * 0.5
        XCTAssertTrue(probe.packet(id: 1, at: halfway)!.ledger.allSatisfy { $0.timeMs <= halfway })
        XCTAssertEqual(probe.observedStats(at: .nan).elapsedMs, 0)
        XCTAssertEqual(probe.observedStats(at: .infinity).elapsedMs, 0)
    }

    func testIdenticalSeedProducesStableChronologicalEventIDsAndAccounting() {
        var config = NetworkConfig.default
        config.transport = .quic
        config.lossPct = 12
        let first = PacketSnifferEngine.simulate(config: config, seed: 1984)
        let second = PacketSnifferEngine.simulate(config: config, seed: 1984)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.schedule.map(\.id), Array(first.schedule.indices))
        XCTAssertEqual(first.schedule.map(\.timeMs), first.schedule.map(\.timeMs).sorted())
        XCTAssertEqual(first.schedule.last?.kind, .complete)
        XCTAssertEqual(first.schedule.last?.timeMs, first.durationMs)
        XCTAssertEqual(first.wireBytes, first.schedule.filter { $0.kind == .transmit }.reduce(0) { $0 + $1.byteCount })
        XCTAssertTrue(first.schedule.allSatisfy { $0.timeMs.isFinite && $0.timeMs >= 0 })
        let anotherSeed = PacketSnifferEngine.simulate(config: config, seed: 1985)
        XCTAssertNotEqual(first.schedule, anotherSeed.schedule)
    }
}
