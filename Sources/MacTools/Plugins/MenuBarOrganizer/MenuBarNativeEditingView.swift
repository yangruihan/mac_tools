import SwiftUI

// This control has no status items or input provider. It is also rendered in
// isolation for documentation, using the same body as the production toolbox.
struct MenuBarNativeEditingView: View {
    let isExpanded: Bool
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("手动编辑布局", systemImage: "arrow.left.arrow.right").font(.subheadline.weight(.medium))
            Text("先点击「编辑布局…」，再到屏幕顶部按住 ⌘ 拖动真实图标。")
            HStack(spacing: 8) {
                Text("收纳区").foregroundStyle(.secondary)
                Text("← │ →").monospaced()
                Text("常驻区").foregroundStyle(.secondary)
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel("分隔符左侧为收纳区，右侧为常驻区")
            Text("跨分隔符改变收纳归属；同侧拖动改变左右顺序。控制图标应留在分隔符右侧。")
            if isExpanded {
                Button("完成并收起", action: onFinish)
                    .accessibilityIdentifier("menu-bar-finish-native-layout")
            }
            Text("排列由你手动完成，松开 ⌘ 即保留位置；收起只改变可见性。图标面板中的缩略图用于打开图标。")
                .foregroundStyle(.secondary)
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
    }
}
