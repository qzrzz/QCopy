import AppKit
import Combine
import SwiftUI

/// 界面外观：黑夜 / 明亮 / 跟随系统。
enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light
    case system

    var id: String { rawValue }

    /// `nil` 表示跟随系统，由 AppKit / SwiftUI 自动解析。
    var nsAppearance: NSAppearance? {
        switch self {
        case .dark: NSAppearance(named: .darkAqua)
        case .light: NSAppearance(named: .aqua)
        case .system: nil
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

/// 持久化并应用外观偏好（同时驱动 SwiftUI 与 AppKit 材质）。
@MainActor
final class AppearanceSettings: ObservableObject {
    @Published var preference: AppearancePreference {
        didSet {
            guard oldValue != preference else { return }
            defaults.set(preference.rawValue, forKey: StorageKey.appearance)
            apply()
        }
    }

    private let defaults = UserDefaults.standard

    private enum StorageKey {
        static let appearance = "qcopy.appearancePreference"
    }

    init() {
        if let raw = defaults.string(forKey: StorageKey.appearance),
           let saved = AppearancePreference(rawValue: raw) {
            preference = saved
        } else {
            preference = .system
        }
        apply()
    }

    func apply() {
        let appearance = preference.nsAppearance
        NSApp.appearance = appearance
        // 已打开窗口也同步，避免动态色仍按旧外观解析成浅色黑字。
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }
}

/// QCopy 的 Liquid Glass 视觉系统。
///
/// 窗口底层使用 AppKit 的 Vibrancy 材质，卡片和交互控件使用 macOS 26
/// 原生 `glassEffect`。两者叠加后，侧边栏、内容区和悬浮控件会保持同一块
/// 连续的玻璃表面，而不是一组互相割裂的半透明色块。
enum QCopyTheme {
    enum Layout {
        static let sidebarWidth: CGFloat = 168
        static let titlebarClearance: CGFloat = 0
        static let contentInset: CGFloat = 16
        static let minWindowWidth: CGFloat = 680
        static let minWindowHeight: CGFloat = 400
        static let defaultWindowWidth: CGFloat = 760
        static let defaultWindowHeight: CGFloat = 450
        static let pathCardHeight: CGFloat = 76
        static let pathIconSize: CGFloat = 38
        static let pathIconGlyph: CGFloat = 22
    }

    enum Spacing {
        static let xs: CGFloat = 5
        static let sm: CGFloat = 9
        static let md: CGFloat = 13
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 30
    }

    enum Radius {
        static let panel: CGFloat = 24
        static let card: CGFloat = 18
        static let row: CGFloat = 12
        static let pill: CGFloat = 999
    }

    enum Colors {
        /// 按当前绘制外观在 light / dark 间切换；兼容菜单强制的 `NSApp.appearance`。
        private static func adaptive(light: NSColor, dark: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
                isDarkAppearance(appearance) ? dark : light
            }))
        }

        private static func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
            let matched = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
            if matched == .darkAqua || matched == .vibrantDark {
                return true
            }
            // 部分材质外观名称不含 aqua，用 rawValue 兜底，避免误用浅色（黑字压在深色底上）。
            let name = appearance.name.rawValue.lowercased()
            return name.contains("dark")
        }

        /// 主强调色：深色模式下提高明度，避免压在玻璃底上发闷。
        static let accent = adaptive(
            light: NSColor(srgbRed: 0.22, green: 0.48, blue: 1.0, alpha: 1),
            dark: NSColor(srgbRed: 0.58, green: 0.76, blue: 1.0, alpha: 1)
        )

        /// 图标强调色（比正文 accent 再亮一档，专用于 SF Symbol）。
        static let iconAccent = adaptive(
            light: NSColor(srgbRed: 0.18, green: 0.45, blue: 0.98, alpha: 1),
            dark: NSColor(srgbRed: 0.72, green: 0.84, blue: 1.0, alpha: 1)
        )

        /// 按当前 SwiftUI `colorScheme` 取图标色，避免动态 NSColor 在 popover 里误判为浅色。
        static func iconAccent(for scheme: ColorScheme) -> Color {
            switch scheme {
            case .dark:
                Color(red: 0.72, green: 0.84, blue: 1.0)
            default:
                Color(red: 0.18, green: 0.45, blue: 0.98)
            }
        }
        /// 「目标」等标签色：深色模式用更亮的紫，保证可读性。
        static let accentPurple = adaptive(
            light: NSColor(srgbRed: 0.56, green: 0.35, blue: 1.0, alpha: 1),
            dark: NSColor(srgbRed: 0.78, green: 0.62, blue: 1.0, alpha: 1)
        )
        static let accentCyan = adaptive(
            light: NSColor(srgbRed: 0.12, green: 0.73, blue: 0.94, alpha: 1),
            dark: NSColor(srgbRed: 0.40, green: 0.88, blue: 1.0, alpha: 1)
        )

        /// 主文案：深色模式下用高不透明白，避免在玻璃底上发灰发暗。
        static let primaryText = adaptive(
            light: NSColor.black.withAlphaComponent(0.88),
            dark: NSColor.white.withAlphaComponent(0.94)
        )

        /// qf 主窗口使用的深色蒙层思路：让系统材质更有层次，同时保留背后的光线。
        static let panelDimming = adaptive(
            light: NSColor.white.withAlphaComponent(0.22),
            dark: NSColor.black.withAlphaComponent(0.16)
        )

        static let glassFrost = adaptive(
            light: NSColor.white.withAlphaComponent(0.22),
            dark: NSColor.white.withAlphaComponent(0.10)
        )

        /// 侧栏提亮叠层：比右侧内容区更浅一档，仍保持同一材质语言。
        static let sidebarGlassTint = adaptive(
            light: NSColor.white.withAlphaComponent(0.1),
            dark: NSColor.white.withAlphaComponent(0.14)
        )

        static let sidebarDivider = adaptive(
            light: NSColor.black.withAlphaComponent(0.08),
            dark: NSColor.white.withAlphaComponent(0.16)
        )

        static let selection = adaptive(
            light: NSColor.black.withAlphaComponent(0.075),
            dark: NSColor.white.withAlphaComponent(0.14)
        )

        static let rowHover = adaptive(
            light: NSColor.black.withAlphaComponent(0.04),
            dark: NSColor.white.withAlphaComponent(0.08)
        )

        static let cardFill = adaptive(
            light: NSColor.white.withAlphaComponent(0.10),
            dark: NSColor.white.withAlphaComponent(0.07)
        )

        static let cardStroke = adaptive(
            light: NSColor.black.withAlphaComponent(0.10),
            dark: NSColor.white.withAlphaComponent(0.18)
        )

        static let divider = adaptive(
            light: NSColor.black.withAlphaComponent(0.10),
            dark: NSColor.white.withAlphaComponent(0.18)
        )

        /// 底栏 / chrome 描边：比系统 separator 更轻，避免压在玻璃上过重。
        static let chromeSeparator = adaptive(
            light: NSColor.black.withAlphaComponent(0.06),
            dark: NSColor.white.withAlphaComponent(0.10)
        )

        /// 次要文案：深色模式提高到约 78% 白，保证玻璃背景上的可读性。
        static let secondary = adaptive(
            light: NSColor.black.withAlphaComponent(0.54),
            dark: NSColor.white.withAlphaComponent(0.78)
        )

        /// 辅助/路径等更淡一级，但仍明显高于旧版 0.38。
        static let tertiary = adaptive(
            light: NSColor.black.withAlphaComponent(0.38),
            dark: NSColor.white.withAlphaComponent(0.60)
        )
    }

    enum Typography {
        /// Pally Bold（PostScript 名：Pally-Bold）
        static let brand = Font.custom("Pally-Bold", size: 16)
        static let eyebrow = Font.system(size: 11, weight: .semibold, design: .rounded)
        static let display = Font.system(size: 24, weight: .bold, design: .rounded)
        static let title = Font.system(size: 14, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 13, weight: .regular, design: .rounded)
        static let caption = Font.system(size: 11, weight: .medium, design: .rounded)
    }
}

