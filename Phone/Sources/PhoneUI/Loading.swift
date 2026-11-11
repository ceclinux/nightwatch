import SwiftUI
import PhoneCore

/// Text with a light sweeping across it: says what the app is doing, and shows that it is still working. Still under
/// Reduce Motion (the words carry the meaning).
struct ShimmerText: View {
    let text: String
    var font: Font = .callout
    @Environment(\.phoneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = -0.5

    var body: some View {
        Text(text).font(font).foregroundStyle(theme.textSecondary.opacity(0.6))
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        Text(text).font(font).foregroundStyle(theme.textPrimary).frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                            .mask {
                                LinearGradient(colors: [.clear, .white, .white, .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: geo.size.width * 0.5)
                                    .offset(x: geo.size.width * sweep)
                            }
                    }
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { sweep = 1.0 }
            }
            .animation(.easeInOut(duration: 0.25), value: text)
            .accessibilityLabel(text)
    }
}

/// The wait for tonight's page: the sky, a dial being traced, and one line saying what is actually happening.
struct LoadingScreen: View {
    let siteName: String
    let stage: PhoneStore.LoadStage?
    @Environment(\.phoneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = 0

    private var message: String {
        switch stage {
        case .planning: "Working out tonight's darkness, the Moon and your best targets"
        default: "Reading the forecast for \(siteName)"
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().stroke(theme.ring, lineWidth: 0.75).frame(width: 66, height: 66)
                ForEach(0..<60, id: \.self) { i in
                    let hour = i % 5 == 0
                    Capsule().fill(i < lit ? theme.accent : theme.tickCloudy)
                        .frame(width: hour ? 1.7 : 1.1, height: hour ? 8 : 4.5)
                        .offset(y: -45.5 + (hour ? 4 : 2.25))
                        .frame(width: 91, height: 91)
                        .rotationEffect(.degrees(Double(i) * 6))
                }
            }
            .frame(width: 91, height: 91).scaleEffect(1.5).frame(width: 140, height: 140)
            .accessibilityHidden(true)
            ShimmerText(text: message).multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { StarField(seed: siteName, calm: true).ignoresSafeArea() }
        .task {
            // The ticks light in turn, round and round: motion that says "working", not progress that is not real.
            guard !reduceMotion else { lit = 15; return }
            while !Task.isCancelled {
                for n in 0...60 { lit = n; try? await Task.sleep(for: .milliseconds(28)) }
                lit = 0
            }
        }
    }
}
