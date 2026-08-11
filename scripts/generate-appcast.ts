#!/usr/bin/env bun
/**
 * 为 QCopy 更新归档签名，并生成 / 增量更新 Sparkle appcast。
 * 机制对齐 Qjiao：`generate_appcast` + ZIP 完整包 + 最多 3 个 delta。
 */
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export interface GenerateAppcastOptions {
  downloadUrlPrefix: string;
  edKeyFile?: string;
  account?: string;
  /** CFBundleVersion（build）列表，传给 generate_appcast --versions */
  versions?: string[];
}

function die(msg: string): never {
  console.error(`error: ${msg}`);
  process.exit(1);
}

/** 依次从环境变量、PATH、工程 DerivedData、本机 Xcode DerivedData 查找工具。 */
export async function findGenerateAppcast(
  projectRoot = process.cwd(),
): Promise<string | null> {
  const fromEnv = process.env.SPARKLE_BIN ?? process.env.SPARKLE_BIN_DIR;
  if (fromEnv && existsSync(join(fromEnv, "generate_appcast"))) {
    return join(fromEnv, "generate_appcast");
  }

  const onPath = Bun.which("generate_appcast");
  if (onPath) return onPath;

  const projectArtifact = join(
    projectRoot,
    "build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast",
  );
  if (existsSync(projectArtifact)) return projectArtifact;

  const derived = join(homedir(), "Library/Developer/Xcode/DerivedData");
  if (existsSync(derived)) {
    const pattern = "*/artifacts/*/Sparkle/bin/generate_appcast";
    try {
      const proc = Bun.spawn(["find", derived, "-path", pattern, "-type", "f"], {
        stdout: "pipe",
        stderr: "pipe",
      });
      const out = await new Response(proc.stdout).text();
      const hit = out.split("\n").filter(Boolean)[0];
      if (hit) return hit;
    } catch {
      // continue
    }
  }
  return null;
}

/** 为 updatesDir 中的 ZIP 签名，并生成 / 更新 appcast.xml。 */
export async function generateAppcast(
  updatesDir: string,
  options: GenerateAppcastOptions,
  projectRoot = process.cwd(),
): Promise<void> {
  const gen = await findGenerateAppcast(projectRoot);
  if (!gen) {
    die(
      "未找到 generate_appcast。请设置 SPARKLE_BIN 为 Sparkle 工具 bin 目录，" +
        "或先构建一次以拉取 Sparkle 包。",
    );
  }
  console.log(`Using: ${gen}`);

  const args = [
    gen,
    ...(options.edKeyFile ? ["--ed-key-file", options.edKeyFile] : []),
    ...(options.account ? ["--account", options.account] : []),
    ...(options.versions?.length ? ["--versions", options.versions.join(",")] : []),
    "--download-url-prefix",
    options.downloadUrlPrefix,
    "--release-notes-url-prefix",
    options.downloadUrlPrefix,
    "--maximum-versions",
    "10",
    "--maximum-deltas",
    "3",
    updatesDir,
  ];

  const proc = Bun.spawn(args, { cwd: projectRoot, stdout: "inherit", stderr: "inherit" });
  const code = await proc.exited;
  if (code !== 0) die(`generate_appcast 失败 (exit ${code})`);
  console.log(`Wrote ${join(updatesDir, "appcast.xml")}`);
}

if (import.meta.main) {
  const updatesDir = process.argv[2];
  if (!updatesDir) die("usage: bun scripts/generate-appcast.ts <updates-dir>");
  const repository = process.env.GITHUB_REPOSITORY ?? "qzrzz/QCopy";
  const tag = process.env.RELEASE_TAG;
  if (!tag) die("请设置 RELEASE_TAG，例如 RELEASE_TAG=v0.2.0");
  await generateAppcast(updatesDir, {
    downloadUrlPrefix: `https://github.com/${repository}/releases/download/${tag}/`,
    edKeyFile: process.env.SPARKLE_PRIVATE_KEY_FILE,
    account: process.env.SPARKLE_ACCOUNT ?? process.env.SPARKLE_KEY_ACCOUNT ?? "qjiao",
  });
}
