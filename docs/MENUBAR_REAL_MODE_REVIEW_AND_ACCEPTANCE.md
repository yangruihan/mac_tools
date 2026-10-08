# 真实模式接线及自建 T/N 单轮验收方案

最新共有停止链路加固（2026-10-07，Asia/Shanghai）：已实装操作世代sticky stop，绑定coordinator/input/channel/driver/菜单控制；witness落盘后、100ms回执等待和每项session/PID效果前检查，open后接管不再关闭菜单/归位。停止不等待在途系统调用/I/O，但已准入效果可完成；取消provider限定owner线程。未确认down只保留责任，不自动补发up/换route；实际driver在显式恢复及全部journal clear前核对，原位几何不能消除down责任。两轮独立复核修正锁/closure/恢复问题；493全量Swift、新增19项生产相关注入、真实/诊断配置各66及44Python通过，五个辅助入口typecheck通过。ANY及六个原政策文件保持；旧v15签名候选未重建，原清单因新增源码拒绝混用，不能称新版运行就绪。无新现场/监听/采样/鼠标发送/权限/安装提交，正式版及旧证据保持，backend禁用，真实移动未验收。可用性需要明确选择保留ANY的拒绝限制、另行批准有限观察停止契约或AX/进程内控制降级，不要求重复点击解释ANY。[实际实现、可用性决策及保证](MENUBAR_INPUT_TAKEOVER_AVAILABILITY.md)；[证据](evidence/menu-bar-shared-stop-hardening-2026-10-07/README.md)。

最新输入接管设计审查（2026-10-07，Asia/Shanghai）：公开SDK与Apple文档确认17个命名CGEventType不是全部系统物理输入证明，counter不计自动重复，状态/位置/焦点快照和enabled tap不能消除异步交付竞争。独立复核发现动作channel空keys覆盖声明、witness后/回执等待取消断点、open后直接cancelMenu及失败补发up安全边界。已形成保持ANY的共有sticky stop/逐项串行效果准入方案，以及须独立批准的有限观察停止契约；接管后不自动逆向归位/warp/抢焦点，possibleDown独立评审。15项纯离线检查、24种排列及6个不可保证反例完成；无生产实现或门禁改变、无新现场/监听/采样/发送/权限/安装提交，backend禁用，真实移动未验收。[可审阅方案及保证边界](MENUBAR_INPUT_TAKEOVER_DESIGN_REVIEW.md)。

最新单次分类型背景取样（2026-10-07，Asia/Shanghai）：父代理明确授权无窗口/tap/发送的10秒只读诊断，未要求用户点击或静止。独立signed counter/age-only程序经12项Swift注入、6项Python协议检查后唯一运行4182DAE7/PID10134，正常exit0、无timeout；1671完整向量、实际10.000492250秒、两份11668414字节终态同SHA，进程已回收。any增833，17公开类型（含null）计数增量合373，串行总差460不直接解释为未知事件。更严格稳定配对发现171对any外围/每行稳定且17类型不变、两组间any合增190；其中两个自然up计数更新的邻接片段有额外any+1、age信号较up约晚1.972/3.452ms，mouseMoved/null/up等命名计数未增。支持查询覆盖/计数口径存在可观测差异，但未证明具体事件类型、设备、来源或旧2F48；不能归咎用户或增加释放容差。5项新增配对检查通过，另5个片段的后来活动估计早于前次age读取，提示读取完成不等于状态同步鲜度，未证明缓存实现。当前门禁、v15三候选/100源码/37保护输入、正式0.2.0(4)/PID29904/原SHA、5999旧冻结文件/59基线及30真实session保持；没有新真实窗口/session/Permit/鼠标动作/权限提示、安全设置或安装提交，backend禁用。只读观测已完成，真实移动仍未验收。[原始数据、实际解释边界和保全](evidence/menu-bar-hid-type-counter-observation-2026-10-07/README.md)。

最新未知HID增量诊断（2026-10-07，Asia/Shanghai）：仅用已有2F48原件完成静态与离线核对。107.105208ms是首次发现增量的样本结束时间，不是事件发生时间；714～717四个精确age读取区间的算术交集指向物理up后约2.336584～2.336791ms的一次最新活动信号更新，不能当作已捕获CGEvent/设备时间。counter30092900→30092901持续四个样本，样本内before/after均同值，源码未累加两次API或tap计数；公开counter是累计查询，旧128次独立读取恒定。annotated在Q后tapCount280未增，session只有来源/消费汇总；两路无逐事件类型/CGtimestamp、无分类型HID计数，无法确认尾随指针、媒体/其他未覆盖输入、OS计数/路由/合并或具体来源，不归咎用户。另一真实轮的增量信号在up后约2217ms，不能建立统一释放尾巴容差。门禁保持严格拒绝。已设计一次独立10秒、17公开类型及any的counter/age分类型只读采样，无窗口/tap/发送/权限提示；本轮尚未实装运行，不要求重复点击。6项新离线分析检查通过；v15候选/正式版、5982旧冻结文件和59基线保持，无新现场session。真实移动仍未验收。[可确认边界、计算、补证方案及保全](evidence/menu-bar-hid-delta-analysis-2026-10-07/README.md)。

