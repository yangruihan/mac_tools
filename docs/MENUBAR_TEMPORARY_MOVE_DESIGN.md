# 临时搬移的最小设计与能力边界

更新：2026-10-03。适用于 `feat/menu-bar-reliable-activation`，基线 HEAD `167771fe`。本设计替代继续调大占位宽度的思路，保留已有增宽控制器、拒绝条件和全部历史证据。正式 `/Applications/MacTools.app` 不参与本轮。

## 决策摘要

推荐独立的搬移事务，而不是把物理迁移塞进 `MenuBarNativeRevealPlan` 的增宽合同。第一阶段只建立**已确认可见的自建 T/N 项**移到右侧槽、观察菜单、关闭、回原序、取消与故障恢复的合同。已实现纯值模型、隔离磁盘日志和输入干预接口/模拟回归；没有真实观测/监听适配器、事件驱动或运行时接线，`backendEnabled = false`。后续基础实现见 [隔离日志及输入接口](evidence/menu-bar-move-foundation-2026-10-03/README.md)。

公开 API 可以读取部分窗口事实、执行 AX 动作、构造并发送鼠标事件。它们没有提供“将指定隐藏状态项搬到右侧”的受支持高层接口，也没有保证按坐标发送 Command 拖动就能命中状态项。当前 T/N 虽逻辑可见，却没有被 WindowServer ordered；这个起拖阻断仍存在。完整菜单栏逻辑顺序、隐藏项位置关系及跨进程重启恢复也没有公开保证。

真正待决定的是产品能力边界：是否接受可见项起拖作为实验首阶段；如果必须支持当前系统隐藏项，是否另立私有依赖评估。推荐保留公开路线与明确失败状态，不默认引入私有路线。私有评估需要新的任务范围，不是本轮默许的下一步。

## 当前真实证据

自建发布故障已经修复：上一轮 52 份 JSON 闭合了直接持有的 item → button → windowNumber → CG owner/ID 绑定，发布一直持续到正常退出。T/N 在代表样本中 `itemVisible`、`NSWindow.isVisible`、`isOnActiveSpace` 均为 true、alpha 为 1、按钮完整落在左侧安全区；同窗口的公开 occlusion visible 为 false，CG on-screen 键缺失且被 on-screen-only 列表排除。不能再将它归为启动或 JSON 发布失败，也不能用 AX 坐标或 AppKit visible 代替真实可见性。

