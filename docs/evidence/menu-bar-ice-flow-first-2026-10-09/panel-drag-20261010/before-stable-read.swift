// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import AppKit

/// Ordinary targets use actual process/window metadata. They never impersonate
/// the owned fixture's published NSStatusItem instance UUIDs.
struct MenuBarIceSelectedTarget: Codable, Equatable {
    struct Row: Identifiable, Equatable {
        let id: UInt32, pid: Int32, title: String, frame: CGRect
    }
    struct Directory {
        let display: UInt32, space: UInt64, rows: [Row]
    }
    let nonce: UUID, owner: MenuBarProcessSignature.Proof
    let windowID: UInt32, display: UInt32, space: UInt64, originalFrame: CGRect
    enum Failure: Error { case scope, missing, identity, changed }

    init(row: Row, directory: Directory, owner: MenuBarProcessSignature.Proof, nonce: UUID = UUID()) throws {
        guard directory.display > 0, directory.space > 0,
              directory.rows.filter({ $0.id == row.id }).count == 1,
              directory.rows.contains(row), row.id > 0, Self.valid(row.frame) else { throw Failure.missing }
        guard owner.pid == row.pid, owner.pid > 0,
              let launch = owner.launch, launch.isFinite, launch > 0,
              !owner.identifier.isEmpty, owner.executable.hasPrefix("/"), owner.sha256.count == 64 else { throw Failure.identity }
        self.nonce = nonce; self.owner = owner; windowID = row.id
        display = directory.display; space = directory.space; originalFrame = row.frame
    }
    /// Exact window and exact launch only. A restart or a sibling is not rematched.
    func validate(directory: Directory, owner current: MenuBarProcessSignature.Proof) throws -> Row {
        guard current == owner else { throw Failure.identity }
        guard directory.display == display, directory.space == space else { throw Failure.scope }
        let rows = directory.rows.filter { $0.id == windowID }
        guard rows.count == 1, rows[0].pid == owner.pid, Self.valid(rows[0].frame) else { throw Failure.missing }
        return rows[0]
    }
    private static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && [frame.minX,frame.minY,frame.width,frame.height].allSatisfy(\.isFinite)
            && frame.width > 8 && frame.width < 150 && frame.height > 0 && frame.height < 64
    }
    /// Existing read-only Ice bindings plus public CGWindow metadata; no new API,
    /// image capture, AX action, sender, permission request or preference write.
    static func readDirectory(includeOwn: Bool = false) throws -> Directory {
        guard NSScreen.screens.count == 1, let screen = NSScreen.screens.first,
              let display = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              let publicRows = CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]] else { throw Failure.scope }
        let directory = try IceMenuBarReadAdapter.isolatedReadOnly().read()
        let grouped = Dictionary(grouping:publicRows, by: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0 })
        let bounds = CGDisplayBounds(display), ownPID = ProcessInfo.processInfo.processIdentifier
        let rows = directory.members.compactMap { member -> Row? in
            guard member.spaces.contains(directory.spaceAfter), Self.valid(member.frame),
                  abs(member.frame.minY-bounds.minY) < 1,
                  let matches = grouped[member.windowID], matches.count == 1, let row = matches.first,
                  let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid > 0, (includeOwn || pid != ownPID),
                  (row[kCGWindowLayer as String] as? NSNumber)?.intValue == Int(CGWindowLevelForKey(.statusWindow)),
                  let app = NSRunningApplication(processIdentifier:pid), app.bundleURL != nil else { return nil }
            return .init(id:member.windowID,pid:pid,title:app.localizedName ?? app.bundleIdentifier ?? "应用",frame:member.frame)
        }.sorted { $0.frame.minX == $1.frame.minX ? $0.id < $1.id : $0.frame.minX < $1.frame.minX }
        return .init(display:display,space:directory.spaceAfter,rows:rows)
    }
    static func capture(_ row: Row, from directory: Directory, includeOwn: Bool = false) throws -> Self {
        let before = try MenuBarProcessSignature.read(row.pid)
        let current = try readDirectory(includeOwn: includeOwn)
        guard current.display == directory.display, current.space == directory.space,
              current.rows.contains(row) else { throw Failure.changed }
        let binding = try Self(row:row,directory:current,owner:before)
        _ = try binding.validate(directory:current,owner:MenuBarProcessSignature.read(row.pid))
        return binding
    }
}

