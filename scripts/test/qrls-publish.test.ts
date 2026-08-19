import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  collectSparkleAttachments,
  r2PublicUrl,
  readSparkleSignatures,
} from "../qrls-publish";

const sampleAppcast = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <title>1.0.4</title>
      <enclosure url="https://download.qzrzz.com/qcopy/QCopy-1.0.4.zip" sparkle:version="8" sparkle:shortVersionString="1.0.4" length="10" type="application/octet-stream" sparkle:edSignature="zip-sig" />
      <sparkle:deltas>
        <enclosure url="https://download.qzrzz.com/qcopy/QCopy8-7.delta" sparkle:version="8" sparkle:shortVersionString="1.0.4" length="4" type="application/octet-stream" sparkle:deltaFrom="7" sparkle:edSignature="delta-sig" />
      </sparkle:deltas>
    </item>
  </channel>
</rss>
`;

describe("QRls 发布辅助", () => {
  test("r2PublicUrl 使用稳定公开前缀", () => {
    expect(r2PublicUrl("appcast.xml")).toBe(
      "https://download.qzrzz.com/qcopy/appcast.xml",
    );
  });

  test("从 generate_appcast 产物读取当前 build 的 ZIP 与 delta 签名", () => {
    const dir = mkdtempSync(join(tmpdir(), "qcopy-qrls-"));
    const appcastPath = join(dir, "appcast.xml");
    writeFileSync(appcastPath, sampleAppcast);
    const signatures = readSparkleSignatures(appcastPath, "8");
    expect(signatures.zipSignature).toBe("zip-sig");
    expect(signatures.deltas).toEqual([
      {
        name: "QCopy8-7.delta",
        edSignature: "delta-sig",
        deltaFromVersion: "7",
      },
    ]);
  });

  test("collectSparkleAttachments 把签名挂到 ZIP 和 delta 上", () => {
    const dir = mkdtempSync(join(tmpdir(), "qcopy-qrls-"));
    const zipPath = join(dir, "QCopy-1.0.4.zip");
    const notesPath = join(dir, "QCopy-1.0.4.md");
    const deltaPath = join(dir, "QCopy8-7.delta");
    const appcastPath = join(dir, "appcast.xml");
    writeFileSync(zipPath, "zip");
    writeFileSync(notesPath, "notes");
    writeFileSync(deltaPath, "delta");
    writeFileSync(appcastPath, sampleAppcast);

    const files = collectSparkleAttachments(
      {
        dmgPath: join(dir, "missing.dmg"),
        zipPath,
        notesPath,
        appcastPath,
        deltaPaths: [deltaPath],
      },
      "8",
    );

    expect(files).toHaveLength(3);
    expect(files[0]).toMatchObject({
      name: "QCopy-1.0.4.zip",
      edSignature: "zip-sig",
    });
    expect(files[2]).toMatchObject({
      name: "QCopy8-7.delta",
      edSignature: "delta-sig",
      deltaFromVersion: "7",
    });
  });
});
