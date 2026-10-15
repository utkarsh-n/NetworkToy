import SwiftUI
import LabKitCore
import LabKitUI

/// A striped corporate globe inside a CRT instrument. The mark is decorative;
/// projected geography, network paths and packets still follow the teaching model.
struct NetworkGlobe: View {
    let nodes: [NetworkNode]
    let route: [NetworkRouteSegment]
    let packets: [NetworkPacket]
    let sourceID: String
    let destinationID: String
    let isRunning: Bool
    var isEasterEggActive: Bool = false
    let onNodeSelect: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @State private var yaw: Double = 1.03
    @State private var pitch: Double = 0.23
    @State private var zoom: Double = 1
    @State private var orbitAnchor = Date.now
    @State private var orbitOffset = 0.0
    @State private var orbitHold: Double?
    @State private var autoOrbitEnabled = true
    @GestureState private var drag: CGSize = .zero
    @GestureState private var magnification: Double = 1

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1 / 30,
                paused: scenePhase != .active || reduceMotion || !autoOrbitEnabled || orbitHold != nil)) { timeline in
            let camera = GlobeCamera(
                size: geometry.size,
                yaw: yaw + automaticYaw(at: timeline.date) + Double(drag.width) * 0.008,
                pitch: (pitch + Double(drag.height) * 0.007).clamped(to: -1.1...1.1),
                zoom: (zoom * magnification).clamped(to: 0.78...1.5) * (isEasterEggActive ? 0.84 : 1)
            )

            Canvas(opaque: false, colorMode: .nonLinear) { context, _ in
                GlobePainter(
                    nodes: nodes,
                    route: route,
                    packets: packets,
                    sourceID: sourceID,
                    destinationID: destinationID,
                    camera: camera,
                    isRunning: isRunning,
                    isEasterEggActive: isEasterEggActive,
                    reducedMotion: reduceMotion,
                    increasedContrast: contrast == .increased
                ).draw(in: &context)
            }
            .contentShape(Rectangle())
            .gesture(rotationGesture.simultaneously(with: zoomGesture))
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    selectNode(at: value.location, camera: camera)
                }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Interactive striped network globe")
            .accessibilityValue(accessibilitySummary)
            .accessibilityHint("Drag to rotate and hold automatic motion. Pinch to zoom. City selection, rotation control, and reset are available in Actions.")
            .accessibilityActions {
                ForEach(nodes, id: \.id) { node in
                    Button("Select \(node.city)") { onNodeSelect(node.id) }
                }
                Button("Reset globe") { resetView() }
                Button(autoOrbitEnabled ? "Stop automatic globe rotation" : "Start automatic globe rotation") {
                    let now = Date.now
                    orbitOffset = automaticYaw(at: now)
                    orbitAnchor = now
                    autoOrbitEnabled.toggle()
                }
            }
            }
        }
        .onChange(of: scenePhase) { previous, _ in
            let now = Date.now
            orbitOffset = automaticYaw(at: now, animating: previous == .active && !reduceMotion && autoOrbitEnabled)
            orbitAnchor = now
        }
        .onChange(of: reduceMotion) { previous, _ in
            let now = Date.now
            orbitOffset = automaticYaw(at: now, animating: scenePhase == .active && !previous && autoOrbitEnabled)
            orbitAnchor = now
        }
    }

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 7)
            .updating($drag) { value, state, _ in state = value.translation }
            .onChanged { _ in holdOrbit() }
            .onEnded { value in
                yaw += Double(value.translation.width) * 0.008
                pitch = (pitch + Double(value.translation.height) * 0.007).clamped(to: -1.1...1.1)
                releaseOrbit()
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($magnification) { value, state, _ in state = Double(value.magnification) }
            .onChanged { _ in holdOrbit() }
            .onEnded { value in
                zoom = (zoom * Double(value.magnification)).clamped(to: 0.78...1.5)
                releaseOrbit()
            }
    }

    private func automaticYaw(at date: Date, animating: Bool? = nil) -> Double {
        if let orbitHold { return orbitHold }
        let active = animating ?? (scenePhase == .active && !reduceMotion && autoOrbitEnabled)
        return orbitOffset + (active ? max(0, date.timeIntervalSince(orbitAnchor)) * 0.048 : 0)
    }

    private func holdOrbit() {
        guard orbitHold == nil else { return }
        orbitHold = automaticYaw(at: .now)
    }

    private func releaseOrbit() {
        orbitOffset = orbitHold ?? orbitOffset
        orbitAnchor = Date.now.addingTimeInterval(10)
        orbitHold = nil
    }

    private var accessibilitySummary: String {
        let source = nodes.first { $0.id == sourceID }?.city ?? "source"
        let destination = nodes.first { $0.id == destinationID }?.city ?? "destination"
        let access = route.contains { $0.medium == .hybrid } ? " Local radio access feeds the fiber backbone." : ""
        let archive = isEasterEggActive ? " Historical Easter egg: seven regional Baby Bells surround the globe." : ""
        return "\(source) to \(destination). \(route.count) network hops. \(packets.count) representative packets.\(access)\(archive)"
    }

    private func selectNode(at point: CGPoint, camera: GlobeCamera) {
        let nearest = nodes.compactMap { node -> (NetworkNode, Double)? in
            let location = camera.rotate(.geographic(latitude: node.latitude, longitude: node.longitude))
            guard location.z > -0.02 else { return nil }
            let projected = camera.project(location * 1.018)
            return (node, hypot(Double(projected.x - point.x), Double(projected.y - point.y)))
        }.min { $0.1 < $1.1 }
        if let nearest, nearest.1 < 30 { onNodeSelect(nearest.0.id) }
    }

    private func resetView() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
            yaw = 1.03
            pitch = 0.23
            zoom = 1
            orbitOffset = 0
            orbitAnchor = .now
            orbitHold = nil
        }
    }
}