/// Manual menu closure policy for the selected ordinary owner. Metadata can
/// authorize a future return only after an observed popup and two fresh absent
/// samples. It does not close the menu and contains no movement transport.
struct MenuBarIceManualMenuClose {
    enum State: String { case unknown, open, closed, stopped }
    struct Window: Equatable { let id: UInt32, pid: Int32, level: Int }
    struct Sample {
        let sequence: Int, uptime: Double
        let owner: MenuBarProcessSignature.Proof
        let display: UInt32, space: UInt64, healthy: Bool, windows: [Window]
    }
    let target: MenuBarIceSelectedTarget
    private(set) var state: State = .unknown
    private var begun = false, sequence = -1, lastTime = -Double.infinity
    private var sawPopup = false, firstAbsent: Double?, lastAbsent: Double?
    enum Failure: Error { case observation, closure }
    init(target: MenuBarIceSelectedTarget) { self.target = target }
    private func valid(_ sample: Sample, now: Double) -> Bool {
        sample.healthy && sample.owner == target.owner && sample.display == target.display && sample.space == target.space
            && sample.sequence > sequence && sample.uptime.isFinite && now.isFinite
            && sample.uptime >= lastTime && now >= sample.uptime && now-sample.uptime <= 0.25
            && sample.windows.count <= 4096 && Set(sample.windows.map(\.id)).count == sample.windows.count
    }
    private func popup(_ sample: Sample) -> Bool {
        sample.windows.contains { $0.pid == target.owner.pid && $0.level == Int(CGWindowLevelForKey(.popUpMenuWindow)) }
    }
    mutating func begin(_ sample: Sample, now: Double) throws {
        guard state != .stopped, !begun, valid(sample,now:now), !popup(sample) else {
            cancel(); throw Failure.observation
        }
        begun = true; sequence = sample.sequence; lastTime = sample.uptime
    }
    @discardableResult mutating func observe(_ sample: Sample, now: Double) -> State {
        guard state != .stopped, begun, valid(sample,now:now) else { cancel(); return state }
        sequence = sample.sequence; lastTime = sample.uptime
        if popup(sample) { sawPopup = true; firstAbsent = nil; lastAbsent = nil; state = .open }
        else if sawPopup {
            if firstAbsent == nil { firstAbsent = sample.uptime }
            lastAbsent = sample.uptime
            state = sample.uptime-firstAbsent! >= 0.1 ? .closed : .unknown
        } else { state = .unknown }
        return state
    }
    func requireClosed(now: Double) throws {
        guard state == .closed, let lastAbsent, now.isFinite, now >= lastAbsent, now-lastAbsent <= 0.25 else { throw Failure.closure }
    }
    mutating func cancel() { state = .stopped; firstAbsent = nil; lastAbsent = nil }
    /// Future live coordinator must supply a fresh scope reader and journal/stop;
    /// offline Samples cannot themselves invoke or enable any native return.
    static func readSample(target: MenuBarIceSelectedTarget, sequence: Int) throws -> Sample {
        let directory = try MenuBarIceSelectedTarget.readDirectory()
        let owner = try MenuBarProcessSignature.read(target.owner.pid)
        _ = try target.validate(directory:directory,owner:owner)
        guard let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly,kCGNullWindowID) as? [[String:Any]] else { throw Failure.observation }
        let windows = rows.compactMap { row -> Window? in
            guard let id = (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let level = (row[kCGWindowLayer as String] as? NSNumber)?.intValue else { return nil }
            return .init(id:id,pid:pid,level:level)
        }
        guard windows.count == rows.count else { throw Failure.observation }
        return .init(sequence:sequence,uptime:ProcessInfo.processInfo.systemUptime,owner:owner,
                     display:directory.display,space:directory.space,healthy:true,windows:windows)
    }
}

// One completed panel drop: exact source session and exact signed destination, never a bare coordinate.
struct MenuBarIceLayoutRequest: Codable, Equatable {
    let nonce: UUID
    let destination: MenuBarIceSelectedTarget
    let onLeft: Bool
}
