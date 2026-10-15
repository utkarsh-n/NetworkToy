import SwiftUI

/// A procedural stripe mark shared by the terminal badge and its archive.
/// Band widths grow towards the base, recalling the dimensional 1980s globe.
struct BellStripeMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for index in 0..<12 {
            let y = -0.93 + Double(index) * 0.165
            let halfWidth = sqrt(max(0, 1 - y * y)) * radius
            let height = (0.035 + Double(index) * 0.0035) * radius
            path.addRoundedRect(in: CGRect(x: center.x - halfWidth,
                y: center.y + y * radius - height / 2, width: 2 * halfWidth, height: height),
                cornerSize: CGSize(width: height / 2, height: height / 2))
        }
        return path
    }
}

struct BellConsoleBackground: View {
    var body: some View {
        NetTheme.background
            .overlay {
                RadialGradient(colors: [NetTheme.globe.opacity(0.055), .clear],
                    center: .top, startRadius: 0, endRadius: 620)
            }
            .overlay {
                Canvas { context, size in
                    var lines = Path()
                    for y in stride(from: CGFloat(0), through: size.height, by: 4) {
                        lines.move(to: CGPoint(x: 0, y: y))
                        lines.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(lines, with: .color(.black.opacity(0.13)), lineWidth: 0.5)
                }
            }
            .ignoresSafeArea().accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct BellScrew: View {
    var body: some View {
        Circle().fill(NetTheme.screenMuted.opacity(0.13)).frame(width: 6, height: 6)
            .overlay { Circle().stroke(NetTheme.screenMuted.opacity(0.24), lineWidth: 0.5) }
            .overlay { Capsule().fill(.black.opacity(0.7)).frame(width: 4, height: 0.7).rotationEffect(.degrees(-35)) }
            .accessibilityHidden(true)
    }
}