/// 原生 AppKit Vibrancy 背景。macOS 26 会将这些材质渲染为系统 Liquid Glass。
struct QCopyVisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
        nsView.state = .active
    }
}

/// 右侧底部 chrome 条：透明玻璃模糊 + 极轻描边。
/// - Parameter separatorOnTop: `true` 用于底栏（线在上方），`false` 用于顶栏模拟（线在下方）。
struct QCopyChromeBarBackground: View {
    var separatorOnTop: Bool = true

    var body: some View {
        ZStack {
            // withinWindow：内容滚过时透出并做毛玻璃；hudWindow 比 titlebar 更通透。
            QCopyVisualEffect(material: .hudWindow, blending: .withinWindow)
                .opacity(0.55)
            // SwiftUI 超薄材质叠一层，增强模糊、降低实色感
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.55)
                .allowsHitTesting(false)
            // 极轻 frost，避免糊成灰块
            QCopyTheme.Colors.glassFrost
                .opacity(0.08)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                if separatorOnTop {
                    Rectangle()
                        .fill(QCopyTheme.Colors.chromeSeparator)
                        .frame(height: 0.5)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(QCopyTheme.Colors.chromeSeparator)
                        .frame(height: 0.5)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// SwiftUI 的 macOS 工具栏会在默认焦点评估结束后再次设置 first responder。
/// 这里仅在窗口第一次成为 key window 时清空一次，不改变任何控件后续的焦点能力。
struct QCopyInitialFocusClearer: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    @MainActor
    final class Coordinator: @unchecked Sendable {
        private var observer: NSObjectProtocol?
        private weak var observedWindow: NSWindow?
        private var didClearInitialFocus = false

        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let window = view?.window else { return }
                guard self.observedWindow !== window else { return }

                self.stopObserving()
                self.observedWindow = window

                if window.isKeyWindow {
                    self.clearInitialFocus(in: window)
                } else {
                    self.observer = NotificationCenter.default.addObserver(
                        forName: NSWindow.didBecomeKeyNotification,
                        object: window,
                        queue: .main
                    ) { [weak self, weak window] _ in
                        guard let self, let window else { return }
                        Task { @MainActor in
                            self.clearInitialFocus(in: window)
                        }
                    }
                }
            }
        }

        func stopObserving() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
        }

