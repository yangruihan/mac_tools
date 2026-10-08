// Derived from Ice 0.11.12 d567f1ec, Jordan Baird. GPL-3.0.
// Standalone owned-fixture candidate; never linked into the product.
import AppKit
struct Logger {
    let category: String
    func error(_ message: String) { fputs("[IceBaseline \(category)] \(message)\n", stderr) }
}
extension CGError { var logString: String { String(rawValue) } }

struct IceBaselineItem: Equatable {
    let windowID: UInt32, pid: Int32
    let key: String
}
enum IceBaselineDestination: Equatable {
    case left(IceBaselineItem), right(IceBaselineItem)
    var item: IceBaselineItem { switch self { case .left(let i), .right(let i): return i } }
}
enum IceBaselineError: Error { case cancelled, identity, geometry, source, timeout, noMovement, tap, budget, menu, pendingDown }

@MainActor
protocol IceBaselineEffects: AnyObject {
    var time: Double { get }
    var lastMouseMove: Double? { get }
    var mouseButtonDown: Bool { get }
    func checkRuntime() throws
    func frame(_ item: IceBaselineItem) throws -> CGRect
    func pause(_ seconds: Double) async throws
    func cursor() throws -> CGPoint
    func hideCursor()
    func showCursor()
    func warp(_ point: CGPoint)
    func configureSuppression() throws
    func beginGesture(down: CGEvent, up: CGEvent) async throws
    func makePacket(_ type:CGEventType,move:Bool,point:CGPoint,item:IceBaselineItem,pid:Int32,marker:Int64)throws->CGEvent
    func prepareRoutingTaps(check: () throws -> Void) throws
    func scromble(_ event: CGEvent, pid: Int32, check: @escaping () throws -> Void) async throws
    func postAndWait(_ event: CGEvent, check: @escaping () throws -> Void) async throws
    func note(_ phase: String, _ values: [String: Any])
}
extension IceBaselineEffects {
    func checkRuntime() throws {}
    func beginGesture(down: CGEvent, up: CGEvent) async throws {}
    func makePacket(_ type:CGEventType,move:Bool,point:CGPoint,item:IceBaselineItem,pid:Int32,marker:Int64)throws->CGEvent {
        try IceBaselinePacket.make(type,move:move,point:point,item:item,pid:pid,marker:marker)
    }
    func prepareRoutingTaps(check: () throws -> Void) throws { try check() }
}

enum IceBaselinePacket {
    // Ice uses one incrementing userData context and a fixed null marker.
    static let nullMarker: Int64 = 0x1CE
    static let matchFields: [CGEventField] = [.eventSourceUserData,
        .mouseEventWindowUnderMousePointer, .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
        CGEventField(rawValue: 0x33)!]
    static func matches(_ a: CGEvent, _ b: CGEvent) -> Bool {
        matchFields.allSatisfy { a.getIntegerValueField($0) == b.getIntegerValueField($0) }
    }
    static func make(_ type: CGEventType, move: Bool, point: CGPoint, item: IceBaselineItem,
                     pid: Int32, marker: Int64) throws -> CGEvent {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(mouseEventSource: source, mouseType: type,
                  mouseCursorPosition: point, mouseButton: .left) else { throw IceBaselineError.source }
        event.flags = move && type == .leftMouseDown ? .maskCommand : []
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        for field in matchFields.dropFirst() { event.setIntegerValueField(field, value: Int64(item.windowID)) }
        if !move { event.setIntegerValueField(.mouseEventClickState, value: 1) }
        // Ice does not set our product's timestamp/number/registry fields.
        return event
    }
    static func summary(_ e: CGEvent) -> [String: Any] {
        ["type": e.type.rawValue, "flags": e.flags.rawValue, "x": e.location.x, "y": e.location.y,
         "pid": e.getIntegerValueField(.eventTargetUnixProcessID),
         "marker": e.getIntegerValueField(.eventSourceUserData),
         "window": e.getIntegerValueField(CGEventField(rawValue: 0x33)!),
         "clickState": e.getIntegerValueField(.mouseEventClickState), "timestamp": e.timestamp]
    }
}

