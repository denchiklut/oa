import AVFoundation
import AppKit
import SwiftUI

struct CaptureEditor: View {
    let image: CGImage
    let apply: (CGImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[CGPoint]] = []
    @State private var stroke: [CGPoint] = []

    private var pixels: CGSize { CGSize(width: image.width, height: image.height) }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Edit Capture").font(.headline)
                Spacer()
                Button("Undo") { _ = strokes.popLast() }.disabled(strokes.isEmpty)
            }
            GeometryReader { proxy in
                let size = AVMakeRect(aspectRatio: pixels, insideRect: CGRect(origin: .zero, size: proxy.size)).size
                drawing.frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { event in
                            stroke.append(CGPoint(x: event.location.x / size.width, y: event.location.y / size.height))
                        }.onEnded { _ in
                            strokes.append(stroke)
                            stroke = []
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Done") {
                    let renderer = ImageRenderer(content: drawing.frame(width: pixels.width, height: pixels.height))
                    if let output = renderer.cgImage { apply(output) }
                }.keyboardShortcut(.defaultAction).disabled(strokes.isEmpty)
            }
        }
        .padding(16).frame(width: 560, height: 390)
    }

    private var drawing: some View {
        Image(decorative: image, scale: 1).resizable().overlay {
            Canvas { context, size in
                let width = max(1 / CGFloat(image.width), 0.006) * size.width
                for points in strokes + [stroke] {
                    let scaled = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                    guard let first = scaled.first else { continue }
                    if scaled.allSatisfy({ $0 == first }) {
                        context.fill(
                            Path(ellipseIn: CGRect(origin: first, size: .zero).insetBy(dx: -width / 2, dy: -width / 2)),
                            with: .color(.red))
                    } else {
                        var path = Path()
                        path.addLines(scaled)
                        context.stroke(
                            path, with: .color(.red),
                            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }.clipped()
    }
}