最新请求回执修复（2026-10-07 UTC）：2F48前序样本711结束于物理up后0.558083ms、回执前0.031417ms，旧物理pre-up锚点对延后同批回调不可靠；仅requestQuiet策略改用严格紧邻回执前驱，完整保留固定250ms历史，并记录公开前序事件类型/时间。首个固定post-receipt样本Q、HID counter/保守age、双fence、250ms静默/固定3秒、新鲜末扫、进程内Permit及v14一次性布局提交均保持；未知或up后活动、overflow/丢失仍拒绝，不加容差、不换晚基线。新ReceiptHistoryV1完整seal和活动时间是原生权限必要条件，preUpContinuity保持。**完整原始后缀另有714样本HID30092900→30092901（up后约107ms），旧锚点错误遮住了它；新回放在实际claim时间仍laterInput拒绝，来源未知。** 仅截至713的原样前缀可离线requestMatched；旧活动时间缺失，不补造为原生授权或静默证明。474全量Swift、107真实配置相关、105诊断配置相关及44Python通过，两个独立诊断入口typecheck通过；v15三辅助完整签名及100/37清单、只读预检通过。5909旧冻结文件/59基线、30旧session及闭合journal保持；无新窗口/fixture/tap/session/鼠标发送，正式0.2.0(4)/PID29904/原SHA保持，backend禁用，无安装提交。软件修复完成，**v15原生运行及真实move/menu/close/restore/cancel仍未验证**；不自动再开实验或要求重复点击。[协议边界、回放、验证和保全](evidence/menu-bar-request-receipt-history-repair-2026-10-07/README.md)。

最新目的控件复查及新授权现场（2026-10-07 UTC）：用户明确“没有全屏，可以测试”。无动作截图/公开CG/AX确认正式恢复按钮PID29904/window314679可见，description及AX中心/完整右安全区通过；0E4历史Space9186与成功历史/本次4634不同，底层可见性变化触发仍未知，未归因为全屏或用户。开测前重新只读核验签名/恢复及同一控件后，仅启动新授权2F48F41E一轮，1060ms准备并发布开始窗口330319，native destination准入通过，收到真实up。Packet各字段、时效及noLaterTapEvent吻合，但Ledger.claim第183行missingPreUpAnchor：up节点712/tapCount280需要279的up前样本，唯一节点711反而结束于物理up后0.558083ms；更早节点709在up前24.111875ms但计数278，不能替代。前序activity类型/物理时间未保存，不归因用户释放后操作。matched/validation0、Permit/交接false，未进入静止/倒计时/v14布局提交，move/menu/close/restore/cancel各自未执行；系统/PID发送0/0、菜单generation0、AX/权限0。两种保留后缀纯离线回放均同因永久停止，无补样或容差。结果窗边界约30.0046秒，worker exit4无信号/超时，双监听关闭，fixture正常quit0，全部辅助退出、无恢复责任/动作消费，正式0.2.0(4)/PID29904/SHA保持。1227原件/8段链、4655旧冻结文件与59基线核验；30会话恢复允许，100/37候选清单未改。未修改控件安全规则/生产源码或重建、安装、提交，未开自动第二轮。当前无需用户继续保持键鼠静止或退出全屏；剩余输入锚点采样时序需先诊断修复。[只读证据、现场覆盖和收尾](evidence/menu-bar-destination-recheck-v14-live-2026-10-07/README.md)。

最新v14唯一现场（2026-10-07 07:25 UTC）：用户回复“准备好了”后立即启动0E4AD5C8一次。fixture签名/nonce/路径/启动、T/N发布和171ms稳定pair通过；随后destination admission在开始窗口构造前拒绝。两次观测27项均未listedOnScreen，正式MacTools三个候选314680/314679/314678的kCGWindowIsOnscreen字段缺失，原可见性条件阻断并短路AX查询。没有run-ready或开始/结果窗口，未等45秒、未收到真实up、未进入静止/倒计时/v14提交或Permit，真实move/menu/close/restore/cancel各自未执行。系统/PID发送0/0，session事件/overflow0，菜单generation0、权限/AX动作0。前台PID91669事后对应Parallels客户端，但隐藏/全屏/系统报告触发未记录，不能归因用户或其他应用。worker exit4无信号/超时，监听已关闭，fixture正常quit0，controller/fixture/supervisor及全部辅助均退出，无journal/消费标记或恢复责任。正式0.2.0(4)/PID29904/原SHA保持，backend禁用；候选源码/签名未改、未安装提交，29会话只读恢复允许。原29文件及5段SHA链、4614旧冻结文件和59基线核验保持，未再开第二轮。下一轮需先保证顶部菜单栏及正式恢复控件持续可见，并仍由原生可见性/AX区域检查确认；本次不是布局提交通过证明。[实际覆盖、停止边界和收尾证据](evidence/menu-bar-v14-layout-live-2026-10-07/README.md)。

