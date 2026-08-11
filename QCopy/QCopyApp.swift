import AppKit
import SwiftUI

@main
struct QCopyApp: App {
    @StateObject private var model = CopyViewModel()
    @StateObject private var appearance = AppearanceSettings()
    @StateObject private var language = LanguageSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(appearance)
                .environmentObject(language)
                .preferredColorScheme(appearance.preference.colorScheme)
                .environment(\.locale, language.language.locale)
                // 语言切换时强制重建界面
                .id(language.preference)
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
                Button(language.t(.chooseSourceMenu)) {
                    model.chooseSource(language: language.language)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button(language.t(.chooseDestinationMenu)) {
                    model.chooseDestination(language: language.language)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button(
                    model.isTransferring
                        ? language.t(.cancelCurrentTask)
                        : language.t(.startCopyMenu)
                ) {
                    if model.isTransferring {
                        model.cancelTransfer()
                    } else {
                        model.startTransfer(language: language.language)
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
            }

            CommandMenu(language.t(.appearanceMenu)) {
                Picker(language.t(.appearanceSection), selection: $appearance.preference) {
                    Text(AppearancePreference.dark.title(language.language))
                        .tag(AppearancePreference.dark)
                    Text(AppearancePreference.light.title(language.language))
                        .tag(AppearancePreference.light)
                    Text(AppearancePreference.system.title(language.language))
                        .tag(AppearancePreference.system)
                }
                .pickerStyle(.inline)

                Divider()

                Picker(language.t(.languageSection), selection: $language.preference) {
                    ForEach(LanguagePreference.allCases) { option in
                        Text(option.menuTitle).tag(option)
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }
}
