> Beta发行上下文：下文为 b09b171 及此前的开发/审查记录，原“未发布/不Push”描述其当时边界。本次用户已授权 v0.2.0-beta Experimental Pre-release；不改变下文真实验收 NOT_TESTED 结论。当前发行说明见 BETA-RELEASE-NOTES.md。

# v0.2 开发与验证报告

状态：REAL_REPAIR_REVIEW_READY（GPT F-11/F-12 已修订，本地候选；真实救援仍未验收）。上一候选 REAL_REPAIR_REVIEW_READY（本地候选，独立复审前不等于安全审查通过；真实救援未验收）。

## 实际实现

- Backup：完整显式 home、私有新目录保护 ACL、磁盘空间/固定 NTFS/非重解析校验、只新增复制、读句柄锁、逐文件大小/SHA256/目录清单、源前后及目标覆盖验证；中断保留副本，Resume另建唯一副本。备份不是干净数据库还原证明。
- StopWriter：确证脚本关联，PID/原生创建时间/owner/可执行与命令哈希/parent 绑定；可验证正常关闭优先，强停每对象额外哈希批准；实际进程句柄阻止 PID复用误杀，自身/祖先进程和其他用户拒绝。内存不可撤销。
- Quarantine/Undo：复用 Task/Run/Startup 事务，保留 F01–F10 保护。两层 Preview 永久门禁替换为入口拒绝+模块版本化同次计划能力；前置启动变更使用独立持久 Undo，配置隔离仍要求完整备份。PENDING/状态核查/冲突拒绝保留。
- Official：只对明确批准的 config.toml/auth.json 同卷移动到私有区；不正则重写 TOML，不动 Skills/Rules/AGENTS/SQLite/历史。本人官方登录/必要 Store 操作卡和暂停，Resume不会再次隔离新登录文件，Undo拒绝覆盖它。
- Assets：核验旧备份源清单，逐文件选择/显式来源审阅/只复制缺失目标，未知来源候选；发现、加载、可调用分开。显式外部项目只读快照，不默认备份，不写项目/Git/Worktree；本补丁将未验证项目备份列为执行前阻塞。
- Sandbox：只读私密 ACL 快照和脱敏摘要；精准规则匹配的单对象 owner-only 人工变更卡，不自动提权或改变ACL。
- Repair/Resume：持久状态、Journal、逐次完整计划哈希批准、至少60秒 config hash+mtime、已批准入口/进程复核、实际观察结果、挑战会话与核心五项验收卡。旧会话续聊仅信息项。GUI/B/C来源、官方模型与重启缺证保持 NOT_TESTED/PARTIAL_RECOVERY，不凭 JSON升级成功。

## 测试与证据复用