// MARK: - Projection

private struct GlobeVector: Sendable {
    var x: Double
    var y: Double
    var z: Double

    static func geographic(latitude: Double, longitude: Double) -> Self {
        let latitude = latitude * .pi / 180
        let longitude = longitude * .pi / 180
        return Self(x: cos(latitude) * sin(longitude), y: sin(latitude), z: cos(latitude) * cos(longitude))
    }

    static func * (lhs: Self, rhs: Double) -> Self {
        Self(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    func dot(_ other: Self) -> Double { x * other.x + y * other.y + z * other.z }

    var normalized: Self {
        let magnitude = sqrt(x * x + y * y + z * z)
        return magnitude > 0.00001 ? self * (1 / magnitude) : self
    }

    func interpolated(to other: Self, progress: Double) -> Self {
        let angle = acos(dot(other).clamped(to: -1...1))
        let sine = sin(angle)
        if abs(sine) < 0.0001 {
            return (self * (1 - progress) + other * progress).normalized
        }
        return self * (sin((1 - progress) * angle) / sine) + other * (sin(progress * angle) / sine)
    }
}

private struct GlobeCamera {
    let size: CGSize
    let yaw: Double
    let pitch: Double
    let zoom: Double
    private let cosineYaw: Double
    private let sineYaw: Double
    private let cosinePitch: Double
    private let sinePitch: Double

    init(size: CGSize, yaw: Double, pitch: Double, zoom: Double) {
        self.size = size
        self.yaw = yaw
        self.pitch = pitch
        self.zoom = zoom
        cosineYaw = cos(yaw)
        sineYaw = sin(yaw)
        cosinePitch = cos(pitch)
        sinePitch = sin(pitch)
    }

    var center: CGPoint { CGPoint(x: size.width * 0.5, y: size.height * 0.51) }
    var radius: Double { min(Double(size.width) * 0.382, Double(size.height) * 0.414) * zoom }

    func rotate(_ vector: GlobeVector) -> GlobeVector {
        let x = vector.x * cosineYaw + vector.z * sineYaw
        let z = -vector.x * sineYaw + vector.z * cosineYaw
        return GlobeVector(x: x, y: vector.y * cosinePitch - z * sinePitch, z: vector.y * sinePitch + z * cosinePitch)
    }

    func project(_ vector: GlobeVector) -> CGPoint {
        CGPoint(x: Double(center.x) + vector.x * radius, y: Double(center.y) - vector.y * radius)
    }

    func point(_ vector: GlobeVector) -> CGPoint { project(rotate(vector)) }

    func isVisible(_ rotated: GlobeVector) -> Bool {
        rotated.z >= -0.012 || rotated.x * rotated.x + rotated.y * rotated.y > 1.004
    }
}

private struct GlobeArc {
    let start: GlobeVector
    let end: GlobeVector
    let medium: LinkMedium
    let length: Double

    var lift: Double {
        let angle = acos(start.dot(end).clamped(to: -1...1))
        return 0.075 + min(0.23, angle * 0.105) + (medium == .wireless ? 0.025 : 0)
    }

    func vector(at progress: Double) -> GlobeVector {
        start.interpolated(to: end, progress: progress) * (1.018 + sin(progress * .pi) * lift)
    }

    func path(camera: GlobeCamera, front: Bool) -> Path {
        var path = Path()
        var connected = false
        for index in 0...72 {
            let vector = camera.rotate(vector(at: Double(index) / 72))
            let visible = front ? camera.isVisible(vector) : !camera.isVisible(vector)
            if visible {
                let point = camera.project(vector)
                if connected { path.addLine(to: point) } else { path.move(to: point) }
                connected = true
            } else {
                connected = false
            }
        }
        return path
    }
}

private struct GlobeLocalAccess {
    let source: CGPoint
    let device: CGPoint
    let labelFrame: CGRect
}

private struct GlobeBellSatellite {
    let abbreviation: String
    let center: CGPoint
    let labelFrame: CGRect
}

// MARK: - Drawing

private struct GlobePainter {
    let nodes: [NetworkNode]
    let route: [NetworkRouteSegment]
    let packets: [NetworkPacket]
    let sourceID: String
    let destinationID: String
    let camera: GlobeCamera
    let isRunning: Bool
    let isEasterEggActive: Bool
    let reducedMotion: Bool
    let increasedContrast: Bool

    private let fiber = NetTheme.fiber
    private let wireless = NetTheme.wireless
    private let packet = NetTheme.packet
    private let danger = NetTheme.danger
    private let muted = NetTheme.screenMuted
    private let globe = NetTheme.globe
    private let screen = NetTheme.screen

    private var arcs: [GlobeArc] {
        let lookup = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return route.compactMap { segment in
            guard let start = lookup[segment.from], let end = lookup[segment.to] else { return nil }
            return GlobeArc(
                start: .geographic(latitude: start.latitude, longitude: start.longitude),
                end: .geographic(latitude: end.latitude, longitude: end.longitude),
                medium: segment.medium,
                length: max(1, segment.distanceKm)
            )
        }
    }

    func draw(in context: inout GraphicsContext) {
        guard camera.radius > 0 else { return }
        let activeArcs = arcs
        drawSurroundings(in: &context)
        drawLinks(activeArcs, front: false, in: &context)
        drawOcean(in: &context)
        drawStripedSphere(in: &context)
        drawLand(in: &context)
        drawPhosphorScanlines(in: &context)
        drawLimb(in: &context)
        drawBackgroundLinks(in: &context)
        drawLinks(activeArcs, front: true, in: &context)
        drawPackets(along: activeArcs, in: &context)
        drawLocalAccess(in: &context)
        drawBellSatellites(in: &context)
        drawNodes(in: &context)
    }

    private func drawSurroundings(in context: inout GraphicsContext) {
        let radius = camera.radius
        let center = camera.center
        var graticule = Path()
        for x in stride(from: 20.0, through: Double(camera.size.width), by: 32) {
            graticule.move(to: CGPoint(x: x, y: 0))
            graticule.addLine(to: CGPoint(x: x, y: camera.size.height))
        }
        for y in stride(from: 20.0, through: Double(camera.size.height), by: 32) {
            graticule.move(to: CGPoint(x: 0, y: y))
            graticule.addLine(to: CGPoint(x: camera.size.width, y: y))
        }
        context.stroke(graticule, with: .color(muted.opacity(increasedContrast ? 0.075 : 0.035)), lineWidth: 0.5)

        let atmosphere = Path(ellipseIn: CGRect(x: Double(center.x) - radius * 1.15, y: Double(center.y) - radius * 1.15, width: radius * 2.3, height: radius * 2.3))
        context.fill(atmosphere, with: .radialGradient(
            Gradient(stops: [
                .init(color: globe.opacity(0), location: 0.72),
                .init(color: globe.opacity(0.15), location: 0.88),
                .init(color: globe.opacity(0), location: 1)
            ]), center: center, startRadius: 0, endRadius: radius * 1.15
        ))
    }

    private func drawOcean(in context: inout GraphicsContext) {
        let radius = camera.radius
        let circle = Self.circle(at: camera.center, radius: radius)
        context.fill(circle, with: .radialGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.022, green: 0.065, blue: 0.102), location: 0),
                .init(color: screen, location: 0.60),
                .init(color: Color(red: 0.01, green: 0.025, blue: 0.043), location: 1)
            ]),
            center: CGPoint(x: Double(camera.center.x) - radius * 0.30, y: Double(camera.center.y) - radius * 0.38),
            startRadius: 0, endRadius: radius * 1.62
        ))
    }

    private func drawStripedSphere(in context: inout GraphicsContext) {
        // These facets live on the same unit sphere as the continent dots.
        // The asymmetric taper belongs to a fixed world longitude, so yaw is
        // visibly a rotation of the whole object rather than a sliding overlay.
        var buckets = Array(repeating: Path(), count: 8)
        var glowInk = Path()
        for facet in GlobeStripeMesh.facets {
            let a = camera.rotate(facet.a)
            let b = camera.rotate(facet.b)
            let c = camera.rotate(facet.c)
            let d = camera.rotate(facet.d)
            guard max(max(a.z, b.z), max(c.z, d.z)) > 0 else { continue }
            let averageDepth = max(0, (a.z + b.z + c.z + d.z) / 4)
            let bucket = min(7, Int(averageDepth * 7))
            var face = Path()
            if min(min(a.z, b.z), min(c.z, d.z)) >= 0 {
                face.move(to: camera.project(a))
                face.addLine(to: camera.project(b))
                face.addLine(to: camera.project(c))
                face.addLine(to: camera.project(d))
            } else {
                let visible = clipAtHorizon([a, b, c, d])
                guard let first = visible.first else { continue }
                face.move(to: camera.project(first))
                for vertex in visible.dropFirst() { face.addLine(to: camera.project(vertex)) }
            }
            face.closeSubpath()
            buckets[bucket].addPath(face)
            glowInk.addPath(face)
        }

        // One bounded bloom pass across the batched geometry; text and controls
        // never enter this filtered context.
        var phosphor = context
        phosphor.addFilter(.shadow(color: globe.opacity(0.78), radius: min(8, camera.radius * 0.045)))
        phosphor.fill(glowInk, with: .color(globe.opacity(0.10)))
        for index in buckets.indices {
            context.fill(buckets[index], with: .color(globe.opacity(0.07 + Double(index) / 7 * 0.17)))
        }

        var edges = Path()
        for boundary in GlobeStripeMesh.boundaries { appendGridLine(to: &edges, points: boundary) }
        context.stroke(edges, with: .color(globe.opacity(0.13)), lineWidth: 3.6)
        context.stroke(edges, with: .color(globe.opacity(0.82)), style: StrokeStyle(lineWidth: 0.65, lineCap: .round))
    }

    private func clipAtHorizon(_ vertices: [GlobeVector]) -> [GlobeVector] {
        guard var previous = vertices.last else { return [] }
        var output: [GlobeVector] = []
        for current in vertices {
            let previousVisible = previous.z >= 0
            let currentVisible = current.z >= 0
            if previousVisible != currentVisible {
                let progress = previous.z / (previous.z - current.z)
                output.append(previous * (1 - progress) + current * progress)
            }
            if currentVisible { output.append(current) }
            previous = current
        }
        return output
    }

    private func drawPhosphorScanlines(in context: inout GraphicsContext) {
        var scanlines = Path()
        for y in stride(from: Double(camera.center.y) - camera.radius,
                        through: Double(camera.center.y) + camera.radius, by: 3) {
            scanlines.move(to: CGPoint(x: Double(camera.center.x) - camera.radius, y: y))
            scanlines.addLine(to: CGPoint(x: Double(camera.center.x) + camera.radius, y: y))
        }
        var raster = context
        raster.clip(to: Self.circle(at: camera.center, radius: camera.radius))
        raster.stroke(scanlines, with: .color(.black.opacity(increasedContrast ? 0.12 : 0.20)), lineWidth: 0.65)
    }

    private func drawGrid(in context: inout GraphicsContext) {
        var grid = Path()
        for latitude in stride(from: -60.0, through: 60.0, by: 30.0) {
            appendGridLine(to: &grid, points: stride(from: -180.0, through: 180.0, by: 3).map { .geographic(latitude: latitude, longitude: $0) })
        }
        for longitude in stride(from: -180.0, through: 150.0, by: 30.0) {
            appendGridLine(to: &grid, points: stride(from: -90.0, through: 90.0, by: 3).map { .geographic(latitude: $0, longitude: longitude) })
        }
        context.stroke(grid, with: .color(muted.opacity(increasedContrast ? 0.10 : 0.045)), lineWidth: 0.45)

        var equator = Path()
        appendGridLine(to: &equator, points: stride(from: -180.0, through: 180.0, by: 2).map { .geographic(latitude: 0, longitude: $0) })
        context.stroke(equator, with: .color(muted.opacity(0.035)), style: StrokeStyle(lineWidth: 0.65, dash: [1, 5]))
    }

    private func appendGridLine(to path: inout Path, points: [GlobeVector]) {
        var connected = false
        for vector in points {
            let rotated = camera.rotate(vector)
            if rotated.z > 0.012 {
                let point = camera.project(rotated)
                if connected { path.addLine(to: point) } else { path.move(to: point) }
                connected = true
            } else { connected = false }
        }
    }

    private func drawLand(in context: inout GraphicsContext) {
        // Combining similarly lit dots into paths makes the field inexpensive to redraw.
        var buckets = Array(repeating: Path(), count: 10)
        for land in GlobeLand.points {
            let rotated = camera.rotate(land.vector)
            guard rotated.z > 0.025 else { continue }
            let depth = pow(rotated.z, 0.55)
            let bucket = min(9, Int((depth * 0.82 + land.texture * 0.18) * 9))
            let dotRadius = (0.70 + land.texture * 0.27) * min(1.25, max(0.80, camera.radius / 148))
            buckets[bucket].addPath(Self.circle(at: camera.project(rotated), radius: dotRadius))
        }
        var glowPoints = Path()
        for bucket in buckets { glowPoints.addPath(bucket) }
        var phosphor = context
        phosphor.addFilter(.shadow(color: Color.cyan.opacity(0.48), radius: 2))
        phosphor.fill(glowPoints, with: .color(Color.cyan.opacity(0.22)))
        for index in buckets.indices {
            let opacity = (increasedContrast ? 0.30 : 0.22) + Double(index) / 9 * 0.47
            context.fill(buckets[index], with: .color(Color.cyan.opacity(opacity)))
        }
    }

    private func drawLimb(in context: inout GraphicsContext) {
        let limb = Self.circle(at: camera.center, radius: camera.radius)
        context.stroke(limb, with: .color(globe.opacity(0.12)), lineWidth: 6)
        context.stroke(limb, with: .linearGradient(
            Gradient(colors: [globe.opacity(0.75), globe.opacity(0.10), globe.opacity(0.48)]),
            startPoint: CGPoint(x: Double(camera.center.x) - camera.radius, y: Double(camera.center.y) - camera.radius),
            endPoint: CGPoint(x: Double(camera.center.x) + camera.radius, y: Double(camera.center.y) + camera.radius)
        ), lineWidth: 0.85)
    }

    private func drawBackgroundLinks(in context: inout GraphicsContext) {
        guard nodes.count > 2 else { return }
        // The faint topology uses the same teaching graph as routing, so every
        // visible connection can actually participate in a simulated journey.
        let lookup = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (from, to) in NetworkEngine.backboneLinks {
            guard let start = lookup[from], let end = lookup[to] else { continue }
            if route.contains(where: { ($0.from == from && $0.to == to) || ($0.from == to && $0.to == from) }) { continue }
            let arc = GlobeArc(
                start: .geographic(latitude: start.latitude, longitude: start.longitude),
                end: .geographic(latitude: end.latitude, longitude: end.longitude),
                medium: .fiber,
                length: 1
            )
            context.stroke(arc.path(camera: camera, front: true), with: .color(fiber.opacity(0.055)), lineWidth: 0.6)
        }
    }

    private func drawLinks(_ arcs: [GlobeArc], front: Bool, in context: inout GraphicsContext) {
        for arc in arcs {
            let path = arc.path(camera: camera, front: front)
            let color = arc.medium == .wireless ? wireless : fiber
            let opacity = front ? 0.82 : 0.13
            let dashes: [CGFloat] = arc.medium == .wireless ? [3, 5] : []
            if front {
                context.stroke(path, with: .color(color.opacity(0.085)), style: StrokeStyle(lineWidth: 7, lineCap: .round, dash: dashes))
                context.stroke(path, with: .color(color.opacity(0.14)), style: StrokeStyle(lineWidth: 3.7, lineCap: .round, dash: dashes))
            }
            context.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: front ? 1.25 : 0.8, lineCap: .round, dash: dashes))
        }
    }

    private var localAccess: GlobeLocalAccess? {
        guard route.contains(where: { $0.from == sourceID && $0.medium == .hybrid }),
              let source = nodes.first(where: { $0.id == sourceID }) else { return nil }
        let vector = camera.rotate(GlobeVector.geographic(latitude: source.latitude, longitude: source.longitude) * 1.018)
        guard vector.z > 0.02 else { return nil }
        let point = camera.project(vector)
        guard point.x > 7, point.x < camera.size.width - 7,
              point.y > 7, point.y < camera.size.height - 7 else { return nil }
        let side = point.x < camera.center.x ? -1.0 : 1.0
        let below = point.y < camera.size.height * 0.64
        let device = CGPoint(
            x: (Double(point.x) + side * 27).clamped(to: 20...max(20, Double(camera.size.width) - 20)),
            y: (Double(point.y) + (below ? 23 : -28)).clamped(to: 22...max(22, Double(camera.size.height) - 49))
        )
        let labelWidth = 88.0
        let labelX = (Double(device.x) - labelWidth / 2).clamped(to: 5...max(5, Double(camera.size.width) - labelWidth - 5))
        return GlobeLocalAccess(source: point, device: device,
            labelFrame: CGRect(x: labelX, y: Double(device.y) + 12, width: labelWidth, height: 15))
    }

    private func drawLocalAccess(in context: inout GraphicsContext) {
        guard let access = localAccess else { return }
        // The access spur is enlarged to stay legible. It represents the model's
        // local 5 km radio tail, while the long globe arc remains fiber.
        var spur = Path()
        spur.move(to: access.device)
        spur.addQuadCurve(to: access.source,
            control: CGPoint(x: (access.source.x + access.device.x) / 2, y: min(access.source.y, access.device.y) - 7))
        context.stroke(spur, with: .color(wireless.opacity(0.12)), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [2, 3]))
        context.stroke(spur, with: .color(wireless.opacity(0.88)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2, 3]))

        let deviceFrame = CGRect(x: access.device.x - 4, y: access.device.y - 6, width: 8, height: 12)
        context.fill(Path(roundedRect: deviceFrame, cornerRadius: 2), with: .color(screen))
        context.stroke(Path(roundedRect: deviceFrame, cornerRadius: 2), with: .color(wireless.opacity(0.92)), lineWidth: 1)
        context.fill(Self.circle(at: CGPoint(x: access.device.x, y: access.device.y + 3.5), radius: 0.7), with: .color(wireless))
        for radius in [5.0, 8.0] {
            var wave = Path()
            wave.addArc(center: CGPoint(x: access.device.x, y: access.device.y - 6), radius: radius,
                startAngle: .degrees(-135), endAngle: .degrees(-45), clockwise: false)
            context.stroke(wave, with: .color(wireless.opacity(radius == 5 ? 0.66 : 0.38)), lineWidth: 0.8)
        }

        context.fill(Path(roundedRect: access.labelFrame, cornerRadius: 3), with: .color(screen.opacity(0.94)))
        let label = Text("LOCAL RADIO").font(.system(size: 7, weight: .medium, design: .monospaced)).tracking(0.8)
            .foregroundColor(wireless.opacity(0.9))
        context.draw(label, at: CGPoint(x: access.labelFrame.midX, y: access.labelFrame.midY))
    }

    private var bellSatellites: [GlobeBellSatellite] {
        guard isEasterEggActive else { return [] }
        let abbreviations = ["AMER", "B ATL", "BSOUTH", "NYNEX", "PAC TEL", "SW BELL", "US WEST"]
        let orbitX = min(camera.radius * 1.48, Double(camera.size.width) * 0.425)
        let orbitY = min(camera.radius * 1.17, Double(camera.size.height) * 0.32)
        let labelWidth = min(60, Double(camera.size.width) * 0.16)
        return abbreviations.enumerated().map { index, abbreviation in
            let phase = -.pi / 2 + Double(index) / 7 * 2 * .pi
            let center = CGPoint(x: Double(camera.center.x) + cos(phase) * orbitX,
                y: Double(camera.center.y) + sin(phase) * orbitY)
            let labelX = (Double(center.x) - labelWidth / 2).clamped(to: 5...max(5, Double(camera.size.width) - labelWidth - 5))
            let labelY = Double(center.y) + (center.y < camera.center.y - 10 ? -26 : 16)
            return GlobeBellSatellite(abbreviation: abbreviation, center: center,
                labelFrame: CGRect(x: labelX, y: labelY, width: labelWidth, height: 12))
        }
    }

    private func drawBellSatellites(in context: inout GraphicsContext) {
        let satellites = bellSatellites
        guard !satellites.isEmpty else { return }
        let orbitX = min(camera.radius * 1.48, Double(camera.size.width) * 0.425)
        let orbitY = min(camera.radius * 1.17, Double(camera.size.height) * 0.32)
        let orbit = Path(ellipseIn: CGRect(x: Double(camera.center.x) - orbitX,
            y: Double(camera.center.y) - orbitY, width: orbitX * 2, height: orbitY * 2))
        context.stroke(orbit, with: .color(globe.opacity(0.28)), style: StrokeStyle(lineWidth: 0.6, dash: [1, 5]))

        for satellite in satellites {
            context.fill(Self.circle(at: satellite.center, radius: 12), with: .color(screen))
            context.stroke(Self.circle(at: satellite.center, radius: 12), with: .color(globe.opacity(0.84)), lineWidth: 1)

            let x = satellite.center.x
            let y = satellite.center.y
            var bell = Path()
            bell.move(to: CGPoint(x: x - 5, y: y + 3))
            bell.addLine(to: CGPoint(x: x - 3.8, y: y + 0.9))
            bell.addQuadCurve(to: CGPoint(x: x - 3.4, y: y - 4), control: CGPoint(x: x - 3.8, y: y - 2))
            bell.addQuadCurve(to: CGPoint(x: x, y: y - 6.5), control: CGPoint(x: x - 2.8, y: y - 6.5))
            bell.addQuadCurve(to: CGPoint(x: x + 3.4, y: y - 4), control: CGPoint(x: x + 2.8, y: y - 6.5))
            bell.addQuadCurve(to: CGPoint(x: x + 3.8, y: y + 0.9), control: CGPoint(x: x + 3.8, y: y - 2))
            bell.addLine(to: CGPoint(x: x + 5, y: y + 3))
            bell.closeSubpath()
            context.stroke(bell, with: .color(Color.white.opacity(0.90)), style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))
            context.fill(Self.circle(at: CGPoint(x: x, y: y + 5), radius: 1.25), with: .color(Color.white.opacity(0.90)))
            context.fill(Self.circle(at: CGPoint(x: x, y: y - 7.5), radius: 0.85), with: .color(Color.white.opacity(0.90)))

            context.fill(Path(roundedRect: satellite.labelFrame, cornerRadius: 1), with: .color(screen.opacity(0.96)))
            let label = Text(satellite.abbreviation).font(.system(size: 7, weight: .semibold, design: .monospaced))
                .tracking(0.35).foregroundColor(Color.white.opacity(0.79))
            context.draw(label, at: CGPoint(x: satellite.labelFrame.midX, y: satellite.labelFrame.midY))
        }
    }

    private func drawPackets(along arcs: [GlobeArc], in context: inout GraphicsContext) {
        guard !arcs.isEmpty else { return }
        let totalDistance = arcs.reduce(0) { $0 + $1.length }
        for item in packets.prefix(80) {
            let distance = item.progress.clamped(to: 0...1) * totalDistance
            var consumed = 0.0
            for (index, arc) in arcs.enumerated() {
                guard distance <= consumed + arc.length || index == arcs.count - 1 else {
                    consumed += arc.length
                    continue
                }
                let progress = ((distance - consumed) / arc.length).clamped(to: 0...1)
                let vector = camera.rotate(arc.vector(at: progress))
                guard camera.isVisible(vector) else { break }
                let point = camera.project(vector)
                let color: Color = item.kind == .lost ? danger : item.kind == .retry ? wireless : item.kind == .ack ? fiber : packet
                context.fill(Self.circle(at: point, radius: item.kind == .lost ? 8 : 9), with: .color(color.opacity(0.105)))

                if !reducedMotion && item.kind != .lost {
                    for tail in 1...3 {
                        let tailDirection = item.kind == .ack ? 1.0 : -1.0
                        let tailProgress = (progress + tailDirection * Double(tail) * 0.016).clamped(to: 0...1)
                        let tailVector = camera.rotate(arc.vector(at: tailProgress))
                        guard camera.isVisible(tailVector) else { continue }
                        context.fill(Self.circle(at: camera.project(tailVector), radius: 2.4 - Double(tail) * 0.45), with: .color(color.opacity(0.36 - Double(tail) * 0.08)))
                    }
                }

                switch item.kind {
                case .lost:
                    var cross = Path()
                    cross.move(to: CGPoint(x: point.x - 3, y: point.y - 3))
                    cross.addLine(to: CGPoint(x: point.x + 3, y: point.y + 3))
                    cross.move(to: CGPoint(x: point.x + 3, y: point.y - 3))
                    cross.addLine(to: CGPoint(x: point.x - 3, y: point.y + 3))
                    context.stroke(cross, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                case .ack:
                    context.stroke(Self.circle(at: point, radius: 2.8), with: .color(color), lineWidth: 1.5)
                case .retry:
                    var triangle = Path()
                    triangle.move(to: CGPoint(x: point.x, y: point.y - 3.7))
                    triangle.addLine(to: CGPoint(x: point.x + 3.4, y: point.y + 2.6))
                    triangle.addLine(to: CGPoint(x: point.x - 3.4, y: point.y + 2.6))
                    triangle.closeSubpath()
                    context.fill(triangle, with: .color(color))
                case .data:
                    context.fill(Self.circle(at: point, radius: 2.9), with: .color(color))
                    context.fill(Self.circle(at: point, radius: 1.2), with: .color(.white.opacity(0.9)))
                }
                break
            }
        }
    }

    private func drawNodes(in context: inout GraphicsContext) {
        struct Marker {
            let node: NetworkNode
            let point: CGPoint
            let depth: Double
            let selected: Bool
        }

        let markers = nodes.compactMap { node -> Marker? in
            let rotated = camera.rotate(GlobeVector.geographic(latitude: node.latitude, longitude: node.longitude) * 1.018)
            guard rotated.z > -0.03 else { return nil }
            return Marker(node: node, point: camera.project(rotated), depth: rotated.z, selected: node.id == sourceID || node.id == destinationID)
        }.sorted { lhs, rhs in
            if lhs.selected != rhs.selected { return lhs.selected }
            return lhs.depth > rhs.depth
        }

        var labelFrames = (localAccess.map { [$0.labelFrame] } ?? []) + bellSatellites.map(\.labelFrame)
        for marker in markers {
            let color = marker.selected ? Color.white.opacity(0.94) : muted
            let opacity = marker.selected ? 1.0 : 0.32 + max(0, marker.depth) * 0.5
            if marker.selected {
                context.fill(Self.circle(at: marker.point, radius: 15), with: .color(Color.white.opacity(0.055)))
                context.stroke(Self.circle(at: marker.point, radius: isRunning ? 10 : 8.5), with: .color(Color.white.opacity(0.30)), lineWidth: 0.7)
            }
            context.fill(Self.circle(at: marker.point, radius: marker.selected ? 5.0 : 3.6), with: .color(screen))
            context.stroke(Self.circle(at: marker.point, radius: marker.selected ? 5.0 : 3.6), with: .color(color.opacity(opacity)), lineWidth: marker.selected ? 1.4 : 0.9)
            if marker.node.id == destinationID {
                var diamond = Path()
                diamond.move(to: CGPoint(x: marker.point.x, y: marker.point.y - 2.4))
                diamond.addLine(to: CGPoint(x: marker.point.x + 2.4, y: marker.point.y))
                diamond.addLine(to: CGPoint(x: marker.point.x, y: marker.point.y + 2.4))
                diamond.addLine(to: CGPoint(x: marker.point.x - 2.4, y: marker.point.y))
                diamond.closeSubpath()
                context.fill(diamond, with: .color(color))
            } else {
                context.fill(Self.circle(at: marker.point, radius: marker.selected ? 2 : 1.2), with: .color(color.opacity(opacity)))
            }

            guard marker.selected || marker.depth > 0.23 else { continue }
            let label = marker.node.label.isEmpty ? marker.node.city : marker.node.label
            let text = Text(label)
                .font(.system(size: marker.selected ? 10.5 : 9, weight: marker.selected ? .semibold : .medium, design: .monospaced))
                .foregroundColor(marker.selected ? Color.white.opacity(0.91) : muted.opacity(0.82))
            let resolved = context.resolve(text)
            let measured = resolved.measure(in: CGSize(width: 120, height: 40))
            let labelSize = CGSize(width: measured.width + 8, height: measured.height + 5)
            let right = marker.point.x < camera.center.x ? false : true
            let offsets: [(Bool, CGFloat)] = [(right, -17), (!right, -17), (right, 12), (!right, 12), (right, -30)]
            for (placeRight, yOffset) in offsets {
                let x = placeRight ? marker.point.x + 12 : marker.point.x - labelSize.width - 12
                let y = marker.point.y + yOffset - labelSize.height / 2
                let rect = CGRect(x: x, y: y, width: labelSize.width, height: labelSize.height)
                guard rect.minX > 5, rect.maxX < camera.size.width - 5, rect.minY > 5, rect.maxY < camera.size.height - 5 else { continue }
                guard !labelFrames.contains(where: { $0.insetBy(dx: -3, dy: -3).intersects(rect) }) else { continue }
                labelFrames.append(rect)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(screen.opacity(marker.selected ? 0.94 : 0.86)))
                context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY))
                var leader = Path()
                leader.move(to: marker.point)
                leader.addLine(to: CGPoint(x: placeRight ? rect.minX - 3 : rect.maxX + 3, y: rect.midY))
                context.stroke(leader, with: .color(color.opacity(marker.selected ? 0.38 : 0.17)), lineWidth: 0.5)
                break
            }
        }
    }

    private static func circle(at center: CGPoint, radius: Double) -> Path {
        Path(ellipseIn: CGRect(x: Double(center.x) - radius, y: Double(center.y) - radius, width: radius * 2, height: radius * 2))
    }

    private static func noise(_ seed: Int) -> Double {
        let value = sin(Double(seed) * 12.9898) * 43758.5453
        return value - floor(value)
    }
}

