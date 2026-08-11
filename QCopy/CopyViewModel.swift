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
    @Published var smartParallel: Bool = true {
        didSet { defaults.set(smartParallel, forKey: StorageKey.smartParallel) }
    }
    @Published var activeJob: TransferJob?
    @Published private(set) var history: [TransferHistoryEntry] = []
    @Published private(set) var recentSources: [RecentPathEntry] = []
    @Published private(set) var recentDestinations: [RecentPathEntry] = []
    @Published var showCompletionNotice = true

    private var workerTask: Task<CopyResult, Error>?
    private var completionTask: Task<Void, Never>?

    /// 速度估算用的 (时间, 已传字节) 采样窗口。
    private var speedSamples: [(date: Date, bytes: Int64)] = []
    private var smoothedSpeed: Double = 0
    /// 任务累计已传字节只升不降（用于速度与「已传输」）。
    private var peakBytesCopied: Int64 = 0
    /// 当前任务界面语言（通知等收尾文案）。
    private var activeLanguage: AppLanguage = .chinese

    private let defaults = UserDefaults.standard
    private let maxRecentPaths = 16
    private let maxHistory = 12
    /// 瞬时速度滑动窗口长度（秒）。
    private let speedWindowSeconds: TimeInterval = 2.5
    /// 图表采样间隔，避免 copyfile 高频回调造成过多 UI 更新。
    private let statisticsSampleInterval: TimeInterval = 0.25
    private let maxStatisticsSamples = 240

    private enum StorageKey {
        static let recentSources = "qcopy.recentSources"
        static let recentDestinations = "qcopy.recentDestinations"
        static let lastSource = "qcopy.lastSourcePath"
        static let lastDestination = "qcopy.lastDestinationPath"
        static let transferHistory = "qcopy.transferHistory"
        static let smartParallel = "qcopy.smartParallel"
    }

    init() {
        loadPersistedState()
        restoreLastPathsOrDefaults()
    }

    var isTransferring: Bool {
        guard let state = activeJob?.state else { return false }
        return state == .transferring || state == .cancelling
    }

    var hasReadyTransfer: Bool {
        sourceURL != nil && destinationURL != nil && !isTransferring
    }

    // MARK: - Path selection

    func chooseSource(language: AppLanguage = .chinese) {
        let panel = NSOpenPanel()
        panel.title = L10n.string(.chooseSource, language: language)
        panel.message = L10n.string(.chooseSourceMessage, language: language)
        panel.prompt = L10n.string(.chooseSource, language: language)
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let sourceURL {
            panel.directoryURL = sourceURL.deletingLastPathComponent()
        } else if let first = recentSources.first {
            panel.directoryURL = URL(fileURLWithPath: first.path).deletingLastPathComponent()
        }
        if panel.runModal() == .OK, let url = panel.url {
            applySource(url)
        }
    }

    func chooseDestination(language: AppLanguage = .chinese) {
        let panel = NSOpenPanel()
        panel.title = L10n.string(.chooseDestination, language: language)
        panel.message = L10n.string(.chooseDestinationMessage, language: language)
        panel.prompt = L10n.string(.chooseDestinationPrompt, language: language)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let destinationURL {
            panel.directoryURL = destinationURL
        } else if let first = recentDestinations.first {
            panel.directoryURL = URL(fileURLWithPath: first.path)
        }
        if panel.runModal() == .OK, let url = panel.url {
            applyDestination(url)
        }
    }

    func setSource(from urls: [URL]) {
        guard let url = urls.first else { return }
        applySource(url)
    }

    func setDestination(from urls: [URL]) {
        guard let url = urls.first else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        applyDestination(url)
    }

    /// 从路径记录快速选用来源。
    func selectRecentSource(_ entry: RecentPathEntry) {
        guard entry.exists else {
            removeRecent(path: entry.path, role: .source)
            return
        }
        applySource(URL(fileURLWithPath: entry.path, isDirectory: entry.pathHasDirectoryHint))
    }

    /// 从路径记录快速选用目标。
    func selectRecentDestination(_ entry: RecentPathEntry) {
        guard entry.exists else {
            removeRecent(path: entry.path, role: .destination)
            return
        }
        var isDirectory: ObjCBool = false
        let path = entry.path
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            removeRecent(path: path, role: .destination)
            return
        }
        applyDestination(URL(fileURLWithPath: path, isDirectory: true))
    }

    func clearRecentPaths(role: PathRole? = nil) {
        switch role {
        case .source:
            recentSources = []
            defaults.removeObject(forKey: StorageKey.recentSources)
        case .destination:
            recentDestinations = []
            defaults.removeObject(forKey: StorageKey.recentDestinations)
        case nil:
            recentSources = []
            recentDestinations = []
            defaults.removeObject(forKey: StorageKey.recentSources)
            defaults.removeObject(forKey: StorageKey.recentDestinations)
        }
    }

    func clearTransferHistory() {
        history = []
        defaults.removeObject(forKey: StorageKey.transferHistory)
    }

    /// 删除单条操作记录。
    func removeHistoryEntry(_ entry: TransferHistoryEntry) {
        history.removeAll { $0.id == entry.id }
        persistHistory()
    }

    // MARK: - Transfer

    func startTransfer(language: AppLanguage = .chinese) {
        guard let sourceURL, let destinationURL, !isTransferring else { return }
        activeLanguage = language
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            createFailedJob(
                source: sourceURL,
                destination: destinationURL,
                message: L10n.string(.sourceMissing, language: language)
            )
            return
        }

        // 开始传输时再次记入路径记录（强化最近使用顺序）
        recordPath(sourceURL, role: .source)
        recordPath(destinationURL, role: .destination)

        let startedAt = Date()
        let job = TransferJob(
            id: UUID(),
            source: sourceURL,
            destination: destinationURL,
            mode: transferMode,
            conflictPolicy: conflictPolicy,
            state: .transferring,
            // phase / currentFile 仍用中文键值，展示时经 L10n.phase 本地化
            phase: "连接文件系统",
            currentFile: "准备开始",
            bytesCopied: 0,
            currentFileBytes: 0,
            currentFileTotalBytes: 0,
            currentConcurrency: 1,
            filesCopied: 0,
            filesSkipped: 0,
            samples: [TransferSample(elapsed: 0, speedBytesPerSecond: 0, concurrency: 1)],
            startedAt: startedAt,
            finishedAt: nil,
            duration: nil,
            speedBytesPerSecond: 0
        )
        activeJob = job
        resetSpeedTracking()
        peakBytesCopied = 0

        let mode = transferMode
        let policy = conflictPolicy
        let useSmartParallel = smartParallel

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
                smartParallel: useSmartParallel,
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

    // MARK: - Private path helpers

    private func applySource(_ url: URL) {
        sourceURL = url
        recordPath(url, role: .source)
        defaults.set(url.path, forKey: StorageKey.lastSource)
    }

    private func applyDestination(_ url: URL) {
        destinationURL = url
        recordPath(url, role: .destination)
        defaults.set(url.path, forKey: StorageKey.lastDestination)
    }

    private func recordPath(_ url: URL, role: PathRole) {
        let standardized = url.standardizedFileURL.path
        let entry = RecentPathEntry(path: standardized, lastUsed: Date())
        switch role {
        case .source:
            recentSources = upsert(entry, into: recentSources)
            persistRecent(recentSources, key: StorageKey.recentSources)
        case .destination:
            recentDestinations = upsert(entry, into: recentDestinations)
            persistRecent(recentDestinations, key: StorageKey.recentDestinations)
        }
    }

    private func upsert(_ entry: RecentPathEntry, into list: [RecentPathEntry]) -> [RecentPathEntry] {
        var next = list.filter { $0.path != entry.path }
        next.insert(entry, at: 0)
        if next.count > maxRecentPaths {
            next = Array(next.prefix(maxRecentPaths))
        }
        return next
    }

    private func removeRecent(path: String, role: PathRole) {
        switch role {
        case .source:
            recentSources.removeAll { $0.path == path }
            persistRecent(recentSources, key: StorageKey.recentSources)
        case .destination:
            recentDestinations.removeAll { $0.path == path }
            persistRecent(recentDestinations, key: StorageKey.recentDestinations)
        }
    }

    private func persistRecent(_ list: [RecentPathEntry], key: String) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: key)
        }
    }

    private func loadPersistedState() {
        if defaults.object(forKey: StorageKey.smartParallel) != nil {
            smartParallel = defaults.bool(forKey: StorageKey.smartParallel)
        }
        if let data = defaults.data(forKey: StorageKey.recentSources),
           let list = try? JSONDecoder().decode([RecentPathEntry].self, from: data) {
            recentSources = list
        }
        if let data = defaults.data(forKey: StorageKey.recentDestinations),
           let list = try? JSONDecoder().decode([RecentPathEntry].self, from: data) {
            recentDestinations = list
        }
        if let data = defaults.data(forKey: StorageKey.transferHistory),
           let list = try? JSONDecoder().decode([TransferHistoryEntry].self, from: data) {
            history = Array(list.prefix(maxHistory))
        }
    }

    private func persistHistory() {
        if history.isEmpty {
            defaults.removeObject(forKey: StorageKey.transferHistory)
            return
        }
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: StorageKey.transferHistory)
        }
    }

    private func restoreLastPathsOrDefaults() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)

        if let path = defaults.string(forKey: StorageKey.lastSource),
           fm.fileExists(atPath: path) {
            sourceURL = URL(fileURLWithPath: path)
        } else if let first = recentSources.first, first.exists {
            sourceURL = URL(fileURLWithPath: first.path)
        } else {
            sourceURL = fm.fileExists(atPath: downloads.path) ? downloads : nil
        }

        if let path = defaults.string(forKey: StorageKey.lastDestination),
           fm.fileExists(atPath: path) {
            destinationURL = URL(fileURLWithPath: path, isDirectory: true)
        } else if let first = recentDestinations.first, first.exists {
            destinationURL = URL(fileURLWithPath: first.path, isDirectory: true)
        } else {
            destinationURL = fm.fileExists(atPath: desktop.path) ? desktop : home
        }
    }

    // MARK: - Progress / completion

    private func apply(_ progress: CopyProgress, jobID: UUID) {
        guard var job = activeJob, job.id == jobID, job.state == .transferring else { return }

        // 累计已传只升不降；单文件进度允许在换文件时归零再涨。
        peakBytesCopied = max(peakBytesCopied, max(0, progress.bytesCopied))
        job.bytesCopied = peakBytesCopied
        job.currentFileBytes = max(0, progress.currentFileBytes)
        job.currentFileTotalBytes = max(0, progress.currentFileTotalBytes)
        job.currentConcurrency = max(1, progress.currentConcurrency)
        job.phase = progress.phase
        job.currentFile = progress.currentFile
        job.filesCopied = progress.filesCopied
        job.filesSkipped = progress.filesSkipped
        job.speedBytesPerSecond = updatedSpeed(
            bytesCopied: peakBytesCopied,
            startedAt: job.startedAt,
            phase: progress.phase
        )
        appendStatisticsSample(to: &job, now: Date())
        activeJob = job
    }

    private func complete(_ result: CopyResult, jobID: UUID) {
        guard var job = activeJob, job.id == jobID else { return }
        job.state = .completed
        job.phase = "传输完成"
        job.currentFile = result.filesSkipped > 0 ? "完成，跳过 \(result.filesSkipped) 项" : "所有项目已完成"
        job.bytesCopied = max(peakBytesCopied, result.bytesCopied)
        job.currentFileBytes = 0
        job.currentFileTotalBytes = 0
        job.filesCopied = result.filesCopied
        job.filesSkipped = result.filesSkipped
        let finishedAt = Date()
        job.finishedAt = finishedAt
        // 优先用引擎计时；再与墙钟取较大值，避免极短任务 duration≈0。
        let wall = finishedAt.timeIntervalSince(job.startedAt)
        let engineDuration = max(0, result.duration)
        job.duration = max(engineDuration, wall)
        // 完成后的速度 = 已传输 / 总耗时（全程平均）。
        job.speedBytesPerSecond = averageSpeed(
            bytesCopied: job.bytesCopied,
            duration: job.duration ?? 0
        )
        appendStatisticsSample(to: &job, now: finishedAt, force: true)
        activeJob = job
        addHistory(for: job)
        workerTask = nil
        completionTask = nil
        resetSpeedTracking()
        if showCompletionNotice {
            showNotification(for: job)
        }
    }

    private func resetSpeedTracking() {
        speedSamples = []
        smoothedSpeed = 0
    }

    /// 用最近窗口内的有效吞吐做 EMA，并与全程平均融合，减少尖峰与归零抖动。
    private func updatedSpeed(bytesCopied: Int64, startedAt: Date, phase: String) -> Double {
        let now = Date()
        speedSamples.append((date: now, bytes: bytesCopied))
        let cutoff = now.addingTimeInterval(-speedWindowSeconds)
        speedSamples.removeAll { $0.date < cutoff }

        let overallElapsed = now.timeIntervalSince(startedAt)
        let overallAverage: Double = {
            guard overallElapsed > 0.25, bytesCopied > 0 else { return 0 }
            return Double(bytesCopied) / overallElapsed
        }()

        guard let first = speedSamples.first, let last = speedSamples.last else {
            return overallAverage
        }

        let windowElapsed = last.date.timeIntervalSince(first.date)
        let windowDelta = last.bytes - first.bytes

        // 窗口太短或字节几乎未动：回落全程平均，避免「速度突然归零」。
        if windowElapsed < 0.35 || windowDelta < 0 {
            return blendSpeed(candidate: overallAverage)
        }

        // 极小写入（大量小文件间隙）用更长基线，避免瞬时 Mbps 乱跳。
        let windowRate = Double(windowDelta) / windowElapsed
        if windowDelta < 64 * 1024, overallAverage > 0 {
            return blendSpeed(candidate: overallAverage * 0.65 + windowRate * 0.35)
        }

        return blendSpeed(candidate: windowRate * 0.75 + overallAverage * 0.25)
    }

    private func blendSpeed(candidate: Double) -> Double {
        let value = max(0, candidate)
        if smoothedSpeed <= 0 {
            smoothedSpeed = value
        } else {
            // 上升跟得稍快，下降更平滑，贴近真实体感。
            let alpha = value >= smoothedSpeed ? 0.45 : 0.22
            smoothedSpeed = smoothedSpeed * (1 - alpha) + value * alpha
        }
        return smoothedSpeed
    }

    private func markCancelled(jobID: UUID) {
        guard var job = activeJob,
              job.id == jobID,
              job.state == .transferring || job.state == .cancelling else { return }
        job.state = .cancelled
        job.phase = "已停止"
        job.currentFile = "任务已取消，已传输的数据会保留"
        finalizeTimingAndAverageSpeed(for: &job)
        appendStatisticsSample(to: &job, now: job.finishedAt ?? Date(), force: true)
        activeJob = job
        addHistory(for: job)
        workerTask = nil
        completionTask = nil
        resetSpeedTracking()
    }

    private func markFailed(_ message: String, jobID: UUID) {
        guard var job = activeJob, job.id == jobID else { return }
        job.state = .failed(message)
        job.phase = "传输失败"
        job.currentFile = message
        finalizeTimingAndAverageSpeed(for: &job)
        appendStatisticsSample(to: &job, now: job.finishedAt ?? Date(), force: true)
        activeJob = job
        addHistory(for: job)
        workerTask = nil
        completionTask = nil
        resetSpeedTracking()
    }

    /// 结束任务时写入耗时，并把速度改成「已传输 / 总耗时」的全程平均。
    private func finalizeTimingAndAverageSpeed(for job: inout TransferJob) {
        let finishedAt = Date()
        job.finishedAt = finishedAt
        let duration = max(0, finishedAt.timeIntervalSince(job.startedAt))
        job.duration = duration
        job.speedBytesPerSecond = averageSpeed(bytesCopied: job.bytesCopied, duration: duration)
    }

    private func appendStatisticsSample(
        to job: inout TransferJob,
        now: Date,
        force: Bool = false
    ) {
        let elapsed = max(0, now.timeIntervalSince(job.startedAt))
        if !force,
           let last = job.samples.last,
           elapsed - last.elapsed < statisticsSampleInterval {
            return
        }
        job.samples.append(
            TransferSample(
                elapsed: elapsed,
                speedBytesPerSecond: job.speedBytesPerSecond,
                concurrency: job.currentConcurrency
            )
        )
        if job.samples.count > maxStatisticsSamples {
            job.samples.removeFirst(job.samples.count - maxStatisticsSamples)
        }
    }

    private func averageSpeed(bytesCopied: Int64, duration: TimeInterval) -> Double {
        guard duration > 0, bytesCopied > 0 else { return 0 }
        return Double(bytesCopied) / duration
    }

    private func createFailedJob(source: URL, destination: URL, message: String) {
        let job = TransferJob(
            id: UUID(), source: source, destination: destination,
            mode: transferMode, conflictPolicy: conflictPolicy,
            state: .failed(message), phase: "无法开始", currentFile: message,
            bytesCopied: 0, currentFileBytes: 0, currentFileTotalBytes: 0,
            currentConcurrency: 1,
            filesCopied: 0, filesSkipped: 0,
            samples: [],
            startedAt: Date(), finishedAt: Date(), duration: 0, speedBytesPerSecond: 0
        )
        activeJob = job
        addHistory(for: job)
    }

    private func addHistory(for job: TransferJob) {
        let duration = job.duration
            ?? job.finishedAt.map { $0.timeIntervalSince(job.startedAt) }
        history.insert(
            TransferHistoryEntry(
                id: job.id,
                source: job.sourceName,
                destination: job.destinationName,
                sourcePath: job.source.standardizedFileURL.path,
                destinationPath: job.destination.standardizedFileURL.path,
                mode: job.mode,
                conflictPolicy: job.conflictPolicy,
                bytes: job.bytesCopied,
                files: job.filesCopied,
                filesSkipped: job.filesSkipped,
                duration: duration,
                averageSpeedBytesPerSecond: averageSpeed(
                    bytesCopied: job.bytesCopied,
                    duration: duration ?? 0
                ),
                date: job.finishedAt ?? Date(),
                state: job.state,
                samples: job.samples
            ),
            at: 0
        )
        if history.count > maxHistory {
            history = Array(history.prefix(maxHistory))
        }
        persistHistory()
    }

    private func showNotification(for job: TransferJob) {
        let lang = activeLanguage
        let title = L10n.string(job.mode == .copy ? .copyFinished : .moveFinished, language: lang)
        let processed = L10n.string(.processed, language: lang)
        let items = L10n.string(.unitItems, language: lang)
        let body = "\(processed) \(job.filesCopied) \(items) · \(ByteFormatter.string(job.bytesCopied))"
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
