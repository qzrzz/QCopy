# QCopy 开发与发布流程

QCopy 使用 Bun + TypeScript 脚本驱动 XcodeGen 和 Xcode 构建，命令可以通过 `npm run` 或 `bun run` 执行。

自动更新机制对齐 **Qjiao**：Sparkle + 完整 ZIP + `generate_appcast`（最多 3 个 delta）+ 本机 `release/` 历史缓存。

## 日常开发

```bash
npm run dev
```

流程：

1. 执行 `xcodegen generate`
2. 编译 Debug 配置到 `build/DerivedData`
3. 启动 `QCopy Dev.app`，终端继续显示 stdout / stderr

Debug 构建**不会**启动 Sparkle（避免开发时弹出更新提示）。Release 构建会在启动后按需静默检查更新。

## 版本号

版本号来源是根目录 `package.json`，Build 号来源是 `project.yml` 的 `CURRENT_PROJECT_VERSION`。

```bash
npm run version              # patch
npm run version -- minor
npm run version -- major
npm run version -- 0.3.0
```

## Sparkle 密钥（首次）

先构建一次以拉取 Sparkle 工具：

```bash
xcodegen generate
xcodebuild -project QCopy.xcodeproj -scheme QCopy -configuration Debug \
  -derivedDataPath build/DerivedData build
```

工具路径：

```text
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/
```

生成密钥（账户名建议 `qcopy`）：

```sh
SPARKLE_BIN="build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
"$SPARKLE_BIN/generate_keys" --account qcopy
```

将输出的**公钥**写入 `QCopy/Info.plist`：

```xml
<key>SUPublicEDKey</key>
<string>REPLACE_WITH_PUBLIC_KEY</string>
```

校验：

```sh
plutil -extract SUPublicEDKey raw QCopy/Info.plist
```

备份私钥（勿提交仓库）：

```sh
"$SPARKLE_BIN/generate_keys" --account qcopy -x qcopy-sparkle-private-key
```

若与 Qjiao / Qf 共用同一把钥匙串密钥，可继续使用现有公钥与 `SPARKLE_ACCOUNT`。

## 本地 Release 构建

```bash
npm run build
npm run build -- 0.2.0
```

会编译、签名、打 DMG，并在 `build/updates/` 生成未签名的 Sparkle 目录结构；**不**发布 GitHub、不写入 `release/` 缓存。

## 正式发布

```bash
npm run release
npm run release -- 0.2.0
```

要求：

- Developer ID Application 证书
- Apple 公证 profile `QCopy-notary`，或 `.env` 中的 Apple 凭据
- 已登录 `gh`
- `QCopy/Info.plist` 中已配置有效 `SUPublicEDKey`
- 钥匙串中有对应 Sparkle 私钥（或 `SPARKLE_PRIVATE_KEY_FILE`）

脚本会依次：

1. 校验 Sparkle 公钥  
2. 同步版本并递增 Build 号  
3. Release 编译 + Developer ID 签名（含 Sparkle 框架）  
4. notarize + staple  
5. 生成 `QCopy-<version>.dmg`（新用户安装）  
6. 从本机 `release/` 取最多 3 个旧 ZIP 作 delta 基线  
7. 生成 `QCopy-<version>.zip` + 版本说明 Markdown  
8. 调用 `generate_appcast` 签名并写出 `appcast.xml`（及 delta）  
9. 上传 GitHub Release：DMG、ZIP、notes、appcast、delta  
10. 将当前 ZIP / appcast / 清单写入本机 `release/`  

应用检查更新的 feed：

```text
https://github.com/qzrzz/QCopy/releases/latest/download/appcast.xml
```

### 发布产物

| 文件 | 用途 |
|------|------|
| `QCopy-<version>.dmg` | 官网 / 新用户安装 |
| `QCopy-<version>.zip` | Sparkle 完整更新包 |
| `QCopy-<version>.md` | 更新说明 |
| `appcast.xml` | Sparkle 更新源 |
| `*.delta` | 相对旧版的差分（有基线时） |

### `.env` 示例

```bash
MACOS_SIGNING_IDENTITY=Developer ID Application: Your Name (TEAMID)
APPLE_ID=your-apple-id@example.com
APPLE_APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx
APPLE_TEAM_ID=XXXXXXXXXX
QCOPY_NOTARY_PROFILE=QCopy-notary

# Sparkle（对齐 Qjiao：默认账户 qjiao，与当前 Info.plist 公钥一致）
SPARKLE_ACCOUNT=qjiao
# SPARKLE_PRIVATE_KEY_FILE=/path/to/sparkle-private-key
# SPARKLE_BIN=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
# NO_HISTORY=1   # 跳过本地 delta 基线，仅完整 ZIP
```

当前 `Info.plist` 的 `SUPublicEDKey` 与 Qjiao 共用同一把公钥。若要为 QCopy 单独密钥，请 `generate_keys --account qcopy` 后替换公钥并设置 `SPARKLE_ACCOUNT=qcopy`。

私钥只应在 macOS Keychain 或本机备份文件中，不要写入仓库。

### 应用内入口

- 菜单：QCopy → 检查更新…  
- 侧栏底部：检查更新…  

## 清理

```bash
npm run clean
```

会执行 `xcodebuild clean` 并删除项目内的 `build` 目录。本机 `release/` Sparkle 历史不会被清理。
