# Quillside 0.7.0：Pi Agent 引擎与订阅授权

2026-10-13，构建3。原生SwiftUI/AppKit界面保留；实际生成切换到嵌入式Pi，新增模型目录、浏览器订阅授权和API Key配置。

## 架构与职责

Notes选区、原文批注和角色/Skill仍由Quillside组织。原有Generate接口现在调用PiRuntime，通过stdin/stdout JSON与隔离的Node进程通信。进程实际创建`@earendil-works/pi-agent-core`的Agent，使用`@earendil-works/pi-coding-agent`的ModelRuntime及AuthStorage处理模型、凭据和刷新，再通过`pi-ai`原生服务商适配器发送请求。

这是直接嵌入Pi引擎，不是调用现有Pi CLI，也不是仅复制其协议。固定Pi 1.2.0及官方Node v22.23.2，macOS arm64/x64分发文件由锁定SHA-256验证。UI和Notes交互仍为原生技术栈，应用包含Node，用户不需要另装Node/npm。

Quillside的WritingAgent继续承担文稿任务策略：组织分析、修订、核对及有限修复，检查每条批注、段落数与事实限制。该策略中的每次模型调用已统一由Pi执行；不把这些文稿约束交给通用编码代理决定。模型响应仍只能产生候选稿，不能自行写Notes。

内置Agent不注册文件读写、shell、网络工具、扩展或MCP；不发现用户全局Pi目录、工作目录AGENTS.md或脚本。已批准的Skill文本和资源仍由现有写作流程传入。此前暂缓的MCP/Tools范围不在本版自动扩张。

## 设置中的使用方式

1. 打开“模型连接”，选择服务商。
2. OpenAI / ChatGPT可点击“使用ChatGPT登录”，或填写API Key。订阅与API账户额度分开。
3. Codex（兼容）使用Pi的openai-codex适配器及独立订阅授权；该路径与新的OpenAI官方Responses授权不同。
4. 从Pi模型目录筛选并主动选择模型，点击“使用此模型”。它会出现在Notes的模型选择器中。
5. 可测试、切换默认模型或移除模型项；退出授权仅删除本应用中该服务商的凭据，不影响其他客户端。

目录包含41个服务商，不意味着每个账户都拥有全部模型。具体模型、地区、计划、额度与服务商附加配置以服务商为准。本版没有宣称41个服务商都经过真实账户联调。

旧连接保持原ID、默认选择和Keychain密钥，放入“自定义服务与旧配置”折叠区。它们的生成也通过Pi兼容适配器，不再通过自建ModelClient发送。Ollama沿用已有地址并经其OpenAI兼容/v1接口调用。未自动读取或搬迁旧密钥。

## OpenAI官方订阅路径

核对当前官方文档后，OpenAI已经提供开源客户端“Sign in with ChatGPT”授权使用ChatGPT计划额度的流程。Pi 1.2.0的openai provider包含该流程，使用动态客户端注册、PKCE及本机回调；Quillside传入自己的应用名和稳定的安装UUID。授权后，Pi负责取得与刷新OAuth凭据。

新路径调用`https://api.openai.com/v1/responses`，使用授权的OAuth bearer凭据、`store:false`和`stream:true`。不会将现有Codex auth.json直接当作OpenAI API Key使用。订阅模式移除官方当前不支持的请求字段，包括max_output_tokens、temperature、conversation与previous_response_id；每次请求携带所需材料，不创建后台远程会话。

浏览器授权必须由用户完成；登录按钮或模拟PKCE测试不等于真实订阅推理已验收。实际账户结果单独记录。

## 凭据与会话生命周期

- Pi数据位于`~/Library/Application Support/OpenNotes/Pi/`。AuthStorage的auth.json采用0600权限，目录0700。这是Pi文件凭据存储，包含API Key或OAuth凭据；不应把该目录加入Git、公共备份或配置导出。
- 不读写`~/.codex/auth.json`、`~/.pi/agent`或Magpie凭据；每个客户端保持自己的授权与刷新所有权。
- OAuth刷新锁由Pi的AuthStorage管理，避免并发请求重复刷新同一轮换令牌。Quillside只传递授权交互事件，不实现自己的OAuth刷新协议。
- 每个操作拥有独立子进程。标准输入传递密钥与文稿，不放在命令行参数或环境变量；stderr不转发原始服务商错误，UI只接收经过归类的错误。
- SSE生成在完成事件后才能成为候选；输出限制2MB，输入合计限制1MB。单请求240秒、90秒无有效进展停止；登录最多10分钟。
- 停止、离开原笔记、休眠、退出仍由现有AIRunRegistry触发取消。Pi中止请求并清理Agent状态，必要时终止子进程。会话仅存在于进程内存；任务完成后没有常驻模型连接。

## 实机发现与修复

首次分发包登录在打开浏览器之前失败。Pi通过变量路径动态加载OAuth，通用esbuild没有跟踪这些模块；源码级登录测试不能覆盖该问题。已使用Pi公开提供的registerBunOAuthFlows静态注册（这些Node模块也适用于本应用的Node单文件包），加入直接启动dist/worker.mjs的登录取消回归。已安装、签名后的worker也确认能进入OpenAI授权回调并退出。用户随后完成新的浏览器授权，Quillside显示已授权订阅，官方Responses模型GPT-6.1 Sol返回OK。

## 已完成的验证

- Pi集成测试8项：服务商/模型目录、私有凭据保存/单提供方登出、真实Pi引擎驱动本地SSE、取消网络请求、截断输出拒绝、错误脱敏、ChatGPT登录的PKCE/稳定host ID/取消恢复，以及分发包自身的OAuth加载与取消。
- 原生回归261项中257项执行通过，4项截图/实机数据库条件跳过；新Swift进程测试覆盖Unicode流、缺少最终结果、异常输出、取消前后与超时、旧ModelConnection兼容。
- 修复了测试夹具的临时对象生命周期问题；超时测量直接针对后台watchdog，避免把全量UI测试占用主线程的排队时间计入进程超时。
- 安装包中的已签名Node与打包worker实际启动，返回Pi 1.2.0及41个服务商；原生设置加载模型与授权控件。
- App和内置Node严格签名检查通过；原有5项MIT组件外，新增48项Pi/Node分发组件许可独立列入清单并随包分发。

本地证据：build/pi-research/，含node-tests-final.log、full-regression-final.log、swift-pi-final.log和构建日志。真实订阅已完成授权及官方Responses测试，返回OK；Notes闭环已通过，[完整验收](PI-REAL-ACCEPTANCE-0.7.0.md)记录单句和整篇首次写回、一次撤销以及五条批注保留。

## 来源

- [Pi官方仓库](https://github.com/earendil-works/pi)，研究时main提交7d75a0e3eb273dff753d49c066ea29fbe7b3b6f6；安装依赖由runtime/pi/package-lock.json锁定。
- [Pi SDK](https://github.com/earendil-works/pi/blob/7d75a0e3eb273dff753d49c066ea29fbe7b3b6f6/packages/coding-agent/docs/sdk.md)
- [Pi服务商配置](https://github.com/earendil-works/pi/blob/7d75a0e3eb273dff753d49c066ea29fbe7b3b6f6/packages/coding-agent/docs/providers.md)
- [OpenAI开源客户端订阅授权](https://developers.openai.com/siwc/token-sharing-open-source)
- [OpenAI模型与推理](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [当前预览限制](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)

Quillside源码继续MIT开放；Pi/Node分发依赖保留各自MIT、Apache-2.0、BSD、ISC及Unlicense条款。正式发布仍需要Developer ID签名/公证，本轮是本机开发签名安装。
