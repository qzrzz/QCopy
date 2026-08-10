import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TransferWorkspaceView: View {
    @EnvironmentObject private var model: CopyViewModel
    @Binding var isSourceDropTargeted: Bool
    @Binding var isDestinationDropTargeted: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                PrototypeTransferPanel(
                    isSourceDropTargeted: $isSourceDropTargeted,
                    isDestinationDropTargeted: $isDestinationDropTargeted
                )
            }
            .padding(.horizontal, QCopyTheme.Layout.contentInset)
            .padding(.top, 8)
            .padding(.bottom, 18)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pinnedFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pinnedFooter: some View {
        Group {
            if model.activeJob != nil {
                ActiveTransferCard()
            } else {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        model.startTransfer()
                    } label: {
                        Text(model.transferMode == .copy ? "开始复制" : "开始移动")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(QCopyPrimaryButtonStyle())
                    .disabled(!model.hasReadyTransfer)
                    .opacity(model.hasReadyTransfer ? 1 : 0.45)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(.horizontal, QCopyTheme.Layout.contentInset)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .background {
            ZStack {
                QCopyVisualEffect(material: .headerView, blending: .behindWindow)
                    .opacity(0.1)
                QCopyTheme.Colors.panelDimming.opacity(0.28)
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(QCopyTheme.Colors.divider)
                        .frame(height: 0.6)
                    Spacer(minLength: 0)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

}

struct TransferModePicker: View {
    @EnvironmentObject private var model: CopyViewModel

    var body: some View {
        Picker("传输方式", selection: $model.transferMode) {
            ForEach(TransferMode.allCases) { mode in
                Label(mode.title, systemImage: mode.symbol)
                    .labelStyle(.titleAndIcon)
                    .tag(mode)
                    .padding(.horizontal, 8)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 4)
        .controlSize(.large)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("复制或移动")
    }
}

private struct PrototypeTransferPanel: View {
    @EnvironmentObject private var model: CopyViewModel
    @Binding var isSourceDropTargeted: Bool
    @Binding var isDestinationDropTargeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                PathCard(
                    role: .source,
                    url: model.sourceURL,
                    isDropTargeted: $isSourceDropTargeted,
                    onChoose: model.chooseSource,
                    onDropURL: { model.setSource(from: [$0]) }
                )

                Image(systemName: "arrow.right")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 30)

                PathCard(
                    role: .destination,
                    url: model.destinationURL,
                    isDropTargeted: $isDestinationDropTargeted,
                    onChoose: model.chooseDestination,
                    onDropURL: { model.setDestination(from: [$0]) }
                )
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("冲突处理")
                    .font(QCopyTheme.Typography.body.weight(.semibold))
                ConflictPolicySelector()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .qcopyGlass(in: RoundedRectangle(cornerRadius: QCopyTheme.Radius.panel, style: .continuous))
    }
}

private struct ConflictPolicySelector: View {
    @EnvironmentObject private var model: CopyViewModel
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: model.conflictPolicy.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(QCopyTheme.Colors.accent)
                    .frame(width: 20)

                Text(model.conflictPolicy.title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 16)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(QCopyTheme.Colors.secondary)
                    .rotationEffect(.degrees(isPresented ? 180 : 0))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .frame(width: 280, height: 48, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .qcopyInteractiveGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 4) {
                ForEach(ConflictPolicy.allCases) { policy in
                    Button {
                        model.conflictPolicy = policy
                        isPresented = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: policy.symbol)
                                .foregroundStyle(QCopyTheme.Colors.accent)
                                .frame(width: 20)
                            Text(policy.title)
                            Spacer(minLength: 20)
                            if model.conflictPolicy == policy {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(QCopyTheme.Colors.accent)
                            }
                        }
                        .font(QCopyTheme.Typography.body)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(width: 250, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(QCopyVisualEffect(material: .popover, blending: .behindWindow))
        }
        .animation(.easeOut(duration: 0.16), value: isPresented)
    }
}

private struct GlassSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(QCopyTheme.Typography.title)
            Spacer(minLength: 10)
            Text(subtitle)
                .font(QCopyTheme.Typography.caption)
                .foregroundStyle(QCopyTheme.Colors.tertiary)
        }
    }
}

struct SourceDestinationPanel: View {
    @EnvironmentObject private var model: CopyViewModel
    @Binding var isSourceDropTargeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            GlassSectionHeader(title: "传输路径", subtitle: "拖入来源，或点击选择")

