> 历史 V0.1 / Preview 文档。v0.2 当前操作与权限以 [真实修复说明](REAL-REPAIR-v02.md) 和 [收敛验收](REAL-REPAIR-ACCEPTANCE.md) 为准；以下旧证据仅适用于其绑定版本。

> **v0.1.0-preview.1 公共预览提示：** 本版真实 Windows 的 Quarantine/Undo 禁用并返回 `PREVIEW_REAL_MUTATION_DISABLED`。下面涉及实际隔离/Undo 的操作仅供历史实现审阅或未来版本规划，不能在本预览版完成。详见 [预览范围](PREVIEW-PUBLICATION.md)。

# 故障恢复与 Undo 指南

## 工具无法启动

从 Windows 正常开始菜单打开 PowerShell，切换到已验证发行目录执行 kit\Rescue.ps1。若系统策略、签名要求、权限或运行时损坏阻止启动，记录系统提示交管理员；不关闭沙盒、改 ACL、使用 ExecutionPolicy Bypass 或复制真实 auth.json。工具启动失败也可能是路径不支持，不等于 Codex 自身坏了。

## 隔离中断

保留原 run 下 transaction-*、undo.json、journal.jsonl、held-* 和原计划。不要清理、改名或重新用相同计划 Apply。记录结果 FAIL/TRANSACTION_INTERRUPTED_USE_UNDO。

在相同普通宿主身份、相同 home 和输出目录调用 Undo -DryRun。检查每项：

- ALREADY_ORIGINAL：没有变化或已经恢复，重复执行安全。
- UNDO_PREVIEW_APPROVAL_REQUIRED：仍处于本工具预期修改状态；审阅后批准 Undo。
- UNDO_CONFLICT：现在有更新对象或任务定义漂移，不能覆盖。
- HELD_COPY_CHANGED_OR_MISSING：原快捷方式不可用，禁止声称恢复成功。
- UNDO_WRITER_DRIFT_REVIEW_REQUIRED：原 writer 缺失、内容变化或路径出现 reparse；保留隔离和 held，不自动重新启用未知代码。预览不代表该检查已执行。
- Journal/undo 校验错误：停止自动恢复，保留材料交独立审查，不重建“看起来合理”的 Journal。

批准 Undo 后检查每个结果，不只看顶层状态。若有冲突，保留原 held 与新对象，让用户选择后续人工处理；本工具不替用户删除任一版本。恢复任务 Enabled 与 Run/快捷方式只恢复自启定义，不自动启动程序；若旧程序会继续改配置，用户应先理解重新启用的影响。

## 配置仍变化或 B 仍不可执行

隔离 PASS 只说明计划中自启源达到预期状态。若配置继续变化，可能存在其他写入源、当前运行中的程序、同步/策略或未匹配命令，不能扩大关键词批量隔离。新一轮只读取证，重新明确目标。

C 能运行而 B 失败，优先对照执行身份、显式 home、外层工具错误和沙盒后端；不得把 C 的成功填入 B。旧会话 400、认证、证书、网络和模型 payload 不在自动修复范围。不得修改 DB model_provider 来“修复”未验证的内容兼容问题。

## 备份与资产

本产品不移动或恢复 Skills/Rules/历史。不存在不能自动证明丢失；存在也不等于新版 Skill 兼容。需要历史基线、已验证备份和另行批准的恢复流程。CheckBackup 的 PASS 只表示清单 payload 此刻内容相符，不能代替干净机器还原演练。不要把真实用户备份复制为发布 fixture。

唯一允许的自动文件删除是 Verify 清理自己刚创建、路径与 challenge 内容均一致的 canary。其他用户文件和事务材料不自动删除。
