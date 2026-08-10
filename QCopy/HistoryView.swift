import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: CopyViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            Group {
                if model.history.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.history) { item in
                            HistoryRow(item: item)
                            if item.id != model.history.last?.id {
                                Rectangle()
                                    .fill(QCopyTheme.Colors.divider)
                                    .frame(height: 0.6)
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .qcopyGlass(in: RoundedRectangle(cornerRadius: QCopyTheme.Radius.card, style: .continuous))
                }
            }
            .padding(.horizontal, QCopyTheme.Layout.contentInset)
            .padding(.top, 8)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            Text("暂无操作记录")
                .font(QCopyTheme.Typography.title)
            Text("完成一次传输后，会在这里显示详细信息")
                .font(QCopyTheme.Typography.caption)
                .foregroundStyle(QCopyTheme.Colors.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .qcopyGlass(in: RoundedRectangle(cornerRadius: QCopyTheme.Radius.card, style: .continuous))
    }
}

private struct HistoryRow: View {
    let item: TransferHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(statusColor.opacity(0.14))
                Image(systemName: item.mode.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.source)
                        .font(QCopyTheme.Typography.body.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(QCopyTheme.Colors.tertiary)
                    Text(item.destination)
                        .font(QCopyTheme.Typography.body)
                        .foregroundStyle(QCopyTheme.Colors.secondary)
                        .lineLimit(1)
                }
                Text("\(item.mode.title) · \(item.files) 项 · \(ByteFormatter.string(item.bytes))")
                    .font(QCopyTheme.Typography.caption)
                    .foregroundStyle(QCopyTheme.Colors.secondary)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 3) {
                Text(item.state.title)
                    .font(QCopyTheme.Typography.caption)
                    .foregroundStyle(statusColor)
                Text(item.date, style: .relative)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(QCopyTheme.Colors.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusColor: Color {
        switch item.state {
        case .completed: .green
        case .cancelled: .orange
        case .failed: .red
        default: QCopyTheme.Colors.accent
        }
    }
}
