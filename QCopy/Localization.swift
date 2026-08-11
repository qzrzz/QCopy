import Foundation
import SwiftUI

// MARK: - Language preference

/// 应用语言：中文 / 英文 / 跟随系统。
enum LanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case chinese
    case english

    var id: String { rawValue }

    /// 菜单显示名（固定，便于识别）。
    var menuTitle: String {
        switch self {
        case .system: "跟随系统 / System"
        case .chinese: "中文"
        case .english: "English"
        }
    }

    /// 解析后的实际界面语言。
    var resolved: AppLanguage {
        switch self {
        case .chinese: return .chinese
        case .english: return .english
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            if preferred.hasPrefix("zh") { return .chinese }
            return .english
        }
    }
}

enum AppLanguage: String, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    var locale: Locale { Locale(identifier: rawValue) }
}

// MARK: - Settings

/// 持久化语言偏好，并驱动界面刷新。
@MainActor
final class LanguageSettings: ObservableObject {
    @Published var preference: LanguagePreference {
        didSet {
            guard oldValue != preference else { return }
            defaults.set(preference.rawValue, forKey: StorageKey.language)
        }
    }

    var language: AppLanguage { preference.resolved }

    private let defaults = UserDefaults.standard

    private enum StorageKey {
        static let language = "qcopy.languagePreference"
    }

    init() {
        if let raw = defaults.string(forKey: StorageKey.language),
           let saved = LanguagePreference(rawValue: raw) {
            preference = saved
        } else {
            preference = .system
        }
    }

    func t(_ key: L10n.Key) -> String {
        L10n.string(key, language: language)
    }

    /// 引擎 / 内部 phase 原文 → 当前语言。
    func phase(_ raw: String) -> String {
        L10n.phase(raw, language: language)
    }

    func format(_ key: L10n.Key, _ args: CVarArg...) -> String {
        String(format: t(key), locale: language.locale, arguments: args)
    }
}

// MARK: - Catalog

enum L10n {
    enum Key: String {
        case appearanceMenu, appearanceSection, languageSection
        case appearanceDark, appearanceLight, appearanceSystem
        case chooseSourceMenu, chooseDestinationMenu, startCopyMenu, cancelCurrentTask, clearHistory
        case checkForUpdates

        case sectionTransfer, sectionHistory, sectionTransferSubtitle, sectionHistorySubtitle

        case modeCopy, modeMove, modeCopyDesc, modeMoveDesc
        case conflictReplace, conflictSkip, conflictRename, conflictSection
        case smartParallel, transferModePicker, transferModeA11y

        case pathSource, pathDestination, pathSourceHelper, pathDestinationHelper
        case browse, recentUsed, browseOrChoosePath, recentPaths, pleaseChooseLocation
        case chooseSource, chooseSourceMessage, chooseDestination, chooseDestinationMessage, chooseDestinationPrompt

        case startCopy, startMove, cancel, collapse, stoppingSafely
        case readyCopy, readyMove, startHint, needPathsHint

        case stateQueued, stateTransferring, stateCancelling, stateCompleted, stateCancelled, stateFailed

        case transferred, processed, speed, averageSpeed, concurrency, skipped
        case unitItems, unitStreams, transferStats, waitingTransferData, noSpeedSamples
        case elapsedA11y, chartA11y

        case emptyHistoryTitle, emptyHistoryBody
        case fileCount, transferSize, transferDuration, avgSpeed, deleteRecord

        case copyFinished, moveFinished, sourceMissing, connectingFS, readyToStart
        case stopping, waitingSafeStop, transferDone, allItemsDone, stopped
        case cancelledKeepData, cannotStart, completedWithSkipped
        case phaseSameVolumeMove, phaseAPFSClone

        case operationMethod, keepOrRemove, conflictWhenExists
        case conflictReplaceDesc, conflictSkipDesc, conflictRenameDesc
        case transferPaths, dropOrClick
        case unitSeconds
    }