// MARK: - World-attached stripe geometry

private enum GlobeStripeMesh {
    struct Facet: Sendable {
        let a: GlobeVector
        let b: GlobeVector
        let c: GlobeVector
        let d: GlobeVector
    }

    private static let segments = 120

    static let facets: [Facet] = {
        var output: [Facet] = []
        output.reserveCapacity(13 * segments)
        for stripe in 0..<13 {
            let height = 0.98 - Double(stripe) * (1.96 / 12)
            for segment in 0..<segments {
                let longitude = -Double.pi + Double(segment) / Double(segments) * 2 * .pi
                let nextLongitude = -Double.pi + Double(segment + 1) / Double(segments) * 2 * .pi
                let first = edges(height: height, longitude: longitude)
                let next = edges(height: height, longitude: nextLongitude)
                output.append(Facet(a: first.0, b: next.0, c: next.1, d: first.1))
            }
        }
        return output
    }()

    static let boundaries: [[GlobeVector]] = {
        var output: [[GlobeVector]] = []
        for stripe in 0..<13 {
            let height = 0.98 - Double(stripe) * (1.96 / 12)
            var north: [GlobeVector] = []
            var south: [GlobeVector] = []
            for segment in 0...segments {
                let longitude = -Double.pi + Double(segment) / Double(segments) * 2 * .pi
                let points = edges(height: height, longitude: longitude)
                north.append(points.0)
                south.append(points.1)
            }
            output.append(north)
            output.append(south)
        }
        return output
    }()

