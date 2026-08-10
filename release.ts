#!/usr/bin/env bun

/**
 * QCopy Release 流程：
 * 1. 同步 package.json / project.yml 版本，并递增 Build 号
 * 2. 生成 Xcode 工程并构建 Release App
 * 3. 使用 Developer ID 签名；有公证凭据时完成 notarize + staple
 * 4. 打包 QCopy-<version>.dmg
 * 5. 默认发布到 GitHub Release；--no-publish 仅生成本地产物
 *
 * 用法：
 *   bun release.ts --no-publish
 *   bun release.ts 0.2.0 --no-publish
 *   bun release.ts 0.2.0
 */

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { isSemVer, readPackageMetadata } from "./version";

const ROOT_DIR = import.meta.dir;
const PROJECT_FILE = "QCopy.xcodeproj";
const SCHEME = "QCopy";
const APP_NAME = "QCopy.app";
const DEFAULT_NOTARY_PROFILE = "QCopy-notary";

function log(message: string) { console.log(message); }
function warn(message: string) { console.warn(`⚠️ ${message}`); }

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

  let updated = projectYml.replace(/MARKETING_VERSION:\s*"([^"]+)"/, `MARKETING_VERSION: "${requestedVersion}"`);
  updated = updated.replace(/CURRENT_PROJECT_VERSION:\s*"([^"]+)"/, `CURRENT_PROJECT_VERSION: "${buildNumber}"`);
  writeFileSync(projectYmlPath, updated, "utf8");
  return { version: requestedVersion, buildNumber };
}

async function resolveSigningIdentity(env: Record<string, string>): Promise<string> {
  const configured = env.MACOS_SIGNING_IDENTITY?.trim();
  if (configured) return configured;
  try {
    const identities = await capture(["security", "find-identity", "-p", "codesigning"]);
    return identities.match(/"([^\"]*Developer ID Application[^\"]*)"/)?.[1] || "-";
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

  const zipPath = join(ROOT_DIR, `build/QCopy-${version}.zip`);
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
  try { createDmg = await capture(["which", "create-dmg"]); } catch { /* fallback */ }

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
  const target = sections.find((section) => section.startsWith(`[${version}]`) || section.startsWith(version));
  if (!target) return `QCopy v${version} 更新说明`;
  const body = target.slice(target.indexOf("\n") + 1).trim();
  return body || `QCopy v${version} 更新说明`;
}

async function publishToGitHub(version: string, dmgPath: string, releaseNotes: string): Promise<void> {
  const tag = `v${version}`;
  try { await capture(["gh", "--version"]); } catch {
    throw new Error("未找到 GitHub CLI gh，请安装后执行 gh auth login");
  }

  let exists = true;
  try { await capture(["gh", "release", "view", tag]); } catch { exists = false; }
  if (exists) {
    log(`▸ 更新 GitHub Release ${tag}…`);
    await run(["gh", "release", "edit", tag, "--notes", releaseNotes]);
    await run(["gh", "release", "upload", tag, dmgPath, "--clobber"]);
  } else {
    log(`▸ 创建 GitHub Release ${tag}…`);
    await run(["gh", "release", "create", tag, dmgPath, "--title", `QCopy ${tag}`, "--notes", releaseNotes]);
  }
  log(`✓ GitHub Release 已发布: ${tag}`);
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
  const { version, buildNumber } = syncVersionAndBumpBuildNumber(versionArg);
  log(`\n📦 QCopy ${shouldPublish ? "发布" : "本地构建"}流程`);
  log(`▸ 版本: ${version} | Build: ${buildNumber}`);

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

  log("▸ 签署 App…");
  if (isDeveloperID) {
    await run(["codesign", "--force", "--deep", "--options", "runtime", "--timestamp", "--sign", identity, appPath]);
  } else {
    await run(["codesign", "--force", "--deep", "--sign", "-", appPath]);
  }

  let notarized = false;
  if (isDeveloperID) notarized = await notarizeApp(appPath, version, env);
  if (shouldPublish && !notarized) {
    throw new Error("发布流程未完成公证；请配置 QCopy-notary profile 或 Apple 公证凭据");
  }

  const dmgPath = join(ROOT_DIR, `build/QCopy-${version}.dmg`);
  await createDMG(appPath, dmgPath);
  const releaseNotes = extractReleaseNotes(version);
  log(`\n✓ 本地构建完成: ${dmgPath}`);
  log(`  版本: ${version} | 签名: ${identity} | 公证: ${notarized ? "是" : "否"}`);

  if (shouldPublish) await publishToGitHub(version, dmgPath, releaseNotes);
  else log("ℹ️ 已跳过 GitHub Release 发布（--no-publish）");
}

if (import.meta.main) {
  main().catch((error) => {
    console.error(`\n✗ ${error instanceof Error ? error.message : error}`);
    process.exit(1);
  });
}