    private static let zh: [Key: String] = [
        .appearanceMenu: "外观",
        .appearanceSection: "外观",
        .languageSection: "语言",
        .appearanceDark: "黑夜",
        .appearanceLight: "明亮",
        .appearanceSystem: "系统",
        .chooseSourceMenu: "选择来源…",
        .chooseDestinationMenu: "选择目标…",
        .startCopyMenu: "开始复制",
        .cancelCurrentTask: "取消当前任务",
        .clearHistory: "清空记录",
        .checkForUpdates: "检查更新…",

        .sectionTransfer: "复制 / 移动",
        .sectionHistory: "操作记录",
        .sectionTransferSubtitle: "创建新的传输任务",
        .sectionHistorySubtitle: "复制 / 移动历史",

        .modeCopy: "复制",
        .modeMove: "移动",
        .modeCopyDesc: "保留原文件，创建一份副本",
        .modeMoveDesc: "传输完成后移除原文件",
        .conflictReplace: "覆盖已存在文件",
        .conflictSkip: "跳过已存在文件",
        .conflictRename: "自动重命名",
        .conflictSection: "冲突处理",
        .smartParallel: "智能并发",
        .transferModePicker: "传输方式",
        .transferModeA11y: "复制或移动",

        .pathSource: "来源",
        .pathDestination: "目标",
        .pathSourceHelper: "拖入文件或文件夹",
        .pathDestinationHelper: "选择目标文件夹",
        .browse: "浏览…",
        .recentUsed: "最近使用",
        .browseOrChoosePath: "浏览或选择路径",
        .recentPaths: "最近路径",
        .pleaseChooseLocation: "请选择位置",
        .chooseSource: "选择来源",
        .chooseSourceMessage: "选择要复制或移动的文件 / 文件夹",
        .chooseDestination: "选择目标文件夹",
        .chooseDestinationMessage: "选择文件传输到的位置",
        .chooseDestinationPrompt: "选择目标",

        .startCopy: "开始复制",
        .startMove: "开始移动",
        .cancel: "取消",
        .collapse: "收起",
        .stoppingSafely: "正在安全停止…",
        .readyCopy: "准备复制",
        .readyMove: "准备移动",
        .startHint: "⌘↩ 开始传输",
        .needPathsHint: "请选择来源和目标后继续",

        .stateQueued: "等待开始",
        .stateTransferring: "正在传输",
        .stateCancelling: "正在停止",
        .stateCompleted: "已完成",
        .stateCancelled: "已取消",
        .stateFailed: "传输失败",

        .transferred: "已传输",
        .processed: "已处理",
        .speed: "速度",
        .averageSpeed: "平均速度",
        .concurrency: "并发",
        .skipped: "已跳过",
        .unitItems: "项",
        .unitStreams: "路",
        .transferStats: "传输统计",
        .waitingTransferData: "等待传输数据…",
        .noSpeedSamples: "无速度采样",
        .elapsedA11y: "耗时",
        .chartA11y: "复制速度和并发数量折线图",

        .emptyHistoryTitle: "暂无操作记录",
        .emptyHistoryBody: "完成一次复制或移动后，会显示文件数、传输尺寸、耗时、平均速度与统计图",
        .fileCount: "文件数量",
        .transferSize: "传输尺寸",
        .transferDuration: "传输耗时",
        .avgSpeed: "平均速度",
        .deleteRecord: "删除记录",

        .copyFinished: "复制完成",
        .moveFinished: "移动完成",
        .sourceMissing: "来源不存在",
        .connectingFS: "连接文件系统",
        .readyToStart: "准备开始",
        .stopping: "正在停止",
        .waitingSafeStop: "等待当前文件安全收尾",
        .transferDone: "传输完成",
        .allItemsDone: "所有项目已完成",
        .stopped: "已停止",
        .cancelledKeepData: "任务已取消，已传输的数据会保留",
        .cannotStart: "无法开始",
        .completedWithSkipped: "完成，跳过 %d 项",
        .phaseSameVolumeMove: "同卷快速移动",
        .phaseAPFSClone: "APFS 快速克隆",

        .operationMethod: "操作方式",
        .keepOrRemove: "保留或移除原文件",
        .conflictWhenExists: "目标存在同名文件时",
        .conflictReplaceDesc: "直接覆盖目标中的同名文件",
        .conflictSkipDesc: "保留目标文件，跳过这一项",
        .conflictRenameDesc: "为新文件添加序号后缀",
        .transferPaths: "传输路径",
        .dropOrClick: "拖入来源，或点击选择",
        .unitSeconds: "秒",
    ]

