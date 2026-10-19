# Codex Rescue Kit v0.2.0-beta

**Experimental / Beta — GitHub Pre-release，非生产级稳定工具。真实 Windows Task Scheduler、HKCU Run、Startup COM 写入，以及官方 GUI/OAuth/模型/工具和真实重启验收仍为 NOT_TESTED。错误归属、进程强停或不完整备份可能损害使用状态；请先读完整计划与下列限制。**

默认 `rescue.cmd` 只运行 Diagnose。显式选择并批准修复计划后，本 Beta 可以执行完整 Home 校验备份、确证启动入口禁用、精确进程停写、冲突配置隔离、逐项 Skills 恢复、官方登录人工引导、Resume/Verify 和安全 Undo，不是只输出报告的诊断器。保留 [v0.1.0-preview.1](https://github.com/Tkkdy/codex-rescue-kit/releases/tag/v0.1.0-preview.1)。

## 下载与使用

从 [v0.2.0-beta Release](https://github.com/Tkkdy/codex-rescue-kit/releases/tag/v0.2.0-beta) 下载 `codex-rescue-kit-v0.2.0-beta-source.zip` 和 `.sha256`，核对 SHA-256 后解压。需要 Windows 11 x64、本地固定 NTFS、普通非管理员独立 PowerShell；不要求安装额外依赖，不绕过执行策略。

```powershell
Get-FileHash .\codex-rescue-kit-v0.2.0-beta-source.zip -Algorithm SHA256
.\rescue.cmd
# 以下命令只创建/展示计划，直到本人审阅影响范围并确认完整批准哈希。
.\rescue.cmd -Mode Repair -Interactive -Channel C -CodexHome 'C:\RescueTarget\.codex' -OutputDirectory 'C:\RescuePrivate\new-unique-run'
```

示例路径不是对当前电脑的操作授权。请在独立 PowerShell 中对明确目标运行，先关闭目标 Codex。中文向导展示文件/启动项/进程/备份与不可撤销风险；强停需逐进程额外批准。脚本调用也必须先生成私有计划、审阅再给完整哈希。

- [完整使用指南：多 writer、Backup、Resume、Skills 与 Undo](docs/REAL-REPAIR-v02.md)
- [Beta Release Notes 与已知风险](docs/BETA-RELEASE-NOTES.md)
- [验证结果与组合证据边界](docs/REAL-REPAIR-VALIDATION.md) · [独立补丁复审](docs/REAL-REPAIR-REVIEW.md)
- [手工验收与威胁模型](docs/REAL-REPAIR-ACCEPTANCE.md) · [安全报告](SECURITY.md)

## 必须保留的停止条件

- 备份不完整/源变化/校验失败、目标归属不明确、PID漂移、配置冲突或Undo材料不足时停止，不跳过。内存与外部登录/Store操作不可Undo。
- 当前 Home 与 Output 必须同卷；不支持 C: Home → D: 备份。不能满足空间/同卷条件时停止。
- Home 外项目只有盘点，无已验证的备份支持；提供外部 `ProjectRoots` 会显示 `PLAN_SCOPE_BLOCKED` 并阻止修复。未提供外部项目也不意味着它们已经备份。
- 复杂启动命令/wrapper与未确认来源保持“未分析”，不声称所有接管源都已清除。没有证据不按名字/端口批量处理。
- 不删除/重写历史 SQLite，不批量改旧会话 provider，不覆盖项目/Git/Worktree或同名 Skills；新官方 config/auth 会阻止Undo覆盖。备份含敏感内容，必须私下保存，不上传 Issues。

## 验证意味着什么

基础为 `b09b171`。独立补丁复审 PASS；两引擎各新增7项、受影响v02流程25项为组合通过证据（PS5.1 CLI曾失败，编码修正后单项复验；原失败保留），旧69项按范围复用。合成双writer复活、备份/隔离/60秒观察/Undo已验证；真实启动API、GUI/本人OAuth/新模型/原项目真实工具/重启仍NOT_TESTED。未要求完整VM矩阵作为本Beta发行门禁，亦不宣称已完成真实救援。

目标是保全历史与项目并恢复官方新会话使用。旧会话可读但不能续聊属于已知兼容限制，不单独判整体修复失败。最终可用性须由使用者核对真实GUI、模型、工具与重启。

MIT — Copyright (c) 2026 Tkkdy。仅发布有权授权的原创实现；不包含客户事故脚本、私人会话、凭据或备份。本项目不属于OpenAI，不获其背书或修复保证。
