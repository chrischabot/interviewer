import SwiftUI

// MARK: - Plasma Orb View

/// A flowing plasma orb visualization that responds to audio levels.
/// Plasma tendrils flow slowly like a lava lamp, then excite with voice.
struct VoiceOrbView: View {
    let audioLevel: CGFloat  // 0.0 to 1.0
    let isActive: Bool       // Whether AI is currently speaking
    let isListening: Bool    // Whether listening to user

    private var clampedLevel: CGFloat {
        min(max(audioLevel, 0), 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/60)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 * 0.42

                // Base animation always runs - never stops
                // Audio just adds extra intensity on top
                let baseSpeed = 0.25  // Always-visible lava lamp flow
                let audioBoost = Double(clampedLevel) * 0.6  // Extra speed from audio
                let speed = baseSpeed + audioBoost

                // Color - always blue/cyan
                let hue = 0.55  // Cyan/blue always

                // Global spin - always rotating, audio adds extra spin
                let baseSpin = time * 0.12  // Always-visible base spin
                let audioSpin = Double(clampedLevel) * time * 0.2  // Extra spin from audio
                let globalSpin = baseSpin + audioSpin

                // Layer 1: Outer glow
                drawGlow(context: context, center: center, radius: radius, hue: hue)

                // Layer 2: Sphere shell (subtle boundary)
                drawSphereShell(context: context, center: center, radius: radius, hue: hue)

                // Layer 3: Plasma tendrils on the sphere surface
                // Glow pass
                var glowCtx = context
                glowCtx.addFilter(.blur(radius: 6))
                drawPlasmaTendrils(
                    context: glowCtx,
                    center: center,
                    radius: radius,
                    time: time,
                    speed: speed,
                    hue: hue,
                    lineWidth: 3.5,
                    globalSpin: globalSpin
                )

                // Sharp pass
                drawPlasmaTendrils(
                    context: context,
                    center: center,
                    radius: radius,
                    time: time,
                    speed: speed,
                    hue: hue,
                    lineWidth: 1.5,
                    globalSpin: globalSpin
                )

                // Layer 4: Highlight
                drawHighlight(context: context, center: center, radius: radius)

            }
        }
        .frame(width: 80, height: 80)
    }

    // MARK: - Glow

    private func drawGlow(context: GraphicsContext, center: CGPoint, radius: CGFloat, hue: Double) {
        var ctx = context
        ctx.opacity = 0.4
        ctx.addFilter(.blur(radius: 12))

        let r = radius * 1.5
        ctx.fill(
            Circle().path(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(
                Gradient(colors: [
                    Color(hue: hue, saturation: 0.8, brightness: 1.0),
                    Color(hue: hue, saturation: 0.5, brightness: 0.6).opacity(0.5),
                    .clear
                ]),
                center: center,
                startRadius: 0,
                endRadius: r
            )
        )
    }

    // MARK: - Sphere Shell

    private func drawSphereShell(context: GraphicsContext, center: CGPoint, radius: CGFloat, hue: Double) {
        // Draw a subtle sphere outline
        var ctx = context
        ctx.opacity = 0.15

        ctx.stroke(
            Circle().path(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(Color(hue: hue, saturation: 0.6, brightness: 0.9)),
            lineWidth: 1
        )

        // Inner gradient for depth
        ctx.opacity = 0.1
        ctx.fill(
            Circle().path(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [
                    .clear,
                    Color(hue: hue, saturation: 0.5, brightness: 0.8).opacity(0.3)
                ]),
                center: center,
                startRadius: radius * 0.3,
                endRadius: radius
            )
        )
    }

    // MARK: - Plasma Tendrils

    private func drawPlasmaTendrils(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        speed: Double,
        hue: Double,
        lineWidth: CGFloat,
        globalSpin: Double
    ) {
        // Draw multiple great circles (tendrils) on the sphere surface
        let tendrilCount = 5

        for i in 0..<tendrilCount {
            let tiltX = Double(i) * 0.4 - 0.8  // Different tilts for each tendril
            let tiltZ = Double(i) * 0.3 - 0.4
            let phase = Double(i) * .pi * 2 / Double(tendrilCount)

            drawSingleTendril(
                context: context,
                center: center,
                radius: radius,
                time: time,
                speed: speed,
                hue: hue,
                tiltX: tiltX,
                tiltZ: tiltZ,
                phase: phase,
                lineWidth: lineWidth,
                globalSpin: globalSpin
            )
        }
    }

    private func drawSingleTendril(
        context: GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        speed: Double,
        hue: Double,
        tiltX: Double,
        tiltZ: Double,
        phase: Double,
        lineWidth: CGFloat,
        globalSpin: Double
    ) {
        let segments = 60
        var points: [(CGPoint, CGFloat)] = []  // Point and opacity based on depth

        // Global rotation that affects all tendrils (the lava lamp flow)
        let globalRotation = time * speed

        for seg in 0...segments {
            let t = Double(seg) / Double(segments)
            let theta = t * .pi * 2  // Go around the circle

            // Start with a point on a unit circle in the XY plane
            var x = cos(theta)
            var y = sin(theta)
            var z = 0.0

            // Rotate around X axis (tilt the circle)
            let cosX = cos(tiltX)
            let sinX = sin(tiltX)
            let y1 = y * cosX - z * sinX
            let z1 = y * sinX + z * cosX
            y = y1
            z = z1

            // Rotate around Z axis (another tilt)
            let cosZ = cos(tiltZ)
            let sinZ = sin(tiltZ)
            let x2 = x * cosZ - y * sinZ
            let y2 = x * sinZ + y * cosZ
            x = x2
            y = y2

            // Apply global Y rotation (the continuous flow)
            let rotY = globalRotation + phase
            let cosY = cos(rotY)
            let sinY = sin(rotY)
            let x3 = x * cosY + z * sinY
            let z3 = -x * sinY + z * cosY
            x = x3
            z = z3

            // Apply global spin (X axis rotation) when audio is active
            if globalSpin != 0 {
                let cosS = cos(globalSpin)
                let sinS = sin(globalSpin)
                let y4 = y * cosS - z * sinS
                let z4 = y * sinS + z * cosS
                y = y4
                z = z4
            }

            // Add subtle wave distortion for organic feel
            let wave = sin(theta * 3 + time * speed * 2 + phase) * 0.08
            let waveRadius = 1.0 + wave

            // Project to 2D (orthographic)
            let screenX = center.x + CGFloat(x * waveRadius) * radius
            let screenY = center.y + CGFloat(y * waveRadius) * radius

            // Depth for opacity (z: -1 to 1, map to 0 to 1)
            let depth = CGFloat((z + 1) / 2)

            points.append((CGPoint(x: screenX, y: screenY), depth))
        }

        // Draw the tendril as segments with depth-based opacity
        for i in 0..<points.count - 1 {
            let (p1, d1) = points[i]
            let (p2, d2) = points[i + 1]

            // Only draw front-facing parts (depth > 0.3)
            let avgDepth = (d1 + d2) / 2
            guard avgDepth > 0.25 else { continue }

            let segmentPath = Path { path in
                path.move(to: p1)
                path.addLine(to: p2)
            }

            var ctx = context
            ctx.opacity = Double(avgDepth) * 0.9  // Fade based on depth

            ctx.stroke(
                segmentPath,
                with: .color(Color(hue: hue + Double(i) * 0.001, saturation: 0.85, brightness: 1.0)),
                style: StrokeStyle(lineWidth: lineWidth * avgDepth, lineCap: .round)
            )
        }
    }

    // MARK: - Highlight

    private func drawHighlight(context: GraphicsContext, center: CGPoint, radius: CGFloat) {
        var ctx = context
        ctx.opacity = 0.25

        let highlightSize = radius * 0.5
        let offsetX = -radius * 0.3
        let offsetY = -radius * 0.3

        ctx.fill(
            Ellipse().path(in: CGRect(
                x: center.x + offsetX - highlightSize / 2,
                y: center.y + offsetY - highlightSize / 2,
                width: highlightSize,
                height: highlightSize * 0.7
            )),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.6), .clear]),
                center: CGPoint(x: center.x + offsetX, y: center.y + offsetY),
                startRadius: 0,
                endRadius: highlightSize / 2
            )
        )
    }

}

// MARK: - Preview

#Preview("Plasma Orb") {
    VStack(spacing: 40) {
        HStack(spacing: 40) {
            VStack {
                VoiceOrbView(audioLevel: 0.9, isActive: true, isListening: false)
                Text("Speaking (Loud)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack {
                VoiceOrbView(audioLevel: 0.3, isActive: true, isListening: false)
                Text("Speaking (Soft)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        HStack(spacing: 40) {
            VStack {
                VoiceOrbView(audioLevel: 0.0, isActive: false, isListening: false)
                Text("Idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack {
                VoiceOrbView(audioLevel: 0.0, isActive: false, isListening: true)
                Text("Listening")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding(60)
    .background(.black)
}
