# v0.2.0-beta — Experimental / Beta

**GitHub Pre-release；非生产级稳定。真实 Windows Task Scheduler/HKCU Run/Startup COM 写入，以及 GUI/OAuth/模型、原项目真实工具和重启验收仍 NOT_TESTED。公开Beta不是这些项目已验收的证明。**

基于 b09b171cb9a0f0c07829cfe54a3236d33281098b 独立补丁复审 PASS。默认 Diagnose；真实修复必须显式选择、审阅范围并确认计划完整哈希，强停逐进程额外批准。Beta 保留可执行 Backup、Quarantine、Resume、Undo、Skills恢复与官方登录引导，未把它们锁回诊断器。

## 实际修复能力

全部启动Undo快照持久化 → 禁用确证复活入口 → 精确停写 → 完整Home逐文件校验备份 → 定向隔离批准的config/auth → 官方本人登录暂停 → Resume/Verify → 冲突安全Undo。支持多writer显式计划；启用CaptureStoppedConfiguration须事先批准停止后快照策略。Undo在改任何文件前全量预检启动材料；备份失败时可凭独立启动快照撤销前置修改。进程内存、人工登录/Store操作不可撤销。

## 风险与适用性限制

- 未完成真实启动API验收；错误归属和强停可能影响使用状态。仅在已确认对象及精确授权下操作，不在当前活跃Codex工具环境试验。
- 备份不完整/漂移、权限/归属不明、Undo材料缺失/冲突均安全停止。不得手改记录或跳过保护。
- Home/Output仅同卷固定NTFS；跨盘备份不支持。Home外项目不备份；外部ProjectRoots缺备份验证会阻塞。不要声称项目盘点等于备份。
- 复杂启动命令与未知来源未处理，不能保证清理所有接管源；需真实观察及本人重启确认。
- 新官方config/auth阻止Undo覆盖；旧历史可读但不能续聊属于兼容性限制。数据库、会话provider、项目Git与同名Skills不覆写。
- 私有备份可能包含认证与聊天内容；不上传Issue/聊天/公开网盘。

## 验证与发布检查

两引擎各7条新增用例和25条受影响流程为组合通过证据，旧69条按未受影响范围复用。原PS5.1 CLI失败及BOM修复后的单项复验保留。未机械重跑完整矩阵。Beta只增加风险文案/发布材料及确认显示，复验默认Diagnose、确认/拒绝路径、DryRun与打包；没有在宿主实施真实修复。

来源/许可/凭据与白名单打包检查通过后发行；MIT Copyright (c) 2026 Tkkdy，运行时不随包分发。保留历史Preview Release/tag/资产。下载源码ZIP并按`.sha256`和manifest核对；操作指南见[REAL-REPAIR-v02.md](REAL-REPAIR-v02.md)，安全报告见[SECURITY.md](../SECURITY.md)。