    private static func edges(height: Double, longitude: Double) -> (GlobeVector, GlobeVector) {
        let angle = longitude + 82 * Double.pi / 180
        let longitudeDistance = atan2(sin(angle), cos(angle))
        let highlight = exp(-pow(longitudeDistance / 0.70, 2)) * exp(-pow((height - 0.28) / 0.64, 2))
        let halfThickness = (0.115 - highlight * 0.067) / 2
        return (point(height: height + halfThickness, longitude: longitude),
                point(height: height - halfThickness, longitude: longitude))
    }

    private static func point(height: Double, longitude: Double) -> GlobeVector {
        let y = height.clamped(to: -0.999_999...0.999_999)
        let horizontalRadius = sqrt(max(0, 1 - y * y))
        return GlobeVector(x: horizontalRadius * sin(longitude), y: y, z: horizontalRadius * cos(longitude))
    }
}

// MARK: - Schematic continents

private enum GlobeLand {
    struct Dot: Sendable {
        let vector: GlobeVector
        let texture: Double
    }

    private struct Region: Sendable {
        let polygon: [(Double, Double)]
        let west: Double
        let east: Double
        let south: Double
        let north: Double

        init(_ polygon: [(Double, Double)]) {
            self.polygon = polygon
            west = polygon.map { $0.0 }.min() ?? 0
            east = polygon.map { $0.0 }.max() ?? 0
            south = polygon.map { $0.1 }.min() ?? 0
            north = polygon.map { $0.1 }.max() ?? 0
        }

