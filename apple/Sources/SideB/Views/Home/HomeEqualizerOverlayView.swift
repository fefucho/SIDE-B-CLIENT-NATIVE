import AppKit
import QuartzCore

/// Superposición visual de ecualizador animado por CoreAnimation (GPU).
/// Diseñada para ocupar toda la superficie de la portada con 0% impacto en CPU.
final class HomeEqualizerOverlayView: NSView {
    private let scrimLayer = CALayer()
    private var barLayers: [CALayer] = []
    private var isAnimating = false
    private var isCompact = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true

        guard let root = layer else { return }
        root.masksToBounds = true

        scrimLayer.backgroundColor = NSColor.black.withAlphaComponent(0.38).cgColor
        root.addSublayer(scrimLayer)

        setupBars(compact: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // La animación es puramente visual; todos los clics y hovers deben pasar a los controles
        nil
    }

    func setCornerRadius(_ radius: CGFloat) {
        layer?.cornerRadius = radius
        scrimLayer.cornerRadius = radius
    }

    func updateStyle(compact: Bool) {
        guard compact != isCompact else { return }
        isCompact = compact
        setupBars(compact: compact)
        layoutBars()
        if isAnimating {
            applyAnimations()
        }
    }

    private func setupBars(compact: Bool) {
        barLayers.forEach { $0.removeFromSuperlayer() }
        barLayers.removeAll()

        let count = compact ? 4 : 5
        let barColor = NSColor.white.withAlphaComponent(0.94).cgColor

        for _ in 0..<count {
            let bar = CALayer()
            bar.backgroundColor = barColor
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(bar)
            barLayers.append(bar)
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scrimLayer.frame = bounds
        layoutBars()
        CATransaction.commit()
    }

    private func layoutBars() {
        guard !barLayers.isEmpty, bounds.width > 0, bounds.height > 0 else { return }

        let count = CGFloat(barLayers.count)
        let barWidth: CGFloat = isCompact ? 3.0 : 6.0
        let barSpacing: CGFloat = isCompact ? 2.5 : 5.0
        let totalWidth = (count * barWidth) + ((count - 1) * barSpacing)
        let startX = (bounds.width - totalWidth) / 2.0
        let centerY = bounds.height / 2.0
        let maxHeight: CGFloat = isCompact ? 20.0 : min(54.0, bounds.height * 0.38)
        let cornerRadius = barWidth / 2.0

        for (index, bar) in barLayers.enumerated() {
            let x = startX + CGFloat(index) * (barWidth + barSpacing)
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: maxHeight)
            bar.position = CGPoint(x: x + barWidth / 2.0, y: centerY)
            bar.cornerRadius = cornerRadius
        }
    }

    func startAnimating() {
        guard !isAnimating else {
            // Si estaba en pausa, reanudar
            if let root = layer, root.speed == 0.0 {
                resumeCoreAnimation()
            }
            return
        }

        isHidden = false
        isAnimating = true
        resetLayerTiming()
        applyAnimations()
    }

    func pauseAnimation() {
        guard isAnimating, let root = layer, root.speed != 0.0 else { return }
        let pausedTime = root.convertTime(CACurrentMediaTime(), from: nil)
        root.speed = 0.0
        root.timeOffset = pausedTime
    }

    private func resumeCoreAnimation() {
        guard let root = layer, root.speed == 0.0 else { return }
        let pausedTime = root.timeOffset
        root.speed = 1.0
        root.timeOffset = 0.0
        root.beginTime = 0.0
        let timeSincePause = root.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        root.beginTime = timeSincePause
    }

    private func resetLayerTiming() {
        guard let root = layer else { return }
        root.speed = 1.0
        root.timeOffset = 0.0
        root.beginTime = 0.0
    }

    func stopAnimating() {
        isAnimating = false
        isHidden = true
        resetLayerTiming()
        barLayers.forEach { $0.removeAllAnimations() }
    }

    private func applyAnimations() {
        guard !barLayers.isEmpty else { return }

        // Variaciones asimétricas orgánicas para simular un ecualizador musical vivo
        let profiles: [(duration: Double, keyframes: [Double])] = [
            (0.62, [0.35, 0.85, 0.40, 1.00, 0.50, 0.35]),
            (0.48, [0.55, 0.25, 0.90, 0.45, 0.95, 0.55]),
            (0.72, [0.20, 0.92, 0.35, 0.78, 0.30, 0.20]),
            (0.54, [0.65, 0.30, 1.00, 0.40, 0.80, 0.65]),
            (0.66, [0.30, 0.75, 0.25, 0.88, 0.42, 0.30]),
            (0.50, [0.45, 0.88, 0.32, 0.92, 0.55, 0.45])
        ]

        let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)

        for (index, bar) in barLayers.enumerated() {
            bar.removeAllAnimations()
            let profile = profiles[index % profiles.count]

            let anim = CAKeyframeAnimation(keyPath: "transform.scale.y")
            anim.values = profile.keyframes
            anim.duration = profile.duration
            anim.repeatCount = .infinity
            anim.autoreverses = true
            anim.timingFunction = easeInOut
            anim.isRemovedOnCompletion = false

            bar.add(anim, forKey: "equalizerBounce")
        }
    }
}
