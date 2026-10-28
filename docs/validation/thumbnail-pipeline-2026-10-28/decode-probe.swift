import Foundation
import AVFoundation
@main struct Probe {
 static func main() async throws {
  let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
  let duration = try await asset.load(.duration).seconds
  let track = try await asset.loadTracks(withMediaType: .video)[0]
  let size = try await track.load(.naturalSize)
  let fps = try await track.load(.nominalFrameRate)
  let descriptions = try await track.load(.formatDescriptions)
  print("duration=\(duration) size=\(size) fps=\(fps) formats=\(descriptions)")
  let density = pow(2.0, 0.6)
  let times = (0...Int(duration*density)).map { CMTime(seconds: Double($0)/density, preferredTimescale: 600) }
  for ordered in [false, true, true, false] {
   let generator = AVAssetImageGenerator(asset: asset)
   generator.appliesPreferredTrackTransform = true
   generator.maximumSize = CGSize(width:240,height:0)
   generator.requestedTimeToleranceBefore = CMTime(seconds:0.5/density,preferredTimescale:600)
   generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore
   let requests = ordered ? times : times.sorted { abs($0.seconds-duration/2) < abs($1.seconds-duration/2) }
   let start = Date(); var count = 0; var failed = 0
   for try await result in generator.images(for: requests) {
    switch result {
    case .success: count += 1
    case .failure(_, let error): failed += 1; print("failure \(error)")
    }
    if count == 1 || count % 10 == 0 { print("ordered=\(ordered) count=\(count) seconds=\(Date().timeIntervalSince(start))") }
   }
   print("DONE ordered=\(ordered) success=\(count) failures=\(failed) seconds=\(Date().timeIntervalSince(start))")
  }
 }
}
