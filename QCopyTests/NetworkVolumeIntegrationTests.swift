import Foundation
import XCTest
@testable import QCopy

final class NetworkVolumeIntegrationTests: XCTestCase {
    func testMountedNetworkVolumeCompatibility() async throws {
        guard let configuredRoot = ProcessInfo.processInfo.environment["QCOPY_NETWORK_TEST_ROOT"],
              !configuredRoot.isEmpty else {
            throw XCTSkip("设置 QCOPY_NETWORK_TEST_ROOT 后运行网络卷兼容测试")
        }

        let fileManager = FileManager.default
        let networkRoot = URL(fileURLWithPath: configuredRoot, isDirectory: true)
        let remoteFixture = networkRoot
            .appendingPathComponent(".qcopy-network-test-\(UUID().uuidString)", isDirectory: true)
        let localFixture = fileManager.temporaryDirectory
            .appendingPathComponent("QCopyNetworkTest-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: remoteFixture, withIntermediateDirectories: false)
        try fileManager.createDirectory(at: localFixture, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: remoteFixture)
            try? fileManager.removeItem(at: localFixture)
        }

        let directorySource = localFixture.appendingPathComponent("directory-payload", isDirectory: true)
        try fileManager.createDirectory(at: directorySource, withIntermediateDirectories: true)
        try Data("directory-data".utf8).write(to: directorySource.appendingPathComponent("inside.bin"))
        _ = try await run(source: directorySource, destination: remoteFixture, policy: .replace)

        let replaceSource = localFixture.appendingPathComponent("replace.bin")
        try Data("new".utf8).write(to: replaceSource)
        try Data("old".utf8).write(to: remoteFixture.appendingPathComponent("replace.bin"))
        _ = try await run(source: replaceSource, destination: remoteFixture, policy: .replace)

        let skipSource = localFixture.appendingPathComponent("skip.bin")
        try Data("skip-data".utf8).write(to: skipSource)
        _ = try await run(source: skipSource, destination: remoteFixture, policy: .skip)

        let renameSource = localFixture.appendingPathComponent("rename.bin")
        try Data("rename-data".utf8).write(to: renameSource)
        try Data("existing".utf8).write(to: remoteFixture.appendingPathComponent("rename.bin"))
        _ = try await run(source: renameSource, destination: remoteFixture, policy: .rename)

        XCTAssertEqual(
            try Data(contentsOf: remoteFixture.appendingPathComponent("directory-payload/inside.bin")),
            Data("directory-data".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: remoteFixture.appendingPathComponent("replace.bin")),
            Data("new".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: remoteFixture.appendingPathComponent("skip.bin")),
            Data("skip-data".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: remoteFixture.appendingPathComponent("rename copy.bin")),
            Data("rename-data".utf8)
        )
    }

    private func run(
        source: URL,
        destination: URL,
        policy: ConflictPolicy
    ) async throws -> CopyResult {
        try await CopyEngine.run(
            source: source,
            destination: destination,
            mode: .copy,
            conflictPolicy: policy,
            progress: { _ in }
        )
    }
}
