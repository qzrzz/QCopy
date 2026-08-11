import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

struct TransferWorkspaceView: View {
    @EnvironmentObject private var model: CopyViewModel
    @EnvironmentObject private var language: LanguageSettings
    @Binding var isSourceDropTargeted: Bool
    @Binding var isDestinationDropTargeted: Bool

    var body: some View {
        // 用 VStack 钉住底栏，避免 ScrollView + safeAreaInset 在矮窗口底部留透明空隙。
        VStack(spacing: 0) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                        model.startTransfer(language: language.language)
                    } label: {
                        Text(
                            model.transferMode == .copy
                                ? language.t(.startCopy)
                                : language.t(.startMove)
                        )
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
        .frame(maxWidth: .infinity)
        .background {
            QCopyChromeBarBackground(separatorOnTop: true)
                .ignoresSafeArea(edges: .bottom)
        }
    }

}

struct TransferModePicker: View {
    @EnvironmentObject private var model: CopyViewModel
    @EnvironmentObject private var language: LanguageSettings

    var body: some View {
        Picker(language.t(.transferModePicker), selection: $model.transferMode) {
            ForEach(TransferMode.allCases) { mode in
                Label(mode.title(language.language), systemImage: mode.symbol)
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
        .accessibilityLabel(language.t(.transferModeA11y))
    }
}

private struct PrototypeTransferPanel: View {
    @EnvironmentObject private var model: CopyViewModel
    @EnvironmentObject private var language: LanguageSettings
    @Binding var isSourceDropTargeted: Bool
    @Binding var isDestinationDropTargeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                PathCard(
                    role: .source,
                    url: model.sourceURL,
                    recentPaths: model.recentSources,
                    isDropTargeted: $isSourceDropTargeted,
                    onChoose: { model.chooseSource(language: language.language) },
                    onSelectRecent: model.selectRecentSource,
                    onDropURL: { model.setSource(from: [$0]) }
                )

                Image(systemName: "arrow.right")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(QCopyTheme.Colors.primaryText)
                    .frame(width: 30)

                PathCard(
                    role: .destination,
                    url: model.destinationURL,
                    recentPaths: model.recentDestinations,
                    isDropTargeted: $isDestinationDropTargeted,
                    onChoose: { model.chooseDestination(language: language.language) },
                    onSelectRecent: model.selectRecentDestination,
                    onDropURL: { model.setDestination(from: [$0]) }
                )
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(language.t(.conflictSection))
                    .font(QCopyTheme.Typography.body.weight(.semibold))
                ConflictPolicySelector()
                SmartParallelToggle()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .qcopyGlass(in: RoundedRectangle(cornerRadius: QCopyTheme.Radius.panel, style: .continuous))
    }
}

private struct ConflictPolicySelector: View {
    @EnvironmentObject private var model: CopyViewModel
    @EnvironmentObject private var language: LanguageSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPresented = false

    private var iconColor: Color {
        QCopyTheme.Colors.iconAccent(for: colorScheme)
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: model.conflictPolicy.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                Text(model.conflictPolicy.title(language.language))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 16)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(iconColor.opacity(0.85))
                    .rotationEffect(.degrees(isPresented ? 180 : 0))
            }
            .foregroundStyle(QCopyTheme.Colors.primaryText)
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
                                .symbolRenderingMode(.monochrome)
                                .foregroundStyle(iconColor)
                                .frame(width: 20)
                            Text(policy.title(language.language))
                            Spacer(minLength: 20)
                            if model.conflictPolicy == policy {
                                Image(systemName: "checkmark")
                                    .symbolRenderingMode(.monochrome)
                                    .foregroundStyle(iconColor)
                            }
                        }
                        .font(QCopyTheme.Typography.body)
                        .foregroundStyle(QCopyTheme.Colors.primaryText)
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

private struct SmartParallelToggle: View {
    @EnvironmentObject private var model: CopyViewModel
    @EnvironmentObject private var language: LanguageSettings

