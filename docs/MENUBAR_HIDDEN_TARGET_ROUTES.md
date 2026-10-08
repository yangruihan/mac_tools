# 真正隐藏目标的搬移与归位：路线选择

2026-10-03。分支 `feat/menu-bar-reliable-activation`，基线 `167771fe`。本轮是源码/兼容研究和无系统调用的隔离原型；没有现场拖动、私有调用、权限变更或正式版操作。

## 建议与待决定项

**如果产品目标必须包含未ordered的隐藏项，建议选择“独立实现的私有兼容helper评估”，先限定本机15.7.4(24G517)，逐个接口和后验验证；当前不启用。** 这是有Ice源码依据的实验路线，不是已证明的解决方案。纯公开接口路线目前缺少受支持的隐藏窗口起拖及完整逻辑顺序合同，不能据公开函数存在而承诺交付。

需要决定两件事：

1. 是否允许后续单独阶段调用限定的私有**只读**菜单项/Space接口来验证真目标成员关系与ABI，并接受非Mac App Store分发和OS维护成本。本轮指令禁止私有调用，因此此阶段尚未执行；这项决定也不授权发送事件。
2. 是否坚持MacTools独立实现及原有MIT范围，或接受复用Ice的GPL组合成果分发义务。推荐独立实现，不默认复制源码。若选择复用，先确定版权/授权与组件范围，再搬代码。

可见T/N不是最终目标，截图栏或AX动作被接受也不是物理迁移验收。技术首验应从**真实隐藏的自建项**开始；自建项成功后仍需分别批准普通第三方多项、MenuExtra/扩展等产品范围测试，不能宣称已支持全部隐藏图标。

## 三条可执行选择

| 路线 | 下一可执行工作 | 对隐藏目标的能力 | 代价与停止条件 |
| --- | --- | --- | --- |
| A 公开接口独立实现 | 保留AX目录能力；如继续研究事件，只能用公开、按其合同使用的接口，在另获准的隔离隐藏样例中证伪或验证 | CGEventPostToPid、PID tap与公开40/42/91/92字段提供传输工具；没有文档保证隐藏状态窗可起拖，也缺完整菜单项逻辑目录 | 当前不能承诺迁移产品。不能把字段91/92写成隐藏windowID就声称路由正确，也不能把0x33包装成公开能力。仅可见项成功不能结束此路线 |
| B 独立私有兼容helper（推荐评估） | 另获准后，先独立只读SPI成员/Space/几何与身份核验；再决定是否批准一次隐藏项定向事件实验 | 可研究Ice使用的CGS菜单项枚举和未公开事件字段；这些依赖有希望填补成员和起拖缺口，但本机未验证 | 每OS build有单独适配与能力收据、未知版本关闭；私有ABI崩溃/行为变化须隔离。完整原序仍需额外证明，不以私有枚举存在当保证 |
| C 复用开源实现 | 先决定GPL组合分发范围，然后抽取或fork真实移动/返回依赖并建立MacTools桥接 | Ice已有隐藏项临时迁移、邻项返回代码；直接复用不是一个小函数即可工作 | 需要AppState/EventTap/缓存/鼠标等依赖和独立恢复加强，GPL对应源码/通知/构建资料等义务；不能用helper拆分自动规避GPL。当前Thaw不支持本机15 |

如果坚持“公开API保证 + 可靠隐藏迁移 + 不接受不确定性”，现有资料不足以同时兑现；不能用降低守卫来补这个能力缺口。A的实验可能性与A的可承诺产品能力需分开。

## Ice实际路径与公开/私有划分

研究源码固定于Ice `11edd39115f3f43a83ae114b5348df6a0e1741cf`，没有运行或集成其代码。

