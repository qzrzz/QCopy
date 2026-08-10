import AppKit
import SwiftUI

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
        private static func adaptive(light: NSColor, dark: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
        }

        static let accent = Color(red: 0.22, green: 0.48, blue: 1.0)
        static let accentPurple = Color(red: 0.56, green: 0.35, blue: 1.0)
        static let accentCyan = Color(red: 0.12, green: 0.73, blue: 0.94)

        /// qf 主窗口使用的深色蒙层思路：让系统材质更有层次，同时保留背后的光线。
        static let panelDimming = adaptive(
            light: NSColor.white.withAlphaComponent(0.22),
            dark: NSColor.black.withAlphaComponent(0.34)
        )

        static let glassFrost = adaptive(
            light: NSColor.white.withAlphaComponent(0.22),
            dark: NSColor.white.withAlphaComponent(0.08)
        )

        static let sidebarGlassTint = adaptive(
            light: NSColor.white.withAlphaComponent(0.32),
            dark: NSColor.white.withAlphaComponent(0.055)
        )

        static let sidebarDivider = adaptive(
            light: NSColor.black.withAlphaComponent(0.08),
            dark: NSColor.white.withAlphaComponent(0.12)
        )

        static let selection = adaptive(
            light: NSColor.black.withAlphaComponent(0.075),
            dark: NSColor.white.withAlphaComponent(0.12)
        )

        static let rowHover = adaptive(
            light: NSColor.black.withAlphaComponent(0.04),
            dark: NSColor.white.withAlphaComponent(0.06)
        )

        static let cardFill = adaptive(
            light: NSColor.white.withAlphaComponent(0.10),
            dark: NSColor.white.withAlphaComponent(0.055)
        )

        static let cardStroke = adaptive(
            light: NSColor.black.withAlphaComponent(0.10),
            dark: NSColor.white.withAlphaComponent(0.13)
        )

        static let divider = adaptive(
            light: NSColor.black.withAlphaComponent(0.10),
            dark: NSColor.white.withAlphaComponent(0.13)
        )

        static let secondary = adaptive(
            light: NSColor.black.withAlphaComponent(0.54),
            dark: NSColor.white.withAlphaComponent(0.55)
        )

        static let tertiary = adaptive(
            light: NSColor.black.withAlphaComponent(0.38),
            dark: NSColor.white.withAlphaComponent(0.38)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(QCopyTheme.Typography.body.weight(.semibold))
            .foregroundStyle(QCopyTheme.Colors.accent)
            .padding(.horizontal, 17)
            .padding(.vertical, 10)
            .background(QCopyTheme.Colors.accent.opacity(0.10), in: Capsule())
            .glassEffect(
                .regular.interactive().tint(QCopyTheme.Colors.accent.opacity(0.14)),
                in: Capsule()
            )
            .shadow(color: QCopyTheme.Colors.accent.opacity(0.12), radius: 8, y: 3)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
