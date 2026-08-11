#!/usr/bin/env bun

/**
 * QCopy Release 流程（自动更新机制对齐 Qjiao）：
 * 1. 同步 package.json / project.yml 版本，并递增 Build 号
 * 2. 生成 Xcode 工程并构建 Release App
 * 3. Developer ID 签名；有公证凭据时 notarize + staple
 * 4. 打包 QCopy-<version>.dmg（新用户安装）
 * 5. 生成 Sparkle ZIP + 版本说明，基于本机 release/ 历史做 delta，调用 generate_appcast
 * 6. 默认发布到 GitHub Release（DMG + ZIP + notes + appcast + deltas）
 *
 * 依赖 .env：
 *   MACOS_SIGNING_IDENTITY / APPLE_* / QCOPY_NOTARY_PROFILE
 *   SPARKLE_ACCOUNT            Keychain 账户（默认 qjiao，与当前公钥一致）
 *   SPARKLE_PRIVATE_KEY_FILE   可选，私钥备份文件；默认读钥匙串
 *   SPARKLE_BIN / SPARKLE_BIN_DIR  可选，generate_appcast 所在 bin
 *
 * 用法：
 *   bun release.ts --no-publish
 *   bun release.ts 0.2.0 --no-publish
 *   bun release.ts 0.2.0
 */

import {
  constants as fsConstants,
  copyFileSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { basename, join } from "node:path";
import { generateAppcast } from "./scripts/generate-appcast";
import { isSemVer, readPackageMetadata } from "./version";

const ROOT_DIR = import.meta.dir;
const PROJECT_FILE = "QCopy.xcodeproj";
const SCHEME = "QCopy";
const APP_NAME = "QCopy.app";
const ARTIFACT_PREFIX = "QCopy";
const DEFAULT_NOTARY_PROFILE = "QCopy-notary";
const GITHUB_OWNER_REPO = process.env.GITHUB_REPOSITORY ?? "qzrzz/QCopy";
const SPARKLE_FEED_URL = `https://github.com/${GITHUB_OWNER_REPO}/releases/latest/download/appcast.xml`;
const INFO_PLIST = join(ROOT_DIR, "QCopy/Info.plist");
const UPDATES_DIR = join(ROOT_DIR, "build/updates");
const RELEASE_CACHE_DIR = process.env.RELEASE_CACHE_DIR ?? join(ROOT_DIR, "release");
const RELEASE_CACHE_ARCHIVES_DIR = join(RELEASE_CACHE_DIR, "archives");
const RELEASE_CACHE_APPCAST_PATH = join(RELEASE_CACHE_DIR, "appcast.xml");
const RELEASE_CACHE_MANIFEST_PATH = join(RELEASE_CACHE_DIR, "manifest.json");
const MAX_DELTA_BASELINES = 3;

interface ReleaseCacheEntry {
  version: string;
  build: string;
  tag: string;
  archiveName: string;
  sha256: string;
  size: number;
  publishedAt: string;
}

interface ReleaseCacheManifest {
  schemaVersion: 1;
  entries: ReleaseCacheEntry[];
}

function log(message: string) {
  console.log(message);
}
function warn(message: string) {
  console.warn(`⚠️ ${message}`);
}

async function run(cmd: string[], cwd = ROOT_DIR): Promise<void> {
  const proc = Bun.spawn(cmd, { cwd, stdout: "inherit", stderr: "inherit" });
  const code = await proc.exited;
  if (code !== 0) throw new Error(`命令失败 (exit ${code}): ${cmd.join(" ")}`);
}

async function capture(cmd: string[], cwd = ROOT_DIR): Promise<string> {
  const proc = Bun.spawn(cmd, { cwd, stdout: "pipe", stderr: "pipe" });
  const [code, stdout, stderr] = await Promise.all([
    proc.exited,
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  if (code !== 0) throw new Error(`命令失败 (exit ${code}): ${cmd.join(" ")}\n${stderr}`);
  return stdout.trim();
}

function loadEnv(): Record<string, string> {
  const env: Record<string, string> = { ...Bun.env };
  const envPath = join(ROOT_DIR, ".env");
  if (!existsSync(envPath)) return env;
  for (const line of readFileSync(envPath, "utf8").split("\n")) {
    const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (match && env[match[1]] === undefined) {
      env[match[1]] = match[2].replace(/^['"]|['"]$/g, "");
    }
  }
  return env;
}

function isValidSparklePublicKey(value: string): boolean {
  // EdDSA 公钥 base64，约 32 字节 → 44 字符含 =
  return /^[A-Za-z0-9+/]{40,60}={0,2}$/.test(value) && !value.includes("REPLACE");
}

/** 发布前检查 Info.plist 中的 Sparkle 公钥（对齐 Qjiao）。 */
async function requireSparklePublicKey(): Promise<string> {
  const key = (
    await capture(["plutil", "-extract", "SUPublicEDKey", "raw", INFO_PLIST])
  ).trim();
  if (!isValidSparklePublicKey(key)) {
    throw new Error(
      "请先在 QCopy/Info.plist 配置 SUPublicEDKey（Sparkle generate_keys 输出的公钥）。见 RELEASE.md",
    );
  }
  return key;
}

/** 同步营销版本，并把 project.yml 的 Build 号递增 1。 */
export function syncVersionAndBumpBuildNumber(versionOverride?: string): {
  version: string;
  buildNumber: string;
} {
  const { path: packagePath, packageJson } = readPackageMetadata();
  const requestedVersion = versionOverride || packageJson.version;
  if (!requestedVersion || typeof requestedVersion !== "string" || !isSemVer(requestedVersion)) {
    throw new Error("package.json 或命令行中未找到有效的 X.Y.Z 版本号");
  }

  if (packageJson.version !== requestedVersion) {
    packageJson.version = requestedVersion;
    writeFileSync(packagePath, JSON.stringify(packageJson, null, 2) + "\n", "utf8");
  }

  const projectYmlPath = join(ROOT_DIR, "project.yml");
  const projectYml = readFileSync(projectYmlPath, "utf8");
  const buildMatch = projectYml.match(/CURRENT_PROJECT_VERSION:\s*"([^"]+)"/);
  if (!buildMatch) throw new Error("project.yml 中未找到 CURRENT_PROJECT_VERSION");
  const currentBuild = Number.parseInt(buildMatch[1], 10);
  const buildNumber = String(Number.isNaN(currentBuild) ? 1 : currentBuild + 1);

  let updated = projectYml.replace(
    /MARKETING_VERSION:\s*"([^"]+)"/,
    `MARKETING_VERSION: "${requestedVersion}"`,
  );
  updated = updated.replace(
    /CURRENT_PROJECT_VERSION:\s*"([^"]+)"/,
    `CURRENT_PROJECT_VERSION: "${buildNumber}"`,
  );
  writeFileSync(projectYmlPath, updated, "utf8");
  return { version: requestedVersion, buildNumber };
}

