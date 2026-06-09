//
//  NotchUsagePanelView.swift
//  NotchTokens
//

import AppKit

@MainActor
final class NotchUsagePanelView: NSView {
    private enum ButtonKind: CaseIterable {
        case refresh
        case settings
        case pin
        case quit

        var symbolName: String {
            switch self {
            case .refresh: "arrow.clockwise"
            case .settings: "gearshape"
            case .pin: "pin"
            case .quit: "power"
            }
        }
    }

    private let monitor: UsageMonitor
    private let onSizeChange: (CGSize) -> Void
    private let onOpenSettings: () -> Void
    private var trackingArea: NSTrackingArea?
    private var snapshot: UsageSnapshot
    private var isExpanded = false
    private var isPinned = false
    private var buttonFrames: [ButtonKind: CGRect] = [:]
    private var rowFrames: [ProviderKind: CGRect] = [:]
    private var hoveredButton: ButtonKind?
    private var hoveredRow: ProviderKind?
    private var collapseWorkItem: DispatchWorkItem?
    private var isRefreshing = false
    private var refreshAngle: CGFloat = 0
    private var refreshTimer: Timer?

    private static let collapsedSize = CGSize(width: 340, height: 68)
    private static let expandedSize = CGSize(width: 380, height: 292)

    private var targetSize: CGSize {
        isExpanded ? Self.expandedSize : Self.collapsedSize
    }

    override var isFlipped: Bool { true }

