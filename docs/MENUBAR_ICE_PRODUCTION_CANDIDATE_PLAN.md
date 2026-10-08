当前整合验收版（2026-10-08）：用户后续明确授权直接整合安装，现 `/Applications/MacTools.app` 已从实核并备份的0.2.0(4)升级至 **0.2.1(5)**，同Bundle ID／开发者签名、五插件保留并正常启动。菜单栏收纳页接入已验证工作端T/N试用；普通图标已支持只读选择／精确身份绑定，关闭观察代码与离线回归通过，普通实际搬移尚未接通。23项适用回归、签名、预检及自有界面渲染通过；无新T/N轮／第三方动作／新权限／提交。此前“正式版保持不变／不安装”的表述为本次后续授权前的历史状态。[当前版本、验收步骤及回滚](MENUBAR_ICE_INSTALLED_ACCEPTANCE.md)。

以下为既有阶段记录。

# 产品候选受限接入已交付（2026-10-08）

`build/MacTools Ice Candidate.app` 已构建签名，独立Bundle ID/设置，不注册正式快捷键。原产品菜单栏收纳页接入SHA绑定的既有Ice工作端，支持本机单屏自建T/N；默认严格ANY不是硬门。产品二进制零窗口预检、实际自有界面渲染及16项默认插件回归通过；没有为接入重跑已通过的B969A05A正常14投递。该产品入口的新现场按钮尚未执行，可按[试用步骤](MENUBAR_ICE_PRODUCT_TRIAL.md)由用户运行。普通第三方自动搬移尚未接入，不能称通用产品backend已通过。

2px变化的第一份记录发生于归位通过后的cleaning等待期，早于真正移除自有项约12.102秒。H仍可见且宽度未变；退出后企业微信宽+2与左侧等量位移符合重排，触发原因及间接影响仍未知。不补偿第三方、不放宽归位、不以此重复正常轮。[时序分析](evidence/menu-bar-ice-v3_7-exit-reflow-analysis-2026-10-08/README.md)；[产品交付证据](evidence/menu-bar-ice-product-entry-2026-10-08/README.md)。

正式0.2.0(4)/backend不变，无安装提交。三份既有源码仅加入候选编译分支，其他141基线文件及六份ANY政策保持。若继续普通应用图标，需扩展目前自有绑定/关闭RPC，并明确一个目标的一次菜单/搬移/关闭后归位授权；尚未开启或操作。

## 以下为历史阶段记录

# 当前 v3.7 Ice 对齐候选：真实闭环通过（2026-10-08）

按用户“去掉这个门禁，先和ice保持一致，先快速验证功能”的明确指令，默认隔离T/N候选不再依赖严格ANY固定计数授权，使用Ice原有mouse tracking／mouseQuiet运输。正常入口不创建原ANY授权监听／Permit；严格ANY仅保留显式诊断，旧拒绝证据保持。身份、超时、共有stop、journal、菜单租约和归位核验继续执行。

唯一B969A05A轮已真实完成14投递（搬出6／点击2／归位6），菜单打开关闭、原生关闭租约和T/N/H/D原位复核通过。22份ACK先持久化returned再清除，helper13924／13976退出，journalPending=false，realClosedLoopVerified=true。实际既有Team58TJ64422P及权限通过，无新权限请求。313项离线检查及41项来源清单通过；旧24根9826文件、144生产及六份政策保持。操作内35个peer完全相同；创建前到退出后快照出现一项宽度+2px及八项联动X−2px，来源未知，未操作第三方消差。[完整现场证据及范围](evidence/menu-bar-ice-v3_7-ice-aligned-live-2026-10-08/README.md)。

默认入口：`python3 Tools/menu-bar-ice-baseline-session.py --prepare-ice-aligned`，再以新目录`--launch-session`并按现有Start一次。正式0.2.0(4)/backend未改，无安装提交。此轮正常功能已通过，不等于正式产品接入或原ANY验收；不自动追加新现场。

## 以下为历史阶段记录

# 当前 v3.6 原生入口状态（2026-10-08）

