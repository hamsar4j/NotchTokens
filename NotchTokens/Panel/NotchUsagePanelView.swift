//
//  NotchUsagePanelView.swift
//  NotchTokens
//

import AppKit

@MainActor
final class NotchUsagePanelView: NSView {
    private enum ButtonKind: CaseIterable {
        case refresh
        case pin
        case quit

        var symbolName: String {
            switch self {
            case .refresh: "arrow.clockwise"
            case .pin: "pin"
            case .quit: "power"
            }
        }
    }

    private let monitor: UsageMonitor
    private let onSizeChange: (CGSize) -> Void
    private var trackingArea: NSTrackingArea?
    private var snapshot: UsageSnapshot
    private var isExpanded = false
    private var isPinned = false
    private var buttonFrames: [ButtonKind: CGRect] = [:]
    private var collapseWorkItem: DispatchWorkItem?

    private static let collapsedSize = CGSize(width: 220, height: 38)
    private static let expandedSize = CGSize(width: 360, height: 188)

    private var targetSize: CGSize {
        isExpanded ? Self.expandedSize : Self.collapsedSize
    }

    override var isFlipped: Bool { true }

    init(monitor: UsageMonitor, onSizeChange: @escaping (CGSize) -> Void) {
        self.monitor = monitor
        self.onSizeChange = onSizeChange
        self.snapshot = monitor.snapshot

        super.init(frame: CGRect(origin: .zero, size: Self.collapsedSize))

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        monitor.onSnapshotChange = { [weak self] snapshot in
            self?.snapshot = snapshot
            self?.needsDisplay = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        guard !isPinned else { return }
        setExpanded(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard !isPinned else { return }
        collapseWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWorkItem = nil
            if !self.mouseIsInsideWindow {
                self.setExpanded(false)
            }
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private var mouseIsInsideWindow: Bool {
        guard let window else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isExpanded {
            for (kind, frame) in buttonFrames where frame.contains(point) {
                handleButton(kind)
                return
            }
        }

        guard event.clickCount == 2 else { return }
        isPinned.toggle()
        setExpanded(true)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        buttonFrames.removeAll()
        drawBackground()

        if isExpanded {
            drawExpanded()
        } else {
            drawCollapsed()
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        frame.size = targetSize
        onSizeChange(targetSize)
        needsDisplay = true
    }

    private func handleButton(_ kind: ButtonKind) {
        switch kind {
        case .refresh:
            monitor.refresh()
        case .pin:
            isPinned.toggle()
            setExpanded(true)
            needsDisplay = true
        case .quit:
            NSApp.terminate(nil)
        }
    }

    // MARK: - Drawing

    private func drawBackground() {
        let radius: CGFloat = isExpanded ? 22 : 16
        let path = bottomRoundedPath(in: bounds, radius: radius)

        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        NSColor(calibratedWhite: 0.04, alpha: 0.97).setFill()
        bounds.fill()

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCollapsed() {
        let claude = provider(.claude)
        let codex = provider(.codex)

        let claudePercent = peakPercent(for: claude)
        let codexPercent = peakPercent(for: codex)

        // Two side-by-side dots + mini bars
        let padding: CGFloat = 14
        let availableWidth = bounds.width - padding * 2
        let halfWidth = (availableWidth - 14) / 2
        let barHeight: CGFloat = 4
        let barY = bounds.midY - barHeight / 2 + 1

        drawSegment(
            x: padding,
            width: halfWidth,
            barY: barY,
            barHeight: barHeight,
            label: "C",
            percent: claudePercent,
            hasData: claude?.state == .ready
        )

        drawSegment(
            x: padding + halfWidth + 14,
            width: halfWidth,
            barY: barY,
            barHeight: barHeight,
            label: "X",
            percent: codexPercent,
            hasData: codex?.state == .ready
        )
    }

    private func drawSegment(x: CGFloat, width: CGFloat, barY: CGFloat, barHeight: CGFloat, label: String, percent: Double?, hasData: Bool) {
        let dotSize: CGFloat = 14
        let dotRect = CGRect(x: x, y: bounds.midY - dotSize / 2, width: dotSize, height: dotSize)

        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        drawText(
            label,
            in: dotRect.insetBy(dx: 0, dy: 0),
            font: .systemFont(ofSize: 9, weight: .bold),
            color: NSColor.white.withAlphaComponent(0.85),
            alignment: .center
        )

        let barX = x + dotSize + 6
        let barWidth = width - dotSize - 6 - 32

        let bar = CGRect(x: barX, y: barY, width: barWidth, height: barHeight)
        NSColor.white.withAlphaComponent(0.10).setFill()
        roundedPath(bar, radius: barHeight / 2).fill()

        if hasData, let pct = percent {
            let fillWidth = max(2, barWidth * CGFloat(pct / 100))
            usageColor(pct).setFill()
            roundedPath(CGRect(x: bar.minX, y: bar.minY, width: fillWidth, height: barHeight), radius: barHeight / 2).fill()
        }

        let textRect = CGRect(x: barX + barWidth + 4, y: bounds.midY - 7, width: 28, height: 14)
        let text = hasData ? (percent.map { "\(Int($0.rounded()))%" } ?? "--") : "--"
        drawText(text, in: textRect, font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: .white, alignment: .right)
    }

    private func drawExpanded() {
        drawHeader()

        let rowHeight: CGFloat = 64
        let rowY: CGFloat = 36

        if let claude = provider(.claude) {
            drawRow(claude, in: CGRect(x: 16, y: rowY, width: bounds.width - 32, height: rowHeight))
        }

        // divider
        let dividerY = rowY + rowHeight + 4
        NSColor.white.withAlphaComponent(0.06).setFill()
        NSRect(x: 16, y: dividerY, width: bounds.width - 32, height: 1).fill()

        if let codex = provider(.codex) {
            drawRow(codex, in: CGRect(x: 16, y: dividerY + 5, width: bounds.width - 32, height: rowHeight))
        }

        drawFooter()
    }

    private func drawHeader() {
        drawText(
            "NotchTokens",
            in: CGRect(x: 16, y: 12, width: 120, height: 14),
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: NSColor.white.withAlphaComponent(0.7)
        )

        if let activity = activityText {
            drawText(
                activity,
                in: CGRect(x: bounds.width - 160, y: 12, width: 144, height: 14),
                font: .systemFont(ofSize: 10, weight: .medium),
                color: NSColor.white.withAlphaComponent(0.45),
                alignment: .right
            )
        }
    }

    private func drawRow(_ provider: ProviderUsage, in rect: CGRect) {
        // Logo
        let logoRect = CGRect(x: rect.minX, y: rect.minY + 4, width: 32, height: 32)
        drawProviderLogo(provider, in: logoRect)

        // Title
        drawText(
            provider.title,
            in: CGRect(x: rect.minX + 42, y: rect.minY + 4, width: 160, height: 16),
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: .white
        )

        // Subtitle (limit label or token count)
        drawText(
            rowSubtitle(provider),
            in: CGRect(x: rect.minX + 42, y: rect.minY + 22, width: 240, height: 13),
            font: .systemFont(ofSize: 10, weight: .medium),
            color: NSColor.white.withAlphaComponent(0.52)
        )

        // Percent label (right side)
        let percent = peakPercent(for: provider)
        let percentText: String = {
            if let p = percent { return "\(Int(p.rounded()))%" }
            return "--"
        }()
        drawText(
            percentText,
            in: CGRect(x: rect.maxX - 60, y: rect.minY + 6, width: 60, height: 18),
            font: .monospacedDigitSystemFont(ofSize: 15, weight: .semibold),
            color: percent.map(usageColor) ?? NSColor.white.withAlphaComponent(0.4),
            alignment: .right
        )

        // Bar
        let barRect = CGRect(x: rect.minX + 42, y: rect.minY + 42, width: rect.width - 42, height: 8)
        drawUsageBar(percent: percent, hasData: provider.state == .ready, in: barRect)

        // Caption under the bar
        if let caption = rowCaption(provider) {
            drawText(
                caption,
                in: CGRect(x: rect.minX + 42, y: rect.minY + 52, width: rect.width - 42, height: 12),
                font: .systemFont(ofSize: 9, weight: .medium),
                color: NSColor.white.withAlphaComponent(0.38)
            )
        }
    }

    private func drawUsageBar(percent: Double?, hasData: Bool, in rect: CGRect) {
        NSColor.white.withAlphaComponent(0.08).setFill()
        roundedPath(rect, radius: rect.height / 2).fill()

        guard hasData, let percent else { return }
        let fillWidth = max(rect.height, rect.width * CGFloat(percent / 100))
        let fillRect = CGRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)

        NSGraphicsContext.saveGraphicsState()
        roundedPath(fillRect, radius: rect.height / 2).addClip()

        let base = usageColor(percent)
        let gradient = NSGradient(colors: [
            base.withAlphaComponent(0.85),
            base,
        ])
        gradient?.draw(in: fillRect, angle: 0)

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawProviderLogo(_ provider: ProviderUsage, in rect: CGRect) {
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.white.withAlphaComponent(0.06).setFill()
        bgPath.fill()

        let assetName = provider.kind == .claude ? "claudecode-color" : "codex-color"
        if let image = NSImage(named: assetName) {
            let inset = rect.insetBy(dx: 4, dy: 4)
            image.draw(in: inset, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        } else {
            let fallback = provider.kind == .claude ? "sparkles" : "chevron.left.forwardslash.chevron.right"
            let tint = provider.kind == .claude
                ? NSColor(calibratedRed: 0.95, green: 0.63, blue: 0.28, alpha: 1)
                : NSColor(calibratedRed: 0.2, green: 0.82, blue: 0.74, alpha: 1)
            drawSymbol(fallback, in: rect.insetBy(dx: 8, dy: 8), color: tint)
        }
    }

    private func drawFooter() {
        var x = bounds.width - 16 - 24
        for kind in ButtonKind.allCases.reversed() {
            let frame = CGRect(x: x, y: bounds.height - 28, width: 24, height: 24)
            buttonFrames[kind] = frame

            NSColor.white.withAlphaComponent(0.06).setFill()
            NSBezierPath(ovalIn: frame).fill()

            let symbolName = kind == .pin && isPinned ? "pin.fill" : kind.symbolName
            drawSymbol(symbolName, in: frame.insetBy(dx: 7, dy: 7), color: NSColor.white.withAlphaComponent(0.78))
            x -= 30
        }
    }

    // MARK: - Helpers

    private func provider(_ kind: ProviderKind) -> ProviderUsage? {
        snapshot.providers.first(where: { $0.kind == kind })
    }

    private func peakPercent(for provider: ProviderUsage?) -> Double? {
        guard let provider, !provider.limits.isEmpty else { return nil }
        return provider.limits.map(\.usedPercent).max()
    }

    private func rowSubtitle(_ provider: ProviderUsage) -> String {
        switch provider.state {
        case .missing: return "Not installed"
        case .failed(let message): return message
        case .empty: return "No usage yet"
        case .ready: break
        }

        if !provider.limits.isEmpty {
            // Find the peak limit window
            if let peak = provider.limits.max(by: { $0.usedPercent < $1.usedPercent }) {
                return "\(peak.name) window"
            }
        }
        return "\(formatTokens(provider.totalTokens)) tokens"
    }

    private func rowCaption(_ provider: ProviderUsage) -> String? {
        guard provider.state == .ready else { return nil }
        var parts: [String] = []
        if provider.totalTokens > 0 {
            parts.append("\(formatTokens(provider.totalTokens)) total")
        }
        if provider.todayTokens > 0 {
            parts.append("\(formatTokens(provider.todayTokens)) today")
        }
        if provider.kind == .codex, provider.cost > 0 {
            parts.append(formatCost(provider.cost))
        }
        if let resets = provider.limits.first?.resetsAt {
            parts.append("resets \(relativeString(resets))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func usageColor(_ percent: Double) -> NSColor {
        let green = NSColor(calibratedRed: 0.34, green: 0.86, blue: 0.58, alpha: 1)
        let yellow = NSColor(calibratedRed: 0.96, green: 0.78, blue: 0.30, alpha: 1)
        let red = NSColor(calibratedRed: 0.95, green: 0.42, blue: 0.42, alpha: 1)

        let clamped = min(max(percent, 0), 100)
        if clamped <= 60 {
            return lerp(green, yellow, t: clamped / 60)
        } else {
            return lerp(yellow, red, t: (clamped - 60) / 40)
        }
    }

    private func lerp(_ a: NSColor, _ b: NSColor, t: Double) -> NSColor {
        let t = CGFloat(min(max(t, 0), 1))
        let ar = a.redComponent, ag = a.greenComponent, ab = a.blueComponent
        let br = b.redComponent, bg = b.greenComponent, bb = b.blueComponent
        return NSColor(
            calibratedRed: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t,
            alpha: 1
        )
    }

    private var activityText: String? {
        guard let latest = snapshot.providers.compactMap(\.lastActivity).max() else {
            return nil
        }
        return relativeString(latest)
    }

    private func relativeString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Drawing primitives

    private func drawSymbol(_ name: String, in rect: CGRect, color: NSColor) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let configured = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: rect.height, weight: .semibold)
        ) ?? image
        configured.isTemplate = true

        NSGraphicsContext.saveGraphicsState()
        color.set()

        let tinted = NSImage(size: rect.size)
        tinted.lockFocus()
        configured.draw(in: CGRect(origin: .zero, size: rect.size), from: .zero, operation: .sourceOver, fraction: 1)
        color.set()
        CGRect(origin: .zero, size: rect.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: rect)

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawText(_ value: String, in rect: CGRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        NSString(string: value).draw(in: rect, withAttributes: attributes)
    }

    private func bottomRoundedPath(in rect: CGRect, radius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.line(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.line(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.curve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            controlPoint1: CGPoint(x: rect.maxX, y: rect.maxY - radius / 2),
            controlPoint2: CGPoint(x: rect.maxX - radius / 2, y: rect.maxY)
        )
        path.line(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.curve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            controlPoint1: CGPoint(x: rect.minX + radius / 2, y: rect.maxY),
            controlPoint2: CGPoint(x: rect.minX, y: rect.maxY - radius / 2)
        )
        path.close()
        return path
    }

    private func roundedPath(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}

private func formatTokens(_ value: Int64) -> String {
    let absValue = abs(Double(value))
    let sign = value < 0 ? "-" : ""

    switch absValue {
    case 1_000_000_000...:
        return "\(sign)\(trim(absValue / 1_000_000_000))B"
    case 1_000_000...:
        return "\(sign)\(trim(absValue / 1_000_000))M"
    case 1_000...:
        return "\(sign)\(trim(absValue / 1_000))K"
    default:
        return "\(value)"
    }
}

private func trim(_ value: Double) -> String {
    let formatted = String(format: "%.1f", value)
    return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
}
