import Foundation

@main
struct ProbeCheck {
    static func main() {
        var evaluations = 0
        func message() -> String { evaluations += 1; return "filtered-cell" }
        ZoomTrace.selection(1_529_300, bucket: 240, "selection-check")
        for _ in 0..<50_000 { ZoomTrace.cell(0, message()) }
        ZoomTrace.event("zoom-after-cell-flood")
        ZoomTrace.cell(1_529_300, "selected-cell")
        ZoomTrace.selection(1_529_333, bucket: 240, "changed-key-same-index")
        ZoomTrace.cell(1_529_333, "changed-selected-cell")
        print("pid=\(ProcessInfo.processInfo.processIdentifier) filteredEvaluations=\(evaluations)")
        precondition(evaluations == 0)
    }
}
