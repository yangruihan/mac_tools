# MacTools 0.2.1（5）本机整合验收

2026-10-08，按用户“记住当前mactools的版本号，帮我直接整合进来我来验收”授权，已替换并正常启动 `/Applications/MacTools.app`。原版实核 **0.2.0（4）**，Bundle ID `com.ryanai.mactools`，签名 Team `58TJ64422P`，二进制 SHA256 `51e82865043c50b09fdee6883eb0a74096db8b865f393bf1d6b408cbe14b7c81`；旧包未保存源码提交，不能把当前HEAD冒称旧包来源。旧完整应用、设置及自身Application Support已备份。

安装后发现旧辅助器仍锁定0.2.0哈希，已修为显式版本基线绑定；工作端manifest标为v3.7.1，只有辅助器及构建脚本变化，原生控制端和fixture二进制SHA保持。最终安装路径预检已独立通过，错误哈希／版本不会自动重基线。

新版 **0.2.1（5）** 保留相同Bundle ID、开发者签名和hardened runtime，二进制 SHA256 `515c9640ea01039d0157a57cae81893547cfac04b404b6ce41086461bfbce9a2`。构建来自分支 `feat/menu-bar-reliable-activation` 的HEAD `167771fe00e26d8688bfa4fe372fe10baf09de95` 加保留的未提交改动，未创建提交。签名、最终安装路径组件预检、23项Swift相关回归、3项辅助器版本绑定拒绝回归及五插件自有界面渲染通过；正常启动PID74193、主窗口及自身状态窗口已用公开元数据确认。

## 现在可验收

1. 打开MacTools，选左侧“菜单栏收纳”。原有其他四个插件及设置继续保留；“原有收纳设置”可展开。
2. 点“打开 T/N 测试窗口”。此动作核验组件与恢复责任，创建一次新会话，仅打开自建测试项及控制窗口；尚不发送鼠标事件。
3. 在控制窗口点“开始自建 T 单轮”。当前Ice mouse tracking契约不依赖严格ANY门禁；搬出T、打开并关闭自有菜单、等待15秒、归位。需要停止时点该控制窗口“取消本轮”。产品页“检查结果”及“查看证据”读取这一轮真实结果。

测试会影响焦点和光标。关闭产品窗口不等于取消独立工作端。取消或失败保留未消除的恢复责任，不补发、不清记录重试；保留必要的身份、共有stop和归位保护。每个产品页实例只准备一次会话。

此次整合没有代用户运行新T/N轮，也没有移动或点击第三方图标，没有申请新权限或更改系统安全设置。已通过的T/N14投递是原v3.7/B969A05A工作端现场，当前绑定同一原生工作端SHA，辅助器／manifest已按升级另标v3.7.1；它不是新版本从产品按钮执行的现场回执。新产品按钮到终态由本次用户验收提供。

## 普通图标与下一次指定目标验证

“刷新图标列表”只用已有Ice只读API及公开CG窗口元数据，无截图或AX操作。本机单屏目录已读取24项。选择具体应用名和窗口ID后，重新读取并绑定真实PID、启动时间、可执行路径、签名SHA、windowID、display/Space及原始frame；应用重启、兄弟窗口替换或Space变化不自动重匹配。标签及窗口ID帮助选择，不能单凭标签授权。

普通应用菜单的用户关闭观察及离线状态处理已接入代码：先看到属于目标owner的popup，再连续两份至少100ms相隔的新鲜消失观察才成立；重开清除关闭证明，未知/身份丢失/取消永久停止。不会向第三方发送自有fixture的关闭RPC；没有popup证据的panel/popover仍是未知。

**普通图标实际搬移运输和恢复journal尚未接入此入口，因此选择后不会自动搬移。** 下一单次方案：由用户明确指定一个列表项并授权该图标；接通绑定此目标的运输/恢复记录后，仅一次临时搬出、打开菜单、用户正常关闭、核验关闭后按Ice等待并归位，失败/取消保留责任。没有现在自动执行或把离线状态测试当作普通目标现场通过。

范围仍限本机单屏。本机试用依赖现有仓库、Python及 `/tmp/mac-tools-ice-baseline-candidate-20261007`；重启清理或组件改变后可能需要重建，不是可迁移安装包。原2px变化发生在归位通过后的清理等待期，因果尚未确定，不用补偿第三方或放宽原位断言消差。

## 回滚与重建

旧包及设置：[rollback目录](evidence/menu-bar-ice-integrated-install-2026-10-08/rollback)。先在测试控制端取消/结束并等待退出；确认无未恢复责任后，按该目录的 `rollback.py` 恢复旧包与偏好。脚本保留所有恢复记录，不恢复旧Application Support来覆盖新责任；回滚未执行。

```sh
MAC_TOOLS_ICE_INTEGRATED=1 sh scripts/build-ice-product-candidate.sh
```

此构建不安装、不启动现场。安装后以已审阅最终二进制SHA显式执行 `python3 scripts/bind-ice-worker-to-installed-host.py --approved-sha256 <SHA>`，不自动接受任意后续变化。重建工作端时须显式设置 `MAC_TOOLS_APPROVED_HOST_SHA=<已审阅安装SHA>`。安装替换属于本次已执行的明确授权范围。

[旧版精确基线](evidence/menu-bar-ice-integrated-install-2026-10-08/old-version-baseline.json)，[新版部署回执](evidence/menu-bar-ice-integrated-install-2026-10-08/installed-version.json)，[验证与保全记录](evidence/menu-bar-ice-integrated-install-2026-10-08/README.md)。
