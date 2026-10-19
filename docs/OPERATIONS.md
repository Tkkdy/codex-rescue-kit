> 历史 V0.1 / Preview 文档。v0.2 当前操作与权限以 [真实修复说明](REAL-REPAIR-v02.md) 和 [收敛验收](REAL-REPAIR-ACCEPTANCE.md) 为准；以下旧证据仅适用于其绑定版本。

> **v0.1.0-preview.1 公共预览提示：** 本版真实 Windows 的 Quarantine/Undo 禁用并返回 `PREVIEW_REAL_MUTATION_DISABLED`。下面涉及实际隔离/Undo 的操作仅供历史实现审阅或未来版本规划，不能在本预览版完成。详见 [预览范围](PREVIEW-PUBLICATION.md)。

# Windows 安装与操作

## 安装和前提

完整解压候选包，核对旁边的 .sha256；不需要安装模块、依赖、服务或写环境变量。PowerShell 5.1 为双击入口；7 可显式运行 kit\Rescue.ps1。只运行已核对来源的 Kit，不能把日志中出现的路径当作可信代码。

使用本地 NTFS 短路径；拒绝 UNC、设备/扩展路径、ADS、路径穿越和 reparse 祖先。长路径不作端到端支持承诺，PS5.1 尤其可能拒绝。不要以管理员运行 Quarantine/Undo；工具拒绝提权身份、服务身份和已识别的管理设备。Diagnose 的只读指读取目标；它仍会在外部输出目录写报告。

## Diagnose

~~~powershell
$kit = "C:\RescueKit"
$targetHome = "C:\RescueLab\home"
$run = "C:\RescueLab\reports\run1"
& "$kit\kit\Rescue.ps1" -Mode Diagnose -CodexHome $targetHome -OutputDirectory $run -Channel C
~~~

上面为示例虚构路径。真实 home 由用户确认，不能照抄。省略 CodexHome 时按进程 CODEX_HOME、用户默认 .codex 顺序选择，并提示不能据此证明运行时实际 home。显式 home 仍需与 Codex 运行身份核对。重复 Diagnose 使用新 run；不得覆盖原证据。默认不读取 auth.json 内容，配置只作有限文本线索提取，不等于 TOML 生效解析。

## 精确 Plan、Dry-run 和隔离

仅在用户已确认具体写入源、归属及影响后，将其实际 writer 文件传入。不能按进程同名、provider 名或任意关键词自动选目标。支持极窄启动命令：直接文件，或 PowerShell -File、Python/WScript 等单文件调用；拒绝额外脚本参数、命令表达式和变量扩展。复杂 CC Switch 部署可能不匹配，此时 N/A 而非猜测归属。

~~~powershell
& "$kit\kit\Rescue.ps1" -Mode Plan -CodexHome $targetHome -OutputDirectory $run -WriterScript "C:\RescueLab\guard.ps1"
# 返回 plan_path 和 approval。先在本地检查 plan.json 中的精确对象与 before 状态。
& "$kit\kit\Rescue.ps1" -Mode Quarantine -CodexHome $targetHome -OutputDirectory $run -PlanPath "<绝对计划路径>" -DryRun
# 用户明确批准这一版计划的 SHA-256 后：
& "$kit\kit\Rescue.ps1" -Mode Quarantine -CodexHome $targetHome -OutputDirectory $run -Channel C -PlanPath "<绝对计划路径>" -ApprovePlanHash "<64位SHA256>"
~~~

Dry-run 只展示输入计划，不代表对象仍有效；Apply 再次发现归属并核对 writer 内容、执行身份和每个对象指纹。任务须只有一个匹配 Action 且 Principal 为当前用户。仅 HKCU Run 的 String 值；不操作 HKLM Run、服务或其他用户自启。Startup .lnk 只移动到同卷 transaction 内；原文件内容不改。

运行中的 writer 会 BLOCKED；请用户在自己的应用中正常退出，并知晓内存状态无法回滚。工具不代替用户终止它。自启禁用不能保证其他未识别来源停止改写，后续须 Verify。

## Undo

~~~powershell
& "$kit\kit\Rescue.ps1" -Mode Undo -CodexHome $targetHome -OutputDirectory $run -Channel C -Transaction "<transaction绝对目录>" -DryRun
& "$kit\kit\Rescue.ps1" -Mode Undo -CodexHome $targetHome -OutputDirectory $run -Channel C -Transaction "<transaction绝对目录>" -ApproveUndo
~~~

同一目标、身份、run 才能回滚。先对照每项状态，用户批准后恢复。冲突项 FAIL，其他可恢复项可继续；必须检查 checks 数组，不能把部分恢复称为全恢复。重复 Undo 识别已恢复项。没有自动重启任务或应用；恢复自启可能重新引入旧问题。

## 状态和退出码

| 状态 | 意义 |
|---|---|
| PASS | 仅该项已运行且达成所述条件 |
| FAIL | 观察到失败、数据不一致或回滚冲突 |
| BLOCKED | 当前身份、权限或安全条件阻止操作 |
| NOT_TESTED | 未执行、证据不足、人工待核对 |
| N/A | 该项确实不适用，例如未找到可隔离关联源 |

退出码 0：本操作完成或 N/A，不代表整体 Codex 恢复；2：至少一项 FAIL；3：有 BLOCKED/NOT_TESTED；4：输入、权限、完整性或调用错误，安全停止。原始异常文本不输出，避免泄露路径/命令行；排查时先核对参数、home/run、权限、批准哈希与 Journal，不开启宽泛错误转储来分享。

## Skill 的安装

候选阶段未自动安装。审查通过并获用户授权后，将 skills/codex-rescue 文件夹安装到用户所选 Skill 根目录；Kit 仍保留在单独、已验证的发行目录。启动 Skill 时提供 Kit 绝对位置，不依赖相对安装布局、不搜索或执行报告里推荐的脚本。安装与切换版本应独立于故障救援，不改当前用户的其他 Skills。
