# v0.1 实现规格

## 分层和目录

~~~text
rescue.cmd                      独立 Windows PowerShell 入口
kit/Rescue.ps1                  CLI 参数与安全错误输出
kit/Rescue.Core.psm1            公共 API
kit/Private/Common.ps1         路径、上下文、持久化、哈希、状态
kit/Private/Adapters.ps1       任务、Run、Startup 与合成适配器
kit/Modules/Diagnose.ps1       白名单观测
kit/Modules/Quarantine.ps1     Plan / Apply / Undo
kit/Modules/Verify.ps1         会话、真实探针、canary、汇总
kit/ProbeChild.ps1             固定无网络子进程探针
skills/codex-rescue/           Markdown 工作流，调用用户确认的 Kit
tests/                        合成故障与入口联调
tools/                        解析/敏感模式检查、候选打包
evidence/                     脱敏合成测试摘要
docs/                         使用、风险、验收与发布关卡
~~~

L0 独立入口不依赖 Codex；L1 确定性 PowerShell 实施；L2 Skill 解读证据和协调真实工具；L3 人工处理 GUI、登录、审批、被策略阻塞及不支持的系统修复。故障分类来自观测代码和状态，无法归因的项目保持 UNKNOWN。没有在线模型分类器或规则下载。

## 输入、输出与权限

| 模块 | 输入 | 输出 | 权限与修改 |
|---|---|---|---|
| Diagnose | 已确认 home、独立新输出目录、观察秒数 | report.json、中文 Markdown | 普通读权限；仅写报告 |
| Plan | 显式 writer 文件、home/run | 私密计划、SHA 批准值、对象指纹 | 读对象和脚本哈希；只写计划 |
| Quarantine | 计划路径、用户批准 SHA、Channel C 声明 | 逐项 Journal、undo 快照、held 快捷方式、结果 | 非提权当前用户；仅关联自启源 |
| Undo | 原事务目录、相同身份/目标、ApproveUndo | 逐项恢复和冲突结果，追加 Journal | 不覆盖更新对象、不重启进程 |
| Verify | 会话、实际 B/C evidence、canary 意图 | 分通道检查与人工 A 清单 | 不改策略；只创建/清理受控探针文件 |
| CheckBackup | 外部逐文件清单、payload | 内容一致性检查 | 只读；不制作/还原备份 |

代码不使用模块安装、管理员 UAC、注册服务或环境变量持久化。正常入口无 Profile；不运行 PATH 上的 Codex 二进制。运行时差异、多个 CLI、home 来源和环境变量存在性只作观测，不将它们本身判定为事故。

## 事务与失败处理

计划包含 schema、随机 id、身份/机器/home 指纹、writer 路径和内容哈希、每项原状态及哈希。原文仅留本机。Apply 校验已批准计划的文件 SHA，重新发现关联，核对身份、对象状态和 writer 内容。运行中的 writer 阻塞，不提供强杀选项。

状态顺序：计划批准 → 输出目录排他锁 → undo.json 持久写入 Flush(true) → BEGIN → 每项 PENDING 持久写入 → 最小修改 → 读取后置状态验证 → APPLIED → COMMITTED。undo 快照使用自身实际字节哈希，BEGIN 同时保存已批准计划的哈希，避免不同 PowerShell 序列化改变撤销校验。

任务仅禁用，保留定义；指纹使用导出的 XML，排除自身 Settings.Enabled 状态，其余触发器/设置保持受检。HKCU Run 保存原 String 类型/值再删除该值；Startup 原 .lnk 同卷 Move 到 held。可恢复性建立在这些特定前置状态上，不是全系统备份。

中断返回 FAIL 并保留事务，绝不暗示自动撤销已完成。Undo 以 PENDING 反向遍历，即使操作已发生而 APPLIED 尚未落盘，也按当前状态判断：原状态则幂等成功；准确的预期修改状态才允许恢复；其他状态冲突拒绝。持有快捷方式必须核对内容哈希。先写 UNDO_PENDING，再恢复、验后置条件、写 UNDONE。每项失败不会掩盖其他项。

Journal 为 seq、prev、JSON payload 字符串和 SHA 链；检测截断、意外损坏和顺序变化。它不是签名或同用户攻击防护。磁盘/硬件失效、断电写缓存、任务外部竞态不承诺绝对事务原子性；遇到损坏停手人工处理。

## 报告契约

schema 版本固定为 rescue-report-v1 / rescue-verification-v1 / rescue-tool-evidence-v1 / rescue-plan-v1。字段为确定性代码白名单，拒绝直接复制日志、配置值、URL、异常消息和聊天正文。共享报告包含版本、synthetic、run/session 标识、时间、目标哈希和 checks。

每项 check：id、status、code、channel、evidence_level、observed_at、data。status 集合严格为 PASS/FAIL/BLOCKED/NOT_TESTED/N/A。等级 CONFIRMED 仅适用于已观测事实，INFERRED 是候选关联或推断，UNKNOWN 为无法证实；等级不等于恢复验收。证据无法采集时仍需标明缺失，不得以空集合当作健康环境。

data 只含存在性、计数、受限版本字符串、枚举、布尔、ACL 权限与主体指纹等安全元数据。真实 provider 地址、命令行、注册表值、home 路径不进入共享报告。Plan/Journal/undo/会话路径及原始工具 stdout 不在共享承诺范围。

备份清单示例：schema=rescue-backup-v1，files 数组每项 path（相对 payload）、bytes、sha256。遍历前拒绝目录链接；验证所有清单文件和实际文件覆盖。统计相同不能替代逐文件哈希；哈希一致不能替代干净机器还原、SQLite WAL/SHM 的同一时点快照或历史会话兼容性验证。

## v0.1 不支持

不自动恢复 Skills/Rules/历史，不迁移会话或改 DB；不修改 auth、模型、provider、端口、网络、防火墙、ACL、owner、Defender 或沙盒后端；不修复 SYSTEM/服务/企业任务；不覆盖复杂命令启动语法；不实现备份/还原、付费探测、全盘搜日志和远程救援。存在真实恢复能力的范围是关联自启源的隔离及其 Undo，不能扩大宣传。

## 本轮评审修订

Run 修改使用固定 HKCU/Registry64 的显式可写 OpenSubKey，不创建键、不修改默认值、不覆盖新增值；仅支持保守命名和 String 类型。原有状态与 writer 哈希继续参与事务复核；Undo 在每个实际恢复项前与锁内复核 writer，漂移停止该项。

CheckBackup 清单独立上限 32MiB / 100000 项，同一只读句柄检查长度并读取，读取期间拒绝并发写。不支持规模或无法读取是 BLOCKED；实际哈希/覆盖失配、非法路径是 FAIL；没有逐文件材料是 NOT_TESTED。枚举只保存计数与已列路径集合，不累积文件对象。逐文件逐时采集不能证明多文件同一时刻一致。

配置快照读取失败转 BLOCKED，不使整份报告消失；初始会话快照不完整不得在后续自动判基线 PASS。home 路径合法、存在、运行时关联是不同事实。通道参数仍是声明，A.gui、B.origin、C.origin 均不自动 PASS。