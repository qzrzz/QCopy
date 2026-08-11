import Foundation

enum TransferMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case copy
    case move

    var id: String { rawValue }
    var title: String { self == .copy ? "复制" : "移动" }
    var symbol: String { self == .copy ? "doc.on.doc" : "arrow.right.doc.on.clipboard" }
    var description: String {
        self == .copy ? "保留原文件，创建一份副本" : "传输完成后移除原文件"
    }
}

enum ConflictPolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    case replace
    case skip
    case rename

    var id: String { rawValue }
    var title: String {
        switch self {
        case .replace: "覆盖已存在文件"
        case .skip: "跳过已存在文件"
        case .rename: "自动重命名"
        }
    }

    var symbol: String {
        switch self {
        case .replace: "arrow.triangle.2.circlepath"
        case .skip: "forward.end"
        case .rename: "text.append"
        }
    }
}

struct CopyProgress: Sendable {
    var phase: String
    var currentFile: String
    /// 本次任务累计已传输字节（用于「已传输」与速度，不做整树预扫）。
    var bytesCopied: Int64
    /// 当前文件已写入字节（进度条分子）。
    var currentFileBytes: Int64
    /// 当前文件逻辑大小（进度条分母；仅当前文件的 size，非全局预扫）。
    var currentFileTotalBytes: Int64
    /// 当前实际工作的并发路数；串行任务为 1。
    var currentConcurrency: Int
    var filesCopied: Int
    var filesSkipped: Int
}

/// 传输过程中用于图表展示的速度 / 并发采样点。
struct TransferSample: Identifiable, Sendable, Equatable, Codable, Hashable {
    let id: UUID
    let elapsed: TimeInterval
    let speedBytesPerSecond: Double
    let concurrency: Int

    init(
        id: UUID = UUID(),
        elapsed: TimeInterval,
        speedBytesPerSecond: Double,
        concurrency: Int
    ) {
        self.id = id
        self.elapsed = max(0, elapsed)
        self.speedBytesPerSecond = max(0, speedBytesPerSecond)
        self.concurrency = max(1, concurrency)
    }
}

struct CopyResult: Sendable {
    let bytesCopied: Int64
    let filesCopied: Int
    let filesSkipped: Int
    let duration: TimeInterval
}

enum TransferState: Equatable, Hashable, Codable, Sendable {
    case queued
    case transferring
    case cancelling
    case completed
    case cancelled
    case failed(String)

    var title: String {
        switch self {
        case .queued: "等待开始"
        case .transferring: "正在传输"
        case .cancelling: "正在停止"
        case .completed: "已完成"
        case .cancelled: "已取消"
        case .failed: "传输失败"
        }
    }

    /// 失败时的错误文案；其他状态为 `nil`。
    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }

    var colorName: String {
        switch self {
        case .completed: "green"
        case .failed: "red"
        case .cancelling, .cancelled: "orange"
        default: "blue"
        }
    }
}

struct TransferJob: Identifiable {
    let id: UUID
    let source: URL
    let destination: URL
    let mode: TransferMode
    let conflictPolicy: ConflictPolicy
    var state: TransferState
    var phase: String
    var currentFile: String
    /// 本次任务累计已传输字节。
    var bytesCopied: Int64
    /// 当前文件进度（单文件 0→100%，不做整体进度）。
    var currentFileBytes: Int64
    var currentFileTotalBytes: Int64
    /// 当前实际工作的并发路数；串行任务为 1。
    var currentConcurrency: Int
    var filesCopied: Int
    var filesSkipped: Int
    /// 本次任务的速度 / 并发历史采样。
    var samples: [TransferSample]
    var startedAt: Date
    var finishedAt: Date?
    var duration: TimeInterval?
    var speedBytesPerSecond: Double

    /// 当前文件进度比例；完成后固定为 1。
    var progress: Double {
        if state == .completed { return 1 }
        guard currentFileTotalBytes > 0 else { return 0 }
        return min(max(Double(currentFileBytes) / Double(currentFileTotalBytes), 0), 1)
    }

    var sourceName: String { source.lastPathComponent.isEmpty ? source.path : source.lastPathComponent }
    var destinationName: String { destination.lastPathComponent.isEmpty ? destination.path : destination.lastPathComponent }
}

