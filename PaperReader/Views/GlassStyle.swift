import SwiftUI

extension View {
    /// Liquid Glass surface on iOS 26+, material fill on earlier releases
    /// (deployment target is iOS 17).
    @ViewBuilder
    func glassCard(in shape: some Shape, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(shape.fill(.regularMaterial))
        }
    }
}
