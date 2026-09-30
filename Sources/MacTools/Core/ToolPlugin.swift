import SwiftUI

struct PluginInfo {
    enum Placement { case utility, content }
    let id: String
    let title: String
    let symbol: String
    let detail: String
    let placement: Placement
}

// Built-in, trusted plugins only. All lifecycle and UI calls run on the main thread.
protocol ToolPlugin: AnyObject {
    var info: PluginInfo { get }
    func start() throws
    func stop() throws
    func makeView() -> AnyView
    func makeMenuItems() -> AnyView
}

extension ToolPlugin {
    func start() throws {}
    func stop() throws {}
}

struct PluginSettings {
    let id: String
    private let defaults: UserDefaults
    init(id: String, defaults: UserDefaults) { self.id = id; self.defaults = defaults }
    private func key(_ key: String) -> String { "plugin.\(id).\(key)" }
    func data(forKey name: String) -> Data? { defaults.data(forKey: key(name)) }
    func set(_ data: Data, forKey name: String) { defaults.set(data, forKey: key(name)) }
    func migrateLegacyData(_ names: [String]) {
        for name in names where data(forKey: name) == nil {
            if let data = defaults.data(forKey: name) { set(data, forKey: name) }
        }
    }
}

struct PluginContext {
    let settings: PluginSettings
    let hotkeys: HotKeyService
    let report: (String) -> Void
    var openToolbox: () -> Void = {}
}

final class PluginRegistry: ObservableObject {
    let plugins: [any ToolPlugin]
    @Published private(set) var enabledIDs: Set<String>
    private var startedIDs = Set<String>()
    private var disabledIDs: Set<String>
    private let defaults: UserDefaults
    private let report: (String) -> Void

    init(plugins: [any ToolPlugin], defaults: UserDefaults, report: @escaping (String) -> Void) throws {
        let ids = plugins.map { $0.info.id }
        guard Set(ids).count == ids.count,
              ids.allSatisfy({ !$0.hasPrefix("app.") && $0.range(of: "^[a-z0-9]+(?:[.-][a-z0-9]+)*$", options: .regularExpression) != nil }) else {
            throw Failure.message("插件标识重复或格式无效")
        }
        self.plugins = plugins; self.defaults = defaults; self.report = report
        disabledIDs = Set(defaults.stringArray(forKey: "disabledPluginIDs") ?? [])
        enabledIDs = Set(ids).subtracting(disabledIDs)
    }

    var enabledPlugins: [any ToolPlugin] { plugins.filter { enabledIDs.contains($0.info.id) } }

    func startAll() {
        for plugin in plugins where enabledIDs.contains(plugin.info.id) && !startedIDs.contains(plugin.info.id) {
            do { try plugin.start(); startedIDs.insert(plugin.info.id) }
            catch {
                let startError = error
                do { try plugin.stop(); enabledIDs.remove(plugin.info.id) }
                catch { startedIDs.insert(plugin.info.id); report("\(plugin.info.title)启动及清理失败，请重试停用：\(error.localizedDescription)"); continue }
                report("\(plugin.info.title)启动失败：\(startError.localizedDescription)")
            }
        }
    }

    @discardableResult func setEnabled(_ enabled: Bool, id: String) -> Bool {
        guard let plugin = plugins.first(where: { $0.info.id == id }) else { return false }
        guard enabled != enabledIDs.contains(id) else { return true }
        do {
            if enabled { try plugin.start(); startedIDs.insert(id); enabledIDs.insert(id); disabledIDs.remove(id) }
            else { try plugin.stop(); startedIDs.remove(id); enabledIDs.remove(id); disabledIDs.insert(id) }
            defaults.set(disabledIDs.sorted(), forKey: "disabledPluginIDs")
            return true
        } catch {
            let operationError = error
            if enabled {
                do { try plugin.stop() }
                catch {
                    startedIDs.insert(id); enabledIDs.insert(id)
                    report("\(plugin.info.title)启用及清理失败，请重试停用：\(error.localizedDescription)")
                    return false
                }
            }
            report("\(plugin.info.title)\(enabled ? "启用" : "停用")失败：\(operationError.localizedDescription)")
            return false
        }
    }

    func stopAll() {
        for plugin in plugins.reversed() where startedIDs.contains(plugin.info.id) {
            do { try plugin.stop(); startedIDs.remove(plugin.info.id) }
            catch { report("\(plugin.info.title)清理失败：\(error.localizedDescription)") }
        }
    }
}

enum Failure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}
