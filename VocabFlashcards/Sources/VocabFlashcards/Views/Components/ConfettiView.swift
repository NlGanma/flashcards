import SwiftUI

/// A tasteful one-shot confetti burst used on the summary screen. Pieces fall, drift,
/// spin, and fade out once. Non-interactive so it never blocks the UI beneath it.
struct ConfettiView: View {
    var intensity: Int = 46

    private struct Piece: Identifiable {
        let id = UUID()
        let xFraction: CGFloat
        let color: Color
        let width: CGFloat
        let height: CGFloat
        let delay: Double
        let duration: Double
        let spin: Double
        let drift: CGFloat
    }

    private static let palette: [Color] = [
        Palette.indigo, Palette.violet, Palette.success, Palette.amber,
        Color(red: 0.95, green: 0.45, blue: 0.6), Color(red: 0.36, green: 0.78, blue: 0.9)
    ]

    @State private var pieces: [Piece] = []
    @State private var fall = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(piece.color)
                        .frame(width: piece.width, height: piece.height)
                        .rotationEffect(.degrees(fall ? piece.spin : 0))
                        .position(
                            x: geo.size.width * piece.xFraction + (fall ? piece.drift : 0),
                            y: fall ? geo.size.height + 60 : -60
                        )
                        .opacity(fall ? 0 : 1)
                        .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: fall)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            pieces = (0..<intensity).map { _ in
                Piece(
                    xFraction: .random(in: 0.02...0.98),
                    color: Self.palette.randomElement()!,
                    width: .random(in: 6...11),
                    height: .random(in: 10...18),
                    delay: .random(in: 0...0.5),
                    duration: .random(in: 1.8...2.8),
                    spin: .random(in: 180...720) * (Bool.random() ? 1 : -1),
                    drift: .random(in: -60...60)
                )
            }
            // Kick off on the next runloop tick so pieces first render at the top.
            DispatchQueue.main.async { fall = true }
        }
    }
}