@MainActor
final class IceBaselineEngine {
    let effects: any IceBaselineEffects
    private(set) var cancelled = false
    private(set) var possibleDown = false
    private var marker: Int64 = 0x1CE
    private let deadline: Double
    init(_ effects: any IceBaselineEffects, budget: Double = 45) {
        self.effects = effects; deadline = effects.time + budget
    }
    func cancel() { cancelled = true; effects.note("cancel-requested", [:]) }
    func check() throws {
        if Task.isCancelled { cancelled = true }
        if cancelled { throw IceBaselineError.cancelled }
        guard effects.time <= deadline else { cancelled = true; throw IceBaselineError.budget }
        do { try effects.checkRuntime() } catch { cancelled = true; throw error }
    }
    private func pause(_ seconds: Double) async throws {
        do {
            try check(); try await effects.pause(seconds); try check()
        } catch {
            if Task.isCancelled || error is CancellationError { cancelled = true }
            throw error
        }
    }
    private func packet(_ type: CGEventType, move: Bool, point: CGPoint, item: IceBaselineItem, pid: Int32) throws -> CGEvent {
        defer { marker += 1 }
        return try effects.makePacket(type,move:move,point:point,item:item,pid:pid,marker:marker)
    }
    private func end(_ d: IceBaselineDestination) throws -> CGPoint {
        let f = try effects.frame(d.item)
        switch d { case .left: return CGPoint(x: f.minX, y: f.midY)
        case .right: return CGPoint(x: f.maxX, y: f.midY) }
    }
    func correct(_ item: IceBaselineItem, _ d: IceBaselineDestination) throws -> Bool {
        let f = try effects.frame(item), t = try effects.frame(d.item)
        switch d { case .left: return f.maxX == t.minX; case .right: return f.minX == t.maxX }
    }
    func waitMouse() async throws {
        while let last = effects.lastMouseMove, effects.time - last <= 0.1 {
            try check(); try await pause(0.01)
        }
        try check()
    }
    private func frameChanged(_ item: IceBaselineItem, initial: CGRect) async throws {
        let limit = effects.time + 0.05
        while effects.time < limit {
            try check()
            if try effects.frame(item) != initial { return }
            try await pause(0.001)
        }
        throw IceBaselineError.timeout
    }
    private func scromble(_ event: CGEvent, item: IceBaselineItem, waitFrame: Bool) async throws {
        try check()
        let initial = try effects.frame(item)
        try effects.prepareRoutingTaps(check: { try self.check() })
        if event.type == .leftMouseDown { possibleDown = true }
        try await effects.scromble(event, pid: item.pid, check: { try self.check() })
        if event.type == .leftMouseUp { possibleDown = false } // route return, not physical release proof
        if waitFrame { try await frameChanged(item, initial: initial) }
    }
    private func wake(_ item: IceBaselineItem) async throws {
        effects.note("wake-up", [:]); let f = try effects.frame(item)
        let down = try packet(.leftMouseDown, move: true, point: .init(x:f.midX,y:f.midY), item:item, pid:item.pid)
        let up = try packet(.leftMouseUp, move: true, point: .init(x:f.midX,y:f.midY), item:item, pid:item.pid)
        try await effects.beginGesture(down:down,up:up)
        for event in [down,up] {
            try await scromble(event, item: item, waitFrame: false)
        }
    }
    private func moveOnce(_ item: IceBaselineItem, _ destination: IceBaselineDestination) async throws {
        let f = try effects.frame(item)
        let down = try packet(.leftMouseDown, move: true, point: .init(x: 20_000, y: 20_000), item: item, pid: item.pid)
        let up = try packet(.leftMouseUp, move: true, point: end(destination), item: destination.item, pid: item.pid)
        let fallback = try packet(.leftMouseUp, move: true, point: .init(x: f.midX, y: f.midY), item: item, pid: item.pid)
        try await effects.beginGesture(down:down,up:up)
        try check(); try effects.configureSuppression()
        do {
            try await scromble(down, item: item, waitFrame: true)
            try await scromble(up, item: item, waitFrame: true)
        } catch {
            // Necessary difference: explicit cancel/deadline never permits cleanup/retry.
            try check()
            effects.note("move-fallback", [:])
            do { try effects.prepareRoutingTaps(check: { try self.check() }); try await effects.postAndWait(fallback, check: { try self.check() }) } catch { }
            throw error
        }
    }
    func move(_ item: IceBaselineItem, to destination: IceBaselineDestination, slow: Bool = true) async throws {
        try check()
        if try correct(item, destination) { return }
        try await waitMouse(); let cursor = try effects.cursor(), initial = try effects.frame(item)
        effects.hideCursor()
        defer {
            // Balance visibility on cancel, but do not pull the user's cursor back.
            if !cancelled && !Task.isCancelled && effects.time <= deadline, (try? check()) != nil { effects.warp(cursor) }
            effects.showCursor()
        }
        for attempt in 1...5 {
            try check(); effects.note("move-attempt", ["attempt": attempt, "target": item.windowID])
            do {
                try await moveOnce(item, destination)
                guard try effects.frame(item) != initial else { throw IceBaselineError.noMovement }
                break
            } catch {
                try check()
                if attempt == 5 { throw error }
                try await wake(item)
            }
        }
        if slow {
            let limit = effects.time + 1
            while try !correct(item, destination) {
                try check(); guard effects.time < limit else { throw IceBaselineError.timeout }
                try await pause(0.001)
            }
        }
    }
    func click(_ item: IceBaselineItem) async throws {
        try check(); let f = try effects.frame(item), cursor = try effects.cursor()
        let point = CGPoint(x: f.midX, y: f.midY)
        let down = try packet(.leftMouseDown, move: false, point: point, item: item, pid: item.pid)
        let up = try packet(.leftMouseUp, move: false, point: point, item: item, pid: item.pid)
        let fallback = try packet(.leftMouseUp, move: false, point: point, item: item, pid: item.pid)
        try await effects.beginGesture(down:down,up:up)
        try effects.configureSuppression(); effects.hideCursor()
        defer { if !cancelled && !Task.isCancelled && effects.time <= deadline, (try? check()) != nil { effects.warp(cursor) }; effects.showCursor() }
        do {
            try effects.prepareRoutingTaps(check: { try self.check() })
            possibleDown = true; try await effects.postAndWait(down, check: { try self.check() })
            try effects.prepareRoutingTaps(check: { try self.check() })
            try await effects.postAndWait(up, check: { try self.check() }); possibleDown = false
        } catch {
            try check(); effects.note("click-fallback", [:])
            do { try effects.prepareRoutingTaps(check: { try self.check() }); try await effects.postAndWait(fallback, check: { try self.check() }) } catch { }
            throw error
        }
    }
    func rehide(_ item: IceBaselineItem, to destination: IceBaselineDestination,
                interfaceOpen: () throws -> Bool, interval: Double = 15) async throws {
        try await pause(interval); try check()
        while try effects.mouseButtonDown || interfaceOpen() {
            effects.note("rehide-delayed", [:]); try await pause(3); try check()
        }
        while true {
            do { try await move(item, to: destination); return }
            catch { try check(); effects.note("rehide-retry", [:]); try await pause(3) }
        }
    }
}
