import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A file's own icon, as Finder draws it for its type: the extension stays in the file's name, so
/// the icon needs no words of its own. It depends on the apps installed, as it does in Finder.
public struct FileIcon: View {
    public var path: String
    public var folder: Bool
    public var size: CGFloat

    public init(path: String, folder: Bool = false, size: CGFloat) {
        self.path = path
        self.folder = folder
        self.size = size
    }

    public var body: some View {
        Image(nsImage: Self.icon(path, folder: folder))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func icon(_ path: String, folder: Bool) -> NSImage {
        let ext = (path as NSString).pathExtension.lowercased()
        let key = folder ? "/" : ext
        if let image = cache[key] { return image }
        let type = folder ? UTType.folder : UTType(filenameExtension: ext) ?? .data
        let image = NSWorkspace.shared.icon(for: type)
        cache[key] = image
        return image
    }
}
