import Foundation

public let videoISODirectory = "Video ISO Files"
public let audioDirectory = "Audio Source Files"

public final class VideoSource {
    public let index: Int
    public let name: String
    public let kind: String  // Video | Still
    public let mp4: URL?
    public var wav: URL?
    public let relative: String
    public var mp4Info: Mp4Info?

    init(index: Int, name: String, kind: String, mp4: URL?, relative: String) {
        self.index = index; self.name = name; self.kind = kind; self.mp4 = mp4; self.relative = relative
    }
}

/// An ATEM recording folder as the converter understands it.
public final class Recording {
    public let log: Log
    public let root: URL
    public let name: String
    public let frameRate: Rational
    public let frameDuration: Rational
    public let interlaced: Bool
    public let width: Int
    public let height: Int
    public let dropFrame: Bool
    public let startFrames: Int
    public let totalFrames: Int
    public let programMp4: URL?
    public let programInfo: Mp4Info?
    public let sources: [VideoSource]  // header order
    public let audioFiles: [(stem: String, path: URL)]  // every WAV in Audio Source Files, sorted
    public var warnings: [String]

    init(log: Log, root: URL, name: String, frameRate: Rational, interlaced: Bool, width: Int, height: Int, dropFrame: Bool,
         startFrames: Int, totalFrames: Int, programMp4: URL?, programInfo: Mp4Info?, sources: [VideoSource],
         audioFiles: [(stem: String, path: URL)], warnings: [String]) {
        self.log = log; self.root = root; self.name = name; self.frameRate = frameRate; self.frameDuration = Rational(1) / frameRate
        self.interlaced = interlaced; self.width = width; self.height = height; self.dropFrame = dropFrame
        self.startFrames = startFrames; self.totalFrames = totalFrames; self.programMp4 = programMp4; self.programInfo = programInfo
        self.sources = sources; self.audioFiles = audioFiles; self.warnings = warnings
    }

    public var startTime: Rational { startFrames * frameDuration }
    public var duration: Rational { totalFrames * frameDuration }
    public func timecode(_ frame: Int) -> String { Timecode.label(startFrames + frame, fps: frameRate, drop: dropFrame) }
    public func source(_ index: Int) -> VideoSource? { sources.first { $0.index == index } }
}

public extension URL {
    /// Python `Path.resolve()`: symlinks resolved, `/var` becoming `/private/var`, no trailing slash.
    var resolvedPath: String {
        // Foundation's resolvingSymlinksInPath strips /private; realpath(3) keeps it, like Python.
        func realpath(_ path: String) -> String {
            if let resolved = Darwin.realpath(path, nil) {
                defer { free(resolved) }
                return String(cString: resolved)
            }
            let url = URL(fileURLWithPath: path)
            let parent = url.deletingLastPathComponent().path
            if parent == path || parent.isEmpty { return path }
            return realpath(parent) + (parent == "/" ? "" : "/") + url.lastPathComponent
        }
        var path = realpath(self.standardizedFileURL.path)
        if path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
    var stem: String { deletingPathExtension().lastPathComponent }
    /// Python `Path.as_uri()`.
    var fileURI: String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~/")
        return "file://" + (resolvedPath.addingPercentEncoding(withAllowedCharacters: allowed) ?? resolvedPath)
    }
}

/// Python string ordering (by code point).
func pythonLess(_ a: String, _ b: String) -> Bool { a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars) }

/// Resolve a log-relative media path, refusing anything outside the recording folder.
public func containedPath(root: URL, relative: String) throws -> URL {
    let parts = relative.split(separator: "/").map(String.init)
    if relative.isEmpty || relative.hasPrefix("/") || relative.hasPrefix("\\") || parts.contains("..") {
        throw ConversionError("Refusing media path outside the recording folder: \(pyRepr(relative))")
    }
    let rootPath = root.resolvedPath
    let candidate = URL(fileURLWithPath: relative, relativeTo: root).resolvedPath
    if candidate != rootPath && !candidate.hasPrefix(rootPath + "/") {
        throw ConversionError("Refusing media path outside the recording folder: \(pyRepr(relative))")
    }
    return URL(fileURLWithPath: candidate)
}

func isFile(_ url: URL) -> Bool {
    var directory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
}

func isDirectory(_ url: URL) -> Bool {
    var directory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
}

func listWavs(root: URL) throws -> [(stem: String, path: URL)] {
    let folder = root.appendingPathComponent(audioDirectory)
    guard isDirectory(folder) else { return [] }
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    var out: [(stem: String, path: URL)] = []
    for name in names.sorted(by: pythonLess) {
        let entry = folder.appendingPathComponent(name)
        guard entry.pathExtension.lowercased() == "wav", !name.hasPrefix("._"), isFile(entry) else { continue }
        let path = try containedPath(root: root, relative: audioDirectory + "/" + name)
        let stem = entry.stem
        if let position = out.firstIndex(where: { $0.stem == stem }) { out[position] = (stem, path) } else { out.append((stem, path)) }
    }
    return out
}

