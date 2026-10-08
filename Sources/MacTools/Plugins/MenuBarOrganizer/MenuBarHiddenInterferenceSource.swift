// Copyright (c) 2026 Ryan.AI. MIT; see LICENSE.
import Foundation

protocol MenuBarHiddenInterferenceSource: MenuBarMoveInterferenceSource {
    func drainEvents() -> [MenuBarMoveInterference.Event]
    func bindOperationStop(_ stop: MenuBarOperationStop?)
}
extension MenuBarHiddenInterferenceSource {
    func bindOperationStop(_ stop: MenuBarOperationStop?) {}
}
