import CoreText
import Foundation

enum FontRegistrar {
    /// Registers a user-imported font for this app process and returns its PostScript names.
    /// Invalid files are ignored here; the importer still retains the file and the UI can report an empty result.
    static func register(url: URL) -> [String] {
        guard ["ttf", "otf"].contains(url.pathExtension.lowercased()) else { return [] }
        var registrationError: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
            return []
        }
        return descriptors.compactMap { descriptor in
            CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
        }
    }
}