窗口发布／签名路径绑定、既有开发者签名的真实 Team `58TJ64422P` 和控制端既有 AX／post／listen 权限已通过；41项候选来源、313项 Swift离线检查（35＋46＋140＋92）。实际 EC7036FD 轮的真实 Start 全字段匹配，但原 ANY 在固定回执后起点31219024之后读到31219025，tap仍1116，`claimRequest` 拒绝 `laterInput`。Permit／运输构造／真实投递均0，helper已退出。新ANY、菜单租约和private-source完整原生回执仍未通过；旧v3.5实际正常14投递及等待取消8投递保持旧标签。

最新离线诊断排除了本地重复累计与重复up处理，确认5.7305ms查询间隙；age提示不是事件或行为者证明。此前零注入观察证明ANY并不等同于17类公开事件计数之和，当前+1来源仍未知。不再要求用户反复点击，不改ANY起点，不删drain/pump抢过门禁。保留严格ANY的可用性代价与独立“点击意图＋后续安静倒计时”契约的收益／保证变化已写成有限决策材料，尚未切换。[时间线、可复算分析与有限结论](evidence/menu-bar-native-any-counter-diagnosis-2026-10-08/README.md)。

正式0.2.0(4)、144生产源码、六份ANY政策、backend关闭、无提交或安装保持；当前失败的晚采样公开端点有变化且来源未知，不称第三方端点完全一致。以下按版本保留历史记录，其中“Team=nil／未接原生入口”只适用于早期bridge构建。

## v3.6 bridge 阶段记录（2026-10-07）

# Ice 隔离生产接入候选 v3.6

客户端任务日期2026-10-07；分支 `feat/menu-bar-reliable-activation`，HEAD `167771fe`。本阶段仅收口以下三项，不新增场景门槛。正式 0.2.0(4)、144份生产源码、6份 ANY 政策保持；backend关闭，无提交或安装。

| 有限清单 | 实现与验证 | 尚未完成的同项验收 |
| --- | --- | --- |
| 显式恢复检查／责任退役 | 完成。仅 stopped、运输已配对或从未保留 route、无未确认 down 的自有记录，且两次原生观察确认原两个 PID 退出和四个窗口 ID 消失，才可显式归档退役。完整原记录先以0600文件、fsync／独占链接／目录fsync保存，随后再次核对并移除活动记录。归档部分失败保留责任，重启必须以新鲜证明显式继续。实际 AE1FB9E6 记录已零移动退役。 | 未知 down 继续阻塞，未实现或声称自动释放；这是明确的拒绝条件，不是本次另起验收项目。 |
| 原 ANY 契约桥接 | 编译完成；直接使用原 RealLocalAuthorization、Gate、Registry 和共有 stop，不改原策略。传入同进程原生 Permit、真实签名和完整 private-source packet；prepared journal先持久化，再逐 route预留／注册／匹配完整回执。显式 replay 只能绑定离线 Native。14 route正例、丢失／外部／未匹配／字段变化等拒绝回放通过。 | **原生入口未通过。** 当前测试签名实际 Team ID为空，原契约要求非空真实 Team ID；AX Start也不产生原同进程原生 Permit。只读列举确认还有现成 Apple Development 身份，但未切换候选 signer或核对该身份的既有权限；没有改签名身份、权限或构造虚假身份／授权。原生 private-source packet 的系统完整回执仍需在这些原入口条件满足后验收。 |
| 菜单 open／closed／unknown 租约 | 编译并接入实际共享引擎。按 owner签名／PID／启动时间、nonce、display／Space和新鲜序列观察公开窗口元数据；先看到归属 owner 的 popup，再有至少100ms的两份新观察确认消失，才允许归位。失去身份、未知关闭、监听不健康、重开或陈旧证明阻止归位。普通第三方 owner也可使用这层只读状态观察，未给予移动或关闭能力。 | 新菜单观察路径尚无 v3.6现场通过记录。自有v3.5原始菜单及关闭后窗口数据回放、同一 engine/Native注入联动正例和三项拒绝通过；保持 replay标签。第三方菜单未被实际点击／关闭／移动。 |

当前候选已签名、40项完整来源清单、**310项 Swift离线检查（35＋46＋140＋89）**通过。此次实际系统鼠标post／tap／新GUI为0；原PID／窗口元数据只读查询用于显式退役。旧20个冻结根7490文件、正式应用SHA及生产／政策哈希保全结果见[本轮证据](evidence/menu-bar-ice-production-bridge-2026-10-07/README.md)。

