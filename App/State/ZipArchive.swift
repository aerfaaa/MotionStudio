import Foundation

/// Small ZIP reader/writer for MotionStudio's portable project and image-sequence packages.
/// It deliberately uses the ZIP "store" method (no compression) to avoid third-party dependencies.
enum ZipArchive {
    enum ArchiveError: LocalizedError {
        case tooManyEntries
        case entryTooLarge(String)
        case malformed
        case unsupportedCompression(String)
        case unsafePath(String)
        case checksumMismatch(String)

        var errorDescription: String? {
            switch self {
            case .tooManyEntries: return "This package contains too many files."
            case .entryTooLarge(let name): return "The file \(name) is too large for this ZIP writer."
            case .malformed: return "The ZIP package is damaged or unsupported."
            case .unsupportedCompression(let name): return "The file \(name) uses unsupported ZIP compression."
            case .unsafePath(let name): return "The package contains an unsafe file path: \(name)."
            case .checksumMismatch(let name): return "The file \(name) failed its integrity check."
            }
        }
    }

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var entry = UInt32(value)
        for _ in 0..<8 { entry = (entry & 1) != 0 ? (entry >> 1) ^ 0xEDB8_8320 : entry >> 1 }
        return entry
    }

    private struct CentralEntry {
        var name: Data
        var crc: UInt32
        var size: UInt32
        var offset: UInt32
        var isDirectory: Bool
    }

    static func create(fromDirectory directory: URL, to destination: URL) throws {
        let fm = FileManager.default
        let base = directory.standardizedFileURL
        guard let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            throw ArchiveError.malformed
        }
        let urls = enumerator.compactMap { $0 as? URL }.sorted { $0.path < $1.path }
        guard urls.count <= Int(UInt16.max) else { throw ArchiveError.tooManyEntries }
        try? fm.removeItem(at: destination)
        guard fm.createFile(atPath: destination.path, contents: nil) else { throw ArchiveError.malformed }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var centralData = Data()
        var central: [CentralEntry] = []

        for url in urls {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = values.isDirectory == true
            var relative = String(url.standardizedFileURL.path.dropFirst(base.path.count))
            if relative.hasPrefix("/") { relative.removeFirst() }
            if relative.isEmpty { continue }
            if isDirectory && !relative.hasSuffix("/") { relative += "/" }
            let nameData = Data(relative.utf8)
            guard nameData.count <= Int(UInt16.max) else { throw ArchiveError.entryTooLarge(relative) }
            let fileData = isDirectory ? Data() : try Data(contentsOf: url, options: [.mappedIfSafe])
            guard fileData.count <= Int(UInt32.max), handle.offsetInFile <= UInt64(UInt32.max) else {
                throw ArchiveError.entryTooLarge(relative)
            }
            let crc = crc32(fileData)
            let offset = UInt32(handle.offsetInFile)
            var header = Data()
            header.appendLE(UInt32(0x04034b50))
            header.appendLE(UInt16(20))
            header.appendLE(UInt16(0x0800)) // UTF-8 file names
            header.appendLE(UInt16(0)) // store, no compression
            header.appendLE(UInt16(0)); header.appendLE(UInt16(0))
            header.appendLE(crc)
            header.appendLE(UInt32(fileData.count)); header.appendLE(UInt32(fileData.count))
            header.appendLE(UInt16(nameData.count)); header.appendLE(UInt16(0))
            header.append(nameData)
            try handle.write(contentsOf: header)
            if !fileData.isEmpty { try handle.write(contentsOf: fileData) }
            central.append(CentralEntry(name: nameData, crc: crc, size: UInt32(fileData.count), offset: offset, isDirectory: isDirectory))
        }

        guard handle.offsetInFile <= UInt64(UInt32.max) else { throw ArchiveError.entryTooLarge("archive") }
        let centralOffset = UInt32(handle.offsetInFile)
        for entry in central {
            centralData.appendLE(UInt32(0x02014b50))
            centralData.appendLE(UInt16(20)); centralData.appendLE(UInt16(20))
            centralData.appendLE(UInt16(0x0800)); centralData.appendLE(UInt16(0))
            centralData.appendLE(UInt16(0)); centralData.appendLE(UInt16(0))
            centralData.appendLE(entry.crc)
            centralData.appendLE(entry.size); centralData.appendLE(entry.size)
            centralData.appendLE(UInt16(entry.name.count)); centralData.appendLE(UInt16(0)); centralData.appendLE(UInt16(0))
            centralData.appendLE(UInt16(0)); centralData.appendLE(UInt16(0))
            centralData.appendLE(UInt32(entry.isDirectory ? 0x10 : 0))
            centralData.appendLE(entry.offset)
            centralData.append(entry.name)
        }
        guard central.count <= Int(UInt16.max), centralData.count <= Int(UInt32.max) else { throw ArchiveError.tooManyEntries }
        try handle.write(contentsOf: centralData)
        var end = Data()
        end.appendLE(UInt32(0x06054b50))
        end.appendLE(UInt16(0)); end.appendLE(UInt16(0))
        end.appendLE(UInt16(central.count)); end.appendLE(UInt16(central.count))
        end.appendLE(UInt32(centralData.count)); end.appendLE(centralOffset)
        end.appendLE(UInt16(0))
        try handle.write(contentsOf: end)
    }

    static func extract(from archiveURL: URL, to destination: URL) throws {
        let data = try Data(contentsOf: archiveURL, options: [.mappedIfSafe])
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var cursor = 0
        while cursor + 4 <= data.count {
            guard let signature: UInt32 = data.readLE(at: cursor) else { throw ArchiveError.malformed }
            if signature == 0x02014b50 || signature == 0x06054b50 { break }
            guard signature == 0x04034b50, cursor + 30 <= data.count else { throw ArchiveError.malformed }
            guard let flags: UInt16 = data.readLE(at: cursor + 6),
                  let method: UInt16 = data.readLE(at: cursor + 8),
                  let crc: UInt32 = data.readLE(at: cursor + 14),
                  let compressedSize: UInt32 = data.readLE(at: cursor + 18),
                  let uncompressedSize: UInt32 = data.readLE(at: cursor + 22),
                  let nameLength: UInt16 = data.readLE(at: cursor + 26),
                  let extraLength: UInt16 = data.readLE(at: cursor + 28) else { throw ArchiveError.malformed }
            guard flags & 0x0008 == 0 else { throw ArchiveError.malformed } // no data-descriptor entries
            guard method == 0 else {
                let nameStart = cursor + 30
                let name = String(data: data.subdata(in: nameStart..<min(data.count, nameStart + Int(nameLength))), encoding: .utf8) ?? "file"
                throw ArchiveError.unsupportedCompression(name)
            }
            guard compressedSize == uncompressedSize else { throw ArchiveError.malformed }
            let nameStart = cursor + 30
            let dataStart = nameStart + Int(nameLength) + Int(extraLength)
            let dataEnd = dataStart + Int(compressedSize)
            guard dataStart >= nameStart, dataEnd <= data.count,
                  let name = String(data: data.subdata(in: nameStart..<(nameStart + Int(nameLength))), encoding: .utf8) else {
                throw ArchiveError.malformed
            }
            guard isSafe(relativePath: name) else { throw ArchiveError.unsafePath(name) }
            let payload = data.subdata(in: dataStart..<dataEnd)
            guard crc32(payload) == crc else { throw ArchiveError.checksumMismatch(name) }
            let target = destination.appendingPathComponent(name).standardizedFileURL
            guard target.path == destination.standardizedFileURL.path || target.path.hasPrefix(destination.standardizedFileURL.path + "/") else {
                throw ArchiveError.unsafePath(name)
            }
            if name.hasSuffix("/") {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try payload.write(to: target, options: .atomic)
            }
            cursor = dataEnd
        }
        guard FileManager.default.fileExists(atPath: destination.appendingPathComponent("project.json").path) else {
            throw ArchiveError.malformed
        }
    }

    private static func isSafe(relativePath: String) -> Bool {
        guard !relativePath.hasPrefix("/"), !relativePath.contains("\\") else { return false }
        return !relativePath.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0 == "." }
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crcTable[index]
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func readLE<T: FixedWidthInteger>(at offset: Int) -> T? {
        guard offset >= 0, offset + MemoryLayout<T>.size <= count else { return nil }
        var value: T = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { copyBytes(to: $0, from: offset..<(offset + MemoryLayout<T>.size)) }
        return T(littleEndian: value)
    }
}
