import SwiftUI

/// Arc's `AppTrayVisualEffectImageProvider`: the tile's favicon drawn far past the tile (its width ÷ 5 times its
/// size), blurred by 5 and pushed to saturation 1.5, brightness 0.05, contrast 0.85, so the tile takes the icon's own
/// colours rather than an average of them.
struct AppTrayVisualEffect: View {
    let favicon: NSImage
    let tileWidth: CGFloat

    var body: some View {
        let size = tileWidth / 5 * 16
        Color.clear
            .overlay {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .blur(radius: 5)
                    .saturation(1.5)
                    .brightness(0.05)
                    .contrast(0.85)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Arc's `AppTrayItemSelectionOutlineView`: the same image through a 2 pt ring. Its opacity is Oa's fit of the
/// measured rims, which read as the image at about three quarters over the white card.
struct AppTrayRing: View {
    let favicon: NSImage
    let tileWidth: CGFloat

    var body: some View {
        AppTrayVisualEffect(favicon: favicon, tileWidth: tileWidth)
            .mask { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(lineWidth: 2) }
            .opacity(0.75)
    }
}
