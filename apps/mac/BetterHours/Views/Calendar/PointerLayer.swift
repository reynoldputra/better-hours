import AppKit
import SwiftUI

struct PointerEvent {
    enum Phase { case down, dragged, up, moved, exited }
    var phase: Phase
    var location: CGPoint
    var width: CGFloat
    var clickCount: Int
}

enum GridKey { case open, delete, escape }

struct PointerLayer: NSViewRepresentable {
    var onPointer: @MainActor (PointerEvent) -> NSCursor?
    var onKey: @MainActor (GridKey) -> Bool

    func makeNSView(context: Context) -> PointerView {
        let view = PointerView()
        view.onPointer = onPointer
        view.onKey = onKey
        return view
    }

    func updateNSView(_ view: PointerView, context: Context) {
        view.onPointer = onPointer
        view.onKey = onKey
    }
}

final class PointerView: NSView {
    var onPointer: (@MainActor (PointerEvent) -> NSCursor?)?
    var onKey: (@MainActor (GridKey) -> Bool)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        send(.down, event)
    }

    override func mouseDragged(with event: NSEvent) {
        autoscroll(with: event)
        send(.dragged, event)
    }

    override func mouseUp(with event: NSEvent) { send(.up, event) }
    override func mouseMoved(with event: NSEvent) { send(.moved, event) }
    override func mouseEntered(with event: NSEvent) { send(.moved, event) }

    override func mouseExited(with event: NSEvent) {
        send(.exited, event)
        NSCursor.arrow.set()
    }

    override func keyDown(with event: NSEvent) {
        let key: GridKey? = switch event.keyCode {
        case 36, 76: .open
        case 51, 117: .delete
        case 53: .escape
        default: nil
        }
        if let key, event.modifierFlags.intersection([.command, .option, .control]).isEmpty, onKey?(key) == true {
            return
        }
        super.keyDown(with: event)
    }

    private func send(_ phase: PointerEvent.Phase, _ event: NSEvent) {
        // clickCount raises on entered, exited and moved events.
        let isButtonEvent = phase == .down || phase == .up || phase == .dragged
        let event = PointerEvent(
            phase: phase,
            location: convert(event.locationInWindow, from: nil),
            width: bounds.width,
            clickCount: isButtonEvent ? event.clickCount : 0
        )
        onPointer?(event)?.set()
    }
}
