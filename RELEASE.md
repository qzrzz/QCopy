# QCopy 开发与发布流程

QCopy 使用 Bun + TypeScript 脚本驱动 XcodeGen 和 Xcode 构建，命令可以通过 `npm run` 或 `bun run` 执行。

## 日常开发

```bash
npm run dev
```

流程：

1. 执行 `xcodegen generate`
2. 编译 Debug 配置到 `build/DerivedData`
3. 启动 `QCopy Dev.app`，终端继续显示 stdout / stderr

只编译不启动可以直接执行：

```bash
xcodebuild -project QCopy.xcodeproj -scheme QCopy -configuration Debug \
  -derivedDataPath build/DerivedData build
```

使用 Instruments：

```bash
npm run debug
npm run debug -- --record
```

## 版本号

版本号的来源是根目录 `package.json`，Build 号来源是 `project.yml` 的 `CURRENT_PROJECT_VERSION`。

```bash
npm run version              # patch: 0.1.0 -> 0.1.1
npm run version -- minor     # minor: 0.1.0 -> 0.2.0
npm run version -- major     # major: 0.1.0 -> 1.0.0
npm run version -- 0.3.0    # 指定版本
```

每次版本更新都会同步：

- `package.json.version`
- `project.yml.MARKETING_VERSION`
- `project.yml.CURRENT_PROJECT_VERSION`（自动 +1）
- 重新生成 `QCopy.xcodeproj`

## 本地 Release 构建

```bash
npm run build
npm run build -- 0.2.0
```

本地构建会执行完整的 Release 编译、签名和 DMG 打包，但不会发布 GitHub Release。产物位于：

```text
build/QCopy-<version>.dmg
```

没有 Developer ID 证书时会生成 ad-hoc 本地签名产物；这种产物只能自用，不能通过公证并发布给其他用户。

## 正式发布

```bash
npm run release
npm run release -- 0.2.0
```

正式发布要求：

- Developer ID Application 证书
- Apple 公证 profile `QCopy-notary`，或 `.env` 中的 Apple 公证凭据
- 已安装并登录 GitHub CLI：`gh auth login`
- 当前目录对应一个 GitHub repository remote

脚本会依次执行：

1. 同步版本并递增 Build 号
2. 生成 Xcode 工程
3. Release 编译
4. Developer ID + Hardened Runtime 签名
5. notarize + staple
6. 生成 `QCopy-<version>.dmg`
7. 创建或更新 GitHub Release `v<version>`

推荐将凭据写入未提交的 `.env`：

```bash
MACOS_SIGNING_IDENTITY=Developer ID Application: Your Name (TEAMID)
APPLE_ID=your-apple-id@example.com
APPLE_APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx
APPLE_TEAM_ID=XXXXXXXXXX
QCOPY_NOTARY_PROFILE=QCopy-notary
```

私钥只应保留在 macOS Keychain，不要写入仓库或 `.env`。

## 清理

```bash
npm run clean
```

会执行 `xcodebuild clean` 并删除项目内的 `build` 目录。
