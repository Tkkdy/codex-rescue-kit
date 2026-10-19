# Codex Rescue Kit — v0.1.0-preview.1

**公开源码预览版 / Public source preview. 非正式修复发行版。**

一个面向 Windows Codex 的独立诊断工具，包含 PowerShell Kit、`codex-rescue` Skill、合成测试与可审计的事务恢复原型。
本项目源自真实故障救援经验，但**不保证能修好任何具体 Codex 故障**，也不是 OpenAI 官方产品。

## 最简单的使用方法

1. 从可信来源取得完整源码 ZIP，解压到你自己的 Windows 本地目录（例如 `C:\RescueKit`）。
2. 在解压目录双击 `rescue.cmd`。默认仅执行 Diagnose；不修改 Codex 配置、认证、Skills、任务或注册表。
3. 查看新建的报告目录中的 `report.zh-CN.md` 和 `report.json`，**分享前手动审阅隐私元数据**。

也可在普通 PowerShell 内运行：

```powershell
.\rescue.cmd
# 已知正确 CODEX_HOME 时，指定它与独立的报告目录：
.\rescue.cmd -Mode Diagnose -CodexHome "C:\Example\.codex" -OutputDirectory "C:\RescueReports\example"
```

PowerShell 的执行策略若阻止运行，请遵守本机策略，不建议绕过。建议 Windows 11 x64、本地 NTFS、普通用户环境；尚未完成跨 Windows 真实功能兼容验收。

## Preview 的功能边界

| 功能 | 本预览版状态 |
|---|---|
| Diagnose | 提供只读目标诊断；会向指定目录写入报告 |
| Plan / Dry-run | 提供归属分析与模拟预览；不会实际移除 Windows 自启项 |
| CheckBackup | 校验所提供逐文件哈希清单；不能证明可还原 |
| Verify / ToolProbe | 实验性证据框架；明确要求用户主动选择受控 canary 路径、外部 B/C 来源核对，不能当作官方功能认证 |
| **Quarantine 实际隔离** | **真实 Windows 禁用：`PREVIEW_REAL_MUTATION_DISABLED`** |
| **Undo 实际恢复** | **真实 Windows 禁用：`PREVIEW_REAL_MUTATION_DISABLED`** |
| 合成 Fixture 测试 | 保留，可在测试目录运行，不是实机兼容证明 |

系统级隔离/恢复实现仍以可读源码公开，仅供独立审查；**不能在本预览版中直接作为可靠修复功能使用**。除默认 Diagnose 外，不推荐非技术用户运行其他操作。修改源代码绕过保护者自行承担风险。

## 验证情况与缺口

基础提交 `e7ce4f5bf7ce75a2039b7036cc5c1a9356ad24af`：开发侧 PowerShell 5.1/7 各 62 个合成基线测试，加各 8 个定向补丁测试；经独立静态/证据复审后结论是 `REVIEW_PASS_RELEASE_BLOCKED`。
上述历史证据不代表 Preview 新验证。本次 Windows PowerShell 5.1.26100.9711 / PowerShell 7.6.5 各完成 73/73 合成回归，包含 4 项新增门禁用例；各引擎 Quarantine/Undo 的真实入口均返回 BLOCKED / PREVIEW_REAL_MUTATION_DISABLED / exit 3。静态检查、虚构 Home 默认入口与 Skill 结构校验通过。见 [Preview 验证边界](docs/PREVIEW-VALIDATION.md)。
真实 Task Scheduler、HKCU Run、Startup COM、Journal/Undo 恢复及真实 A/B/C 与 Sandbox 边界仍 **NOT_TESTED**。

`evidence/` 顶层是基础提交的历史文本捕获；新验证在 `evidence/preview1/`，两者分开关联。完整活跃 Codex 数据目录未作前后不变性验收，不将入口阻断或合成成功称为真实修复成功。
参见 [预览说明](docs/PREVIEW-PUBLICATION.md)、[安全限制](docs/SECURITY.md)、[已知限制](docs/KNOWN-LIMITATIONS.md) 和 [Skill](skills/codex-rescue/SKILL.md)。

## 开源许可与责任

本仓库保留原始候选采用的 [MIT 许可证](LICENSE) 和 [第三方说明](THIRD_PARTY_NOTICES.md)，允许商业使用。公开前应由权利人确认可授权的原创内容、Copyright 署名与安全联系渠道；不能把客户事故文件当作授权材料。

本包不包含历史救援日志、客户备份、认证材料、真实私人配置或原始 Git bundle。没有联网遥测或自动更新器。使用前阅读安全说明；报告只经过字段白名单过滤，**并不保证绝对没有敏感信息**。
