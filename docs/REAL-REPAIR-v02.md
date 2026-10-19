# Codex Rescue Kit v0.2.0-beta 操作指南

本候选从完整开发历史 `37a32e0` 建立 `codex/real-repair-v0.2`，冻结补丁 `e7ce4f5` 保留。公开 `v0.1.0-preview.1` 不变。本版本以 GitHub Pre-release / Experimental Beta 发布。真实 Windows Task/Run/Startup 写入、GUI/OAuth/模型/工具和重启尚未验收。只在明确选择的目标和已审阅批准的计划下修复；不要在仍使用中的 Codex 工具进程内操作。

## 核心目标和能力边界

恢复的标准是：历史可打开阅读、资产与项目保全、官方新会话可发消息、原项目中的新会话可运行终端、已确认的接管在观察及手工重启后未复发。旧会话无法续聊只记兼容性限制，不单独导致恢复失败。不写历史 SQLite、provider 字段、内部 API 别名，不默认重装，不追求 Doctor 全绿。

代码确实执行文件备份、精确进程退出、任务禁用/Run 值移除/Startup 同卷移动、config.toml/auth.json 定向移动和逐文件资产恢复。调用不是只打印建议。真实启动适配器沿用事务实现；本次不在现用任务/Run/Startup 上注入样本，其真实 API 写入验收仍 NOT_TESTED。GUI 登录、Store 和必要管理员操作由用户完成。

## 从普通用户的独立 PowerShell 开始

不要从被修复的 Codex 工具内执行修改。使用普通、非管理员、非 sandbox 的 Windows 11 x64 PowerShell；当前版本要求本地固定 NTFS、非域/云管理设备。关闭目标 Codex 客户端。不得改执行策略绕过阻止。

双击 rescue.cmd 默认 Diagnose。中文修复向导：

```powershell
.\rescue.cmd -Mode Repair -Interactive -Channel C -CodexHome 'C:\RescueTarget\.codex' -OutputDirectory 'C:\RescuePrivate\new-unique-run'
```

这些是占位示例，须替换成目标机器上确认的路径，不能照抄为当前用户授权。向导选择症状、确证脚本、冲突文件，生成私有 repair-plan，再要求完整批准哈希。没有批准不执行修复。需强停时每个进程还须单独输入批准码。内存、进程生命周期和外部登录不可 Undo。

也可以在 PowerShell 内使用结构化调用：

```powershell
Import-Module .\kit\Rescue.Core.psm1 -Force -DisableNameChecking
$ctx = New-RescueContext -CodexHome 'C:\RescueTarget\.codex' -OutputDirectory 'C:\RescuePrivate\new-unique-run'
$ctx.channel = 'C'
$p = New-RepairPlan $ctx -WriterScript 'C:\ConfirmedSource\writer.ps1' -ConfigurationFiles @('config.toml','auth.json') -ConfirmTakeover -CaptureStoppedConfiguration
# 打开 $p.plan_path 审阅：路径/身份、文件原状态、进程身份、任务定义、影响范围和不可撤销步骤。
$r = Invoke-Repair $ctx -PlanPath $p.plan_path -ApproveRepairHash $p.approval
```

`ConfirmTakeover` 是本人确认该配置非自愿冲突，工具不凭 provider、名字或端口判恶意。任务/Run/快捷方式只接受完整确证脚本的窄命令语法；复杂 shell wrapper、多 Action、未知父子 runner 需要分对象人工归属，未确认者不自动停止。计划固定显示 unresolved_startup=NOT_ANALYZED...；这不表示所有接管源已排除。默认不按端口范围处理。已关联的进程记录 PID+创建时间+owner+可执行文件及命令行哈希，计划包含关联入口及观察到的监听端口。

如果进程不能正常关闭，安全停止会给出 `FORCE_PROCESS_APPROVAL_REQUIRED:<hash>`。审阅不可回滚风险后，按每个 `$p.processes[*].force_approval` 用 `-ApproveForceProcess @('精确码')` 单独授权；不接受进程名称批量终止。

多 writer 使用 `-WriterScripts @('C:\ConfirmedSource\reviver.ps1','C:\ConfirmedSource\writer.ps1')`，按明确审阅的上游守护优先顺序列出；每个进程仍需独立强停授权。计划 v3 明确授权顺序：全部启动 Undo 快照持久化 → 禁用所有确证入口 → 精确停止进程 → 校验完整 Home 备份 → 隔离配置。旧 v2 计划不能继续执行，须重新审阅；原事务 Undo 仍可用。

