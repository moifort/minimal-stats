import Foundation
import Darwin

/// Shared sizing between the SystemStats history buffers and the chart views.
enum ChartMetrics {
    /// 5 minutes of history at `refreshInterval` seconds per sample
    static let sampleCount = 150
    static let refreshInterval: TimeInterval = 2.0
}

// Network interface stats from sysctl
private let CTL_NET: Int32 = 4
private let PF_ROUTE: Int32 = 17
private let NET_RT_IFLIST2: Int32 = 6
private let RTM_IFINFO2: UInt8 = 0x12

final class SystemStats {

    // MARK: – State for delta-based metrics

    private var prevCPU: (user: natural_t, system: natural_t, idle: natural_t, nice: natural_t)?

    /// Rolling CPU usage history (last 5 minutes at 2-second intervals = 150 samples)
    private(set) var cpuHistory: [Double] = []
    private let maxHistoryCount = ChartMetrics.sampleCount

    /// Disk space in bytes
    private(set) var diskUsed: Int64 = 0
    private(set) var diskTotal: Int64 = 0

    /// Network speed in bytes/sec
    private var prevNetBytes: (inBytes: UInt64, outBytes: UInt64)?
    private var prevNetTime: Date?
    private(set) var netInHistory: [Double] = []   // bytes/sec
    private(set) var netOutHistory: [Double] = []  // bytes/sec

    // MARK: – Public

    func refresh() {
        readDisk()
        readNetwork()
        // The first reading only seeds the deltas and yields no sample
        if let cpu = readCPU() {
            cpuHistory.append(cpu)
            if cpuHistory.count > maxHistoryCount {
                cpuHistory.removeFirst(cpuHistory.count - maxHistoryCount)
            }
        }
    }

    // MARK: – Network

    private func readNetwork() {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len: Int = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return }

        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: len)
        defer { buf.deallocate() }
        guard sysctl(&mib, UInt32(mib.count), buf, &len, nil, 0) == 0 else { return }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var ptr = buf
        let end = buf.advanced(by: len)

        while ptr < end {
            let msg = ptr.withMemoryRebound(to: if_msghdr.self, capacity: 1) { $0.pointee }
            if msg.ifm_type == RTM_IFINFO2 {
                let ifm2 = ptr.withMemoryRebound(to: if_msghdr2.self, capacity: 1) { $0.pointee }
                totalIn += UInt64(ifm2.ifm_data.ifi_ibytes)
                totalOut += UInt64(ifm2.ifm_data.ifi_obytes)
            }
            ptr = ptr.advanced(by: Int(msg.ifm_msglen))
        }

        let now = Date()
        if let prev = prevNetBytes, let prevTime = prevNetTime {
            let dt = now.timeIntervalSince(prevTime)
            if dt > 0 {
                let inSpeed = Double(totalIn &- prev.inBytes) / dt
                let outSpeed = Double(totalOut &- prev.outBytes) / dt
                netInHistory.append(inSpeed)
                netOutHistory.append(outSpeed)
                if netInHistory.count > maxHistoryCount {
                    netInHistory.removeFirst(netInHistory.count - maxHistoryCount)
                }
                if netOutHistory.count > maxHistoryCount {
                    netOutHistory.removeFirst(netOutHistory.count - maxHistoryCount)
                }
            }
        }
        prevNetBytes = (totalIn, totalOut)
        prevNetTime = now
    }

    // MARK: – Disk

    private func readDisk() {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = attrs[.systemSize] as? Int64,
              let free = attrs[.systemFreeSize] as? Int64 else { return }
        diskTotal = total
        diskUsed = total - free
    }

    // MARK: – CPU

    private func readCPU() -> Double? {
        var loadInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &loadInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let user   = loadInfo.cpu_ticks.0
        let system = loadInfo.cpu_ticks.1
        let idle   = loadInfo.cpu_ticks.2
        let nice   = loadInfo.cpu_ticks.3

        defer { prevCPU = (user, system, idle, nice) }
        guard let prev = prevCPU else { return nil }

        let dUser   = Double(user   &- prev.user)
        let dSystem = Double(system &- prev.system)
        let dIdle   = Double(idle   &- prev.idle)
        let dNice   = Double(nice   &- prev.nice)
        let total   = dUser + dSystem + dIdle + dNice
        guard total > 0 else { return nil }
        return ((dUser + dSystem + dNice) / total) * 100.0
    }
}
