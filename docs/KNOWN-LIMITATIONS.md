> 历史 V0.1 / Preview 文档。v0.2 当前操作与权限以 [真实修复说明](REAL-REPAIR-v02.md) 和 [收敛验收](REAL-REPAIR-ACCEPTANCE.md) 为准；以下旧证据仅适用于其绑定版本。

> **v0.1.0-preview.1 公共预览提示：** 本版真实 Windows 的 Quarantine/Undo 禁用并返回 `PREVIEW_REAL_MUTATION_DISABLED`。下面涉及实际隔离/Undo 的操作仅供历史实现审阅或未来版本规划，不能在本预览版完成。详见 [预览范围](PREVIEW-PUBLICATION.md)。

# 已知限制

- 真实 Windows Task Scheduler、HKCU Run 和快捷方式 COM 适配器的修改/归属发现未在当前工作机测试；开发侧只验证合成事务引擎、真实文件移动与 XML mock。必须在可丢弃 VM 审查。
- 没有对真实 Codex 桌面/CLI 版本、Sandbox 后端、登录或 GUI 做恢复验收；不提供笼统版本兼容声明。
- B 的来源无法由 JSON 自证；A.gui、B.origin 与 C.origin 保持 NOT_TESTED，正常完整采集也可能退出 3。需要外部工具日志/人工签署。
- B 无权写 session 时仅 stdout 返回 evidence；无法获得 stdout 就缺证。跨身份可能连 Kit/session 都读不到，不放宽权限解决。
- 不能自动推断谁在持续改写配置；默认报告是候选计数和存在性，隔离要求用户提供已确认 writer。命令语法窄，复杂包装、脚本参数、多 Action、服务及其他用户不支持。
- 仅处理已明确归属的自启源；没有自动进程终止、配置修复、备份制作、资产恢复、DB 迁移、ACL/owner 修复或关闭沙盒。
- 配置稳定性是有限采样窗口，秒间修改/复原可能漏检；.env 仅元数据，不能检出保持元数据的内容变化。
- 路径预检不能对抗有权限的本地恶意竞态、hardlink 或管理员；Journal 哈希链不是签名。电源/硬件故障不作完整持久性承诺。
- UNC、设备/扩展路径、ADS、reparse 祖先拒绝；NTFS 短路径优先，长路径不承诺端到端支持。
- 企业管理检测不完整。域/检测到云域加入会拒绝修改，其他企业管理设备也不在支持范围。
- CheckBackup 的字节哈希不证明同一时点 SQLite/WAL、一致恢复或旧会话兼容；真实事故资料与身份归属未用于发布事实背书。
- 原始安全错误被刻意收敛，可能降低排障细节；本地私密计划/Journal 需要人工保管。公开联系地址、签名发行与维护承诺尚未配置。
