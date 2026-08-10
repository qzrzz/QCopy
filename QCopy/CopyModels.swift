import Foundation

enum TransferMode: String, CaseIterable, Identifiable, Sendable {
    case copy
    case move

    var id: String { rawValue }
    var title: String { self == .copy ? "复制" : "移动" }
    var symbol: String { self == .copy ? "doc.on.doc" : "arrow.right.doc.on.clipboard" }
    var description: String {
        self == .copy ? "保留原文件，创建一份副本" : "传输完成后移除原文件"
    }
}

enum ConflictPolicy: String, CaseIterable, Identifiable, Sendable {
    case replace
    case skip
    case rename

    var id: String { rawValue }
    var title: String {
        switch self {
        case .replace: "替换现有文件"
        case .skip: "跳过现有文件"
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
    var bytesCopied: Int64
    var totalBytes: Int64
    var filesCopied: Int
    var filesSkipped: Int
}

struct CopyResult: Sendable {
    let bytesCopied: Int64
    let filesCopied: Int
    let filesSkipped: Int
    let duration: TimeInterval
}

enum TransferState: Equatable {
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
    var bytesCopied: Int64
    var totalBytes: Int64
    var filesCopied: Int
    var filesSkipped: Int
    var startedAt: Date
    var finishedAt: Date?
    var duration: TimeInterval?
    var speedBytesPerSecond: Double

    var progress: Double {
        guard totalBytes > 0 else { return state == .completed ? 1 : 0 }
        return min(max(Double(bytesCopied) / Double(totalBytes), 0), 1)
    }

    var sourceName: String { source.lastPathComponent.isEmpty ? source.path : source.lastPathComponent }
    var destinationName: String { destination.lastPathComponent.isEmpty ? destination.path : destination.lastPathComponent }
}

struct TransferHistoryEntry: Identifiable {
    let id = UUID()
    let source: String
    let destination: String
    let mode: TransferMode
    let bytes: Int64
    let files: Int
    let date: Date
    let state: TransferState
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

    static func speed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "—" }
        return "\(string(Int64(bytesPerSecond)))/秒"
    }
}
