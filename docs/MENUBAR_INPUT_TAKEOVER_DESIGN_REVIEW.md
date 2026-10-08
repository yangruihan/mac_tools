# 菜单栏输入接管与停止机制设计审查

2026-10-07，Asia/Shanghai。状态：**可审阅方案，未接入生产**。分支 feat/menu-bar-reliable-activation，基线 167771fe。独立复核已完成；没有新窗口、监听、采样、鼠标发送、权限请求、安装或提交。现有 ANY 保护、固定 Q、静止期限、双 fence、Permit、目标与恢复检查全部保持；backend 禁用。

建议把工程目标收敛为：**观察到取消、非自身输入或监测失效后，永久停止本轮新动作调度，保留可能产生效果的责任记录。** 不再把“全局计数可解释”当作用户接管机制的唯一实现目标。公开 API 不能提供“所有设备都没有物理输入”或“检查与 WindowServer 投递绝对互斥”的证明。

当前可先做保持 ANY 的停止链路加固。将来如果要改变 ANY 的授权作用，必须单独审阅保护范围及残余竞争风险；本文不是移除 ANY、增加尾巴容差或启用真实动作的批准。

## 公开 API 能证明什么

本地公开 SDK 的声明、语义和哈希记录在 [SDK核对索引](evidence/menu-bar-input-takeover-design-review-2026-10-07/sdk-index.json)。另已查阅 Apple 官方文档；旧文档的权限描述不能代替当前机器权限或覆盖实测。

| 信号 | 可用事实 | 不能推导的保证 |
| --- | --- | --- |
| HIDSystemState | 多个硬件事件源投递的组合状态表 | 来源是某个人、某设备；原始物理报告完整覆盖；不能用 sourcePID=0 或 state=HID 认证用户 |
| counter/age | WindowServer 生命周期中的类型计数、距上次该类型活动的时间 | ANY 等于17类总和；所有物理输入都对应计数；与tap一一对应；age是精确硬件时间；查询已经同步到最新活动 |
| listenOnly CGEvent tap | 指定位置、允许的mask内已交付回调；不修改或丢弃输入 | enabled即完整覆盖；没有回调即没有物理输入；前置filter没有改变/吞掉事件；callback与post之间无竞态 |
| buttonState/keyState/flagsState | 查询时所选Quartz状态表中的当前状态 | 两次释放状态之间没有短按；所有键/扩展按钮均覆盖；多个API读取是原子的 |
| 光标位置 | 某次位置观测，或已交付move/drag事件 | 两次位置相同意味着没移动；设备未移动；位置由用户造成；可安全自动warp回旧位置 |
| 前台应用/焦点/Space/显示变化 | 当前环境差异及已交付通知，可用于停止 | 期间没有切换后返回；同一PID内没换控件；通知交付与输入或投递同步 |
| 精确自身packet回执 | 本sender预注册的完整包、单次、限定时间内在该监听阶段吻合 | 加密认证；同用户恶意进程不能伪造；目标处理成功；移动/菜单/归位成功；一次receipt代表所有route已经执行 |

计数语义见 [Apple counter API](https://developer.apple.com/documentation/coregraphics/cgeventsource/counterforeventtype(_:eventtype:))，状态域见 [Apple HIDSystemState](https://developer.apple.com/documentation/coregraphics/cgeventsourcestateid/hidsystemstate)。本地 CGEventSource.h 另明确：修饰键产生 flagsChanged；部分音量、亮度、弹出键不生成 keyDown/up；键自动重复不计数；down/up数不等不能判断有键按住。这些事实否定“键计数平衡＝键全部释放”，也不能据此确定本次 ANY-only 增量具体来自媒体键。

tap 按指定阶段及mask监听，权限可裁剪部分mask；回调由所挂CFRunLoop调度。[Apple tapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)) 没有提供全部物理输入同步交付保证。前置active filter可改写/丢弃，见本地 CGEvent.h。公开文档中 HID位置/root限制等历史描述存在，不能把增加更早tap视为本任务现有权限下的可用替代。

