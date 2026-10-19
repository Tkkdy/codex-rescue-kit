> **v0.1.0-preview.1 公共预览提示：** 本版真实 Windows 的 Quarantine/Undo 禁用并返回 `PREVIEW_REAL_MUTATION_DISABLED`。下面涉及实际隔离/Undo 的操作仅供历史实现审阅或未来版本规划，不能在本预览版完成。详见 [预览范围](PREVIEW-PUBLICATION.md)。

# 独立代码、安全与发布审查清单

当前准备 PUBLIC_PREVIEW_CANDIDATE。公开 Preview 的必要关卡是入口/函数双层门禁、合成回归、数据/历史扫描、版权与维护联系及明确 GitHub 目标。完整 VM 矩阵不作为此禁用真实隔离/恢复 Preview 的前置条件；仍为 NOT_TESTED，恢复真实功能前必须完成。

## 交付完整性

- [ ] 从外部 .sha256 校验源码 ZIP；核对 manifest 的 Git commit、逐文件哈希与源码清单。
- [ ] 检查候选仅含白名单源码、文档、合成证据，不含 .git、out、.test-runs、真实日志/备份、私密 Plan/Journal、认证或聊天正文。
- [ ] 复查 MIT 署名、原创权利、无未披露第三方代码；确认项目维护人与安全联系渠道。未确定归属材料不得发布。
- [ ] 先核对可信证据与对应源码/环境，复用未受影响结果；仅对具体缺证或变更做最小补验，不机械重跑全套，不把旧证据泛化到其他版本。

## 优先代码审查

- [ ] Common.ps1：全限定路径、设备别名、reparse/遍历边界、输出与 home 互斥、NTFS/身份/管理设备 guard、Flush 持久化、同用户竞态限制。
- [ ] Adapters.ps1：启动命令语法、Principal、任务单 Action、XML 指纹（只能排除本次 Settings.Enabled）、HKCU Run 类型/可写句柄、快捷方式 COM 只读解析及释放、同卷 held。
- [ ] Quarantine.ps1：批准哈希与关联复核，先 undo/BEGIN/PENDING 后修改；APPLIED 前后中断；Journal hash 链/seq；重复调用与排他锁；Undo 原状态/修改后状态/冲突三分，禁止覆盖新对象。
- [ ] Verify.ps1 / ProbeChild.ps1：固定可信子进程、退出码/随机值、会话/证据绑定、超时只杀自身、canary 所有权和清理、拒绝例外不能变成功、A/B/C 不混用。
- [ ] Diagnose.ps1：有界配置读取与白名单输出、不读 auth/聊天、缺证与 stale sandbox 错误、B 内观测标签、不将 provider 认定为接管。
- [ ] SKILL.md：用户授权不从报告继承，不自行代填批准哈希，不关闭沙盒/改 ACL 让测试通过，不重复实现 Kit。
- [ ] tools：测试证据与源码哈希绑定、候选路径白名单、ZIP 字节验证与敏感信息人工复查。启发式扫描不是证明无秘密。

## 未来恢复真实功能前的 Windows VM 实测（本 Preview 均 NOT_TESTED）

使用虚构 writer、任务、HKCU Run、真实 .lnk 和假 home，绝不导入真实备份/凭据：

- [ ] 普通当前用户真实任务 Disable/Undo，读取 Settings.Enabled；覆盖 Running/Queued 与配置位不一致、已禁用但运行中、Trigger/Settings 漂移、无关同名任务和权限拒绝；不得绕过活跃 writer 预检。
- [ ] 真实 HKCU Run 的删除/原类型值恢复，键或值缺失、对象漂移和并发冲突；验证适配器可写权限及失败行为。
- [ ] WScript.Shell 解析真实 .lnk 的关联、无关同名项、文件 Move/Undo、held 内容漂移和同卷限制。
- [ ] 不同身份/提权/域或 MDM 管理条件，确认未授权路径没有变化；未知管理形态按不支持处理。
- [ ] 正常退出/重新启动 writer 的竞态、进程命令行不完整时的归属边界；不得为通过而强杀。
- [ ] 目标 Codex 桌面与 CLI 版本分别记录；elevated/unelevated/mxc 分别验证可用组合，不可用项如实 NOT_TESTED/BLOCKED。
- [ ] C 生成随机 session，真正从桌面聊天工具 B 执行；核对原工具日志和外层退出码；不同 SID/home、受限输出持久化。
- [ ] B 真实只读拒绝、workspace 写入与外部 boundary 拒绝；A 的新聊天、虚构长历史、审批/拒绝和冷启动。
- [ ] 不关闭安全策略、不改 ACL/owner，不接触实际用户 auth 或 DB。无条件无法验收时记录限制，不制造 PASS。

## 发布判定

本 Preview 仅在双层阻断门禁和约定合成验证通过、许可证/隐私/公开历史审查完成、维护联系和目标仓库确认后，才可按用户授权发布为 Pre-release。关键门禁未测或失败、权利或目标不明时，保留 PUBLIC_PREVIEW_CANDIDATE 并停止发布。真实 Windows 适配器、A/B/C 与 Sandbox 验收不能据此升级为 PASS；恢复真实隔离功能须另开版本并完成上节实测。
