import Foundation

#if os(Linux)
import Glibc

typealias SystemStat = Glibc.stat

extension Glibc.stat {
    // Linux's portable stat interface has no birth time. Unknown stays unknown; ctime is
    // metadata change time and must never stand in for creation time.
    var st_birthtimespec: timespec { timespec(tv_sec: 0, tv_nsec: 0) }
    var st_atimespec: timespec { st_atim }
    var st_mtimespec: timespec { st_mtim }
    var st_ctimespec: timespec { st_ctim }
}

// swift-corelibs-foundation uses Swift ownership instead of Objective-C autorelease pools.
func autoreleasepool<Result>(invoking body: () throws -> Result) rethrows -> Result {
    try body()
}

extension NSString {
    var abbreviatingWithTildeInPath: String {
        let path = self as String
        let home = NSHomeDirectory()
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
#else
import Darwin

typealias SystemStat = Darwin.stat
#endif
