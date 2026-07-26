import AppKit

enum KeyKongTheme {
    static let charcoal = NSColor(hex: 0x17191D)
    static let graphite = NSColor(hex: 0x252932)
    static let slate = NSColor(hex: 0x343B47)
    static let cobalt = NSColor(hex: 0x5376A6)
    static let brass = NSColor(hex: 0xC99646)
    static let silver = NSColor(hex: 0xAEB4BD)

    static var emblem: NSImage? {
        Bundle.main.url(
            forResource: "keykong-app-icon-emblem",
            withExtension: "png"
        ).flatMap(NSImage.init(contentsOf:))
    }

    @MainActor
    static func style(_ field: NSTextField) {
        let cell: NSTextFieldCell = field is NSSecureTextField
            ? KeyKongSecureTextFieldCell(textCell: "")
            : KeyKongTextFieldCell(textCell: "")
        cell.isEditable = true
        cell.isSelectable = true
        cell.isScrollable = true
        cell.wraps = false
        cell.lineBreakMode = .byClipping
        field.cell = cell
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.backgroundColor = graphite
        field.textColor = .white
        field.font = .systemFont(ofSize: 14)
        field.focusRingType = .default
        field.placeholderString = nil
    }

    @MainActor
    static func symbol(
        _ name: String,
        description: String,
        glyphLimit: CGFloat = 14
    ) -> NSImage? {
        guard let glyph = NSImage(
            systemSymbolName: name,
            accessibilityDescription: description
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(
                pointSize: 14,
                weight: .semibold
            ).applying(
                NSImage.SymbolConfiguration(hierarchicalColor: brass)
            )
        ) else {
            return nil
        }
        let canvasSize = NSSize(width: 18, height: 18)
        let scale = min(
            glyphLimit / glyph.size.width,
            glyphLimit / glyph.size.height
        )
        let glyphSize = NSSize(
            width: glyph.size.width * scale,
            height: glyph.size.height * scale
        )
        return NSImage(size: canvasSize, flipped: false) { bounds in
            glyph.draw(
                in: NSRect(
                    x: bounds.midX - glyphSize.width / 2,
                    y: bounds.midY - glyphSize.height / 2,
                    width: glyphSize.width,
                    height: glyphSize.height
                )
            )
            return true
        }
    }

    @MainActor
    static func stylePrimaryButton(_ button: NSButton) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = brass.cgColor
        button.layer?.borderColor = cobalt.cgColor
        button.layer?.borderWidth = 1.5
        button.layer?.cornerRadius = 7
        button.contentTintColor = charcoal
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: charcoal,
                .font: NSFont.systemFont(ofSize: 13, weight: .medium)
            ]
        )
        button.focusRingType = .default
    }

    @MainActor
    static func styleSecondaryButton(_ button: NSButton) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = slate.cgColor
        button.layer?.borderColor = silver.withAlphaComponent(0.22).cgColor
        button.layer?.borderWidth = 1
        button.layer?.cornerRadius = 7
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .regular)
            ]
        )
        button.focusRingType = .default
    }

    @MainActor
    static func style(_ button: NSPopUpButton) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = graphite.cgColor
        button.layer?.borderColor = slate.cgColor
        button.layer?.borderWidth = 1
        button.layer?.cornerRadius = 6
        button.contentTintColor = silver
        button.font = .systemFont(ofSize: 14)
        button.focusRingType = .default
    }

    @MainActor
    static func styleCheckbox(_ button: NSButton) {
        button.contentTintColor = brass
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [
                .foregroundColor: silver,
                .font: NSFont.systemFont(ofSize: 13)
            ]
        )
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

final class KeyKongBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(
            colorsAndLocations:
                (KeyKongTheme.graphite, 0),
                (KeyKongTheme.charcoal, 0.72),
                (KeyKongTheme.charcoal.blended(
                    withFraction: 0.18,
                    of: KeyKongTheme.slate
                ) ?? KeyKongTheme.charcoal, 1)
        )?.draw(in: bounds, angle: -90)

        KeyKongTheme.slate.withAlphaComponent(0.8).setStroke()
        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: 0, y: bounds.maxY - 38.5))
        divider.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - 38.5))
        divider.lineWidth = 1
        divider.stroke()
    }
}

final class KeyKongFlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private func verticallyCenteredTextRect(
    for cell: NSCell,
    bounds: NSRect,
    drawingRect: NSRect
) -> NSRect {
    guard let font = cell.font else { return drawingRect }
    let height = ceil(font.ascender - font.descender + font.leading)
    return NSRect(
        x: drawingRect.minX,
        y: floor(bounds.midY - height / 2),
        width: drawingRect.width,
        height: height
    )
}

final class KeyKongTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        verticallyCenteredTextRect(
            for: self,
            bounds: rect,
            drawingRect: super.drawingRect(forBounds: rect)
        )
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObject: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: drawingRect(forBounds: rect),
            in: controlView,
            editor: textObject,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObject: NSText,
        delegate: Any?,
        start selectionStart: Int,
        length selectionLength: Int
    ) {
        super.select(
            withFrame: drawingRect(forBounds: rect),
            in: controlView,
            editor: textObject,
            delegate: delegate,
            start: selectionStart,
            length: selectionLength
        )
    }
}

final class KeyKongSecureTextFieldCell: NSSecureTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        verticallyCenteredTextRect(
            for: self,
            bounds: rect,
            drawingRect: super.drawingRect(forBounds: rect)
        )
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObject: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: drawingRect(forBounds: rect),
            in: controlView,
            editor: textObject,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObject: NSText,
        delegate: Any?,
        start selectionStart: Int,
        length selectionLength: Int
    ) {
        super.select(
            withFrame: drawingRect(forBounds: rect),
            in: controlView,
            editor: textObject,
            delegate: delegate,
            start: selectionStart,
            length: selectionLength
        )
    }
}
