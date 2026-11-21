import SwiftUI

/// After Arc's `ShadowView`: a shape's shadow at full strength, however translucent what fills the shape. SwiftUI's
/// own would be scaled by the fill's alpha and show through it, so an opaque shape casts it and only what falls
/// outside the shape is kept.
struct ShadowView<S: Shape>: View {
    let shape: S
    let color: Color
    let radius: CGFloat
    var y: CGFloat = 0

    var body: some View {
        shape
            .shadow(color: color, radius: radius, y: y)
            .mask {
                Rectangle().padding(-(radius * 4 + abs(y)))
                    .overlay { shape.blendMode(.destinationOut) }
                    .compositingGroup()
            }
    }
}
