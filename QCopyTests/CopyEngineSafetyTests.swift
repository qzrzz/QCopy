import Darwin
import Foundation
import XCTest
@testable import QCopy

final class CopyEngineSafetyTests: XCTestCase {
    func testMoveSkipRetainsSourceFile() async throws {
        try await withFixture { root in
            let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
            let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
            try createDirectory(sourceDirectory)
            try createDirectory(destinationDirectory)

            let source = sourceDirectory.appendingPathComponent("same.txt")
            let destination = destinationDirectory.appendingPathComponent("same.txt")
            try write("SOURCE-NEW", to: source)
            try write("DESTINATION-OLD", to: destination)

            let result = try await run(
                source: source,
                destination: destinationDirectory,
                mode: .move,
                policy: .skip
            )

            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(try read(source), "SOURCE-NEW")
            XCTAssertEqual(try read(destination), "DESTINATION-OLD")
            XCTAssertEqual(result.filesCopied, 0)
            XCTAssertEqual(result.filesSkipped, 1)
        }
    }

    func testMoveDirectoryOnlyRemovesCommittedItems() async throws {
        try await withFixture { root in
            let source = root.appendingPathComponent("payload", isDirectory: true)
            let destinationRoot = root.appendingPathComponent("destination", isDirectory: true)
            let destination = destinationRoot.appendingPathComponent("payload", isDirectory: true)
            try createDirectory(source)
            try createDirectory(destination)

            let skippedSource = source.appendingPathComponent("conflict.txt")
            let movedSource = source.appendingPathComponent("moved.txt")
            let skippedDestination = destination.appendingPathComponent("conflict.txt")
            let movedDestination = destination.appendingPathComponent("moved.txt")
            try write("SOURCE-CONFLICT", to: skippedSource)
            try write("MOVE-ME", to: movedSource)
            try write("DESTINATION-CONFLICT", to: skippedDestination)

            let result = try await run(
                source: source,
                destination: destinationRoot,
                mode: .move,
                policy: .skip
            )

            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: skippedSource.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: movedSource.path))
            XCTAssertEqual(try read(skippedSource), "SOURCE-CONFLICT")
            XCTAssertEqual(try read(skippedDestination), "DESTINATION-CONFLICT")
            XCTAssertEqual(try read(movedDestination), "MOVE-ME")
            XCTAssertEqual(result.filesCopied, 1)
            XCTAssertEqual(result.filesSkipped, 1)
        }
    }

    func testReplaceNeverDeletesDirectoryForFileCollision() async throws {
        try await withFixture { root in
            let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
            let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
            try createDirectory(sourceDirectory)
            try createDirectory(destinationDirectory)

            let source = sourceDirectory.appendingPathComponent("collision")
            let destination = destinationDirectory.appendingPathComponent("collision", isDirectory: true)
            let valuableFile = destination.appendingPathComponent("valuable.txt")
            try write("NEW-FILE", to: source)
            try createDirectory(destination)
            try write("VALUABLE", to: valuableFile)

            await assertTypeConflict {
                try await self.run(
                    source: source,
                    destination: destinationDirectory,
                    mode: .copy,
                    policy: .replace
                )
            }

            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
            XCTAssertEqual(try read(valuableFile), "VALUABLE")
        }
    }

    func testReplaceOverwritesExistingRegularFile() async throws {
        try await withFixture { root in
            let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
            let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
            try createDirectory(sourceDirectory)
            try createDirectory(destinationDirectory)
            let source = sourceDirectory.appendingPathComponent("same.txt")
            let destination = destinationDirectory.appendingPathComponent("same.txt")
            try write("NEW", to: source)
            try write("OLD", to: destination)

            let result = try await run(
                source: source,
                destination: destinationDirectory,
                mode: .copy,
                policy: .replace
            )

            XCTAssertEqual(try read(source), "NEW")
            XCTAssertEqual(try read(destination), "NEW")
            XCTAssertEqual(result.filesCopied, 1)
            XCTAssertEqual(result.filesSkipped, 0)
        }
    }

    func testDestinationSymlinkIntoSourceIsRejected() async throws {
        try await withFixture { root in
            let source = root.appendingPathComponent("source", isDirectory: true)
            let actualDestination = source.appendingPathComponent("inside", isDirectory: true)
            let destinationLink = root.appendingPathComponent("destination-link", isDirectory: true)
            try createDirectory(actualDestination)
            try write("DATA", to: source.appendingPathComponent("file.txt"))
            try FileManager.default.createSymbolicLink(at: destinationLink, withDestinationURL: actualDestination)

            do {
                _ = try await run(
                    source: source,
                    destination: destinationLink,
                    mode: .copy,
                    policy: .replace
                )
                XCTFail("目标链接指向来源内部时必须拒绝传输")
            } catch let error as CopyError {
                guard case .invalidDestination = error else {
                    return XCTFail("预期 invalidDestination，实际为 \(error)")
                }
            }

            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: actualDestination.appendingPathComponent(source.lastPathComponent).path
                )
            )
        }
    }

    func testDirectoryCollisionDoesNotFollowDestinationSymlink() async throws {
        try await withFixture { root in
            let source = root.appendingPathComponent("payload", isDirectory: true)
            let destinationRoot = root.appendingPathComponent("destination", isDirectory: true)
            let outside = root.appendingPathComponent("outside", isDirectory: true)
            let collisionLink = destinationRoot.appendingPathComponent("payload", isDirectory: true)
            try createDirectory(source)
            try createDirectory(destinationRoot)
            try createDirectory(outside)
            try write("DO-NOT-ESCAPE", to: source.appendingPathComponent("file.txt"))
            try FileManager.default.createSymbolicLink(at: collisionLink, withDestinationURL: outside)

            await assertTypeConflict {
                try await self.run(
                    source: source,
                    destination: destinationRoot,
                    mode: .copy,
                    policy: .replace
                )
            }

            XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("file.txt").path))
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: collisionLink.path), outside.path)
        }
    }

    func testSkipRecognizesDanglingDestinationSymlink() async throws {
        try await withFixture { root in
            let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
            let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
            try createDirectory(sourceDirectory)
            try createDirectory(destinationDirectory)
            let source = sourceDirectory.appendingPathComponent("same.txt")
            let destination = destinationDirectory.appendingPathComponent("same.txt")
            let missingTarget = destinationDirectory.appendingPathComponent("missing.txt")
            try write("SOURCE", to: source)
            try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: missingTarget)

            let result = try await run(
                source: source,
                destination: destinationDirectory,
                mode: .move,
                policy: .skip
            )

            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path), missingTarget.path)
            XCTAssertEqual(result.filesCopied, 0)
            XCTAssertEqual(result.filesSkipped, 1)
        }
    }

    func testBasicFileDatesArePreserved() async throws {
        try await withFixture { root in
            let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
            let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
            try createDirectory(sourceDirectory)
            try createDirectory(destinationDirectory)
            let source = sourceDirectory.appendingPathComponent("dated.txt")
            let sourceDate = Date(timeIntervalSince1970: 946_684_800)
            try write("DATA", to: source)
            try FileManager.default.setAttributes(
                [.modificationDate: sourceDate],
                ofItemAtPath: source.path
            )

            _ = try await run(
                source: source,
                destination: destinationDirectory,
                mode: .copy,
                policy: .replace
            )

            let copied = destinationDirectory.appendingPathComponent("dated.txt")
            let attributes = try FileManager.default.attributesOfItem(atPath: copied.path)
            let copiedDate = try XCTUnwrap(attributes[.modificationDate] as? Date)
            XCTAssertEqual(copiedDate.timeIntervalSince1970, sourceDate.timeIntervalSince1970, accuracy: 1)
        }
    }

    func testFileAndDirectoryExtendedAttributesArePreserved() async throws {
        try await withFixture { root in
            let source = root.appendingPathComponent("payload", isDirectory: true)
            let nested = source.appendingPathComponent("nested", isDirectory: true)
            let file = nested.appendingPathComponent("data.bin")
            let destinationRoot = root.appendingPathComponent("destination", isDirectory: true)
            try createDirectory(nested)
            try createDirectory(destinationRoot)
            try Data([0, 1, 2, 3]).write(to: file)

            let directoryAttribute = Data("directory-xattr".utf8)
            let fileAttribute = Data("file-xattr".utf8)
            try setExtendedAttribute("com.qzrzz.qcopy.directory-test", value: directoryAttribute, at: source)
            try setExtendedAttribute("com.qzrzz.qcopy.file-test", value: fileAttribute, at: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o751], ofItemAtPath: source.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o701], ofItemAtPath: nested.path)

            _ = try await run(
                source: source,
                destination: destinationRoot,
                mode: .copy,
                policy: .replace
            )

            let copied = destinationRoot.appendingPathComponent("payload", isDirectory: true)
            let copiedNested = copied.appendingPathComponent("nested", isDirectory: true)
            let copiedFile = copiedNested.appendingPathComponent("data.bin")
            XCTAssertEqual(
                try extendedAttribute("com.qzrzz.qcopy.directory-test", at: copied),
                directoryAttribute
            )
            XCTAssertEqual(
                try extendedAttribute("com.qzrzz.qcopy.file-test", at: copiedFile),
                fileAttribute
            )
            XCTAssertEqual(try permissions(at: copied), 0o751)
            XCTAssertEqual(try permissions(at: copiedNested), 0o701)
        }
    }

    func testMergingDirectoryDoesNotOverwriteExistingDirectoryMetadata() async throws {
        try await withFixture { root in
            let source = root.appendingPathComponent("payload", isDirectory: true)
            let destinationRoot = root.appendingPathComponent("destination", isDirectory: true)
            let existingDestination = destinationRoot.appendingPathComponent("payload", isDirectory: true)
            try createDirectory(source)
            try createDirectory(existingDestination)
            try write("DATA", to: source.appendingPathComponent("file.txt"))

            let attributeName = "com.qzrzz.qcopy.merge-test"
            try setExtendedAttribute(attributeName, value: Data("source".utf8), at: source)
            try setExtendedAttribute(attributeName, value: Data("destination".utf8), at: existingDestination)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o711], ofItemAtPath: existingDestination.path)

            _ = try await run(
                source: source,
                destination: destinationRoot,
                mode: .copy,
                policy: .replace
            )

            XCTAssertEqual(try extendedAttribute(attributeName, at: existingDestination), Data("destination".utf8))
            XCTAssertEqual(try permissions(at: existingDestination), 0o711)
            XCTAssertEqual(try read(existingDestination.appendingPathComponent("file.txt")), "DATA")
        }
    }

    func testSymbolicLinkIsCopiedWithoutFollowingItsTarget() async throws {
        try await withFixture { root in
            let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
            let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
            try createDirectory(sourceDirectory)
            try createDirectory(destinationDirectory)
            let source = sourceDirectory.appendingPathComponent("dangling-link")
            try FileManager.default.createSymbolicLink(
                atPath: source.path,
                withDestinationPath: "relative-missing-target"
            )

            _ = try await run(
                source: source,
                destination: destinationDirectory,
                mode: .copy,
                policy: .replace
            )

            let copied = destinationDirectory.appendingPathComponent("dangling-link")
            let info = try lstatInfo(copied)
            XCTAssertEqual(info.st_mode & S_IFMT, S_IFLNK)
            XCTAssertEqual(
                try FileManager.default.destinationOfSymbolicLink(atPath: copied.path),
                "relative-missing-target"
            )
        }
    }

    func testSparseFileRemainsSparse() async throws {
        try await withFixture { root in
            let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
            let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
            try createDirectory(sourceDirectory)
            try createDirectory(destinationDirectory)
            let source = sourceDirectory.appendingPathComponent("sparse.bin")
            let logicalSize: Int64 = 64 * 1024 * 1024
            try createSparseFile(at: source, logicalSize: logicalSize)

            let sourceInfo = try lstatInfo(source)
            let sourceAllocatedBytes = Int64(sourceInfo.st_blocks) * 512
            if sourceAllocatedBytes >= logicalSize / 4 {
                throw XCTSkip("当前测试文件系统未创建出稀疏文件")
            }

            _ = try await run(
                source: source,
                destination: destinationDirectory,
                mode: .copy,
                policy: .replace
            )

            let copied = destinationDirectory.appendingPathComponent("sparse.bin")
            let copiedInfo = try lstatInfo(copied)
            let copiedAllocatedBytes = Int64(copiedInfo.st_blocks) * 512
            XCTAssertEqual(Int64(copiedInfo.st_size), logicalSize)
            XCTAssertLessThan(copiedAllocatedBytes, logicalSize / 4)
        }
    }

    func testFileSizeMismatchIsReported() async throws {
        try await withFixture { root in
            let target = root.appendingPathComponent("wrong-size.bin")
            try write("1234", to: target)

            XCTAssertThrowsError(try CopyEngine.verifyFileSize(at: target, expectedSize: 3)) { error in
                guard case let CopyError.sizeMismatch(path, expected, actual) = error else {
                    return XCTFail("预期尺寸校验错误，实际为 \(error)")
                }
                XCTAssertEqual(path, target.path)
                XCTAssertEqual(expected, 3)
                XCTAssertEqual(actual, 4)
            }
        }
    }

    func testSameVolumeMoveUsesAtomicRenameFastPath() async throws {
        try await withFixture { root in
            let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
            let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
            try createDirectory(sourceDirectory)
            try createDirectory(destinationDirectory)
            let source = sourceDirectory.appendingPathComponent("move-me.txt")
            try write("MOVE", to: source)
            let recorder = ProgressRecorder()

            _ = try await CopyEngine.run(
                source: source,
                destination: destinationDirectory,
                mode: .move,
                conflictPolicy: .replace,
                progress: { recorder.record($0.phase) }
            )

            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(try read(destinationDirectory.appendingPathComponent("move-me.txt")), "MOVE")
            XCTAssertTrue(recorder.phases().contains("同卷快速移动"))
        }
    }

    func testDanglingSymbolicLinkCanBeMovedAtomically() async throws {
        try await withFixture { root in
            let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
            let destinationDirectory = root.appendingPathComponent("destination", isDirectory: true)
            try createDirectory(sourceDirectory)
            try createDirectory(destinationDirectory)
            let source = sourceDirectory.appendingPathComponent("dangling-link")
            try FileManager.default.createSymbolicLink(
                atPath: source.path,
                withDestinationPath: "still-missing"
            )

            _ = try await run(
                source: source,
                destination: destinationDirectory,
                mode: .move,
                policy: .replace
            )

            let moved = destinationDirectory.appendingPathComponent("dangling-link")
            XCTAssertThrowsError(try lstatInfo(source))
            XCTAssertEqual(try lstatInfo(moved).st_mode & S_IFMT, S_IFLNK)
            XCTAssertEqual(
                try FileManager.default.destinationOfSymbolicLink(atPath: moved.path),
                "still-missing"
            )
        }
    }

    func testSmartParallelCopiesManySmallFiles() async throws {
        try await withFixture { root in
            let source = root.appendingPathComponent("many-small-files", isDirectory: true)
            let destination = root.appendingPathComponent("destination", isDirectory: true)
            try createDirectory(source)
            try createDirectory(destination)

            for index in 0..<48 {
                try write("payload-\(index)", to: source.appendingPathComponent("file-\(index).txt"))
            }

            let result = try await run(
                source: source,
                destination: destination,
                mode: .copy,
                policy: .replace,
                smartParallel: true
            )

            XCTAssertEqual(result.filesCopied, 48)
            XCTAssertEqual(result.filesSkipped, 0)
            for index in 0..<48 {
                XCTAssertEqual(
                    try read(destination.appendingPathComponent("many-small-files/file-\(index).txt")),
                    "payload-\(index)"
                )
            }
        }
    }

    func testProgressReportsCurrentConcurrency() async throws {
        try await withFixture { root in
            let source = root.appendingPathComponent("concurrency-source", isDirectory: true)
            let destination = root.appendingPathComponent("concurrency-destination", isDirectory: true)
            try createDirectory(source)
            try createDirectory(destination)
            for index in 0..<16 {
                try write("payload-\(index)", to: source.appendingPathComponent("file-\(index).txt"))
            }

            let recorder = ProgressRecorder()
            _ = try await CopyEngine.run(
                source: source,
                destination: destination,
                mode: .copy,
                conflictPolicy: .replace,
                smartParallel: true,
                progress: { recorder.recordConcurrency($0.currentConcurrency) }
            )

            let values = recorder.concurrencies()
            XCTAssertFalse(values.isEmpty)
            XCTAssertTrue(values.allSatisfy { $0 >= 1 })
            // 文件很小时，worker 可能在其它首批任务获得槽位前就完成；
            // 这里验证 UI 收到真实的并行活动，而不把瞬时峰值误当成固定上限。
            XCTAssertGreaterThan(values.max() ?? 0, 1)
        }
    }

    func testAdaptiveParallelTunerIncreasesAndDecreasesConcurrency() {
        var tuner = AdaptiveParallelTuner()
        XCTAssertEqual(tuner.maximumConcurrency, 32)
        let initial = tuner.concurrency

        for _ in 0..<8 {
            tuner.observe(bytes: 1_000_000, duration: 1)
        }
        for _ in 0..<8 {
            tuner.observe(bytes: 2_000_000, duration: 1)
        }
        let increased = tuner.concurrency
        XCTAssertGreaterThan(increased, initial)

        for _ in 0..<8 {
            tuner.observe(bytes: 100_000, duration: 1)
        }
        XCTAssertLessThan(tuner.concurrency, increased)
    }

    func testAdaptiveParallelTunerCanGrowToGlobalMaximum() {
        var tuner = AdaptiveParallelTuner()
        for _ in 0..<1_000 {
            tuner.observe(bytes: 2_000_000, duration: 1)
        }
        XCTAssertEqual(tuner.concurrency, AdaptiveParallelTuner.maximumConcurrencyLimit)
    }

    func testAdaptiveParallelTunerSelectsInitialConcurrencyByFileSize() {
        let megabyte: Int64 = 1024 * 1024
        let cases: [(Int64, Int)] = [
            (0, 16),
            (megabyte - 1, 16),
            (megabyte, 12),
            (8 * megabyte - 1, 12),
            (8 * megabyte, 8),
            (16 * megabyte, 4),
            (32 * megabyte, 2),
            (64 * megabyte - 1, 2),
            (64 * megabyte, 2),
            (500 * megabyte - 1, 1),
            (500 * megabyte, 1)
        ]

        for (size, expected) in cases {
            var tuner = AdaptiveParallelTuner()
            tuner.prepare(forFileSize: size)
            XCTAssertEqual(tuner.concurrency, expected, "文件大小 \(size) 应从 \(expected) 路开始")
        }
    }

    func testAdaptiveParallelTunerUsesAtMostThirtyTwoPrefetchedFiles() {
        XCTAssertEqual(AdaptiveParallelTuner.prefetchBatchSize, 32)
        XCTAssertTrue(AdaptiveParallelTuner.isParallelEligible(fileSize: 499 * 1024 * 1024))
        XCTAssertFalse(AdaptiveParallelTuner.isParallelEligible(fileSize: 500 * 1024 * 1024))

        var tuner = AdaptiveParallelTuner()
        XCTAssertEqual(tuner.prefetchLimit, 32)
        tuner.markBatchStarted()
        XCTAssertEqual(tuner.prefetchLimit, 32)
    }

    func testAdaptiveParallelTunerChoosesBatchStartFromObservedSizes() {
        let megabyte: Int64 = 1024 * 1024
        XCTAssertEqual(
            AdaptiveParallelTuner.initialConcurrency(forFileSizes: [
                2 * megabyte,
                12 * megabyte,
                40 * megabyte
            ]),
            8
        )
        XCTAssertEqual(
            AdaptiveParallelTuner.initialConcurrency(forFileSizes: [
                80 * megabyte,
                120 * megabyte
            ]),
            1
        )
        XCTAssertEqual(
            AdaptiveParallelTuner.maximumSafeConcurrency(forFileSize: 2 * megabyte),
            32
        )
        XCTAssertEqual(
            AdaptiveParallelTuner.maximumSafeConcurrency(forFileSize: 40 * megabyte),
            2
        )
        XCTAssertEqual(
            AdaptiveParallelTuner.maximumSafeConcurrency(forFileSize: 80 * megabyte),
            1
        )
    }

    func testFilesOver500MBAreAlwaysTransferredSerially() async throws {
        try await withFixture { root in
            let source = root.appendingPathComponent("large-source", isDirectory: true)
            let destination = root.appendingPathComponent("large-destination", isDirectory: true)
            try createDirectory(source)
            try createDirectory(destination)

            let largeFile = source.appendingPathComponent("large.bin")
            try createSparseFile(
                at: largeFile,
                logicalSize: 500 * 1024 * 1024 + 1
            )

            let recorder = ProgressRecorder()
            _ = try await CopyEngine.run(
                source: source,
                destination: destination,
                mode: .copy,
                conflictPolicy: .replace,
                smartParallel: true,
                progress: { recorder.recordConcurrency($0.currentConcurrency) }
            )

            XCTAssertFalse(recorder.concurrencies().isEmpty)
            XCTAssertEqual(recorder.concurrencies().max(), 1)
        }
    }

    private func run(
        source: URL,
        destination: URL,
        mode: TransferMode,
        policy: ConflictPolicy,
        smartParallel: Bool = true
    ) async throws -> CopyResult {
        try await CopyEngine.run(
            source: source,
            destination: destination,
            mode: mode,
            conflictPolicy: policy,
            smartParallel: smartParallel,
            progress: { _ in }
        )
    }

    private func assertTypeConflict(
        operation: () async throws -> CopyResult
    ) async {
        do {
            _ = try await operation()
            XCTFail("文件与目录类型冲突时必须停止")
        } catch let error as CopyError {
            guard case .typeConflict = error else {
                return XCTFail("预期 typeConflict，实际为 \(error)")
            }
        } catch {
            XCTFail("预期 CopyError.typeConflict，实际为 \(error)")
        }
    }

    private func withFixture(
        operation: (URL) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QCopyTests-\(UUID().uuidString)", isDirectory: true)
        try createDirectory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        try await operation(root)
    }

    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? Int)
    }

    private func setExtendedAttribute(_ name: String, value: Data, at url: URL) throws {
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return name.withCString { attributeName in
                value.withUnsafeBytes { buffer in
                    Darwin.setxattr(path, attributeName, buffer.baseAddress, buffer.count, 0, 0)
                }
            }
        }
        guard result == 0 else { throw currentPOSIXError() }
    }

    private func extendedAttribute(_ name: String, at url: URL) throws -> Data {
        let size = url.withUnsafeFileSystemRepresentation { path -> Int in
            guard let path else { return -1 }
            return name.withCString { attributeName in
                Darwin.getxattr(path, attributeName, nil, 0, 0, 0)
            }
        }
        guard size >= 0 else { throw currentPOSIXError() }
        var data = Data(count: size)
        let readSize = url.withUnsafeFileSystemRepresentation { path -> Int in
            guard let path else { return -1 }
            return name.withCString { attributeName in
                data.withUnsafeMutableBytes { buffer in
                    Darwin.getxattr(path, attributeName, buffer.baseAddress, buffer.count, 0, 0)
                }
            }
        }
        guard readSize == size else { throw currentPOSIXError() }
        return data
    }

    private func createSparseFile(at url: URL, logicalSize: Int64) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, 0o600)
        }
        guard descriptor >= 0 else { throw currentPOSIXError() }
        defer { Darwin.close(descriptor) }

        guard Darwin.ftruncate(descriptor, off_t(logicalSize)) == 0 else {
            throw currentPOSIXError()
        }
        var firstByte: UInt8 = 0x41
        var lastByte: UInt8 = 0x5A
        let firstWrite = withUnsafePointer(to: &firstByte) {
            Darwin.pwrite(descriptor, $0, 1, 0)
        }
        let lastWrite = withUnsafePointer(to: &lastByte) {
            Darwin.pwrite(descriptor, $0, 1, off_t(logicalSize - 1))
        }
        guard firstWrite == 1, lastWrite == 1 else { throw currentPOSIXError() }
    }

    private func lstatInfo(_ url: URL) throws -> stat {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.lstat(path, &info)
        }
        guard result == 0 else { throw currentPOSIXError() }
        return info
    }

    private func currentPOSIXError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedPhases: [String] = []
    private var recordedConcurrency: [Int] = []

    func record(_ phase: String) {
        lock.lock()
        recordedPhases.append(phase)
        lock.unlock()
    }

    func phases() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPhases
    }

    func recordConcurrency(_ concurrency: Int) {
        lock.lock()
        recordedConcurrency.append(concurrency)
        lock.unlock()
    }

    func concurrencies() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return recordedConcurrency
    }
}
