import Foundation
import Darwin

/// How this copy of Stats reached the Mac.
///
/// The Mac App Store build (`scripts/build-app-store.sh`, `APP_STORE` flag)
/// runs in the App Sandbox. Measured in a sandboxed build (docs/app-store.md):
/// - `/bin/ps` and `/usr/bin/top` are setuid root: the sandbox refuses to
///   launch them, and libproc (`proc_pidinfo`, `proc_pidpath`) answers for no
///   process. Nothing reads another process's CPU time or memory, so the CPU
///   and Memory tabs go, and so does the Disk tab: `proc_pid_rusage` only
///   answers for Stats itself. `sysctl(KERN_PROC_ALL)` still lists every process with
///   its parent, enough to group the Network tab by application;
/// - `/usr/bin/nettop` is not setuid and still runs: the Network tab stays;
/// - `kill` and `NSRunningApplication.terminate` are refused for other
///   processes: no quit buttons;
/// - the app cannot write next to its own bundle nor move it to the Trash: the
///   App Store installs the updates and deleting the app removes its container,
///   so the updater and the uninstaller go;
/// - guideline 2.4.5(iii) forbids opening at login without the user's consent:
///   the right-click menu offers it instead of registering at first launch.
///
/// The four menu bar widgets and the popover's live figures (host statistics,
/// interface counters, volume capacity) work unchanged.
enum Distribution {
    #if APP_STORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif

    /// `/bin/ps` measures every process's CPU and memory, libproc their disk activity.
    static var measuresProcesses: Bool { !isAppStore }
    static var canQuitProcesses: Bool { !isAppStore }
    static var hasUninstaller: Bool { !isAppStore }
    /// Never from a build folder: it would replace a build product, and the
    /// next build would overwrite it anyway.
    static var hasUpdater: Bool { !isAppStore && !isBuildProduct }
    /// The Developer ID build opens at login from its first launch; the App
    /// Store build only when the user asks. A build product never registers:
    /// the login item would point into a build folder.
    static var registersLoginItemAtFirstLaunch: Bool { !isAppStore && !isBuildProduct }
    static var offersOpenAtLogin: Bool { isAppStore && !isBuildProduct }

    /// The running bundle sits in a build folder (SwiftPM, the build scripts, Xcode).
    static var isBuildProduct: Bool { isBuildProduct(path: Bundle.main.bundlePath) }

    static func isBuildProduct(path: String) -> Bool {
        ["/.build/", "/build/", "/Build/Products/", "/DerivedData/"].contains { path.contains($0) }
    }
}

extension ProcessSort {
    /// The tabs this build can fill: only Network in the App Store build.
    static var available: [ProcessSort] {
        Distribution.measuresProcesses ? allCases : [.network]
    }
}

extension ProcessSampler {
    /// Every process with its parent, owner and name, from `sysctl(KERN_PROC_ALL)`,
    /// which the sandbox allows: no CPU or memory figures, only what grouping
    /// by application needs. Names are the kernel's, cut at 16 characters.
    nonisolated static func listWithoutFigures(ownPID: pid_t = getpid(), currentUID: uid_t = getuid()) -> [ProcessUsage]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        // Room for processes started between the two calls
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 32)
        size = processes.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 3, &processes, &size, nil, 0) == 0 else { return nil }
        let count = size / MemoryLayout<kinfo_proc>.stride
        return processes.prefix(count).compactMap { info in
            let pid = info.kp_proc.p_pid
            guard pid > 0, pid != ownPID else { return nil }
            var comm = info.kp_proc.p_comm
            let name = withUnsafeBytes(of: &comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return ProcessUsage(
                pid: pid,
                parentPID: info.kp_eproc.e_ppid,
                name: name,
                cpuPercent: nil,
                memoryBytes: 0,
                isOwnedByUser: info.kp_eproc.e_ucred.cr_uid == currentUID
            )
        }
    }
}
