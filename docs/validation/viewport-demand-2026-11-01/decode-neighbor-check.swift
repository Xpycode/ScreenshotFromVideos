import Foundation
import AVFoundation

@main
struct DecodeCheck {
    static func main() async {
        let asset = AVURLAsset(url: URL(fileURLWithPath: "/Users/sim/Movies/PenumbraSmoke/mp4-long-perf.mp4"))
        let renderer = ThumbnailRenderer(asset: asset)
        let times = (49100...49111).map { CMTime(seconds: Double($0) / 30, preferredTimescale: 600) }
        print("Requested indices 49100...49111, selected 49106; width 240; tolerance half-gap", terminator: "\n")
        var received = Set<Int64>()
        for await (time, image) in renderer.render(times: times, targetWidth: 240,
                                                  tolerance: CMTime(seconds: 0.5 / 30, preferredTimescale: 600)) {
            let key = Int64((CMTimeGetSeconds(time) * 1000).rounded())
            received.insert(key)
            print("received \(key) size \(image.width)x\(image.height)")
        }
        let expected = Set(times.map { Int64((CMTimeGetSeconds($0) * 1000).rounded()) })
        print("received \(received.count)/\(expected.count); missing \(expected.subtracting(received).sorted())")
    }
}