安全输入可能使键盘事件不向截获进程交付；端口仍有效不等于键盘观察完整。Apple [TN2150](https://developer.apple.com/library/archive/technotes/tn2150/_index.html) 是历史说明，支持将安全输入作为已知覆盖风险，不能据此宣称当前系统各API的全部行为已验证。未来可以审阅只读的 IsSecureEventInputEnabled 检查；不得启用/禁用其他应用的安全输入，也不得绕过它。

## 17类型是否完整

本轮采样覆盖 CGEventType 中17个普通命名值：null及16种mouse/key/flags/scroll/tablet类型。另两项 tapDisabled 是带外健康通知，不是普通输入类型或可直接移位构造的mask位。生产监听实际只有16种，未包括null。

这是一份公开枚举目录，**不是全部系统输入的封闭集合**。AppKit另有公开systemDefined、gesture、magnify、swipe、pressure等事件类型，媒体键也有普通keyDown/up之外的处理路径。AppKit类型域不能直接当成同rawValue的CG类型域；不能靠新增若干猜测rawValue实现完整覆盖，更不能把旧ANY差异归因为某个猜测类型。

未来可评审公共 kCGEventMaskForAllEvents：在收到回调时对未认识类型一律停止，只读取类型及必要时间标量，不解析媒体键payload或键内容，不新增私有字段。该mask仍只表示该tap允许观察的事件位，并非全部设备报告；应确认本进程实际tap信息/有效mask，查询失败或裁剪则拒绝授权。**本文没有创建该tap，也没有修改生产mask。**

AppKit本地+全局monitor可补系统/手势的已交付活动，但不能作为更强的原始输入证明：全局不覆盖自身应用，本地不覆盖其他应用；键盘受权限限制，均在主线程调度。Apple还指出全局monitor不能发现所有Command-Tab或系统警报情形，应配合生命周期通知。[Apple Monitoring Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html)。因此最小第一步不增加第三条监听，先修共有停止链路；覆盖补充留作独立方案。

## 已有路径的具体薄弱处

源码原样保存于 [source-reviewed](evidence/menu-bar-input-takeover-design-review-2026-10-07/source-reviewed/)，以下行号对应本次审查版本。

1. MenuBarListenOnlyInterferenceSource.swift:408–432 只查询left/right/center及五种手势修饰键，keys恒为空，却返回包含keyboard的requiredCoverage。它不是所有普通键已释放的证明。起始requestQuiet路径另合并NSEvent.pressedMouseButtons（MenuBarLocalNoMoveInput.swift:152–159），但不能把这个补充误称为动作期间channel已有全按钮覆盖。现有ANY/age提供额外保守拒绝；去掉它不会自动让空keys可靠。
2. MenuBarOwnedMouseTransport.swift:89–93 在注册receipt、写witness后直接session post；落盘期间的取消未接入最后共有检查。95–107的100ms回执等待只查receipt/健康，不读取coordinator的cancelled；PID投递是第二项独立效果，需要自己的停止检查。
3. MenuBarHiddenMoveCoordinator.swift:87–90 在open返回后直接cancelOwnedMenu；打开过程中已交付的接管可能在下一boundary之前仍触发主动关菜单。不能把自有菜单控制请求视为无副作用。
4. MenuBarOwnedMouseTransport.swift:39–45、118–130 的失败defer会尝试emergency up，且可能换投递路由。needsRelease表示可能已发down，不是系统可验证的“自己的down仍按住”。定址/private source不能保证与用户物理手势隔离，也不能把补发成功等同于已安全释放。
5. 现有coordinator具有边界检查、日志保留、显式restoreRetained及禁止启动重放的好结构，应该保留。但每个检查和后续系统调用仍有时间差，固定倒计时、更多pump或更密轮询不能消除该差异。

独立复核与上述发现一致，详见 [独立复核记录](evidence/menu-bar-input-takeover-design-review-2026-10-07/independent-review.md)。这些是静态设计发现，未由新真实动作复现；本轮也未更改相关代码。

## 最小组合设计

**阶段A：保持当前授权范围，补齐停止链路。** 新建一个操作世代绑定的sticky stop状态和串行dispatch arbiter；当前ANY/fixed Q及其他原门禁继续存在。任何取消、未精确匹配自身包的已交付输入、未知类型、tap失联/禁用/超时、overflow/序列断档、权限失效、期限/证据失败都永久结束本轮。保留首因、接收时间、世代；随后安静不解除。监听callback只做小型状态更新，不执行落盘、恢复或阻塞业务。

所有会产生效果的入口共用这项状态：第一次session post、第二次PID post、下一packet、菜单open/close、恢复发送及任何光标/前台操作。witness落盘后、回执等待每次迭代、精确回执后均重查；每个route分别串行准入。等待不能靠外层coordinator下一个步骤才看到取消。UI/file取消只允许置位，不能授予start或恢复。

**停止保证必须以软件准入为界写清。** arbiter接受stop之后，不再准入新的普通effect；一次只允许一项在途effect。已经取得准入、正在进入或执行中的系统调用可能仍完成，无法撤回。callback到达、stop被arbiter接受、native调用进入三个时间点不能混为一谈；锁或原子变量不使物理输入与WindowServer投递原子化。即使每次post前复查，仍有检查后输入到达或callback延后情况。当前session/PID双route不能整体算作一个不可分割包；第一项在途不授予第二项。

**状态与环境作补充。** 可以提出明确范围的aggregate held-key状态扫描，仅保留“所选键域是否有键按住”，不留具体键码/内容/序列；使用公开虚拟键目录而非假定0…65535均有效，域外状态明确未知。额外按钮可用公开pressedMouseButtons补充；modifier选择要区分瞬时手势按键与Caps Lock之类锁定状态。全部是串行快照，不能宣称原子无输入证明。新增按键状态查询不在本轮实装范围，若坚持不读取任何按键状态，就必须保留起始普通键已按住的限制。

位置与环境检查只用来拒绝：意外光标差异、应用激活/失活、Space/屏幕变化、目标身份/布局/菜单状态变化均置位；可配合公开NSWorkspace通知和动作前新鲜快照。不能通过增加位置容差替未知输入开绿灯，也不主动warp、抢回焦点。已知安全输入、权限裁剪、监测覆盖不可确认或心跳停滞应停止；自己的runloop心跳只证明线程存活，不证明所有设备事件都在交付。

**接管后的菜单和恢复。** 用户/其他输入接管、显式停止或监测失效后，不自动cancel菜单、不逆向拖动、不还原光标、不抢回前台。不以“恢复最初状态”为由继续发送；保留possible-effect journal。另一次明确恢复请求必须获得新世代、新身份/同实例/布局/锚点/菜单已关闭证明和现有恢复规则。一个新安静期本身不构成恢复请求，也不能自动清除旧责任。

**可能未释放的down单独处理。** 保存原sender/source/target/window/number及哪个route可能执行，状态至少区分notStarted、possibleDown、upAttempted、releaseUnconfirmed。当前失败fallback不是未来方案的安全证明。新契约默认只报告并保留possibleDown；若后续单独批准有限cleanup，它必须至多一次、无drag/归位/新目标、不自动换route，并记录是停止后的清理效果。公开API不能在交错物理输入下证明一个up只终止自己的down；不能同时承诺“接管后绝对零发送”与“总能自动释放down”。无法证明安全时，应给具体人工收尾步骤而不是冒充已释放。此处是必须单独评审的行为变更，本文不更改当前release实现。

**阶段B：仅在另行审阅后选择输入契约。** 可将主要保障改为“对已交付且未匹配自身的活动及时停机；每项效果有界、单次、可保留恢复责任”，ANY保留为诊断/完整性风险信号是否还阻断授权需独立决定。这样不会无限等待对每个ANY增量的归因，但保护范围确实改变，不能表述为同等的全物理静默证明。普通事件type/PID/state或本次171对样本不能替代这一决策。

如果产品要求是“任何物理输入发生后都不能有一包自动鼠标效果”，当前公开异步观测链无法保证；正确选择是继续禁用自动搬移，并用已有公开AX动作或用户手动操作作有限降级。AX动作也需要身份、时效与结果验证，不能保证无并发输入或隐藏第三方菜单都能激活；自有菜单可优先用进程内控制，第三方无公开动作就报告不支持，不能扩展此次自建测试授权。

## 离线验证及后续验收边界

[纯离线模型](evidence/menu-bar-input-takeover-design-review-2026-10-07/stop_contract_model.py) 不导入CoreGraphics/AppKit、不连接生产Permit、不构造事件。15项检查覆盖24种stop/两次dispatch/quiet排列、19种停止原因×9项效果，以及witness后取消、receipt等待取消、菜单打开后接管、在途效果完成、世代不匹配、possibleDown和未确认up日志保留。它证明模型的已接受stop之后无新准入约束，**不是生产实现或实机成功**。

反例明确保留：按下后释放发生在两次poll之间；位置离开后返回；焦点切换后返回；监听开始前已按住键且repeat不计数；未覆盖类型；物理输入先发生、callback后交付而中间已有post。组合信号能降低盲区，不能删去这些反例。[离线结果](evidence/menu-bar-input-takeover-design-review-2026-10-07/offline-model-result.json)。已冻结观测的171对/ANY+190仅作为计数覆盖差异的既有证据，未重新采样、未归因用户。

后续实施阶段A应把这些竞争点用注入适配器测试到真实生产边界，包括文件写入、receipt等待、第二route、菜单关闭和release；新增方案不能通过给mock全空状态来获得通过。实现加固并不自动完成阶段B政策批准，也不自动取得真实动作授权。任何现场验证仍须自建身份/可见区域、现有准入、明确单轮范围、真实效果与恢复证据，不能靠离线模型宣称完成。

本轮证据、独立复核、源哈希和保全见 [证据目录](evidence/menu-bar-input-takeover-design-review-2026-10-07/README.md)。当前根因不能进一步认证为具体设备/事件；可解决的是停止链路和产品保证边界，真实move/menu/close/restore/cancel仍未验证。