async function resolveSigningIdentity(env: Record<string, string>): Promise<string> {
  const configured = env.MACOS_SIGNING_IDENTITY?.trim();
  if (configured) return configured;
  try {
    const identities = await capture(["security", "find-identity", "-p", "codesigning"]);
    return identities.match(/"([^"]*Developer ID Application[^"]*)"/)?.[1] || "-";
  } catch {
    return "-";
  }
}

async function hasNotaryProfile(profile: string): Promise<boolean> {
  try {
    await capture(["xcrun", "notarytool", "history", "--keychain-profile", profile]);
    return true;
  } catch {
    return false;
  }
}

async function configureNotaryProfile(env: Record<string, string>): Promise<boolean> {
  const profile = env.QCOPY_NOTARY_PROFILE?.trim() || DEFAULT_NOTARY_PROFILE;
  if (await hasNotaryProfile(profile)) return true;
  const appleID = env.APPLE_ID;
  const password = env.APPLE_APP_SPECIFIC_PASSWORD;
  const teamID = env.APPLE_TEAM_ID;
  if (!appleID || !password || !teamID) return false;

  log(`▸ 写入公证凭据到钥匙串 profile: ${profile}…`);
  try {
    await run([
      "xcrun", "notarytool", "store-credentials", profile,
      "--apple-id", appleID,
      "--team-id", teamID,
      "--password", password,
    ]);
  } catch {
    warn("写入公证凭据失败");
  }
  return hasNotaryProfile(profile);
}