**可试用候选的范围已经固定：本机单屏、自有 T/N/H/D、原 mouseQuiet 入口、一次正常闭环或菜单关闭后的等待取消。** v3.5旧现场证明保留原版本；v3.6可重建／预检并准备新session，新增菜单路径的第一次现场验证应明确标为v3.6，不重用旧结果。ANY原生入口及第三方产品使用不在已通过范围。没有为当前自有试用另增多屏、刘海或按下途中取消门槛。

```sh
sh scripts/build-ice-baseline-candidate.sh
python3 Tools/menu-bar-ice-baseline-session.py --preflight
python3 Tools/menu-bar-ice-baseline-session.py --prepare-session
# 使用上一步返回的完整目录：仅在协调好自有场景时启动。
python3 Tools/menu-bar-ice-baseline-session.py --launch-session <完整目录>
```

构建／预检／准备不打开GUI、不发送事件。launch打开自有fixture及控制端，等待现有Start按钮；此入口保持mouseQuiet，不授予ANY。每轮目录只能用一次，终态后不能复用。

取消后恢复检查及显式退役入口：

```sh
"/tmp/mac-tools-ice-baseline-candidate-20261007/Ice Baseline Controller.app/Contents/MacOS/IceBaselineController" --inspect-recovery
"/tmp/mac-tools-ice-baseline-candidate-20261007/Ice Baseline Controller.app/Contents/MacOS/IceBaselineController" --retire-owned-fixture <检查返回的nonce> <检查返回的recordSHA256>
```

只在返回 `eligibleForExplicitOwnedDisposalRetirement` 时才可能成功；原生双次观察、精确旧记录CAS和新停止世代仍在执行中检查。存在 owner／原窗口或未确认 down 时拒绝，不做隐式补up、逆向、warp、删记录重试。归档声明 `ownedFixtureDisposed`、nativePosts=0、nativeReturnProven=false、physicalReleaseProven=false；它不把取消改写为正常归位。

原生产 live movement driver继续抛 `movementUnavailable`，正式backend未启用；版本化候选桥接不等于已经接入正式产品。下一次要完成的固定验收为：v3.6自有菜单租约现场；ANY则先获得原契约已要求的真实签名Team／原生Permit，再验其完整原生回执。未满足条件时报告同一项阻塞，不放宽策略，也不扩展成无限清单。

## 以下为 v3.5 阶段原记录，状态按当时理解

# Ice 候选接入与验收边界

客户端任务日期2026-10-07；原始 UTC 时间不改。分支 `feat/menu-bar-reliable-activation`，HEAD `167771fe`。已完成隔离候选 **v3.5 异步 journal/stop 适配**、控制端恢复门禁、构建签名和安全离线回归。新19项清单下的自有正常与等待取消两轮现场均通过。正式 `/Applications/MacTools.app` 0.2.0(4) 与生产 backend 保持不变；未提交或安装。

## 当前可交付范围

候选位于 `/tmp/mac-tools-ice-baseline-candidate-20261007`，revision 为 `isolated-Ice-0.11.12-baseline-v3.5-async-durable-candidate`。可重建，已在本机单屏自建 fixture 范围完成正常闭环及等待取消验收；当前取消恢复记录保留，阻止新交易。来源仍是 Ice 0.11.12 固定提交 `d567f1ecac68936a090d6b47d6f0b882c489c6f4`。独立构建，没有把 GPL 派生运输链接进正式产品；分发前仍须审阅许可及包内告知。

```sh
sh scripts/build-ice-baseline-candidate.sh
python3 Tools/menu-bar-ice-baseline-session.py --preflight
"/tmp/mac-tools-ice-baseline-candidate-20261007/Ice Baseline Controller.app/Contents/MacOS/IceBaselineController" --inspect-recovery
```

构建自动执行离线测试；其余两条只核验签名、来源及恢复记录，不开 GUI、不发送事件。CLI 检查先于 NSApplication 创建。当前保留 `AE1FB9E6` 的 stopped 记录，实际新 session 已被拒绝。存在旧记录时 `--prepare` 与 `--launch` 拒绝；直接绕过 helper 启动控制端，协调器也在创建原生运输之前拒绝新交易。不要删除 recovery 目录来重试。

