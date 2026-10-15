import XCTest
@testable import NetworkToyCore

final class NetworkEngineTests: XCTestCase {
    func testDefaultRouteUsesAtlanticHubsAndContinuousSegments() {
        let metrics = NetworkEngine.calculate(.default)
        XCTAssertEqual(metrics.routeNodes.map(\.id), ["san-francisco", "new-york", "london"])
        XCTAssertEqual(metrics.route.count, metrics.routeNodes.count - 1)
        XCTAssertGreaterThan(metrics.distanceKm, 10_000)
        XCTAssertLessThan(metrics.distanceKm, 15_000)
        for (index, segment) in metrics.route.enumerated() {
            XCTAssertEqual(segment.from, metrics.routeNodes[index].id)
            XCTAssertEqual(segment.to, metrics.routeNodes[index + 1].id)
            XCTAssertGreaterThan(segment.propagationMs, 0)
        }
        XCTAssertEqual(metrics.distanceKm, metrics.route.reduce(0) { $0 + $1.distanceKm }, accuracy: 0.001)
    }

    func testBandwidthChangesSerializationButNotPropagation() {
        var config = NetworkConfig.default
        config.compressionPct = 0
        config.bandwidthMbps = 10
        let slow = NetworkEngine.calculate(config)
        config.bandwidthMbps = 100
        let fast = NetworkEngine.calculate(config)
        XCTAssertEqual(slow.serializationMs / fast.serializationMs, 10, accuracy: 0.00001)
        XCTAssertEqual(slow.propagationMs, fast.propagationMs, accuracy: 0.00001)
        XCTAssertEqual(slow.rttMs, fast.rttMs, accuracy: 0.00001)
        XCTAssertGreaterThan(slow.totalMs, fast.totalMs)
        // Every link does not serialize the entire payload serially.
        XCTAssertEqual(fast.serializationMs, fast.wireBytes * 8 / (fast.effectiveMbps * 1_000), accuracy: 0.001)
    }

    func testAddedLatencyIsOneWayAndAffectsRoundTrips() {
        var config = NetworkConfig.default
        config.transport = .tcp
        let baseline = NetworkEngine.calculate(config)
        config.latencyMs = 80
        let delayed = NetworkEngine.calculate(config)
        XCTAssertEqual(delayed.oneWayMs - baseline.oneWayMs, 80, accuracy: 0.001)
        XCTAssertEqual(delayed.rttMs - baseline.rttMs, 160, accuracy: 0.001)
        XCTAssertEqual(delayed.serializationMs, baseline.serializationMs, accuracy: 0.001)
        XCTAssertGreaterThan(delayed.totalMs, baseline.totalMs + 160)
    }

    func testReliableLossAddsRetriesButUDPDoesNotRecover() {
        var config = NetworkConfig.default
        config.lossPct = 10
        config.transport = .tcp
        let tcp = NetworkEngine.calculate(config)
        config.transport = .quic
        let quic = NetworkEngine.calculate(config)
        config.transport = .udp
        let udp = NetworkEngine.calculate(config)
        XCTAssertEqual(tcp.deliveredPct, 100)
        XCTAssertEqual(quic.deliveredPct, 100)
        XCTAssertEqual(udp.deliveredPct, 90)
        XCTAssertEqual(udp.expectedRetransmissions, 0)
        XCTAssertEqual(udp.lossRecoveryMs, 0)
        XCTAssertGreaterThan(tcp.expectedRetransmissions, 0)
        XCTAssertGreaterThan(quic.expectedRetransmissions, 0)
        XCTAssertEqual(quic.expectedRetransmissions, Double(quic.packetCount) * 0.1 / 0.9, accuracy: 0.0001)
        XCTAssertEqual(tcp.lossRecoveryMs, quic.lossRecoveryMs, accuracy: 0.001)
        XCTAssertEqual(udp.deliveredBytes, udp.payloadBytes * 0.9, accuracy: 0.001)
    }

    func testProtocolHandshakesMatchFreshConnectionAssumptions() {
        var config = NetworkConfig.default
        config.transport = .tcp
        let tcp = NetworkEngine.calculate(config)
        config.transport = .quic
        let quic = NetworkEngine.calculate(config)
        config.transport = .udp
        let udp = NetworkEngine.calculate(config)
        XCTAssertTrue(tcp.phases.contains { $0.id == "tcp" })
        XCTAssertTrue(tcp.phases.contains { $0.id == "tls" })
        XCTAssertTrue(quic.phases.contains { $0.id == "quic" })
        XCTAssertFalse(quic.phases.contains { $0.id == "tls" })
        XCTAssertFalse(udp.phases.contains { ["tcp", "tls", "quic", "ack"].contains($0.id) })
        XCTAssertGreaterThan(tcp.totalMs, quic.totalMs)
    }

