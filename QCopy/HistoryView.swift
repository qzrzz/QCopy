import AppKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: CopyViewModel
    @EnvironmentObject private var language: LanguageSettings

    var body: some View {
        Group {
            if model.history.isEmpty {
                emptyState
                    .padding(.horizontal, QCopyTheme.Layout.contentInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.history) { item in
                        HistoryRow(item: item) {
                            model.removeHistoryEntry(item)
                        }
                        .listRowInsets(
                            EdgeInsets(
                                top: 6,
                                leading: QCopyTheme.Layout.contentInset,
                                bottom: 6,
                                trailing: QCopyTheme.Layout.contentInset
                            )
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(QCopyTheme.Colors.accentPurple.opacity(0.13))
                    .frame(width: 48, height: 48)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(QCopyTheme.Colors.accentPurple)
            }
            Text(language.t(.emptyHistoryTitle))
                .font(QCopyTheme.Typography.title)
            Text(language.t(.emptyHistoryBody))
                .font(QCopyTheme.Typography.caption)
                .foregroundStyle(QCopyTheme.Colors.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .qcopyGlass(in: RoundedRectangle(cornerRadius: QCopyTheme.Radius.card, style: .continuous))
    }
}

// MARK: - History row

private struct HistoryRow: View {
    @EnvironmentObject private var language: LanguageSettings
    let item: TransferHistoryEntry
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.14))
                    Image(systemName: item.mode.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 36, height: 36)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text(item.mode.title(language.language))
                            .font(QCopyTheme.Typography.body.weight(.semibold))
                        Text("·")
                            .foregroundStyle(QCopyTheme.Colors.tertiary)
                        Text(item.source)
                            .font(QCopyTheme.Typography.body.weight(.medium))
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(QCopyTheme.Colors.tertiary)
                        Text(item.destination)
                            .font(QCopyTheme.Typography.body)
                            .foregroundStyle(QCopyTheme.Colors.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(item.state.title(language.language, mode: item.mode))
                            .font(QCopyTheme.Typography.caption.weight(.semibold))
                            .foregroundStyle(statusColor)
                    }
                    .padding(.bottom, 8)

                    HStack(spacing: 0) {
                        metric(title: language.t(.fileCount), value: "\(item.files) \(language.t(.unitItems))")
                        metric(title: language.t(.transferSize), value: ByteFormatter.string(item.bytes))
                        metric(title: language.t(.transferDuration), value: durationText)
                        metric(title: language.t(.avgSpeed), value: speedText)
                    }

                    Text(item.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(QCopyTheme.Colors.tertiary)
                }
            }

            TransferStatisticsChart(
                samples: item.samples,
                chartHeight: 112,
                showsTitle: false
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: QCopyTheme.Radius.card, style: .continuous)
                    .fill(QCopyTheme.Colors.rowHover)
            }
        }
        .qcopyGlass(in: RoundedRectangle(cornerRadius: QCopyTheme.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: QCopyTheme.Radius.card, style: .continuous))
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(language.t(.deleteRecord), role: .destructive, action: onDelete)
        }
        .help("\(item.mode.title(language.language)) · \(item.date.formatted(date: .abbreviated, time: .shortened))")
    }

    private var durationText: String {
        guard let duration = item.duration, duration > 0 else { return "—" }
        return DurationFormatter.string(duration, language: language.language)
    }

    private var speedText: String {
        guard item.averageSpeedBytesPerSecond > 0 else { return "—" }
        return ByteFormatter.speed(item.averageSpeedBytesPerSecond, language: language.language)
    }

    private var statusColor: Color {
        switch item.state {
        case .completed: .green
        case .cancelled: .orange
        case .failed: .red
        default: QCopyTheme.Colors.accent
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(QCopyTheme.Colors.tertiary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(QCopyTheme.Colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
