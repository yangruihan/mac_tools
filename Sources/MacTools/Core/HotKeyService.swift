import SwiftUI
import Carbon

struct KeyChord: Codable, Equatable {
    var key = ""
    var modifiers = UInt32(cmdKey | optionKey)
}

struct HotKeyAction {
    let id: String
    let chord: KeyChord
    let perform: () -> Void
}

final class HotKeyService: ObservableObject {
    @Published private(set) var errors: [String: String] = [:]
    private var owners: [String: [HotKeyAction]] = [:]
    private var references: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?
    private var installationStatus: OSStatus = noErr

    init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        installationStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard status == noErr, key.signature == 0x4D54424F else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKeyService>.fromOpaque(context).takeUnretainedValue().actions[key.id]?()
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func error(owner: String, id: String) -> String? { errors[owner + "/" + id] }
    func replace(owner: String, actions: [HotKeyAction]) { owners[owner] = actions; register() }
    func remove(owner: String) { owners.removeValue(forKey: owner); register() }

    private func register() {
        references.forEach { UnregisterEventHotKey($0) }; references.removeAll(); actions.removeAll()
        var failures: [String: String] = [:]
        // Deterministic priority: host keys (app.*), then plugins sorted by ID.
        for owner in owners.keys.sorted(by: {
            if $0.hasPrefix("app.") != $1.hasPrefix("app.") { return $0.hasPrefix("app.") }
            return $0 < $1
        }) {
            let bindings = owners[owner] ?? []
            guard Set(bindings.map(\.id)).count == bindings.count else {
                for binding in bindings { failures[owner + "/" + binding.id] = "快捷键标识重复" }
                continue
            }
            for binding in bindings {
                let key = owner + "/" + binding.id
                guard !binding.chord.key.isEmpty else { continue }
                guard installationStatus == noErr else { failures[key] = "快捷键事件监听失败（\(installationStatus)）"; continue }
                guard let code = keyCodes[binding.chord.key.uppercased()], binding.chord.modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else {
                    failures[key] = "请选择字母/数字，至少包含 ⌘、⌥ 或 ⌃"; continue
                }
                guard nextID < UInt32.max else { failures[key] = "快捷键编号已耗尽，请重启应用"; continue }
                let id = nextID; nextID += 1 // Never reuse IDs: queued old events must not execute a new binding.
                var reference: EventHotKeyRef?
                let status = RegisterEventHotKey(code, binding.chord.modifiers, EventHotKeyID(signature: 0x4D54424F, id: id), GetApplicationEventTarget(), 0, &reference)
                if status == noErr, let reference { references.append(reference); actions[id] = binding.perform }
                else { failures[key] = "快捷键冲突或注册失败（\(status)）" }
            }
        }
        errors = failures
    }

    deinit {
        references.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}

let keyCodes: [String: UInt32] = ["A":0,"S":1,"D":2,"F":3,"H":4,"G":5,"Z":6,"X":7,"C":8,"V":9,"B":11,"Q":12,"W":13,"E":14,"R":15,"Y":16,"T":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"O":31,"U":32,"I":34,"P":35,"L":37,"J":38,"K":40,"N":45,"M":46]
