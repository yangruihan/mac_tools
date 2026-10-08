// Adapted from Ice 0.11.12, MenuBarItemManager.swift, commit
// d567f1ecac68936a090d6b47d6f0b882c489c6f4. Copyright (c) Jordan Baird.
// Modifications Copyright (c) 2026 Ryan.AI. GPL-3.0; see COPYING.GPL-3.0.
import ApplicationServices
import Darwin
import Foundation

/// Packet construction only: no posts, suppression settings or permission requests.
/// The private window-number field is the already authorized Ice field 0x33.
enum IceOwnedMouseEvent {
    enum Failure: Error { case invalid, creation }
    static func make(type: CGEventType, point: CGPoint, pid: Int32, window: UInt32,
                     command: Bool, marker: Int64, number: Int64, source: CGEventSource) throws -> CGEvent {
        guard [.leftMouseDown, .leftMouseUp].contains(type), pid > 0, window > 0,
              marker > 0, Int16(exactly: number) != nil, point.x.isFinite, point.y.isFinite else { throw Failure.invalid }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                  mouseCursorPosition: point, mouseButton: .left) else { throw Failure.creation }
        // Quartz construction leaves timestamp zero; initialize the exact
        // monotonic nanosecond packet before registration, not after posting.
        event.timestamp = UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
        event.flags = command ? .maskCommand : []
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.setIntegerValueField(.mouseEventNumber, value: number)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
        event.setIntegerValueField(CGEventField(rawValue: 0x33)!, value: Int64(window))
        if !command { event.setIntegerValueField(.mouseEventClickState, value: 1) }
        return event
    }
}
