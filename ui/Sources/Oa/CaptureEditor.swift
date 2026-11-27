import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct CaptureEditor: View {
    let result: CapturedRegion
    let palette: WindowTheme.PrimaryColorPalette
    let cancel: () -> Void
    let apply: ([CaptureAnnotation], CGImage) -> Void
    @State private var marks: [CaptureAnnotation]
    @State private var history: [[CaptureAnnotation]] = []
    @State private var tool = CaptureTool.select
    @State private var selected: UUID?
    @State private var color = CaptureEditor.orange
    @State private var drag: Drag?
    @State private var textID: UUID?
    @FocusState private var typing: Bool
    @State private var importing = false

    init(
        result: CapturedRegion, palette: WindowTheme.PrimaryColorPalette, cancel: @escaping () -> Void,
        apply: @escaping ([CaptureAnnotation], CGImage) -> Void
    ) {
        self.result = result
        self.palette = palette
        self.cancel = cancel
        self.apply = apply
        _marks = State(initialValue: result.annotations)
    }

    private struct Drag {
        let index: Int
        let original: [CGPoint]
        var endpoint: Int?
        var creating = false
    }

    private var pixels: CGSize { CGSize(width: result.original.width, height: result.original.height) }

    var body: some View {
        GeometryReader { geometry in
            let rect = AVMakeRect(
                aspectRatio: pixels, insideRect: CGRect(origin: .zero, size: geometry.size).insetBy(dx: 20, dy: 20))
            let scale = rect.width / pixels.width
            ZStack(alignment: .topLeading) {
                Backdrop(onClick: finish, color: .black.withAlphaComponent(0.72))
                KeyTrap(onReturn: finish, onEscape: cancel)
                ZStack(alignment: .topLeading) {
                    AnnotatedCapture(
                        image: result.original, annotations: marks, selected: selected, editingText: textID
                    )
                    .contentShape(Rectangle()).gesture(gesture(scale: scale))
                    .simultaneousGesture(
                        SpatialTapGesture(count: 2).onEnded { tap in
                            let point = CGPoint(x: tap.location.x / scale, y: tap.location.y / scale)
                            if let mark = marks.last(where: {
                                $0.tool == .text && $0.contains(point, tolerance: 3 / scale)
                            }) {
                                remember()
                                selected = mark.id
                                textID = mark.id
                            }
                        })
                    if let i = marks.firstIndex(where: { $0.id == textID }) {
                        let mark = marks[i]
                        TextField(
                            "Text",
                            text: Binding(
                                get: { marks.first { $0.id == mark.id }?.text ?? "" },
                                set: { value in
                                    if let i = marks.firstIndex(where: { $0.id == mark.id }) {
                                        marks[i].updateText(value)
                                    }
                                })
                        )
                        .textFieldStyle(.plain).font(.system(size: mark.width * 6 * scale, weight: .semibold))
                        .foregroundStyle(mark.color).focused($typing)
                        .frame(width: max(90, mark.bounds.width * scale + 16), alignment: .leading)
                        .offset(x: mark.bounds.minX * scale, y: mark.bounds.minY * scale)
                        .onAppear { typing = true }.onSubmit { endText() }
                    }
                }
                .frame(width: rect.width, height: rect.height)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .position(x: rect.midX, y: rect.midY)
                toolbar
                    .fixedSize().offset(
                        x: min(rect.minX + 12, max(4, geometry.size.width - 280)), y: max(4, rect.maxY - 56))
                if let mark = marks.first(where: { $0.id == selected }), mark.tool != .image, textID == nil, drag == nil
                {
                    palette(mark: mark)
                        .position(
                            x: min(max(96, rect.minX + mark.bounds.midX * scale), geometry.size.width - 96),
                            y: max(40, rect.minY + mark.bounds.minY * scale - 48))
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { response in
                guard case .success(let file) = response else { tool = .select; return }
                let scoped = file.startAccessingSecurityScopedResource()
                defer { if scoped { file.stopAccessingSecurityScopedResource() } }
                guard let image = NSImage(contentsOf: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                else { tool = .select; return }
                let frame = AVMakeRect(
                    aspectRatio: CGSize(width: image.width, height: image.height),
                    insideRect: CGRect(origin: .zero, size: pixels).insetBy(
                        dx: pixels.width * 0.2, dy: pixels.height * 0.2))
                remember()
                let mark = CaptureAnnotation(
                    tool: .image, points: [frame.origin, CGPoint(x: frame.maxX, y: frame.maxY)], color: color,
                    width: 4 / scale, image: image)
                marks.append(mark)
                selected = mark.id
                tool = .select
            }
        }
        .background {
            Button("Undo") { undo() }.keyboardShortcut("z")
                .disabled(history.isEmpty || typing).opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
        .accessibilityAction(named: "Finish Editing", finish)
    }

    private var toolbar: some View {
        let active = palette.midTone.opacity(0.53).over(palette.shadedDark).opacity(0.69).over(.black).color
        return HStack(spacing: 2) {
            ForEach(CaptureTool.allCases, id: \.self) { item in
                Button {
                    endText()
                    tool = item
                    selected = nil
                    if item == .image { importing = true }
                } label: {
                    Image(systemName: item.symbol).font(.system(size: 17, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(tool == item ? active : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(item.rawValue).help(item.rawValue)
            }
        }
        .foregroundStyle(palette.tintedLight.color).padding(4)
        .background(palette.shadedDark.opacity(0.15).over(.black).color, in: RoundedRectangle(cornerRadius: 8))
    }

    private static func swatch(_ rgb: UInt32) -> Color {
        Color(
            .sRGB, red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255,
            blue: Double(rgb & 255) / 255)
    }
    private static let orange = swatch(0xff994e)
    private static let colors: [[(String, Color)]] = [
        [
            ("Black", .black), ("Yellow", swatch(0xffd336)), ("Orange", orange), ("Red", swatch(0xf53615)),
            ("Mint", swatch(0x00ec8d)), ("Green", swatch(0x0e7a01)),
        ],
        [
            ("White", .white), ("Gray", swatch(0xbbbbbb)), ("Magenta", swatch(0xc0009f)),
            ("Cyan", swatch(0x00cbf8)), ("Blue", swatch(0x3239fb)),
        ],
    ]

    private func palette(mark: CaptureAnnotation) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 5) {
                ForEach(Self.colors.indices, id: \.self) { row in
                    HStack(spacing: 5) {
                        ForEach(Self.colors[row], id: \.0) { name, swatch in
                            Button {
                                guard let i = marks.firstIndex(where: { $0.id == mark.id }) else { return }
                                remember()
                                marks[i].color = swatch
                                color = swatch
                            } label: {
                                Circle().fill(swatch).overlay { Circle().strokeBorder(.white.opacity(0.22)) }
                                    .overlay {
                                        if mark.color == swatch {
                                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(
                                                    ["Black", "Blue", "Green", "Magenta"].contains(name)
                                                        ? .white : .black)
                                        }
                                    }
                                    .frame(width: 20, height: 20)
                            }.buttonStyle(.plain).accessibilityLabel(name)
                        }
                    }
                }
            }.padding(10).background(.black, in: RoundedRectangle(cornerRadius: 8))
            Path { path in
                path.move(to: .zero); path.addLine(to: CGPoint(x: 14, y: 0)); path.addLine(to: CGPoint(x: 7, y: 7));
                path.closeSubpath()
            }.fill(.black).frame(width: 14, height: 7)
        }.fixedSize()
    }

    private func gesture(scale: CGFloat) -> some Gesture {
        let pixels = self.pixels
        return DragGesture(minimumDistance: 0).onChanged { value in
            func point(_ p: CGPoint) -> CGPoint {
                CGPoint(x: min(pixels.width, max(0, p.x / scale)), y: min(pixels.height, max(0, p.y / scale)))
            }
            let start = point(value.startLocation), current = point(value.location)
            if drag == nil {
                endText()
                if tool == .select {
                    let arrow = marks.firstIndex { $0.id == selected && $0.tool == .arrow }
                    if let arrow,
                        let handle = marks[arrow].points.firstIndex(where: {
                            hypot($0.x - start.x, $0.y - start.y) <= 9 / scale
                        })
                    {
                        remember()
                        drag = Drag(index: arrow, original: marks[arrow].points, endpoint: handle)
                    } else {
                        guard let i = marks.lastIndex(where: { $0.contains(start, tolerance: 6 / scale) }) else {
                            selected = nil; return
                        }
                        selected = marks[i].id
                        remember()
                        drag = Drag(index: i, original: marks[i].points)
                    }
                } else {
                    let mark = CaptureAnnotation(tool: tool, points: [start, start], color: color, width: 3 / scale)
                    remember()
                    marks.append(mark)
                    selected = nil
                    drag = Drag(index: marks.count - 1, original: mark.points, creating: true)
                }
            }
            guard let drag else { return }
            if drag.creating {
                if tool == .pen {
                    marks[drag.index].points.append(current)
                } else {
                    marks[drag.index].points[1] = current
                }
            } else if let endpoint = drag.endpoint {
                marks[drag.index].points[endpoint] = current
            } else {
                marks[drag.index].points = drag.original.map {
                    CGPoint(x: $0.x + current.x - start.x, y: $0.y + current.y - start.y)
                }
            }
        }.onEnded { _ in
            guard let drag else { return }
            if drag.creating {
                selected = marks[drag.index].id
                if tool == .text { marks[drag.index].updateText(""); textID = selected }
                tool = .select
            }
            if !drag.creating && marks[drag.index].points == drag.original { _ = history.popLast() }
            self.drag = nil
        }
    }

    private func endText() {
        if let textID { marks.removeAll { $0.id == textID && $0.text.isEmpty } }
        textID = nil
        typing = false
    }

    private func remember() { history.append(marks) }
    private func undo() {
        guard let previous = history.popLast() else { return }
        textID = nil
        selected = nil
        marks = previous
    }

    private func finish() {
        endText()
        guard !history.isEmpty || !marks.isEmpty else { cancel(); return }
        if marks.isEmpty { apply([], result.original); return }
        let original = result.original
        let rect = CGRect(origin: .zero, size: pixels)
        let colorSpace =
            original.colorSpace?.model == .rgb ? original.colorSpace : CGColorSpace(name: CGColorSpace.sRGB)
        guard let colorSpace,
            let context = CGContext(
                data: nil, width: original.width, height: original.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        // Compositing the overlay in the source profile keeps untouched screenshot pixels intact.
        context.draw(original, in: rect)
        let overlay = AnnotatedCapture(image: original, showsOriginal: false, annotations: marks)
            .frame(width: pixels.width, height: pixels.height)
        ImageRenderer(content: overlay).render { _, draw in draw(context) }
        if let image = context.makeImage() { apply(marks, image) }
    }
}