    func testCompressionSavesSlowLinkTimeButHasCPUTradeoff() {
        var config = NetworkConfig.default
        config.bandwidthMbps = 10
        config.compressionPct = 0
        let slowRaw = NetworkEngine.calculate(config)
        config.compressionPct = 75
        let slowCompressed = NetworkEngine.calculate(config)
        XCTAssertEqual(slowCompressed.compressedBytes, slowRaw.payloadBytes * 0.25, accuracy: 0.001)
        XCTAssertLessThan(slowCompressed.totalMs, slowRaw.totalMs)
        XCTAssertGreaterThan(slowCompressed.compressionMs, 0)
        config.bandwidthMbps = 1_000
        config.compressionPct = 0
        let fastRaw = NetworkEngine.calculate(config)
        config.compressionPct = 90
        let fastCompressed = NetworkEngine.calculate(config)
        XCTAssertGreaterThan(fastCompressed.totalMs, fastRaw.totalMs)
    }

    func testCongestionReducesSharedCapacityAndAddsQueueDelay() {
        var config = NetworkConfig.default
        let empty = NetworkEngine.calculate(config)
        config.congestionPct = 80
        let full = NetworkEngine.calculate(config)
        XCTAssertEqual(full.effectiveMbps, empty.effectiveMbps * 0.2, accuracy: 0.001)
        XCTAssertGreaterThan(full.queueMs, empty.queueMs)
        XCTAssertGreaterThan(full.rttMs, empty.rttMs)
        XCTAssertGreaterThan(full.totalMs, empty.totalMs)
    }

    func testMediumModelsPropagationAndAirtimeSeparately() {
        var config = NetworkConfig.default
        config.medium = .fiber
        let fiber = NetworkEngine.calculate(config)
        config.medium = .wireless
        let radio = NetworkEngine.calculate(config)
        config.medium = .hybrid
        let hybrid = NetworkEngine.calculate(config)
        XCTAssertLessThan(radio.propagationMs, fiber.propagationMs)
        XCTAssertGreaterThan(radio.serializationMs, fiber.serializationMs)
        XCTAssertLessThan(hybrid.effectiveMbps, fiber.effectiveMbps)
        XCTAssertEqual(hybrid.route.first?.medium, .hybrid)
        XCTAssertTrue(hybrid.route.dropFirst().allSatisfy { $0.medium == .fiber })
        XCTAssertTrue(fiber.route.allSatisfy { $0.medium == .fiber })
        XCTAssertTrue(radio.route.allSatisfy { $0.medium == .wireless })
    }

    func testInvalidInputsNormalizeToFiniteBoundedMetrics() {
        var config = NetworkConfig.default
        config.sourceID = "unknown"
        config.destinationID = "unknown"
        config.bandwidthMbps = .nan
        config.latencyMs = .infinity
        config.lossPct = 100
        config.compressionPct = -20
        config.payloadMB = 1_000
        config.congestionPct = 200
        let metrics = NetworkEngine.calculate(config)
        XCTAssertEqual(metrics.config.sourceID, "san-francisco")
        XCTAssertEqual(metrics.config.destinationID, "london")
        XCTAssertEqual(metrics.config.bandwidthMbps, 100)
        XCTAssertEqual(metrics.config.latencyMs, 0)
        XCTAssertEqual(metrics.config.lossPct, 20)
        XCTAssertEqual(metrics.config.compressionPct, 0)
        XCTAssertEqual(metrics.config.payloadMB, 50)
        XCTAssertEqual(metrics.config.congestionPct, 90)
        XCTAssertTrue(metrics.totalMs.isFinite)
        XCTAssertGreaterThan(metrics.totalMs, 0)
        XCTAssertGreaterThan(metrics.effectiveMbps, 0)
    }

    func testAllNodePairsHaveFiniteConnectedRoutes() {
        for source in NetworkEngine.nodes {
            for destination in NetworkEngine.nodes where source != destination {
                var config = NetworkConfig.default
                config.sourceID = source.id
                config.destinationID = destination.id
                let metrics = NetworkEngine.calculate(config)
                XCTAssertEqual(metrics.routeNodes.first?.id, source.id)
                XCTAssertEqual(metrics.routeNodes.last?.id, destination.id)
                XCTAssertFalse(metrics.route.isEmpty)
                XCTAssertTrue(metrics.totalMs.isFinite)
            }
        }
    }

    func testTimelineIsContiguousAndEventsRespectProgress() {
        var simulation = NetworkSimulation()
        XCTAssertEqual(simulation.state.progress, 0)
        XCTAssertEqual(simulation.state.phase, "dns")
        XCTAssertEqual(simulation.state.events.count, 1)
        let phases = simulation.metrics.phases
        XCTAssertEqual(phases.first?.startMs, 0)
        XCTAssertEqual(phases.last?.endMs, simulation.metrics.totalMs)
        for (first, second) in zip(phases, phases.dropFirst()) {
            XCTAssertEqual(first.endMs, second.startMs, accuracy: 0.001)
            XCTAssertEqual(first.durationMs, first.endMs - first.startMs, accuracy: 0.001)
        }
        let halfway = simulation.advance(simulation.metrics.totalMs / 2)
        XCTAssertEqual(halfway.progress, 0.5, accuracy: 0.0001)
        XCTAssertTrue(halfway.events.allSatisfy { $0.timeMs <= halfway.elapsedMs })
        let complete = simulation.advance(simulation.metrics.totalMs)
        XCTAssertTrue(complete.complete)
        XCTAssertEqual(complete.progress, 1)
        XCTAssertEqual(complete.phase, "complete")
        XCTAssertEqual(complete.events.last?.type, "complete")
        XCTAssertTrue(complete.packets.isEmpty)
    }

