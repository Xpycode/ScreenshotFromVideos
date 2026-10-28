import Foundation
import AVFoundation
@main struct ModelProbe {
 @MainActor static func main() async throws {
  let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
  let model = StripModel(duration: 22, nominalFPS: 25, cache: ThumbnailCache(totalCostLimit: 50_000_000), renderer: ThumbnailRenderer(asset: asset))
  func counts() -> (Int, Int) {
   let times = model.thumbnailTimes(in: 0...22)
   return (times.filter { model.cache.image(for: ThumbKey(timeMillis: Int64(($0.seconds * 1000).rounded()), widthBucket: model.widthBucket)) != nil }.count, times.count)
  }
  func waitForFill(_ label: String) async throws {
   let start = Date()
   for _ in 0..<200 {
    let c = counts()
    if c.0 == c.1 { print("PASS \(label): \(c) cacheVersion=\(model.cacheVersion) seconds=\(Date().timeIntervalSince(start))"); return }
    try await Task.sleep(for: .milliseconds(50))
   }
   fatalError("Incomplete \(label): \(counts())")
  }
  model.onVisibleRangeChange(0...22)
  try await waitForFill("initial explicit range")
  for zoom in [2.0, 3.0, 4.0, 2.5, 3.5, 2.0] {
   model.setZoom(zoom)
   model.onVisibleRangeChange(0...22)
   try await Task.sleep(for: .milliseconds(100))
  }
  try await waitForFill("zoom cancellation final range")
  model.setZoom(1)
  model.onVisibleRangeChange(0...22)
  try await waitForFill("return cached zoom1")
 }
}