            HStack(spacing: 9) {
                PathCard(
                    role: .source,
                    url: model.sourceURL,
                    isDropTargeted: $isSourceDropTargeted,
                    onChoose: model.chooseSource,
                    onDropURL: { model.setSource(from: [$0]) }
                )

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(QCopyTheme.Colors.secondary)
                    .frame(width: 20)

                PathCard(
                    role: .destination,
                    url: model.destinationURL,
                    isDropTargeted: .constant(false),
                    onChoose: model.chooseDestination,
                    onDropURL: nil
                )
            }
        }
        .padding(17)
        .qcopyGlass(in: RoundedRectangle(cornerRadius: QCopyTheme.Radius.card, style: .continuous))
    }
}

enum PathCardRole {
    case source
    case destination

    var title: String { self == .source ? "来源" : "目标" }
    var symbol: String { self == .source ? "folder" : "folder.badge.arrow.down" }
    var accent: Color { self == .source ? QCopyTheme.Colors.accentCyan : QCopyTheme.Colors.accentPurple }
    var helper: String { self == .source ? "拖入文件或文件夹" : "选择目标文件夹" }
}

struct PathCard: View {
    let role: PathCardRole
    let url: URL?
    @Binding var isDropTargeted: Bool
    let onChoose: () -> Void
    let onDropURL: ((URL) -> Void)?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: QCopyTheme.Radius.row, style: .continuous)
    }

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: 11) {
                if let url {
                    FileIcon(url: url, tint: role.accent)
                } else {
                    PlaceholderIcon(symbol: role.symbol, tint: role.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(role.title)
                        .font(QCopyTheme.Typography.caption)
                        .foregroundStyle(role.accent)
                    Text(displayName)
                        .font(QCopyTheme.Typography.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(url?.path ?? role.helper)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(QCopyTheme.Colors.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 3)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(QCopyTheme.Colors.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: QCopyTheme.Layout.pathCardHeight, alignment: .leading)
            .background {
                if isDropTargeted {
                    shape.fill(role.accent.opacity(0.14))
                }
            }
            .overlay {
                shape.stroke(
                    isDropTargeted ? role.accent.opacity(0.75) : QCopyTheme.Colors.cardStroke,
                    lineWidth: isDropTargeted ? 1.2 : 0.7
                )
            }
        }
        .buttonStyle(.plain)
        .qcopyInteractiveGlass(in: shape)
        .frame(maxWidth: .infinity)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            guard onDropURL != nil else { return false }
            loadURL(from: providers)
            return true
        }
        .animation(.easeOut(duration: 0.16), value: isDropTargeted)
    }

    private var displayName: String {
        guard let url else { return "请选择位置" }
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    private func loadURL(from providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let item = item as? URL {
                url = item
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let item = item as? NSURL {
                url = item as URL
            } else {
                url = nil
            }
            guard let url else { return }
            Task { @MainActor in onDropURL?(url) }
        }
    }
}

struct FileIcon: View {
    let url: URL
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.14))
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: QCopyTheme.Layout.pathIconGlyph, height: QCopyTheme.Layout.pathIconGlyph)
        }
        .frame(width: QCopyTheme.Layout.pathIconSize, height: QCopyTheme.Layout.pathIconSize)
    }
}

struct PlaceholderIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.14))
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: QCopyTheme.Layout.pathIconSize, height: QCopyTheme.Layout.pathIconSize)
    }
}

private struct TransferModeCard: View {
    @EnvironmentObject private var model: CopyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(title: "操作方式", subtitle: "保留或移除原文件")

            VStack(spacing: 4) {
                ForEach(TransferMode.allCases) { mode in
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) { model.transferMode = mode }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(mode == .copy ? QCopyTheme.Colors.accentCyan : QCopyTheme.Colors.accentPurple)
                                .frame(width: 25)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                    .font(QCopyTheme.Typography.body.weight(.semibold))
                                Text(mode.description)
                                    .font(QCopyTheme.Typography.caption)
                                    .foregroundStyle(QCopyTheme.Colors.secondary)
                            }

                            Spacer(minLength: 4)
                            if model.transferMode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(QCopyTheme.Colors.accent)
                            }
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            if model.transferMode == mode {
                                RoundedRectangle(cornerRadius: QCopyTheme.Radius.row - 3, style: .continuous)
                                    .fill(QCopyTheme.Colors.selection)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .qcopyGlass(in: RoundedRectangle(cornerRadius: QCopyTheme.Radius.card, style: .continuous))
    }
}

private struct ConflictPolicyCard: View {
    @EnvironmentObject private var model: CopyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(title: "冲突处理", subtitle: "目标存在同名文件时")

