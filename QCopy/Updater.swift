import Combine
import Sparkle
import SwiftUI

/// 应用级 Sparkle 更新管理器（对齐 Qjiao）。
///
/// 单例持有更新生命周期；菜单「检查更新」与侧栏按钮共用此实例。
/// Feed URL 与公钥来自 Info.plist 的 `SUFeedURL` / `SUPublicEDKey`。
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    /// 正在检查时禁用菜单项，避免重复触发。
    @Published private(set) var canCheckForUpdates = false

    /// 是否按 Sparkle 计划自动检查。值由 Sparkle 持久化在 UserDefaults。
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    private init() {
        // Debug 不启动：避免后台检查与「是否自动检查」系统提示干扰开发。
        #if DEBUG
        let startImmediately = false
        #else
        let startImmediately = true
        #endif

        controller = SPUStandardUpdaterController(
            startingUpdater: startImmediately,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // didSet 在 init 赋值时不触发，手动从 Sparkle 种子。
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        // 启动 updater 只会武装「按间隔」调度（约一天一次）。
        // 若开启了自动检查，在启动后立即做一次静默后台检查。
        if startImmediately && automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    /// 用户可见的检查更新（进度窗与确认提示）。
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// 应用菜单中的「检查更新…」命令。
struct CheckForUpdatesView: View {
    @ObservedObject var updater: Updater
    let title: String

    var body: some View {
        Button(title) {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