| 检查 | PowerShell 7 | Windows PowerShell 5.1 | 证据 |
|---|---|---|---|
| 新闭环与安全定向 | 22/22 PASS | 22/22 PASS | evidence/v02/*-targeted-results.json |
| 旧共享模块必要回归 | 69/69 PASS | 69/69 PASS | *-legacy-reused.json（从本轮完整运行派生子集，非新增重跑） |
| 最终 CLI 入口、Repair/Undo DryRun | 1/1 PASS | 1/1 PASS | *-entry-results.json |
| Sandbox 人工卡最终字段 | 1/1 PASS | 1/1 PASS | *-sandbox-results.json（同名用例覆盖最终小差异） |
| 独立复审两项补丁定向 | 2/2 PASS | 2/2 PASS | *-review-patch-results.json |
| 全部 PowerShell 语法及有界隐私/禁用操作词检查 | PASS | PASS | static-results.json |

上述是按改动范围复用的组合覆盖，不声称最终树一次完整跑过94例。旧回归69例已在本轮执行，不机械再次重跑。Windows PowerShell子进程只选其自身 Modules 路径，未改持久环境变量。测试普通独立进程运行，未注入真实 Task/Run/Startup。

两个完全虚构故障：持续写配置原生子进程，及误隔离的 Skills 文件；另有虚构 Sandbox ACL 样本。原生闭环实际停进程，备份、移走 config/auth、禁用模拟入口、暂停人工卡、60秒稳定、Undo恢复原字节。sessions/Skills/Rules/AGENTS/SQLite及显式项目未受批准部分有前后哈希断言。所有文件/进程写入限夹具目录；唯一真实 ACL 创建测试只保护新建虚构目录，不改现有目录。

安全测试覆盖：精确批准、合法第三方不自动隔离、保护范围、进程身份漂移、额外强停批准、writer/config漂移、备份中断/复制期间源变化、空间不足、备份内容及清单损坏、Journal损坏、文件移动后中断、Resume/Undo、新登录文件冲突、来源不明Skills、Sandbox匹配、DryRun无变更。

## 已发现并修复的测试失败

首轮新模块16/17，原生进程身份失败；全量回归PS7 89/90、PS5.1 89/91。进程错误来自时间表示及 CIM微秒与原生句柄100ns精度不一致，改为绑定原生完整创建时间并精确复核。PS5.1额外DryRun失败发生于开发更新测试文件而在途进程仍加载旧模块，最终定向与独立入口已通过。保留原失败结果与stdout/stderr在私有交付目录，不篡改为全绿。此后只重跑受影响新模块与最终入口/Sandbox小差异，不重复旧69项。

## 验收未完成项

真实 Task Scheduler / HKCU Registry64 / Startup COM 写入及OS级故障：NOT_TESTED；官方GUI/本人OAuth/新模型会话/原项目真实工具B/真实重启：NOT_TESTED；Sandbox管理员owner修复及真实工具复验：NOT_TESTED；数据库干净环境还原：NOT_TESTED。未获备用用户环境与精确真实对象授权，未在现用Codex、认证、Skills、任务/Run/Startup、DB或ACL上试验。

真实用户操作清单与最小有界API测试在 REAL-REPAIR-ACCEPTANCE.md。没有要求以完整VM项目阻挡开发；缺失这些证据同时意味着候选不能声称“真实Windows救援已经成功”。

## 来源与隐私

新代码由本任务原创实现，基线37a32e0来自完整开发历史，公开版权/安全联络文件从fcfc5b4同步；无客户原始脚本/数据/凭据/备份、无新增依赖或二进制。候选只白名单导出已提交文件，不带.git、out、.test-runs和私有v02-validation。原冻结commit、包及公开Preview未改、未推送。

## 独立复审补丁

独立 Agent 首轮 PATCH_REQUIRED，两项：计划7天过期误阻止原事务Undo；SandboxGuide复用已有目录缺私有ACL检查。已最小修复：过期仅阻止Forward，原事务须重新明确批准Undo且继续检查hash/上下文/Journal/备份/漂移，嵌套capability同规则；Sandbox在任何私密采集/落盘前统一检查目录，不改已有ACL。两引擎各2/2定向通过。无新增旧套件重跑。复审结果另见 REAL-REPAIR-REVIEW.md。

## GPT F-11/F-12 修订（基线 11647c8）

F-11：批准父计划绑定多个 writer 和各自启动子计划/hash，先持久保存所有启动恢复材料，再禁用确证入口、按批准顺序停进程、完整备份及隔离。选择 CaptureStoppedConfiguration 才允许批准后的停写快照，默认保留原漂移拒绝。旧 v2 执行计划拒绝 Forward，但保留原 Undo。

F-12：任何 Undo 文件变更前，全量检查必需启动事务目录、undo/Journal 哈希绑定、对象状态及 held 快捷方式。预检失败不恢复 config、不返回 PASS；开始撤销后失败记录 PARTIAL/CONFLICT。无 Home 备份的前置启动 Undo 独立可用。独立 Agent 另发现 startup-only 部分 Undo 重试不应要求从未创建的配置快照，已定向修复并加入用例。

F-13 保留重大适用性限制：Home/Output 同卷，跨卷在计划阶段明确拒绝；本轮未实现跨卷备份，不宣称复刻 C:→D: 原事故布局。F-14：外部项目未备份则 scope_blockers/unbacked_projects 明示，执行前阻断；项目盘点不是备份证据。未知复杂启动命令固定标为未分析，不能断言全部接管源已清除。

本轮仅复测受顺序变化影响的 v02 调用链与新增复活/缺失撤销材料用例，未机械重跑旧69项。本轮最终证据为每引擎新增7条不同用例均PASS、受影响v02流程25条组合覆盖均PASS；不是最终源码一次全量运行。PS7新增为6/6+独立复审重试补验1/1，PS5.1新增7/7；计划阻塞最终显示另各1/1。PS7 v02流程25/25；PS5.1原运行24/25，CLI入口唯一失败，定位为含中文UTF-8无BOM在系统代码页下解析失败，增加BOM后仅复验入口，PS5.1与PS7各1/1通过；其余24例复用。gpt-patch-execution-index.json逐运行列原始结果哈希、退出码和筛选条件；*-gpt-*-results.json明确为组合证据，原失败结果保留于交接包raw fixtures。历史失败/历史PASS均保留原时间与适用范围。

本轮没有保存逐运行原始stdout文件（控制台输出在工具记录中），不补造stdout；results.json、事务Journal、state、备份清单、合成文件和revival-loop退出码记录均实际保留。脱敏交接副本保留原哈希锚点，脱敏后不伪造新的运行Journal链；副本与原始哈希分别列示。

独立 Agent 已逐文件核对本轮补丁及最终证据，判定 PASS（限代码与合成验证）。原生双进程摘要 first_exit/writer_exit 为 null，未采得退出码；退出已由 WaitForExit 断言确认，不补造为0。reviver_exit=-1、repair_exit=3、undo_exit=0 保留实际值。

## v0.2.0-beta发行差异验证

仅新增计划/确认/执行/Undo风险提示和发行材料。PS7与PS5.1各Beta定向2/2、CLI/DryRun1/1通过；完整修复能力以虚构备份→隔离→Undo用例确认，未新增永久诊断锁。旧修复链结果按b09范围复用，不重跑完整矩阵。发布前静态、凭据/隐私、来源/版权、证据绑定与白名单打包检查；本次用户明确授权Experimental Beta，完整VM不是发行前置；真实API/GUI等NOT_TESTED状态不变。明细见evidence/beta/publication-checks.json。
