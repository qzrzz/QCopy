import AppKit
import SwiftUI

@main
struct QCopyApp: App {
    @StateObject private var model = CopyViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(
                    minWidth: QCopyTheme.Layout.minWindowWidth,
                    minHeight: QCopyTheme.Layout.minWindowHeight
                )
        }
        .defaultSize(
            width: QCopyTheme.Layout.defaultWindowWidth,
            height: QCopyTheme.Layout.defaultWindowHeight
        )
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("选择来源…") {
                    model.chooseSource()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("选择目标…") {
                    model.chooseDestination()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button(model.isTransferring ? "取消当前任务" : "开始复制") {
                    if model.isTransferring {
                        model.cancelTransfer()
                    } else {
                        model.startTransfer()
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }

    }
}
