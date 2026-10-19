> 历史 V0.1 / Preview 文档。v0.2 当前操作与权限以 [真实修复说明](REAL-REPAIR-v02.md) 和 [收敛验收](REAL-REPAIR-ACCEPTANCE.md) 为准；以下旧证据仅适用于其绑定版本。

> **v0.1.0-preview.1 公共预览提示：** 本版真实 Windows 的 Quarantine/Undo 禁用并返回 `PREVIEW_REAL_MUTATION_DISABLED`。下面涉及实际隔离/Undo 的操作仅供历史实现审阅或未来版本规划，不能在本预览版完成。详见 [预览范围](PREVIEW-PUBLICATION.md)。

# A / B / C 验收

A 是桌面 GUI；B 是目标聊天实际调用的本地工具执行通道；C 是独立宿主 PowerShell。三者分别记录。主机命令成功、CLI 成功或 JSON 自报 channel=B，都不能证明桌面聊天的工具恢复。

## 创建会话和宿主基线

在独立普通 PowerShell 中，指定已确认的 targetHome 和持久 run：

~~~powershell
$kit = "C:\RescueKit"
$targetHome = "C:\RescueLab\home"
$run = "C:\RescueLab\reports\verify1"
& "$kit\kit\Rescue.ps1" -Mode Verify -CodexHome $targetHome -OutputDirectory $run -Channel C
~~~

返回 session_path、session_sha256、随机 challenge、canary_root、boundary_root。记录这些值和本次 Codex 聊天/工具调用标识。会话两小时过期，目录固定，不能重定向 canary 到用户资产。

~~~powershell
$session = "<session.json绝对路径>"
& "$kit\kit\Rescue.ps1" -Mode ToolProbe -CodexHome $targetHome -OutputDirectory $run -SessionPath $session -Channel C -CanaryMode WorkspaceWrite
~~~

三个探针分别在当前 PowerShell 的**绝对安装路径**启动无 Profile 子进程执行 Get-Location、版本检查、Get-Date。必须退出 0 且 stdout 精确匹配本次随机 challenge；超时、启动失败和非零退出为 FAIL。无网络请求。仅终止自身创建且超时的探针子进程，不终止用户应用。

## 在实际 B 通道执行

让目标桌面聊天通过它的真实 shell 工具执行同一命令，但 Channel=B。不能从另一个宿主窗口代跑。允许 B 的 SID 与 C 不同；必须显式指定相同 home 和 run，session 绑定 home 指纹，另记录 B 执行者指纹。若隔离身份无法读取发行 Kit 或会话，记 BLOCKED，不能复制用户 auth、放宽 ACL 或关闭沙盒使其通过。

工具返回 3 项实际退出记录及 canary 结果。它们证明这一次执行链，包括子进程；不涵盖所有 Codex 工具或未来运行。最终人工核对工具 transcript 中的会话 ID、challenge、命令、时间、工具外层退出码和审批状态。无法获得 transcript 时，B.origin 维持 NOT_TESTED。

### 写入与拒绝边界

WorkspaceWrite：在该 session 的 canary_root 创建唯一 challenge.txt，flush、读回并删除自身刚创建的那个文件。既有文件会阻塞，不清理陌生文件。

ReadOnly：在**确实以只读策略运行的 B** 中，尝试同一路径，预期真实 UnauthorizedAccessException 且文件不存在；若写成功即 FAIL，并只清理自身文件。

BoundaryDenied：目标为 session 的 boundary_root。必须由实际 B 的工作区边界把 canary_root 作为可写范围，而让它的兄弟 boundary_root 位于该范围外。Kit 不修改 ACL 或策略来制造拒绝。可在可丢弃 Codex 工作区中打开返回的 canary_root，按当前客户端支持的方式选择只读/工作区权限；具体组合由独立审查验证。若客户端不提供该边界，记录 NOT_TESTED 或 N/A 的人工说明，不能靠移动用户项目或降低策略来通过。

不要在具有全盘写权限的宿主上声称验证了 B 的只读策略；错误类型也可能由 NTFS 权限造成，须结合策略/工具日志解释。拒绝预期是能力边界测试，不意味着允许修改该边界。

