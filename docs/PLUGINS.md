# 内置工具插件架构 v1

## 边界

这是 **应用内部的 Swift 编译期插件**，不是 Codex 插件，也不是运行时加载 `.bundle`、脚本或网络下载的插件市场。新增工具后需重新构建应用。插件与宿主同进程、同权限；接口划分不是安全沙箱。

本轮目标是让新增工具不再修改一个大 Store：每个插件独立拥有状态、视图、菜单与资源生命周期；宿主无需知道插件具体类型就能呈现、启停它。窗口管理、外观、窗口快捷键属于宿主基础设施，不包装成工具插件。

## 目录与职责

- `Sources/MacTools/MacTools.swift`：应用入口、窗口、菜单栏 Scene、退出钩子。
- `AppModel.swift`：宿主外观与窗口快捷键；**唯一内置插件注册列表**。
- `Core/ToolPlugin.swift`：`ToolPlugin` 契约、元数据、注册/启停、配置命名空间、状态回报。
- `Core/HotKeyService.swift`：唯一 Carbon 监听器；跨插件冲突检测、按 owner 释放与重试。
- `UI/`：只迭代注册表的通用宿主 UI，以及复用的原生控件。
- `Plugins/QuickControls/`：亮度、音量、配置增删改、耳机保护、解锁快捷键、200ms 锁定与硬件接口。
- `Plugins/KeepAwake/`：电源断言，启用后防闲置熄屏/休眠，不保证防锁屏。
- `Plugins/Trackpad/`：系统触控板开关与恢复；辅助功能权限只在用户操作时申请。
- `Plugins/WindowPreview/`：屏幕录制授权、窗口选择、只读可缩放悬浮窗。macOS 14+；使用 ScreenCaptureKit 周期快照，非动态视频录制。

亮度和音量保留在一个“快捷控制”插件中，因为它们共用配置、锁定和快捷键流程；保持唤醒和触控板是独立插件。

## 插件契约

`ToolPlugin` 的入口：

| 成员 | 约束 |
| --- | --- |
| `info` | 稳定、唯一的小写 ID；允许点和连字符。`app.*` 保留给宿主。标题、图标、说明供界面使用。 |
| `info.placement` | `.utility` 放入自适应紧凑卡片网格；`.content` 放入中央滚动面板。 |
| `makeView()` | 返回该插件拥有的 SwiftUI 视图；有状态时视图须通过 `@ObservedObject` 观察插件。 |
| `makeMenuItems()` | 返回菜单栏条目；同样观察插件状态，不复制一套状态。 |
| `start()` | 默认空实现。仅在启用时运行；不要因加载插件就操作亮度、音量或申请权限。失败应撤销已获取资源再抛错。 |
| `stop()` | 默认空实现。同步、幂等地释放快捷键、定时器、电源断言并恢复临时系统设置；失败必须抛错，不能假装停用成功。 |

所有生命周期、状态和 UI 入口都在主线程调用。耗时工作应由插件自行移到后台，UI 更新回主线程；不在 `makeView()` 或 `makeMenuItems()` 中产生副作用。插件不得持有强引用的宿主回调形成循环。

`PluginContext` 提供：

- `settings`：该插件自己的 `plugin.<id>.<key>` 配置；不能修改别的插件/宿主的 key。
- `hotkeys`：以 `info.id` 为 owner 注册/移除快捷键；action ID 在 owner 内唯一，闭包弱引用插件。
- `report`：共享状态栏回报，不依赖 `AppModel` 具体类型。

Carbon 注册错误显示在对应编辑器；保留系统保留键和其他应用冲突。宿主 `app.*` 的键优先，其他插件按 ID 确定顺序；释放冲突 owner 后重新尝试仍启用的快捷键。停用工具时不影响窗口显示/收起快捷键。

## 启停语义

“插件”菜单控制的是**工具是否可用**，与工具内部功能开关不同：

- 停用快捷控制：解除运行中亮度/音量锁定、停止计时器、注销其快捷键；不改实际设备值、不删除配置。
- 停用保持唤醒：释放电源断言。再启用插件不会自动恢复保持唤醒。
- 停用触控板：恢复用户操作前的系统开关。权限被撤销等导致恢复失败时，宿主保留启用状态并显示错误，以便重试。
- 退出：按注册逆序清理已启动插件，个别失败不会阻止清理其他插件。异常退出的资源恢复限制与此前相同；触控板仍可能需要系统设置手动恢复。
- 插件启用选择保存在 `disabledPluginIDs`，保留未知插件 ID，便于后续版本恢复对应工具。

