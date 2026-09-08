# 开源检查（2026-09-09）

## 结论

可以准备以 MIT 发布源码，未发现明确的第三方开源许可冲突或常见凭据模式；不是“零风险”证明，也不是法律意见。公开完整 Git 历史前，请确认接受以下个人信息公开。当前没有配置 Git remote，本次不推送。

## 检查范围与证据

检查 Package.swift、全部应用源码、构建脚本、README、已跟踪文件清单、提交身份，以及所有本地 refs 可达的 31 个 Git blob。扫描只覆盖常见私钥、GitHub/OpenAI/AWS 密钥和凭据赋值模式，未覆盖不可达对象、远端、完整二进制取证或未知凭据格式。扫描结果见 OPEN-SOURCE-SCAN.json：0 个模式命中。不把启发式扫描当作无秘密保证。

### 发布前需确认：个人信息

- 全部现有提交署名包含 Ryan.AI 和用户指定的 Gmail 邮箱。
- docs/TEST-OUTPUT.txt 与 docs/tray-transaction/VERIFICATION.txt（含历史版本）包含本机用户名和绝对路径；验证日志还包含进程号、测试时间等开发环境信息。
- 若不希望公开，应在公开前脱敏并另行决定是否改写历史；仅删除当前文件无法清理 Git 历史。本次未擅自删除证据或改写提交。

### 许可与素材

- 已添加标准 MIT 文本，年份 2026、权利人 Ryan.AI。MIT 允许商业使用、修改和再分发，要求保留版权和许可通知，并有免责条款。源码及二进制发行均应随附 LICENSE。
- Package.swift 没有第三方包依赖，未发现 vendor 源码或捆绑第三方库。使用 Apple 系统框架，不代表将 Apple 框架、SDK 或系统符号重新许可为 MIT。
- 当前扳手 PNG/ICNS 为本任务通过 OpenAI 图像工具生成，ICNS 由 macOS sips/iconutil 转换。没有使用用户提供的第三方参考图。相关可授权权利纳入 MIT，但不能保证版权成立、图案独占或不涉及他人权利；未做商标或反向图片检索，正式品牌注册需另行审查。

### 源码开源与 App Store 发布是两回事

- Hardware.apply 动态加载私有 DisplayServicesSetBrightness。Apple 审核指南 2.5.1 要求公共 API；现状存在明确 App Store 审核障碍及系统更新兼容风险。不能将“可发布源码”理解为“可上架”。未发现将 Apple 私有框架二进制打包进仓库。
- 构建产物为本机架构、ad-hoc 签名，未做 Developer ID 签名、公证和跨机器验证；不能当作已经可正式分发的发行版。
- 构建脚本尚未把 LICENSE 复制到 .app 内；分发二进制时务必将 LICENSE 放在发行包中。

### 产品与验收风险（不阻止发布实验性源码）

- 真实设备兼容和窗口快捷键端到端验收尚不完整，应标为早期版本，不宣传已全面验证。
- 音量百分比不是声压；18% 保护不能保证听力安全。亮度允许 0%，公开说明应提醒用户可能变黑。
- UserDefaults 配置载入错误后仍允许保存新列表，可能覆盖原始坏数据；应作为后续可靠性修复项，不宣称可靠备份。
- README 保留历史阶段说明，有旧的“启动不弹窗”描述，后文已注明更新替代；正式对外整理时建议合并为唯一当前说明。

## 官方来源

- MIT 标准文本：https://opensource.org/license/mit
- Apple App Review Guidelines 2.5.1：https://developer.apple.com/app-store/review/guidelines/
- OpenAI 输出权利及非唯一性说明：https://openai.com/policies/terms-of-use/

协议许可不等于对第三方权利、商标或各法域 AI 版权问题的法律保证。

## 本次验证

Test Case '-[MacToolsTests.Checks testWindowShortcutPersistenceAndConflict]' started.
Test Case '-[MacToolsTests.Checks testWindowShortcutPersistenceAndConflict]' passed (0.002 seconds).
Test Suite 'Checks' passed at 2026-09-09 01:26:33.417.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.045 (0.046) seconds
Test Suite 'MacToolsPackageTests.xctest' passed at 2026-09-09 01:26:33.417.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.045 (0.046) seconds
Test Suite 'All tests' passed at 2026-09-09 01:26:33.417.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.045 (0.047) seconds
◇ Test run started.
↳ Testing Library Version: 1501
↳ Target Platform: arm64e-apple-macos14.0
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