    init(monitor: UsageMonitor, onSizeChange: @escaping (CGSize) -> Void, onOpenSettings: @escaping () -> Void) {
        self.monitor = monitor
        self.onSizeChange = onSizeChange
        self.onOpenSettings = onOpenSettings
        self.snapshot = monitor.snapshot

        super.init(frame: CGRect(origin: .zero, size: Self.collapsedSize))

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityHelp("Shows AI coding-tool usage. Move the pointer over it to expand.")
        updateAccessibility()

        monitor.onSnapshotChange = { [weak self] snapshot in
            self?.snapshot = snapshot
            self?.updateAccessibility()
            self?.stopRefreshAnimation()
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
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
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

    override func mouseMoved(with event: NSEvent) {
        guard isExpanded else { return }
        let point = convert(event.locationInWindow, from: nil)
        let newHoverButton = buttonFrames.first(where: { $0.value.contains(point) })?.key
        let newHoverRow =
            newHoverButton == nil
            ? rowFrames.first(where: { $0.value.contains(point) })?.key
            : nil

        if newHoverButton != nil || newHoverRow != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }

        if newHoverButton != hoveredButton || newHoverRow != hoveredRow {
            hoveredButton = newHoverButton
            hoveredRow = newHoverRow
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredButton != nil || hoveredRow != nil {
            hoveredButton = nil
            hoveredRow = nil
            NSCursor.arrow.set()
            needsDisplay = true
        }
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
            for (kind, frame) in rowFrames where frame.contains(point) {
                handleRowClick(kind, copy: event.modifierFlags.contains(.command))
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
        rowFrames.removeAll()
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
        if !expanded {
            hoveredButton = nil
            hoveredRow = nil
        }
        onSizeChange(targetSize)
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    private func handleButton(_ kind: ButtonKind) {
        switch kind {
        case .refresh:
            startRefreshAnimation()
            monitor.refresh()
        case .settings:
            onOpenSettings()
        case .pin:
            isPinned.toggle()
            setExpanded(true)
            needsDisplay = true
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func handleRowClick(_ kind: ProviderKind, copy: Bool) {
        guard let provider = snapshot.providers.first(where: { $0.kind == kind }) else { return }
        if copy {
            copyStats(for: provider)
        } else if let url = Self.dashboardURL(for: kind) {
            NSWorkspace.shared.open(url)
        } else {
            copyStats(for: provider)
        }
    }

    private func copyStats(for provider: ProviderUsage) {
        var line = provider.title
        if let percent = peakPercent(for: provider) {
            line += " — \(Int(percent.rounded()))%"
        }
        if let caption = rowCaption(provider) {
            line += " · \(caption)"
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(line, forType: .string)
    }

    /// Best-effort landing page where each provider's usage can be reviewed. OpenCode is
    /// local-only, so its rows fall back to copying stats.
    private static func dashboardURL(for kind: ProviderKind) -> URL? {
        switch kind {
        case .claude: URL(string: "https://claude.ai/settings/usage")
        case .codex: URL(string: "https://platform.openai.com/usage")
        case .opencode: nil
        }
    }

    private func startRefreshAnimation() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshTimer?.invalidate()
        let timer = Timer(
            timeInterval: 1.0 / 30.0,
            target: self,
            selector: #selector(advanceRefreshSpinner),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        // Safety net: never leave the spinner stuck if a refresh never republishes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.stopRefreshAnimation()
        }
    }

    @objc private func advanceRefreshSpinner() {
        refreshAngle += 0.28
        needsDisplay = true
    }

    private func stopRefreshAnimation() {
        guard isRefreshing else { return }
        isRefreshing = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshAngle = 0
        needsDisplay = true
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
        let providers = snapshot.providers
        guard !providers.isEmpty else {
            drawText(
                "No providers",
                in: CGRect(x: 14, y: bounds.height - 28, width: bounds.width - 28, height: 16),
                font: .systemFont(ofSize: 11, weight: .semibold),
                color: NSColor.white.withAlphaComponent(0.62),
                alignment: .center
            )
            return
        }

        let padding: CGFloat = 14
        let gap: CGFloat = 10
        let segmentCount = CGFloat(providers.count)
        let segmentWidth = (bounds.width - padding * 2 - gap * (segmentCount - 1)) / segmentCount
        let barHeight: CGFloat = 5
        let contentCenterY = bounds.height - 19
        let barY = contentCenterY - barHeight / 2

        for (index, provider) in providers.enumerated() {
            drawSegment(
                x: padding + CGFloat(index) * (segmentWidth + gap),
                width: segmentWidth,
                contentCenterY: contentCenterY,
                barY: barY,
                barHeight: barHeight,
                provider: provider,
                percent: peakPercent(for: provider),
                hasData: provider.state == .ready
            )
        }
    }

    private func drawSegment(
        x: CGFloat,
        width: CGFloat,
        contentCenterY: CGFloat,
        barY: CGFloat,
        barHeight: CGFloat,
        provider: ProviderUsage?,
        percent: Double?,
        hasData: Bool
    ) {
        let logoSize: CGFloat = 20
        let logoRect = CGRect(x: x, y: contentCenterY - logoSize / 2, width: logoSize, height: logoSize)

        if let provider {
            drawCompactProviderLogo(provider, in: logoRect)
        } else {
            drawSymbol(
                "questionmark", in: logoRect.insetBy(dx: 4, dy: 4), color: NSColor.white.withAlphaComponent(0.45))
        }

        if let provider, let badge = statusBadge(for: provider) {
            let size: CGFloat = 11
            drawSymbol(
                badge.symbol,
                in: CGRect(x: logoRect.maxX - 6, y: logoRect.minY - 3, width: size, height: size),
                color: badge.color
            )
        }

        let textWidth: CGFloat = 34
        let barX = logoRect.maxX + 7
        let barWidth = max(10, width - logoSize - 7 - textWidth - 5)

        let bar = CGRect(x: barX, y: barY, width: barWidth, height: barHeight)
        NSColor.white.withAlphaComponent(0.10).setFill()
        roundedPath(bar, radius: barHeight / 2).fill()

        if hasData, let pct = percent {
            let fillWidth = max(2, barWidth * CGFloat(pct / 100))
            usageColor(pct).setFill()
            roundedPath(CGRect(x: bar.minX, y: bar.minY, width: fillWidth, height: barHeight), radius: barHeight / 2)
                .fill()
        }

        let textRect = CGRect(x: bar.maxX + 5, y: contentCenterY - 8, width: textWidth, height: 16)
        let text = hasData ? (percent.map { "\(Int($0.rounded()))%" } ?? "--") : "--"
        drawText(
            text, in: textRect, font: .monospacedDigitSystemFont(ofSize: 10, weight: .semibold), color: .white,
            alignment: .right)
    }

    private func drawExpanded() {
        drawHeader()

        let rowHeight: CGFloat = 60
        let rowGap: CGFloat = 10
        var y: CGFloat = 36

        if snapshot.providers.isEmpty {
            drawText(
                "No providers enabled",
                in: CGRect(x: 16, y: y + 24, width: bounds.width - 32, height: 16),
                font: .systemFont(ofSize: 12, weight: .medium),
                color: NSColor.white.withAlphaComponent(0.52),
                alignment: .center
            )
            drawFooter()
            return
        }

        for (index, provider) in snapshot.providers.enumerated() {
            drawRow(provider, in: CGRect(x: 16, y: y, width: bounds.width - 32, height: rowHeight))
            y += rowHeight

            if index < snapshot.providers.count - 1 {
                NSColor.white.withAlphaComponent(0.06).setFill()
                NSRect(x: 16, y: y + 4, width: bounds.width - 32, height: 1).fill()
                y += rowGap
            }
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
        rowFrames[provider.kind] = rect

        // Hover highlight — signals the whole row is one clickable target.
        if hoveredRow == provider.kind {
            let highlight = CGRect(x: rect.minX - 6, y: rect.minY - 2, width: rect.width + 12, height: 64)
            NSColor.white.withAlphaComponent(0.06).setFill()
            roundedPath(highlight, radius: 9).fill()
        }

        // Logo
        let logoRect = CGRect(x: rect.minX, y: rect.minY + 4, width: 32, height: 32)
        drawProviderLogo(provider, in: logoRect)

        // Title
        let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        drawText(
            provider.title,
            in: CGRect(x: rect.minX + 42, y: rect.minY + 4, width: 160, height: 16),
            font: titleFont,
            color: .white
        )

        // On hover, an "opens externally" hint trailing the title (only when a row opens a URL).
        if hoveredRow == provider.kind, Self.dashboardURL(for: provider.kind) != nil {
            let titleWidth = (provider.title as NSString).size(withAttributes: [.font: titleFont]).width
            let glyphRect = CGRect(x: rect.minX + 42 + titleWidth + 6, y: rect.minY + 6, width: 11, height: 11)
            drawSymbol("arrow.up.forward", in: glyphRect, color: NSColor.white.withAlphaComponent(0.5))
        }

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

        if let badge = statusBadge(for: provider) {
            drawSymbol(
                badge.symbol,
                in: CGRect(x: rect.maxX - 78, y: rect.minY + 8, width: 13, height: 13),
                color: badge.color
            )
        }

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
        NSColor.white.setFill()
        bgPath.fill()

        if let image = NSImage(named: provider.kind.assetName) {
            let fit = Self.aspectFitRect(imageSize: image.size, in: rect.insetBy(dx: 4, dy: 4))
            image.draw(in: fit, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        } else {
            drawSymbol("questionmark", in: rect.insetBy(dx: 8, dy: 8), color: NSColor.white.withAlphaComponent(0.4))
        }
    }

    private func drawCompactProviderLogo(_ provider: ProviderUsage, in rect: CGRect) {
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.white.withAlphaComponent(0.95).setFill()
        bgPath.fill()

        if let image = NSImage(named: provider.kind.assetName) {
            let fit = Self.aspectFitRect(imageSize: image.size, in: rect.insetBy(dx: 3, dy: 3))
            image.draw(in: fit, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
        } else {
            drawSymbol("questionmark", in: rect.insetBy(dx: 5, dy: 5), color: NSColor.black.withAlphaComponent(0.45))
        }
    }

    private static func aspectFitRect(imageSize: CGSize, in container: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return container }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: container.midX - size.width / 2,
            y: container.midY - size.height / 2
        )
        return CGRect(origin: origin, size: size)
    }

    private func drawFooter() {
        let buttonSize: CGFloat = 28
        let spacing: CGFloat = 6
        var x = bounds.width - 16 - buttonSize

        for kind in ButtonKind.allCases.reversed() {
            let frame = CGRect(x: x, y: bounds.height - buttonSize - 8, width: buttonSize, height: buttonSize)
            buttonFrames[kind] = frame

            let isHovered = hoveredButton == kind
            let isActive = kind == .pin && isPinned

            let fillAlpha: CGFloat = isHovered ? 0.22 : (isActive ? 0.16 : 0.10)
            let strokeAlpha: CGFloat = isHovered ? 0.28 : 0.14
            let iconAlpha: CGFloat = isHovered ? 1.0 : (isActive ? 0.95 : 0.78)

            let path = NSBezierPath(ovalIn: frame)
            NSColor.white.withAlphaComponent(fillAlpha).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(strokeAlpha).setStroke()
            path.lineWidth = 1
            path.stroke()

            let symbolName = kind == .pin && isPinned ? "pin.fill" : kind.symbolName
            let rotation: CGFloat = (kind == .refresh && isRefreshing) ? refreshAngle : 0
            drawSymbol(
                symbolName, in: frame.insetBy(dx: 8, dy: 8), color: NSColor.white.withAlphaComponent(iconAlpha),
                rotation: rotation)

            x -= (buttonSize + spacing)
        }
    }

    // MARK: - Helpers

    private func peakPercent(for provider: ProviderUsage?) -> Double? {
        guard let provider, !provider.limits.isEmpty else { return nil }
        return provider.limits.map(\.usedPercent).max()
    }

    private var alertThreshold: Double {
        monitor.settings.settings.alertThreshold
    }

    private func isWarning(_ provider: ProviderUsage) -> Bool {
        guard provider.state == .ready, let peak = peakPercent(for: provider) else { return false }
        return peak >= alertThreshold
    }

    // MARK: - Accessibility

    private func updateAccessibility() {
        let providers = snapshot.providers
        guard !providers.isEmpty else {
            setAccessibilityLabel("NotchTokens. No providers enabled.")
            return
        }
        let parts = providers.map(accessibilityDescription)
        setAccessibilityLabel("NotchTokens usage. " + parts.joined(separator: ". ") + ".")
    }

    private func accessibilityDescription(for provider: ProviderUsage) -> String {
        switch provider.state {
        case .missing: return "\(provider.title), not installed"
        case .empty: return "\(provider.title), no usage yet"
        case .failed(let message): return "\(provider.title), error, \(message)"
        case .ready: break
        }

        guard let peak = peakPercent(for: provider) else {
            return "\(provider.title), \(formatTokens(provider.totalTokens)) tokens"
        }
        let windowName = provider.limits.max(by: { $0.usedPercent < $1.usedPercent })?.name ?? "usage"
        let warning = peak >= alertThreshold ? ", nearing limit" : ""
        return "\(provider.title), \(Int(peak.rounded())) percent of \(windowName) limit\(warning)"
    }

    private static let warningColor = NSColor(calibratedRed: 0.98, green: 0.74, blue: 0.18, alpha: 1)
    private static let errorColor = NSColor(calibratedRed: 0.95, green: 0.42, blue: 0.42, alpha: 1)

    /// The status badge (symbol + tint) to overlay for a provider, or nil when nothing
    /// needs flagging. A fetch error takes precedence over the near-limit warning.
    private func statusBadge(for provider: ProviderUsage) -> (symbol: String, color: NSColor)? {
        if case .failed = provider.state {
            return ("exclamationmark.circle.fill", Self.errorColor)
        }
        if isWarning(provider) {
            return ("exclamationmark.triangle.fill", Self.warningColor)
        }
        return nil
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
        if let limitStatus = provider.limitStatus {
            return limitStatus
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
        if provider.costWindowCost > 0 {
            parts.append("\(formatCost(provider.costWindowCost)) \(provider.costWindowLabel)")
        } else if provider.cost > 0 {
            parts.append(formatCost(provider.cost))
        }
        if let peak = provider.limits.max(by: { $0.usedPercent < $1.usedPercent }),
            let resets = peak.resetsAt
        {
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
        let ar = a.redComponent
        let ag = a.greenComponent
        let ab = a.blueComponent
        let br = b.redComponent
        let bg = b.greenComponent
        let bb = b.blueComponent
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

    private func drawSymbol(_ name: String, in rect: CGRect, color: NSColor, rotation: CGFloat = 0) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let configured =
            image.withSymbolConfiguration(
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

        if rotation != 0 {
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byRadians: rotation)
            transform.translateX(by: -rect.midX, yBy: -rect.midY)
            transform.concat()
        }
        tinted.draw(in: rect)

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawText(
        _ value: String, in rect: CGRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left
    ) {
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