## 新增一个工具

1. 新建 `Sources/MacTools/Plugins/Example/ExamplePlugin.swift`。
2. 实现协议，例如下面的无硬件示例。
3. 在 `AppModel.plugins` 的 `builtins` 中增加 `ExamplePlugin(context: context(for: ExamplePlugin.id))`。
4. 添加至少一个行为及 `stop()` 清理检查，运行 `swift test` 和布局检查；不用改 `ContentView` 或菜单栏分支。

```swift
import SwiftUI

final class ExamplePlugin: ToolPlugin {
    static let id = "example"
    let info = PluginInfo(id: id, title: "示例工具", symbol: "puzzlepiece",
                          detail: "最小插件示例", placement: .content)
    private let context: PluginContext
    init(context: PluginContext) { self.context = context }
    func makeView() -> AnyView {
        AnyView(GroupBox("示例工具") {
            Button("运行") { [weak self] in self?.context.report("示例工具已运行") }
        })
    }
    func makeMenuItems() -> AnyView {
        AnyView(Button("运行示例工具") { [weak self] in self?.context.report("示例工具已运行") })
    }
}
```

需要状态时令插件符合 `ObservableObject`，把交互状态放在插件自己的 `@Published` 属性中，用单独视图观察，不向宿主增加对应字段。需系统权限的插件自行检查、明确提示失败；不要在注册或启用插件时自动授权。

## 配置兼容与回退

- 快捷控制首次复制旧 `presets`、`unlockShortcut` 到 `plugin.quick-controls.*`；JSON 的 UUID、档位、锁定、按键全部保留。
- 窗口快捷键首次复制旧 `windowShortcut` 到 `app.windowShortcut`；能读取旧的完整 Preset JSON，新格式只保存按键和修饰键。
- 迁移不覆盖已有新格式配置，**不修改或删除旧 key**。外观仍使用原来的 `appearanceMode`。
- 回退旧二进制会看到迁移时的旧配置，而不是插件版期间的新编辑；未来需要双向降级时再增加明确的导出/导入方案，不偷偷同步覆盖旧数据。
- 新版本更改插件配置格式时，使用该插件自己的版本化迁移；不能只改稳定 ID，否则旧配置和停用状态将脱离原工具。

## 已验证与边界

12 项测试覆盖旧数据迁移、命名空间隔离、外观保存、锁定及停用清理、跨插件快捷键冲突/释放、真实电源断言释放、模拟触控板恢复失败、新插件自动呈现契约、重复/非法 ID 和启动/清理错误；另覆盖悬浮窗置顶层级、横纵缩放、图像尺寸上限、停用清理、在途结果取消和错误画面清理。

保持原生灰阶与大滚动区。原生布局检查同时支持旧单文件和新源目录：

```sh
swift test
EXPECT_NATIVE=1 EXPECT_MODERN=1 scripts/check-ui-layout.sh Sources/MacTools
UI_DARK=1 EXPECT_NATIVE=1 EXPECT_MODERN=1 scripts/check-ui-layout.sh Sources/MacTools
./scripts/build-app.sh
```

真实亮度/音频输出、完整触控板授权链本轮不重复操作；迁移和清理测试不能替代设备兼容验收。本轮不覆盖正在运行的 Applications 版本。

## 有意不做的部分

暂不引入动态二进制插件、网络安装、脚本执行、依赖解析或 IPC。未来确实需要外部插件时，先把契约抽成公开 SwiftPM 库，再决定 ABI/协议版本、签名、来源校验、权限隔离、崩溃隔离与更新机制；现有同进程接口不能直接宣称适合加载不受信任代码。

### 快照型异步插件的停止约束

窗口预览的 `stop()` 立即撤销刷新任务、关闭选择/预览窗口并清除内存画面。系统已经受理的单次截图请求未必可取消，因此使用 generation 标识丢弃过期返回值，且不再发起后续请求。任务串行运行，最多一个请求和一张可见图片；不需要修改宿主同步生命周期，也不假称系统在途请求已瞬间结束。应用加载/启用插件时绝不自动采集或弹授权，只有用户操作授权/刷新/开始按钮才进入对应路径。
