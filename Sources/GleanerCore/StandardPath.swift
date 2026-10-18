import Foundation

/// A path in one spelling, whatever is on disk now. `standardizingPath` drops `/private` from
/// `/private/var`, `/private/tmp` and `/private/etc` only while the path exists, so a delivered file
/// that is gone would read as another path than the same file while it was there, and a folder
/// an agent worked in as another folder than the files in it.
public func standardPath(_ path: String) -> String {
    let standard = (path as NSString).standardizingPath
    for root in ["/private/var", "/private/tmp", "/private/etc"] where standard == root || standard.hasPrefix(root + "/") {
        return String(standard.dropFirst("/private".count))
    }
    return standard
}
