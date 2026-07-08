import SwiftUI

/// A `Layout` that wraps its subviews left-to-right onto multiple lines
/// when the row's width is exceeded — the standard "tag cloud" / "chip
/// row" behavior. Native SwiftUI doesn't have one (`HStack` clips,
/// `LazyVGrid(.adaptive)` mostly works but distributes evenly which
/// looks wrong for variable-width chips).
///
/// Used inside `QuestionCard` to lay out variable-width `Chip`s. The
/// math is intentionally simple — sizes are computed once per pass and
/// cached in the placement; we don't try to align baselines or do
/// fancy justification.
///
/// Compatible with iOS 16+ (the `Layout` protocol shipped in iOS 16).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { running, row in
            running + row.maxHeight + (running == 0 ? 0 : lineSpacing)
        }
        let width = rows.map(\.totalWidth).max() ?? 0
        return CGSize(
            width: maxWidth.isFinite ? maxWidth : width,
            height: height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = computeRows(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for entry in row.entries {
                subviews[entry.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(entry.size)
                )
                x += entry.size.width + spacing
            }
            y += row.maxHeight + lineSpacing
        }
    }

    // MARK: - Row computation

    private struct RowEntry {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var entries: [RowEntry] = []
        var totalWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
    }

    private func computeRows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = size.width + (rows[rows.count - 1].entries.isEmpty ? 0 : spacing)
            if rows[rows.count - 1].totalWidth + needed > maxWidth,
               !rows[rows.count - 1].entries.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].entries.isEmpty
            rows[rows.count - 1].entries.append(RowEntry(index: index, size: size))
            rows[rows.count - 1].totalWidth += size.width + (isFirst ? 0 : spacing)
            rows[rows.count - 1].maxHeight = max(rows[rows.count - 1].maxHeight, size.height)
        }
        return rows
    }
}

#Preview {
    FlowLayout(spacing: 8, lineSpacing: 8) {
        ForEach(["Streetwear", "Minimal", "Bold", "Nostalgic", "Premium", "Cyberpunk", "Cottagecore"], id: \.self) { label in
            Chip(title: label, isSelected: label == "Minimal", action: {})
        }
    }
    .padding(20)
    .frame(maxWidth: 320)
    .background(AppColor.background)
    .preferredColorScheme(.dark)
}
