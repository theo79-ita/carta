import SwiftUI

struct WritingDesk: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            Color(red: dark ? 0.12 : 0.84, green: dark ? 0.15 : 0.88, blue: dark ? 0.19 : 0.92)
            if !reduceTransparency {
                GeometryReader { geometry in
                    let radius = max(geometry.size.width, geometry.size.height)
                    RadialGradient(colors: [Color(red: 0.48, green: 0.76, blue: 0.77).opacity(dark ? 0.31 : 0.57), .clear],
                                   center: .bottomLeading, startRadius: 0, endRadius: radius * 0.82)
                    RadialGradient(colors: [Color(red: 0.66, green: 0.68, blue: 0.91).opacity(dark ? 0.32 : 0.64), .clear],
                                   center: .topTrailing, startRadius: 0, endRadius: radius * 0.74)
                    RadialGradient(colors: [.white.opacity(dark ? 0.07 : 0.73), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: radius * 0.73)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    func writingGlass<S: InsettableShape>(in shape: S) -> some View {
        modifier(WritingGlass(shape: shape))
    }
}

private struct WritingGlass<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: S

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.background {
            surface
                .overlay {
                    if !reduceTransparency {
                        shape.fill(.linearGradient(colors: [
                            .white.opacity(scheme == .dark ? 0.13 : 0.50),
                            .white.opacity(scheme == .dark ? 0.035 : 0.19)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    shape.strokeBorder(.linearGradient(colors: [
                        .white.opacity(scheme == .dark ? 0.34 : 0.90),
                        .primary.opacity(contrast == .increased ? 0.60 : 0.18)
                    ], startPoint: .top, endPoint: .bottom))
                }
                .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.12), radius: 7, y: 3)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var surface: some View {
        if reduceTransparency {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        } else {
            // The project can also be built with the Swift 5.9 toolchain.
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                shape.fill(.clear).glassEffect(.regular, in: shape)
            } else {
                shape.fill(.regularMaterial)
            }
            #else
            shape.fill(.regularMaterial)
            #endif
        }
    }
}