B 可能没有权限把 evidence JSON 写回 session。此时返回 persistence_status=BLOCKED、evidence_path=null，并在 stdout 的 evidence 字段保留白名单结构。宿主在人工核对原工具记录后，把这个 **evidence 对象本身**保存为 session 目录下的新 JSON，切勿执行复制来的文本。若 stdout 也不可获得，该项 NOT_TESTED。禁止把 BLOCKED 改写为 PASS。

## 汇总

在 C 中列出本次实际生成的 evidence 路径：

~~~powershell
& "$kit\kit\Rescue.ps1" -Mode Verify -CodexHome $targetHome -OutputDirectory $run -SessionPath $session -EvidencePaths "<evidence-C绝对路径>","<evidence-B绝对路径>" -StabilitySeconds 60 -Channel C
~~~

用 PowerShell 原生入口传 string[]，避免 cmd 对逗号参数的不同解析。汇总检查 schema、会话绑定、有效期、随机值、3 个不同探针、真实非空退出码、canary 条件和 C 侧文件不存在。失配或缺证不判成功。

config.toml 检查 SHA-256、长度、mtime；.env **只看长度和 mtime，不读取内容**。准备会话与验收时的基线对比，以及默认 60 秒每秒采样。它不保证秒间瞬时修改、修改后复原或未来持续稳定。

## A 人工清单

使用虚构内容，不打开真实用户历史用于发布测试。逐条记录客户端版本、实际操作、时间和证据引用，标 PASS/FAIL/BLOCKED/NOT_TESTED/N/A：

- 冷启动客户端，打开新聊天，发送虚构无敏感信息内容并完成响应。
- 在该聊天完成本次 B 探针，确认命令实际进入工具通道。
- 按客户端的正常机制进行一次人工审批；拒绝一次，确认没有继续执行。
- 用本测试版本生成的虚构旧/长会话测试打开与继续对话。CLI 结果单独记，不替代 GUI。
- 退出后冷启动，复查 home、身份、配置稳定性与用户能力仍在；不承诺 8 小时后不漂移。

Kit 的 A.gui、B.origin 故意不自动 PASS，汇总常返回 3。人工审查结论应作为独立签署材料，不覆盖原始机器结果。无论隔离成功与否，不能把它直接称为 Codex 全面恢复。

## 来源关联记录（人工材料，不覆盖机器结果）

-Channel B/C 仅是采集者声明。C.origin 与 B.origin 均保持 NOT_TESTED；在聊天工具里写 -Channel C 不能把它变成独立宿主证明。home.input PASS 也仅表示路径通过检查；home.selection 在存在时仍等待 runtime 关联，缺失则 BLOCKED。

独立审查者对每次执行保留下面的表。只记录虚构测试，不附凭据、聊天正文或整段环境变量：

| 字段 | 应记录的事实 |
|---|---|
| session / challenge / session SHA | 与本次机器证据一致 |
| 声明通道 / 外部确认通道 | 分开填写；无法外部确认则 UNKNOWN |
| 外层证据引用 | 宿主窗口操作记录或 Codex 工具调用 ID、时间、可核验 transcript 引用 |
| 命令与退出码 | 外层工具退出码、ToolProbe 退出码、三个子探针退出码分开记录 |
| 身份 / home 关联 | 指纹对应关系、客户端版本、实际策略与审批状态；不导出真实路径和 secrets |
| 人工结论 | reviewer 标识、UTC 时间、PASS/FAIL/BLOCKED/NOT_TESTED/N/A 与依据 |

这份表是整理和签署材料，引用的实际工具/窗口证据才是来源依据；表本身也不是密码学证明。Kit 不自动导入此表、不把人工声明提升为 PASS。独立来源验收必须在可丢弃环境中完成，不能模拟为已通过。

配置采样读取异常时，config.session/config.stability 为 BLOCKED，其他验收继续落盘；观察到实际变化仍为 FAIL。会话初始基线不可读，即使后来解锁也不能把该基线比较判 PASS。
