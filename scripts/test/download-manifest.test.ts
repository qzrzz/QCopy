import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  buildDownloadManifest,
  createFileSha256,
  describeDownloadAsset,
  DOWNLOAD_JSON_PATHS,
  DOWNLOAD_JSON_RELATIVE_PATHS,
  downloadJsonExists,
  githubAssetUrl,
  writeDownloadManifest,
  writeDownloadManifestFiles,
  writeDownloadManifestFromExisting,
} from "../download-manifest";

const CURRENT_TEST_DIR = import.meta.dirname ?? import.meta.dir ?? process.cwd();
const TEST_DIR = join(CURRENT_TEST_DIR, "fixtures");

beforeAll(() => {
  mkdirSync(TEST_DIR, { recursive: true });
});

afterAll(() => {
  rmSync(TEST_DIR, { recursive: true, force: true });
});

describe("官网下载清单 download.json 工具测试", () => {
  test("githubAssetUrl 正确构造 GitHub Release 资产下载链接", () => {
    const url = githubAssetUrl("qzrzz/QCopy", "v1.0.7", "QCopy-1.0.7.dmg");
    expect(url).toBe("https://github.com/qzrzz/QCopy/releases/download/v1.0.7/QCopy-1.0.7.dmg");
  });

  test("createFileSha256 正确计算文件哈希值", async () => {
    const testFile = join(TEST_DIR, "test-file.txt");
    writeFileSync(testFile, "Hello QCopy", "utf8");

    const sha256 = await createFileSha256(testFile);
    // sha256 of "Hello QCopy"
    expect(sha256).toMatch(/^[a-f0-9]{64}$/);
  });

  test("describeDownloadAsset 抛出异常当文件不存在时", async () => {
    await expect(
      describeDownloadAsset(join(TEST_DIR, "non-existent.dmg"), "qzrzz/QCopy", "v1.0.0"),
    ).rejects.toThrow("安装包不存在或为空");
  });

  test("describeDownloadAsset 正确生成资源元数据", async () => {
    const dmgPath = join(TEST_DIR, "QCopy-1.0.7.dmg");
    writeFileSync(dmgPath, "dummy-dmg-binary-data", "utf8");

    const info = await describeDownloadAsset(dmgPath, "qzrzz/QCopy", "v1.0.7");
    expect(info.name).toBe("QCopy-1.0.7.dmg");
    expect(info.url).toBe("https://github.com/qzrzz/QCopy/releases/download/v1.0.7/QCopy-1.0.7.dmg");
    expect(info.size).toBeGreaterThan(0);
    expect(info.sha256).toMatch(/^[a-f0-9]{64}$/);
  });

  test("buildDownloadManifest 构建完整的下载清单对象", async () => {
    const dmgPath = join(TEST_DIR, "QCopy-1.0.7.dmg");
    const zipPath = join(TEST_DIR, "QCopy-1.0.7.zip");
    writeFileSync(dmgPath, "dummy-dmg-content", "utf8");
    writeFileSync(zipPath, "dummy-zip-content", "utf8");

    const publishedAt = "2026-08-14T15:09:09.382Z";
    const manifest = await buildDownloadManifest({
      version: "1.0.7",
      build: "11",
      repository: "qzrzz/QCopy",
      dmgPath,
      zipPath,
      publishedAt,
    });

    expect(manifest.schemaVersion).toBe(1);
    expect(manifest.name).toBe("QCopy");
    expect(manifest.version).toBe("1.0.7");
    expect(manifest.build).toBe("11");
    expect(manifest.tag).toBe("v1.0.7");
    expect(manifest.publishedAt).toBe(publishedAt);
    expect(manifest.htmlUrl).toBe("https://github.com/qzrzz/QCopy/releases/tag/v1.0.7");
    expect(manifest.dmg.name).toBe("QCopy-1.0.7.dmg");
    expect(manifest.dmg.url).toBe("https://github.com/qzrzz/QCopy/releases/download/v1.0.7/QCopy-1.0.7.dmg");
    expect(manifest.dmg.size).toBeGreaterThan(0);
    expect(manifest.dmg.sha256).toBeDefined();
    expect(manifest.zip.name).toBe("QCopy-1.0.7.zip");
    expect(manifest.zip.url).toBe("https://github.com/qzrzz/QCopy/releases/download/v1.0.7/QCopy-1.0.7.zip");
    expect(manifest.zip.size).toBeGreaterThan(0);
    expect(manifest.zip.sha256).toBeDefined();
  });

  test("writeDownloadManifestFiles 成功原子写入指定的目标路径", async () => {
    const target1 = join(TEST_DIR, "out1/download.json");
    const target2 = join(TEST_DIR, "out2/download.json");

    const dmgPath = join(TEST_DIR, "QCopy-1.0.7.dmg");
    const zipPath = join(TEST_DIR, "QCopy-1.0.7.zip");
    const manifest = await buildDownloadManifest({
      version: "1.0.7",
      build: "11",
      repository: "qzrzz/QCopy",
      dmgPath,
      zipPath,
    });

    const written = await writeDownloadManifestFiles(manifest, [target1, target2]);
    expect(written).toEqual([target1, target2]);
    expect(existsSync(target1)).toBe(true);
    expect(existsSync(target2)).toBe(true);

    const parsed1 = JSON.parse(readFileSync(target1, "utf8"));
    expect(parsed1.version).toBe("1.0.7");
    expect(parsed1.name).toBe("QCopy");
  });

  test("DOWNLOAD_JSON_RELATIVE_PATHS 包含 web 和 docs 两个输出路径", () => {
    expect(DOWNLOAD_JSON_RELATIVE_PATHS).toContain("web/download.json");
    expect(DOWNLOAD_JSON_RELATIVE_PATHS).toContain("docs/download.json");
    expect(DOWNLOAD_JSON_RELATIVE_PATHS.length).toBe(2);
  });

  test("downloadJsonExists 准确判断所有清单文件是否存在", () => {
    const path1 = join(TEST_DIR, "exists1.json");
    const path2 = join(TEST_DIR, "exists2.json");
    writeFileSync(path1, "{}", "utf8");

    expect(downloadJsonExists([path1, path2])).toBe(false);
    writeFileSync(path2, "{}", "utf8");
    expect(downloadJsonExists([path1, path2])).toBe(true);
  });

  test("writeDownloadManifestFromExisting 根据本地现有产物生成清单", async () => {
    const targetPath = join(TEST_DIR, "existing-test-download.json");
    const manifest = await writeDownloadManifestFromExisting({
      targetPaths: [targetPath],
    });

    expect(manifest.schemaVersion).toBe(1);
    expect(manifest.name).toBe("QCopy");
    expect(manifest.version).toBeDefined();
    expect(manifest.build).toBeDefined();
    expect(existsSync(targetPath)).toBe(true);

    const content = JSON.parse(readFileSync(targetPath, "utf8"));
    expect(content.dmg.name).toMatch(/^QCopy-.*\.dmg$/);
    expect(content.zip.name).toMatch(/^QCopy-.*\.zip$/);
  });
});
