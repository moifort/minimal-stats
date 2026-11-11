import XCTest
@testable import Stats

final class NetworkChartTests: XCTestCase {

    func testSmallTrafficStaysVisibleAfterAPeak() {
        let scaled = NetworkChartView.scaled(inHistory: [40_000_000, 20_000], outHistory: [10_000])
        XCTAssertEqual(scaled.maxValue, 40_000_000.squareRoot(), accuracy: 0.001)
        // 20 KB/s against a 40 MB/s peak: 0.05% of the height linearly, over 2% now
        XCTAssertEqual(scaled.inHistory[1] / scaled.maxValue, 0.0224, accuracy: 0.0001)
        XCTAssertEqual(scaled.inHistory[0], scaled.maxValue)
        XCTAssertEqual(scaled.outHistory, [100])
    }

    func testIdleNetworkKeepsAUnitScale() {
        let scaled = NetworkChartView.scaled(inHistory: [], outHistory: [0, 0])
        XCTAssertEqual(scaled.maxValue, 1)
        XCTAssertEqual(scaled.outHistory, [0, 0])
    }

    func testScaleKeepsTheOrderOfSamples() {
        let history: [Double] = [0, 500, 1_000, 250_000, 3_000_000]
        let scaled = NetworkChartView.scaled(inHistory: history, outHistory: []).inHistory
        XCTAssertEqual(scaled, scaled.sorted())
        XCTAssertEqual(Set(scaled).count, history.count)
    }
}