最新布局绑定修复（2026-10-07 UTC）：依据9E0冻结时间线，T/N初始异步布局启动后257ms已稳定，controller首次前台仍为677/706；约6.64秒、用户点击之前才变为689/718，快照中的另一同PID菜单项宽44→32。该进程同时前台仅为关联，具体宽度触发未记录，不能归咎标题变化、controller激活或用户。旧计划将约18秒前的准备几何当作动作几何，是本轮可修复的绑定时机缺陷。现在启动准备固定身份/nonce/实例/邻接/顺序/成员/显示器/桌面/可见状态；真实请求匹配并通过原250ms静止后，在原固定3秒倒计时入口仅采集、准入一次稳定新布局并持久记录，随后动作前仍按完整sameFacts精确比较。N实例从首次成功准入固定；任何身份/邻接/状态/环境变化、采样不稳定或不新鲜、输入/监听故障、期限或证据写失败均停止且不重试。没有放宽坐标、HID、全局hit或后续恢复检查，也没有延长/重启时间。9项新增离线、463全量Swift、72真实配置相关及44Python通过，两个无发送诊断入口类型检查通过。v14-countdown-layout三辅助候选完整签名、100/37清单及只读预检通过；4568旧冻结文件、59基线和617原件保持，28会话恢复允许、无辅助残留，动作标记未消费。正式0.2.0(4)/PID29904/原SHA保持，backend禁用，未开新现场、发送、安装或提交。**新版原生布局提交及真实move/menu/close/restore/cancel尚未验证，本轮不自动再开实验。** [根因、修复、验证和下一次单轮条件](evidence/menu-bar-layout-commit-repair-2026-10-07/README.md)。

最新现场及原因展示修复（2026-10-07 UTC）：449项候选后按用户“准备好了”唯一启动9E0D457A，T/N与窗口1168ms就绪。真实AppKit up完整匹配，250ms静止、完整3秒倒计时及新鲜末端验证均通过，validation1/PermitIssued=true；随后动作前checkGateEntry以binding拒绝，handedOff=false。准备快照和新original-plan仅items事实不同：前10项x统一+12px，第9项宽44→32，自有T x677→689、N706→718；scope/owner/成员/顺序/carriers一致。原sameFacts条件必须拒绝；旧代码未细分同码抛出点，不能补造，也不归因上轮HID或用户移动。系统/PID发送0/0、AX/权限0，菜单generation0，无journal或动作消费；移动/菜单/归位各自均未执行。结果窗口显示约16.427秒并关闭，父截图证实generic文字遗漏绑定原因；worker exit4无信号/超时，fixture正常exit0，全部辅助退出，正式0.2.0(4)/PID29904/原SHA保持。[原始617文件、12段链与实际边界](evidence/menu-bar-post-notice-real-live-2026-10-07/README.md)。后续仅修诊断：Terminal新增可选bindingRejection/check/failedFields，分别记录进程身份、输入/计划和请求证明的首个失败；原guard、sameFacts和期限均不改，不重绑定计划。结果窗将计划items变化解释为准备后位置/可见状态变化，旧binding记录明确未细分字段，其他错误显示实际原因，避免generic盲测。5项新增、28项相关、454全量及56真实配置通过，两个无发送入口typecheck通过；100/37辅助候选完整构建签名及只读预检通过，28会话允许。未再开现场/fixture/tap/发送，backend禁用，未安装提交。新版具体原因显示尚未现场验收，真实move/menu/close/restore/cancel仍未通过。[修复及保全证据](evidence/menu-bar-binding-reason-repair-2026-10-07/README.md)。

最新停止提示修复及只读归属分析（2026-10-07 UTC）：继续分析597EB86B，98个post-guard采样中前97个HID计数稳定，最后29803933→29803935且age重置；完整读取81.083µs、age区间583ns、推导活动区间在固定guard后约2.21646秒，全部样本边界有效，最大采样间隔88.908042ms。annotated tapCount189不变、session fence200不变、队列/overflow/timeout/disabled均0。排除记录所示的age读取边界延迟和计数回绕；两处tap选择的公开事件掩码并非完整HID流，健康不能证明全面覆盖，未记录逐类型HID计数，仍不能判定事件类型/来源或排除系统计数异常，不能归咎用户。授权规则不改。真实worker现在先完成原事务/恢复检查、保存终态并关闭双监听，再在原窗口显示原因/发送状态/恢复责任；开始/取消禁用且操作closure清除，仅允许关闭，最多30秒，仍受worker启动后120秒边界限制，125秒supervisor及原45秒/250ms/3秒/5秒规则不变；主动关闭窗口不重开，证据写失败不延迟退出。7项新回归含原真人完整轨迹两种callback顺序仍laterInput；449项全量、51项真实配置通过，共享窗口两个无发送诊断入口typecheck通过。三个辅助候选完整重建签名，100/37清单与只读预检通过，27会话允许、无残留/动作消费；3885旧冻结证据及59基线保持。未开新窗口/fixture/tap、无新发送/权限请求，正式0.2.0(4)保持、backend禁用，未安装提交。停止提示实际显示效果及真实move/menu/close/restore/cancel仍待现场验证，不自动第二轮。[本轮分析、修复与候选证据](evidence/menu-bar-stop-notice-and-hid-analysis-2026-10-07/README.md)。

最新现场（2026-10-07 UTC，HID/队列修复后）：父提前通知后启动唯一轮597EB86B，T/N与窗口1107ms内就绪，真实AppKit up匹配1次，请求和250ms静止检查通过，进入完整3秒倒计时。倒计时1.895559208秒时，第576号sample的HID计数29803933→29803935，age从2.1548585秒重置为0.022811041秒，在Ledger.swift:134触发laterInput；annotated tapCount仍189，没有保留可归属事件，来源/类型未知，不能忽略增量或断言用户移动。历史、采样时间及session队列修复本轮均未重现原故障：保留100节点，等待51批消费191事件，队列0、overflow0；原native计数/年龄检查保持。Permit/交接0、系统/PID发送0/0、菜单generation0，无真实动作消费或恢复责任。worker exit4无超时/信号，fixture正常exit0，全部辅助退出，正式0.2.0(4)/PID29904/原SHA不变，27会话只读恢复后检允许。238份原始文件及8段SHA链已核验，3634份旧冻结证据和59基线不变；未改源码/重建、未开第二轮、未安装提交。真实move/menu/close/restore/cancel仍未通过；本轮没有证据支持放宽检查或新的代码修复。[原始证据、具体边界与收尾](evidence/menu-bar-hid-queue-repaired-live-2026-10-07/README.md)。

