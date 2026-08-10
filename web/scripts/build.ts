#!/usr/bin/env bun
import { $ } from "bun";
import chalk from "chalk";
import { existsSync, mkdirSync, rmSync, cpSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/** web 项目根路径与目标 docs 目录路径 */
const WEB_DIR = resolve(__dirname, "..");
const DIST_DIR = resolve(WEB_DIR, "dist");
const DOCS_DIR = resolve(WEB_DIR, "../docs");

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
 * 构建 Vite 产物并同步到 GitHub Pages docs 目录。
 */
export async function buildAndPublishDocs(): Promise<void> {
  console.log(chalk.bold.cyan("\n🚀 开始构建 QCopy Web 官网...\n"));

  console.log(chalk.blue("📦 步骤 1/4: 正在执行 Vite 打包构建..."));
  try {
    await $`bunx vite build`.cwd(WEB_DIR);
    console.log(chalk.green("✔ Vite 构建成功完成！\n"));
  } catch (error) {
    console.error(chalk.red("✖ Vite 构建发生错误："), error);
    process.exit(1);
  }

  console.log(chalk.blue("🧹 步骤 2/4: 正在清空 ../docs 目录..."));
  cleanDirectory(DOCS_DIR);
  console.log(chalk.green(`✔ 已成功清空: ${chalk.gray(DOCS_DIR)}\n`));

  console.log(chalk.blue("📋 步骤 3/4: 复制构建产物至 ../docs 目录..."));
  copyDirectoryContents(DIST_DIR, DOCS_DIR);
  console.log(chalk.green("✔ 内容复制完成\n"));

  console.log(chalk.blue("⚙️  步骤 4/4: 创建 GitHub Pages .nojekyll 文件..."));
  writeFileSync(resolve(DOCS_DIR, ".nojekyll"), "");
  console.log(chalk.green("✔ 已生成 .nojekyll 文件\n"));

  console.log(
    chalk.bold.bgGreen.black(" 🎉 QCopy Web 构建及 docs 同步完成！ ") + "\n",
  );
}

if (import.meta.main) {
  buildAndPublishDocs();
}