持续写入场景可在生成计划时明确选择 `-CaptureStoppedConfiguration`，批准仅对所选 config/auth 在停写后捕获原状态；该私有快照哈希绑定 Journal，并与备份、隔离、Undo 一致使用。默认未选择时继续严格拒绝配置漂移。不要停写后另建计划丢失原启动事务；同一计划 Resume。StopWriter/Backup 模式已会先禁用确证启动入口，只在文件隔离前停下，不能当成纯只读检查。

## 私有备份及范围

默认完整复制明确选择的 Codex home：包含 config、auth、sessions/归档、SQLite/WAL/SHM、attachments、Skills、Rules、AGENTS、MCP/插件及 UI 文件。未知文件也保留；遇到重解析点或读取失败则整体停止，不略过后宣称完整。停止全部已批准进程并确认未见 Codex 客户端后，逐文件锁定读句柄复制，源前后清单、大小、哈希和目标清单都核对。不能保证没有未识别写入者，因此“无已知写入者+哈希复核”不等于数据库干净环境还原证明。

每次备份是新建私有目录；不覆盖旧快照，不用 MIR。新目录创建时保护 ACL，只允许当前身份和 SYSTEM；若现有输出目录权限不合格，拒绝而不修改它。中断副本保留，Resume 新建另一唯一副本。剩余空间、磁盘类型、路径、同卷和重解析点均检查。现有内容校验器每个备份清单上限100,000文件/32MiB；超限安全停止，不声称完成备份。复制前后源变化、内容/清单损坏会阻止后续修改。

备份含 Token 和聊天内容，不上传、不进 Git/候选 ZIP/公开缓存。请加密并离线保存。当前不支持跨卷备份：Home/Output 不同卷时在计划阶段报 REPAIR_REQUIRES_SAME_VOLUME_PRIVATE_RUN；C: 空间不足但 D: 有空间的原事故布局仍不适用，不能宣称完整复刻。

默认不备份 home 外项目/Worktree；`-ProjectRoots` 仅记录显式项目的只读全文件清单哈希、数量及前后比较，**不复制项目**。当前提供外部 ProjectRoots 时，计划明确列出 scope_blockers/unbacked_projects，执行前报 PROJECT_BACKUP_NOT_VERIFIED_PLAN_BLOCKED。没有已验证外置项目备份的实现，不能绕过此阻塞声称项目已备份。项目/.git/Worktree 没有修复写入路径；需要项目灾备须另行明确范围，不声称默认覆盖所有业务数据。清单哈希也不代表 GUI 可读。

## 暂停、官方恢复、Resume

完成备份、启动入口隔离和配置文件移动后，phase 为 AWAITING_OFFICIAL。原件在受限事务目录，原 home 中仅所批准的 config/auth 缺席，Skills/Rules/AGENTS/DB/历史不移动。采用整文件安全隔离、让官方客户端再生成，不用正则改 TOML，不设置模型名/内部 endpoint。

阅读 run/official-step.json。本人打开官方 Codex，走 ChatGPT 登录；只有安装损坏时考虑官方 Store 修复。不要向 Rescue 提供 Token。手工步骤完成后关闭客户端，使用同一输出、计划与批准哈希：

```powershell
$r = Invoke-Repair $ctx -PlanPath $p.plan_path -ApproveRepairHash $p.approval -OfficialStepComplete -StabilitySeconds 60
```

CLI 等价为 `-Mode Resume -PlanPath ... -ApproveRepairHash ... -OfficialStepComplete -Channel C`，还需同一 CodexHome/OutputDirectory。每次重启后都重新审阅使用相同计划，继续修复的计划有效期7天；过期须新审阅计划，不重放过期批准。原事务 Undo 不受此时间限制，但每次仍须明确批准原计划哈希及 ApproveUndo，完整复核身份、Journal、备份和漂移；不能借 Undo 执行新的修复。

至少 60 秒逐秒检查 config 哈希+mtime；观察到稳定仅代表该窗口。检查已批准入口仍处目标状态及确证 writer 未重现。端口只观察原先绑定 PID，不能推出所有代理消失。出现新官方配置/auth 不会被 Resume 再隔离。验证会话和 acceptance 清单绑定 run、计划哈希、时间、home、首次/当前 boot；必须由用户手工重启，开关窗口不算冷启动。