最新无动作修复就绪（2026-10-07 UTC）：针对C8F1E081，采样新增age API调用的实际起止时间，仍用该区间的保守末端判定；旧记录没有此时间戳，继续用原整份采样末端，74.708µs原拒绝不改，也不补填数据或加容差。session等待事件按批核对累计eventCount/continuity/epoch后消费，开始前关闭此路径；真实overflow/丢失仍永久停止，故障队列最多保留513条。窗口timer覆盖eventTracking，避免鼠标按钮追踪期间等待消费饥饿。无窗口/fixture/tap/发送的原生取样128次，计数不变，新活动上界波动167ns，旧整段上界波动约19.4ms；健康字段明确false，不构成许可。11项新增测试覆盖五万等待事件、跨阶段和真正溢出、原始拒绝回放及tracking timer；442项全量Swift、57项真实配置、37项诊断配置、44项Python通过。三个工具完整重建签名，只读预检99项源码/36项真实输入匹配，26会话恢复允许、无辅助残留和真实动作消费。正式0.2.0(4)保持，backend禁用，未开真人窗口、安装/提交/push。[设计依据、诊断、回归与就绪证据](evidence/menu-bar-hid-queue-repair-2026-10-07/README.md)。真实授权及move/menu/close/restore/cancel仍待单轮实测。

最新现场（2026-10-07 UTC，历史修复后）：唯一轮C8F1E081的T/N及窗口1146ms内准备通过，真实AppKit up与annotated候选完整吻合。等待前缀退役478节点后仅保留36节点，旧512→513阻断未再出现；随后claimRequest在第2393号sample触发hidActivityUnproven：查询耗时2.315292ms，保守活动上界超过首个post-up Q边界74.708µs。计数29564178未变、无更晚annotated事件，不能断言实际额外输入，也未放宽边界。独立session监听还记录577次queueOverflow、队列1089、terminalCause=queueOverflow。matched/validated/Permit仍0，发送0/0、标记未消费、无恢复责任。worker exit4，fixture正常exit0，辅助进程全部退出，正式版0.2.0(4)保持；26历史会话恢复允许。未再开第二轮、未修改源码/重建或安装提交。[本轮原始样本及收尾](evidence/menu-bar-history-repaired-live-2026-10-07/README.md)。剩余是真实请求阶段保守HID证明和session等待队列容量问题；真实move/menu/close/restore/cancel仍未通过。

最新修复就绪（2026-10-07 UTC）：已修复AF9D4687的等待历史容量缺陷。开始时仅退役早于不可变up前250ms、不能作为合法前置锚点的等待前缀，保留整个必要区间及之后的全部事件；序号、epoch、tapCount、HID计数、receipt和时钟不重设，开始后不再裁剪，必要区间或证明期超过512条仍永久overflow。新增StartHistoryBoundary记录边界，旧证据解码兼容。原真人前缀离线回放仅requestMatched，不冒充原生静止/许可；旧真人HID拒绝仍通过。127项相关、431项全量Swift、46项真实配置、26项诊断配置及44项Python通过；完整重建三个辅助应用并签名，只读预检98项源码/36项真实输入匹配、25会话恢复允许、无辅助残留和动作消费。未打开现场窗口，backend禁用，正式版0.2.0(4)保持，未安装/提交/push。[修复、回归和就绪证据](evidence/menu-bar-start-history-repair-2026-10-07/README.md)。真实move/menu/close/restore/cancel仍待实测；本轮不自动开启下一轮。

最新现场（2026-10-07 UTC）：按父会话提前通知后的明确启动指令打开唯一轮AF9D4687。T/N及窗口1122ms内准备成功；本轮收到真实本地AppKit up及完整吻合的annotated候选，两个监听分别收到347/384事件。但ready期历史已达512节点，进入awaitingReceipt后第866号sample追加至513节点，在Ledger.swift:288触发overflow，matched/validated/Permit均0，未进入静止/倒计时或实际移动。系统/PID发送0/0、真实动作标记未消费、无恢复责任；controller exit4，fixture正常exit0，辅助进程全部退出，正式版0.2.0(4)保持。未重建或修改源码，未再开第二轮。[原始轨迹、准确停止原因及收尾](evidence/menu-bar-real-v13-restart-live-2026-10-07/README.md)。当前25个真实会话恢复后检允许；下一步需修复开始阶段历史容量问题并验证，真实move/menu/close/restore/cancel仍未通过。

