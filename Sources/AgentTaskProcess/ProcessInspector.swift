import Foundation
import Darwin
import AgentTaskCore

public enum ProcessInspector {
    /// Inspects the process with the given PID and returns a ProcessIdentity if the process exists.
    public static func inspect(pid: Int32) -> ProcessIdentity? {
        var kinfo = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        let result = sysctl(&mib, UInt32(mib.count), &kinfo, &size, nil, 0)
        guard result == 0 && size > 0 else {
            return nil
        }

        // Check if PID actually matched
        guard kinfo.kp_proc.p_pid == pid else {
            return nil
        }

        let ppid = kinfo.kp_eproc.e_ppid
        let startSec = kinfo.kp_proc.p_starttime.tv_sec
        let startUsec = kinfo.kp_proc.p_starttime.tv_usec
        let startTime = Date(timeIntervalSince1970: Double(startSec) + Double(startUsec) / 1_000_000.0)

        // Resolve executable path
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        let executable: String? = pathLength > 0 ? String(cString: pathBuffer) : nil

        let cwd = FileManager.default.currentDirectoryPath

        return ProcessIdentity(
            pid: pid,
            ppid: ppid,
            processStartedAt: startTime,
            executable: executable,
            bundleId: nil,
            cwd: cwd,
            lastAliveAt: Date()
        )
    }

    /// Captures process identity of the currently running process.
    public static func currentProcess() -> ProcessIdentity {
        let myPid = getpid()
        return inspect(pid: myPid) ?? ProcessIdentity(pid: myPid, processStartedAt: Date(), cwd: FileManager.default.currentDirectoryPath)
    }
}
