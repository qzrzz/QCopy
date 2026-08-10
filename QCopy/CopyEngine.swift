import Darwin
import Foundation

enum CopyEngine {
    static func run(
        source: URL,
        destination: URL,
        mode: TransferMode,
        conflictPolicy: ConflictPolicy,
        progress: @escaping @Sendable (CopyProgress) -> Void
    ) async throws -> CopyResult {
        let startedAt = Date()
        let fileManager = FileManager.default
        var state = EngineState()

        try validate(source: source, destination: destination, mode: mode)

        let sourceValues = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let isDirectory = sourceValues.isDirectory == true && sourceValues.isSymbolicLink != true

        if isDirectory {
            let proposed = destination.appendingPathComponent(source.lastPathComponent, isDirectory: true)
            if let rootDestination = try resolveDirectoryDestination(
                proposed,
                source: source,
                policy: conflictPolicy
            ) {
                let rootDestinationExists = try destinationItemKind(at: rootDestination) != nil
                if mode == .move, !rootDestinationExists {
                    switch try renameItem(source: source, target: rootDestination, exclusive: true) {
                    case .moved:
                        state.filesCopied = 1
                        emit(
                            state: state,
                            phase: "同卷快速移动",
                            currentFile: source.lastPathComponent,
                            progress: progress
                        )
                        return CopyResult(
                            bytesCopied: 0,
                            filesCopied: 1,
                            filesSkipped: 0,
                            duration: Date().timeIntervalSince(startedAt)
                        )
                    case .destinationExists:
                        throw CopyError.destinationChanged(rootDestination.path)
                    case .crossDevice, .unavailable:
                        break
                    }
                }
                try fileManager.createDirectory(at: rootDestination, withIntermediateDirectories: true)
                try copyDirectory(
                    source: source,
                    target: rootDestination,
                    targetWasCreated: !rootDestinationExists,
                    mode: mode,
                    fileManager: fileManager,
                    conflictPolicy: conflictPolicy,
                    state: &state,
                    progress: progress
                )
            } else {
                state.filesSkipped += 1
                emit(state: state, phase: "已跳过", currentFile: source.lastPathComponent, progress: progress)
            }
        } else {
            let proposed = destination.appendingPathComponent(source.lastPathComponent)
            try transferLeaf(
                source: source,
                proposedTarget: proposed,
                mode: mode,
                conflictPolicy: conflictPolicy,
                state: &state,
                progress: progress
            )
        }

        return CopyResult(
            bytesCopied: state.bytesCopied,
            filesCopied: state.filesCopied,
            filesSkipped: state.filesSkipped,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    private static func validate(source: URL, destination: URL, mode: TransferMode) throws {
        let fileManager = FileManager.default
        let destinationPath = destination.standardizedFileURL.path
        guard try sourceExistsWithoutFollowingSymlinks(source) else {
            throw CopyError.sourceUnavailable
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destinationPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CopyError.invalidDestination("目标位置不是文件夹")
        }

        // standardizedFileURL 不会解析符号链接。安全校验必须基于实际落盘位置，
        // 否则目标链接可以绕过「目标位于来源内部」检查，造成递归复制自身。
        let canonicalSource = source.resolvingSymlinksInPath().standardizedFileURL
        let canonicalDestination = destination.resolvingSymlinksInPath().standardizedFileURL
        guard canonicalSource.path != canonicalDestination.path else {
            throw CopyError.invalidDestination("来源和目标不能是同一个位置")
        }
        if isSameOrDescendant(canonicalDestination, of: canonicalSource) {
            throw CopyError.invalidDestination("目标不能位于来源文件夹内部")
        }

        // 移动(删除)模式下,系统敏感目录禁止作为来源
        if mode == .move {
            try validateMoveSource(source, fileManager: fileManager)
        }

        // 文件复制到自身所在目录也必须拒绝。即使数据内容最终相同，原子替换仍会
        // 改变文件身份和部分元数据；目录则还可能在遍历中看到新生成的目标。
        let proposedRoot = canonicalDestination.appendingPathComponent(source.lastPathComponent)
        let canonicalProposedRoot = proposedRoot.resolvingSymlinksInPath().standardizedFileURL
        if canonicalProposedRoot.path == canonicalSource.path {
            throw CopyError.invalidDestination("目标位置就是来源本身,无法进行传输")
        }
    }

    /// 移动(删除)模式下的系统敏感目录,禁止作为来源
    private static let protectedPaths: Set<String> = [
        "/", "/System", "/Library", "/Users", "/Applications", "/Volumes",
        "/private", "/bin", "/sbin", "/usr", "/etc", "/tmp", "/var", "/dev",
        "/cores", "/home", "/net", "/opt", "/Network",
    ]

    private static func validateMoveSource(_ source: URL, fileManager: FileManager) throws {
        let path = source.standardizedFileURL.path
        if protectedPaths.contains(path) {
            throw CopyError.protectedSource(path)
        }
        // 用户主目录
        if path == fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path {
            throw CopyError.protectedSource(path)
        }
        // 任何已挂载磁盘的根目录(如 /Volumes/xxx)
        if let volumes = fileManager.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) {
            let volumeRoots = Set(volumes.map { $0.standardizedFileURL.path })
            if volumeRoots.contains(path) {
                throw CopyError.protectedSource(path)
            }
        }
    }

    private static func resolveDirectoryDestination(
        _ proposed: URL,
        source: URL,
        policy: ConflictPolicy
    ) throws -> URL? {
        guard let destinationKind = try destinationItemKind(at: proposed) else {
            return proposed
        }
        if destinationKind == .directory {
            return proposed
        }
        switch policy {
        case .replace:
            throw CopyError.typeConflict(source: source.path, destination: proposed.path)
        case .skip:
            return nil
        case .rename:
            return try uniqueURL(for: proposed)
        }
    }

    private static func copyDirectory(
        source: URL,
        target: URL,
        targetWasCreated: Bool,
        mode: TransferMode,
        fileManager: FileManager,
        conflictPolicy: ConflictPolicy,
        state: inout EngineState,
        progress: @escaping @Sendable (CopyProgress) -> Void
    ) throws {
        var enumerationError: CopyError?
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { url, error in
                enumerationError = .cannotReadItem(path: url.path, reason: error.localizedDescription)
                return false
            }
        ) else {
            throw CopyError.cannotReadSource
        }

        var directoryTargets: [String: URL] = [source.standardizedFileURL.path: target]
        var sourceDirectories: [URL] = [source]
        var createdDirectories: [DirectoryMetadataPair] = targetWasCreated
            ? [DirectoryMetadataPair(source: source, target: target)]
            : []

        while let item = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let parentKey = item.deletingLastPathComponent().standardizedFileURL.path
            guard let targetParent = directoryTargets[parentKey] else {
                throw CopyError.cannotReadItem(path: item.path, reason: "无法确定目标父目录")
            }
            let destinationURL = targetParent.appendingPathComponent(item.lastPathComponent)
            let values = try item.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )

            if values.isDirectory == true && values.isSymbolicLink != true {
                sourceDirectories.append(item)
                var resolvedDirectory = destinationURL
                var directoryWasCreated = false
                if let destinationKind = try destinationItemKind(at: destinationURL) {
                    if destinationKind != .directory {
                        switch conflictPolicy {
                        case .replace:
                            throw CopyError.typeConflict(source: item.path, destination: destinationURL.path)
                        case .skip:
                            enumerator.skipDescendants()
                            state.filesSkipped += 1
                            emit(state: state, phase: "已跳过", currentFile: item.lastPathComponent, progress: progress)
                            continue
                        case .rename:
                            resolvedDirectory = try uniqueURL(for: destinationURL)
                            directoryWasCreated = true
                        }
                    }
                } else {
                    directoryWasCreated = true
                }
                try fileManager.createDirectory(at: resolvedDirectory, withIntermediateDirectories: true)
                directoryTargets[item.standardizedFileURL.path] = resolvedDirectory
                if directoryWasCreated {
                    createdDirectories.append(DirectoryMetadataPair(source: item, target: resolvedDirectory))
                }
                continue
            }

            guard values.isSymbolicLink == true || values.isRegularFile == true else {
                throw CopyError.unsupportedItem(item.path)
            }

            try transferLeaf(
                source: item,
                proposedTarget: destinationURL,
                mode: mode,
                conflictPolicy: conflictPolicy,
                state: &state,
                progress: progress
            )
        }

        if let enumerationError {
            throw enumerationError
        }

        // 目录权限必须在内容完成后再恢复，否则只读权限或 ACL 可能阻止后续写入。
        // 只处理本次创建的目录；合并到已有目录时保留目标目录自身的元数据。
        for pair in createdDirectories.reversed() {
            try Task.checkCancellation()
            try copyDirectoryMetadata(from: pair.source, to: pair.target)
        }

        if mode == .move {
            try removeEmptySourceDirectories(sourceDirectories.reversed())
        }
    }

    private static func transferLeaf(
        source: URL,
        proposedTarget: URL,
        mode: TransferMode,
        conflictPolicy: ConflictPolicy,
        state: inout EngineState,
        progress: @escaping @Sendable (CopyProgress) -> Void
    ) throws {
        for _ in 0..<32 {
            try Task.checkCancellation()
            guard let target = try resolveLeafDestination(
                proposedTarget,
                source: source,
                policy: conflictPolicy
            ) else {
                state.filesSkipped += 1
                emit(state: state, phase: "已跳过", currentFile: source.lastPathComponent, progress: progress)
                return
            }

            let targetKind = try destinationItemKind(at: target)
            let replaceExisting = conflictPolicy == .replace && targetKind != nil

            if mode == .move {
                switch try renameItem(source: source, target: target, exclusive: !replaceExisting) {
                case .moved:
                    let size = try logicalSize(of: target)
                    state.bytesCopied += size
                    state.totalBytes += size
                    state.filesCopied += 1
                    emit(
                        state: state,
                        phase: "同卷快速移动",
                        currentFile: source.lastPathComponent,
                        progress: progress
                    )
                    return
                case .destinationExists:
                    continue
                case .crossDevice, .unavailable:
                    break
                }
            }

            let copyResult = try copyToTemporaryAndCommit(
                source: source,
                target: target,
                replaceExisting: replaceExisting,
                baseState: state,
                progress: progress
            )
            guard copyResult.committed else {
                continue
            }

            state.bytesCopied += copyResult.logicalSize
            state.totalBytes += copyResult.logicalSize
            state.filesCopied += 1
            emit(
                state: state,
                phase: copyResult.wasCloned ? "APFS 快速克隆" : "传输中",
                currentFile: source.lastPathComponent,
                progress: progress
            )

            if mode == .move {
                try Task.checkCancellation()
                try unlinkSourceLeaf(source)
            }
            return
        }

        throw CopyError.destinationChanged(proposedTarget.path)
    }

    /// 生成目标同目录下的隐藏临时文件路径(保证同卷,可原子交换)
    private static func temporaryURL(near target: URL) -> URL {
        let parent = target.deletingLastPathComponent()
        let name = ".\(target.lastPathComponent).qcopy-tmp-\(UUID().uuidString)"
        return parent.appendingPathComponent(name)
    }

    private static func resolveLeafDestination(
        _ proposed: URL,
        source: URL,
        policy: ConflictPolicy
    ) throws -> URL? {
        guard let destinationKind = try destinationItemKind(at: proposed) else { return proposed }
        if (destinationKind == .directory || destinationKind == .other) && policy == .replace {
            throw CopyError.typeConflict(source: source.path, destination: proposed.path)
        }
        switch policy {
        case .replace:
            return proposed
        case .skip:
            return nil
        case .rename:
            return try uniqueURL(for: proposed)
        }
    }

    private static func copyToTemporaryAndCommit(
        source: URL,
        target: URL,
        replaceExisting: Bool,
        baseState: EngineState,
        progress: @escaping @Sendable (CopyProgress) -> Void
    ) throws -> NativeCopyResult {
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true || values.isSymbolicLink == true else {
            throw CopyError.unsupportedItem(source.path)
        }

        let logicalSize = Int64(values.fileSize ?? 0)
        let tempURL = temporaryURL(near: target)
        defer { unlinkTemporaryIfPresent(tempURL) }

        let context = CopyfileCallbackContext { copiedBytes in
            progress(CopyProgress(
                phase: "传输中",
                currentFile: source.lastPathComponent,
                bytesCopied: baseState.bytesCopied + min(copiedBytes, logicalSize),
                totalBytes: baseState.totalBytes + logicalSize,
                filesCopied: baseState.filesCopied,
                filesSkipped: baseState.filesSkipped
            ))
        }
        guard let copyState = copyfile_state_alloc() else {
            throw CopyError.cannotCopy(path: source.path, reason: "无法分配 copyfile 状态")
        }
        defer { copyfile_state_free(copyState) }

        let contextPointer = Unmanaged.passUnretained(context).toOpaque()
        let callbackPointer = unsafeBitCast(copyfileStatusCallback, to: UnsafeRawPointer.self)
        guard copyfile_state_set(copyState, UInt32(COPYFILE_STATE_STATUS_CB), callbackPointer) == 0,
              copyfile_state_set(copyState, UInt32(COPYFILE_STATE_STATUS_CTX), contextPointer) == 0 else {
            throw CopyError.cannotCopy(path: source.path, reason: "无法配置 copyfile 回调")
        }

        var flags = COPYFILE_ALL | COPYFILE_EXCL | COPYFILE_NOFOLLOW_SRC | COPYFILE_NOFOLLOW_DST
        if values.isRegularFile == true {
            flags |= COPYFILE_CLONE | COPYFILE_DATA_SPARSE
        }
        let copyCall = withFileSystemRepresentations(source, tempURL) { sourcePath, targetPath in
            copyfile(sourcePath, targetPath, copyState, copyfile_flags_t(flags))
        }
        guard copyCall.result == 0 else {
            if copyCall.errorCode == ECANCELED || Task.isCancelled {
                throw CancellationError()
            }
            throw CopyError.cannotCopy(path: source.path, reason: posixMessage(copyCall.errorCode))
        }

        try Task.checkCancellation()
        var wasCloned = false
        _ = copyfile_state_get(copyState, UInt32(COPYFILE_STATE_WAS_CLONED), &wasCloned)

        switch try commitTemporary(tempURL, target: target, replaceExisting: replaceExisting) {
        case .moved:
            return NativeCopyResult(
                committed: true,
                logicalSize: logicalSize,
                wasCloned: wasCloned
            )
        case .destinationExists:
            return NativeCopyResult(committed: false, logicalSize: 0, wasCloned: false)
        case .crossDevice, .unavailable:
            throw CopyError.cannotCommit(path: target.path, reason: "目标文件系统不支持安全原子提交")
        }
    }

    private static func commitTemporary(
        _ temp: URL,
        target: URL,
        replaceExisting: Bool
    ) throws -> RenameResult {
        let outcome = try renameItem(source: temp, target: target, exclusive: !replaceExisting)
        guard outcome == .unavailable else { return outcome }

        // 少数文件系统不支持 RENAME_EXCL。对叶子对象可用 linkat 原子占位，
        // 成功后再 unlink 临时名，仍不会覆盖并发出现的目标。
        let linkResult = withFileSystemRepresentations(temp, target) { sourcePath, targetPath in
            Darwin.linkat(AT_FDCWD, sourcePath, AT_FDCWD, targetPath, 0)
        }
        if linkResult.result == 0 {
            unlinkTemporaryIfPresent(temp)
            return .moved
        }
        if linkResult.errorCode == EEXIST {
            return .destinationExists
        }
        throw CopyError.cannotCommit(path: target.path, reason: posixMessage(linkResult.errorCode))
    }

    private static func renameItem(source: URL, target: URL, exclusive: Bool) throws -> RenameResult {
        let result = withFileSystemRepresentations(source, target) { sourcePath, targetPath in
            if exclusive {
                return Darwin.renamex_np(sourcePath, targetPath, UInt32(RENAME_EXCL))
            }
            return Darwin.rename(sourcePath, targetPath)
        }
        if result.result == 0 { return .moved }
        switch result.errorCode {
        case EEXIST: return .destinationExists
        case EXDEV: return .crossDevice
        case ENOTSUP: return .unavailable
        default:
            throw CopyError.cannotCommit(path: target.path, reason: posixMessage(result.errorCode))
        }
    }

    private static func logicalSize(of url: URL) throws -> Int64 {
        let result = url.withUnsafeFileSystemRepresentation { path -> LStatSizeResult in
            guard let path else { return LStatSizeResult(status: -1, errorCode: EINVAL, size: 0) }
            var info = stat()
            let status = Darwin.lstat(path, &info)
            return LStatSizeResult(
                status: status,
                errorCode: status == 0 ? 0 : errno,
                size: status == 0 ? Int64(info.st_size) : 0
            )
        }
        guard result.status == 0 else {
            throw CopyError.cannotReadItem(path: url.path, reason: posixMessage(result.errorCode))
        }
        return result.size
    }

    private static func copyDirectoryMetadata(from source: URL, to target: URL) throws {
        let sourceFD = source.withUnsafeFileSystemRepresentation { path -> POSIXResult in
            guard let path else { return POSIXResult(result: -1, errorCode: EINVAL) }
            let descriptor = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            return POSIXResult(result: descriptor, errorCode: descriptor >= 0 ? 0 : errno)
        }
        guard sourceFD.result >= 0 else {
            throw CopyError.cannotCopy(path: source.path, reason: posixMessage(sourceFD.errorCode))
        }
        defer { Darwin.close(sourceFD.result) }

        let targetFD = target.withUnsafeFileSystemRepresentation { path -> POSIXResult in
            guard let path else { return POSIXResult(result: -1, errorCode: EINVAL) }
            let descriptor = Darwin.open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            return POSIXResult(result: descriptor, errorCode: descriptor >= 0 ? 0 : errno)
        }
        guard targetFD.result >= 0 else {
            throw CopyError.cannotCopy(path: target.path, reason: posixMessage(targetFD.errorCode))
        }
        defer { Darwin.close(targetFD.result) }

        let result = Darwin.fcopyfile(
            sourceFD.result,
            targetFD.result,
            nil,
            copyfile_flags_t(COPYFILE_METADATA)
        )
        guard result == 0 else {
            throw CopyError.cannotCopy(path: source.path, reason: posixMessage(errno))
        }
    }

    private static func unlinkTemporaryIfPresent(_ url: URL) {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            // 临时路径即使被外部进程替换成目录也绝不递归删除。
            _ = Darwin.unlink(path)
        }
    }

    private static func unlinkSourceLeaf(_ source: URL) throws {
        let result = source.withUnsafeFileSystemRepresentation { path -> POSIXResult in
            guard let path else { return POSIXResult(result: -1, errorCode: EINVAL) }
            let result = Darwin.unlink(path)
            return POSIXResult(result: result, errorCode: result == 0 ? 0 : errno)
        }
        guard result.result == 0 else {
            throw CopyError.cannotRemoveSource(path: source.path, reason: posixMessage(result.errorCode))
        }
    }

    private static func removeEmptySourceDirectories<S: Sequence>(_ directories: S) throws where S.Element == URL {
        for directory in directories {
            try Task.checkCancellation()
            let result = directory.withUnsafeFileSystemRepresentation { path -> POSIXResult in
                guard let path else { return POSIXResult(result: -1, errorCode: EINVAL) }
                let result = Darwin.rmdir(path)
                return POSIXResult(result: result, errorCode: result == 0 ? 0 : errno)
            }
            if result.result == 0 || result.errorCode == ENOENT {
                continue
            }
            // 目录仍含有跳过项或传输期间新增的内容时必须保留，绝不递归删除。
            if result.errorCode == ENOTEMPTY || result.errorCode == EEXIST {
                continue
            }
            throw CopyError.cannotRemoveSource(path: directory.path, reason: posixMessage(result.errorCode))
        }
    }

    private static func withFileSystemRepresentations(
        _ source: URL,
        _ destination: URL,
        operation: (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32
    ) -> POSIXResult {
        source.withUnsafeFileSystemRepresentation { sourcePath in
            guard let sourcePath else { return POSIXResult(result: -1, errorCode: EINVAL) }
            return destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let destinationPath else { return POSIXResult(result: -1, errorCode: EINVAL) }
                let result = operation(sourcePath, destinationPath)
                return POSIXResult(result: result, errorCode: result == 0 ? 0 : errno)
            }
        }
    }

    private static func posixMessage(_ errorCode: Int32) -> String {
        String(cString: strerror(errorCode))
    }

    private static func isSameOrDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootComponents = root.standardizedFileURL.pathComponents
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }

    private static func destinationItemKind(at url: URL) throws -> DestinationItemKind? {
        let result = url.withUnsafeFileSystemRepresentation { path -> LStatResult in
            guard let path else {
                return LStatResult(status: -1, errorCode: EINVAL, mode: 0)
            }
            var info = stat()
            let status = Darwin.lstat(path, &info)
            return LStatResult(
                status: status,
                errorCode: status == 0 ? 0 : errno,
                mode: status == 0 ? info.st_mode : 0
            )
        }
        if result.status == 0 {
            switch result.mode & S_IFMT {
            case S_IFDIR: return .directory
            case S_IFREG: return .regularFile
            case S_IFLNK: return .symbolicLink
            default: return .other
            }
        }
        if result.errorCode == ENOENT {
            return nil
        }
        throw CopyError.cannotInspectDestination(path: url.path, reason: posixMessage(result.errorCode))
    }

    private static func sourceExistsWithoutFollowingSymlinks(_ url: URL) throws -> Bool {
        let result = url.withUnsafeFileSystemRepresentation { path -> POSIXResult in
            guard let path else { return POSIXResult(result: -1, errorCode: EINVAL) }
            var info = stat()
            let status = Darwin.lstat(path, &info)
            return POSIXResult(result: status, errorCode: status == 0 ? 0 : errno)
        }
        if result.result == 0 { return true }
        if result.errorCode == ENOENT { return false }
        throw CopyError.cannotReadItem(path: url.path, reason: posixMessage(result.errorCode))
    }

    private static func uniqueURL(for url: URL) throws -> URL {
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let parent = url.deletingLastPathComponent()
        var index = 2
        var candidate = parent.appendingPathComponent("\(stem) copy\(ext.isEmpty ? "" : ".\(ext)")")
        while try destinationItemKind(at: candidate) != nil {
            candidate = parent.appendingPathComponent("\(stem) copy \(index)\(ext.isEmpty ? "" : ".\(ext)")")
            index += 1
        }
        return candidate
    }

    private static func emit(
        state: EngineState,
        phase: String,
        currentFile: String,
        progress: @escaping @Sendable (CopyProgress) -> Void
    ) {
        progress(CopyProgress(
            phase: phase,
            currentFile: currentFile,
            bytesCopied: state.bytesCopied,
            totalBytes: state.totalBytes,
            filesCopied: state.filesCopied,
            filesSkipped: state.filesSkipped
        ))
    }
}

