import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const PACKAGE_JSON_PATH = join(import.meta.dir, "package.json");

export interface PackageMetadata {
  version?: string;
  [key: string]: unknown;
}

export function readPackageMetadata(): {
  path: string;
  packageJson: PackageMetadata;
} {
  if (!existsSync(PACKAGE_JSON_PATH)) {
    throw new Error(`未找到 package.json: ${PACKAGE_JSON_PATH}`);
  }

  try {
    return {
      path: PACKAGE_JSON_PATH,
      packageJson: JSON.parse(readFileSync(PACKAGE_JSON_PATH, "utf8")) as PackageMetadata,
    };
  } catch (error) {
    throw new Error(`解析 package.json 失败: ${error instanceof Error ? error.message : String(error)}`);
  }
}

export function readPackageVersion(): string {
  const { packageJson } = readPackageMetadata();
  if (!packageJson.version || typeof packageJson.version !== "string") {
    throw new Error("package.json 中未找到有效的 version 字段");
  }
  return packageJson.version;
}

export function readProjectBuildNumber(projectYmlPath = join(import.meta.dir, "project.yml")): string {
  const content = readFileSync(projectYmlPath, "utf8");
  const match = content.match(/CURRENT_PROJECT_VERSION:\s*"([^"]+)"/);
  if (!match) throw new Error(`project.yml 中未找到 CURRENT_PROJECT_VERSION: ${projectYmlPath}`);
  return match[1];
}

export function isSemVer(value: string): boolean {
  return /^\d+\.\d+\.\d+$/.test(value);
}
