# 构建 Quillside

需要 macOS、Swift 6.2+（Xcode或对应Command Line Tools）、Python 3.10+、ripgrep、Node/npm。Node固定版本见根`.node-version`，Pi最低要求见`runtime/pi/package.json`。最终App包含Node，普通用户无需额外安装。

```sh
# 在仓库根目录
node --version
swift --version
npm ci --prefix runtime/pi --ignore-scripts
python3 scripts/check-open-source.py
./scripts/verify-stage1.sh
OPENNOTES_CODE_SIGN_IDENTITY=- ./scripts/bundle-app.sh release
open build/Quillside.app
```

自动检查使用临时SQLite和本地模拟模型，不读取个人Notes或真实密钥。4项截图/实机数据库用例默认不启用。首次构建会下载锁定依赖与经SHA-256验证的官方Node；后续依赖锁改变会刷新node_modules。

构建最低系统14.0；当前实机结果不覆盖所有较新系统与Intel。完整Xcode和Command Line Tools使用不同Framework路径，脚本依据`DEVELOPER_DIR`识别。安装多套Xcode时可显式指定该变量。

本地不指定签名时，脚本优先复用仓库外的本机开发身份，再查Apple Development，最后使用ad-hoc。显式`OPENNOTES_CODE_SIGN_IDENTITY=-`可强制临时签名，不需要付费Developer Program。不要覆盖日常使用的已授权App进行测试；签名变更可能要求重新授予权限。

正式发行使用Developer ID与公证，见[发布指南](RELEASING.md)。历史数据目录、Keychain服务与bundle ID保留兼容，不能直接改名迁移。

官网构建不需要macOS：

```sh
python3 site/build.py
python3 site/check.py
node --check site/assets/site.js
python3 -m http.server 4173 --bind 127.0.0.1 --directory site/dist
```

纯脚本发行保护回归：`python3 scripts/test-release.py`。构建仍存在部分Swift隔离/弃用告警，当前不是无告警工程；修改时应缩小范围并保留Notes写回和撤销验收。
