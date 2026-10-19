# F-09 / F-10 复核与开发侧补丁
状态：V0.1_REVIEW_READY；独立复审、VM、公开发布仍未通过。基线为 6a39c247cc4f64e9d1cc14bbf33d02ecd3cedd4b。最终 Commit、包哈希见外部交接清单，避免自引用。本文件是整理记录，不是执行输出。

| 问题 | 独立复核 | 本次处置 | 证据边界 |
|---|---|---|---|
| F-09 | CONFIRMED：原适配器用动态 State 判断配置 Enabled；运行/排队实例与配置启用位不是同一属性。报告所述本版本真实 Windows 后果仍 NOT_TESTED。 | 只读 Settings.Enabled 布尔值；缺失或非布尔值以 TASK_ENABLED_UNAVAILABLE 拒绝，不从 State 猜测。保留仅忽略 Settings.Enabled 的 XML 指纹。 | 每个引擎 8 个 task 定向用例，包括既有指纹用例和新增 7 例；真实 API 待 VM。 |
| F-10 | CONFIRMED：StreamReader 先解码字符串、WriteAllText 再编码 UTF-8，旧“原始输出字节”描述错误。此结论不推翻已有 ASCII 测试结果/文件哈希。 | 采用报告方案①：纠正文本捕获口径；新捕获显式使用 UTF-8 解码/替换非法字节，记录解码策略；修正旧 metadata，不改变旧日志。 | 两引擎各 1 次非 ASCII/非法 UTF-8 边界捕获；证明保存的文本与原 pipe 字节不同，不承诺任意编码无损。 |

## F-09 定向验证

测试仅用本地函数 mock Windows cmdlet；真实 Get-TargetState、Plan、事务、Journal 和 Undo 引擎参与，持久化仅在新建合成 fixture。Settings=true/false 与 Running/Queued/Ready/Disabled 矩阵覆盖；缺少设置/字符串 false 必须拒绝。Running、Queued 在禁用后仍保持动态状态，检查配置确实禁用、随后 Undo 实际恢复启用，不能走假 ALREADY_ORIGINAL。已禁用但运行/排队的任务不进 Plan。修改后/APPLIED 前中断仍可恢复，重复 Undo 不产生第二次修改。修改前要求已持久化 undo.json 和 PENDING/UNDO_PENDING；合成用户资产树保持不变。active-writer 预检仍应 BLOCKED，没有为了复现关闭安全预检。

这些用例不证明真实 Task Scheduler 可以在本机安全变更，也不证明所有 Cmdlet/CIM 返回类型兼容。Settings.Enabled 非布尔或不可读时拒绝是保守兼容边界。

## F-10 证据纠正

capture 字段改为 RUNTIME_CAPTURED_TEXT_REENCODED_UTF8_SAVED_WITHOUT_MANUAL_EDIT。stdout/stderr 日志表示运行时解码后重编码的文本，保存后未人工编辑；其哈希只证明这些文件字节的一致性。新记录有 UTF-8 decoder、UTF-8_NO_BOM 保存和替换策略；非法 UTF-8 的 0xFF 被替为 U+FFFD。非 ASCII stdout/stderr 正向文本与替换行为各自断言。

旧 ps51/pwsh-commands.json 只更正 capture/provenance 并追加 F-10 纠错说明，原命令参数、UTC、退出码、tested_source、输出日志及哈希不变。旧记录器没有记录实际 decoder，明确 UNKNOWN，不倒填为新 UTF-8 策略。旧候选包/交接包及 sidecar 保持原字节，其中旧说法由本文件纠正。

## 复用与本轮执行

- 基线：PS5.1/7 各 62/62 PASS、入口、至少 60 秒窗口、Skill validator 证据，已被独立报告逐文件核对；不机械重跑。它们仍关联基线 Git blob，不能称为本次提交的全量 69 例回归。
- 本轮：PS5.1/7 各 8/8 task 定向 PASS，编码检查 PASS，各一次源码解析/有限敏感模式扫描 PASS。三类子进程 regression / encoding / static 的退出码均为 0；这些是测试驱动退出码。
- 未改动的 Verify 保持 A.gui/B.origin/C.origin=NOT_TESTED；历史完整产品 Verify=3，不以外层测试驱动 0 替代真实通道验收。
- evidence/patch-validation.json 是整理的复用依据；source-manifest.json 保持基线 16 文件，current-source-manifest.json 与新命令记录绑定当前源码。打包器从真实基线 Git blob 校验旧哈希，逐项核对改动、补丁捕获/结果、当前源文件哈希；缺证则拒绝打包。
- 本轮无须重测未变的 Run、Startup、三通道与 Skill 逻辑；F-01～F-08 保留上一份独立报告的关闭/部分关闭边界。

## 必需的 VM 与发布关卡

在可丢弃 Windows 11 x64/NTFS、无真实用户数据的普通账户中验证：
1. 真 Task Scheduler 的启用+运行→禁用但实例继续→Undo，以及已禁用但 Running/Queued；核对 Settings.Enabled、Plan、Journal 和最终配置，不绕过 active-writer guard。不能安全触发时保留 BLOCKED/NOT_TESTED。
2. 真 HKCU Run 的 Registry64、String 类型、可写句柄/默认值保护、无关同名对象、拒绝访问与 Undo 冲突；真实 Startup COM .lnk 的归属、移动/恢复。
3. 三类目标在 PENDING 后及实际修改后/APPLIED 前中断；writer/对象/held/Journal 漂移，重复 Undo、权限不足与恢复边界。
4. 独立宿主 C 和真实 Codex 工具 B 的外层来源记录、沙盒只读/工作区/越界拒写，A GUI 的新聊天/虚构长历史/审批/冷启动。
5. 独立代码/安全审查、支持矩阵、维护者/安全联系方式、MIT 权利归属和最终隐私复核。公开发布须另获明确授权。

无系统配置、真实任务/Run、ACL/owner、真实 Codex/auth/历史/Skills 修改；无 push、部署或公开发布。

官方复核依据：[RunningTask.State](https://learn.microsoft.com/en-us/windows/win32/taskschd/runningtask-state)、[TaskSettings.Enabled](https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings-enabled)、[StreamReader.ReadToEndAsync](https://learn.microsoft.com/en-us/dotnet/api/system.io.streamreader.readtoendasync)。未复制第三方实现代码。
