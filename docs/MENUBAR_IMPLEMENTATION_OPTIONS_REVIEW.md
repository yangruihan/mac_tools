# 菜单栏可靠激活的实现选择

2026-10-07。评估依据：当前分支 `feat/menu-bar-reliable-activation`、已冻结的493项测试证据、本地固定Ice源码、Apple官方文档/SDK，以及下载后只读核对的Hidden Bar与Dozer原始源码。本轮只有评估文档和证据新增；生产代码、ANY用途、正式安装、backend状态均不改变，未启动现场窗口、tap或系统事件。

**证据更正与次序更新：官方Ice0.11.12在本机自建T/N已有一次真实move/menu/close/restore闭环；我们当前搬移和提议的混合方案均未实测通过，不能称更可靠。下一步先复现固定官方Ice基线，再建立相同运输算法的独立基线，逐项加现有控制并实测。**原评估遗漏了[完整Ice现场证据](evidence/menu-bar-ice-authorized-permissions-2026-10-03/owned-T-closed-loop/README.md)。[更正后的基线路线与权限差异](MENUBAR_ICE_BASELINE_REPRODUCTION_PLAN.md)是当前下一步依据；下文保留各方案技术比较，不能当作混合方案已经更可靠的结论。

这项推荐不意味着更改ANY。**严格ANY仍可能在发送前拒绝正常请求，换运输引擎不能解除这一点。**如果坚持当前策略，就接受其保守可用性边界；如果希望消除ANY-only单独否决，需要另行明确决定有限观察停止契约，影响面见[已有策略评估](MENUBAR_INPUT_TAKEOVER_AVAILABILITY.md)。

## A、B、C比较

| 路线 | 可复用价值 | 当前关键限制 | 建议 |
| --- | --- | --- | --- |
| A：完整隔离复用Ice0.11.12 | 窗口/PID定向包、null握手、session/PID路由、帧变化观察、原邻居归位；有完整产品使用经验 | 源码快照只包含参考片段，缺EventTap/MouseCursor/MenuBarItem/AppState等依赖；原样补up、唤醒重试、tap自动重启、定时归位、光标warp与永久停止冲突；不能保证本机运输成功 | 不整体调用ItemManager；提取完整运输算法为显式改造的适配器，单独验收 |
| B：现部分移植＋自研门禁 | 身份及布局、durable witness/journal、逐route停止、unknown-down责任已有生产注入验证 | 当前session→PID并不等价于Ice的PID null→session→PID；包语义也有差异；真实发送为0，无法判定运输有效性 | 保留外层控制；暂停无目标的门禁扩展，将工作收敛到运输差异及真实闭环 |
| C：平台公开AX／自有进程内菜单控制／自有宽度展开 | 对提供动作的目标减少全局鼠标副作用；现有AXActivator已有唯一身份和动作前重查 | AX支持由目标决定，不能保证隐藏图标均提供动作；宽度展开不是逐图标搬移，空间不足仍可能不可见 | 作为当前可交付功能边界和正常降级；不能声称替代所有第三方搬移 |

独立只读审查同样不建议A原样替换，并推荐先交付C的明确范围、保留B保护边界，再做经过改造的A运输实验。[审查摘要及本轮保全](evidence/menu-bar-implementation-options-review-2026-10-07/README.md)。

## Ice哪些动作保留，哪些必须改

固定参考版本：Ice0.11.12，commit `d567f1ecac68936a090d6b47d6f0b882c489c6f4`；不是宣称该版本在所有新系统仍可靠。

