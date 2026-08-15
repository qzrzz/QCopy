#!/usr/bin/env bun

/**
 * 官网下载清单模块：发布版本时生成并输出 download.json 文件到 ./web/download.json 与 ./docs/download.json。
 * 若仓库或本地缺失 download.json，支持根据现有产物与 release 缓存自动生成一份。
 */

import { createHash } from "node:crypto";
import { createReadStream, existsSync, mkdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import chalk from "chalk";
import { readPackageVersion, readProjectBuildNumber } from "../version";

const SCRIPT_DIR = import.meta.dirname ?? import.meta.dir ?? process.cwd();
const ROOT_DIR = join(SCRIPT_DIR, "..");
const APP_NAME = "QCopy";
const ARTIFACT_PREFIX = "QCopy";
const DEFAULT_REPOSITORY = "qzrzz/QCopy";

/**
 * download.json 相对于项目根目录的输出路径列表
 */
export const DOWNLOAD_JSON_RELATIVE_PATHS = [
  "web/download.json",
  "docs/download.json",
] as const;

/**
 * download.json 绝对路径列表
 */
export const DOWNLOAD_JSON_PATHS = DOWNLOAD_JSON_RELATIVE_PATHS.map((relativePath) =>
  join(ROOT_DIR, relativePath),
);

/**
 * 下载资源（DMG / ZIP）元数据接口
 */
export interface DownloadAssetInfo {
  name: string;
  url: string;
  size: number;
  sha256: string;
}

/**
 * 官网 download.json 结构定义
 */
export interface DownloadManifest {
  schemaVersion: 1;
  name: typeof APP_NAME;
  version: string;
  build: string;
  tag: string;
  publishedAt: string;
  htmlUrl: string;
  dmg: DownloadAssetInfo;
  zip: DownloadAssetInfo;
}

/**
 * Release 缓存清单条目接口
 */
interface ReleaseCacheEntry {
  version: string;
  build: string;
  tag: string;
  archiveName: string;
  sha256?: string;
  size?: number;
  publishedAt: string;
}

/**
 * 打印日志文本
 * @param message 要输出的日志文本
 */
function log(message: string): void {
  console.log(message);
}

/**
 * 打印带颜色的警告日志
 * @param message 警告文本
 */
function warn(message: string): void {
  console.warn(chalk.yellow(`⚠️  ${message}`));
}

/**
 * 生成 GitHub Release 资源下载直链
 * @param repository GitHub 仓库（格式如 'owner/repo'）
 * @param tag Release Tag（如 'v1.0.3'）
 * @param name 资源文件名（如 'QCopy-1.0.3.dmg'）
 * @returns 完整的资源下载 URL
 */
export function githubAssetUrl(repository: string, tag: string, name: string): string {
  return `https://github.com/${repository}/releases/download/${tag}/${name}`;
}

/**
 * 计算指定文件的 SHA-256 哈希值
 * @param path 文件绝对路径
 * @returns 十六进制格式的 SHA-256 哈希字符串
 */
export async function createFileSha256(path: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const hash = createHash("sha256");
    const stream = createReadStream(path);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolve(hash.digest("hex")));
    stream.on("error", (error) => reject(error));
  });
}

/**
 * 读取并描述本地安装包资源（名称、下载链接、大小、SHA-256）
 * @param path 安装包文件路径
 * @param repository GitHub 仓库
 * @param tag Release Tag
 * @returns 安装包元信息对象
 */
export async function describeDownloadAsset(
  path: string,
  repository: string,
  tag: string,
): Promise<DownloadAssetInfo> {
  if (!existsSync(path)) {
    throw new Error(`无法写入官网下载信息：安装包不存在或为空 ${path}`);
  }
  const stat = statSync(path);
  if (stat.size === 0) {
    throw new Error(`无法写入官网下载信息：安装包不存在或为空 ${path}`);
  }
  const name = basename(path);
  const size = stat.size;
  const sha256 = await createFileSha256(path);
  return {
    name,
    url: githubAssetUrl(repository, tag, name),
    size,
    sha256,
  };
}

/**
 * 构建完整的 DownloadManifest 数据对象
 * @param options 构建参数（版本号、构建号、仓库、DMG路径、ZIP路径、发布时间）
 * @returns 符合规范的 DownloadManifest 对象
 */
export async function buildDownloadManifest(options: {
  version: string;
  build: string;
  repository: string;
  dmgPath: string;
  zipPath: string;
  publishedAt?: string;
}): Promise<DownloadManifest> {
  const tag = `v${options.version}`;
  return {
    schemaVersion: 1,
    name: APP_NAME,
    version: options.version,
    build: options.build,
    tag,
    publishedAt: options.publishedAt ?? new Date().toISOString(),
    htmlUrl: `https://github.com/${options.repository}/releases/tag/${tag}`,
    dmg: await describeDownloadAsset(options.dmgPath, options.repository, tag),
    zip: await describeDownloadAsset(options.zipPath, options.repository, tag),
  };
}

/**
 * 将 DownloadManifest 写入到所有目标位置（./web/download.json 与 ./docs/download.json）
 * @param manifest 下载清单数据对象
 * @param customPaths 自定义写入路径列表（默认写入 DOWNLOAD_JSON_PATHS）
 * @returns 成功写入的路径列表
 */
export async function writeDownloadManifestFiles(
  manifest: DownloadManifest,
  customPaths: readonly string[] = DOWNLOAD_JSON_PATHS,
): Promise<string[]> {
  const body = `${JSON.stringify(manifest, null, 2)}\n`;
  const written: string[] = [];
  for (const path of customPaths) {
    mkdirSync(dirname(path), { recursive: true });
    const temporaryPath = `${path}.${process.pid}.tmp`;
    try {
      writeFileSync(temporaryPath, body, "utf8");
      renameSync(temporaryPath, path);
    } finally {
      rmSync(temporaryPath, { force: true });
    }
    written.push(path);
  }
  return written;
}

