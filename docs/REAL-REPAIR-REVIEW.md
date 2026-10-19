> Beta发行上下文：下文为 b09b171 及此前的开发/审查记录，原“未发布/不Push”描述其当时边界。本次用户已授权 v0.2.0-beta Experimental Pre-release；不改变下文真实验收 NOT_TESTED 结论。当前发行说明见 BETA-RELEASE-NOTES.md。

# 独立 Agent 复审结果

当前结论：本轮 F-11/F-12 补丁及最终定向证据独立 Agent 复审 PASS（本地候选，不代表真实救援验收通过）。GPT 对上一候选11647c8的CHANGES_REQUIRED保留为修订来源。以下早期PASS仅覆盖原两项问题。

独立只读审查对象：实现 commit 87f2946af2710bacb41544c69837bdb45335c8c3，基线37a32e0；随后复审最小补丁差异。独立审查未修改实现、未运行真实环境修复、未机械重跑旧测试。

首轮 PATCH_REQUIRED：
1. P1：原事务计划7天过期后Undo被阻止，新计划无法撤销旧run。修复为Forward拒绝过期，原事务经本人重新明确批准可Undo，全部哈希/身份/Journal/备份/漂移仍验证，嵌套Undo capability同规则。
2. P2：SandboxGuide复用已有非私有输出目录会落私密快照。修复为创建/复用后统一Assert-PrivateDirectory，拒绝不合格目录且不修改已有ACL。

补丁复审：两项关闭。独立Agent实际读取PowerShell7.6.5及WindowsPowerShell5.1各2/2定向结果，核对Forward/Undo过期分离、新官方auth冲突保护、新建/合格/不合格输出目录行为。其余已关闭项保持关闭。

真实Task/Registry/COM写入、GUI/本人官方登录与模型、原项目新会话实际工具、重启与Sandbox管理员修复均NOT_TESTED。缺失这些证据不是编码阻塞，也绝非已被本次代码审查证明成功。候选停在REAL_REPAIR_REVIEW_READY，不Push、不发布。

最终Commit/候选ZIP/逐项哈希绑定在包外manifest，避免提交或压缩包的自引用。

## GPT 定向修订复审

范围：相对 11647c8 的 F-11/F-12 差异，F-13/F-14 计划阻塞与披露。沿用未受影响旧项，不把原 PASS 当成本轮结论。独立 Agent 只读审查当前差异、核对定向证据；不操作真实系统。最终结论 PASS：独立 Agent 实际阅读当前补丁与两引擎最终结果、原失败记录及最小复验，没有重跑旧测试。F-11/F-12 关闭；F-13/F-14 保留适用性阻塞并明确披露，不宣称功能已经支持。

复审另发现：CaptureStoppedConfiguration 的 startup-only Undo 失败后 phase 变为 PARTIAL，会误要求从未创建的停止后快照；修为按真实快照/备份/配置 Journal 事实要求绑定，并以中断 Stop→首次启动 Undo 失败→第二次成功的定向用例闭合。

最终证据：PS7 新增6/6加重试1/1，PS5.1新增7/7；v02流程PS7 25/25，PS5.1原24/25（CLI编码失败保留），UTF-8 BOM修正后CLI两引擎各1/1；最终scope显示各1/1。组合覆盖，不是一次最终源码全量。独立复审核对CLI最后差异仅BOM及已审参数接线。

原生合成双writer确实复现复活，repair_exit=3、undo_exit=0、60秒观察、保护资产一致。first_exit/writer_exit为null，未取得退出码；退出由实际WaitForExit断言确认，不填造0；reviver_exit=-1按原记录保留。真实API、GUI/模型/工具/重启仍NOT_TESTED。
