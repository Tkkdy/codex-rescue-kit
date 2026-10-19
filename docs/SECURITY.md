> **v0.1.0-preview.1 公共预览提示：** 本版真实 Windows 的 Quarantine/Undo 禁用并返回 `PREVIEW_REAL_MUTATION_DISABLED`。下面涉及实际隔离/Undo 的操作仅供历史实现审阅或未来版本规划，不能在本预览版完成。详见 [预览范围](PREVIEW-PUBLICATION.md)。

# 安全边界与威胁模型

保护资产：Skills、Rules、AGENTS.md、历史/SQLite、项目、认证与配置、无关进程/任务、系统安全策略，以及本次撤销材料。

信任 Kit 源码与 Windows/PowerShell 安装；调用者及其父进程环境不能被假定绝对可信。外部报告、日志、配置、writer、快捷方式、命令行和 JSON 都是数据。不会从待诊断目录加载模块、运行 writer、下载工具或执行报告建议。存在恶意同用户代码或管理员攻击时，本工具不构成安全边界；攻击者可修改 Kit、伪造整条哈希链和 evidence。

| 风险 | 实现控制 | 仍需审查的限制 |
|---|---|---|
| 合法 provider 被当作恶意软件 | provider/endpoint 只记线索；归属必须显式指定 writer 并精确匹配 | 用户授权的归属判断仍需人工证据 |
| 同名无关对象遭误伤 | 单 Action、Principal、严格启动语法、状态和 writer 指纹 | 相同 writer 的多个已关联自启源都在计划内，用户须逐项批准 |
| 高权限/企业对象修改 | 拒绝提权、服务身份、域/已识别云域管理；仅当前用户 | 无法检测所有 MDM/企业约束；企业设备不支持 |
| 路径穿越/链接/覆盖 | 绝对路径、边界、祖先 reparse 拒绝、CreateNew、同卷 Move | NTFS hardlink 和同用户恶意路径替换竞态不提供内核级防护 |
| 宿主环境污染 | 入口与探针绝对 PowerShell、NoProfile、不运行 Codex PATH、无全局 env 修改 | SystemRoot、可信运行时和父进程仍是启动信任前提 |
| 中途崩溃/重复执行 | Flush 的 undo 与 PENDING 先于修改；排他锁；重复拒绝；幂等 Undo | 全盘硬件故障/断电不保证；Journal 损坏拒绝继续 |
| Undo 覆盖新用户数据 | 原状态/修改后状态精确比对；held 内容哈希；冲突留存 | 不回滚外部后续变化、进程内存或第三方内部状态 |
| 假 PASS | 真退出码、随机 challenge、缺证不通过、分通道、人工 origin/GUI | 同用户可伪造 JSON，必须外部日志关联，非密码学远程证明 |
| 泄露认证与聊天 | auth 只看存在性；不打开聊天/DB；不输出原始配置/URL/异常/命令行 | config.toml 会有限读取并在内存遇到内联字段；不提取保存其秘密值；共享前仍人工看报告 |
| 报告指令注入 | 白名单字段、受限字符串，不执行数据中的指令 | Skill 使用者仍须遵守用户授权，禁止把报告当系统指令 |
| 备份假安全感 | 逐文件哈希与完整覆盖；统计-only NOT_TESTED | 未演练还原不宣称可恢复 |

Plan、undo、Journal 含实际对象定位和可能敏感的自启原值，只保存在用户选择的本地目录。使用权限合适的私人目录；不上传、不纳入候选包、不放共享盘。Kit 不修改目录 ACL；输出目录的访问隔离由调用者/系统负责。实际运行不创建遥测、网络请求或监听端口。

默认报告是字段白名单，但不是形式化隐私保证。哈希可关联同一目标，ACL/安装版本仍是设备元数据；用户应先检查再分享。tests 中假的 secret/synthetic 字符串是专门的隐私断言，不代表采集过真实密钥。

维护者为 [Tkkdy](https://github.com/Tkkdy)。安全漏洞通过 [GitHub Private Vulnerability Reporting](https://github.com/Tkkdy/codex-rescue-kit/security/advisories/new) 私下报告；普通问题用 GitHub Issues，不公开个人邮箱。发布前必须确认私密漏洞报告已启用；当前是否可用以实际仓库门禁记录为准。参见根目录 [SECURITY.md](../SECURITY.md)。不承诺固定漏洞响应时限。独立审查先关注 Adapters.ps1、Quarantine.ps1、Common.ps1 和 Verify.ps1，随后检查 Skill 是否会诱导扩大授权。