新增 `IceBaselineCandidateJournal.swift` 与 `IceBaselineCandidateCoordinator.swift`，测试是 `IceBaselineCandidateTests.swift`。异步 MainActor 协调器持有一个不可复位的 `MenuBarOperationStop` 世代。I/O 在 detached worker 中完成，不使用嵌套 runloop，也不让 `withoutActuallyEscaping` 的取消闭包跨 await。UI Cancel 与 Task 取消进入同一个 stop；成功回执、安静或新 Task 均不能复位。

```text
prepared(durable) → moving → visible → opening → menuClosed
→ restoring(durable intent, includes 15s wait) → returned(durable evidence) → clear
任何失败/取消 → stopped + retained responsibility
写入结果不明 → stop + uncertain proposal；不重写，不继续投递
```

Journal 采用 owner/路径/PID/启动时间/签名哈希/nonce、四个窗口实例、display/Space、原始布局及停止世代绑定，checksum、CAS、0600 文件/0700 目录、nofollow、单链接、inode 检查、进程锁、文件和目录 fsync。阶段只向前；三组手势及每组 route 只能追加。prepared ACK 之后才创建原生运输。每个 down/up 的完整原始 packet 与计划路由在 50ms 运输开始之前持久化；该准备另有 500ms 上限，慢落盘不延长运输期限。

原始移动 down 的 clickState=1、up=0，点击两者为1，这是 CGEvent 构造器和已封存 v3.3 packet 的实际值。保留 Command down、无修饰 up、H/N 窗口目标、marker、坐标、source state 和 timestamp。系统投递会注解 CGEvent flags；绑定候选每次发送字段相同的副本，使原始意图保持不可变。未规范化收到的 packet、未放宽字段检查。离线回归模拟发送后 flags/timestamp 被修改，原始责任仍一致；真实窗口服务器已在本轮正常14post和等待取消8post中走过新副本路径，正常归位严格通过。

每个 session/PID 投递、tap 创建/启用、运输创建、suppression、hide/warp 与自有菜单关闭请求均受同一 stop 准入。tap 禁用、移除监听及平衡本实例已成功 hide 的 show 可在停止后清理。已准入的同步调用或 I/O 可以在停止后返回；不能宣称 stop 撤销了在途调用，更不能宣称物理输入与 post 原子排斥。

`downReserved/downReturned/upReserved` 视为保守的未确认责任。**reserved intent 不等于实际 post，pairedTransportReturned 不等于物理释放。** 例如 down reservation 写入结果不明而实际 post=0，内存仍保留 possibleDown=true。重启只读出实际提交版本；既存交易阻止新 nonce。只有三组运输配对返回及严格归位证据持久化后，才准入清记录。控制端 result 保留最后已证实的完整 record/绑定/route、每次 durable ACK 的 revision/phase/record hash，以及写入不明时的 proposal；清 journal 不清这份审计。result 最终保存仍可能失败，不能据审计内存冒称文件已写入。停止、配置清理、自有窗口退出或一次按钮 false 均不能清记录。

绑定候选任何运输失败都终止该世代，不执行旧 engine 的 fallback/wake/retry；独立旧 engine 测试仍保留 Ice 原有有界重试行为。这个候选差异明确记录，不把旧行为的通过冒充新适配器通过。

## 可安全执行的回归结果

本轮共 **270 项**：35 生命周期、46 共享 Engine/Native 路由、138 异步 durable 适配、18 布局、16 会话/恢复门禁、17 严格归位回放。实际 OS send/tap/monitor/窗口/cursor 操作为0；测试调用实际 Engine、Native、协调器与真实文件 journal，注入 tap/send/帧/时钟 seam。正常注入轮走14个 Native send 调用并清除已证实返回的日志；不能称真实移动。

