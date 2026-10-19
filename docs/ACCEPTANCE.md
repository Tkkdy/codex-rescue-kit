# v0.1 开发侧验收报告

状态：**V0.1_REVIEW_READY**。这是可交独立 Agent 的开发候选，不代表安全审计、真实用户验收或公开发布许可。未发现当前合成验收范围内未解决的关键失败；真实系统适配器与 GUI/沙盒验证仍是明确关卡。

## 实际交付与覆盖

| 要求 | 开发结果 | 证据/边界 |
|---|---|---|
| 独立默认 Diagnose 入口 | 完成 | rescue.cmd 使用绝对 Windows PowerShell、NoProfile、不提权/绕策略 |
| Windows/CLI/Store、身份/home、配置/provider 线索 | 完成有限发现 | 只采元数据；完整有效配置与运行时归属 UNKNOWN，不运行 PATH 的 Codex |
| auth、Skills/Rules/历史保护 | 完成 | auth 仅存在性；不打开聊天/DB；资产树不变断言 |
| Sandbox/ACL、自启/代理、配置稳定性 | 完成只读元数据和窗口监控 | 不把旧错误/保护 DACL 判为根因；不修改安全策略 |
| Quarantine | 完成真实适配器与合成引擎 | 精确 writer/Principal/命令匹配、Plan+哈希批准、对象复核、禁止强杀 |
| 持久 Undo 与中断 | 完成 | undo+PENDING Flush 先于修改，APPLIED 前后中断回归，冲突/损坏拒绝 |
| Verify A/B/C | 完成确定性记录和汇总 | 真实 native exit/challenge/canary；A.gui/B.origin/C.origin 无自动 PASS |
| Codex Skill | 完成，未安装到当前环境 | 标准 name/description，复用 Kit，标准 validator 通过 |
| 开源准备 | 完成候选准备 | 中英文 README、操作/安全/恢复/测试/许可/独立审查文档；白名单包 |
| 公共发布/生产应用 | 未执行 | 没有 push、release、部署、登录、付费调用或真实 Codex 配置修改 |

## 自动化结果

- PowerShell 7.6.5：**62 PASS / 0 FAIL**。
- Windows PowerShell 5.1.26100.9711：**62 PASS / 0 FAIL**。
- Windows 11 x64、OS 10.0.26200.0，本地 NTFS；只对这两个合成组合记实测。
- 入口污染环境联调 PASS：实际 rescue.cmd→5.1，默认 Diagnose，真实退出码 3。
- 真实 60 秒窗口联调 PASS：3 个 C 原生探针与 canary，完整汇总仍为 3，A/B 缺口保留。
- 全部 PowerShell 源码解析、受限敏感模式/禁止操作扫描 PASS。扫描不等于完整安全审计。
- Skill 标准 quick_validate 通过；校验器仅来自已有宿主，不作为依赖打包。

详细逐项结果在 evidence；其中所有场景均标 synthetic_only=true。source-manifest.json 关联核心源码和测试工具字节。候选 ZIP manifest 关联最终 Git commit 与每个归档文件 SHA-256。Git SHA/ZIP SHA 在外部交付记录中，避免在自身提交内容中循环引用。

## 重要修复记录

测试暴露并修复 File.Replace 的 null 字符串互操作问题，使合成状态修改实际完成；随后验证真实 held 文件移动/恢复与资产不变。60 秒联调另发现 PowerShell 7 JSON 日期对象被重复换算时区，导致有效证据错误拒绝；已统一 UTC 处理，并将 C/B 正向汇总纳入断言。进一步修复任务指纹归一化不能掩盖 Trigger Enabled 漂移、盘符相对路径/设备别名拒绝，以及 B 诊断不能误标 C。最终结果以上述修复后的回归为准，早期失败缓存不打包。

## 未测试、部分支持与已知风险

**NOT_TESTED**：真实 Task Scheduler/HKCU Run 修改、真实快捷方式 COM 归属发现、真实 Codex 版本组合与 Sandbox 权限、GUI/登录/UAC/审批、真实旧长会话、干净机器还原。用户明确要求不对当前真实环境试验，因此留待可丢弃环境独立验收；没有伪造 PASS。

**部分支持**：TOML 只作有限线索；没有可靠历史基线不能宣布资产丢失；启动命令语法窄，不支持服务/跨用户/复杂包装。企业/提权环境拒绝修改。长路径与不同后端不作泛化兼容承诺。

**风险**：有权限的本地攻击者、同用户伪造/竞态、硬件断电、企业管理识别不完整、B 来源不可自证，以及 Undo 恢复自启可能重新引入原故障。详见 SECURITY、KNOWN-LIMITATIONS 与 RELEASE-CHECKLIST。

开发侧验收完成后停止，不以这些残余人工项目为理由触碰真实 Codex，也不把它们包装为已通过。若独立审查发现关键缺陷，应退回开发并撤销候选状态后修复，重新关联证据和提交。

## 独立审查后补丁

逐项复核、证据等级修正及关闭边界见 REVIEW-RESPONSE.md。修复 F-01～F-07 对应的已确认代码/测试缺口；F-08 按能力限制处理，增加 C.origin 明确缺证，不能声称自动证明来源。真实适配器、权限与 A/B/C 独立来源仍保留发布关卡。

本轮 evidence 增加双版本实际命令/退出码捕获及运行时解码并重编码 UTF-8 的输出文本（保存后未人工编辑，非 pipe 原始字节），源码哈希绑定最终回归。之前记录器跨版本模块路径导致的失败已保留并解释，不作为成功证据。没有触碰真实 Codex 环境。

## F-09 / F-10 补丁验收范围

本次 PS5.1/7 各 8/8 task 定向回归、编码边界与静态检查通过；上文 62/62、入口与 60 秒窗口为基线 6a39c247cc4f 的复用证据，并非本次提交全套重跑。F-09 改读任务 Settings.Enabled，F-10 纠正文本捕获口径；开发侧关闭范围和 VM 关卡见 PATCH-F09-F10.md。公开发布仍 RELEASE_BLOCKED。