            VStack(spacing: 4) {
                ForEach(ConflictPolicy.allCases) { policy in
                    Button {
                        model.conflictPolicy = policy
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: policy.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(QCopyTheme.Colors.accent)
                                .frame(width: 25)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(policy.title)
                                    .font(QCopyTheme.Typography.body.weight(.semibold))
                                Text(description(for: policy))
                                    .font(QCopyTheme.Typography.caption)
                                    .foregroundStyle(QCopyTheme.Colors.secondary)
                            }

                            Spacer(minLength: 4)
                            if model.conflictPolicy == policy {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(QCopyTheme.Colors.accent)
                            }
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            if model.conflictPolicy == policy {
                                RoundedRectangle(cornerRadius: QCopyTheme.Radius.row - 3, style: .continuous)
                                    .fill(QCopyTheme.Colors.selection)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .qcopyGlass(in: RoundedRectangle(cornerRadius: QCopyTheme.Radius.card, style: .continuous))
    }

    private func description(for policy: ConflictPolicy) -> String {
        switch policy {
        case .replace: "直接覆盖目标中的同名文件"
        case .skip: "保留目标文件，跳过这一项"
        case .rename: "为新文件添加序号后缀"
        }
    }
}

struct StartTransferBar: View {
    @EnvironmentObject private var model: CopyViewModel

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(QCopyTheme.Colors.accent.opacity(0.14))
                Image(systemName: model.transferMode.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(QCopyTheme.Colors.accent)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.transferMode == .copy ? "准备复制" : "准备移动")
                    .font(QCopyTheme.Typography.title)
                Text(model.hasReadyTransfer ? "⌘↩ 开始传输" : "请选择来源和目标后继续")
                    .font(QCopyTheme.Typography.caption)
                    .foregroundStyle(QCopyTheme.Colors.secondary)
            }

            Spacer(minLength: 10)

            Button {
                model.startTransfer()
            } label: {
                HStack(spacing: 7) {
                    Text(model.transferMode == .copy ? "开始复制" : "开始移动")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(QCopyPrimaryButtonStyle())
            .disabled(!model.hasReadyTransfer)
            .opacity(model.hasReadyTransfer ? 1 : 0.45)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(16)
        .qcopyGlass(in: RoundedRectangle(cornerRadius: QCopyTheme.Radius.card, style: .continuous))
    }
}

struct ActiveTransferCard: View {
    @EnvironmentObject private var model: CopyViewModel

    var body: some View {
        if let job = model.activeJob {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: symbol(for: job.state))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color(for: job.state))
                    Text(job.state.title)
                        .font(QCopyTheme.Typography.title)
                    Spacer()
                    if job.state == .transferring {
                        Button("取消") { model.cancelTransfer() }
                            .buttonStyle(QCopyButtonStyle(tint: .orange))
                    } else if job.state == .cancelling {
                        Text("正在安全停止…")
                            .font(QCopyTheme.Typography.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Button("收起") { model.clearFinishedJob() }
                            .buttonStyle(QCopyButtonStyle(tint: QCopyTheme.Colors.secondary))
                    }
                }

                Text(job.currentFile)
                    .font(QCopyTheme.Typography.body)
                    .foregroundStyle(QCopyTheme.Colors.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                ProgressTrack(
                    progress: job.progress,
                    isActive: job.state == .transferring || job.state == .cancelling,
                    tint: color(for: job.state)
                )

                HStack(spacing: 14) {
                    TransferStat(title: "已传输", value: ByteFormatter.string(job.bytesCopied))
                    TransferStat(title: "已处理", value: "\(job.filesCopied) 项")
                    TransferStat(title: "速度", value: ByteFormatter.speed(job.speedBytesPerSecond))
                    if job.filesSkipped > 0 {
                        TransferStat(title: "已跳过", value: "\(job.filesSkipped) 项")
                    }
                }

                if case .failed(let message) = job.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(QCopyTheme.Typography.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(17)
            .qcopyGlass(in: RoundedRectangle(cornerRadius: QCopyTheme.Radius.card, style: .continuous))
        }
    }

    private func symbol(for state: TransferState) -> String {
        switch state {
        case .transferring: "arrow.up.forward.circle"
        case .cancelling: "stop.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "pause.circle.fill"
        case .failed: "xmark.circle.fill"
        case .queued: "clock"
        }
    }

    private func color(for state: TransferState) -> Color {
        switch state {
        case .completed: .green
        case .cancelling, .cancelled: .orange
        case .failed: .red
        default: QCopyTheme.Colors.accent
        }
    }
}

struct ProgressTrack: View {
    let progress: Double
    let isActive: Bool
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(QCopyTheme.Colors.selection)
                Capsule()
                    .fill(tint)
                    .frame(width: max(proxy.size.width * progress, isActive ? 30 : 0))
                    .animation(.easeOut(duration: 0.2), value: progress)
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
    }
}

struct TransferStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(QCopyTheme.Typography.caption)
                .foregroundStyle(QCopyTheme.Colors.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