/**
 * 组装并写入 download.json 到 ./web/download.json 和 ./docs/download.json
 * @param options 构建与写入参数
 * @returns 生成的 DownloadManifest 数据对象
 */
export async function writeDownloadManifest(options: {
  version: string;
  build: string;
  repository: string;
  dmgPath: string;
  zipPath: string;
  publishedAt?: string;
  targetPaths?: readonly string[];
}): Promise<DownloadManifest> {
  const manifest = await buildDownloadManifest(options);
  const written = await writeDownloadManifestFiles(manifest, options.targetPaths ?? DOWNLOAD_JSON_PATHS);
  for (const path of written) {
    log(chalk.cyan("▸ ") + chalk.green("已写入官网下载信息: ") + chalk.bold(path));
  }
  return manifest;
}

/**
 * 检查所有目标位置的 download.json 是否均已存在
 * @param paths 检查的文件路径列表（默认 DOWNLOAD_JSON_PATHS）
 * @returns 是否全部存在
 */
export function downloadJsonExists(paths: readonly string[] = DOWNLOAD_JSON_PATHS): boolean {
  return paths.every((path) => existsSync(path));
}

/**
 * 读取 release/manifest.json 中最新一条已发布版本记录
 * @returns 最新的 Release 缓存条目或 undefined
 */
function readLatestReleaseCacheEntry(): ReleaseCacheEntry | undefined {
  const manifestPath = join(ROOT_DIR, "release/manifest.json");
  if (!existsSync(manifestPath)) return undefined;
  try {
    const value = JSON.parse(readFileSync(manifestPath, "utf8")) as {
      entries?: ReleaseCacheEntry[];
    };
    const entries = Array.isArray(value.entries) ? value.entries : [];
    return entries
      .filter(
        (entry) =>
          typeof entry.version === "string" &&
          typeof entry.build === "string" &&
          typeof entry.publishedAt === "string",
      )
      .sort((a, b) => Date.parse(b.publishedAt) - Date.parse(a.publishedAt))[0];
  } catch {
    return undefined;
  }
}

/**
 * 查找本地现有的 Sparkle ZIP 文件路径
 * @param version 目标版本号
 * @param archiveName 预期的压缩包文件名（可选）
 * @returns 存在的 ZIP 绝对路径
 */
function resolveExistingZipPath(version: string, archiveName?: string): string {
  const candidates = [
    archiveName ? join(ROOT_DIR, "release/archives", archiveName) : undefined,
    join(ROOT_DIR, "release/archives", `${ARTIFACT_PREFIX}-${version}.zip`),
    join(ROOT_DIR, "build/updates", `${ARTIFACT_PREFIX}-${version}.zip`),
    join(ROOT_DIR, "build", `${ARTIFACT_PREFIX}-${version}.zip`),
  ].filter((path): path is string => typeof path === "string");
  const found = candidates.find((path) => existsSync(path) && statSync(path).size > 0);
  if (!found) {
    throw new Error(`未找到 ${version} 的 Sparkle ZIP，无法生成 download.json`);
  }
  return found;
}

/**
 * 查找本地现有的 DMG 文件路径
 * @param version 目标版本号
 * @returns 存在的 DMG 绝对路径
 */
function resolveExistingDmgPath(version: string): string {
  const candidates = [
    join(ROOT_DIR, `build/${ARTIFACT_PREFIX}-${version}.dmg`),
    join(ROOT_DIR, `release/${ARTIFACT_PREFIX}-${version}.dmg`),
    join(ROOT_DIR, `release/archives/${ARTIFACT_PREFIX}-${version}.dmg`),
  ];
  const found = candidates.find((path) => existsSync(path) && statSync(path).size > 0);
  if (!found) {
    throw new Error(`未找到 ${version} 的 DMG，无法生成 download.json: ${join(ROOT_DIR, `build/${ARTIFACT_PREFIX}-${version}.dmg`)}`);
  }
  return found;
}

/**
 * 根据本机现有产物和 release 历史生成 download.json（当前仓库没有清单时使用）
 * @param options 可选仓库名与目标路径配置
 * @returns 生成的 DownloadManifest 数据对象
 */
export async function writeDownloadManifestFromExisting(options?: {
  repository?: string;
  targetPaths?: readonly string[];
}): Promise<DownloadManifest> {
  const cached = readLatestReleaseCacheEntry();
  const version = cached?.version || readPackageVersion();
  const build = cached?.build || readProjectBuildNumber();
  const repository = options?.repository ?? process.env.GITHUB_REPOSITORY ?? DEFAULT_REPOSITORY;
  return writeDownloadManifest({
    version,
    build,
    repository,
    dmgPath: resolveExistingDmgPath(version),
    zipPath: resolveExistingZipPath(version, cached?.archiveName),
    publishedAt: cached?.publishedAt,
    targetPaths: options?.targetPaths,
  });
}

if (typeof process !== "undefined" && process.argv[1]?.endsWith("download-manifest.ts")) {
  const force = process.argv.includes("--force");
  if (downloadJsonExists() && !force) {
    log(chalk.blue("ℹ️  ") + chalk.gray("download.json 已存在；如需按本机产物重写请加 --force"));
    process.exit(0);
  }
  writeDownloadManifestFromExisting().catch((error) => {
    console.error(`\n${chalk.red("✗")} ${error instanceof Error ? error.message : error}`);
    process.exit(1);
  });
}