        func contains(longitude: Double, latitude: Double) -> Bool {
            guard longitude >= west, longitude <= east, latitude >= south, latitude <= north else { return false }
            return GlobeLand.contains(longitude: longitude, latitude: latitude, polygon: polygon)
        }
    }

    private static let regions = polygons.map(Region.init)

    /// Coarse geography is intentional: this is a network instrument, not a map.
    /// Longitude/latitude polygons are sampled once rather than rebuilt every frame.
    static let points: [Dot] = {
        var dots: [Dot] = []
        for latitude in stride(from: -80.0, through: 82.0, by: 1.65) {
            let spacing = 1.65 / max(0.28, cos(latitude * .pi / 180))
            for longitude in stride(from: -179.0, through: 179.0, by: spacing) {
                let noise = sin(latitude * 17.31 + longitude * 7.97) * 43758.5453
                let texture = noise - floor(noise)
                let jitterLatitude = latitude + (texture - 0.5) * 0.44
                let jitterLongitude = longitude + (texture - 0.5) * 0.44
                if regions.contains(where: { $0.contains(longitude: jitterLongitude, latitude: jitterLatitude) }) {
                    dots.append(Dot(vector: .geographic(latitude: jitterLatitude, longitude: jitterLongitude), texture: texture))
                }
            }
        }
        return dots
    }()