/// 一次已结束传输任务的操作记录（跨启动持久化）。
struct TransferHistoryEntry: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    /// 来源显示名（文件 / 文件夹名）。
    let source: String
    /// 目标显示名。
    let destination: String
    /// 来源绝对路径，便于回填与展示完整位置。
    let sourcePath: String
    /// 目标绝对路径。
    let destinationPath: String
    let mode: TransferMode
    let conflictPolicy: ConflictPolicy
    let bytes: Int64
    let files: Int
    let filesSkipped: Int
    let duration: TimeInterval?
    let averageSpeedBytesPerSecond: Double
    let date: Date
    let state: TransferState
    /// 传输统计采样；旧数据无此字段时解码为空。
    let samples: [TransferSample]

    var sourceExists: Bool {
        FileManager.default.fileExists(atPath: sourcePath)
    }

    var destinationExists: Bool {
        FileManager.default.fileExists(atPath: destinationPath)
    }

    enum CodingKeys: String, CodingKey {
        case id, source, destination, sourcePath, destinationPath
        case mode, conflictPolicy, bytes, files, filesSkipped
        case duration, averageSpeedBytesPerSecond, date, state, samples
    }

    init(
        id: UUID,
        source: String,
        destination: String,
        sourcePath: String,
        destinationPath: String,
        mode: TransferMode,
        conflictPolicy: ConflictPolicy,
        bytes: Int64,
        files: Int,
        filesSkipped: Int,
        duration: TimeInterval?,
        averageSpeedBytesPerSecond: Double,
        date: Date,
        state: TransferState,
        samples: [TransferSample] = []
    ) {
        self.id = id
        self.source = source
        self.destination = destination
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.mode = mode
        self.conflictPolicy = conflictPolicy
        self.bytes = bytes
        self.files = files
        self.filesSkipped = filesSkipped
        self.duration = duration
        self.averageSpeedBytesPerSecond = averageSpeedBytesPerSecond
        self.date = date
        self.state = state
        self.samples = samples
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        source = try c.decode(String.self, forKey: .source)
        destination = try c.decode(String.self, forKey: .destination)
        sourcePath = try c.decode(String.self, forKey: .sourcePath)
        destinationPath = try c.decode(String.self, forKey: .destinationPath)
        mode = try c.decode(TransferMode.self, forKey: .mode)
        conflictPolicy = try c.decode(ConflictPolicy.self, forKey: .conflictPolicy)
        bytes = try c.decode(Int64.self, forKey: .bytes)
        files = try c.decode(Int.self, forKey: .files)
        filesSkipped = try c.decode(Int.self, forKey: .filesSkipped)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration)
        averageSpeedBytesPerSecond = try c.decode(Double.self, forKey: .averageSpeedBytesPerSecond)
        date = try c.decode(Date.self, forKey: .date)
        state = try c.decode(TransferState.self, forKey: .state)
        samples = try c.decodeIfPresent([TransferSample].self, forKey: .samples) ?? []
    }
}

/// 最近选择的文件 / 文件夹路径记录（来源或目标）。
struct RecentPathEntry: Identifiable, Codable, Equatable, Hashable {
    /// 使用绝对路径作为稳定 ID，便于去重。
    var id: String { path }
    let path: String
    var lastUsed: Date

    var url: URL { URL(fileURLWithPath: path, isDirectory: pathHasDirectoryHint) }

    var displayName: String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? path : name
    }

    /// 是否像是目录路径（末尾 `/` 或仍存在且为目录）。
    var pathHasDirectoryHint: Bool {
        if path.hasSuffix("/") { return true }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        return false
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

enum PathRole: String, Codable, CaseIterable {
    case source
    case destination

    var title: String { self == .source ? "来源" : "目标" }
}

enum ByteFormatter {
    static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }

    /// 拆成「数值 + 单位」，供统计行不同字号显示。
    static func parts(_ bytes: Int64) -> (magnitude: String, unit: String) {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.isAdaptive = true
        formatter.includesUnit = false
        formatter.includesCount = true
        let magnitude = formatter.string(fromByteCount: bytes)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        formatter.includesUnit = true
        formatter.includesCount = false
        let unit = formatter.string(fromByteCount: max(bytes, 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if magnitude.isEmpty {
            return ("0", unit.isEmpty ? "KB" : unit)
        }
        return (magnitude, unit)
    }

    static func speed(_ bytesPerSecond: Double, language: AppLanguage = .chinese) -> String {
        let parts = speedParts(bytesPerSecond, language: language)
        if parts.unit.isEmpty { return parts.magnitude }
        return "\(parts.magnitude) \(parts.unit)"
    }
}

enum DurationFormatter {
    /// 将秒格式化为可读耗时；无语言参数时默认中文（兼容旧调用）。
    static func string(_ seconds: TimeInterval) -> String {
        string(seconds, language: .chinese)
    }
}
