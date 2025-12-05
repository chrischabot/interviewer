import SwiftUI

// MARK: - Voice Orb View

/// An animated orb that visualizes AI speech, creating a sense of
/// an intelligent, interactive presence during interviews.
struct VoiceOrbView: View {
    let audioLevel: CGFloat  // 0.0 to 1.0
    let isActive: Bool       // Whether AI is currently speaking
    let isListening: Bool    // Whether listening to user (shows different state)

    // Idle animation state
    @State private var idlePhase: Double = 0
    @State private var rotationAngle: Double = 0

    private var clampedLevel: CGFloat {
        min(max(audioLevel, 0), 1)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/60)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let baseRadius = min(size.width, size.height) / 2 * 0.7

                // Dynamic values based on audio level and time
                let breathe = sin(time * 2) * 0.05 + 1.0  // Subtle idle breathing
                let audioScale = 1.0 + Double(clampedLevel) * 0.35
                let combinedScale = isActive ? audioScale : breathe

                // Layer 1: Outer glow (largest, most diffuse)
                if isActive || isListening {
                    let glowRadius = baseRadius * combinedScale * 1.6
                    let glowOpacity = isActive ? 0.15 + Double(clampedLevel) * 0.25 : 0.1

                    var outerGlow = context
                    outerGlow.opacity = glowOpacity
                    outerGlow.addFilter(.blur(radius: 20))

                    outerGlow.fill(
                        Circle().path(in: CGRect(
                            x: center.x - glowRadius,
                            y: center.y - glowRadius,
                            width: glowRadius * 2,
                            height: glowRadius * 2
                        )),
                        with: .radialGradient(
                            Gradient(colors: [.cyan.opacity(0.6), .purple.opacity(0.2), .clear]),
                            center: center,
                            startRadius: 0,
                            endRadius: glowRadius
                        )
                    )
                }

                // Layer 2: Rotating ring (creates "thinking" effect)
                let ringRadius = baseRadius * combinedScale * 1.15
                let ringRotation = time * (isActive ? 2.0 : 0.5)

                // Draw segmented ring
                for i in 0..<6 {
                    let segmentAngle = Double(i) * .pi / 3 + ringRotation
                    let segmentOpacity = 0.3 + sin(segmentAngle * 2 + time * 3) * 0.3

                    var segmentContext = context
                    segmentContext.opacity = segmentOpacity * (isActive ? 1.0 : 0.5)

                    let startAngle = Angle(radians: segmentAngle)
                    let endAngle = Angle(radians: segmentAngle + .pi / 4)

                    let arcPath = Path { path in
                        path.addArc(
                            center: center,
                            radius: ringRadius,
                            startAngle: startAngle,
                            endAngle: endAngle,
                            clockwise: false
                        )
                    }

                    segmentContext.stroke(
                        arcPath,
                        with: .linearGradient(
                            Gradient(colors: [.cyan, .purple]),
                            startPoint: CGPoint(x: center.x - ringRadius, y: center.y),
                            endPoint: CGPoint(x: center.x + ringRadius, y: center.y)
                        ),
                        lineWidth: 2 + CGFloat(clampedLevel) * 2
                    )
                }

                // Layer 3: Inner orb (main body)
                let orbRadius = baseRadius * combinedScale
                let orbRect = CGRect(
                    x: center.x - orbRadius,
                    y: center.y - orbRadius,
                    width: orbRadius * 2,
                    height: orbRadius * 2
                )

                // Gradient shifts based on state
                let primaryColor: Color = isActive ? .cyan : (isListening ? .green.opacity(0.8) : .blue)
                let secondaryColor: Color = isActive ? .blue : .purple.opacity(0.7)

                context.fill(
                    Circle().path(in: orbRect),
                    with: .radialGradient(
                        Gradient(colors: [
                            primaryColor.opacity(0.9),
                            secondaryColor.opacity(0.7),
                            .purple.opacity(0.5)
                        ]),
                        center: CGPoint(x: center.x - orbRadius * 0.2, y: center.y - orbRadius * 0.2),
                        startRadius: 0,
                        endRadius: orbRadius * 1.2
                    )
                )

                // Layer 4: Inner highlight (adds depth/glass effect)
                let highlightRadius = orbRadius * 0.6
                let highlightOffset = orbRadius * 0.25
                let highlightRect = CGRect(
                    x: center.x - highlightRadius - highlightOffset,
                    y: center.y - highlightRadius - highlightOffset,
                    width: highlightRadius * 2,
                    height: highlightRadius * 2
                )

                var highlightContext = context
                highlightContext.opacity = 0.4

                highlightContext.fill(
                    Ellipse().path(in: highlightRect),
                    with: .radialGradient(
                        Gradient(colors: [.white.opacity(0.5), .clear]),
                        center: CGPoint(x: center.x - highlightOffset, y: center.y - highlightOffset),
                        startRadius: 0,
                        endRadius: highlightRadius
                    )
                )

                // Layer 5: Audio reactive "pulses" (when speaking)
                if isActive && clampedLevel > 0.1 {
                    let pulseCount = 3
                    for i in 0..<pulseCount {
                        let pulsePhase = (time * 4 + Double(i) * 0.3).truncatingRemainder(dividingBy: 1.0)
                        let pulseRadius = orbRadius * (1.0 + pulsePhase * 0.5)
                        let pulseOpacity = (1.0 - pulsePhase) * Double(clampedLevel) * 0.4

                        var pulseContext = context
                        pulseContext.opacity = pulseOpacity

                        let pulseRect = CGRect(
                            x: center.x - pulseRadius,
                            y: center.y - pulseRadius,
                            width: pulseRadius * 2,
                            height: pulseRadius * 2
                        )

                        pulseContext.stroke(
                            Circle().path(in: pulseRect),
                            with: .color(.cyan),
                            lineWidth: 1.5
                        )
                    }
                }

                // Layer 6: Listening indicator dots (when user is speaking)
                if isListening && !isActive {
                    for i in 0..<3 {
                        let dotAngle = Double(i) * .pi * 2 / 3 - .pi / 2 + time * 2
                        let dotRadius: CGFloat = 4
                        let orbitRadius = orbRadius * 1.3

                        let dotX = center.x + cos(dotAngle) * orbitRadius
                        let dotY = center.y + sin(dotAngle) * orbitRadius

                        let dotRect = CGRect(
                            x: dotX - dotRadius,
                            y: dotY - dotRadius,
                            width: dotRadius * 2,
                            height: dotRadius * 2
                        )

                        context.fill(
                            Circle().path(in: dotRect),
                            with: .color(.green)
                        )
                    }
                }
            }
        }
        .frame(width: 60, height: 60)
    }
}

// MARK: - Preview

#Preview("Speaking") {
    VStack(spacing: 40) {
        VoiceOrbView(audioLevel: 0.8, isActive: true, isListening: false)
        VoiceOrbView(audioLevel: 0.3, isActive: true, isListening: false)
        VoiceOrbView(audioLevel: 0.0, isActive: false, isListening: false)
        VoiceOrbView(audioLevel: 0.0, isActive: false, isListening: true)
    }
    .padding(40)
    .background(.black)
}
