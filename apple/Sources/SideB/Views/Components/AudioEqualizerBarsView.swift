import SwiftUI

/// Vista animada de 4 barras de ecualizador de audio al estilo Apple Music.
/// Acelerada por hardware (CoreAnimation) sin impacto en el hilo principal de CPU a 120 FPS.
public struct AudioEqualizerBarsView: View {
    @State private var bar1Height: CGFloat = 4
    @State private var bar2Height: CGFloat = 8
    @State private var bar3Height: CGFloat = 5
    @State private var bar4Height: CGFloat = 7

    public init() {}

    public var body: some View {
        HStack(alignment: .bottom, spacing: 2.2) {
            Capsule()
                .fill(Color.white)
                .frame(width: 2.8, height: bar1Height)
            
            Capsule()
                .fill(Color.white)
                .frame(width: 2.8, height: bar2Height)
            
            Capsule()
                .fill(Color.white)
                .frame(width: 2.8, height: bar3Height)
            
            Capsule()
                .fill(Color.white)
                .frame(width: 2.8, height: bar4Height)
        }
        .frame(height: 18, alignment: .bottom)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.42).repeatForever(autoreverses: true)) {
                bar1Height = 15
            }
            withAnimation(.easeInOut(duration: 0.58).repeatForever(autoreverses: true)) {
                bar2Height = 18
            }
            withAnimation(.easeInOut(duration: 0.36).repeatForever(autoreverses: true)) {
                bar3Height = 13
            }
            withAnimation(.easeInOut(duration: 0.48).repeatForever(autoreverses: true)) {
                bar4Height = 16
            }
        }
    }
}
