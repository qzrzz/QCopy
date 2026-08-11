import Darwin
import Foundation

enum CopyEngine {
    static func run(
        source: URL,
        destination: URL,
        mode: TransferMode,
        conflictPolicy: ConflictPolicy,
        smartParallel: Bool = true,
        progress: @escaping @Sendable (CopyProgress) -> Void
    ) async throws -> CopyResult {
        let startedAt = Date()
        let fileManager = FileManager.default
        var state = EngineState()

        try validate(source: source, destination: destination, mode: mode)

        // 只比较来源和目标根目录所在的卷，不读取目录内容。
        // 同卷移动继续走原子 rename；跨卷移动才需要复制 + 校验 + 删除源文件。
        let isCrossVolumeMove: Bool = {
            guard mode == .move else { return false }
            do {
                let sourceDevice = try deviceID(of: source)
                let destinationDevice = try deviceID(
                    of: destination.resolvingSymlinksInPath().standardizedFileURL
                )
                return sourceDevice != destinationDevice
            } catch {
                // 无法可靠判断卷时保持串行，优先保证移动安全。
                return false
            }
        }()

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
                    switch try renameItem(
                        source: source,
                        target: rootDestination,
                        exclusive: conflictPolicy != .replace
                    ) {
                    case .moved:
                        state.filesCopied = 1
                        emit(
                            state: state,
                            phase: "同卷快速移动",
                            currentFile: source.lastPathComponent,
                            currentFileBytes: 0,
                            currentFileTotalBytes: 0,
                            progress: progress
                        )
                        return CopyResult(
                            bytesCopied: state.bytesCopied,
                            filesCopied: state.filesCopied,
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
                try await copyDirectory(
                    source: source,
                    target: rootDestination,
                    targetWasCreated: !rootDestinationExists,
                    mode: mode,
                    fileManager: fileManager,
                    conflictPolicy: conflictPolicy,
                    smartParallel: smartParallel,
                    parallelMove: isCrossVolumeMove,
                    state: &state,
                    progress: progress
                )
            } else {
                state.filesSkipped += 1
                emit(
                    state: state,
                    phase: "已跳过",
                    currentFile: source.lastPathComponent,
                    currentFileBytes: 0,
                    currentFileTotalBytes: 0,
                    progress: progress
                )
            }
        } else {
            let proposed = destination.appendingPathComponent(source.lastPathComponent)
            let outcome = try transferLeaf(
                source: source,
                proposedTarget: proposed,
                mode: mode,
                conflictPolicy: conflictPolicy,
                state: state,
                progress: progress
            )
            apply(outcome, to: &state, progress: progress)
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
        smartParallel: Bool,
        parallelMove: Bool,
        state: inout EngineState,
        progress: @escaping @Sendable (CopyProgress) -> Void
    ) async throws {
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
        // 移动目录时绝不在 DirectoryEnumerator 仍在运行期间删除来源项。
        // 否则并发任务会改变目录内容，DirectoryEnumerator 可能静默跳过后续项。
        var pendingSourceDeletions: [SourceDeletionRecord] = []
        let parallelEnabled = smartParallel
            && (mode == .copy || (mode == .move && parallelMove))
        var transferPool: ContinuousTransferPool?
        var initialParallelWork: [LeafTransferWork] = []
        var initialFileSizes: [Int64] = []

        do {
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
                                if let transferPool {
                                    await transferPool.recordSkipped(
                                        currentFile: item.lastPathComponent,
                                        progress: progress
                                    )
                                } else {
                                    state.filesSkipped += 1
                                    state.currentConcurrency = 1
                                    emit(
                                        state: state,
                                        phase: "已跳过",
                                        currentFile: item.lastPathComponent,
                                        currentFileBytes: 0,
                                        currentFileTotalBytes: 0,
                                        progress: progress
                                    )
                                }
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

                // 只读取当前枚举到的文件尺寸；不会为了计算总进度或文件总数而预扫来源。
                let fileSize = values.fileSize.map(Int64.init)
                let work = LeafTransferWork(
                    source: item,
                    proposedTarget: destinationURL,
                    mode: mode,
                    conflictPolicy: conflictPolicy,
                    fileSize: fileSize
                )

                if parallelEnabled {
                    if let transferPool {
                        try await transferPool.enqueue(work)
                    } else {
                        // 启动阶段最多收集 32 个文件的尺寸；worker pool 启动后，
                        // 枚举器和 worker 会持续并行推进，不再按批次等待。
                        initialParallelWork.append(work)
                        if let fileSize {
                            initialFileSizes.append(fileSize)
                        }
                        if initialParallelWork.count >= AdaptiveParallelTuner.prefetchBatchSize {
                            let newPool = ContinuousTransferPool(
                                initialState: state,
                                initialFileSizes: initialFileSizes,
                                progress: progress
                            )
                            transferPool = newPool
                            await newPool.start()
                            for initialWork in initialParallelWork {
                                try await newPool.enqueue(initialWork)
                            }
                            initialParallelWork.removeAll(keepingCapacity: true)
                            initialFileSizes.removeAll(keepingCapacity: true)
                        }
                    }
                } else {
                    state.currentConcurrency = 1
                    let outcome = try transferLeaf(
                        source: item,
                        proposedTarget: destinationURL,
                        mode: mode,
                        conflictPolicy: conflictPolicy,
                        state: state,
                        deferSourceDeletion: mode == .move,
                        progress: progress
                    )
                    apply(outcome, to: &state, progress: progress)
                    if let sourceDeletion = outcome.sourceDeletion {
                        pendingSourceDeletions.append(sourceDeletion)
                    }
                }
            }
        } catch {
            transferPool?.cancel()
            if let transferPool {
                _ = try? await transferPool.finish()
            }
            throw error
        }

        if let enumerationError {
            transferPool?.cancel()
            if let transferPool {
                _ = try? await transferPool.finish()
            }
            throw enumerationError
        }

        if parallelEnabled {
            do {
                if transferPool == nil {
                    let newPool = ContinuousTransferPool(
                        initialState: state,
                        initialFileSizes: initialFileSizes,
                        progress: progress
                    )
                    transferPool = newPool
                    await newPool.start()
                    for initialWork in initialParallelWork {
                        try await newPool.enqueue(initialWork)
                    }
                }
                if let transferPool {
                    let result = try await transferPool.finish()
                    state = result.state
                    pendingSourceDeletions = result.sourceDeletions
                }
            } catch {
                transferPool?.cancel()
                if let transferPool {
                    _ = try? await transferPool.finish()
                }
                throw error
            }
        }

        // 目录权限必须在内容完成后再恢复，否则只读权限或 ACL 可能阻止后续写入。
        // 只处理本次创建的目录；合并到已有目录时保留目标目录自身的元数据。
        for pair in createdDirectories.reversed() {
            try Task.checkCancellation()
            try copyDirectoryMetadata(from: pair.source, to: pair.target)
        }

        // 两阶段移动：所有文件完成复制、校验和目录元数据提交后才删除来源文件。
        // 这样来源目录在枚举期间保持稳定，失败/取消时也不会删除未提交的来源。
        if mode == .move {
            try deleteCommittedSources(pendingSourceDeletions)
        }

        if mode == .move {
            try removeEmptySourceDirectories(sourceDirectories.reversed())
        }
    }