| 情景 | 检查及实际范围 |
| --- | --- |
| 正常 move/click/15s rehide | 真实共享代码、14次注入发送、三配对手势、证据先落盘再清；无系统发送 |
| 八个投递边界取消 | 1～8次注入发送处停止，所有 tap 禁用；不追加下一 route、up、fallback、wake 或逆向；保留责任 |
| 15秒等待取消 | 8次已配对注入发送，之后0；逻辑 possibleDown=false，恢复交易仍 retained |
| Task 取消/暂停 fsync | MainActor 仍能停止；完成的写入返回后保留 down 意图，不发送；另 Task 不可复用 |
| prepared/down 落盘故障 | 临时文件、文件 fsync、rename、目录 fsync 注入；不明结果停止，原 store 禁止覆盖；重启读实际提交版本 |
| 慢意图 I/O | 独立500ms准备期限拒绝；不进入、延长50ms运输 |
| 身份/权限/期限/timeout | 各自终止，无 fallback/wake，持久化 stopped；未知 down 保守保留 |
| 篡改原 packet | PID/window/flags/click/source/point 均拒绝，0发送；不改正常 packet 构造 |
| Journal 安全 | stale CAS、阶段倒退、不足三配对手势的 returned、未知状态清理、截断、symlink、目录 inode 替换拒绝 |
| clear 不明 | 只有 returned 已持久化才准入 unlink；失败保留 returned 证据和不明诊断，不虚构 down 或硬件结论 |
| 新会话 | 旧 retained 记录即使 nonce不同也阻止 prepare/launch；缺失或错误恢复响应拒绝 |
| 默认/产品契约 | disabled/productionANY 在写 journal 及任何原生效果前拒绝 |

适配阶段[checkpoint](evidence/menu-bar-ice-async-adapter-2026-10-07/checkpoint.json)、源码清单、构建/回放日志和保留核验独立封存，记录当时尚未做新现场。之后另根封存[正常现场](evidence/menu-bar-ice-v3_5-normal-live-2026-10-07/checkpoint.json)与[等待取消现场](evidence/menu-bar-ice-v3_5-wait-cancel-live-2026-10-07/checkpoint.json)，不能改写前一阶段原件。旧v3.4的126项为历史版本结果。

## 产品输入契约评审

| 契约 | 准入与输入语义 | 本轮结论 |
| --- | --- | --- |
| disabled | 默认值；写 journal、创建运输或发送前拒绝 | 保持默认拒绝，离线已验 |
| isolatedOwnedQuietV1 | 明确授权的自建 T/N/H/D；一次 Start/nonce/清单；原 Ice mouseMoved 100ms quiet、同一 stop、所有绑定身份/区域检查 | 仅此隔离候选接入；人工或已授权自有 AX Start 不作为硬件起始证明；未扩大到第三方 |
| productionANY | 现有 annotated listen-only 监听健康、ANY counter/age、连续性与本地授权等既有规则 | 新适配器直接拒绝，六份 ANY 源码保持哈希一致，未以 mouseQuiet 替代 ANY |

Ice 的 mouseMoved 观察、共享按钮快照、创建 hidSystemState 事件源、CG 权限通过都不能证明物理排他或实际设备来源。候选尚未实现生产 ANY 的版本化桥接、第三方菜单 open/closed/unknown lease 或全部监听丢失策略，不能开启产品 backend。现有 `MenuBarHiddenMoveCoordinator.run` 是同步/5秒协议；生产 `MenuBarLiveOperationDriver` 仍抛 movementUnavailable。未修改这两者来假装兼容15秒流程，144份生产源码逐字节保留。

## 旧现场证据与剩余门槛

v3.3 自建正常轮 `34B24C5B-C6DD-4291-9C5A-259AE13080D5` 实际14投递，严格归位、两份公共/私有最终检查和 **34个第三方** 对照通过。取消轮 `D5C3C212-F8CC-48D2-B007-B898E1415DFC` 菜单已关闭后等待取消，实际8投递；停止后投递/补发/逆向/warp为0，约15.102秒有界退出。它们继续保留原 v3.3 标签，未重跑或改写。

新 v3.5 现场已完成，两个单实例按顺序使用新 session，19项签名/来源清单一致：

| 新现场 | 实际结果 | Durable 接入与清理 |
| --- | --- | --- |
| `4B11BA2F-A356-4897-96B8-836A1CAA3ACD`，fixture71144/controller71146 | 一次自有AX Start；14post move/menu/close/restore，严格三样本与双最终公共/私有检查，realClosedLoopVerified=true | 22份ACK revision0～21，route6/2/6，returned证据持久化后清记录；helper退出、T/N偏好恢复、H/D清理 |
| `AE1FB9E6-027E-4A2D-A447-2A894C9C3A88`，fixture73065/controller73078 | 一次AX Start＋一次AX Cancel；先确认菜单关闭、durable restoring且两手势配对，8post停止，之后post/warp/fallback/wake/逆向0 | 17份ACK revision0～16，stopped保留、pendingRecovery=true、逻辑unconfirmedDown=false；取消后15.060592秒fixture finished，helper退出/偏好恢复，新session实际被拒绝 |

