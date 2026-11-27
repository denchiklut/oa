import AppKit
import SwiftUI

enum CaptureTool: String, CaseIterable {
    case select = "Select", image = "Image", text = "Text", ellipse = "Ellipse"
    case rectangle = "Rectangle", arrow = "Arrow", pen = "Freehand"

    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .image: "photo"
        case .text: "character"
        case .ellipse: "circle"
        case .rectangle: "square"
        case .arrow: "arrow.up.right"
        case .pen: "scribble"
        }
    }
}

struct CaptureAnnotation: Identifiable {
    let id = UUID()
    let tool: CaptureTool
    var points: [CGPoint]
    var color: Color
    let width: CGFloat
    var text = ""
    var image: CGImage?

    var bounds: CGRect {
        points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    var path: Path {
        var path = Path()
        guard let start = points.first, let end = points.last else { return path }
        switch tool {
        case .ellipse: path.addEllipse(in: bounds)
        case .rectangle: path.addRect(bounds)
        case .arrow:
            let angle = atan2(end.y - start.y, end.x - start.x)
            let head = min(width * 6, hypot(end.x - start.x, end.y - start.y) * 0.45)
            path.addLines([start, end])
            for offset in [-CGFloat.pi / 6, .pi / 6] {
                path.move(to: end)
                path.addLine(to: CGPoint(x: end.x - cos(angle + offset) * head, y: end.y - sin(angle + offset) * head))
            }
        case .pen:
            path.addLines(points)
            if start == end && bounds.size == .zero {
                path.addLine(to: CGPoint(x: start.x + width / 100, y: start.y))
            }
        default: break
        }
        return path
    }

    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        if tool == .image || tool == .text { return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
        return path.strokedPath(StrokeStyle(lineWidth: width + tolerance * 2, lineCap: .round, lineJoin: .round))
            .contains(point)
    }

    mutating func updateText(_ value: String) {
        text = value
        let size = (value as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: width * 6, weight: .semibold)
        ])
        points[1] = CGPoint(
            x: points[0].x + max(width * 4, size.width.rounded(.up)), y: points[0].y + size.height.rounded(.up))
    }

    func draw(in context: GraphicsContext) {
        switch tool {
        case .image:
            if let image { context.draw(Image(decorative: image, scale: 1), in: bounds) }
        case .text:
            context.draw(
                Text(text).font(.system(size: width * 6, weight: .semibold)).foregroundStyle(color), at: bounds.origin,
                anchor: .topLeading)
        default:
            context.stroke(
                path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }
}

struct AnnotatedCapture: View {
    let image: CGImage
    var showsOriginal = true
    let annotations: [CaptureAnnotation]
    var viewport = CaptureViewport()
    var selected: UUID?
    var editingText: UUID?

    var body: some View {
        Canvas { context, size in
            let transform = viewport.transform(image: CGSize(width: image.width, height: image.height), in: size)
            let scale = transform.a
            context.concatenate(transform)
            if showsOriginal {
                context.draw(
                    Image(decorative: image, scale: 1), in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
                )
            }
            for mark in annotations {
                if mark.id == selected {
                    let stroke = mark.tool == .arrow || mark.tool == .pen
                    context.stroke(
                        stroke ? mark.path : Path(mark.bounds), with: .color(.cyan),
                        style: StrokeStyle(
                            lineWidth: (stroke ? mark.width : 0) + 2 / scale, lineCap: .round, lineJoin: .round))
                }
                if mark.id != editingText { mark.draw(in: context) }
                if mark.id == selected && mark.tool == .arrow {
                    for endpoint in mark.points {
                        let dot = Path(
                            ellipseIn: CGRect(origin: endpoint, size: .zero).insetBy(dx: -3 / scale, dy: -3 / scale))
                        context.fill(dot, with: .color(.black))
                        context.stroke(dot, with: .color(.cyan), lineWidth: 2 / scale)
                    }
                }
            }
        }
    }
}
