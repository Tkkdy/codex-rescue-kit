# 第三方运行时与许可

项目原创代码与文档采用 MIT。标准许可证文本核对来源：[Open Source Initiative MIT](https://opensource.org/license/mit)。允许商业使用，仍须保留版权与许可声明；公开发布前由维护者确认 contributors 署名及权利归属。

没有 vendored 第三方代码、npm/Python/NuGet 模块、二进制或字体；也没有直接/传递包安装依赖。Pester、PyYAML、Git、Python、PowerShell 和 Windows 均不打入源码候选 ZIP。

| 组件 | 用途 | 发行处理 |
|---|---|---|
| Windows PowerShell 5.1 / Windows / .NET Framework | Windows 系统运行时、任务/注册表/文件 API | 用户自备，适用其系统条款，不再分发 |
| PowerShell 7 / .NET | 可选运行时 | 用户自行安装；本包不包含其源码或二进制，也不声明整个运行时适用本项目 MIT |
| Git | 本地工程提交与候选打包工具 | 开发者自备，不再分发；不是救援运行依赖 |
| Python + 已有 PyYAML | 本次调用宿主已有 Skill 校验器 | 不要求用户安装，不再分发；项目测试不依赖它们 |
| Codex / OpenAI 客户端 | 被诊断的外部产品与可选 Skill 宿主 | 不包含客户端；无关联、背书或修复保证的声明 |

设计时参考官方 Skill 格式和 Windows 沙盒说明，仅保留链接，未复制实现代码：
- [官方 Skills](https://learn.chatgpt.com/docs/build-skills)
- [官方 Windows sandbox](https://learn.chatgpt.com/docs/windows/windows-sandbox)

没有引入历史 01–08 脚本、WorkBuddy 报告原文、Stage2/FinalPass、用户备份、第三方产品实现或凭据。历史事件只作为安全需求背景；本候选不把未复核的单机因果归属当成产品事实。未来引入任何新依赖/原始材料时，必须重新核查许可证及数据权利。