- `tempShowItem` 在目标未on-screen时取菜单项列表，先保存返回邻项，再寻找右安全区/应用菜单右边有容量的可见邻项，移到其左侧，之后可点击。窗口变化用于推测菜单，计时后等按钮释放/界面关闭再返回。见 [迁移/归位](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift#L1289)。
- 起拖并不依赖普通全局hit-test：代码用目标ownerPID、多个window字段及离屏起点，PID与session tap之间转送/等待事件、观察frame变化；失败有fallback和重试。我们不把这些重试、warp、等待策略直接引入生产。见 [移动实现](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift#L985)。
- **公开部分**：SDK声明CGEventPostToPid、CGEventTapCreateForPid、CGEventPost和CGEvent字段40/42/91/92；PID传输和tap本身不是私有API。它们存在不保证整条隐藏起拖语义。
- **私有部分**：CGSGetProcessMenuBarWindowList、CGSMainConnectionID、CGSGetWindowCount及Space/部分几何查询，以及未命名的事件field51(0x33)。Ice以私有声明调用前者，额外设置后者。见 [桥接](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/Bridging/Shims/Private.swift)、[字段构造](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift#L1549)。本机SDK静态检查中51没有公开枚举名，这三项CGS接口也不在公开header；没有调用它们。
- **原序证明不能外包给SPI**：私有菜单项枚举提供候选成员关系，Ice随后仍按 `frame.maxX` 排序；返回保存左/右邻项，而不是系统提供的持久完整序。窗口枚举顺序、隐藏记忆坐标与真实逻辑序需另验证。见 [取项](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/MenuBar/MenuBarItems/MenuBarItem.swift#L168)、[排序](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/Utilities/Extensions.swift#L490)、[返回锚点](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift#L1260)。

本机原公开status-layer清单包含17条unordered项；SPI可能帮助辨认真菜单窗和非成员，但尚无收据。不能预先删除旧静止ControlCenter窗、猜其不是菜单项，或将混合几何排序认作完整持久序。

## macOS兼容证据与不能推断之处

| 环境 | 一级来源证据 | MacTools结论 |
| --- | --- | --- |
| Ice14+基线 | README最低14，项目deployment14；稳定0.11.12发布于2024-10-29，修过修饰键误判导致无法移动，加入无屏幕录制的有限模式 | 是项目支持范围和功能证据，不是本机15.7.4 ABI/隐藏移动/崩溃恢复证据。[稳定发布](https://github.com/jordanbaird/Ice/releases/tag/0.11.12) |
| 本机15.7.4(24G517)、arm64 | 本轮sw_vers只读确认；上轮同签名caller的AX/post/listen preflight均true | 现有权限不是当时阻断，但新helper身份须单独核对。没有私有ABI或动作验证；已验证的runtime allow-list为空 |
| macOS26 | Ice dev.1报告移动失败、菜单未关闭即回藏和归位错误，且未测Sequoia及以下；dev.2报告修复多数26问题 | 必须独立适配，不能把26分支补丁默认带回15，也不能根据dev.2说明声称完整恢复通过。[dev.1](https://github.com/jordanbaird/Ice/releases/tag/0.11.13-dev.1)、[dev.2](https://github.com/jordanbaird/Ice/releases/tag/0.11.13-dev.2) |
| 当前Thaw | 项目迁至thaw-app/Thaw，README要求26+、GPL-3.0，有独立ItemService及CLI目录 | 可作未来26/27组件候选，但本轮未做其代码审计或执行；不能作为15.7.4可安装替代。[当前项目](https://github.com/thaw-app/Thaw) |

Ice dev.2相关源文件的raw下载失败，API也遇限流；本轮使用其维护者发布说明作兼容事实，未声称已审核该分支实现。SDK26.2静态header审计不等于运行时15.7.4私有符号存在、ABI正确或事件行为可用。

## 接入MacTools的位置与隔离边界

现有 `MenuBarLiveOperationDriver.prepareReveal/reveal/restore` 明确拒绝movementUnavailable；生产AX激活与未知菜单不归位的状态机保持。未来helper应通过单独provider注入既有事务入口，不能直接绕开控制器发事件。

独立进程负责潜在ABI/事件异常隔离，主进程保留事务、日志和恢复责任。IPC要有固定版本/体积/时限/单事务限制，验证双方代码身份/audit来源；helper报告自己的实际AX/post/listen能力。相同Team不等于共享TCC授权，不能靠伪装caller、改权限或让controller代签假收据解决拒绝。helper崩溃时主进程保留possible-effect阶段，原输入租约失效，不自动重发。

**既有可见项Plan不能直接支持隐藏起点。** 它的原始样本及恢复检查要求目标可见；不能给捕获样本填onScreen=true，或删掉守卫。真正隐藏路线需要独立 `HiddenMoveRecord` / 拓扑收据合同：隐藏起点以签名/nonce/item/window强绑定及被验证目录成员关系授权；迁移后必须转为真实可见；归位需恢复原邻接/完整序、原身份/几何且回到原隐藏状态。现有文件持久化机制可以后续抽取复用，当前typed journal不能直接存这种新Plan，需独立文件/版本，不覆写旧日志。

其他必需品：可验证完整参与拓扑而非“只剩目标与锚点”；按所选display/Space的原序责任；关闭菜单后才回藏；输入干预中止且不盲目回滚用户重排；目标激活导致前台变化须另有明确阶段合同，不能全局忽略前台变动。原序未知时记录pending而不是成功。

## 最小隔离原型与阶段

本轮实际新增 [离线helper请求原型](../Tools/menu-bar-hidden-route-prototype.py)。它通过独立子进程stdin/stdout解析真实历史未ordered的T/N，检查前后item/window/PID/nonce一致，分别列出三路线缺失条件；拒绝执行字段、错误owner、窗口变更和可见起点替代。保存T310776/N310777及其同owner几何邻项，但明确这些不是完整原序或活身份授权。9案例通过，所有canExecute/recordPrepared为false，没有native/provider/系统调用。

这个原型验证的是隔离请求和隐藏证据不会被升级为动作，不是起拖驱动，也没有证明目标已重新可见。当前实屏T/N仍未运行；没有为本轮重开。

后续可执行的最小阶段（需上述决定后分别授权）：

1. **SPI只读阶段**：首次只核对接口可解析/ABI/返回形状/成员身份及Space/屏一致性，针对新鲜签名隐藏自建项；只读结果不足证明完整顺序时停止，不能进入动作。预留helper崩溃隔离收据。无第三方移动、无新权限。
2. **唯一隐藏目标动作阶段**：完整身份/拓扑/输入覆盖/右槽容量通过并先落隐藏事务prepared后，才允许一次目标定向迁移；两次正面ordered/list/owner visibility确认后才能打开菜单。没有空间或无法命中便停止，禁止坐标重试/补点/自动fallback复刻Ice。
3. **回藏及失败阶段**：menu闭合证据、当前拓扑与lease通过→persist restorePrepared→一次归位；两次原序/几何/原隐藏状态证明→persist restored→清日志确认。取消与失败同样保留责任；Space、owner重启、用户重排或权限失效时不做猜测归位。

任何一步未通过，正式版、私有backend开关和第三方测试范围不扩展。自建隐藏项是起点验证，不是最终产品范围。

## 验收矩阵

| 情况 | 必须保存的证据 | 成功/拒绝规则 |
| --- | --- | --- |
| 未ordered但逻辑visible的隐藏T/N | 直接item→button→window、PID/start/path/签名/nonce；CG与owner负面 | 认可隐藏起点，绝不能当作可见或仅取AX坐标；目录/拓扑无正证则拒绝动作 |
| 已可见T/N | 公开正面显示事实 | 可作其他测试，但不能替代隐藏→显示验收 |
| 隐藏项移到右槽 | 身份连续、完整参与拓扑、容量、两次ordered/list/owner visibility、安全按钮区域 | 位置变化或事件回执都不足；不能挤掉其他项 |
| 菜单打开/关闭 | 自建菜单delegate或其他明确归属/生命周期观测 | AX accepted不等于opened；unknown/open绝不开始回藏 |
| 原始隐藏归位/用户cancel | 原序/双邻接、完整身份集/几何、原隐藏事实两次及日志确认 | 只回附近、只恢复宽度或setter成功均不算归位；用户并发重排保持pending |
| 只写prepared后崩溃 | 磁盘记录与新的可信现场读回 | 可能已有效果，不盲目重发或清除；源连续性丢失不承诺自动回原序 |
| restorePrepared后失联 | 当前原序证明或明确阻断 | 禁止第二次盲目归位；仅观察已归位才能结束 |
| 隐藏静止peer/窗口ID复用/多项同owner | 真成员目录、运行身份与item级区分、完整拓扑来源 | 不按标题或windowID单值识别，不删unknown peer来通过 |
| 输入干预/监听失效/掉线 | 覆盖/连续性、来源事件与epoch变化 | 当前lease永久阻断；回藏动作也须重新合法证明，不假装输入idle |
| Space/显示/缩放/前台变化 | 指定屏身份/尺度、Space来源和允许的阶段迁移 | 失效保留责任；不按旧坐标跨屏/跨Space搬回 |
| 不可移动系统项、MenuExtra/普通多项app | 每种provider的真实对象/支持范围 | 不将自建项结果推广为全部第三方支持；不支持者明确拒绝 |
| 15补丁版/26/Intel | 每build/架构独立ABI、隐藏迁移及恢复故障收据 | 未验证profile禁用，不沿用上一build标志 |

## 许可与分发

仓库现有MIT许可。独立实现可以维持自身许可范围，但需记录设计来源、避免复制/翻译Ice实现；已经阅读源码，不声称clean-room。阅读不等于自动引入GPL，保护表达和组合实现复用须区别。

Ice为GPL-3.0；若直接纳入其移动实现并分发组合成果，不能继续把组合体仅声明MIT，需要按GPL保留通知、提供对应源码及构建资料等，原MIT部分通知仍保留。仅自用研究与向用户分发是不同阶段。GPL允许商业分发，不意味着没有这些义务。[Ice LICENSE](https://github.com/jordanbaird/Ice/blob/11edd39115f3f43a83ae114b5348df6a0e1741cf/LICENSE)。

helper是崩溃/ABI边界，不是许可豁免。FSF解释：进程通信的形式和语义共同决定是否为组合程序；深度交换内部结构仍可能构成整体。不能把GPL代码装进XPC后宣称主程序一定免GPL。[GNU FAQ](https://www.gnu.org/licenses/gpl-faq.en.html#MereAggregation)。

Hidden为MIT，但此前检查的notch overflow只做AXPress，没有隐藏项物理迁移/归位；其OS27私有assessment框架也不能解决本机15。宽度隐藏机制不在本轮备选路线。Thaw同为GPL，当前最低26+，不能作为低成本15组件直接采用。

私有路线不符合Mac App Store仅公开API要求，[Apple 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements)。如将来直发，需要独立处理Developer ID/Hardened Runtime/公证；本地现有Apple Development签名不是对外公证证书，公证也不是App Review或隐藏迁移兼容保证。[Apple公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。本轮未签名/安装新应用或触发分发。

## 本轮结果

原型9案例和SDK静态审计通过；只改Tools/文档，生产驱动、旧模型/持久化/输入接口守卫保留。无新的live、API preflight、鼠标、私有调用、权限或正式动作。读取源码/发布/许可证时的网络失败已记账；没有按失败源推断26内部实现。

[证据、源码核对与检查点](evidence/menu-bar-hidden-target-routes-2026-10-03/README.md)。隐藏目标实际移动、打开/关闭菜单、回藏及取消仍未验证；正式保留12:57:51Z最新只读身份/哈希收据，本轮未重采样。未提交或安装。
