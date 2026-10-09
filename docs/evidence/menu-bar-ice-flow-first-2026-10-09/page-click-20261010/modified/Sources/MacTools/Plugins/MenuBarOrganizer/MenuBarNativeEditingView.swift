import SwiftUI

// This control has no status items or input provider. It is also rendered in
// isolation for documentation, using the same body as the production toolbox.
struct MenuBarNativeEditingView: View {
    let isExpanded: Bool
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("⌘ 拖动顶部图标：分隔符左侧收纳，右侧常驻。")
                .accessibilityLabel("分隔符左侧为收纳区，右侧为常驻区")
            if isExpanded {
                Button("完成并收起", action: onFinish)
                    .accessibilityIdentifier("menu-bar-finish-native-layout")
            }
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
    }
}