Apple 明确说明空间不足时状态项可能暂时隐藏而 `isVisible` 仍为 true；这支持上述语义解释，尚不能唯一指认本机隐藏触发机制。[Apple isVisible](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible)。增大自有 `length` 只分配自身空间，上一次实测实际增长 45pt、目标向左 45pt；这不是向右侧槽搬移。[Apple length](https://developer.apple.com/documentation/appkit/nsstatusitem/length)。

原始证据见 [owner 同窗口采样](evidence/menu-bar-native-owner-window-2026-10-03/README.md)、[机制及固定源码研究](evidence/menu-bar-native-mechanism-research-2026-10-03/README.md)。本轮没有新现场，没有 move/menu/close/restore/cancel 的真实成功证据；隔离模型成功轨迹不能替代这些验收。

## 公开 API、权限与私有依赖

| 部分 | 受支持工具与用途 | 边界与权限 |
| --- | --- | --- |
| 身份和几何 | CGWindowListCopyWindowInfo、PID 的内核启动身份、应用路径/bundle、代码签名校验；自建端直接 NSStatusItem/button/window 绑定 | windowID 或 bundleID 单独不能稳定标识同一项；CG 排列是窗口列表/几何事实，不是菜单栏完整逻辑顺序服务 |
| 显示与安全区 | NSScreen frame/backingScaleFactor/auxiliaryTopLeftArea/auxiliaryTopRightArea，CGDisplay ID/UUID 与公开显示配置通知 | 必须转换所选屏 AppKit 与 Quartz 坐标；安全矩形没有分配状态项槽或让隐藏项重显的承诺 |
| AX 语义激活 | AXIsProcessTrusted、AXUIElementCopyAttributeValue、AXUIElementGetPid、AXUIElementPerformAction | 使用已存在的辅助功能权限；返回成功只说明动作被接受，菜单结果必须独立观测；自进程菜单 AX 按已有主线程修复读取 |
| 鼠标事件 | CGEventCreateMouseEvent、CGEventFlags 的 Command 标志、CGEventPost | 公开输入传输是候选驱动基础，不能保证指定菜单项可拖动或隐藏项可命中；需单独验证发送能力，不能以 AX 权限替代 |
| 并发输入观测 | 公开 event tap/事件来源字段及合适的输入状态读取，待选择及验证具体方案 | 发送和监听是不同能力；CGPreflightPostEventAccess 与 CGPreflightListenEventAccess 分开检查。监听方案可能涉及 Input Monitoring；本轮不请求、不修改权限，没有监听适配器即不准进入候选实测 |
| 截图辅助栏 | 可选 CGWindow 图像/屏幕采集与缓存 | 可能要求屏幕录制授权；不是物理迁移，不能把截图点击成功当原生菜单搬移通过；本轮不增加这一权限 |
| 隐藏项起拖/精确定向 | 当前无已验证的公开实现 | Ice 的 CGS 枚举、Space 接口和原始 0x33 窗口事件定向不属于采用的公开路线；不调用、不移植 |
| 状态项位置/全局隐藏策略 | 没有采用 PreferredPosition 等内部偏好键 | 此类键不是受支持搬移控制合同；Hidden 的 OS27 MenuBarClientCore 私有 assessment 分支也排除，本机为 macOS15.7.4 |

公开发送与监听检查见 [Apple PostEventAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess())、[Apple ListenEventAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightlisteneventaccess())。接口存在不等于当前已获监听授权。所有 request-access 变体均不在本轮范围内。

## 身份合同与观测输入

目标必须是签名标识 `com.ryanai.mactools.nativetargets` 的 T 或 N 项。绑定 PID、内核启动时间、bundle/path、签名 identifier/team/code hash、随机 nonce、持有实例 UUID、直接 item key/windowNumber 和 CG 同 owner/windowID。每次观测同时核对，不以标题、坐标或 PID 猜测替换目标。重启产生的新实例不能继承旧物理动作责任。

纯模型接收这些字段，并检查一致性；**模型不执行代码签名或 nonce 鉴权**。未来观测适配器须验证真实发布来源、路径和签名，拒绝过时、伪造、部分或不一致发布，才能把输入视为可信。测试中的 `model-team`/`model-code-hash` 是构造值，不是运行时鉴权证据。

同屏同一行参与窗口的完整身份集合不得筛掉隐藏项。初版模型要求全部 ordered、列入 on-screen-only、alpha 有效，所有完整按钮落在左/右安全区域，且不与前台应用菜单或已知覆盖区域相交；目标另要求自建 owner occlusion visible 正证据。若存在隐藏的静止 CG 窗，完整逻辑顺序没有证据，则拒绝，不能删除它来让排序通过。当前真实桌面因此不能通过此初版模型。

CGWindowList 不是完整菜单栏逻辑目录。未来适配器如何证明参与集合完整、漏项、非状态窗识别及隐藏项关系，仍是阻断项；代码注释要求完整输入不能自动使它成为事实。第三方多个状态项跨重启缺乏统一公开持久身份，初版不支持第三方目标搬移。

样本用单调时钟；两次事实完全一致、序号递增、间隔 100–500ms、第二次距当前不超过 250ms。连续性丢失重新生成 UUID，不能恢复旧序号和连续性令牌来假装未发生变化。这些是保守实验参数，不是 WindowServer 的稳定性保证。

## 右侧槽容量与顺序

先确定所选屏、前台应用菜单、左/右安全矩形、独立恢复入口和所有参与者。默认右侧留 20pt，容量按目标**实际 backing window 宽度**加实测间距预留；`NSStatusItem.length` 的请求值不能替代实际宽度。本轮模型要求外部提供的 reservation 至少覆盖实际目标宽度，间距校准尚无真实适配器。

目的地定义为“独立恢复入口紧邻左侧”，恢复入口位置保持不变。须证明右侧可见前缀有足够余量，在插入预留宽度后仍完整在安全区；不仅检查目标能放下。后验也核对所有参与者完整安全区域、原尺寸、正面可见性，拒绝把其他项挤进刘海或用缩小按钮制造槽容量。

预期显示顺序只允许一个置换：从完整原序移除目标、在恢复入口前插入；其他项相对顺序保持。归位检查完整原序、所有原身份、原 frame/button 几何（1pt 容差）与恢复入口。两次稳定读回才构成模型成功。坐标排序可以用于可见单行模型，不能推断系统隐藏项的持久排列。不同分辨率、动态长度、RTL、无刘海屏布局未被这套初版已验证合同覆盖。

## 事务与持久化顺序

```
idle → persist prepared → 一次候选搬移 → 两次显示后验
     → persist moved → shown / 等待菜单关闭
     → 两次关闭后当前状态核验 → persist restorePrepared
     → 一次候选归位 → 两次原序及原几何后验
     → persist restored → 清日志确认 → idle
任一失败 → needsRecovery（保留恢复记录）
```

`prepared` 表示“可能已经产生物理效果”，不能表示“尚未发生”。磁盘确认与 WindowServer 动作不原子：崩溃可发生在发送之后、写 moved 之前。搬移和归位各最多发出一次模型动作意图；不根据日志阶段盲目重放。同事务/同内容的持久化收据才推进状态；过期收据和重复动作不能授权新的搬移。

菜单 open 或 unknown 都不能开始归位；不得把 AX success、无 owner 窗口或采样失败当作 closed。未来须定义当前目标的菜单/弹窗观测，含跨进程菜单、打开/关闭超时与 `accepted/refused/uncertain` 激活结果。模型只接受三态接口输入，没有菜单观测器，也不执行 AXPress 或模拟点击。

新增 Record 的 schema1 是**新的纯模型格式**，与已有增宽恢复 journal 不兼容。后续已完成独立磁盘适配器与故障注入：另设目录及 `temporary-move-v1.json`，拒绝旧格式，校验 envelope/checksum、schema、事务与结构、体积、目录/文件归属/链接及权限；用 compare-and-swap、同目录临时文件、fsync/atomic rename/目录刷盘后才确认 persist。仍没有运行时接线或本地启动恢复管理器，不能声称已验证物理归位或断电耐久性。

## 超时、取消与崩溃

动作阶段默认 5 秒，允许参数上限 30 秒；超时保留记录，不当作无效果或成功。取消与失败都进入同一个归位合同：若已在原序且原几何两次稳定，持久化 restored 后可清；若完整预期显示布局、菜单 closed、身份/环境/连续性都有效，则可准备一次归位；其他情况保留责任。菜单关闭等待不能绕开状态检查。

重启读取日志仅进入 needsRecovery。若归位已准备或发送但后验缺失，不再发送第二次；重新核实原序后才可结束。如果目标实例、前台应用、显示、Space epoch 或观测连续性变化，停止自动物理动作。没有公开持久 Space ID 与跨重启同实例/顺序保证；应用崩溃、目标重启、系统重启之后**不能承诺自动回原序**。只能保留恢复记录、展示具体阻断和原邻项信息，由用户决定后续恢复方式；不能按旧 PID、旧坐标或同名应用自动搬动。

此设计保住可追踪的恢复责任，不能保证每次故障立即物理归位。若产品要求任何崩溃都无条件恢复，当前公开路线无法兑现。

## Space、多屏与焦点

使用明确选中的 CGDisplay UUID/ID、frame、scale、rotation 和对应 NSScreen，不使用 `NSScreen.main` 作为目标选择。所有 AppKit→Quartz 变换以该屏为依据。监听显示变化、睡眠/唤醒、前台应用与 `NSWorkspace.activeSpaceDidChangeNotification`；这些公开通知用于使观测 epoch 失效，不能拿它们推断持久 Space 身份。[Apple activeSpaceDidChange](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification)。

初版只考虑一个指定带刘海屏的连续观测周期。Space 切换、分屏全屏、显示拔插或镜像/缩放变化、目标移到别屏：保留记录并停止物理动作，不自动转移到其他屏。跨 Space、主屏切换和多个菜单栏实例要另建实测合同。光标及焦点恢复也须证明用户未接管，否则不能按旧位置强制恢复；当前模型不操作光标或焦点。

## 用户并发拖动与一次事件序列

应用内事务互斥只防本应用并发，不能锁住 WindowServer 或用户硬件输入。未来驱动须确认按键、按钮、修饰键处于允许状态，并具有已验证的干预观测能力；可以用公开来源标记区分自身事件，但标记不是系统互斥，也不是防伪保证。任何用户输入、参与项重新排序或环境失效都中止推进，不用补点、重试坐标或重新激活填补不确定性。

完整公开事件序列、Command 拖动可行性、输入监听准确性、半途失败时仅清理自身手势，以及不覆盖用户鼠标状态的收尾协议，均待独立验证。不能无条件 mouse-up、回拉用户已排好的图标或 warp 光标。最小事件驱动至多操作已绑定的自建目标，绝不向第三方项起拖；自然布局变更也须经全参与者后验。

当 user-cancel 与真实用户拖动并发，保留恢复状态比盲目回原位置更安全。产品必须允许“待恢复/需人工处理”，不能把这类状态显示为成功。

## 许可证与独立实现

已经阅读固定 Ice/Hidden 源码，并据行为建立我们自己的值模型；没有复制、翻译或集成它们的实现，不声称未接触源代码的 clean-room 流程。Ice 当前研究快照为 GPL-3.0；如果后续纳入受其版权保护的实现并分发，必须按适用 GPL 条款评估整体授权和对应源码义务，不能继续将整合成果简单声明为仅 MIT。Hidden 为 MIT，若复用代码需保留相应版权与许可证通知。读取行为用于对照，与直接复用代码须明确区分。许可评估不使私有 API 或权限需求消失。

来源与固定 commit/逐段链接、实际 LICENSE 见 [研究源清单](evidence/menu-bar-native-mechanism-research-2026-10-03/sources.json)；不依赖 README 的陈旧行为说明，也不把开发分支当已发布版本。

## 落地范围与后续门槛

本轮新增 [纯模型](../Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarTemporaryMoveModel.swift) 与 [隔离测试](../Tests/MacToolsTests/MenuBarTemporaryMoveModelTests.swift)，没有修改已有生产 Plan/Observation/Controller 或样例生命周期。测试正面流程使用明确的模型输入；真实 owner 负面证据进入单独拒绝测试，不被改写为正面样本。

磁盘适配器与输入干预接口/故障回归已隔离落地，仍不发系统事件。下一最小真实方案仅只读检查已有监听能力和现场条件；实际公开输入适配器、完整参与集合、已可见自建目标、容量和干预观测仍缺。各项缺失时仍不准现场试拖。只有真实 move/menu/close/restore/cancel 与负面恢复证据齐全，才讨论实验开关和产品接线。第三方目标、系统隐藏项自动起拖、跨重启无条件恢复都不在当前可兑现范围内。

本轮验证与源码清单见 [交付记录](evidence/menu-bar-temporary-move-model-2026-10-03/README.md)。未提交、安装或启用实际 backend。
