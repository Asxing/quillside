import AppKit

/// All frames share an 18pt canvas; only the ink moves, never the menu-bar layout.
enum StatusIconAnimation {
    static let size = NSSize(width: 18, height: 18)
    static let duration: TimeInterval = 0.72
    static let frameCount = 23

    struct Pose {
        var xScale: CGFloat = 1
        var yScale: CGFloat = 1
        var lift: CGFloat = 0
        var degrees: CGFloat = 0
    }

    static func pose(at progress: Double) -> Pose {
        let keys: [(Double, Pose)] = [
            (0, Pose()),
            (0.12, Pose(xScale: 1.06, yScale: 0.91, lift: -0.4, degrees: -3)),
            (0.32, Pose(xScale: 0.98, yScale: 1.02, lift: 1.2, degrees: -10)),
            (0.56, Pose(xScale: 1.04, yScale: 0.95, lift: -0.2, degrees: 7)),
            (0.78, Pose(xScale: 0.99, yScale: 1.01, lift: 0.5, degrees: -3)),
            (1, Pose())
        ]
        let t = min(1, max(0, progress))
        for index in 1..<keys.count where t <= keys[index].0 {
            let (start, a) = keys[index - 1], (end, b) = keys[index]
            let linear = CGFloat((t - start) / (end - start))
            let eased = linear * linear * (3 - 2 * linear)
            func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * eased }
            return Pose(xScale: mix(a.xScale, b.xScale), yScale: mix(a.yScale, b.yScale),
                        lift: mix(a.lift, b.lift), degrees: mix(a.degrees, b.degrees))
        }
        return Pose()
    }

    static func loadIcon(bundle: Bundle = .main) -> NSImage {
        let image = bundle.url(forResource: "MenuBarTemplate", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "note.text", accessibilityDescription: "Quillside")
            ?? NSImage(size: size)
        image.size = size
        image.isTemplate = true
        return image
    }

    static func frames(from source: NSImage) -> [NSImage] {
        (0..<frameCount).map { render(source, pose: pose(at: Double($0) / Double(frameCount - 1))) }
    }

    static func render(_ source: NSImage, pose: Pose) -> NSImage {
        let pixels = 72
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { return source }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.scaleBy(x: 4, y: 4)
        context.translateBy(x: size.width / 2, y: size.height / 2 + pose.lift)
        context.rotate(by: pose.degrees * .pi / 180)
        context.scaleBy(x: pose.xScale, y: pose.yScale)
        source.draw(in: NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height),
                    from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        bitmap.size = size
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        image.isTemplate = true
        return image
    }
}

/// A short, demand-driven timer also runs while AppKit is tracking an open menu.
@MainActor final class StatusIconAnimator: NSObject {
    private let rest: NSImage
    private let display: (NSImage) -> Void
    private let reduceMotion: () -> Bool
    private var frames: [NSImage]?
    private var timer: Timer?
    private var startedAt: TimeInterval = 0
    var isPlaying: Bool { timer != nil }

    init(image: NSImage, reduceMotion: @escaping () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }, display: @escaping (NSImage) -> Void) {
        rest = image; self.reduceMotion = reduceMotion; self.display = display
        super.init()
    }

    func play() {
        stop()
        guard !reduceMotion() else { return }
        if frames == nil { frames = StatusIconAnimation.frames(from: rest) }
        startedAt = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(tick),
                          userInfo: nil, repeats: true)
        timer.tolerance = 0.002
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        display(rest)
    }

    @objc private func tick() {
        let progress = (ProcessInfo.processInfo.systemUptime - startedAt) / StatusIconAnimation.duration
        guard progress < 1, !reduceMotion(), let frames else { stop(); return }
        display(frames[min(frames.count - 1, Int(progress * Double(frames.count - 1)))])
    }
}