    private static let en: [Key: String] = [
        .appearanceMenu: "Appearance",
        .appearanceSection: "Appearance",
        .languageSection: "Language",
        .appearanceDark: "Dark",
        .appearanceLight: "Light",
        .appearanceSystem: "System",
        .chooseSourceMenu: "Choose Source…",
        .chooseDestinationMenu: "Choose Destination…",
        .startCopyMenu: "Start Copy",
        .cancelCurrentTask: "Cancel Current Task",
        .clearHistory: "Clear History",
        .checkForUpdates: "Check for Updates…",

        .sectionTransfer: "Copy / Move",
        .sectionHistory: "History",
        .sectionTransferSubtitle: "Start a new transfer",
        .sectionHistorySubtitle: "Copy / move history",

        .modeCopy: "Copy",
        .modeMove: "Move",
        .modeCopyDesc: "Keep the original and create a duplicate",
        .modeMoveDesc: "Remove the original after transfer",
        .conflictReplace: "Replace existing files",
        .conflictSkip: "Skip existing files",
        .conflictRename: "Auto-rename",
        .conflictSection: "Conflict handling",
        .smartParallel: "Smart parallel",
        .transferModePicker: "Transfer mode",
        .transferModeA11y: "Copy or move",

        .pathSource: "Source",
        .pathDestination: "Destination",
        .pathSourceHelper: "Drop a file or folder",
        .pathDestinationHelper: "Choose a destination folder",
        .browse: "Browse…",
        .recentUsed: "Recent",
        .browseOrChoosePath: "Browse or choose a path",
        .recentPaths: "Recent paths",
        .pleaseChooseLocation: "Choose a location",
        .chooseSource: "Choose Source",
        .chooseSourceMessage: "Select the file or folder to copy or move",
        .chooseDestination: "Choose Destination Folder",
        .chooseDestinationMessage: "Select where files should be transferred",
        .chooseDestinationPrompt: "Choose Destination",

        .startCopy: "Start Copy",
        .startMove: "Start Move",
        .cancel: "Cancel",
        .collapse: "Dismiss",
        .stoppingSafely: "Stopping safely…",
        .readyCopy: "Ready to copy",
        .readyMove: "Ready to move",
        .startHint: "⌘↩ to start",
        .needPathsHint: "Choose source and destination to continue",

        .stateQueued: "Queued",
        .stateTransferring: "Transferring",
        .stateCancelling: "Stopping",
        .stateCompleted: "Completed",
        .stateCancelled: "Cancelled",
        .stateFailed: "Failed",

        .transferred: "Transferred",
        .processed: "Processed",
        .speed: "Speed",
        .averageSpeed: "Avg. speed",
        .concurrency: "Parallel",
        .skipped: "Skipped",
        .unitItems: "items",
        .unitStreams: "streams",
        .transferStats: "Transfer stats",
        .waitingTransferData: "Waiting for transfer data…",
        .noSpeedSamples: "No speed samples",
        .elapsedA11y: "Elapsed",
        .chartA11y: "Transfer speed and concurrency chart",

        .emptyHistoryTitle: "No history yet",
        .emptyHistoryBody: "After a copy or move, file count, size, duration, average speed, and charts appear here",
        .fileCount: "Files",
        .transferSize: "Size",
        .transferDuration: "Duration",
        .avgSpeed: "Avg. speed",
        .deleteRecord: "Delete record",

        .copyFinished: "Copy finished",
        .moveFinished: "Move finished",
        .sourceMissing: "Source does not exist",
        .connectingFS: "Connecting to file system",
        .readyToStart: "Ready to start",
        .stopping: "Stopping",
        .waitingSafeStop: "Waiting for the current file to finish safely",
        .transferDone: "Transfer complete",
        .allItemsDone: "All items finished",
        .stopped: "Stopped",
        .cancelledKeepData: "Cancelled. Already transferred data is kept",
        .cannotStart: "Unable to start",
        .completedWithSkipped: "Done, skipped %d items",
        .phaseSameVolumeMove: "Same-volume quick move",
        .phaseAPFSClone: "APFS clone",

        .operationMethod: "Operation",
        .keepOrRemove: "Keep or remove originals",
        .conflictWhenExists: "When a file already exists",
        .conflictReplaceDesc: "Overwrite the existing file at the destination",
        .conflictSkipDesc: "Keep the existing file and skip this item",
        .conflictRenameDesc: "Add a numeric suffix to the new file",
        .transferPaths: "Transfer paths",
        .dropOrClick: "Drop a source, or click to choose",
        .unitSeconds: "s",
    ]

