> 历史 V0.1 / Preview 文档。v0.2 当前操作与权限以 [真实修复说明](REAL-REPAIR-v02.md) 和 [收敛验收](REAL-REPAIR-ACCEPTANCE.md) 为准；以下旧证据仅适用于其绑定版本。

# v0.1.0-preview.1 — 公开源码预览说明

## 目的与安全范围

此预览从源码基线 `e7ce4f5bf7ce75a2039b7036cc5c1a9356ad24af` 派生；没有改动基础候选原件与 Git 历史。
只将公开的默认使用场景限定到 Diagnose（和高级用户主动运行的报告校验 / 分通道证据测试）。

真实 Windows 上 `Quarantine`、`Undo` 默认走双层保护：

1. `kit/Rescue.ps1` 在入口拒绝未使用 FixtureRoot 的实际写操作，返回状态 `BLOCKED`、code `PREVIEW_REAL_MUTATION_DISABLED`、退出码 3；
2. `kit/Modules/Quarantine.ps1` 的隔离与恢复函数在 `Context.fixture=false` 时再次拒绝实际修改。Synthetic FixtureRoot 必须经过 `New-RescueContext` 的 marker/路径验证。

`Plan`/`-DryRun` 允许审阅候选对象；**不会自动执行实际隔离或回滚**。发布的源码是可编辑源码，上述保护并不防范用户自己修改源文件的行为，也不等同于系统级沙盒。

**注意：Verify/ToolProbe 可以创建受控测试文件、会话与报告。它们不是零文件写入或真实来源的自动认证。**

## 测试事实与未测试项

- 基线合成：开发侧 PS5.1 / PS7 各 62 项通过，绑定旧提交 `6a39c247`；补丁 PS5.1 / PS7 各 8 项通过，绑定 `e7ce4f5`。
- 独立静态代码复审 `REVIEW_PASS_RELEASE_BLOCKED`；不能声称真实 Windows 的 Quarantine/Undo 已验收。
- 本轮已在 Windows PowerShell 5.1.26100.9711 / PowerShell 7.6.5 执行入口拒绝检查，各自合成回归 73/73（含 4 项 Preview 专属用例），静态及合成默认 Diagnose 入口检查通过。仅认证本轮观测范围；完整活跃 Codex 数据目录未作前后不变性验收。详见 [验证边界](PREVIEW-VALIDATION.md)。
- Task Scheduler、HKCU Run、Startup COM、真实 A/B/C 来源、沙盒边界仍为 NOT_TESTED。
- `evidence/current-source-manifest.json` 与 `tools/Test-CandidateEvidence.ps1` 属于冻结的 e7ce 基线证据；由于本预览变更代码哈希，该校验器不能拿来证明新预览通过。必须以新预览代码的独立测试/新 manifest 为准。

## 发布纪律

1. 确认 MIT Copyright 主体与原创权利、项目维护者/安全联系方式；无授权原始客户资料一律不公开。
2. 不把本预览版标注为 production-ready、verified fix 或 one-click safe repair。
3. GitHub 仓库可公开代码，但不要公开私人接力包、完整事故审计 ZIP、原始 Git bundle、私密日志或用户配置。
4. 若将来恢复 Quarantine/Undo 实际功能，必须由独立版本开发、明确标注变更、真实 Windows 适配器测试与专门复审；不能仅删除预览闸门。
5. 不自动推送到 GitHub，也不代表用户同意未来所有版本公开发布。
