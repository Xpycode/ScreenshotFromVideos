import Foundation

/// Raw viewport geometry, independent of zoom and the loaded video. Keeping
/// these inputs lets the view recompute demand even when scrolling is idle.
struct ThumbnailViewport: Equatable {
    let size: CGSize
    let offsetY: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.size.width == rhs.size.width && lhs.size.height == rhs.size.height && lhs.offsetY == rhs.offsetY
    }

    struct Projection: Equatable {
        let columns: Int
        let fullyVisibleRows: ClosedRange<Int>
        let timeRange: ClosedRange<Double>
    }

    func project(cellWidth: CGFloat, density: Double, duration: Double, count: Int) -> Projection? {
        guard size.width.isFinite, size.height.isFinite, offsetY.isFinite,
              size.width > 0, size.height > 0, cellWidth.isFinite, cellWidth > 0,
              density.isFinite, density > 0, duration.isFinite, duration > 0,
              count > 0 else { return nil }
        // Match LazyVGrid's 8-point horizontal / 4-point vertical padding,
        // fixed 16:9 cells and one-point spacing.
        let columns = max(1, Int((size.width - 15) / (cellWidth + 1)))
        let cellHeight = cellWidth * 9 / 16
        let rowHeight = cellHeight + 1
        let firstRow = max(0, Int(floor((offsetY - 4) / rowHeight)))
        let lastRow = max(firstRow, Int(floor((offsetY + size.height - 4) / rowHeight)))
        let firstIndex = min(count - 1, firstRow * columns)
        let lastIndex = min(count - 1, (lastRow + 1) * columns - 1)
        let lower = max(0, min(duration, Double(firstIndex) / density))
        let upper = max(lower, min(duration, Double(lastIndex + 1) / density))
        let firstFullRow = max(0, Int(ceil((offsetY - 4) / rowHeight)))
        let lastFullRow = max(firstFullRow,
                              Int(floor((offsetY + size.height - 4 - cellHeight) / rowHeight)))
        return Projection(columns: columns, fullyVisibleRows: firstFullRow...lastFullRow,
                          timeRange: lower...upper)
    }
}
