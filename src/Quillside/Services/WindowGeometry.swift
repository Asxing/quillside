import CoreGraphics

enum WindowGeometry {
    static func cocoaRect(
        fromAX rect: CGRect,
        primaryScreenFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func cocoaPoint(
        fromAX point: CGPoint,
        primaryScreenFrame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: point.x,
            y: primaryScreenFrame.maxY - point.y
        )
    }

    static func targetScreenFrame(
        for rect: CGRect,
        screenFrames: [CGRect]
    ) -> CGRect? {
        screenFrames
            .map { frame in
                (
                    frame: frame,
                    area: frame.intersection(rect).area
                )
            }
            .max { $0.area < $1.area }?
            .frame
    }

    static func noteActionsOrigin(
        axNotesFrame: CGRect,
        panelSize: CGSize,
        primaryScreenFrame: CGRect,
        visibleScreenFrames: [CGRect],
        margin: CGFloat = 16
    ) -> CGPoint {
        let notesFrame = cocoaRect(
            fromAX: axNotesFrame,
            primaryScreenFrame: primaryScreenFrame
        )
        let targetScreen = targetScreenFrame(
            for: notesFrame,
            screenFrames: visibleScreenFrames
        ) ?? primaryScreenFrame

        var origin = CGPoint(
            x: notesFrame.maxX - panelSize.width - margin,
            y: notesFrame.minY + margin
        )
        origin.x = max(
            notesFrame.minX + margin,
            min(
                origin.x,
                notesFrame.maxX - panelSize.width - margin
            )
        )
        origin.y = max(
            notesFrame.minY + margin,
            min(
                origin.y,
                notesFrame.maxY - panelSize.height - margin
            )
        )
        origin.x = max(
            targetScreen.minX,
            min(origin.x, targetScreen.maxX - panelSize.width)
        )
        origin.y = max(
            targetScreen.minY,
            min(origin.y, targetScreen.maxY - panelSize.height)
        )
        return origin
    }

    static func backlinksOrigin(
        axNotesFrame: CGRect,
        panelSize: CGSize,
        primaryScreenFrame: CGRect,
        visibleScreenFrames: [CGRect],
        trailingInset: CGFloat = 20,
        bottomInset: CGFloat = 60
    ) -> CGPoint {
        let notesFrame = cocoaRect(
            fromAX: axNotesFrame,
            primaryScreenFrame: primaryScreenFrame
        )
        let targetScreen = targetScreenFrame(
            for: notesFrame,
            screenFrames: visibleScreenFrames
        ) ?? primaryScreenFrame

        var origin = CGPoint(
            x: notesFrame.maxX - panelSize.width - trailingInset,
            y: notesFrame.minY + bottomInset
        )
        origin.x = max(
            targetScreen.minX,
            min(origin.x, targetScreen.maxX - panelSize.width)
        )
        origin.y = max(
            targetScreen.minY,
            min(origin.y, targetScreen.maxY - panelSize.height)
        )
        return origin
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(width, 0) * max(height, 0)
    }
}