    var body: some View {
        Toggle(isOn: $model.smartParallel) {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.t(.smartParallel))
                    .font(QCopyTheme.Typography.body.weight(.medium))
            }
        }
        .toggleStyle(.switch)
        .tint(QCopyTheme.Colors.accent)
        .padding(5)
        .padding(.top, 8 )
        .frame(width: 280, alignment: .leading)
 
       
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
    @EnvironmentObject private var language: LanguageSettings
    @EnvironmentObject private var model: CopyViewModel
    @Binding var isSourceDropTargeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            GlassSectionHeader(title: language.t(.transferPaths), subtitle: language.t(.dropOrClick))

            HStack(spacing: 9) {
                PathCard(
                    role: .source,
                    url: model.sourceURL,
                    recentPaths: model.recentSources,
                    isDropTargeted: $isSourceDropTargeted,
                    onChoose: { model.chooseSource(language: language.language) },
                    onSelectRecent: model.selectRecentSource,
                    onDropURL: { model.setSource(from: [$0]) }
                )

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(QCopyTheme.Colors.secondary)
                    .frame(width: 20)

                PathCard(
                    role: .destination,
                    url: model.destinationURL,
                    recentPaths: model.recentDestinations,
                    isDropTargeted: .constant(false),
                    onChoose: { model.chooseDestination(language: language.language) },
                    onSelectRecent: model.selectRecentDestination,
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

    var symbol: String { self == .source ? "folder" : "folder.badge.arrow.down" }
    var accent: Color { self == .source ? QCopyTheme.Colors.accentCyan : QCopyTheme.Colors.accentPurple }

    func title(_ lang: AppLanguage) -> String {
        L10n.string(self == .source ? .pathSource : .pathDestination, language: lang)
    }

    func helper(_ lang: AppLanguage) -> String {
        L10n.string(self == .source ? .pathSourceHelper : .pathDestinationHelper, language: lang)
    }
}

struct PathCard: View {
    @EnvironmentObject private var language: LanguageSettings
    let role: PathCardRole
    let url: URL?
    var recentPaths: [RecentPathEntry] = []
    @Binding var isDropTargeted: Bool
    let onChoose: () -> Void
    var onSelectRecent: ((RecentPathEntry) -> Void)?
    let onDropURL: ((URL) -> Void)?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: QCopyTheme.Radius.row, style: .continuous)
    }

    private var usableRecent: [RecentPathEntry] {
        recentPaths.filter { $0.exists && $0.path != url?.standardizedFileURL.path }
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onChoose) {
                HStack(spacing: 11) {
                    if let url {
                        FileIcon(url: url, tint: role.accent)
                    } else {
                        PlaceholderIcon(symbol: role.symbol, tint: role.accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(role.title(language.language))
                            .font(QCopyTheme.Typography.caption)
                            .foregroundStyle(role.accent)
                        Text(displayName)
                            .font(QCopyTheme.Typography.title)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(url?.path ?? role.helper(language.language))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(QCopyTheme.Colors.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 3)
                }
                .padding(.leading, 12)
                .padding(.trailing, 4)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: QCopyTheme.Layout.pathCardHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button(language.t(.browse), action: onChoose)
                if !usableRecent.isEmpty {
                    Divider()
                    Section(language.t(.recentUsed)) {
                        ForEach(usableRecent.prefix(10)) { entry in
                            Button {
                                onSelectRecent?(entry)
                            } label: {
                                Label {
                                    VStack(alignment: .leading) {
                                        Text(entry.displayName)
                                        Text(entry.path)
                                            .font(.caption)
                                    }
                                } icon: {
                                    Image(systemName: role.symbol)
                                }
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(usableRecent.isEmpty ? QCopyTheme.Colors.tertiary : role.accent)
                    .frame(width: 36, height: QCopyTheme.Layout.pathCardHeight)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(usableRecent.isEmpty ? language.t(.browseOrChoosePath) : language.t(.recentPaths))
            .padding(.trailing, 4)
        }
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
        guard let url else { return language.t(.pleaseChooseLocation) }
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
    @EnvironmentObject private var language: LanguageSettings
    @EnvironmentObject private var model: CopyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(title: language.t(.operationMethod), subtitle: language.t(.keepOrRemove))

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
                                Text(mode.title(language.language))
                                    .font(QCopyTheme.Typography.body.weight(.semibold))
                                Text(mode.description(language.language))
                                    .font(QCopyTheme.Typography.caption)
                                    .foregroundStyle(QCopyTheme.Colors.secondary)
                            }

                            Spacer(minLength: 4)
                            if model.transferMode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(QCopyTheme.Colors.accent)
                            }
                        }
                        .foregroundStyle(QCopyTheme.Colors.primaryText)
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
    @EnvironmentObject private var language: LanguageSettings
    @EnvironmentObject private var model: CopyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionHeader(title: language.t(.conflictSection), subtitle: language.t(.conflictWhenExists))

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
                                Text(policy.title(language.language))
                                    .font(QCopyTheme.Typography.body.weight(.semibold))
                                Text(policy.detail(language.language))
                                    .font(QCopyTheme.Typography.caption)
                                    .foregroundStyle(QCopyTheme.Colors.secondary)
                            }

                            Spacer(minLength: 4)
                            if model.conflictPolicy == policy {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(QCopyTheme.Colors.accent)
                            }
                        }
                        .foregroundStyle(QCopyTheme.Colors.primaryText)
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

}