两轮各自启动前与退出后 **33个第三方** 公开端点精确相同；正常运行期完整37窗口（4自有＋33第三方）peerBefore/peerAfter精确相同。数量取本轮原件，旧v3.3的34个仍按原版本引用。fixture创建前与创建后的布局是不同边界，端点对照不排除所有中间影响。没有第三方target动作。

当前可交付范围是本机单屏、自有T/N/H/D、原Ice mouseQuiet契约的真实正常闭环与等待取消；自动恢复/再次使用的完整产品工作流尚未交付。取消后保留记录，无清责任入口，不删记录继续下一轮。Start由已授权工具标准AXPress现有自有按钮完成，不再人为要求真人手点，也不把AX回执当成硬件证明。

最低生产接入阻塞是已有三项：保留责任的显式恢复/退役（包括未知down）、生产ANY与live movement driver的版本化桥接、第三方菜单open/closed/unknown lease。自有关闭RPC保持测试专用。多屏/全屏等未验收场景不在当前已交付范围内；不为本次单屏自建目标新扩验收需求。生产backend仍关闭，没有提交或安装。

## 12份阳性记录保持未知

已封存1261份查询，取消后730份；两个共享状态各12份阳性落在同样三个区段，分别5/3/4份，约取消后3.818～3.910秒、15.886～15.934秒、16.763～16.830秒。后两个区段 fixture 已退出；所有区段没有同期新的自有 post。八个自有 post 全部在取消前，末次约早204.691ms；取消探针调用 AXPress，没有鼠标发送。

查询没有 device、packet、来源PID或操作端硬件回执。不能称12次点击、归因为正常用户动作，或仅凭无新post排除旧异步状态影响。没有新增无限采样或重放来猜来源。按钮 false 只证明查询时刻的共享布尔值，physicalReleaseProven 仍为 false。原[只读归因](evidence/menu-bar-ice-deliverable-candidate-2026-10-07/button-attribution.json)保持不变。

## 按下途中真实取消：恢复与风险评审

**本轮只评审，不执行。** 会保留部分移动或 WindowServer 逻辑 down，风险高于菜单关闭后的等待取消。stop 永久拒绝下一 route/up/fallback/warp/restore，不能用“取消”暗中补一次 up。

拟议现场严格限定一个新 nonce、自有 T 与可见 H。v3.5正常/等待取消现场及durable意图/只读恢复检查已通过；进入更高风险场景前，必须先验证明确恢复/责任退役条件，记录预算/目标/所有预准入 route。最多在一个指定的 session down 边界停止；未知投递数量不得继续另一轮。新 coordinator、清配置和 helper 退出都不能擦除旧责任。

有界恢复顺序：

1. 立即请求同一 stop，禁用本实例 tap/监听、平衡已 hide 的 cursor，保留未确认 down 与原 owner/邻居/Space；只记录操作数量，不发送 up 或逆向。
2. 只读 `--inspect-recovery` 和已绑定状态原件。系统共享按钮查询需外部超时；超时停止查询进程，不能据此发送恢复事件。一次 false 不清记录。
3. 若现场有持续按下/拖动现象，暂停自动实验；操作者可在自有可见恢复界面手动按下再释放鼠标，可能改变焦点和状态。该步骤是人为释放尝试，效果未经本轮证明，不等于归位或可清 durable 责任。不能把手动动作纳入候选自动发送授权。
4. 自有 helper 有界退出、nonce H/D 配置清理分别留证；配置原位、窗口退出或再无现象仍不自动清日志。没有新鲜同一 owner/原邻居/Space 及明确责任消除证明时，保留阻塞。

当前未实现/验证自动消除未确认 down 与可安全退役责任的恢复入口，因此这不是已经保证成功的恢复方案。若有必要进入该较高风险现场，父线程须先评审上述具体风险和操作者可执行的手动释放步骤，并明确追加该轮操作范围；无法提供有界恢复条件时保留注入验收。本轮没有因此阻塞可完成的适配、签名和离线回归，也没有向用户重复索取既有批准。