    private static func apply(
        _ outcome: LeafTransferOutcome,
        to state: inout EngineState,
        progress: @escaping @Sendable (CopyProgress) -> Void
    ) {
        state.bytesCopied += outcome.bytesCopied
        state.filesCopied += outcome.filesCopied
        state.filesSkipped += outcome.filesSkipped
        emit(
            state: state,
            phase: outcome.phase,
            currentFile: outcome.currentFile,
            currentFileBytes: outcome.currentFileBytes,
            currentFileTotalBytes: outcome.currentFileTotalBytes,
            progress: progress
        )
    }

    private static func transferLeaf(
        source: URL,
        proposedTarget: URL,
        mode: TransferMode,
        conflictPolicy: ConflictPolicy,
        state: EngineState,
        deferSourceDeletion: Bool = false,
        progress: @escaping @Sendable (CopyProgress) -> Void
    ) throws -> LeafTransferOutcome {
        for _ in 0..<32 {
            try Task.checkCancellation()
            guard let target = try resolveLeafDestination(
                proposedTarget,
                source: source,
                policy: conflictPolicy
            ) else {
                return LeafTransferOutcome(
                    bytesCopied: 0,
                    filesCopied: 0,
                    filesSkipped: 1,
                    phase: "已跳过",
                    currentFile: source.lastPathComponent,
                    currentFileBytes: 0,
                    currentFileTotalBytes: 0,
                    sourceDeletion: nil
                )
            }

            _ = try destinationItemKind(at: target)
            // 「覆盖」描述的是提交策略，而不是检查瞬间目标是否存在。
            // 目标可能在检查后出现；覆盖策略仍应使用普通原子 rename。
            let allowsOverwrite = conflictPolicy == .replace

            var sourceDeletion: SourceDeletionRecord?
            if mode == .move && deferSourceDeletion {
                // 必须在复制开始前记录来源身份。复制期间路径可能被外部进程替换，
                // 之后只允许删除仍然是同一个 inode 的对象。
                sourceDeletion = try sourceDeletionRecord(for: source)
            }
            if mode == .move && !deferSourceDeletion {
                let sourceSize = try logicalSize(of: source)
                switch try renameItem(source: source, target: target, exclusive: !allowsOverwrite) {
                case .moved:
                    try verifyFileSize(at: target, expectedSize: sourceSize)
                    return LeafTransferOutcome(
                        bytesCopied: sourceSize,
                        filesCopied: 1,
                        filesSkipped: 0,
                        phase: "同卷快速移动",
                        currentFile: source.lastPathComponent,
                        currentFileBytes: sourceSize,
                        currentFileTotalBytes: sourceSize,
                        sourceDeletion: nil
                    )
                case .destinationExists:
                    continue
                case .crossDevice, .unavailable:
                    break
                }
            }

            let copyResult = try copyToTemporaryAndCommit(
                source: source,
                target: target,
                allowsOverwrite: allowsOverwrite,
                baseState: state,
                progress: progress
            )
            guard copyResult.committed else {
                continue
            }

            if mode == .move {
                if !deferSourceDeletion {
                    try Task.checkCancellation()
                    try unlinkSourceLeaf(source)
                }
            }
            return LeafTransferOutcome(
                bytesCopied: copyResult.logicalSize,
                filesCopied: 1,
                filesSkipped: 0,
                phase: copyResult.wasCloned ? "APFS 快速克隆" : "传输中",
                currentFile: source.lastPathComponent,
                currentFileBytes: copyResult.logicalSize,
                currentFileTotalBytes: copyResult.logicalSize,
                sourceDeletion: sourceDeletion
            )
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
        allowsOverwrite: Bool,
        baseState: EngineState,
        progress: @escaping @Sendable (CopyProgress) -> Void
    ) throws -> NativeCopyResult {
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true || values.isSymbolicLink == true else {
            throw CopyError.unsupportedItem(source.path)
        }

        // 使用 lstat 的逻辑尺寸，避免符号链接被解析到目标文件尺寸。
        let logicalSize = try logicalSize(of: source)
        let tempURL = temporaryURL(near: target)
        defer { unlinkTemporaryIfPresent(tempURL) }

        // 进度条只反映当前文件；累计字节用于「已传输」与速度。不做整树预扫。
        let context = CopyfileCallbackContext { copiedBytes in
            let fileCopied: Int64
            if logicalSize > 0 {
                fileCopied = min(max(copiedBytes, 0), logicalSize)
            } else {
                fileCopied = max(copiedBytes, 0)
            }
            progress(CopyProgress(
                phase: "传输中",
                currentFile: source.lastPathComponent,
                bytesCopied: baseState.bytesCopied + fileCopied,
                currentFileBytes: fileCopied,
                currentFileTotalBytes: logicalSize,
                currentConcurrency: baseState.currentConcurrency,
                filesCopied: baseState.filesCopied,
                filesSkipped: baseState.filesSkipped
            ))
        }
        var flags = copyfile_flags_t(
            COPYFILE_ALL | COPYFILE_EXCL | COPYFILE_NOFOLLOW_SRC | COPYFILE_NOFOLLOW_DST
        )
        if values.isRegularFile == true {
            flags |= copyfile_flags_t(COPYFILE_CLONE | COPYFILE_DATA_SPARSE)
        }

        let wasCloned: Bool
        do {
            wasCloned = try performCopyfile(
                source: source,
                target: tempURL,
                flags: flags,
                context: context
            )
        } catch let failure as CopyfileAttemptError {
            guard shouldRetryWithoutMetadata(failure.errorCode) else {
                throw CopyError.cannotCopy(path: source.path, reason: posixMessage(failure.errorCode))
            }
            unlinkTemporaryIfPresent(tempURL)

            // NFS、WebDAV、AFP 和部分 FUSE/SMB 服务不提供 macOS ACL 或扩展属性。
            // 数据只复制一次；元数据随后逐项尽力保留，避免因某项能力缺失而失败。
            var portableFlags = copyfile_flags_t(
                COPYFILE_DATA | COPYFILE_EXCL | COPYFILE_NOFOLLOW_SRC | COPYFILE_NOFOLLOW_DST
            )
            if values.isRegularFile == true {
                portableFlags |= copyfile_flags_t(COPYFILE_DATA_SPARSE)
            }
            do {
                _ = try performCopyfile(
                    source: source,
                    target: tempURL,
                    flags: portableFlags,
                    context: context
                )
            } catch let portableFailure as CopyfileAttemptError {
                let reason: String
                if values.isSymbolicLink == true, shouldRetryWithoutMetadata(portableFailure.errorCode) {
                    reason = "目标卷不支持保留符号链接"
                } else {
                    reason = posixMessage(portableFailure.errorCode)
                }
                throw CopyError.cannotCopy(path: source.path, reason: reason)
            }
            copyOptionalMetadata(from: source, to: tempURL)
            wasCloned = false
        }

        try Task.checkCancellation()

        // 先校验临时文件，确保尺寸错误不会提交到目标路径。
        try verifyFileSize(at: tempURL, expectedSize: logicalSize)

        switch try commitTemporary(tempURL, target: target, allowsOverwrite: allowsOverwrite) {
        case .moved:
            // 提交后再校验一次，覆盖网络卷或并发进程导致的目标尺寸变化。
            try verifyFileSize(at: target, expectedSize: logicalSize)
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

    private static func performCopyfile(
        source: URL,
        target: URL,
        flags: copyfile_flags_t,
        context: CopyfileCallbackContext
    ) throws -> Bool {
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

        let copyCall = withFileSystemRepresentations(source, target) { sourcePath, targetPath in
            copyfile(sourcePath, targetPath, copyState, flags)
        }
        guard copyCall.result == 0 else {
            if copyCall.errorCode == ECANCELED || Task.isCancelled {
                throw CancellationError()
            }
            throw CopyfileAttemptError(errorCode: copyCall.errorCode)
        }

        var wasCloned = false
        _ = copyfile_state_get(copyState, UInt32(COPYFILE_STATE_WAS_CLONED), &wasCloned)
        return wasCloned
    }

    private static func copyOptionalMetadata(from source: URL, to target: URL) {
        let components = [COPYFILE_STAT, COPYFILE_XATTR, COPYFILE_ACL]
        for component in components {
            let flags = copyfile_flags_t(component | COPYFILE_NOFOLLOW_SRC | COPYFILE_NOFOLLOW_DST)
            _ = withFileSystemRepresentations(source, target) { sourcePath, targetPath in
                copyfile(sourcePath, targetPath, nil, flags)
            }
        }
    }

    private static func shouldRetryWithoutMetadata(_ errorCode: Int32) -> Bool {
        errorCode == ENOTSUP
            || errorCode == ENOSYS
            || errorCode == ENOTTY
            || errorCode == EPERM
            || errorCode == EACCES
    }

    private static func commitTemporary(
        _ temp: URL,
        target: URL,
        allowsOverwrite: Bool
    ) throws -> RenameResult {
        let outcome = try renameItem(source: temp, target: target, exclusive: !allowsOverwrite)
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
        if linkResult.errorCode == ENOTSUP || linkResult.errorCode == EPERM || linkResult.errorCode == EACCES {
            return try reserveTargetAndReplace(temp, target: target)
        }
        throw CopyError.cannotCommit(path: target.path, reason: posixMessage(linkResult.errorCode))
    }

    /// SMB 等文件系统既不支持 RENAME_EXCL，也不支持硬链接。此时先以 O_EXCL
    /// 创建最终名称作为占位，再用普通 rename 原子替换由本进程持有的占位文件。
    /// 这样仍能避免与正常复制进程竞争时误覆盖已经存在的目标。
    private static func reserveTargetAndReplace(_ temp: URL, target: URL) throws -> RenameResult {
        let reservation = target.withUnsafeFileSystemRepresentation { path -> POSIXResult in
            guard let path else { return POSIXResult(result: -1, errorCode: EINVAL) }
            let descriptor = Darwin.open(
                path,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(S_IRUSR | S_IWUSR)
            )
            return POSIXResult(result: descriptor, errorCode: descriptor >= 0 ? 0 : errno)
        }
        if reservation.result < 0 {
            if reservation.errorCode == EEXIST { return .destinationExists }
            throw CopyError.cannotCommit(path: target.path, reason: posixMessage(reservation.errorCode))
        }

        let descriptor = reservation.result
        var reservationInfo = stat()
        guard Darwin.fstat(descriptor, &reservationInfo) == 0 else {
            let errorCode = errno
            Darwin.close(descriptor)
            // 无法取得对象身份时不能按路径删除，避免误删并发替换后的目标。
            throw CopyError.cannotCommit(path: target.path, reason: posixMessage(errorCode))
        }

        var committed = false
        defer {
            Darwin.close(descriptor)
            if !committed {
                unlinkIfMatching(target, device: reservationInfo.st_dev, inode: reservationInfo.st_ino)
            }
        }

        // 确认名称仍指向刚创建的占位对象；若被其他进程替换则绝不覆盖。
        guard itemMatches(target, device: reservationInfo.st_dev, inode: reservationInfo.st_ino) else {
            return .destinationExists
        }

        let result = withFileSystemRepresentations(temp, target) { sourcePath, targetPath in
            Darwin.rename(sourcePath, targetPath)
        }
        guard result.result == 0 else {
            throw CopyError.cannotCommit(path: target.path, reason: posixMessage(result.errorCode))
        }
        committed = true
        return .moved
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

    private static func deviceID(of url: URL) throws -> dev_t {
        let result = url.withUnsafeFileSystemRepresentation { path -> LStatDeviceResult in
            guard let path else {
                return LStatDeviceResult(status: -1, errorCode: EINVAL, device: 0)
            }
            var info = stat()
            let status = Darwin.lstat(path, &info)
            return LStatDeviceResult(
                status: status,
                errorCode: status == 0 ? 0 : errno,
                device: status == 0 ? info.st_dev : 0
            )
        }
        guard result.status == 0 else {
            throw CopyError.cannotReadItem(path: url.path, reason: posixMessage(result.errorCode))
        }
        return result.device
    }

    static func verifyFileSize(at url: URL, expectedSize: Int64) throws {
        let actualSize = try logicalSize(of: url)
        guard actualSize == expectedSize else {
            throw CopyError.sizeMismatch(
                path: url.path,
                expected: expectedSize,
                actual: actualSize
            )
        }
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
        if result != 0 {
            let errorCode = errno
            // 目录内容已经安全写入；网络卷不支持某类元数据时保留其默认值。
            if shouldRetryWithoutMetadata(errorCode) || errorCode == EINVAL || errorCode == EISDIR {
                return
            }
            throw CopyError.cannotCopy(path: source.path, reason: posixMessage(errorCode))
        }
    }

    private static func unlinkTemporaryIfPresent(_ url: URL) {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            // 临时路径即使被外部进程替换成目录也绝不递归删除。
            _ = Darwin.unlink(path)
        }
    }

    private static func itemMatches(_ url: URL, device: dev_t, inode: ino_t) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            var info = stat()
            return Darwin.lstat(path, &info) == 0
                && info.st_dev == device
                && info.st_ino == inode
        }
    }

    private static func unlinkIfMatching(_ url: URL, device: dev_t, inode: ino_t) {
        guard itemMatches(url, device: device, inode: inode) else { return }
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
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

    private static func sourceDeletionRecord(for source: URL) throws -> SourceDeletionRecord {
        let result = source.withUnsafeFileSystemRepresentation { path -> LStatIdentityResult in
            guard let path else {
                return LStatIdentityResult(status: -1, errorCode: EINVAL, device: 0, inode: 0, size: 0)
            }
            var info = stat()
            let status = Darwin.lstat(path, &info)
            return LStatIdentityResult(
                status: status,
                errorCode: status == 0 ? 0 : errno,
                device: status == 0 ? info.st_dev : 0,
                inode: status == 0 ? info.st_ino : 0,
                size: status == 0 ? Int64(info.st_size) : 0
            )
        }
        guard result.status == 0 else {
            throw CopyError.cannotReadItem(path: source.path, reason: posixMessage(result.errorCode))
        }
        return SourceDeletionRecord(
            source: source,
            device: result.device,
            inode: result.inode,
            size: result.size
        )
    }

    private static func deleteCommittedSources(_ records: [SourceDeletionRecord]) throws {
        for record in records {
            try Task.checkCancellation()
            // 复制完成后来源可能被外部程序替换；绝不按路径删除新对象。
            guard itemMatches(record.source, device: record.device, inode: record.inode),
                  (try? logicalSize(of: record.source)) == record.size else {
                throw CopyError.cannotRemoveSource(
                    path: record.source.path,
                    reason: "来源在复制期间发生变化，已保留"
                )
            }
            try unlinkSourceLeaf(record.source)
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
        currentFileBytes: Int64,
        currentFileTotalBytes: Int64,
        progress: @escaping @Sendable (CopyProgress) -> Void
    ) {
        progress(CopyProgress(
            phase: phase,
            currentFile: currentFile,
            bytesCopied: state.bytesCopied,
            currentFileBytes: currentFileBytes,
            currentFileTotalBytes: currentFileTotalBytes,
            currentConcurrency: state.currentConcurrency,
            filesCopied: state.filesCopied,
            filesSkipped: state.filesSkipped
        ))
    }

    private struct ContinuousPoolResult: Sendable {
        let state: EngineState
        let sourceDeletions: [SourceDeletionRecord]
    }

    /// 限制枚举器与 worker 之间的未完成项目总量，避免把整棵目录树放入内存。
    private actor ParallelWorkSlots {
        private var available: Int
        private var cancelled = false
        private var waiters: [CheckedContinuation<Bool, Never>] = []

        init(capacity: Int) {
            available = max(1, capacity)
        }

        func acquire() async -> Bool {
            guard !cancelled else { return false }
            if available > 0 {
                available -= 1
                return true
            }
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func release() {
            guard !cancelled else { return }
            if let continuation = waiters.first {
                waiters.removeFirst()
                continuation.resume(returning: true)
            } else {
                available += 1
            }
        }

        func cancel() {
            guard !cancelled else { return }
            cancelled = true
            let pending = waiters
            waiters.removeAll()
            for continuation in pending {
                continuation.resume(returning: false)
            }
        }
    }

    /// 全局并发闸门。worker 数量固定为 32，实际运行路数通过闸门连续调整，
    /// 不再因为一个批次结束而整体停顿。64 MB 以上文件使用串行屏障。
    private actor ParallelConcurrencyGate {
        private struct Waiter {
            let fileLimit: Int
            let continuation: CheckedContinuation<Bool, Never>
        }

        private var limit: Int
        private var active = 0
        private var activeMedium = 0
        private var activeSerial = false
        private var serialWaiters = 0
        private var waiters: [Waiter] = []
        private var cancelled = false

        init(limit: Int) {
            self.limit = max(1, min(limit, AdaptiveParallelTuner.maximumConcurrencyLimit))
        }

        func acquire(fileSize: Int64?) async -> Bool {
            let fileLimit = Self.fileLimit(for: fileSize)
            guard !cancelled else { return false }
            if waiters.isEmpty, canAcquire(fileLimit) {
                grant(fileLimit)
                return true
            }
            if fileLimit <= 1 { serialWaiters += 1 }
            return await withCheckedContinuation { continuation in
                waiters.append(Waiter(fileLimit: fileLimit, continuation: continuation))
            }
        }

        func release(fileSize: Int64?) {
            let fileLimit = Self.fileLimit(for: fileSize)
            active = max(0, active - 1)
            if fileLimit <= 1 { activeSerial = false }
            if fileLimit == 2 { activeMedium = max(0, activeMedium - 1) }
            pumpWaiters()
        }

        func setLimit(_ newLimit: Int) {
            limit = max(1, min(newLimit, AdaptiveParallelTuner.maximumConcurrencyLimit))
            pumpWaiters()
        }

        func activeCount() -> Int {
            active
        }

        func cancel() {
            guard !cancelled else { return }
            cancelled = true
            let pending = waiters
            waiters.removeAll()
            for waiter in pending {
                waiter.continuation.resume(returning: false)
            }
        }

        private static func fileLimit(for fileSize: Int64?) -> Int {
            guard let fileSize else { return 1 }
            return AdaptiveParallelTuner.maximumSafeConcurrency(forFileSize: fileSize)
        }

        private func canAcquire(_ fileLimit: Int) -> Bool {
            guard !cancelled, !activeSerial else { return false }
            if fileLimit <= 1 {
                return active == 0
            }
            guard serialWaiters == 0, active < limit else { return false }
            if fileLimit == 2, activeMedium >= 2 { return false }
            return true
        }

        private func grant(_ fileLimit: Int) {
            active += 1
            if fileLimit <= 1 { activeSerial = true }
            if fileLimit == 2 { activeMedium += 1 }
        }

        private func pumpWaiters() {
            // 串行文件一旦排队，先让当前活动任务自然排空；否则队首的普通
            // 文件会挡住串行 waiter，形成永久等待。
            if serialWaiters > 0 {
                guard active == 0,
                      let serialIndex = waiters.firstIndex(where: { $0.fileLimit <= 1 }) else {
                    return
                }
                let waiter = waiters.remove(at: serialIndex)
                serialWaiters = max(0, serialWaiters - 1)
                grant(waiter.fileLimit)
                waiter.continuation.resume(returning: true)
                return
            }

            while let waiter = waiters.first, canAcquire(waiter.fileLimit) {
                waiters.removeFirst()
                grant(waiter.fileLimit)
                waiter.continuation.resume(returning: true)
            }
        }
    }

    private actor ParallelTransferCoordinator {
        private var state: EngineState
        private var tuner: AdaptiveParallelTuner
        private var sourceDeletions: [SourceDeletionRecord] = []
        private let gate: ParallelConcurrencyGate
        private let progress: @Sendable (CopyProgress) -> Void

        init(
            initialState: EngineState,
            initialFileSizes: [Int64],
            gate: ParallelConcurrencyGate,
            progress: @escaping @Sendable (CopyProgress) -> Void
        ) {
            var tuner = AdaptiveParallelTuner()
            tuner.prepare(forFileSizes: initialFileSizes)
            self.state = initialState
            self.tuner = tuner
            self.gate = gate
            self.progress = progress
        }

        func stateSnapshot() -> EngineState {
            state
        }

        /// worker 获得执行槽后立即发出一次快照。
        /// 小文件可能在下一次完成事件前已经结束；如果只在完成时上报，
        /// UI 和统计图会错过真实的峰值并发。
        func workerStarted(currentFile: String, currentFileTotalBytes: Int64) async {
            state.currentConcurrency = max(1, await gate.activeCount())
            emit(
                state: state,
                phase: "传输中",
                currentFile: currentFile,
                currentFileBytes: 0,
                currentFileTotalBytes: currentFileTotalBytes,
                progress: progress
            )
        }

        func record(_ outcome: LeafTransferOutcome, duration: TimeInterval) async {
            state.bytesCopied += outcome.bytesCopied
            state.filesCopied += outcome.filesCopied
            state.filesSkipped += outcome.filesSkipped
            state.currentConcurrency = max(1, await gate.activeCount())
            if let sourceDeletion = outcome.sourceDeletion {
                sourceDeletions.append(sourceDeletion)
            }
            emit(
                state: state,
                phase: outcome.phase,
                currentFile: outcome.currentFile,
                currentFileBytes: outcome.currentFileBytes,
                currentFileTotalBytes: outcome.currentFileTotalBytes,
                progress: progress
            )
            let newLimit = tuner.observe(bytes: outcome.bytesCopied, duration: duration)
            if let newLimit {
                await gate.setLimit(newLimit)
            }
        }

        func recordSkipped(currentFile: String, progress: @escaping @Sendable (CopyProgress) -> Void) async {
            state.filesSkipped += 1
            state.currentConcurrency = max(1, await gate.activeCount())
            emit(
                state: state,
                phase: "已跳过",
                currentFile: currentFile,
                currentFileBytes: 0,
                currentFileTotalBytes: 0,
                progress: progress
            )
        }

        func result() -> ContinuousPoolResult {
            ContinuousPoolResult(state: state, sourceDeletions: sourceDeletions)
        }
    }

    private final class PoolFailureBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storedError: Error?
        private var wasCancelled = false

        func set(_ error: Error) {
            lock.lock()
            defer { lock.unlock() }
            if storedError == nil, !wasCancelled {
                storedError = error
            }
        }

        func cancel() {
            lock.lock()
            wasCancelled = true
            lock.unlock()
        }

        func error() -> Error? {
            lock.lock()
            defer { lock.unlock() }
            return storedError
        }

        func isCancelled() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return wasCancelled
        }
    }

    private final class ContinuousTransferPool: @unchecked Sendable {
        private let stream: AsyncStream<LeafTransferWork>
        private let continuation: AsyncStream<LeafTransferWork>.Continuation
        private let slots = ParallelWorkSlots(capacity: AdaptiveParallelTuner.prefetchBatchSize)
        private let gate: ParallelConcurrencyGate
        private let coordinator: ParallelTransferCoordinator
        private let progress: @Sendable (CopyProgress) -> Void
        private let failure = PoolFailureBox()
        private var workers: [Task<Void, Never>] = []
        private var started = false

        init(
            initialState: EngineState,
            initialFileSizes: [Int64],
            progress: @escaping @Sendable (CopyProgress) -> Void
        ) {
            var continuation: AsyncStream<LeafTransferWork>.Continuation?
            stream = AsyncStream(bufferingPolicy: .unbounded) { value in
                continuation = value
            }
            self.continuation = continuation!
            self.progress = progress

            var tuner = AdaptiveParallelTuner()
            tuner.prepare(forFileSizes: initialFileSizes)
            gate = ParallelConcurrencyGate(limit: tuner.concurrency)
            coordinator = ParallelTransferCoordinator(
                initialState: initialState,
                initialFileSizes: initialFileSizes,
                gate: gate,
                progress: progress
            )
        }

        func start() async {
            guard !started else { return }
            started = true
            workers = (0..<AdaptiveParallelTuner.maximumConcurrencyLimit).map { _ in
                Task { [weak self] in
                    await self?.workerLoop()
                }
            }
        }

        func enqueue(_ work: LeafTransferWork) async throws {
            try Task.checkCancellation()
            guard await slots.acquire() else { throw CancellationError() }
            switch continuation.yield(work) {
            case .enqueued:
                return
            case .dropped, .terminated:
                await slots.release()
                if let error = failure.error() { throw error }
                throw CancellationError()
            @unknown default:
                await slots.release()
                throw CancellationError()
            }
        }

        func recordSkipped(currentFile: String, progress: @escaping @Sendable (CopyProgress) -> Void) async {
            await coordinator.recordSkipped(currentFile: currentFile, progress: progress)
        }

        func finish() async throws -> ContinuousPoolResult {
            try await withTaskCancellationHandler(operation: {
                continuation.finish()
                for worker in workers {
                    await worker.value
                }
                try Task.checkCancellation()
                if let error = failure.error() {
                    throw error
                }
                return await coordinator.result()
            }, onCancel: {
                cancel()
            })
        }

        func cancel() {
            failure.cancel()
            continuation.finish()
            Task {
                await gate.cancel()
                await slots.cancel()
            }
            for worker in workers {
                worker.cancel()
            }
        }

        private func workerLoop() async {
            for await work in stream {
                guard !failure.isCancelled() else {
                    await slots.release()
                    break
                }
                let acquired = await gate.acquire(fileSize: work.fileSize)
                guard acquired else {
                    await slots.release()
                    break
                }

                let startedAt = Date()
                do {
                    await coordinator.workerStarted(
                        currentFile: work.source.lastPathComponent,
                        currentFileTotalBytes: work.fileSize ?? 0
                    )
                    let baseState = await coordinator.stateSnapshot()
                    let outcome = try CopyEngine.transferLeaf(
                        source: work.source,
                        proposedTarget: work.proposedTarget,
                        mode: work.mode,
                        conflictPolicy: work.conflictPolicy,
                        state: baseState,
                        deferSourceDeletion: work.mode == .move,
                        progress: progress
                    )
                    await coordinator.record(
                        outcome,
                        duration: max(Date().timeIntervalSince(startedAt), 0.001)
                    )
                } catch {
                    await gate.release(fileSize: work.fileSize)
                    await slots.release()
                    if !failure.isCancelled() {
                        failure.set(error)
                        cancel()
                    }
                    break
                }
                await gate.release(fileSize: work.fileSize)
                await slots.release()
            }
        }
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

private struct LeafTransferWork: Sendable {
    let source: URL
    let proposedTarget: URL
    let mode: TransferMode
    let conflictPolicy: ConflictPolicy
    /// 当前枚举到该文件时读取的尺寸；不做全量尺寸预取。
    let fileSize: Int64?
}

private struct LeafTransferOutcome: Sendable {
    let bytesCopied: Int64
    let filesCopied: Int
    let filesSkipped: Int
    let phase: String
    let currentFile: String
    let currentFileBytes: Int64
    let currentFileTotalBytes: Int64
    let sourceDeletion: SourceDeletionRecord?
}

private struct SourceDeletionRecord: Sendable {
    let source: URL
    let device: dev_t
    let inode: ino_t
    let size: Int64
}

struct AdaptiveParallelTuner {
    /// 启动阶段只预取有限数量的文件，避免先统计整棵目录树。
    static let prefetchBatchSize = 32
    /// 超过 500 MB 的文件永远不进入并行队列。
    static let parallelEligibilityLimit: Int64 = 500 * 1024 * 1024
    static let maximumConcurrencyLimit = 32
    private static let megabyte: Int64 = 1024 * 1024

    let maximumConcurrency: Int
    var concurrency: Int = 2
    private var previousThroughput: Double?
    private var observedBytes: Int64 = 0
    private var observedDuration: TimeInterval = 0
    private var observedFiles = 0
    private var stableWindows = 0
    private var cooldownWindows = 0
    private var hasPrepared = false

    init() {
        maximumConcurrency = Self.maximumConcurrencyLimit
    }

    /// 首批固定为 32；worker pool 启动后继续使用同样的有限窗口。
    var prefetchLimit: Int { Self.prefetchBatchSize }

    static func isParallelEligible(fileSize: Int64) -> Bool {
        fileSize >= 0 && fileSize < parallelEligibilityLimit
    }

    /// 单个文件的安全并发上限：小文件可由吞吐调节到全局上限；
    /// 32–64 MB 最多 2 路，64 MB 以上只运行 1 路。
    static func maximumSafeConcurrency(forFileSize fileSize: Int64) -> Int {
        guard isParallelEligible(fileSize: fileSize) else { return 1 }
        switch fileSize {
        case ..<(32 * megabyte): return maximumConcurrencyLimit
        case ..<(64 * megabyte): return 2
        default: return 1
        }
    }

    /// 兼容单文件调用；批处理使用 `initialConcurrency(forFileSizes:)`。
    static func initialConcurrency(forFileSize fileSize: Int64) -> Int {
        guard isParallelEligible(fileSize: fileSize) else { return 1 }
        switch fileSize {
        case ..<(1 * megabyte): return 16
        case ..<(8 * megabyte): return 12
        case ..<(16 * megabyte): return 8
        case ..<(32 * megabyte): return 4
        case ..<(64 * megabyte): return 2
        case 64 * megabyte: return 2
        default: return 1
        }
    }

    static func initialConcurrency(forFileSizes fileSizes: [Int64]) -> Int {
        guard !fileSizes.isEmpty else { return 1 }
        // 使用中位数而不是最大值，避免首批中偶然出现一个极小文件就把整个
        // worker pool 拉到高并发；每个文件仍由 gate 施加自己的尺寸上限。
        let starts = fileSizes.map(initialConcurrency(forFileSize:)).sorted()
        return starts[(starts.count - 1) / 2]
    }

    mutating func prepare(forFileSize fileSize: Int64) {
        prepare(forFileSizes: [fileSize])
    }

    mutating func prepare(forFileSizes fileSizes: [Int64]) {
        guard !hasPrepared, !fileSizes.isEmpty else { return }
        hasPrepared = true
        concurrency = min(
            maximumConcurrency,
            Self.initialConcurrency(forFileSizes: fileSizes)
        )
    }

    func concurrencyLimit(forFileSize fileSize: Int64) -> Int {
        Self.maximumSafeConcurrency(forFileSize: fileSize)
    }

    /// 兼容旧测试/调用方；持续 worker pool 不再按批次切换状态。
    mutating func markBatchStarted() {}

    /// 按连续完成窗口调节并发，而不是每个批次调节。
    /// 返回 nil 表示本次完成还不足以触发调整。
    mutating func observe(bytes: Int64, duration: TimeInterval) -> Int? {
        observedBytes += max(0, bytes)
        observedDuration += max(0.001, duration)
        observedFiles += 1

        guard observedFiles >= 8 || observedDuration >= 2 else { return nil }
        let throughput = Double(observedBytes) / max(observedDuration, 0.001)
        observedBytes = 0
        observedDuration = 0
        observedFiles = 0

        guard let previousThroughput else {
            self.previousThroughput = throughput
            return nil
        }

        // 对连续窗口做 EMA，并设置 15% 滞回，过滤网络卷的瞬时抖动。
        let smoothedThroughput = previousThroughput * 0.7 + throughput * 0.3
        self.previousThroughput = smoothedThroughput
        if cooldownWindows > 0 {
            cooldownWindows -= 1
            return nil
        }

        if smoothedThroughput < previousThroughput * 0.85 {
            concurrency = max(1, concurrency - 1)
            stableWindows = 0
            cooldownWindows = 2
            return concurrency
        }
        if smoothedThroughput > previousThroughput * 1.15 {
            concurrency = min(maximumConcurrency, concurrency + 1)
            stableWindows = 0
            cooldownWindows = 2
            return concurrency
        }

        stableWindows += 1
        if stableWindows >= 2 {
            concurrency = min(maximumConcurrency, concurrency + 1)
            stableWindows = 0
            cooldownWindows = 2
            return concurrency
        }
        return nil
    }
}

private struct CopyfileAttemptError: Error {
    let errorCode: Int32
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

private struct LStatDeviceResult {
    let status: Int32
    let errorCode: Int32
    let device: dev_t
}

private struct LStatIdentityResult {
    let status: Int32
    let errorCode: Int32
    let device: dev_t
    let inode: ino_t
    let size: Int64
}

private enum DestinationItemKind {
    case directory
    case regularFile
    case symbolicLink
    case other
}

private struct EngineState: Sendable {
    /// 本次任务累计已传输逻辑字节（不做整树预扫）。
    var bytesCopied: Int64 = 0
    /// 当前批次实际使用的并发路数；没有并行批次时为 1。
    var currentConcurrency: Int = 1
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
    case sizeMismatch(path: String, expected: Int64, actual: Int64)
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
        case .sizeMismatch(let path, let expected, let actual):
            "文件尺寸校验失败 \(path)：期望 \(expected) 字节，实际 \(actual) 字节"
        case .cannotRemoveSource(let path, let reason): "目标已写入，但无法移除来源 \(path): \(reason)"
        case .destinationChanged(let path): "传输期间目标持续发生变化，已停止以避免覆盖：\(path)"
        }
    }
}

private final class CopyfileCallbackContext: @unchecked Sendable {
    private let onProgress: @Sendable (Int64) -> Void
    private var lastEmissionTime: TimeInterval = 0
    private var highestReportedBytes: Int64 = 0

    init(onProgress: @escaping @Sendable (Int64) -> Void) {
        self.onProgress = onProgress
    }

    func report(_ copiedBytes: Int64, force: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastEmissionTime >= 0.1 else { return }
        lastEmissionTime = now
        highestReportedBytes = max(highestReportedBytes, copiedBytes)
        onProgress(highestReportedBytes)
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