func recordingStopped(_ event: [String: Any]) -> Bool {
    guard let blocks = JSONValues.list(event["mixEffectBlocks"]) else { return false }
    return blocks.contains { block in
        guard let dict = block as? [String: Any], let value = dict["onAir"], JSONValues.isBool(value) else { return false }
        return (value as! NSNumber).boolValue == false
    }
}

public func openRecording(_ logPath: URL, session: Int? = nil) throws -> Recording {
    let log = try loadLog(logPath, session: session)
    let root = logPath.deletingLastPathComponent()
    let header = log.header
    let mode = try VideoMode.parse(JSONValues.string(header["videoMode"]) ?? "")
    var frameRate = mode.rate
    var master = try Timecode.parse(JSONValues.string(header["masterTimecode"]) ?? "", fps: frameRate)
    var warnings: [String] = []

    var programMp4: URL?
    var programInfo: Mp4Info?
    let isoStems = log.sources.compactMap { entry -> String? in
        guard JSONValues.string(entry.source["type"]) == "Video", let file = JSONValues.string(entry.source["file"]), !file.isEmpty else { return nil }
        return URL(fileURLWithPath: file).stem
    }
    let camPattern = try! NSRegularExpression(pattern: #" CAM \d+$"#)
    let prefixes = isoStems.compactMap { stem -> String? in
        let range = NSRange(stem.startIndex..., in: stem)
        guard camPattern.firstMatch(in: stem, range: range) != nil else { return nil }
        return camPattern.stringByReplacingMatches(in: stem, range: range, withTemplate: "")
    }
    for candidate in [logPath.stem] + prefixes {
        let path = try containedPath(root: root, relative: "\(candidate).mp4")
        if isFile(path) {
            programMp4 = path
            programInfo = try probeMp4(path)
            break
        }
    }
    if programMp4 == nil {
        warnings.append("Program recording \(logPath.stem).mp4 not found; transitions and keys cannot fall back to it.")
    }

    var sources: [VideoSource] = []
    for entry in log.sources {
        let source = entry.source
        guard let kind = JSONValues.string(source["type"]), kind == "Video" || kind == "Still",
              let file = JSONValues.string(source["file"]), !file.isEmpty else { continue }
        let path: URL
        do { path = try containedPath(root: root, relative: file) } catch let error as ConversionError {
            warnings.append(error.message); continue
        }
        let name = JSONValues.truthy(source["name"]) ? JSONValues.pythonString(source["name"]!) : "Input \(entry.index)"
        let item = VideoSource(index: entry.index, name: name, kind: kind, mp4: isFile(path) ? path : nil, relative: file)
        if item.mp4 == nil { warnings.append("\(item.name): file not found: \(file)") }
        if let position = sources.firstIndex(where: { $0.index == entry.index }) { sources[position] = item } else { sources.append(item) }
    }

    let audioFiles = try listWavs(root: root)
    for item in sources where item.kind == "Video" {
        item.wav = audioFiles.first { $0.stem == URL(fileURLWithPath: item.relative).stem }?.path
    }

    var reference = programInfo
    if reference == nil, let first = sources.first(where: { $0.kind == "Video" && $0.mp4 != nil }) {
        reference = try probeMp4(first.mp4!)
    }
    guard let reference else { throw ConversionError("No ISO or program MP4 files were found next to the .drp.") }
    if reference.frameRate != frameRate {
        warnings.append("videoMode says \(formatG(frameRate.doubleValue)) fps but the recording is \(formatG(reference.frameRate.doubleValue)) fps; using the recording.")
        frameRate = reference.frameRate
    }
    master = try Timecode.parse(JSONValues.string(header["masterTimecode"]) ?? "", fps: frameRate)
    let drop = master.drop || reference.dropFrame
    let startFrames = master.frames
    if let tc = reference.timecodeFrames, tc != master.frames {
        warnings.append("Program timecode \(Timecode.label(tc, fps: frameRate, drop: drop)) differs from the log's master timecode; using the log.")
    }
    let totalFrames = reference.frames
    if let endEvent = log.events.last(where: recordingStopped) {
        let end = try Timecode.parse(JSONValues.string(endEvent["masterTimecode"]) ?? "", fps: frameRate).frames
        var logFrames = end - startFrames
        if logFrames < 0 { logFrames += Timecode.framesPerDay(fps: frameRate, drop: master.drop) }
        if abs(logFrames - totalFrames) > 2 {
            warnings.append("The log says the recording is \(logFrames) frames but the media has \(totalFrames); using the media.")
        }
    }
    return Recording(log: log, root: root, name: logPath.stem, frameRate: frameRate, interlaced: mode.interlaced, width: reference.width,
                     height: reference.height, dropFrame: drop, startFrames: startFrames, totalFrames: totalFrames, programMp4: programMp4,
                     programInfo: programInfo, sources: sources, audioFiles: audioFiles, warnings: warnings)
}
