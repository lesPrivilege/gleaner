#if os(Linux)
// glibc's integer-expression macro is not imported by Swift. POSIX utimensat uses
// this nanosecond sentinel to leave modification time untouched in access-time tests.
let UTIME_OMIT = (1 << 30) - 2
#endif