| 上游动作与代码位置 | 处理 |
| --- | --- |
| `MenuBarItemManager.swift:1648` 写目标PID/窗口字段，`:1511` 搬移down带Command、up无Command | 保留窗口定向思路；先做事件包逐字段差异表。当前`MenuBarOwnedMouseTransport.swift:44` down/up共用command，native channel要求flags相等，不能简单把up清flags后绕过匹配。改造应预登记同gesture的各自精确预期包；不允许跨gesture、归一化收到的包或模糊匹配。source `.hidSystemState` 对现private source的差别也须明确记录，不假定等价 |
| `:724` null先到PID，再触发真实session包，session精确回执后转PID | 保留完整握手顺序；每个null/真实包、每次callback投递都经过同一stop准入与witness，不仅在外层检查。现exact registry不支持null，必须扩展明确包类型/一次性回执，不对未知活动豁免 |
| null defaultTap回调返回nil；`:752`、`:784` disabled后自动enable | 需改变。只处理精确登记的自身null；其他事件原样透传且按现策略停止。监听disabled永久停止，不自动重启同世代。主动过滤tap不同于当前listenOnly范围，须另行明确接受实验能力范围；不请求或修改系统权限 |
| `:826` 帧变化等待及`:1109` 精确邻接等待 | 保留观察同步；最终成功继续采用现完整排列、peer位移和身份验证。上游帧不可读时固定50ms延时不能替代新鲜证明；只发生位移也不算目标位置成功 |
| `:997` combinedSessionState permit-all filter、suppressionInterval=0 | 首个候选不引入这些全局事件源配置修改。Ice此处不是阻断人的所有输入；其设置也不能证明零竞争。如果缺此步骤导致搬移无效，应明确报告方案在现约束下不成立，不能暗中启用 |
| `:1022` 错误后fallback up；`:900` wake-up也是down/up；`:1079` 最多五次尝试 | 首个候选不启用。取消、接管、监听失效、uncertain down/up之后一律停止，保留责任。日后有限重试只可针对独立可证明无未决效果的类型化结果，且明确重试预算/授权；当前failed会永久停止，不能catch错误后自动继续 |
| `:1067` stopAll自身eventManager，`:1075` defer恢复旧光标位置 | 保留外部输入监听，避免盲区；首个候选避免新增hide/warp。接管后不得无条件把光标拉回旧位置。若运输确实需要warp，须作为额外效果讨论和验收 |
| `:1237` 记录左右邻居；`:1392` 菜单仍开/按钮按住时定时再归位，失败三秒再试 | 保留原邻居定位及菜单关闭证明。正常归位属于仍有效的原操作；一旦stop就不再关闭菜单或归位。用户后续安静不重启本轮；显式恢复使用新世代，unknown-down仍禁止逆向及清日志 |

主动tap、null包、本机系统鼠标流及额外重试的实验范围，应与ANY用途决定分开。保持ANY并不等于新增null会自动通过现策略；所有已知自身效果必须有明确契约，无法解释的ANY依旧拒绝。不得因换引擎而隐藏原始计数或扩大豁免。

这些事件包和路由差异是需要验收的功能风险，**不是已实测定位的搬移失败根因**：当前请求在发送前被拒绝，实际运输尚未执行。适配器应在同一绑定线程/CFRunLoop处理回执与准入，监听回调只做有界匹配/状态通知；避免把磁盘落盘或阻塞等待放进tap回调导致系统disable。实际路由发送前仍须完成独立witness与最后stop检查，不允许用性能优化取消它们。

## 原生及其他开源是否更可靠