最新重试（2026-10-06 UTC）：父会话提前通知窗口/按钮和期限后，按明确启动指令打开唯一一轮617E6B34。T/N和窗口准备1171ms内通过，但仍未记录本地开始事件，ready等待45秒后expired；两个监听事件均0，系统投递0、无许可、动作标记未消费、无恢复责任。controller exit4、fixture正常exit0，全部辅助进程退出，正式版不变，未再开下一轮。原因只能确定为开始事件未到达，不能称HID保护误判或真实移动通过。[本轮原始证据与收尾](evidence/menu-bar-real-v13-retry-live-2026-10-06/README.md)。当前24个真实会话的恢复后检允许，v13源码/签名清单保持。

**此前现场（2026-10-06 UTC）**：v13唯一真实现场轮721AE01F已结束。T/N及窗口准备通过，但45秒内没有本地开始事件，ready直接expired，未进入request/quiet/countdown；系统发送0、真实标记未消费、无恢复责任。controller exit4，fixture正常exit0，全部辅助进程退出，正式版未改；没有第二轮。[原始证据、精确原因及收尾](evidence/menu-bar-real-v13-live-2026-10-06/README.md)。**真实授权及move/menu/close/restore/cancel仍未验证。** 当前23份会话的恢复后检允许，v13源码和签名清单仍匹配。

**此前进展（2026-10-05 UTC）**：真实请求预热已接入独立真实 worker，完整签名版本为 **controller-real-local-v13-request-quiet**。98项源码/36项受保护输入逐项匹配，AX/post/listen只读预检全true；424项全量Swift、39项真实配置、19项诊断配置、44项Python通过。真实worker须以自己的双监听完整证明、同进程身份及一次性许可通过目标/恢复Gate，诊断许可和注入证明不能消费真实标记。本轮没有现场窗口、fixture、监听或鼠标发送，没有新增会话；正式版不变、backend禁用。[本轮工具与证据](evidence/menu-bar-real-request-integration-2026-10-05/README.md)。**真人硬件开始及真实移动/菜单/归位仍未验收。**

此前唯一一次原生无发送实验FEF17D8A通过。核实自有窗口后仅合成点击一次，使用原签名候选完成双监听250ms静止、固定3秒、末端新样本、诊断Permit与共享Gate交接，161节点均为原生记录；worker exit0。按钮事件2、图标事件0，辅助进程全部退出，真实标记未消费。[原生证据与范围](evidence/menu-bar-request-warmup-native-2026-10-05/README.md)。原生Q后未观察到活动；12个基于该轨迹的离线活动反例永久停止，16项Swift与10项Python通过，没有原生第二轮。真人硬件输入及真实搬移仍未通过，生产继续拒绝实验许可，backend禁用。

此前[分界模型与无发送实现](evidence/menu-bar-request-warmup-design-2026-10-05/README.md)将点击仅视为请求，在固定候选边界之后验证完整静止区间。原真人315节点回放仅匹配请求；该轮模拟后缀与本轮完整原生记录明确分开。当时旧真实sender未重建，v12源码清单失配而在启动前拒绝；本轮保留该旧清单/程序归档，完整构建v13并生成新的正确清单，没有忽略哈希检查。

**前次真人轮**：B8FF57E5已结束。T/N与窗口启动发布通过；完整开始up吻合，但HID计数29361010→29361011，准确记录v12 `claim(at:)`第134行`hidChangedAcrossStart`，未进入倒计时，发送0、动作未消费。[现场及收尾](evidence/menu-bar-real-local-user-round-2026-10-05/README.md)。后续离线时间分析支持活动与up吻合，无法唯一归属增量；原生产策略保留拒绝。[原归属分析](evidence/menu-bar-captured-start-attribution-2026-10-05/README.md)。新策略承认此前未授权历史不构成连续性证明，没有替历史补归属，也没有把隔离结果写成真人或移动通过。

此前独立无发送程序的合成5B92F1FA单轮已通过真实窗口/broker/双监听、固定3秒、进程内Permit及交接，143节点。对比旧原始readCount与签名v9源码，旧BED7277D停止位置已定位到首次session fence前，其具体Cause仍未知；不要将该历史缺口套用到最新B8FF57E5。[同路径合成诊断](evidence/menu-bar-real-input-diagnostic-2026-10-05/README.md)。

此前唯一一次无窗口只读观察只有185个健康样本、事件0，不能验证开始链；其时限偏差已离线修复，未重跑。[静止观察记录](evidence/menu-bar-ready-observation-2026-10-05/README.md)。

2026-10-05（Asia/Shanghai）。**07:20 已按新增授权执行一次真实本地现场轮：T/N、窗口发布及搬移准入在1105ms内通过，随后本地输入授权以 `stopped` 拒绝。系统发送0、动作标记未消费、无新恢复责任，已正常收尾；真实移动闭环未通过。** 该版本仅在授权成功时保存本地输入，失败原因明细丢失，不能将启动时的活动分类或推测当作此次具体原因。

[前次真实现场与v10修复](evidence/menu-bar-real-local-live-2026-10-05/README.md)：当时补齐具体停止原因、完整本地输入及关闭监听前终态，保留原检查；133项Swift、25项Python通过，v10完整构建签名及只读后检通过。该轮没有追加现场或代点。正式版保持、backend禁用，无权限改动、安装或提交；旧noMove结果仍不能生成真实Permit。

**前次v11停止证据增强**：[停止路径、可靠落盘与最小只读实验](evidence/menu-bar-local-diagnostic-hardening-2026-10-05/README.md)。该轮140项Swift、31项Python通过，14种停止原因均有隔离收据；启动内部清理前快照、首次停止位置、fence/lease对照和独立备份已补齐，取消文件错误不再被泛化。当时仅准备观察工具，后续单次只读执行结果见上文；该轮没有重开真实现场。

