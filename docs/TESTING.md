> 历史 V0.1 / Preview 文档。v0.2 当前操作与权限以 [真实修复说明](REAL-REPAIR-v02.md) 和 [收敛验收](REAL-REPAIR-ACCEPTANCE.md) 为准；以下旧证据仅适用于其绑定版本。

# 测试与兼容性矩阵

测试数据全部由 tests/Run-Tests.ps1 生成：虚构配置、无效认证文本、文本形式的虚构快捷方式、JSON 任务/Run 适配器和空壳历史载体。没有复制真实用户文件，没有调用 Codex CLI、模型或登录服务。发布复现应使用新建可丢弃目录，不复用真实 home。

## 实测范围

| 组合/通道 | 结果与依据 | 不代表什么 |
|---|---|---|
| Windows 11 x64，OS 10.0.26200.0，NTFS，PowerShell 7.6.5 | 62/62 合成回归；见 evidence/pwsh-results.json | 不代表所有 PS7/Codex/沙盒后端 |
| 同主机 Windows PowerShell 5.1.26100.9711 | 62/62 合成回归；见 evidence/ps51-results.json | 长路径整个救援流程不作保证 |
| rescue.cmd → Windows PowerShell 5.1 | 实际子进程、污染 PATH/PATHEXT/APPDATA/CODEX_HOME、默认 Diagnose、真实退出 3 | 不证明 B 或 GUI |
| 三个原生探针 | 实际 Get-Location/版本/Get-Date；真实非零退出和 1ms 超时失败测试 | 合成 B 标记不等于实际 Codex 工具来源 |
| Task XML 指纹 | 在模块内 mock Windows cmdlet：保留 Trigger Enabled 漂移，排除自身 Settings.Enabled | 未在真实 Task Scheduler 修改任务 |
| Startup 文件事务 | 真正创建、Move、哈希校验、Undo 虚构 .lnk 字节 | 未创建/解析真实 WScript 快捷方式 |
| Task/HKCU Run 事务引擎 | JSON 合成适配器真实持久写入、中断与恢复 | 真实 Win32 任务/注册表修改适配器尚未实机验收 |
| Sandbox elevated/unelevated/mxc | 只解析配置线索；虚构 ACL/错误元数据 | 无真实后端兼容/ACL 修复证明 |
| A GUI、B origin、登录、UAC、真实只读/写边界 | NOT_TESTED | 不允许写成自动验收 PASS |

日期和实际运行时以 evidence 文件为准。兼容承诺只限上述合成实现组合；公开发布前的真实可丢弃 Windows 矩阵尚待独立 Agent。

## 故障覆盖

正常观测、合法第三方 provider、真实有界周期改写、同名无关对象与活跃 writer、双 CLI 和显式 home 混淆、旧 Sandbox 错误/保护 DACL、mxc 不依赖旧目录、用户资产保护、假秘密不导出、恶意指令不执行、PATHEXT 和入口四项子环境污染、中文/空格/长路径尝试、路径穿越/UNC、reparse 拒绝、统计-only 备份、同长内容损坏、未列出的 WAL、退出码/challenge/缺证/超时、事务中断（APPLIED 前后）、Journal/undo 损坏、writer/对象漂移、Undo 冲突/重复/预览、held 缺失、B 身份不同及目标 home 不同、JSON 日期对象/字符串的 UTC 一致性。

通过断言验证没有发生：资产树字节未变、无关对象 Enabled 未变、活跃进程不被终止、新用户快捷方式不被覆盖、隐私 sentinel 不进报告、越界路径被拒绝、失败证据不升级 PASS。环境变量污染只存在测试子进程或受控临时变量，finally 恢复；不修改用户/机器环境变量。

合成 FixtureFault 是结果注入，用于验证汇总拒绝假 PASS；另有真实子进程失败/超时回归。fixture 中 fake-writer 文件从不执行，周期改写器为测试本身新生成的固定代码，只写自己的虚构 config.toml。

## 复现与检查

在两个已安装的 PowerShell 中分别运行 tests/Run-Tests.ps1，输出目录自动选项目 out 或 .test-runs。入口联调运行 tests/Smoke-Entry.ps1。tools/Test-Source.ps1 做全部源码解析、有限敏感模式和禁止操作扫描；它不是商业 SAST 或安全审计。不安装 Pester 或依赖。

失败时先修复相关实现再跑受影响回归。此前第一轮事务实现的 File.Replace 空路径问题已修复，后续完整回归通过；不能把中断后无实际修改的 Undo 成功当作恢复能力证据。

source-manifest.json 记录被测试核心源码与测试入口的 SHA-256，用于候选包关联；测试摘要是开发侧证据，仍可由同用户伪造，需要独立复核。候选工具逐文件验证 ZIP 与提交源码字节一致，不包含 fixture、缓存、真实用户数据或 .git。

## F-01～F-08 补丁回归

tests/Review-Cases.ps1 增加 14 个定向场景，由主套件执行，总计 62 项。旧 Throws 已全部改为精确预期错误码，修改拒绝场景核对 fixture 哈希；摘要 expected_refusals 可核验具体拒绝原因。真实 API 不由 mock 代替，见 REVIEW-RESPONSE.md 的逐项证据边界。

tools/Invoke-ReviewChecks.ps1 分别捕获 PS5.1/7 的回归、入口、60 秒窗口、静态检查四个子进程。evidence/*-commands.json 与 *.stdout.log / *.stderr.log 是基线轮次的运行时文本捕获；命令记录将工作目录与引擎目录用占位符/文件名哈希表示，文本经 StreamReader 解码、重编码 UTF-8 后保存，保存后未人工编辑；不能称为原始 pipe 字节（F-10 纠正）。docs 与交接任务书属于整理记录。更深层测试内部子命令没有完整原始 transcript 时，不补造记录。

本轮发现测试记录器直接用 ProcessStartInfo 从 PS7 启动 PS5.1 时，继承的模块路径导致 Get-FileHash 不可用，产生 24 PASS/38 FAIL；失败缓存保留 out，不纳入通过证据。记录器修正为仅在子进程使用对应引擎自身 Modules 目录，避免加载用户或另一引擎的模块；不改父进程、用户或机器环境变量。这是隔离测试条件，不是对任意污染宿主环境的产品兼容承诺。

>2MiB 合法清单测试用 JSON 空白填充验证解析边界，没有做数万实际文件压力测试；32MiB 超限为明确 BLOCKED。真实 Windows 独占锁只发生在合成 config/payload。没有修改真实 ACL、Run、任务或当前 Codex。

## F-09 / F-10 定向复验

基线 62/62 x 两引擎继续复用，绑定 6a39c247cc4f；本次只运行 task* 定向 8/8 x 两引擎、编码边界和静态检查，不声称当前提交做过完整 69 例回归。新增 tests/Task-State-Cases.ps1 使用 Windows cmdlet mock，真实任务仍 NOT_TESTED。运行 tools/Invoke-ReviewChecks.ps1 -EnginePath <已安装引擎> -Label ps51或pwsh -RunId <新目录名> -PatchOnly，详细证据与复用边界见 PATCH-F09-F10.md。
