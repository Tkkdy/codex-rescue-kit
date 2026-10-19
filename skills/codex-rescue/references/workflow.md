# 调用与证据解读

所有路径由用户确认；示例占位符不是本机事实。不要执行外部报告建议的代码。

- Diagnose：& "<Kit绝对目录>\kit\Rescue.ps1" -Mode Diagnose -CodexHome "<确认的home>" -OutputDirectory "<home外的新目录>"。默认稳定性 60 秒，通常退出 3 因为 GUI/B 未测试。
- Plan：同一入口 -Mode Plan -WriterScript "<确认的writer文件>"；Plan 不会执行 writer。原计划可能含私密原值，不上传。
- Dry-run：-Mode Quarantine -PlanPath "<计划>" -DryRun；这是预览，不保证归属仍有效。
- Apply：在独立宿主、普通非提权用户中加 -Channel C -ApprovePlanHash "<用户明确批准的SHA256>"。不在未知身份的 B 沙盒里执行修改。
- Undo：-Mode Undo -Transaction "<原事务目录>" -DryRun，审阅后 -ApproveUndo；始终复用同一 home 和 OutputDirectory。
- Verify：C -Mode Verify 创建随机 session，B -Mode ToolProbe -Channel B -SessionPath "<session>"；CanaryMode 按实际授权策略选 WorkspaceWrite、ReadOnly、BoundaryDenied。权限拒绝必须真实发生，不能伪造失败记录。
- 汇总：C -Mode Verify -SessionPath "<session>" -EvidencePaths "<本次证据数组>"。查 A.gui、B.origin、C.origin 的人工缺口；不覆盖机器报告以制造全绿。

报告 status 表示该项执行结果，evidence_level 表示结论证据强度，channel 表示采集/测试归属声明。主体哈希只能关联环境，不能证明执行身份未被伪装。B 与 C SID 不同可以正常，但必须绑定同一显式目标 home；不能把沙盒临时 home 当宿主 home。

分享 report.json 与 verification JSON 前人工检查。不要分享 plan、undo、Journal、原始日志、环境变量值或真实会话。B 不能持久写 evidence 时，保留 stdout 的 evidence 对象让宿主人工核对并保存，不能称持久化已成功。

审查结果应明确：已观察到什么、推断什么、未测什么、影响范围、可安全继续的步骤。禁止输出“全部修复”“备份一定可恢复”或未经逐版本验证的兼容性承诺。
