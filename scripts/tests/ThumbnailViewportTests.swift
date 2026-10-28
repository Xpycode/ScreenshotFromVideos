import Foundation

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
        print("ThumbnailViewport: all regression checks passed")
    }
}
