import SwiftUI

// MARK: - Liquid Glass Design System
//
// macOS 26 Tahoe / iOS 26 Liquid Glass design language:
// - Blur + translucency for panels and sidebars
// - Elevated surfaces with subtle shadows
// - Consistent corner radii (12, 16, 20, 24)
// - Respect system Reduce Transparency toggle

// MARK: - Glass Panel

/// A translucent panel with blur and subtle shadow
struct GlassPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 16,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                panelBackground
            )
    }

    @ViewBuilder
    private var panelBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(white: 0.95).opacity(0.95))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
    }
}

// MARK: - Glass Card

/// An elevated card with glass effect for content sections
struct GlassCard<Content: View>: View {
    let title: String?
    let icon: String?
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        title: String? = nil,
        icon: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.headline)
                }
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
    }
}

// MARK: - Glass Button

/// A glass-styled button with blur background
struct GlassButton: View {
    let title: String
    let icon: String?
    let role: ButtonRole?
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        _ title: String,
        icon: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(buttonBackground)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        if reduceTransparency {
            Capsule()
                .fill(role == .destructive ? Color.red.opacity(0.15) : Color.primary.opacity(0.08))
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        }
    }
}

// MARK: - Glass Input Field

/// A glass-styled text input field
struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    let axis: Axis

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var isFocused: Bool

    init(_ placeholder: String, text: Binding<String>, axis: Axis = .horizontal) {
        self.placeholder = placeholder
        self._text = text
        self.axis = axis
    }

    var body: some View {
        TextField(placeholder, text: $text, axis: axis)
            .textFieldStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(fieldBackground)
            .focused($isFocused)
    }

    @ViewBuilder
    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(reduceTransparency ? Color.primary.opacity(0.05) : Color.primary.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isFocused ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isFocused ? 2 : 1)
            )
    }
}

// MARK: - Glass Toolbar

/// A glass-styled toolbar or bottom bar
struct GlassToolbar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        content()
            .padding()
            .frame(maxWidth: .infinity)
            .background(toolbarBackground)
    }

    @ViewBuilder
    private var toolbarBackground: some View {
        if reduceTransparency {
            Rectangle()
                .fill(Color(white: 0.96))
        } else {
            Rectangle()
                .fill(.bar)
        }
    }
}

// MARK: - Glass Overlay

/// A full-screen glass overlay for modals and loading states
struct GlassOverlay<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                Rectangle()
                    .fill(Color.black.opacity(0.3))
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }

            content()
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass Tag

/// A small glass-styled tag/chip
struct GlassTag: View {
    let text: String
    let color: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(_ text: String, color: Color = .blue) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(reduceTransparency ? color.opacity(0.15) : color.opacity(0.1))
            )
    }
}

// MARK: - View Modifiers

extension View {
    /// Apply glass panel styling to any view
    func glassPanel(cornerRadius: CGFloat = 16, padding: CGFloat = 0) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, padding: padding))
    }

    /// Apply glass card styling to any view
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}

private struct GlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                Group {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color(white: 0.95).opacity(0.95))
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                    }
                }
            )
    }
}

private struct GlassCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Group {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                    }
                }
            )
    }
}