    private static func contains(longitude: Double, latitude: Double, polygon: [(Double, Double)]) -> Bool {
        var inside = false
        var previous = polygon.count - 1
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[previous]
            if (a.1 > latitude) != (b.1 > latitude), longitude < (b.0 - a.0) * (latitude - a.1) / (b.1 - a.1) + a.0 {
                inside.toggle()
            }
            previous = index
        }
        return inside
    }

    private static let polygons: [[(Double, Double)]] = [
        [(-168, 71), (-147, 72), (-130, 62), (-122, 51), (-125, 41), (-117, 32), (-106, 23), (-97, 17), (-84, 8), (-77, 9), (-82, 18), (-81, 25), (-75, 38), (-66, 45), (-53, 52), (-56, 61), (-79, 63), (-95, 72), (-125, 74), (-145, 70)],
        [(-64, 60), (-43, 59), (-21, 75), (-30, 83), (-52, 83), (-65, 73)],
        [(-81, 12), (-65, 10), (-50, 3), (-35, -8), (-40, -22), (-51, -31), (-64, -55), (-71, -53), (-76, -36), (-81, -6)],
        [(-10, 36), (-10, 44), (-5, 49), (7, 53), (9, 60), (20, 71), (31, 71), (42, 58), (36, 45), (29, 41), (23, 35), (15, 38), (8, 43), (2, 39)],
        [(-6, 50), (1, 50), (0, 58), (-5, 59), (-7, 55)],
        [(-10, 51), (-6, 51), (-6, 55), (-10, 56)],
        [(-24, 63), (-13, 63), (-15, 67), (-23, 66)],
        [(28, 42), (38, 54), (60, 62), (78, 72), (120, 73), (157, 66), (179, 61), (173, 51), (148, 46), (145, 38), (132, 32), (121, 22), (110, 20), (107, 8), (102, 2), (98, 9), (92, 22), (79, 8), (70, 24), (53, 27), (42, 35)],
        [(-18, 35), (3, 37), (14, 33), (32, 32), (43, 12), (51, 12), (44, -11), (34, -26), (20, -35), (13, -32), (8, -19), (-7, 5), (-16, 13)],
        [(43, -12), (50, -14), (49, -24), (44, -26)],
        [(113, -22), (122, -13), (132, -12), (138, -17), (145, -15), (153, -26), (148, -39), (133, -35), (116, -35)],
        [(130, 31), (134, 32), (137, 35), (141, 38), (142, 42), (146, 45), (142, 46), (138, 41), (135, 36), (131, 34)],
        [(121, 22), (123, 25), (121, 26), (120, 23)],
        [(95, 5), (106, -6), (104, -7), (98, -1)],
        [(108, 6), (119, 7), (119, -4), (112, -4)],
        [(106, -6), (116, -8), (115, -10), (106, -8)],
        [(130, -3), (145, -3), (151, -9), (141, -10), (133, -7)],
        [(166, -45), (173, -40), (178, -36), (179, -39), (172, -46), (167, -47)],
        [(-180, -74), (-135, -71), (-90, -74), (-60, -64), (-45, -71), (0, -72), (45, -68), (90, -71), (135, -73), (179, -74), (179, -89), (-180, -89)]
    ]
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { min(range.upperBound, max(range.lowerBound, self)) }
}