async function notarizeApp(appPath: string, version: string, env: Record<string, string>): Promise<boolean> {
  if (!(await configureNotaryProfile(env))) {
    warn("未找到公证凭据，跳过 notarize；发布时必须配置 QCopy-notary profile");
    return false;
  }

  const zipPath = join(ROOT_DIR, `build/QCopy-${version}-notary.zip`);
  const profile = env.QCOPY_NOTARY_PROFILE?.trim() || DEFAULT_NOTARY_PROFILE;
  log("▸ 压缩 App 并提交 Apple 公证…");
  await run(["ditto", "-c", "-k", "--keepParent", appPath, zipPath]);
  try {
    await run(["xcrun", "notarytool", "submit", zipPath, "--keychain-profile", profile, "--wait"]);
    log("▸ 装订公证凭据…");
    await run(["xcrun", "stapler", "staple", appPath]);
    return true;
  } finally {
    if (existsSync(zipPath)) await run(["rm", "-f", zipPath]);
  }
}

async function createDMG(appPath: string, dmgPath: string): Promise<void> {
  await run(["rm", "-f", dmgPath]);
  let createDmg: string | undefined;
  try {
    createDmg = await capture(["which", "create-dmg"]);
  } catch {
    /* fallback */
  }

  if (createDmg) {
    try {
      log("▸ 使用 create-dmg 打包安装镜像…");
      await run([
        createDmg,
        "--volname", "QCopy",
        "--window-pos", "200", "120",
        "--window-size", "600", "400",
        "--icon-size", "128",
        "--icon", APP_NAME, "160", "190",
        "--app-drop-link", "440", "190",
        "--hide-extension", APP_NAME,
        "--overwrite", dmgPath, appPath,
      ]);
      return;
    } catch (error) {
      warn(`create-dmg 打包失败，改用 diskutil fallback: ${error instanceof Error ? error.message : error}`);
    }
  }

  log("▸ 使用 diskutil fallback 打包安装镜像…");
  const stage = await capture(["mktemp", "-d"]);
  try {
    await run(["cp", "-R", appPath, join(stage, APP_NAME)]);
    await run(["ln", "-s", "/Applications", join(stage, "Applications")]);
    await run(["diskutil", "image", "create", "from", stage, "--format", "UDZO", "--volumeName", "QCopy", dmgPath]);
  } finally {
    await run(["rm", "-rf", stage]);
  }
}