本机只读确认是macOS15.7.4/build24G517。Apple的[NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)提供创建自有状态项、长度、菜单、按钮及可见性；[autosaveName](https://developer.apple.com/documentation/appkit/nsstatusitem/autosavename-swift.property)为自有项保存信息。SDK的NSStatusItem.h没有用于指定并搬移其他进程图标的公开排序接口。这是核对到的接口边界，不是对所有可能Apple接口作绝对不存在的证明。

官方[expandedInterfaceDelegate](https://developer.apple.com/documentation/appkit/nsstatusitem/expandedinterfacedelegate)从macOS27提供自有状态项展开界面的生命周期；赋NSMenu的项不接收这些回调。它不能用于当前15.7.4，也未提供跨进程搬移接口。将来可用于自有界面闭合证明，不应当作第三方排序替代。

公开AX路径先读取动作列表，再执行支持的ShowMenu/Press。Apple官方[不支持动作错误](https://developer.apple.com/documentation/applicationservices/axerror/actionunsupported)及SDK AXUIElement.h:283–331明确目标可以不支持动作；cannotComplete也可能是目标尚未返回，不能据此自动再点击一次。当前`MenuBarAXActivator.swift:16–54`已直接查询所属应用的extrasMenuBar，唯一匹配PID/角色/几何并动作前重查，不必反复全局hit-test试坐标；`:58–63`保留uncertain结果。反应或API success仍需要菜单状态证据，不能当闭环成功。

只读下载并核对两个固定原始源码快照：

- [Hidden Bar v1.10，86b08cc](https://github.com/dwarvesf/hidden/blob/86b08cc469ac58f76bc6435a44ad2e8f736d0c34/hidden/Features/StatusBar/StatusBarController.swift)：通过改自有separator.length展开/隐藏左侧整组，不提供这里所需的逐图标定向move/restore。可参考低副作用的自有展开，不能解决全部刘海/空间不足目标。当前上游架构文档与后续版本正在变化，本评估没有把旧快照或develop文档当成最新发布实现。
- [Dozer，b054037](https://github.com/Mortennn/Dozer/blob/b0540378c01690ce566058b67bc7dc7e01efa4e6/Dozer/StatusIconClasses/HelperStatusIcon.swift)：show/hide同样切换自有statusIcon.length；项目说明要求用户手动Command拖动分组。未发现能替代Ice逐目标搬移的成熟原生运输实现。

因此C更适合覆盖可提供语义动作的目标；剩余真实搬移，Ice运输是目前已核对材料里更贴近需求的参考，而非有官方长期兼容保证的方案。

## 493测试的有效范围和缺口

冻结证据证明493项全量Swift、两种编译条件各66项相关检查、44项Python及五入口typecheck通过。新增19项验证生产发送链和coordinator的停止竞争点，不再只是抽象模型。实际权限/状态/发送/时钟/pump被注入替换，CGEvent仅构造，未投递、未启动tap/fixture。

这些检查证明停止准入、责任保留、日志顺序、边界校验的指定行为；不证明WindowServer实际接收、目标处理、真实菜单打开/关闭、排序/归位、监测覆盖或调度延迟上界。旧v15签名包因新增源码缺清单而预检拒绝，不能称新版运行就绪。真实move/menu/close/restore/cancel缺口仍完整保留。

## 最小实现路线和退出条件

1. **先复现已经通过的官方产品基线。**固定0.11.12原包、原有工具及选择器，独立新nonce/目录；只做自建T一次正常move/menu/自有AXclose/Ice restore。现有一次正证据不保证下一轮或全部设备成功，原失败轮同样保留。只读评估不授权本轮执行。
2. **建立最小相同算法的运输基线。**按固定源补齐所需依赖及逐字段/路由差异，不先删完上游行为再称完整复用。保留主动tap、suppression配置、retry/cleanup/warp等若与现契约冲突，先决定实验范围；未批准则不启动，明确仅有官方黑盒基线。
3. **逐项加入我们的控制并做因果对照。**每次只改变一个明确因果组：身份/日志、精确归因、共享stop/unknown-down、授权/ANY。停止后禁止自动补发/唤醒/归位属于需要验证的改变，不能凭逻辑测试认定可靠性更高。首个回归定位前后差异后停止叠加。
4. **保持政策及发布边界。**原准入/5秒预算和ANY不暗改；官方基线实际返回约15.2秒，不能称其已满足5秒执行。新helper始终独立签名/源清单/身份绑定，旧v15不混用；当前backend禁用、不安装、不扩展第三方。需要主动过滤或输入策略变化时单独明确决定，不用对比提问当批准。

首轮按move→menu open→close→restore推进，每阶段独立记录结果，失败即停止；取消试验只按另行明确的阶段和预算执行，不能偷偷多搬一次。只有相关阶段各有原始证据，才能称端到端通过。不得先用进程内菜单调用掩盖鼠标click未验收，再把它算作完整系统鼠标闭环。

量化验收建议（未来候选的明确预算，不是本轮已经通过）：

| 指标 | 首轮门槛 |
| --- | --- |
| 正常动作 | 一次move、一次menu open、一次close、一次restore；没有自动失败补动作 |
| 当前B运输上限 | 三个down/up对，最多6个鼠标包×2条route＝12次系统投递尝试；close为一次自有菜单请求 |
| 提议的统一null握手上限 | 若6个鼠标包全部采用PID null→session真包→PID真包，最多6个null包＋6个鼠标包、18次投递；tap不是投递，不能漏记null。AX优先路径须单列动作数，不能混报为鼠标通过 |
| 成功证据 | 两份新鲜一致的目标身份/布局原始观测，精确目标邻接与peer排列；菜单确实打开/关闭；最终原始布局恢复，returned落盘先于journal clear |
| 停止证据 | 软件接受stop之后新普通效果准入0，最多一项已准入效果完成；分别记录session/PID/null/close/restore，不能用聚合计数掩盖第二route |
| 不确定结果 | unknown down/up不补发、不重试、不逆向、不清journal；原位几何不能消除责任 |
| 时限 | 保留原准入与5秒执行预算；实际wall time和超时阶段记录，超时就失败，不把软件检查宣称硬实时上界 |

一次成功只证明当次自建对象、15.7.4及显示/Space环境。若批准进一步扩大产品范围，预先固定兼容矩阵，每格至少20次正常闭环、每个取消/监听失效边界至少一次；所有错误归位、跨目标、stop后新准入、责任被清除均须为0。成功率、P95耗时、失败原因和人工收尾次数分别发布；建议支持门槛每格至少19/20正常闭环且所有安全不变量通过。这是后续工程门槛，不是统计可靠性保证，也不是本轮无限重复现场的授权。

## 必须决策的风险、回退与维护

用户/父线程需明确的决定：保留严格ANY的拒绝限制，还是批准有限观察停止契约；是否批准主动null过滤tap及对应投递范围；是否接受停止可能留下搬移位置、菜单或未确认down。以后任何唤醒/重试/补up/warp须有单独明确行为与预算。不存在“引用开源就自动获准”或绝对零输入竞争的保证。

故障前无投递：可恢复构建、发布、查询故障继续修，只有durable no-dispatch证明才清准备日志。有possible effect：本轮永久停止，保留身份、原邻居、packet、route和责任，不在用户安静后自动续跑。明确恢复请求才建新世代并按原严格条件处理；unknown-down没有已验证自动消除路径。自有目标可给明确进程内收尾或最小手动步骤，不能拿自有能力推断第三方也可自动清理。

运输不成立或兼容未知时，退回明确可验证的AX/自有展开和手动入口，自动搬移保持禁用。AX动作uncertain不自动切换鼠标再点，避免重复动作；菜单状态未知不强行归位。产品应展示具体未完成状态和恢复要求，不用通用成功提示掩盖中断。

长期维护：固定源码提交/许可证/字段ABI和OS能力profile；现CGS只读及0x33字段均属已有私有依赖，新OS先禁用搬移，独立候选验收后才增支持。监听display/Space、目标重建及菜单几何变化并失效旧计划；按目标动作能力选择AX或运输，避免同次操作在不确定结果后切引擎。上游[0.11.13 Tahoe预发布说明](https://github.com/jordanbaird/Ice/releases/tag/0.11.13-dev.1)已明确菜单栏变化、间歇搬移及归位问题；不能用0.11.12的成熟历史承诺未来系统可用。采用GPL覆盖适配代码时继续保留现许可证及来源记录，正式分发另审组合分发义务。

当前次序：先恢复官方Ice实测基线，再按每项变化验证运输及控制。C仍可作为功能范围有限的降级；混合方案只是假设，不称更可靠。下一次基线实验执行、后续主动tap及ANY变化均按[差异表](MENUBAR_ICE_BASELINE_REPRODUCTION_PLAN.md)分别决定，当前策略和正式版保持。
