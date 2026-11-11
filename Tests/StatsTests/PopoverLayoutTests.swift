import XCTest
import SwiftUI
@testable import Stats

/// The popover's panel is sized once, when it opens: if a refresh made the
/// content ask for another size, it would jump inside the panel.
@MainActor
final class PopoverLayoutTests: XCTestCase {

    private func fittingSize(_ model: StatusBarModel) -> CGSize {
        let host = NSHostingView(rootView: PopoverView(model: model))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    func testRefreshesNeverChangeThePopoverSize() {
        let names = ["Claude", "com.apple.WebKit.Networking", "Google Chrome Helper (Renderer)", "mediaanalysisd",
                     "日本語のアプリ", "Émojis 🚀", "gh", "a", "NotificationCenter", String(repeating: "W", count: 60)]
        var sizes: Set<String> = []
        var generator = SystemRandomNumberGenerator()
        for round in 0..<200 {
            let m = StatusBarModel()
            m.processSort = ProcessSort.allCases[round % ProcessSort.allCases.count]
            m.cpuHistory = [Double.random(in: 0...100, using: &generator)]
            m.netInHistory = [Double.random(in: 0...9e9, using: &generator)]
            m.netOutHistory = [Double.random(in: 0...9e9, using: &generator)]
            m.memoryTotal = 16 << 30
            m.memoryUsed = UInt64.random(in: 0...(16 << 30), using: &generator)
            m.diskTotal = 494_000_000_000
            m.diskFree = Int64.random(in: 0...494_000_000_000, using: &generator)
            let count = round % 7
            let processes = (0..<count).map { i in
                ProcessUsage(pid: pid_t(100 + i), parentPID: 1, name: names[(round + i) % names.count],
                             cpuPercent: Double.random(in: 0...100, using: &generator),
                             memoryBytes: UInt64.random(in: 0...(64 << 30), using: &generator), isOwnedByUser: i % 2 == 0)
            }
            m.processGroups = ProcessGroup.make(from: processes)
            m.networkProcesses = processes.map { .init(pid: $0.pid, name: $0.name, bytesIn: UInt64.random(in: 0...(1 << 40), using: &generator), bytesOut: UInt64.random(in: 0...(1 << 40), using: &generator)) }
            m.diskProcesses = processes.map { .init(pid: $0.pid, name: $0.name, bytesIn: UInt64.random(in: 0...(1 << 40), using: &generator), bytesOut: UInt64.random(in: 0...(1 << 40), using: &generator)) }
            let size = fittingSize(m)
            sizes.insert("\(size.width)x\(size.height)")
        }
        XCTAssertEqual(sizes.count, 1, "the popover asked for \(sizes.sorted())")
    }
}
