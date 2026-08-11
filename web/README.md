# QCopy Web

QCopy 的产品官网（最小化骨架），使用 Vite、React 与 TypeScript 构建。  
架构参考 [Qjiao/web](../../Qjiao/web)：`Feature/` 组件分区、`i18n` 文案字典、`scripts/build.ts` 发布到 `../docs`。

## 开发

```bash
cd web
bun install
bun run dev
```

## 构建 / 发布到 GitHub Pages

```bash
bun run build
```

会执行 Vite 打包，并将产物同步到仓库根目录的 `docs/`（供 GitHub Pages 使用）。

## 目录

- `src/content.ts`：**内容框架入口**（分区 + 卡片，en / zh-Hans）
- `src/components/`：`FeatureSection` / `FeatureCard` 通用渲染
- `src/Feature/`：Header / Hero / Footer 页面壳
- `src/i18n/dict.ts`：壳层 UI 文案（标题、下载按钮等）
- `src/shots/`：营销截图 / 演示媒体（在 content 里 import）
- `src/assets/fonts/`：GeneralSans + Pally（与 Qjiao 官网同源）
- `src/styles.css`：分区与卡片布局样式
- `public/`：图标与 `latest.json`
- `scripts/build.ts`：构建并同步到 `../docs`

## 如何改内容

只改 `src/content.ts` 的 `sectionsContentMap`：

1. 增删 **section**（分区标题 / 描述 / id）
2. 在 section.cards 里增删 **card**（仅 `image` + `style`）

```ts
import transfer from "./shots/transfer.png";

{ image: transfer, style: "left" } // style: left | right | bottom
// 无图时：{ style: "left" } 显示占位
```

Header 分区锚点会根据 sections 自动生成（`#section-{id}`）。