[前次 v9 签名与只读检查](evidence/menu-bar-real-signed-preflight-2026-10-05/README.md)及[原签名身份与权限收据](evidence/menu-bar-real-signed-preflight-2026-10-05/read-only-preflight.json)保留原样；该轮本身没有现场操作。

[前次代码实现证据与差异](evidence/menu-bar-real-local-integration-2026-10-05/README.md)；[前次真实模式审查](evidence/menu-bar-real-mode-review-2026-10-05/README.md)；[既有无移动原生成功](evidence/menu-bar-local-auto-completion-2026-10-05/README.md)。启动/发布已有成功的新会话证据；本轮没有重复启动或坐标试探，也没有把旧粗粒度 window 错误反推为已知具体根因。

## 已完成的代码边界

| 项目 | 实现与失败行为 | 本轮验证范围 |
| --- | --- | --- |
| 真实 T 全局 hit | [OwnedTargetHit](../Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarOwnedTargetHit.swift) 从已认证 PID 的 extras menu bar 取唯一 T，严格核对 owner、AXMenuBarItem、T help、精确 frame。全局中心命中须 CFEqual 同一元素，随后重新读取身份/几何，AX 超时 100ms。容器、其他元素、错 PID、N、重复候选、几何变化均拒绝。 | 注入 AX 读取的正反例；未查询本轮桌面的真实 T。 |
| 发布和 N anchor | [Sampler](../Tools/MenuBarOwnedFixtureSampler.swift) 保留签名、team、实际 SHA、内核启动、路径、nonce、双模型一致和新鲜度检查；原右邻必须为同一 fixture 的 N，instance 有效且不同于 T。菜单点击前再次核对发布和全局 hit。 | 代码审查、入口编译、驱动回归；运行时库存/可见区域仍须满足严格准入。 |
| 本地启动 | [真实窗口](../Tools/MenuBarNativeRealAcceptanceWindow.swift) 只接收本窗口开始按钮的一次 AppKit leftMouseUp；window 对象、windowNumber、按钮范围匹配后复制不可变 CGEvent。无虚拟启动或 JSON 启动入口。独立诊断仅通过编译配置切换文案/能力声明。 | 合成同路径开始与交接通过。最新真人v12完整Packet匹配，但跨开始HID计数增加而拒绝；离线回放重现，真人授权未通过。 |
| 连续性交接 | [RealLocalAuthorization](../Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarRealLocalAuthorization.swift) 的真实worker固定requestQuietReal：精确Packet请求、首个post-up样本Q、双监听核验后的固定250ms静止、两份新样本、完整3秒及末端两份新样本。Q/counter/计时不重设，session continuity/epoch/eventCount连续。 | 两种回调顺序、33种三阶段停止、重扫描/fence空隙、12个原生轨迹离线反例；没有v13现场证明。 |
| 许可与记账 | Authority与连续性策略分开且不可变。真实消费要求nativeRealWorker、native monitor、本进程PID/内核启动/SHA、绑定和完整证明；诊断或注入来源不能升级。coordinator先拒绝待恢复日志、重新读取目标/准入，再检查许可、消费原子的全局/session标记，随后重新核验并武装Gate、持久化handoff才停annotated。 | 真实构建拒绝nil/旧策略/诊断/注入许可；无文件消费、无输入读取；假驱动验证准入/恢复/取消/写失败顺序。 |
| 阶段证据 | [StageRecorder](../Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarMoveStageRecorder.swift) 使用全新 0700 目录、0600 O_EXCL 文件、file/parent fsync、连续序号和 SHA-256 前链。编码或写入错误永久停止后续追加。 | durable/部分写失败测试；returned 和 complete 持久化、最后输入边界通过后才清 journal。 |
| 取消与恢复 | [Coordinator](../Sources/MacTools/Plugins/MenuBarOrganizer/MenuBarHiddenMoveCoordinator.swift) 的正常路径、显式恢复都有 5 秒预算。取消、干预、监听或证据失败保留责任；归位两组观测间须整表同事实，原 N 消失不能回退另一邻项。同步边界处理窗口取消和绑定取消文件。 | 返回末端/落盘中干预、恢复超时/取消、丢失邻项及 Space 改变。 |
| 路由与构建 | prepare --real-local-once 只路由到真实 worker 的 --local-real-once；独立 no-move 仍无发送能力，模式/SHA/ready 互换拒绝，全部入口拒绝远程run-once，旧--wait-once/--run-once不能进入真实worker。--local-only 必须证明真实/fixture 全部编译输入未变；旧清单或真实输入变化要求完整重建。 | Python 模式/清单/收尾测试，no-move 负符号检查。 |
| 本地拒绝证据 | 保留stopped的Cause及首次文件/函数/行号/状态，启动内部stop前保存健康；real-local-ui-terminal在UI清理前冻结原错误、完整ledger及基准/最新fence、handoff尝试。独立local-input-terminal备份在stage失败后仍尝试落盘，编码失败保留原因摘要，首份记录不覆盖。 | 14种Cause、同名不同位置、非ledger错误、写入/编码和清理矩阵；Q后的HID增量仍拒绝，不倒填历史原因。 |

