import Foundation
import Darwin

final class SystemStats {

    // MARK: – State for delta-based metrics

    private var prevCPU: (user: natural_t, system: natural_t, idle: natural_t, nice: natural_t)?

    /// Rolling CPU usage history (last 5 minutes at 2-second intervals = 150 samples)
    private(set) var cpuHistory: [Double] = []
    private let maxHistoryCount = 150

    // MARK: – Public

    func refresh() -> Double {
        let cpu = readCPU()
        cpuHistory.append(cpu)
        if cpuHistory.count > maxHistoryCount {
            cpuHistory.removeFirst(cpuHistory.count - maxHistoryCount)
        }
        return cpu
    }

    // MARK: – CPU

    private func readCPU() -> Double {
        var loadInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &loadInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }

        let user   = loadInfo.cpu_ticks.0
        let system = loadInfo.cpu_ticks.1
        let idle   = loadInfo.cpu_ticks.2
        let nice   = loadInfo.cpu_ticks.3

        var usage: Double = 0
        if let prev = prevCPU {
            let dUser   = Double(user   &- prev.user)
            let dSystem = Double(system &- prev.system)
            let dIdle   = Double(idle   &- prev.idle)
            let dNice   = Double(nice   &- prev.nice)
            let total   = dUser + dSystem + dIdle + dNice
            if total > 0 {
                usage = ((dUser + dSystem + dNice) / total) * 100.0
            }
        }
        prevCPU = (user, system, idle, nice)
        return usage
    }
}