    func testSimulationIsDeterministicAcrossDifferentFrameSteps() {
        var config = NetworkConfig.default
        config.lossPct = 12
        var stepped = NetworkSimulation(config: config)
        var jumped = NetworkSimulation(config: config)
        let target = stepped.metrics.phases.first { $0.id == "transfer" }!.startMs + stepped.metrics.transferMs * 0.4
        for _ in 0..<10 { stepped.advance(target / 10) }
        jumped.advance(target)
        XCTAssertEqual(stepped.state.elapsedMs, jumped.state.elapsedMs, accuracy: 0.0000001)
        XCTAssertEqual(stepped.state.phase, jumped.state.phase)
        XCTAssertEqual(stepped.state.events, jumped.state.events)
        XCTAssertEqual(stepped.state.packets.count, jumped.state.packets.count)
        for (first, second) in zip(stepped.state.packets, jumped.state.packets) {
            XCTAssertEqual(first.id, second.id)
            XCTAssertEqual(first.kind, second.kind)
            XCTAssertEqual(first.progress, second.progress, accuracy: 0.0000001)
            XCTAssertTrue((0...1).contains(first.progress))
        }
        XCTAssertFalse(jumped.state.packets.isEmpty)
    }

    func testInvalidAdvanceAndPausedReadDoNotChangeSimulation() {
        var simulation = NetworkSimulation()
        let original = simulation.state
        simulation.advance(-100)
        simulation.advance(.nan)
        simulation.advance(.infinity)
        XCTAssertEqual(simulation.state, original)
        XCTAssertEqual(simulation.state, simulation.state)
    }

    func testCompressionVisiblyReducesRepresentativeBatches() {
        func dataSamples(compression: Double) -> [Int: Double] {
            var config = NetworkConfig.default
            config.transport = .udp
            config.compressionPct = compression
            var simulation = NetworkSimulation(config: config)
            var samples: [Int: Double] = [:]
            let step = simulation.metrics.oneWayMs / 4
            while !simulation.state.complete {
                let state = simulation.advance(step)
                for packet in state.packets where packet.kind == .data && packet.id >= 10_000 {
                    samples[packet.id] = packet.sizeBytes
                }
            }
            return samples
        }
        let raw = dataSamples(compression: 0)
        let compressed = dataSamples(compression: 75)
        let highlyCompressed = dataSamples(compression: 90)
        XCTAssertEqual(raw.count, 48)
        XCTAssertEqual(compressed.count, 12)
        XCTAssertEqual(highlyCompressed.count, 6)
        XCTAssertEqual(raw.values.reduce(0, +), 5_000_000, accuracy: 0.001)
        XCTAssertEqual(compressed.values.reduce(0, +), 1_250_000, accuracy: 0.001)
        XCTAssertEqual(highlyCompressed.values.reduce(0, +), 500_000, accuracy: 0.001)
    }

    func testVisualPacketsStayVisibleWhenLongTransferIsTimeScaled() {
        var config = NetworkConfig.default
        config.transport = .udp
        config.medium = .wireless
        config.bandwidthMbps = 1
        config.congestionPct = 90
        config.payloadMB = 50
        config.compressionPct = 0
        var simulation = NetworkSimulation(config: config)
        let scale = simulation.metrics.totalMs / 16_000
        let minimumFlight = scale * 350
        var physicalFrames = 0
        var visualFrames = 0
        // 120 ms frames cover the Reduced Motion redraw interval too.
        while !simulation.state.complete {
            let snapshot = simulation.advance(scale * 120)
            XCTAssertEqual(simulation.visualPackets(minimumFlightMs: 0), snapshot.packets)
            let visual = simulation.visualPackets(minimumFlightMs: minimumFlight)
            if snapshot.packets.contains(where: { $0.kind == .data }) { physicalFrames += 1 }
            if visual.contains(where: { $0.kind == .data }) { visualFrames += 1 }
            XCTAssertTrue(visual.allSatisfy { (0...1).contains($0.progress) })
            XCTAssertEqual(snapshot, simulation.state)
        }
        XCTAssertGreaterThan(visualFrames, 100)
        XCTAssertGreaterThan(visualFrames, physicalFrames + 50)
        XCTAssertTrue(simulation.visualPackets(minimumFlightMs: minimumFlight).isEmpty)
        XCTAssertEqual(simulation.state.elapsedMs, simulation.metrics.totalMs)
    }
}
