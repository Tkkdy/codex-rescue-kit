# F-01～F-08 复核与补丁交付

状态：V0.1_REVIEW_READY（开发侧候选，独立复审、VM、公开发布许可均未完成）。
基线：716f991a31d6a0089a65cfd84ab43e7222b90506。新 commit 与包哈希见外部候选清单，避免自引用。

| 项目 | 复核结论与证据边界 | 修复与针对性回归 | 开发侧处置 |
|---|---|---|---|
| F-01 | CONFIRMED 原写句柄问题。官方 PS7 RegistryProvider.GetItem 使用 writeAccess=false；不能把静态证据称为两版本实际注册表实测。 | 固定 HKCU/Registry64，显式 OpenSubKey(...,true)，不创建键；句柄内复核待删除值，Undo 不覆盖新值，finally 关闭。工厂约束与内存键 mock 验证删除、原 String 类型恢复、漂移/冲突及默认/无关值保护。 | 代码修复；真实 API 待 VM。 |
| F-02 | CONFIRMED Undo 未使用 writer_hash。 | 每项恢复前及锁内核对 writer 存在、普通路径、SHA；漂移报 UNDO_WRITER_DRIFT_REVIEW_REQUIRED。修改/缺失/父目录 junction 三例覆盖 task/run/startup，核对对象、held、Journal 不变。 | 开发侧关闭；真实适配器仍待 VM。 |
| F-03 | 原为 INFERRED；合成文件上的真实 Windows 独占锁支持读取异常判断，不能扩称全部 OS/ACL 故障已复现。 | 安全快照失败转 BLOCKED；Diagnose、会话创建、Verify 基线和窗口继续产出报告。持续锁、瞬时 IO 异常、失败基线解锁后仍不可变 PASS。 | 已测读取失败路径关闭。 |
| F-04 | CONFIRMED 存在性未参与旧 PASS 条件；显式路径不证明 runtime 归属。 | 分离 home.input 路径合法与 home.selection；缺失 BLOCKED，存在仍 NOT_TESTED 等待运行时关联。测显式/默认缺失及存在路径。 | 开发侧关闭。 |
| F-05 | CONFIRMED 2MB 上限和 blanket FAIL 不合适；数万真实文件必触发上限仍无规模证据。 | 独立 32MiB/100000 项上限，同一只读句柄拒绝并发写，枚举只计数。无法读/超上限 BLOCKED；内容失配/漏项/非法路径 FAIL；统计-only NOT_TESTED。测 >2MiB 合法空白填充清单、锁、32MiB 上限及原损坏/WAL 案例。 | 已测缺陷关闭；未做十万文件压力/完整还原测试。 |
| F-06 | CONFIRMED 旧 Throws 接受任意异常；旧 48 项实际曾假 PASS 未知。 | 所有 Throws 指定精确错误码，摘要记录 expected_refusals；修改拒绝场景核对前后哈希；测试断言器拒绝无关异常/未抛错。 | 开发侧关闭。 |
| F-07 | CONFIRMED 旧枚举未过滤空名称；其真实 OS 自启后果仍 INFERRED。 | 发现、读取、修改统一拒绝空白、过长、反斜线/控制字符名称；合成默认/异常值不进计划且保留原值。保守语法不扩大隔离范围。 | 过滤缺口关闭；真实默认值行为待 VM。 |
| F-08 | CONFIRMED 能力限制，原代码未自动全 PASS；不是隐藏的来源证明。 | 显式增加 C.origin=NOT_TESTED、诊断 channel_origin 声明、外层人工记录清单。同进程自报 B/C，calls 可 PASS，但两个 origin/GUI 不得 PASS，整体 exit=3。 | 防误读加固；真实来源仍需独立人工确认，不能宣称已解决。 |

官方依据：[PowerShell v7.6.0 RegistryProvider.GetItem](https://github.com/PowerShell/PowerShell/blob/v7.6.0/src/System.Management.Automation/namespaces/RegistryProvider.cs#L211-L223)。未复制第三方实现代码。

## 验证与证据性质

PS5.1/7 各 62 项合成回归。两种引擎分别做入口联调、真实 60 秒窗口及源码解析/受限敏感扫描，详情见 evidence。产品 Verify 保留 exit=3；识别该预期结果的测试驱动退出 0，不能混淆。

本轮 *-commands.json 是机器捕获的参数、UTC 时间、退出码、输出哈希和被测源码哈希；*-stdout.log、*-stderr.log 是运行时捕获、经 StreamReader 解码并重编码为 UTF-8 的输出文本，保存后未人工编辑；不是原始 pipe 字节（F-10 纠正）。引擎目录和工作目录为安全分享分别以文件名/哈希、<REPOSITORY_ROOT> 表示。测试内部更深层子命令只保留实现及明确观测结果，不虚构未捕获的完整外层工具 transcript。

本文件、验收报告、任务书与交接 README 是**整理记录**。旧 execution-records.json 来自历史会话整理，不是原始 stdout/stderr；旧包保持原样，本轮捕获不能倒推证明旧版本当时的执行。

## 独立复审与 VM 必需关卡

- 真正的 HKCU Run、Task Scheduler 与 COM .lnk：发现、普通用户权限、精确归属、隔离/Undo、原类型恢复、无关对象保护、权限拒绝。
- 每类对象 PENDING 后、实际修改后/APPLIED 前中断；日志不能假成功，应可恢复或明确部分失败。
- writer 修改/删除/reparse、held/Journal 损坏、Undo 冲突与重复调用；同用户竞态仍是限制，哈希链不是签名。
- 独立宿主 C、真正桌面工具 B 的外层来源与退出码、真实只读/工作区/边界拒绝，A 新聊天/虚构长历史/审批/冷启动。
- 独立核对版本支持矩阵、许可证归属、维护者/安全联系、最终包隐私和公开发布许可。

本轮只写独立源码与合成 fixture，没有修改真实 Codex、auth、安装 Skill、任务/Run/ACL/owner 或持久环境变量；没有 push、发布或部署。
