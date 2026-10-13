# 0.7.4 开源发布回执

2026-10-13。用户已确认个人账号、GitHub Pages默认地址与自动发版顺序，GitHub CLI授权由用户完成。

| 项目 | 实际结果 |
|---|---|
| 源码仓库 | https://github.com/Asxing/quillside ，public，GitHub识别MIT |
| 官网 | https://asxing.github.io/quillside/ ，HTTPS，简体/繁体/英文各5页 |
| 版本 | https://github.com/Asxing/quillside/releases/tag/v0.7.4 ，源码预发布 |
| 标签提交 | `1618907fa3f2f92a3447c06b3afd69c8fe2eea89` |
| 远程CI | https://github.com/Asxing/quillside/actions/runs/38406996913 ，两个job通过 |
| 自动发版 | https://github.com/Asxing/quillside/actions/runs/38407914028 ，prepare/native/publish/website全部通过 |
| 私密报告 | 已启用Private vulnerability reporting |
| 主分支规则 | 要求repository-and-site/native检查，禁止force push与删除；管理员可按仓库规则维护 |
| Pages环境 | 允许main分支及v*标签部署，使用workflow构建 |

公开Release实际包含源码ZIP、单独SHA-256、release-metadata.json和SHA256SUMS。已重新下载，校验433个源码文件的哈希与SOURCE_MANIFEST中的提交；此Release没有App二进制。

默认标签发版模式为source。preview模式可生成明确标注UNNOTARIZED的ad-hoc测试包，本机已验证其打包和资产保护；未将它作为已公证正式版发布。notarized路径已准备，仍需Apple发行身份、实际公证和新用户安装/升级验收。

本轮实机工作没有更换用户已有的0.7.3应用，没有使用个人模型密钥发起请求。GitHub公开源版本0.7.4主要包含开源文档、构建及发布流程整理。

首次CI失败暴露了runner没有ripgrep、loopback模拟HTTP服务器执行不必要反向DNS的问题，已补齐依赖并让fixture不依赖DNS。首次Release已成功发布源码，但复用Pages部署的调用身份是标签，被仅允许main的环境规则阻止；增加v*策略后重试部署job成功。标签触发已由Release负责，普通CI后续仅接收分支push，避免重复跑相同回归。

本机证据在忽略目录`build/release-preparation/`：回归日志、actionlint、干净源码构建、源码与测试包资产清单、公开Release下载、HTTPS检查和线上截图。线上结果不能替代Developer ID、公证或其他Mac的App安装验证。
