import Foundation
import CoreGraphics

// Headless regression coverage of the production viewport projection. These
// inputs stand in for SwiftUI callbacks; callback delivery and actual decoding
// still require the short-clip app acceptance check.
@main
enum ThumbnailViewportTests {
    static func main() {
        let density = pow(2.0, 0.6)
        let count = Int(floor(22 * density)) + 1
        func project(_ size: CGSize, offset: CGFloat = 0, width: CGFloat = 60,
                     rate: Double = pow(2.0, 0.6), duration: Double = 22,
                     count: Int = 34) -> ThumbnailViewport.Projection? {
            ThumbnailViewport(size: size, offsetY: offset).project(
                cellWidth: width, density: rate, duration: duration, count: count)
        }
        func check(_ passed: Bool, _ message: String) {
            guard passed else { fatalError(message) }
        }

        check(count == 34, "22-second fixture must contain 34 thumbnails")
        let initial = project(CGSize(width: 800, height: 200))!
        check(initial.columns == 12, "adaptive columns include padding and spacing")
        check(initial.timeRange == 0...22, "initial visible short clip must request the complete visible grid")
        check(project(CGSize(width: 0, height: 0)) == nil, "zero layout must not seed a tiny render range")
        check(project(CGSize(width: 800, height: 0)) == nil, "zero height is not a viewport")
        check(project(CGSize(width: 0, height: 200)) == nil, "zero width is not a viewport")
        check(project(CGSize(width: -1, height: 200)) == nil, "negative transient size is ignored")
        check(project(CGSize(width: CGFloat.infinity, height: 200)) == nil, "nonfinite size is ignored")

        let transient = project(CGSize(width: 137, height: 20))!
        check(transient.columns == 2 && transient.timeRange.upperBound < 2,
              "small transient layout reproduces a narrow request")
        check(initial.timeRange.upperBound > transient.timeRange.upperBound,
              "settled size must expand initial demand without scrolling")
        let resized = project(CGSize(width: 137, height: 80))!
        check(resized.timeRange.upperBound > transient.timeRange.upperBound,
              "vertical resize must include additional rows")

        // Exactly two columns fit at 137 points: 16 padding + 2*60 + 1 gap.
        check(project(CGSize(width: 137, height: 80))!.columns == 2, "exact column boundary")
        check(project(CGSize(width: 136.99, height: 80))!.columns == 1, "below column boundary")
        let fullRow = project(CGSize(width: 137, height: 33.75), offset: 4)!
        check(fullRow.fullyVisibleRows == 0...0, "one exact fully visible row")
        let scrolled = project(CGSize(width: 137, height: 33.75), offset: 38.75)!
        check(scrolled.fullyVisibleRows == 1...1, "one row scroll advances full-row bounds")
        check(abs(scrolled.timeRange.lowerBound - 2 / density) < 0.000001,
              "scrolling advances demand by the number of columns")
        let partial = project(CGSize(width: 137, height: 80), offset: 5)!
        check(partial.fullyVisibleRows.lowerBound == 1, "clipped first row is not fully visible")

        let zoomed = project(CGSize(width: 800, height: 200), width: 120, rate: 4, count: 89)!
        check(zoomed.columns == 6 && zoomed.timeRange.upperBound < 22,
              "same raw viewport must recompute demand after zoom")
        let cappedZoom = project(CGSize(width: 800, height: 200), width: 180, rate: 4, count: 89)!
        check(cappedZoom.columns == 4 && cappedZoom.timeRange.upperBound < zoomed.timeRange.upperBound,
              "cell width changes must recompute demand even when density stays at the fps cap")
        let replacement = project(CGSize(width: 800, height: 200), duration: 5, count: 8)!
        check(replacement.timeRange == 0...5, "same geometry must recompute for a replacement clip")
        let beyond = project(CGSize(width: 800, height: 200), offset: 10000)!
        check(beyond.timeRange.upperBound == 22 && beyond.timeRange.lowerBound <= 22,
              "content offset beyond end remains clamped")
        check(project(CGSize(width: 800, height: 200), count: 0) == nil, "empty clip has no demand")

        // Deep-scroll regression: a four/five-column mismatch near frame 213
        // requests an entirely different time range. The view now uses this
        // projection's columns explicitly rather than packing adaptively.
        // Verify both sides of the five-column boundary at every-frame zoom.
        for viewportWidth: CGFloat in [1219.99, 1220, 1380] {
            let projection = project(CGSize(width: viewportWidth, height: 360),
                                     offset: 53 * 136 + 4, width: 240,
                                     rate: 25, count: 551)!
            let expectedColumns = viewportWidth < 1220 ? 4 : 5
            check(projection.columns == expectedColumns, "four/five-column layout boundary")
            let rowStart = 53 * projection.columns
            for index in rowStart..<(rowStart + 3 * projection.columns) {
                check(projection.timeRange.contains(Double(index) / 25),
                      "every visible cell at a deep scroll offset must be requested")
            }
            let selected = rowStart + 1
            let below = selected + projection.columns
            check(below % expectedColumns == selected % expectedColumns,
                  "vertical navigation must retain the rendered column")
        }
        // A deep LazyVGrid can report an offset whose nominal row is about ten
        // seconds before the cells actually on screen. Demand must include all
        // intersecting neighbors, not only the selected cell.
        let deep = ThumbnailViewport(size: CGSize(width: 696, height: 315), offsetY: 3055853)
        let measured: [Int: CGRect] = [
            45236: CGRect(x: 8, y: -100, width: 240, height: 135),
            45237: CGRect(x: 249, y: -100, width: 240, height: 135),
            45238: CGRect(x: 8, y: 36, width: 240, height: 135),
            45239: CGRect(x: 249, y: 36, width: 240, height: 135),
            45240: CGRect(x: 8, y: 172, width: 240, height: 135),
            45241: CGRect(x: 249, y: 172, width: 240, height: 135),
            45242: CGRect(x: 8, y: 308, width: 240, height: 135),
            45243: CGRect(x: 249, y: 308, width: 240, height: 135),
            45244: CGRect(x: 8, y: 444, width: 240, height: 135)
        ]
        let actual = deep.measuredProjection(cellBounds: measured, columns: 2,
                                             density: 30, duration: 1800, count: 54001)!
        let nominal = deep.project(cellWidth: 240, density: 30, duration: 1800, count: 54001)!
        check(!nominal.timeRange.contains(45238.0 / 30), "fixture reproduces deep offset omission")
        check(actual.timeRange == (45236.0 / 30)...(45244.0 / 30),
              "actual geometry includes every partially visible neighboring cell")
        check(actual.fullyVisibleRows == 22619...22620, "follow uses measured fully visible rows")
        let noOffset = ThumbnailViewport(size: deep.size, offsetY: 0)
        check(noOffset.measuredProjection(cellBounds: measured, columns: 2,
                                          density: 30, duration: 1800, count: 54001) == actual,
              "measured demand is independent of estimated content offset")
        let zoom = deep.measuredProjection(cellBounds: measured, columns: 2,
                                           density: 60, duration: 1800, count: 108001)!
        check(zoom.timeRange == (45236.0 / 60)...(45244.0 / 60),
              "density changes remap the same measured indices without a scroll")
        let narrower = ThumbnailViewport(size: CGSize(width: 240, height: 170), offsetY: 3055853)
        let repacked: [Int: CGRect] = [
            45238: CGRect(x: 0, y: 0, width: 240, height: 135),
            45239: CGRect(x: 0, y: 136, width: 240, height: 135),
            45240: CGRect(x: 0, y: 272, width: 240, height: 135)
        ]
        let repackedDemand = narrower.measuredProjection(cellBounds: repacked, columns: 1,
                                                          density: 30, duration: 1800, count: 54001)!
        check(repackedDemand.timeRange == (45238.0 / 30)...(45240.0 / 30),
              "repacking at capped density replaces demand with new visible bounds")
        check(repackedDemand.fullyVisibleRows == 45238...45238,
              "measured follow rows use current rendered columns")
        let edges: [Int: CGRect] = [
            0: CGRect(x: 0, y: -10, width: 10, height: 10), // touches top only
            1: CGRect(x: 0, y: -9, width: 10, height: 10),
            2: CGRect(x: 695, y: 314, width: 10, height: 10),
            3: CGRect(x: 696, y: 0, width: 10, height: 10), // touches right only
            4: CGRect(x: 0, y: 315, width: 10, height: 10), // touches bottom only
            5: CGRect(x: 0, y: 0, width: 0, height: 10),
            -1: CGRect(x: 0, y: 0, width: 10, height: 10),
            100: CGRect(x: 0, y: 0, width: 10, height: 10)
        ]
        check(deep.measuredProjection(cellBounds: edges, columns: 2, density: 1,
                                       duration: 10, count: 11)!.timeRange == 1...3,
              "positive-area intersections include clipped edges and exclude touching/invalid cells")
        check(deep.measuredProjection(cellBounds: [:], columns: 2, density: 30,
                                       duration: 1800, count: 54001) == nil,
              "unmeasured layout must not invent demand from a stale offset")
        check(deep.measuredProjection(cellBounds: [10: CGRect(x: 0, y: 0, width: 10, height: 10)],
                                       columns: 2, density: 1, duration: 10, count: 11)!.timeRange == 10...10,
              "final visible thumbnail clamps to duration")
        print("ThumbnailViewport: all regression checks passed")
    }
}
