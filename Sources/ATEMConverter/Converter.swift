import Foundation

/// Find the `.drp` from a file or recording folder, as the reference command line does.
public func locateLog(_ target: URL) throws -> URL {
    if isDirectory(target) {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: target.path)) ?? []).sorted(by: pythonLess)
        let candidates = names.filter { name in
            let url = target.appendingPathComponent(name)
            return url.pathExtension.lowercased() == "drp" && isFile(url) && !name.hasPrefix("._")
        }
        if candidates.count != 1 {
            throw ConversionError("Expected exactly one .drp in \(target.lastPathComponent); found \(candidates.count).")
        }
        return URL(fileURLWithPath: target.appendingPathComponent(candidates[0]).resolvedPath)
    }
    if target.pathExtension.lowercased() == "mp4" {
        let sibling = target.deletingPathExtension().appendingPathExtension("drp")
        if isFile(sibling) { return URL(fileURLWithPath: sibling.resolvedPath) }
    }
    if target.pathExtension.lowercased() != "drp" || !isFile(target) {
        throw ConversionError("Select the ATEM .drp file (or its folder): \(target.path)")
    }
    return URL(fileURLWithPath: target.resolvedPath)
}

public enum OutputWriter {
    /// Write the finished XML without following links or truncating recording media.
    public static func write(_ payload: Data, to output: URL, replace: Bool) throws {
        let manager = FileManager.default
        if (try? output.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw ConversionError("Refusing a symbolic link as the output file; choose a new .fcpxml name.")
        }
        if !replace {
            let fd = open(output.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
            if fd < 0 {
                if errno == EEXIST { throw ConversionError("\(output.path) already exists. Use --force to replace it.") }
                throw ConversionError("Could not create \(output.path): \(String(cString: strerror(errno)))")
            }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            do {
                try handle.write(contentsOf: payload)
                try handle.synchronize()
                try handle.close()
            } catch {
                try? manager.removeItem(at: output)
                throw error
            }
            return
        }
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".atem-\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        try payload.write(to: temporary, options: [.atomic])
        _ = try manager.replaceItemAt(output, withItemAt: temporary, backupItemName: nil, options: [])
    }

    /// Paths that must never be overwritten by the output.
    public static func protectedPaths(_ rec: Recording) -> Set<String> {
        var protected: Set<String> = [rec.log.path.resolvedPath]
        for entry in rec.audioFiles { protected.insert(entry.path.resolvedPath) }
        for source in rec.sources { if let mp4 = source.mp4 { protected.insert(mp4.resolvedPath) } }
        if let program = rec.programMp4 { protected.insert(program.resolvedPath) }
        return protected
    }
}