private struct POSIXResult {
    let result: Int32
    let errorCode: Int32
}

private struct NativeCopyResult {
    let committed: Bool
    let logicalSize: Int64
    let wasCloned: Bool
}

private struct DirectoryMetadataPair {
    let source: URL
    let target: URL
}

private enum RenameResult: Equatable {
    case moved
    case destinationExists
    case crossDevice
    case unavailable
}

private struct LStatResult {
    let status: Int32
    let errorCode: Int32
    let mode: mode_t
}

private struct LStatSizeResult {
    let status: Int32
    let errorCode: Int32
    let size: Int64
}

private enum DestinationItemKind {
    case directory
    case regularFile
    case symbolicLink
    case other
}

private struct EngineState: Sendable {
    var bytesCopied: Int64 = 0
    var totalBytes: Int64 = 0
    var filesCopied: Int = 0
    var filesSkipped: Int = 0
}

enum CopyError: LocalizedError {
    case sourceUnavailable
    case cannotReadSource
    case cannotReadItem(path: String, reason: String)
    case invalidDestination(String)
    case protectedSource(String)
    case typeConflict(source: String, destination: String)
    case unsupportedItem(String)
    case cannotInspectDestination(path: String, reason: String)
    case cannotCopy(path: String, reason: String)
    case cannotCommit(path: String, reason: String)
    case cannotRemoveSource(path: String, reason: String)
    case destinationChanged(String)

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable: "来源文件或文件夹不存在"
        case .cannotReadSource: "无法读取来源文件夹"
        case .cannotReadItem(let path, let reason): "无法读取项目 \(path): \(reason)"
        case .invalidDestination(let message): message
        case .protectedSource(let path): "出于安全考虑,不能移动系统敏感目录:\(path)"
        case .typeConflict(let source, let destination):
            "来源与目标类型不一致，已停止以避免删除目录。来源：\(source)，目标：\(destination)"
        case .unsupportedItem(let path): "暂不支持复制此文件系统对象：\(path)"
        case .cannotInspectDestination(let path, let reason): "无法安全检查目标 \(path): \(reason)"
        case .cannotCopy(let path, let reason): "无法复制 \(path): \(reason)"
        case .cannotCommit(let path, let reason): "无法安全提交到 \(path): \(reason)"
        case .cannotRemoveSource(let path, let reason): "目标已写入，但无法移除来源 \(path): \(reason)"
        case .destinationChanged(let path): "传输期间目标持续发生变化，已停止以避免覆盖：\(path)"
        }
    }
}

private final class CopyfileCallbackContext: @unchecked Sendable {
    private let onProgress: @Sendable (Int64) -> Void
    private var lastEmissionTime: TimeInterval = 0

    init(onProgress: @escaping @Sendable (Int64) -> Void) {
        self.onProgress = onProgress
    }

    func report(_ copiedBytes: Int64, force: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastEmissionTime >= 0.1 else { return }
        lastEmissionTime = now
        onProgress(copiedBytes)
    }
}

private let copyfileStatusCallback: copyfile_callback_t = {
    what,
    stage,
    state,
    _,
    _,
    rawContext in
    guard let rawContext else { return COPYFILE_QUIT }
    if Task.isCancelled { return COPYFILE_QUIT }

    guard what == COPYFILE_COPY_DATA else { return COPYFILE_CONTINUE }
    var copiedBytes: off_t = 0
    guard copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copiedBytes) == 0 else {
        return COPYFILE_CONTINUE
    }
    let context = Unmanaged<CopyfileCallbackContext>
        .fromOpaque(rawContext)
        .takeUnretainedValue()
    context.report(Int64(copiedBytes), force: stage == COPYFILE_FINISH)
    return COPYFILE_CONTINUE
}