真实 sender 保持完整 Envelope、Int16 编号、同对 down/up 编号一致、逐包唯一 marker、session 精确回执后 PID 投递、100ms 时限和一次消费。收据落盘后重新泵监听并复核回执/健康/期限，不能借磁盘等待跨过干预。紧急释放仅配对自身可能未闭合的 down；证据写失败不阻止既有配对释放责任，也不把释放当恢复成功。没有新增私有 API。

真实worker的开始up仅是请求，不把请求前HID增量唯一归属给点击；pre-up原样留档，不减计数或补写历史。Q固定为第一份post-up样本，Q后的tap、HID计数/年龄变化、按键、修饰键、监听丢失或覆盖缺口永久停止。双监听核验后才固定完整250ms静止期限，随后完整3秒倒计时，均须新的双样本；拒绝后不等待恢复或重置计时。session监听原有HID读取规则未改。此前合成诊断成功仍不等于真人入口或图标操作已通过。

## 持久证据及通过标准

`stages/0001-*.json` 包含 nonce、controllerPID、sequence、previousSHA256 和 base64 原始 JSON payload。result 的 stageCount/stageHeadSHA256 对应最后一项；缺项、错链、错绑定、poisoned 或写入不确定均不得认定完整验收。

| 阶段 | 必须保留的事实 |
| --- | --- |
| 预热 | worker-start、实际 worker-identity、observation-pair、fixture-binding、run-ready、real-local-ui-ready；T/N instance、原序/原帧、carrier、scope、右邻 N、目的地准入诊断。 |
| 授权 | real-local-input 的原生连续记录；real-local-handoff 保存截至交接的完整记录、绑定、session fence、gesture 和时间。当前 Gate continuity/epoch 与 fence 一致。 |
| 本地终态 | real-local-ui-terminal 含具体停止原因和关闭监听前的输入/监听快照；拒绝也必须保存。它不授予Permit，也不替代worker最终投递与恢复结论。 |
| 尝试/发送 | original-plan及最新准入、真实许可检查、全局消费标记/run-consumed/action-consumed、Gate/handoff、prepared；每包 packet-intent、session-receipt、packet-delivered，与独立 dispatch witness 对应。 |
| 移动后 | moved、两份完整库存、global-hit-T、visible-verified；T 在安全可见区域，完整排列及系统自然位移符合预计。 |
| 菜单 | 点击前新的 global-hit-T；menu-opened 两份相同 generation、T itemKey、自有公开菜单窗口；menu-closed 两份 closed generation、cancel ack、菜单窗口消失。 |
| 归位 | restore-prepared；再次验证 T/原 N/全表；returned Record 含两份新返回观测、原序/原帧/原身份/scope。returned、complete 落盘，末端输入/取消/预算复核，再清 journal。 |
| 收尾 | worker-terminal/result.json、supervisor-terminal.json、session-finish.json；正式版 SHA、fixture 普通退出和无残留证据。 |

**新本地真实轮完整通过**须同时满足：startPolicy=requestQuietReal、authority=nativeRealWorker、workerMode=--local-real-once、localStartRequired=true、localStartHandedOff=true、moveMenuRestorePassed=true、passed=true、无 initialFailure、无 stageEvidencePoisoned、emergencyReleases=0、pendingRecovery=false、returnJournalCleared=true，且全部阶段、监督和收尾证据一致。三对鼠标包的双路投递预期 session=6、PID=6；这是方案预期，不是本轮实测，也不能仅凭计数认定通过。

explicitRecoveryPassed=true 只表示失败后的恢复成功，保留 initialFailure、recoveryOnly=true、moveMenuRestorePassed=false、passed=false。未发送中止保存 durable witness/归档，仍为 restored=false。若返回证据落盘后最后输入边界失败，可能保留 phase=restored 的 journal；其存在仍是待处理责任，不能仅看 phase 删除。

## 当前工具与后续入口（本轮仅构建及只读预检）

可用真实工具为 **controller-real-local-v13-request-quiet**，controller SHA256 `748ef09eeaeeca01564f1c14e104d6d41c370151703d05cb2e54c00279c8273c`。三应用、完整98项源码及36项受保护输入见[清单](evidence/menu-bar-real-request-integration-2026-10-05/v13-prepared-build.json)。无需再次构建即可进行下面的只读预检：

```sh
python3 /Users/yangruihan/Workspace/mac_tools/Tools/menu-bar-hidden-driver-session.py preflight
```

该入口已实测通过，只检查源码/二进制/签名、旧恢复分类和AX/post/listen能力，不打开窗口、fixture或监听，不写动作标记。两个旧独立诊断程序及已消费标记原样保留；源码变化使其旧清单过期，不能重跑或拿它们授权真实操作。

后续现场入口已准备，但**本轮没有执行**。它需要新的真实worker运行自己的完整证明，不能使用FEF17D8A或任何JSON/诊断许可：

```sh
python3 /Users/yangruihan/Workspace/mac_tools/Tools/menu-bar-hidden-driver-session.py prepare --real-local-once
```

它会启动新自建 fixture 和真实本地窗口，不会自动点击开始。运行时重新核验源码/二进制/签名、辅助进程及逐 session 恢复分类；真正 pending、错绑/未知证据或活旧 owner 均阻断。历史 closed archive 按精确归档识别，旧 prepared 不改写、不重放、不认定 restored。全局动作标记若存在直接拒绝，不得删除或改名。本轮只读分类覆盖22份旧会话，无新增会话；全部原始现场证据不改写。

