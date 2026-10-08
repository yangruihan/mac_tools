# MacTools 0.2.1（5）整合安装验收交付

2026-10-08。按 `authorization.json` 的后续明确安装授权执行，取代此前“不安装／正式版不变”的任务边界。最终 `/Applications/MacTools.app` 0.2.1(5)、Bundle ID `com.ryanai.mactools`、Team `58TJ64422P`、hardened runtime，正常运行PID74193。最终二进制SHA256：`515c9640ea01039d0157a57cae81893547cfac04b404b6ce41086461bfbce9a2`。

旧版先实核并备份：0.2.0(4)、displayName `MacTools AX-only Preview`、同Bundle ID/Team、SHA256 `51e82865043c50b09fdee6883eb0a74096db8b865f393bf1d6b408cbe14b7c81`。`old-version-baseline.json` 含签名、完整包哈希及可回滚路径，`rollback/` 保存原包、应用自身偏好和相关Application Support。旧包没有源码提交标识，未知；当前仓库HEAD不可冒称旧包来源。新包来自HEAD167771fe及未提交工作树，94份来源见 `source-at-delivery/` 和 `source-hashes.json`。未提交代码。

## 实现与证据

* `MenuBarIceCandidateProduct.swift` 的原独立T/N入口可在整合构建中使用；五插件保留，默认打开菜单栏收纳，原有收纳设置折叠保留。Normal start保留原插件及快捷键。`ui-delivery.json` 与 `delivery-ui.png` 为最终二进制的自有View渲染，五插件及按钮、只读选择和原有设置已查看；该检查独立设置域、禁止Start，不宣称AX语义读回成功。
* `MenuBarIceSelectedTarget.swift` 为普通应用新增单屏只读目录、精确窗口/PID/启动/签名/display/Space/frame绑定，以及用户关闭菜单的popup观察状态与公开只读采样器。无外国NSStatusItem UUID伪造、无兄弟／重启重匹配、无第三方关闭RPC。只读实际24项在 `ordinary-directory.json`，界面支持选择具体窗口ID并复核身份。普通原生运输和durable责任接入尚未实现，选择不移动图标。
* `regression-delivery.log`：23项Swift回归通过（原插件相关16、新绑定/关闭7）。初始初始化访问级别编译失败及修复日志保留；布局调整后的回归为最终检查。旧native worker的313离线及T/N现场14post保留原v3.7标签，未重跑正常fixture轮。
* 0.2.1初次安装后发现旧helper硬编码正式版0.2.0SHA，真实安装路径预检失败。修复为显式发行绑定：`scripts/bind-ice-worker-to-installed-host.py` 必须传入已审阅当前SHA，验证Bundle ID/version/build/签名Team、完整来源、两工作端binary及无当前恢复责任/运行helper；封存旧manifest后更新基线。运行预检不自动重绑定。`host-binding-tests.log` 的3拒绝回归确认变更SHA、错误version和错误显式SHA不能接受。修复前包SHA430001b0及回执保留；最终包SHA515c9640，不能混用初次交付数据。
* 最终工作端manifest版本 `isolated-Ice-0.11.12-baseline-v3.7.1-authorized-host-binding`。41项中39保持，变化仅helper及重建脚本；控制端SHA `93dc00b3c38bfb33917fe4aeaf9ed8a8f5275904525c3c8d92512d4bcafc96d6`、fixtureSHA `ab310760705869ec38908eb5d15c99aeff7c5cbdd89fd7eb908a0ae13c5181fc`及全部原生运输/目标/取消/归位代码保持。严格ANY仍仅诊断，不恢复为默认门禁。
* `host-bind-final.json`、`runtime-worker-manifest.json` 绑定最终安装SHA；`preflight-installed.json` 和独立 `preflight-installed-independent.json` 从 `/Applications` 实际二进制通过，journalPending=false。App资源的prepared-build是签名前来源快照，运行使用已显式绑定的外部manifest；它不能承载依赖自身签名的最终hostSHA，两者职责分别记录。
* `deploy.py`、`termination.json`、`normal-launch.json`、`installed-version.json`、`signature-installed-final.txt`记录精确路径正常退出、替换签名、绑定预检及正常启动；公开窗口元数据确认最终主窗口。最后 `preferences-after-final.plist` 与旧偏好内容完全一致，原插件/快捷键保全。

## 保全及验收边界

`preservation-final.json`：27个旧冻结根10351文件保持；144基线生产中141保持，三份既有主应用入口文件为明确整合改动；六份原政策保持。新增helper/build来源变化是正式安装授权后的版本绑定修复，未放宽fixture身份或归位断言。最终 `hashes.json` 覆盖本根交付文件。

本轮新原生post0、新T/N会话0、第三方目标动作0、新权限请求0、系统安全设置改动0。只读UI检查创建主应用测试窗口；部署按授权创建正常主应用窗口和原有自身状态项。T/N的产品按钮到新终态交由用户验收；既有B969A05A14投递不能冒称新产品现场。普通实际搬移/backend未开启，下一次需完成目标绑定的运输/journal接入并由用户指定一个图标，执行单次搬出/menu/用户正常关闭/归位。未知菜单或恢复责任不猜测成功。

仍限本机单屏，依赖现有仓库、Python、固定/tmp工作端，非便携发行包。2px变化触发原因仍未确定，不影响已经发生的原严格归位证明，也不宣称永远绝对坐标不重排。没有新增第三方补偿或重复相关现场。

[当前使用与回滚说明](../../MENUBAR_ICE_INSTALLED_ACCEPTANCE.md)。回滚脚本仅预备，未执行；必须先结束自己的T/N会话并处理现存责任，保留所有journal，不以旧Application Support覆盖新责任。