    static func string(_ key: Key, language: AppLanguage) -> String {
        let table = language == .chinese ? zh : en
        return table[key] ?? en[key] ?? key.rawValue
    }

    /// 引擎 phase 原文（多为中文）→ 当前语言文案。
    static func phase(_ raw: String, language: AppLanguage) -> String {
        switch raw {
        case "传输中":
            return string(.stateTransferring, language: language)
        case "同卷快速移动":
            return string(.phaseSameVolumeMove, language: language)
        case "已跳过":
            return string(.skipped, language: language)
        case "APFS 快速克隆":
            return string(.phaseAPFSClone, language: language)
        case "连接文件系统":
            return string(.connectingFS, language: language)
        case "准备开始":
            return string(.readyToStart, language: language)
        case "正在停止":
            return string(.stopping, language: language)
        case "等待当前文件安全收尾":
            return string(.waitingSafeStop, language: language)
        case "传输完成":
            return string(.transferDone, language: language)
        case "所有项目已完成":
            return string(.allItemsDone, language: language)
        case "已停止":
            return string(.stopped, language: language)
        case "任务已取消，已传输的数据会保留":
            return string(.cancelledKeepData, language: language)
        case "无法开始":
            return string(.cannotStart, language: language)
        case "传输失败":
            return string(.stateFailed, language: language)
        case "来源不存在":
            return string(.sourceMissing, language: language)
        default:
            break
        }

        // 「完成，跳过 N 项」
        if raw.hasPrefix("完成，跳过") || raw.hasPrefix("Done, skipped") {
            let digits = raw.compactMap { $0.isNumber ? $0 : nil }
            if let n = Int(String(digits)) {
                return String(format: string(.completedWithSkipped, language: language), n)
            }
        }
        return raw
    }
}

// MARK: - Model helpers

extension TransferMode {
    func title(_ lang: AppLanguage) -> String {
        L10n.string(self == .copy ? .modeCopy : .modeMove, language: lang)
    }

    func description(_ lang: AppLanguage) -> String {
        L10n.string(self == .copy ? .modeCopyDesc : .modeMoveDesc, language: lang)
    }
}

extension ConflictPolicy {
    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .replace: L10n.string(.conflictReplace, language: lang)
        case .skip: L10n.string(.conflictSkip, language: lang)
        case .rename: L10n.string(.conflictRename, language: lang)
        }
    }

    func detail(_ lang: AppLanguage) -> String {
        switch self {
        case .replace: L10n.string(.conflictReplaceDesc, language: lang)
        case .skip: L10n.string(.conflictSkipDesc, language: lang)
        case .rename: L10n.string(.conflictRenameDesc, language: lang)
        }
    }
}

extension TransferState {
    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .queued: L10n.string(.stateQueued, language: lang)
        case .transferring: L10n.string(.stateTransferring, language: lang)
        case .cancelling: L10n.string(.stateCancelling, language: lang)
        case .completed: L10n.string(.stateCompleted, language: lang)
        case .cancelled: L10n.string(.stateCancelled, language: lang)
        case .failed: L10n.string(.stateFailed, language: lang)
        }
    }
}

extension AppearancePreference {
    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .dark: L10n.string(.appearanceDark, language: lang)
        case .light: L10n.string(.appearanceLight, language: lang)
        case .system: L10n.string(.appearanceSystem, language: lang)
        }
    }
}

extension ByteFormatter {
    static func speedUnitSuffix(_ lang: AppLanguage) -> String {
        lang == .chinese ? "/秒" : "/s"
    }

    static func speedParts(_ bytesPerSecond: Double, language: AppLanguage) -> (magnitude: String, unit: String) {
        guard bytesPerSecond > 0 else { return ("—", "") }
        let base = parts(Int64(bytesPerSecond))
        let unit = base.unit.isEmpty
            ? speedUnitSuffix(language)
            : "\(base.unit)\(speedUnitSuffix(language))"
        return (base.magnitude, unit)
    }
}

extension DurationFormatter {
    static func string(_ seconds: TimeInterval, language: AppLanguage) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let secLabel = L10n.string(.unitSeconds, language: language)
        if seconds < 60 {
            if seconds < 10 {
                return String(format: language == .chinese ? "%.1f \(secLabel)" : "%.1f\(secLabel)", seconds)
            }
            return String(format: language == .chinese ? "%.0f \(secLabel)" : "%.0f\(secLabel)", seconds.rounded())
        }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
