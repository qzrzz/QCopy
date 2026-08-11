#!/usr/bin/env bun
import { $ } from "bun";
import chalk from "chalk";
import {
  existsSync,
  mkdirSync,
  rmSync,
  cpSync,
  writeFileSync,
  readFileSync,
} from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  SUPPORTED_LANGS,
  uiDictMap,
  type SupportedLang,
} from "../src/i18n/dict";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/** web 项目根路径与目标 docs 目录路径 */
const WEB_DIR = resolve(__dirname, "..");
const DIST_DIR = resolve(WEB_DIR, "dist");
const DOCS_DIR = resolve(WEB_DIR, "../docs");

/** GitHub Pages 站点根（用于 hreflang）。 */
const SITE_ORIGIN = "https://qzrzz.github.io/QCopy";

/**
 * 清空指定的目录内容。如果目录不存在则重新创建空目录。
 */
export function cleanDirectory(dirPath: string): void {
  if (existsSync(dirPath)) {
    rmSync(dirPath, { recursive: true, force: true });
  }
  mkdirSync(dirPath, { recursive: true });
}

/**
 * 递归复制源目录下的所有内容到目标目录。
 */
export function copyDirectoryContents(srcDir: string, destDir: string): void {
  if (!existsSync(srcDir)) {
    throw new Error(`源目录不存在: ${srcDir}`);
  }
  cpSync(srcDir, destDir, { recursive: true });
}

/**
 * 生成多语言 SEO 静态 HTML。
 */
function generateSeoHtml(templateHtml: string, lang: SupportedLang): string {
  const dict = uiDictMap[lang] || uiDictMap.en;
  const htmlLang = lang === "zh-Hans" ? "zh-Hans" : "en";
  const title = escapeHtml(dict.siteTitle);
  const desc = escapeHtml(dict.metaDesc);

  let html = templateHtml.replace(/<html lang="[^"]*"/, `<html lang="${htmlLang}"`);
  html = html.replace(/<title>.*?<\/title>/, `<title>${title}</title>`);
  html = html.replace(
    /<meta\s+name="description"\s+content="[^"]*"\s*\/?>/,
    `<meta name="description" content="${desc}" />`,
  );
  html = html.replace(
    /<meta\s+property="og:title"\s+content="[^"]*"\s*\/?>/,
    `<meta property="og:title" content="${title}" />`,
  );
  html = html.replace(
    /<meta\s+property="og:description"\s+content="[^"]*"\s*\/?>/,
    `<meta property="og:description" content="${desc}" />`,
  );

  const seoHeadTags = `
    <link rel="alternate" hreflang="en" href="${SITE_ORIGIN}/" />
    <link rel="alternate" hreflang="zh-Hans" href="${SITE_ORIGIN}/zh-Hans/" />
    <link rel="alternate" hreflang="x-default" href="${SITE_ORIGIN}/" />
  `;

  html = html.replace("</head>", `${seoHeadTags}\n  </head>`);

  // 子目录页面：相对静态资源改为 ../
  if (lang !== "en") {
    html = html.replaceAll('="./', '="../');
    html = html.replaceAll('src="./', 'src="../');
    html = html.replaceAll('href="./', 'href="../');
  }

  return html;
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

/**
 * 构建 Vite 产物，生成多语言 SEO 页并同步到 GitHub Pages docs。
 */
export async function buildAndPublishDocs(): Promise<void> {
  console.log(chalk.bold.cyan("\n🚀 开始构建 QCopy Web 多语言官网...\n"));

  console.log(chalk.blue("📦 步骤 1/5: 正在执行 Vite 打包构建..."));
  try {
    await $`bunx vite build`.cwd(WEB_DIR);
    console.log(chalk.green("✔ Vite 构建成功完成！\n"));
  } catch (error) {
    console.error(chalk.red("✖ Vite 构建发生错误："), error);
    process.exit(1);
  }

  console.log(chalk.blue("🧹 步骤 2/5: 正在清空 ../docs 目录..."));
  cleanDirectory(DOCS_DIR);
  console.log(chalk.green(`✔ 已成功清空: ${chalk.gray(DOCS_DIR)}\n`));

  console.log(chalk.blue("📋 步骤 3/5: 复制构建产物至 ../docs 目录..."));
  copyDirectoryContents(DIST_DIR, DOCS_DIR);
  console.log(chalk.green("✔ 内容复制完成\n"));

  console.log(
    chalk.blue(
      `🌐 步骤 4/5: 生成多语言 SEO 静态页 (${SUPPORTED_LANGS.join(", ")})...`,
    ),
  );
  const templateHtmlPath = resolve(DOCS_DIR, "index.html");
  const templateHtml = readFileSync(templateHtmlPath, "utf-8");

  for (const lang of SUPPORTED_LANGS) {
    const seoHtml = generateSeoHtml(templateHtml, lang);

    if (lang === "en") {
      writeFileSync(templateHtmlPath, seoHtml);
      console.log(
        chalk.green(`  ✔ 默认/英文: ${chalk.gray("docs/index.html")}`),
      );
    } else {
      const langDir = resolve(DOCS_DIR, lang);
      mkdirSync(langDir, { recursive: true });
      writeFileSync(resolve(langDir, "index.html"), seoHtml);
      console.log(
        chalk.green(`  ✔ ${lang}: ${chalk.gray(`docs/${lang}/index.html`)}`),
      );
    }
  }

  console.log(chalk.blue("\n⚙️  步骤 5/5: 创建 GitHub Pages .nojekyll 文件..."));
  writeFileSync(resolve(DOCS_DIR, ".nojekyll"), "");
  console.log(chalk.green("✔ 已生成 .nojekyll 文件\n"));

  console.log(
    chalk.bold.bgGreen.black(" 🎉 QCopy Web 多语言构建及 docs 同步完成！ ") +
      "\n",
  );
}

if (import.meta.main) {
  buildAndPublishDocs();
}
