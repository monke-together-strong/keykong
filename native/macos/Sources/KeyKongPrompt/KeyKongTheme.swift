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
        guard glyph.size.width > 0, glyph.size.height > 0 else {
            return nil
        }
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
    static func shieldLockSymbol(description: String) -> NSImage? {
        // Bootstrap Icons "shield-lock-fill", MIT licensed.
        // https://icons.getbootstrap.com/icons/shield-lock-fill/
        let svg = #"""
        <svg xmlns="http://www.w3.org/2000/svg"
             width="18" height="18"
             viewBox="-2.2857 -2.2857 20.5714 20.5714">
          <path fill="#C99646" fill-rule="evenodd"
                d="M8 0c-.69 0-1.843.265-2.928.56-1.11.3-2.229.655-2.887.87a1.54 1.54 0 0 0-1.044 1.262c-.596 4.477.787 7.795 2.465 9.99a11.8 11.8 0 0 0 2.517 2.453c.386.273.744.482 1.048.625.28.132.581.24.829.24s.548-.108.829-.24a7 7 0 0 0 1.048-.625 11.8 11.8 0 0 0 2.517-2.453c1.678-2.195 3.061-5.513 2.465-9.99a1.54 1.54 0 0 0-1.044-1.263 63 63 0 0 0-2.887-.87C9.843.266 8.69 0 8 0m0 5a1.5 1.5 0 0 1 .5 2.915l.385 1.99a.5.5 0 0 1-.491.595h-.788a.5.5 0 0 1-.49-.595l.384-1.99A1.5 1.5 0 0 1 8 5"/>
        </svg>
        """#
        guard let image = NSImage(data: Data(svg.utf8)) else {
            return nil
        }
        image.accessibilityDescription = description
        return image
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
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
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
        let titlebarHeight = window.map {
            bounds.height - convert($0.contentLayoutRect, from: nil).height
        } ?? 38.5
        let dividerY = bounds.maxY - titlebarHeight + 0.5
        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: 0, y: dividerY))
        divider.line(to: NSPoint(x: bounds.maxX, y: dividerY))
        divider.lineWidth = 1
        divider.stroke()
    }
}

final class KeyKongFlippedView: NSView {
    override var isFlipped: Bool { true }
}

class KeyKongPopUpButton: NSPopUpButton {
    override var acceptsFirstResponder: Bool { true }

    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}

final class KeyKongCheckboxButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
class KeyKongPointerButton: NSButton {
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

@MainActor
enum KeyKongPointerCursor {
    private static let marker = "KeyKongPointerCursor"

    static func install(on view: NSView) {
        guard !isInstalled(on: view) else {
            return
        }
        view.addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.activeInKeyWindow, .cursorUpdate, .inVisibleRect],
                owner: KeyKongPointerCursorOwner.shared,
                userInfo: [marker: true]
            )
        )
    }

    static func isInstalled(on view: NSView) -> Bool {
        view.trackingAreas.contains {
            $0.userInfo?[marker] as? Bool == true
        }
    }
}

@MainActor
private final class KeyKongPointerCursorOwner: NSObject {
    static let shared = KeyKongPointerCursorOwner()

    @objc func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
}

@MainActor
private func verticallyCenteredTextRect(
    for cell: NSCell,
    bounds: NSRect,
    drawingRect: NSRect,
    trailingInset: CGFloat
) -> NSRect {
    guard let font = cell.font else { return drawingRect }
    let height = ceil(font.ascender - font.descender + font.leading)
    return NSRect(
        x: drawingRect.minX,
        y: floor(bounds.midY - height / 2),
        width: max(0, drawingRect.width - trailingInset),
        height: height
    )
}

final class KeyKongTextFieldCell: NSTextFieldCell {
    var trailingTextInset: CGFloat = 0

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        verticallyCenteredTextRect(
            for: self,
            bounds: rect,
            drawingRect: super.drawingRect(forBounds: rect),
            trailingInset: trailingTextInset
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
    var trailingTextInset: CGFloat = 0

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        verticallyCenteredTextRect(
            for: self,
            bounds: rect,
            drawingRect: super.drawingRect(forBounds: rect),
            trailingInset: trailingTextInset
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