        private func clearInitialFocus(in window: NSWindow) {
            guard !didClearInitialFocus else { return }
            didClearInitialFocus = true
            stopObserving()

            // 延后到工具栏完成自己的焦点写入之后再清空。
            DispatchQueue.main.async { [weak window] in
                DispatchQueue.main.async { [weak window] in
                    window?.makeFirstResponder(nil)
                }
            }
        }
    }
}

extension View {
    /// 静态玻璃表面：内容卡片、空状态和状态面板。
    func qcopyGlass<S: Shape>(in shape: S = RoundedRectangle(cornerRadius: QCopyTheme.Radius.card, style: .continuous)) -> some View {
        glassEffect(.regular.tint(QCopyTheme.Colors.glassFrost), in: shape)
    }

    /// 交互玻璃表面：侧边栏入口、路径选择卡和按钮。
    func qcopyInteractiveGlass<S: Shape>(in shape: S = RoundedRectangle(cornerRadius: QCopyTheme.Radius.card, style: .continuous)) -> some View {
        glassEffect(.regular.interactive().tint(QCopyTheme.Colors.glassFrost), in: shape)
    }
}

struct QCopyIcon: View {
    let symbol: String
    var color: Color = QCopyTheme.Colors.accent
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size + 14, height: size + 14)
    }
}

struct QCopyPill: View {
    let text: String
    var color: Color = QCopyTheme.Colors.secondary

    var body: some View {
        Text(text)
            .font(QCopyTheme.Typography.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(QCopyTheme.Colors.selection, in: Capsule())
    }
}

struct QCopyButtonStyle: ButtonStyle {
    var tint: Color = QCopyTheme.Colors.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QCopyTheme.Typography.body.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(tint.opacity(configuration.isPressed ? 0.18 : 0.10), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.20), lineWidth: 0.7))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct QCopyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let isDark = colorScheme == .dark
        // 深色：白字 + 实心蓝底，避免「浅蓝字压浅蓝玻璃」对比不足。
        let fill = isDark
            ? Color(red: 0.28, green: 0.52, blue: 1.0)
            : QCopyTheme.Colors.accent
        let label = isDark ? Color.white : Color.white

        return configuration.label
            .font(QCopyTheme.Typography.body.weight(.semibold))
            .foregroundStyle(label)
            .padding(.horizontal, 17)
            .padding(.vertical, 10)
            .background(fill.opacity(configuration.isPressed ? 0.88 : 1), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isDark
                            ? Color.white.opacity(0.22)
                            : QCopyTheme.Colors.accent.opacity(0.25),
                        lineWidth: 0.8
                    )
            )
            .shadow(
                color: fill.opacity(isDark ? 0.45 : 0.22),
                radius: isDark ? 10 : 8,
                y: 3
            )
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
