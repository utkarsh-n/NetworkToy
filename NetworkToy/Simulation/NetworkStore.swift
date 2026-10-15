import Foundation
import Observation

@MainActor @Observable
final class NetworkStore {
    var config = NetworkConfig() {
        didSet {
            guard config != oldValue else { return }
            metrics = NetworkEngine.calculate(config)
            simulation = nil
            snapshot = nil
            renderedPackets = []
            isRunning = false
            hasRun = false
        }
    }
    private(set) var metrics: NetworkMetrics
    private(set) var snapshot: NetworkState?
    private(set) var renderedPackets: [NetworkPacket] = []
    private(set) var isRunning = false
    private(set) var hasRun = false
    var playbackSpeed = 1.0
    private var simulation: NetworkSimulation?

    init() { metrics = NetworkEngine.calculate(NetworkConfig()) }

    var progress: Double { snapshot?.progress ?? 0 }
    var phaseTitle: String { snapshot?.phaseLabel ?? "Ready to send" }
    var complete: Bool { snapshot?.complete ?? false }
    var visualScale: Double {
        let visualSeconds = min(16, max(8, metrics.totalMs / 1000))
        return metrics.totalMs / (visualSeconds * 1000)
    }

    func toggleRun() {
        if isRunning { isRunning = false; return }
        if simulation == nil || complete {
            simulation = NetworkSimulation(config: config)
            snapshot = simulation?.state
            hasRun = true
        }
        isRunning = true
    }

    func tick(seconds: Double) {
        guard isRunning, var run = simulation else { return }
        snapshot = run.advance(seconds * 1000 * visualScale * playbackSpeed)
        renderedPackets = run.visualPackets(minimumFlightMs: visualScale * 350)
        simulation = run
        if snapshot?.complete == true { isRunning = false }
    }

    func reset() {
        isRunning = false
        simulation = nil
        snapshot = nil
        renderedPackets = []
        hasRun = false
    }

    func chooseNode(_ id: String) {
        guard id != config.sourceID else { return }
        config.destinationID = id
    }

    func setMedium(_ medium: LinkMedium) {
        // Medium changes routing only. Capacity and loss stay independently adjustable.
        config.medium = medium
    }

    func preset(_ preset: NetworkExperiment) {
        var next = NetworkConfig()
        next.destinationID = "london"
        switch preset {
        case .acrossTheOcean:
            next.medium = .fiber; next.bandwidthMbps = 500; next.payloadMB = 10
        case .busyAirwaves:
            next.medium = .hybrid; next.bandwidthMbps = 25; next.lossPct = 5
            next.congestionPct = 65; next.transport = .tcp
        case .smallIsFast:
            next.medium = .fiber; next.bandwidthMbps = 5; next.payloadMB = 20
            next.compressionPct = 70; next.transport = .quic
        }
        config = next
    }
}

enum NetworkExperiment: String, CaseIterable, Identifiable {
    case acrossTheOcean, busyAirwaves, smallIsFast
    var id: String { rawValue }
    var title: String {
        switch self {
        case .acrossTheOcean: "Across the ocean"
        case .busyAirwaves: "Busy airwaves"
        case .smallIsFast: "Small is fast"
        }
    }
    var icon: String {
        switch self {
        case .acrossTheOcean: "water.waves"
        case .busyAirwaves: "antenna.radiowaves.left.and.right"
        case .smallIsFast: "arrow.down.right.and.arrow.up.left"
        }
    }
    var detail: String {
        switch self {
        case .acrossTheOcean: "A wide fiber pipe still has a long journey. Try increasing capacity, then compare the round trip."
        case .busyAirwaves: "Shared capacity and 5% loss. Compare TCP, raw UDP, and QUIC to see what recovery costs."
        case .smallIsFast: "A 20 MB payload on a narrow link. Turn compression down and watch bytes and transfer time grow."
        }
    }
}