struct StartTransferBar: View {
    @EnvironmentObject private var language: LanguageSettings
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
                Text(model.transferMode == .copy ? language.t(.readyCopy) : language.t(.readyMove))
                    .font(QCopyTheme.Typography.title)
                Text(model.hasReadyTransfer ? language.t(.startHint) : language.t(.needPathsHint))
                    .font(QCopyTheme.Typography.caption)
                    .foregroundStyle(QCopyTheme.Colors.secondary)
            }

            Spacer(minLength: 10)

            Button {
                model.startTransfer(language: language.language)
            } label: {
                HStack(spacing: 7) {
                    Text(model.transferMode == .copy ? language.t(.startCopy) : language.t(.startMove))
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
    @EnvironmentObject private var language: LanguageSettings

    var body: some View {
        if let job = model.activeJob {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let isRunning = job.state == .transferring || job.state == .cancelling
                let elapsed = elapsedSeconds(for: job, now: context.date)
                let speedTitle = isRunning ? language.t(.speed) : language.t(.averageSpeed)
                let speedValue = isRunning
                    ? ByteFormatter.speed(job.speedBytesPerSecond)
                    : ByteFormatter.speed(averageSpeed(for: job, elapsed: elapsed))

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 9) {
                        Image(systemName: symbol(for: job.state))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(color(for: job.state))
                        Text(job.state.title(language.language))
                            .font(QCopyTheme.Typography.title)
                        // 耗时放在「正在传输」右侧
                        Text(DurationFormatter.string(elapsed, language: language.language))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(QCopyTheme.Colors.secondary)
                            .monospacedDigit()
                            .accessibilityLabel("\(language.t(.elapsedA11y)) \(DurationFormatter.string(elapsed, language: language.language))")
                        Spacer()
                        if job.state == .transferring {
                            Button(language.t(.cancel)) { model.cancelTransfer() }
                                .buttonStyle(QCopyButtonStyle(tint: .orange))
                        } else if job.state == .cancelling {
                            Text(language.t(.stoppingSafely))
                                .font(QCopyTheme.Typography.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Button(language.t(.collapse)) { model.clearFinishedJob() }
                                .buttonStyle(QCopyButtonStyle(tint: QCopyTheme.Colors.secondary))
                        }
                    }

                    Text(language.phase(job.currentFile))
                        .font(QCopyTheme.Typography.body)
                        .foregroundStyle(QCopyTheme.Colors.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    ProgressTrack(
                        progress: job.progress,
                        isActive: isRunning,
                        isIndeterminate: isRunning && job.currentFileTotalBytes <= 0,
                        tint: color(for: job.state)
                    )

                    TransferStatsRow(
                        items: {
                            let bytesParts = ByteFormatter.parts(job.bytesCopied)
                            let speedBps = isRunning
                                ? job.speedBytesPerSecond
                                : averageSpeed(for: job, elapsed: elapsed)
                            let speedParts = ByteFormatter.speedParts(speedBps, language: language.language)
                            var items: [TransferStatItem] = [
                                .init(
                                    title: language.t(.transferred),
                                    magnitude: bytesParts.magnitude,
                                    unit: bytesParts.unit,
                                    symbol: "arrow.down.doc.fill",
                                    gradient: TransferChartPalette.bytes
                                ),
                                .init(
                                    title: language.t(.processed),
                                    magnitude: "\(job.filesCopied)",
                                    unit: language.t(.unitItems),
                                    symbol: "doc.on.doc.fill",
                                    gradient: TransferChartPalette.files
                                ),
                                .init(
                                    title: speedTitle,
                                    magnitude: speedParts.magnitude,
                                    unit: speedParts.unit,
                                    symbol: "gauge.with.dots.needle.67percent",
                                    gradient: TransferChartPalette.speed
                                ),
                                .init(
                                    title: language.t(.concurrency),
                                    magnitude: "\(max(1, job.currentConcurrency))",
                                    unit: language.t(.unitStreams),
                                    symbol: "square.stack.3d.up.fill",
                                    gradient: TransferChartPalette.concurrency
                                ),
                            ]
                            if job.filesSkipped > 0 {
                                items.append(
                                    .init(
                                        title: language.t(.skipped),
                                        magnitude: "\(job.filesSkipped)",
                                        unit: language.t(.unitItems),
                                        symbol: "forward.end.fill",
                                        gradient: TransferChartPalette.skipped
                                    )
                                )
                            }
                            return items
                        }()
                    )

                    TransferStatisticsChart(samples: job.samples, chartHeight: 140)

                    if case .failed(let message) = job.state {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(QCopyTheme.Typography.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(17)
            .qcopyGlass(in: RoundedRectangle(cornerRadius: QCopyTheme.Radius.card, style: .continuous))
        }
    }

    private func elapsedSeconds(for job: TransferJob, now: Date) -> TimeInterval {
        if let duration = job.duration, job.state != .transferring, job.state != .cancelling {
            return max(0, duration)
        }
        if let finishedAt = job.finishedAt, job.state != .transferring, job.state != .cancelling {
            return max(0, finishedAt.timeIntervalSince(job.startedAt))
        }
        return max(0, now.timeIntervalSince(job.startedAt))
    }

    /// 结束后：平均速度 = 已传输 / 总耗时。
    private func averageSpeed(for job: TransferJob, elapsed: TimeInterval) -> Double {
        if job.speedBytesPerSecond > 0,
           job.state != .transferring,
           job.state != .cancelling {
            return job.speedBytesPerSecond
        }
        guard elapsed > 0, job.bytesCopied > 0 else { return 0 }
        return Double(job.bytesCopied) / elapsed
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

/// 传输统计区的轻量渐变色板，用于图标与图表线条。
private enum TransferChartPalette {
    static let speed = LinearGradient(
        colors: [
            Color(red: 0.28, green: 0.62, blue: 1.0),
            Color(red: 0.42, green: 0.82, blue: 1.0),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let concurrency = LinearGradient(
        colors: [
            Color(red: 0.62, green: 0.38, blue: 1.0),
            Color(red: 0.88, green: 0.52, blue: 1.0),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let bytes = LinearGradient(
        colors: [
            Color(red: 0.18, green: 0.72, blue: 0.92),
            Color(red: 0.35, green: 0.88, blue: 0.78),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let files = LinearGradient(
        colors: [
            Color(red: 0.35, green: 0.58, blue: 1.0),
            Color(red: 0.55, green: 0.78, blue: 1.0),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let duration = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.58, blue: 0.28),
            Color(red: 1.0, green: 0.78, blue: 0.32),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let skipped = LinearGradient(
        colors: [
            Color(red: 0.62, green: 0.66, blue: 0.74),
            Color(red: 0.78, green: 0.82, blue: 0.88),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 线：纯色；填充：仅线下方区域渐变。
    static let speedColor = Color(red: 0.32, green: 0.68, blue: 1.0)
    static let concurrencyColor = Color(red: 0.72, green: 0.45, blue: 1.0)

    static let speedArea = LinearGradient(
        colors: [
            speedColor.opacity(0.36),
            speedColor.opacity(0.02),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

struct TransferStatisticsChart: View {
    @EnvironmentObject private var language: LanguageSettings
    let samples: [TransferSample]
    /// 历史条目内可适当压低高度。
    var chartHeight: CGFloat = 140
    var showsTitle: Bool = true
    @State private var hoveredSampleID: UUID?

    private var visibleSamples: [TransferSample] {
        Array(samples.suffix(240))
    }

    private var elapsedDomain: ClosedRange<Double> {
        guard let first = visibleSamples.first?.elapsed,
              let last = visibleSamples.last?.elapsed else {
            return 0...1
        }
        let lower = min(first, last)
        let upper = max(first, last)
        return lower == upper ? lower...(upper + 1) : lower...upper
    }

    private var speedDomain: ClosedRange<Double> {
        let maximum = visibleSamples.map(\.speedBytesPerSecond).max() ?? 0
        return 0...max(1, maximum * 1.12)
    }

    private var concurrencyAxisValues: [Double] {
        stride(from: 0.0, through: Double(AdaptiveParallelTuner.maximumConcurrencyLimit), by: 16.0)
            .map { scaledConcurrency($0) }
    }

    private var hoveredSample: TransferSample? {
        guard let hoveredSampleID else { return nil }
        return visibleSamples.first { $0.id == hoveredSampleID }
    }

    private func scaledConcurrency(_ concurrency: Double) -> Double {
        concurrency / Double(AdaptiveParallelTuner.maximumConcurrencyLimit) * speedDomain.upperBound
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                HStack(spacing: 8) {
                    Label {
                        Text(language.t(.transferStats))
                    } icon: {
                        Image(systemName: "chart.xyaxis.line")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(TransferChartPalette.speed)
                    }
                    .font(QCopyTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(QCopyTheme.Colors.primaryText)
                    Spacer()
                    legend(color: TransferChartPalette.speedColor, title: language.t(.speed))
                    legend(color: TransferChartPalette.concurrencyColor, title: language.t(.concurrency), dashed: true)
                }
            } else {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    legend(color: TransferChartPalette.speedColor, title: language.t(.speed))
                    legend(color: TransferChartPalette.concurrencyColor, title: language.t(.concurrency), dashed: true)
                }
            }

            if visibleSamples.count < 2 {
                Text(showsTitle ? language.t(.waitingTransferData) : language.t(.noSpeedSamples))
                    .font(QCopyTheme.Typography.caption)
                    .foregroundStyle(QCopyTheme.Colors.tertiary)
                    .frame(maxWidth: .infinity, minHeight: max(64, chartHeight * 0.55), alignment: .center)
            } else {
                combinedChart
            }
        }
        .padding(.top, showsTitle ? 4 : 0)
    }

    private var combinedChart: some View {
        Chart {
            ForEach(visibleSamples) { sample in
                // 仅速度曲线下方做渐变填充
                AreaMark(
                    x: .value("时间", sample.elapsed),
                    y: .value("速度", sample.speedBytesPerSecond),
                    series: .value("指标", "速度填充")
                )
                .foregroundStyle(TransferChartPalette.speedArea)
                .interpolationMethod(.catmullRom)

                // 折线本身纯色，不做渐变
                LineMark(
                    x: .value("时间", sample.elapsed),
                    y: .value("速度", sample.speedBytesPerSecond),
                    series: .value("指标", "速度")
                )
                .foregroundStyle(TransferChartPalette.speedColor)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("时间", sample.elapsed),
                    y: .value("并发", scaledConcurrency(Double(sample.concurrency))),
                    series: .value("指标", "并发")
                )
                .foregroundStyle(TransferChartPalette.concurrencyColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 3]))
                .interpolationMethod(.stepEnd)
            }

            if let hoveredSample {
                RuleMark(x: .value("时间", hoveredSample.elapsed))
                    .foregroundStyle(QCopyTheme.Colors.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(DurationFormatter.string(hoveredSample.elapsed, language: language.language))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(QCopyTheme.Colors.primaryText)
                            Text("\(language.t(.speed))  \(ByteFormatter.speed(hoveredSample.speedBytesPerSecond, language: language.language))")
                                .font(.system(size: 10))
                                .foregroundStyle(TransferChartPalette.speedColor)
                            Text("\(language.t(.concurrency))  \(hoveredSample.concurrency) \(language.t(.unitStreams))")
                                .font(.system(size: 10))
                                .foregroundStyle(TransferChartPalette.concurrencyColor)
                        }
                        .padding(7)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
            }
        }
        .chartXScale(domain: elapsedDomain)
        .chartYScale(domain: speedDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(QCopyTheme.Colors.divider)
                AxisTick().foregroundStyle(QCopyTheme.Colors.tertiary)
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(DurationFormatter.string(seconds, language: language.language))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(QCopyTheme.Colors.divider)
                AxisValueLabel {
                    if let speed = value.as(Double.self) {
                        Text(ByteFormatter.speed(speed, language: language.language))
                    }
                }
            }
            AxisMarks(position: .trailing, values: concurrencyAxisValues) { value in
                AxisGridLine().foregroundStyle(.clear)
                AxisValueLabel {
                    if let scaledValue = value.as(Double.self), speedDomain.upperBound > 0 {
                        let concurrency = scaledValue / speedDomain.upperBound
                            * Double(AdaptiveParallelTuner.maximumConcurrencyLimit)
                        Text("\(Int(concurrency.rounded())) \(language.t(.unitStreams))")
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrameAnchor = proxy.plotFrame else {
                                hoveredSampleID = nil
                                return
                            }
                            let plotFrame = geometry[plotFrameAnchor]
                            guard plotFrame.contains(location),
                                  let elapsed = proxy.value(
                                      atX: location.x - plotFrame.minX,
                                      as: Double.self
                                  ) else {
                                hoveredSampleID = nil
                                return
                            }
                            hoveredSampleID = visibleSamples.min {
                                abs($0.elapsed - elapsed) < abs($1.elapsed - elapsed)
                            }?.id
                        case .ended:
                            hoveredSampleID = nil
                        }
                    }
            }
        }
        .frame(height: chartHeight)
        .accessibilityLabel(language.t(.chartA11y))
    }

    private func legend(color: Color, title: String, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color)
                .frame(width: 16, height: 2.5)
                .mask {
                    if dashed {
                        HStack(spacing: 2) {
                            ForEach(0..<4, id: \.self) { _ in
                                Capsule().frame(width: 2.5, height: 2.5)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Rectangle()
                    }
                }
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(QCopyTheme.Colors.secondary)
        }
    }
}

struct ProgressTrack: View {
    let progress: Double
    let isActive: Bool
    let isIndeterminate: Bool
    let tint: Color

    private var fillGradient: LinearGradient {
        LinearGradient(
            colors: [
                tint,
                tint.opacity(0.72),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(progress, 0), 1)
            let minActiveWidth: CGFloat = isActive && clamped > 0 && clamped < 1 ? 8 : 0
            ZStack(alignment: .leading) {
                Capsule().fill(QCopyTheme.Colors.selection)
                if isIndeterminate {
                    TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { timeline in
                        let width = max(44, proxy.size.width * 0.22)
                        let cycle = timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.1) / 1.1
                        Capsule()
                            .fill(fillGradient)
                            .frame(width: width)
                            .offset(x: -width + CGFloat(cycle) * (proxy.size.width + width))
                    }
                } else {
                    Capsule()
                        .fill(fillGradient)
                        .frame(width: max(proxy.size.width * clamped, minActiveWidth))
                        .animation(.easeOut(duration: 0.18), value: clamped)
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
    }
}

/// 单条传输统计数据：数值与单位分开，字号分别为 15 / 13。
struct TransferStatItem: Identifiable {
    /// 用标题作稳定 id，避免 Timeline 刷新时整行闪烁。
    var id: String { title }
    let title: String
    let magnitude: String
    let unit: String
    let symbol: String
    let gradient: LinearGradient

    var displayValue: String {
        unit.isEmpty ? magnitude : "\(magnitude) \(unit)"
    }
}

/// 等宽均分的统计行：每列图标 + 标题 + 数值垂直居中对齐。
struct TransferStatsRow: View {
    let items: [TransferStatItem]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(QCopyTheme.Colors.divider.opacity(0.7))
                        .frame(width: 0.5)
                        .padding(.vertical, 4)
                }
                TransferStat(item: item)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct TransferStat: View {
    let item: TransferStatItem

    init(item: TransferStatItem) {
        self.item = item
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: item.symbol)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.gradient)
                .frame(width: 22, height: 22)

            Text(item.title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(QCopyTheme.Colors.secondary)
                .lineLimit(1)

            // 数值 15pt + 单位 13pt，基线对齐；不用 scale 压小字号。
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(item.magnitude)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(QCopyTheme.Colors.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                if !item.unit.isEmpty {
                    Text(item.unit)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(QCopyTheme.Colors.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title) \(item.displayValue)")
    }
}
