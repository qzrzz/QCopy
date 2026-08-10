import AppKit
import Combine
import Foundation
import UserNotifications

@MainActor
final class CopyViewModel: ObservableObject {
    @Published var sourceURL: URL?
    @Published var destinationURL: URL?
    @Published var transferMode: TransferMode = .copy
    @Published var conflictPolicy: ConflictPolicy = .replace
    @Published var activeJob: TransferJob?
    @Published private(set) var history: [TransferHistoryEntry] = []
    @Published var showCompletionNotice = true

    private var workerTask: Task<CopyResult, Error>?
    private var completionTask: Task<Void, Never>?
    private var lastProgressDate = Date()
    private var lastProgressBytes: Int64 = 0

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        sourceURL = FileManager.default.fileExists(atPath: downloads.path) ? downloads : nil
        destinationURL = FileManager.default.fileExists(atPath: desktop.path) ? desktop : home
    }

    var isTransferring: Bool {
        guard let state = activeJob?.state else { return false }
        return state == .transferring || state == .cancelling
    }

    var hasReadyTransfer: Bool {
        sourceURL != nil && destinationURL != nil && !isTransferring
    }

    func chooseSource() {
        let panel = NSOpenPanel()
        panel.title = "选择来源"
        panel.message = "选择要复制或移动的文件 / 文件夹"
        panel.prompt = "选择来源"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            sourceURL = panel.url
        }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "选择目标文件夹"
        panel.message = "选择文件传输到的位置"
        panel.prompt = "选择目标"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            destinationURL = panel.url
        }
    }

    func setSource(from urls: [URL]) {
        guard let url = urls.first else { return }
        sourceURL = url
    }

    func setDestination(from urls: [URL]) {
        guard let url = urls.first else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        destinationURL = url
    }

    func startTransfer() {
        guard let sourceURL, let destinationURL, !isTransferring else { return }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            createFailedJob(source: sourceURL, destination: destinationURL, message: "来源不存在")
            return
        }

        let job = TransferJob(
            id: UUID(),
            source: sourceURL,
            destination: destinationURL,
            mode: transferMode,
            conflictPolicy: conflictPolicy,
            state: .transferring,
            phase: "连接文件系统",
            currentFile: "准备开始",
            bytesCopied: 0,
            totalBytes: 0,
            filesCopied: 0,
            filesSkipped: 0,
            startedAt: Date(),
            finishedAt: nil,
            duration: nil,
            speedBytesPerSecond: 0
        )
        activeJob = job
        lastProgressDate = Date()
        lastProgressBytes = 0

        let mode = transferMode
        let policy = conflictPolicy

        let jobID = job.id
        let progressHandler: @Sendable (CopyProgress) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.apply(progress, jobID: jobID)
            }
        }

        let worker = Task.detached(priority: .userInitiated) {
            try await CopyEngine.run(
                source: sourceURL,
                destination: destinationURL,
                mode: mode,
                conflictPolicy: policy,
                progress: progressHandler
            )
        }
        workerTask = worker
        completionTask = Task { @MainActor [weak self] in
            do {
                let result = try await worker.value
                self?.complete(result, jobID: jobID)
            } catch is CancellationError {
                self?.markCancelled(jobID: jobID)
            } catch {
                self?.markFailed(error.localizedDescription, jobID: jobID)
            }
        }
    }

    func cancelTransfer() {
        guard var job = activeJob, job.state == .transferring else { return }
        job.state = .cancelling
        job.phase = "正在停止"
        job.currentFile = "等待当前文件安全收尾"
        activeJob = job
        workerTask?.cancel()
    }

    func clearFinishedJob() {
        guard let job = activeJob else { return }
        guard job.state != .transferring, job.state != .cancelling else { return }
        activeJob = nil
    }

    private func apply(_ progress: CopyProgress, jobID: UUID) {
        guard var job = activeJob, job.id == jobID, job.state == .transferring else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastProgressDate)
        if elapsed > 0.12 {
            let delta = progress.bytesCopied - lastProgressBytes
            job.speedBytesPerSecond = Double(delta) / elapsed
            lastProgressDate = now
            lastProgressBytes = progress.bytesCopied
        }
        job.phase = progress.phase
        job.currentFile = progress.currentFile
        job.bytesCopied = progress.bytesCopied
        job.totalBytes = progress.totalBytes
        job.filesCopied = progress.filesCopied
        job.filesSkipped = progress.filesSkipped
        activeJob = job
    }

    private func complete(_ result: CopyResult, jobID: UUID) {
        guard var job = activeJob, job.id == jobID else { return }
        job.state = .completed
        job.phase = "传输完成"
        job.currentFile = result.filesSkipped > 0 ? "完成，跳过 \(result.filesSkipped) 项" : "所有项目已完成"
        job.bytesCopied = result.bytesCopied
        job.totalBytes = max(job.totalBytes, result.bytesCopied)
        job.filesCopied = result.filesCopied
        job.filesSkipped = result.filesSkipped
        job.finishedAt = Date()
        job.duration = result.duration
        job.speedBytesPerSecond = result.duration > 0 ? Double(result.bytesCopied) / result.duration : 0
        activeJob = job
        addHistory(for: job)
        workerTask = nil
        completionTask = nil
        if showCompletionNotice {
            showNotification(for: job)
        }
    }

    private func markCancelled(jobID: UUID) {
        guard var job = activeJob,
              job.id == jobID,
              job.state == .transferring || job.state == .cancelling else { return }
        job.state = .cancelled
        job.phase = "已停止"
        job.currentFile = "任务已取消，已传输的数据会保留"
        job.finishedAt = Date()
        activeJob = job
        addHistory(for: job)
        workerTask = nil
        completionTask = nil
    }

    private func markFailed(_ message: String, jobID: UUID) {
        guard var job = activeJob, job.id == jobID else { return }
        job.state = .failed(message)
        job.phase = "传输失败"
        job.currentFile = message
        job.finishedAt = Date()
        activeJob = job
        addHistory(for: job)
        workerTask = nil
        completionTask = nil
    }

    private func createFailedJob(source: URL, destination: URL, message: String) {
        activeJob = TransferJob(
            id: UUID(), source: source, destination: destination,
            mode: transferMode, conflictPolicy: conflictPolicy,
            state: .failed(message), phase: "无法开始", currentFile: message,
            bytesCopied: 0, totalBytes: 0, filesCopied: 0, filesSkipped: 0,
            startedAt: Date(), finishedAt: Date(), duration: nil, speedBytesPerSecond: 0
        )
    }

    private func addHistory(for job: TransferJob) {
        history.insert(
            TransferHistoryEntry(
                source: job.sourceName,
                destination: job.destinationName,
                mode: job.mode,
                bytes: job.bytesCopied,
                files: job.filesCopied,
                date: job.finishedAt ?? Date(),
                state: job.state
            ),
            at: 0
        )
        if history.count > 12 { history.removeLast() }
    }

    private func showNotification(for job: TransferJob) {
        let title = job.mode == .copy ? "复制完成" : "移动完成"
        let body = "已处理 \(job.filesCopied) 个项目 · \(ByteFormatter.string(job.bytesCopied))"
        let identifier = job.id.uuidString
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            do {
                guard try await center.requestAuthorization(options: [.alert]) else { return }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
                try await center.add(request)
            } catch {
                // 通知权限是可选能力，不能影响传输结果。
            }
        }
    }
}
