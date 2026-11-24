/// Arc's `ZoomActionType`.
enum ZoomActionType {
    case `in`, out, reset
}

extension WindowModel {
    /// Arc's cursor is set from each zoom change the engine reports, so it is read here from the page's zoom as it
    /// is now. The Peek before its tab's page, as Copy URL.
    func canZoom(_ type: ZoomActionType) -> Bool {
        guard let page = frontPage else { return false }
        let state = ZoomState(factor: page.zoomFactor)
        return switch type {
        case .in: !state.isAtMax
        case .out: !state.isAtMin
        case .reset: !state.isActualSize || page.isPageScaled
        }
    }

    /// As Arc's: the next preset, or 100 % with the pinch undone, and its toast on the page, from a key or the menu.
    func zoom(_ type: ZoomActionType) {
        guard let page = frontPage else { return }
        var state = ZoomState(factor: page.zoomFactor)
        switch type {
        case .in:
            state.zoomIn()
            page.setZoomFactor(state.factor)
        case .out:
            state.zoomOut()
            page.setZoomFactor(state.factor)
        case .reset:
            state = ZoomState()
            page.resetZoomAndScaleFactors()
        }
        present(.zoomChanged("\(Int(state.factor * 100))%"), at: .windowContent(page.id))
    }
}