Verify/ToolProbe 沿用原 challenge、真实退出码、canary 与 B/C 来源限制。进入 OBSERVED 仍是 PARTIAL_RECOVERY：GUI/官方模型/真实工具及重启缺证不会自动 PASS。acceptance JSON 是验收卡而不是证明，编辑字段不能把结果升级为 RECOVERED_VERIFIED。

## Skills / Rules / AGENTS 恢复

```powershell
Get-AssetRecoveryCandidates $ctx -Manifest 'C:\AuthorizedBackup\manifest.json' -Payload 'C:\AuthorizedBackup\payload'
$p = New-RepairPlan $ctx -Symptom Assets -RestoreManifest 'C:\AuthorizedBackup\manifest.json' -RestorePayload 'C:\AuthorizedBackup\payload' -AssetPaths @('skills/example/SKILL.md') -ReviewedAssetSources
```

先验证来源 manifest 全覆盖与内容。计数基于该清单和当前 home 的资产文件数，不等同历史 Skill 总数。逐项审阅来源、版本/内容与网络/外发行为；未知来源只列候选，不自动执行。`ReviewedAssetSources` 和完整计划哈希共同确认选中的文件。只复制不存在的文件，任何现有目标都拒绝覆盖。发现/加载/可调用分三层，复制成功只证明发现。

## SandboxGuide

只读采集 error、支持 backend、owner/DACL/SDDL 的私密快照，返回脱敏指纹。mxc/unknown 或不精确匹配一律不给 ACL 修改方案。只有人工审阅的 `rescue-reviewed-owner-rule-v2` 精确绑定 backend、目标相对路径、before owner、完整 SDDL 哈希，且 desired owner 是当前用户 SID 时，才输出单对象 owner-only 人工卡；没有内置通用 takeown 规则。不自动提权，不改 DACL、不递归、不关 sandbox/Defender。管理操作在独立管理员 PowerShell 经额外批准后完成，再采集 ACL 与真实 B 通道结果。无匹配证据则保持 BLOCKED，不阻塞其他模块。

## Undo

```powershell
Undo-Repair $ctx -PlanPath $p.plan_path -ApproveRepairHash $p.approval -ApproveUndo
```

Undo 在任何资产/配置移动前，先检查所有必需启动事务、undo 清单、Journal、目标状态和待还原快捷方式，再检查全部文件冲突；预检缺失或损坏则阻断，不标记 UNDONE。之后处理资产和配置，最后恢复启动入口。若开始实际撤销后再失败，持久记录 UNDO_PARTIAL_CONFLICT，保持可重试。启动事务有独立 Undo 快照，备份失败时可以在无 Home 备份的情况下撤销前置启动变更；不需要伪造一份备份。新官方 config/auth 存在时拒绝覆盖，不恢复旧凭据；需要本人另行保护新文件、决定保留哪套内容后再继续。改变的资产、writer、任务定义、已新建目标、损坏 Journal/备份都拒绝覆盖。资产撤销是移入事务私有区，不删除原文件。进程不会被重启；内存和本人执行的登录/Store/管理员操作不撤销。返回 ROLLBACK_AVAILABLE/UNDONE 只指受管文件和入口已还原。

## 无真实资料的演示

```powershell
.\tests\Run-Tests.ps1 -CaseFilter 'v02 native*' -ResultDirectory 'C:\SyntheticRescueDemo\unique'
.\tests\Run-Tests.ps1 -CaseFilter 'v02 Skills*' -ResultDirectory 'C:\SyntheticSkillsDemo\unique'
```

脚本在独立 fixture 中创建虚构 home/启动对象，第一项启动且真正停止持续改配置的原生子进程，执行备份→隔离→人工卡暂停→Resume/60 秒稳定→Undo；第二项恢复误隔离的虚构 Skill。它们不是目标 Codex 或真实任务/Registry/COM 验收。测试副本和进程只在 fixture 根，保留证据不自动清理。

退出码：0=相应受管步骤完成（如 Undo）；2=旧模块的确定失败；3=待人工/未验证/部分恢复；4=安全停止或输入/环境不满足。不要把单阶段 0 当作全量修复成功。

## Beta 发布边界

基于独立补丁复审通过的 b09b171cb9a0f0c07829cfe54a3236d33281098b，Beta 只增加风险披露和发行材料，不解开备份、目标归属、同卷或Undo材料安全停止条件。修复并非默认禁用：按本指南生成计划、审阅范围并批准完整哈希即可调用真实修复链。计划/交互确认/执行与撤销前均显示 Experimental 风险；不要将公开发布等同于真实系统验收。