function extractReleaseNotes(version: string): string {
  const changelogPath = join(ROOT_DIR, "CHANGELOG.md");
  if (!existsSync(changelogPath)) return `QCopy v${version} 更新说明`;
  const content = readFileSync(changelogPath, "utf8");
  const sections = content.split(/^##\s+/m).slice(1);
  const target = sections.find(
    (section) => section.startsWith(`[${version}]`) || section.startsWith(version),
  );
  if (!target) {
    if (sections.length > 0) {
      const first = sections[0];
      const body = first.slice(first.indexOf("\n") + 1).trim();
      if (body) return body;
    }
    return `QCopy v${version} 更新说明`;
  }
  const body = target.slice(target.indexOf("\n") + 1).trim();
  return body || `QCopy v${version} 更新说明`;
}

function copyFileAtomically(source: string, destination: string): void {
  const temporaryPath = `${destination}.${process.pid}.tmp`;
  rmSync(temporaryPath, { force: true });
  try {
    copyFileSync(source, temporaryPath, fsConstants.COPYFILE_FICLONE);
    renameSync(temporaryPath, destination);
  } finally {
    rmSync(temporaryPath, { force: true });
  }
}

async function createFileSha256(path: string): Promise<string> {
  const hash = new Bun.CryptoHasher("sha256");
  for await (const chunk of Bun.file(path).stream()) {
    hash.update(chunk);
  }
  return hash.digest("hex");
}

function readReleaseCacheManifest(): ReleaseCacheManifest {
  if (!existsSync(RELEASE_CACHE_MANIFEST_PATH)) {
    return { schemaVersion: 1, entries: [] };
  }
  try {
    const value = JSON.parse(readFileSync(RELEASE_CACHE_MANIFEST_PATH, "utf8")) as {
      schemaVersion?: unknown;
      entries?: unknown;
    };
    if (value.schemaVersion !== 1 || !Array.isArray(value.entries)) {
      throw new Error("unsupported schema");
    }
    const entries = value.entries.filter(isReleaseCacheEntry);
    return { schemaVersion: 1, entries };
  } catch {
    warn(`忽略损坏的 release 缓存清单: ${RELEASE_CACHE_MANIFEST_PATH}`);
    return { schemaVersion: 1, entries: [] };
  }
}

function isReleaseCacheEntry(value: unknown): value is ReleaseCacheEntry {
  if (!value || typeof value !== "object") return false;
  const entry = value as Partial<ReleaseCacheEntry>;
  return (
    typeof entry.version === "string" &&
    entry.version.length > 0 &&
    typeof entry.build === "string" &&
    /^[1-9][0-9]*$/.test(entry.build) &&
    typeof entry.tag === "string" &&
    typeof entry.archiveName === "string" &&
    basename(entry.archiveName) === entry.archiveName &&
    entry.archiveName.endsWith(".zip") &&
    typeof entry.sha256 === "string" &&
    /^[a-f0-9]{64}$/.test(entry.sha256) &&
    typeof entry.size === "number" &&
    Number.isSafeInteger(entry.size) &&
    entry.size > 0 &&
    typeof entry.publishedAt === "string" &&
    Number.isFinite(Date.parse(entry.publishedAt))
  );
}

async function validateReleaseCacheEntry(entry: ReleaseCacheEntry): Promise<boolean> {
  const path = join(RELEASE_CACHE_ARCHIVES_DIR, entry.archiveName);
  return (
    existsSync(path) &&
    Bun.file(path).size === entry.size &&
    (await createFileSha256(path)) === entry.sha256
  );
}

function assertBuildIsNewerThanCache(build: string, version: string): void {
  const cachedBuilds = readReleaseCacheManifest().entries.map((e) => BigInt(e.build));
  if (cachedBuilds.length === 0) return;
  const latestBuild = cachedBuilds.reduce((a, b) => (b > a ? b : a));
  if (BigInt(build) <= latestBuild) {
    throw new Error(
      `build ${build} 不大于本地缓存的 build ${latestBuild}；发布 ${version} 前请递增 CURRENT_PROJECT_VERSION`,
    );
  }
}

/** 将本机 release/ 历史复制到 updates 目录，作为 delta 基线。 */
async function prepareLocalDeltaBaselines(
  currentBuild: string,
  appcastPath: string,
): Promise<void> {
  const manifest = readReleaseCacheManifest();
  if (existsSync(RELEASE_CACHE_APPCAST_PATH) && Bun.file(RELEASE_CACHE_APPCAST_PATH).size > 0) {
    copyFileAtomically(RELEASE_CACHE_APPCAST_PATH, appcastPath);
    log(`▸ 使用本地 Sparkle 历史: ${RELEASE_CACHE_APPCAST_PATH}`);
  }

  const candidates = manifest.entries
    .filter((entry) => entry.build !== currentBuild)
    .sort((a, b) => Date.parse(b.publishedAt) - Date.parse(a.publishedAt))
    .slice(0, MAX_DELTA_BASELINES);

  let copied = 0;
  for (const entry of candidates) {
    if (!(await validateReleaseCacheEntry(entry))) {
      warn(`忽略无效 delta 基线 ${entry.archiveName}`);
      continue;
    }
    copyFileAtomically(
      join(RELEASE_CACHE_ARCHIVES_DIR, entry.archiveName),
      join(UPDATES_DIR, entry.archiveName),
    );
    copied += 1;
    log(`▸ delta 基线 ${copied}/${MAX_DELTA_BASELINES}: ${entry.archiveName} (build ${entry.build})`);
  }
  if (copied === 0) {
    log("▸ 无有效本地基线，仅生成完整 ZIP 更新");
  }
}

/** 强制历史完整 ZIP 的 enclosure URL 指向对应 GitHub tag。 */
async function normalizeAppcastArchiveUrls(path: string): Promise<void> {
  const original = readFileSync(path, "utf8");
  const normalized = original.replace(/<item>[\s\S]*?<\/item>/g, (item): string => {
    const version = item.match(
      /<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>/,
    )?.[1];
    if (!version || !/^[0-9A-Za-z.+-]+$/.test(version)) return item;
    const archiveUrl =
      `https://github.com/${GITHUB_OWNER_REPO}/releases/download/` +
      `v${version}/${ARTIFACT_PREFIX}-${version}.zip`;
    return item
      .replace(/<title>[^<]*<\/title>/, `<title>${version}</title>`)
      .replace(/(<enclosure\s+url=")[^"]+\.zip(")/, `$1${archiveUrl}$2`);
  });
  if (normalized !== original) {
    await Bun.write(path, normalized);
  }
}

async function writeReleaseCacheManifest(manifest: ReleaseCacheManifest): Promise<void> {
  mkdirSync(RELEASE_CACHE_DIR, { recursive: true });
  const temporaryPath = `${RELEASE_CACHE_MANIFEST_PATH}.${process.pid}.tmp`;
  try {
    await Bun.write(temporaryPath, `${JSON.stringify(manifest, null, 2)}\n`);
    renameSync(temporaryPath, RELEASE_CACHE_MANIFEST_PATH);
  } finally {
    rmSync(temporaryPath, { force: true });
  }
}

/** 发布成功后把当前 ZIP 与 appcast 写入本机 release/（对齐 Qjiao）。 */
async function persistReleaseCache(
  version: string,
  build: string,
  tag: string,
  zipPath: string,
  appcastPath: string,
): Promise<void> {
  if (!existsSync(zipPath) || Bun.file(zipPath).size === 0) {
    throw new Error("无法缓存不完整的 Sparkle ZIP");
  }
  if (!existsSync(appcastPath) || Bun.file(appcastPath).size === 0) {
    throw new Error("无法缓存不完整的 appcast");
  }

  mkdirSync(RELEASE_CACHE_ARCHIVES_DIR, { recursive: true });
  const archiveName = basename(zipPath);
  const entry: ReleaseCacheEntry = {
    version,
    build,
    tag,
    archiveName,
    sha256: await createFileSha256(zipPath),
    size: Bun.file(zipPath).size,
    publishedAt: new Date().toISOString(),
  };

  copyFileAtomically(zipPath, join(RELEASE_CACHE_ARCHIVES_DIR, archiveName));
  if (!(await validateReleaseCacheEntry(entry))) {
    throw new Error(`缓存 ZIP 校验失败: ${archiveName}`);
  }
  copyFileAtomically(appcastPath, RELEASE_CACHE_APPCAST_PATH);

  const previous = readReleaseCacheManifest();
  const entries = [
    entry,
    ...previous.entries.filter(
      (cached) => cached.build !== entry.build && cached.archiveName !== entry.archiveName,
    ),
  ]
    .sort((a, b) => Date.parse(b.publishedAt) - Date.parse(a.publishedAt))
    .slice(0, MAX_DELTA_BASELINES);
  await writeReleaseCacheManifest({ schemaVersion: 1, entries });

  const kept = new Set(entries.map((e) => e.archiveName));
  for (const name of readdirSync(RELEASE_CACHE_ARCHIVES_DIR)) {
    if (
      name.startsWith(`${ARTIFACT_PREFIX}-`) &&
      name.endsWith(".zip") &&
      !kept.has(name)
    ) {
      rmSync(join(RELEASE_CACHE_ARCHIVES_DIR, name), { force: true });
    }
  }
  log(
    `▸ 已写入本地 Sparkle 历史 ${RELEASE_CACHE_DIR}（${entries.length}/${MAX_DELTA_BASELINES} 版）`,
  );
}

function listGeneratedDeltaPaths(): string[] {
  if (!existsSync(UPDATES_DIR)) return [];
  return readdirSync(UPDATES_DIR)
    .filter((name) => name.endsWith(".delta"))
    .sort()
    .map((name) => join(UPDATES_DIR, name));
}

/** 生成 Sparkle ZIP、说明与 appcast（含 delta）。 */
async function generateSparkleUpdates(options: {
  appPath: string;
  version: string;
  buildNumber: string;
  releaseNotes: string;
  env: Record<string, string>;
  sign: boolean;
}): Promise<{ zipPath: string; notesPath: string; appcastPath: string }> {
  const { appPath, version, buildNumber, releaseNotes, env, sign } = options;
  const tag = `v${version}`;
  const zipName = `${ARTIFACT_PREFIX}-${version}.zip`;
  const notesName = `${ARTIFACT_PREFIX}-${version}.md`;
  const zipPath = join(UPDATES_DIR, zipName);
  const notesPath = join(UPDATES_DIR, notesName);
  const appcastPath = join(UPDATES_DIR, "appcast.xml");

  if (sign) {
    assertBuildIsNewerThanCache(buildNumber, version);
  }

  rmSync(UPDATES_DIR, { recursive: true, force: true });
  mkdirSync(UPDATES_DIR, { recursive: true });

  if (sign && env.NO_HISTORY !== "1") {
    await prepareLocalDeltaBaselines(buildNumber, appcastPath);
  }

  log("▸ 生成 Sparkle 完整更新 ZIP…");
  await run(["ditto", "-c", "-k", "--keepParent", appPath, zipPath]);
  await Bun.write(notesPath, `${releaseNotes}\n`);

  if (sign) {
    // 默认 qjiao：与 Info.plist 中共用公钥对应的钥匙串账户一致；独立密钥可设 SPARKLE_ACCOUNT=qcopy
    const account = env.SPARKLE_ACCOUNT?.trim() || env.SPARKLE_KEY_ACCOUNT?.trim() || "qjiao";
    const privateKeyFile = env.SPARKLE_PRIVATE_KEY_FILE?.trim();
    if (privateKeyFile && !existsSync(privateKeyFile)) {
      throw new Error("SPARKLE_PRIVATE_KEY_FILE 指向的文件不存在");
    }

    log("▸ 调用 generate_appcast（签名 ZIP / 生成 delta / 更新 appcast）…");
    const downloadUrlPrefix =
      `https://github.com/${GITHUB_OWNER_REPO}/releases/download/${tag}/`;
    await generateAppcast(
      UPDATES_DIR,
      {
        downloadUrlPrefix,
        edKeyFile: privateKeyFile,
        account,
        versions: [buildNumber],
      },
      ROOT_DIR,
    );
    await normalizeAppcastArchiveUrls(appcastPath);
  } else {
    // 本地构建：不签名，仅写占位 appcast 便于检查目录结构
    await Bun.write(
      appcastPath,
      `<?xml version="1.0" encoding="utf-8"?>\n` +
        `<!-- unsigned local appcast for ${version} (build ${buildNumber}) -->\n`,
    );
  }

  if (!existsSync(appcastPath)) {
    throw new Error(`未生成 appcast: ${appcastPath}`);
  }
  return { zipPath, notesPath, appcastPath };
}

async function publishToGitHub(options: {
  version: string;
  dmgPath: string;
  zipPath: string;
  notesPath: string;
  appcastPath: string;
  releaseNotes: string;
}): Promise<void> {
  const { version, dmgPath, zipPath, notesPath, appcastPath, releaseNotes } = options;
  const tag = `v${version}`;
  try {
    await capture(["gh", "--version"]);
  } catch {
    throw new Error("未找到 GitHub CLI gh，请安装后执行 gh auth login");
  }

  const assets = [
    dmgPath,
    zipPath,
    notesPath,
    appcastPath,
    ...listGeneratedDeltaPaths(),
  ];

  let exists = true;
  try {
    await capture(["gh", "release", "view", tag, "--repo", GITHUB_OWNER_REPO]);
  } catch {
    exists = false;
  }

  if (exists) {
    log(`▸ 更新 GitHub Release ${tag}…`);
    await run(["gh", "release", "edit", tag, "--repo", GITHUB_OWNER_REPO, "--notes", releaseNotes]);
  } else {
    log(`▸ 创建 GitHub Release ${tag}…`);
    await run([
      "gh", "release", "create", tag,
      "--repo", GITHUB_OWNER_REPO,
      "--title", `QCopy ${tag}`,
      "--notes", releaseNotes,
    ]);
  }

  for (const [index, asset] of assets.entries()) {
    log(`▸ 上传 ${index + 1}/${assets.length}: ${basename(asset)}`);
    await run([
      "gh", "release", "upload", tag, asset,
      "--repo", GITHUB_OWNER_REPO,
      "--clobber",
    ]);
  }

  log(`✓ GitHub Release 已发布: ${tag}`);
  log(`  Sparkle feed: ${SPARKLE_FEED_URL}`);
}

async function main() {
  const args = process.argv.slice(2);
  const noPublishIndex = args.indexOf("--no-publish");
  const shouldPublish = noPublishIndex === -1;
  if (noPublishIndex !== -1) args.splice(noPublishIndex, 1);
  const versionArg = args[0];
  if (versionArg && !isSemVer(versionArg)) throw new Error(`版本号必须是 X.Y.Z: ${versionArg}`);
  process.env.DEVELOPER_DIR ??= "/Applications/Xcode.app/Contents/Developer";

  const env = loadEnv();
  // 对齐 Qjiao：公钥写在 Info.plist，发布前校验
  await requireSparklePublicKey();

  const { version, buildNumber } = syncVersionAndBumpBuildNumber(versionArg);
  log(`\n📦 QCopy ${shouldPublish ? "发布" : "本地构建"}流程`);
  log(`▸ 版本: ${version} | Build: ${buildNumber}`);
  log(`▸ Sparkle feed: ${SPARKLE_FEED_URL}`);

  log("▸ 生成 Xcode 工程…");
  await run(["xcodegen", "generate"]);

  const identity = await resolveSigningIdentity(env);
  const isDeveloperID = identity.includes("Developer ID Application");
  log(`▸ 签名身份: ${identity}${isDeveloperID ? "" : "（ad-hoc / 本地）"}`);
  if (shouldPublish && !isDeveloperID) {
    throw new Error("发布流程必须使用 Developer ID Application 签名；本地构建请使用 npm run build");
  }

  const buildArgs = [
    "xcodebuild",
    "-project", PROJECT_FILE,
    "-scheme", SCHEME,
    "-configuration", "Release",
    "-derivedDataPath", "build/DerivedData",
    "CODE_SIGN_STYLE=Manual",
    `CODE_SIGN_IDENTITY=${identity}`,
    `MARKETING_VERSION=${version}`,
    `CURRENT_PROJECT_VERSION=${buildNumber}`,
  ];
  if (isDeveloperID) {
    buildArgs.push("ENABLE_HARDENED_RUNTIME=YES", "OTHER_CODE_SIGN_FLAGS=--timestamp");
  }
  buildArgs.push("build");

  log("▸ 构建 Release App…");
  await run(buildArgs);
  const appPath = join(ROOT_DIR, "build/DerivedData/Build/Products/Release", APP_NAME);
  if (!existsSync(appPath)) throw new Error(`未找到 Release App: ${appPath}`);

  log("▸ 签署 App（含内嵌 Sparkle 框架）…");
  if (isDeveloperID) {
    await run([
      "codesign", "--force", "--deep", "--options", "runtime", "--timestamp",
      "--sign", identity, appPath,
    ]);
  } else {
    await run(["codesign", "--force", "--deep", "--sign", "-", appPath]);
  }

  let notarized = false;
  if (isDeveloperID) notarized = await notarizeApp(appPath, version, env);
  if (shouldPublish && !notarized) {
    throw new Error("发布流程未完成公证；请配置 QCopy-notary profile 或 Apple 公证凭据");
  }

  const dmgPath = join(ROOT_DIR, `build/${ARTIFACT_PREFIX}-${version}.dmg`);
  await createDMG(appPath, dmgPath);
  if (isDeveloperID && notarized) {
    try {
      await run(["xcrun", "stapler", "staple", dmgPath]);
    } catch {
      warn("DMG staple 失败（可稍后手动 stapler staple）");
    }
  }

  const releaseNotes = extractReleaseNotes(version);
  const { zipPath, notesPath, appcastPath } = await generateSparkleUpdates({
    appPath,
    version,
    buildNumber,
    releaseNotes,
    env,
    sign: shouldPublish,
  });

  log(`\n✓ 本地构建完成`);
  log(`  DMG: ${dmgPath}`);
  log(`  Sparkle ZIP: ${zipPath}`);
  log(`  appcast: ${appcastPath}`);
  log(`  版本: ${version} | Build: ${buildNumber} | 签名: ${identity} | 公证: ${notarized ? "是" : "否"}`);

  if (shouldPublish) {
    await publishToGitHub({
      version,
      dmgPath,
      zipPath,
      notesPath,
      appcastPath,
      releaseNotes,
    });
    await persistReleaseCache(version, buildNumber, `v${version}`, zipPath, appcastPath);
  } else {
    log("ℹ️ 已跳过 GitHub Release 与 release/ 缓存（--no-publish）");
  }
}

if (import.meta.main) {
  main().catch((error) => {
    console.error(`\n✗ ${error instanceof Error ? error.message : error}`);
    process.exit(1);
  });
}