仅以后生产/工具源码变化时才需重新完整构建；正确命令包含 `sh`（脚本当前没有执行位）：

```sh
MAC_TOOLS_SIGN_IDENTITY=722852A9656BC9126B2C4585713B724D58F60DB6 \
  sh scripts/build-hidden-move-controller.sh /tmp/mac-tools-hidden-driver-task7
```

该命令仅更新隔离暂存工具，不安装到 /Applications。不要手改旧 SHA 或用 --local-only 认可真实源码变化。

后续新轮也只启动一份新fixture和一个真实窗口，ready有效45秒。初始T必须隐藏、原右邻为自建N，完整库存/显示器/Space/rightSafe稳定，目的地可见且容纳T，已有AX/post/listen权限满足。该窗口的一次开始只匹配请求；先验证固定250ms静止及新样本，再完整倒计时3秒并取末端新样本、同worker真实许可及Gate后才可执行操作链。本轮已结束，无等待窗口，不要求再次点击或改权限，不调用旧无移动点击工具。

隐藏 T 不具备可物理点击的可见按钮；初始搬移依赖已审查的自有窗口身份、原位及可见目的地准入。T 被证明可见后才执行全局 hit；若仍只命中 AXMenuBar，停止并保留恢复责任，禁止换坐标再试。正式项仅作现有目的地参照，不操纵正式项或第三方图标。

取 prepare 输出的 session 路径为 `$SESSION`，按实际阶段选择：

```sh
python3 Tools/menu-bar-hidden-driver-session.py status "$SESSION"
python3 Tools/menu-bar-hidden-driver-session.py cancel "$SESSION"
python3 Tools/menu-bar-hidden-driver-session.py finish "$SESSION"
```

分别用于查看、明确取消和终态收尾。真实本地模式拒绝 run-once SESSION；窗口取消/关闭、绑定取消文件、输入、监听失效、超时或读写失败停止本次操作。没有自动重试或第二轮。消费标记表示一次尝试，即使消费后零发送拒绝也不恢复资格。

若可能发送且无返回证明，status 暴露 restore-control，fixture 保留；worker 最多等候 60 秒的**显式**恢复请求，不自动逆向或退出 fixture。既有协议为原子新建 session 的 restore-request.json，nonce/transaction 取当前 restore-control，action=restore-once。只能在 status 确认同一活 worker/fixture/nonce 和 restorePending 后明确发出；它不重开动作轮次。恢复须重新核验原 owner、scope、N、菜单关闭、新 lease、5 秒预算及完整返回。recorder 已失败、监听已丢失或 worker 已退出时保留日志，不另建会话绕过。

## 最新验证与保全

[v13验证、只读预检与保全](evidence/menu-bar-real-request-integration-2026-10-05/README.md)：424项全量Swift、39项真实配置、19项诊断配置、44项Python通过；四个签名旧入口及两项编译配置冲突拒绝。三个工具完整签名，98项输入零失配；1354项旧冻结证据、59基线、正式0.2.0(4)/PID29904/SHA、22个旧会话和旧prepared不变。真实标记仍不存在，两个诊断标记保留，全部辅助进程退出。没有新现场或真实发送，未安装、提交。

以下为保留的历史验证，不代表当前工具版本。

[此前v11验证結果](evidence/menu-bar-local-diagnostic-hardening-2026-10-05/validation.json)：140项Swift、31项Python通过。原133项之外新增7项Swift测试覆盖14种停止原因、清理后首因保留、启动内部清理前健康、同名拒绝位置、不可编码数据、独立备份故障及broker错误矩阵；另有6项Python只读收据/假worker退出测试。原菜单/逆向可能生效后抛错、各durable阶段不确定和handoff失败矩阵继续通过。

v11与独立只读工具均完整构建签名，源码/实际SHA/strict校验通过；新真实程序只运行--capabilities，AX/post/listen全true、零发送/权限请求。独立只读工具仅wrapper --check，无原生main/tap，且无发送/窗口/AX action/私有窗口API/dlsym导入。no-move仍无发送。真实后台默认禁用，没有第二轮原生窗口或监听。

[保全与只读后检](evidence/menu-bar-real-local-live-2026-10-05/postflight.json)：正式0.2.0(4)/PID29904/原SHA、59基线、254份旧证据和旧prepared保持。新增的唯一BED7277D会话7项阶段前链有效，原目录与归档一致，worker退出4、无信号/超时、fixture普通退出0，三种本轮辅助进程均已无，动作标记仍不存在、无新恢复责任。另一个既有研究程序未触碰。v9三应用和清单在archive-before-real-local-v10-20261005.tar.gz留档，无安装提交。

后续[诊断增强保全](evidence/menu-bar-local-diagnostic-hardening-2026-10-05/postflight.json)继续确认正式版、59基线、589份旧证据及旧prepared不变；没有新真实session或只读观察目录，四个辅助程序均无进程。v10程序已另行留档，新工具只完成构建和只读签名检查。

历史v9缺少具体Cause，不能用后续原因倒填；v12真人轮已准确定位跨开始HID计数变化，FEF17D8A只证明合成开始的原生诊断请求链。v13已完成真实模式实现、离线回归及只读预检，尚未验证真人硬件开始、当前T/N准入或实际move→menu open→close→按N restore及现场取消；不把这些层次合并为真实验收通过。
