import Foundation
import CoreGraphics

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

    /// Include partially clipped cells and every visible neighbor; prefetch padding
    /// and request limits remain the model's responsibility.
    func measuredProjection(cellBounds: [Int: CGRect], columns: Int, density: Double,
                            duration: Double, count: Int) -> Projection? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              columns > 0, density.isFinite, density > 0,
              duration.isFinite, duration > 0, count > 0 else { return nil }
        // Bounds are resolved in the scroll viewport's coordinates. Lazy-grid
        // content offsets can include estimated row heights, so they cannot
        // establish which indices are actually on screen after deep zooms.
        let viewport = CGRect(origin: .zero, size: size)
        let visible = cellBounds.filter { index, bounds in
            guard index >= 0, index < count,
                  bounds.origin.x.isFinite, bounds.origin.y.isFinite,
                  bounds.width.isFinite, bounds.height.isFinite,
                  bounds.width > 0, bounds.height > 0 else { return false }
            let intersection = viewport.intersection(bounds)
            return !intersection.isNull && intersection.width > 0 && intersection.height > 0
        }
        guard let first = visible.keys.min(), let last = visible.keys.max() else { return nil }
        let fullRows = visible.filter { viewport.contains($0.value) }.keys.map { $0 / columns }
        let firstFull = fullRows.min() ?? first / columns
        let lastFull = fullRows.max() ?? firstFull
        let lower = min(duration, Double(first) / density)
        let upper = max(lower, min(duration, Double(last + 1) / density))
        return Projection(columns: columns, fullyVisibleRows: firstFull...lastFull,
                          timeRange: lower...upper)
    }

    func project(cellWidth: CGFloat, density: Double, duration: Double, count: Int) -> Projection? {
        guard size.width.isFinite, size.height.isFinite, offsetY.isFinite,
              size.width > 0, size.height > 0, cellWidth.isFinite, cellWidth > 0,
              density.isFinite, density > 0, duration.isFinite, duration > 0,
              count > 0 else { return nil }
        // This count drives the grid's explicit fixed columns as well as
        // navigation and decode demand. Do not independently use adaptive
        // packing in the view: its count can differ at layout boundaries.
        // Account for 8-point horizontal / 4-point vertical padding,
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
