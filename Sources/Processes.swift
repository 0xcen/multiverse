import AppKit

/// What we know about a running process.
struct ProcessInfoLite {
    let pid: pid_t
    let bundleID: String?
    let bundlePath: String?
    let args: [String]

    init(pid: pid_t) {
        self.pid = pid
        let app = NSRunningApplication(processIdentifier: pid)
        bundleID = app?.bundleIdentifier
        bundlePath = app?.bundleURL?.standardizedFileURL.path
        args = processArguments(pid)
    }

    /// Value of `--user-data-dir`, if the process was started with one.
    var userDataDir: String? {
        for (i, a) in args.enumerated() {
            if a.hasPrefix("--user-data-dir=") { return String(a.dropFirst("--user-data-dir=".count)) }
            if a == "--user-data-dir", i + 1 < args.count { return args[i + 1] }
        }
        return nil
    }
}

/// argv of another process via sysctl KERN_PROCARGS2 (same user only).
func processArguments(_ pid: pid_t) -> [String] {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
    var buf = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }

    let argc = buf.withUnsafeBytes { $0.load(as: Int32.self) }
    var i = MemoryLayout<Int32>.size
    while i < size, buf[i] != 0 { i += 1 }  // exec path
    while i < size, buf[i] == 0 { i += 1 }  // padding

    var args: [String] = []
    while args.count < argc, i < size {
        let start = i
        while i < size, buf[i] != 0 { i += 1 }
        args.append(String(decoding: buf[start..<i], as: UTF8.self))
        i += 1
    }
    return args
}

/// Running main processes of `appPath` whose `--user-data-dir` equals `dataDir` (nil = none given).
func runningInstances(of appPath: String, dataDir: String?) -> [ProcessInfoLite] {
    let target = URL(fileURLWithPath: expand(appPath)).standardizedFileURL.path
    let wanted = dataDir.map { expand($0) }
    return NSWorkspace.shared.runningApplications
        .filter { $0.bundleURL?.standardizedFileURL.path == target }
        .map { ProcessInfoLite(pid: $0.processIdentifier) }
        .filter { $0.userDataDir.map(expand) == wanted }
}
