import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: CopyViewModel
    @State private var selectedSection: SidebarSection = .transfer
    @State private var isSourceDropTargeted = false
    @State private var isDestinationDropTargeted = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: QCopyTheme.Layout.sidebarWidth,
                    ideal: QCopyTheme.Layout.sidebarWidth,
                    max: QCopyTheme.Layout.sidebarWidth
                )
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if selectedSection == .transfer {
                    TransferModePicker()
                }
            }
            if selectedSection == .history {
                ToolbarItem(placement: .principal) {
                    Text("操作记录")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .overlay(alignment: .topLeading) {
            QCopyInitialFocusClearer()
                .frame(width: 0, height: 0)
        }
        .background(QCopyTheme.Colors.panelDimming)
        .background(
            QCopyVisualEffect(material: .hudWindow, blending: .behindWindow)
                .ignoresSafeArea()
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 8) {
                ForEach(SidebarSection.allCases) { section in
                    SidebarRow(
                        section: section,
                        isSelected: selectedSection == section,
                        badge: section == .history ? model.history.count : nil
                    ) {
                        withAnimation(.easeOut(duration: 0.16)) {
                            selectedSection = section
                        }
                    }
                }
            }

            Spacer(minLength: 18)
            appFooter
        }
        .padding(.top, 10)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            ZStack(alignment: .trailing) {
                QCopyVisualEffect(material: .sidebar, blending: .behindWindow)
                QCopyTheme.Colors.sidebarGlassTint
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        }
    }

    private var appFooter: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text("QCopy")
                    .font(QCopyTheme.Typography.brand)
                Text("v\(appVersion)")
                    .font(QCopyTheme.Typography.caption)
                    .foregroundStyle(QCopyTheme.Colors.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var detailPane: some View {
        Group {
            switch selectedSection {
            case .transfer:
                TransferWorkspaceView(
                    isSourceDropTargeted: $isSourceDropTargeted,
                    isDestinationDropTargeted: $isDestinationDropTargeted
                )
            case .history:
                HistoryView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        QCopyTheme.Colors.accent.opacity(0.055),
                        QCopyTheme.Colors.accentPurple.opacity(0.035),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                QCopyVisualEffect(material: .hudWindow, blending: .withinWindow)
                    .opacity(0.72)
            }
            .ignoresSafeArea()
        )
    }
}

enum SidebarSection: String, CaseIterable, Identifiable {
    case transfer
    case history

    var id: String { rawValue }
    var title: String { self == .transfer ? "复制 / 移动" : "操作记录" }
    var subtitle: String { self == .transfer ? "创建新的传输任务" : "查看已完成的任务" }
    var symbol: String { self == .transfer ? "arrow.triangle.2.circlepath" : "clock.arrow.circlepath" }
    var tint: Color { self == .transfer ? QCopyTheme.Colors.accent : QCopyTheme.Colors.accentPurple }
    var iconBackground: Color { self == .transfer ? QCopyTheme.Colors.accent.opacity(0.16) : QCopyTheme.Colors.accentPurple.opacity(0.16) }
}

private struct SidebarRow: View {
    let section: SidebarSection
    let isSelected: Bool
    let badge: Int?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(section.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular, design: .rounded))

                Spacer(minLength: 4)

                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? .primary.opacity(0.72) : QCopyTheme.Colors.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(QCopyTheme.Colors.selection, in: Capsule())
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: QCopyTheme.Radius.row, style: .continuous)
                        .fill(Color.clear)
                        .qcopyInteractiveGlass(in: RoundedRectangle(cornerRadius: QCopyTheme.Radius.row, style: .continuous))
                } else if isHovered {
                    RoundedRectangle(cornerRadius: QCopyTheme.Radius.row, style: .continuous)
                        .fill(QCopyTheme.Colors.rowHover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
