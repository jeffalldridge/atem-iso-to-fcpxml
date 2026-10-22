import Foundation

public struct Angle: Sendable {
    public let id: String
    public let name: String
    public let kind: String  // camera | still | program | program-audio | audio
    public let video: URL?
    public let audio: URL?
    public let sourceIndex: Int?
}

public struct Plan {
    public let recording: Recording
    public let edit: EditList
    public let angles: [Angle]
    public let mainAudioAngle: String
    public let name: String
    public let event: String?
    public let transitions: String

    public func summary() -> [String] {
        let rec = recording
        var lines = ["Recording: \(rec.name) (\(rec.width)x\(rec.height), \(formatG(rec.frameRate.doubleValue)) fps, \(rec.totalFrames) frames, \(rec.timecode(0)) to \(rec.timecode(rec.totalFrames)))"]
        for angle in angles {
            var detail = angle.kind
            if let video = angle.video, let audio = angle.audio { detail = "\(video.lastPathComponent) + \(audio.lastPathComponent)" }
            else if let video = angle.video { detail = video.lastPathComponent }
            else if let audio = angle.audio { detail = audio.lastPathComponent }
            let tag = angle.id == mainAudioAngle ? "  (main soundtrack)" : ""
            lines.append("Angle \(angle.name): \(detail)\(tag)")
        }
        let dissolves = edit.cuts.filter { $0.transitionIn != nil }.count
        let fallbacks = edit.cuts.filter { $0.picture.kind != "angle" || !$0.picture.reason.isEmpty }
        lines.append("Timeline: \(edit.cuts.count) clips, \(dissolves) cross dissolves, \(fallbacks.count) stand-in sections")
        for cut in fallbacks { lines.append("  \(rec.timecode(cut.start))–\(rec.timecode(cut.end)): \(cut.picture.reason)") }
        for cut in edit.cuts {
            if let t = cut.transitionIn, t.approximated { lines.append("  \(rec.timecode(t.start)): ATEM \(t.kind) transition shown as a cross dissolve") }
        }
        for warning in rec.warnings { lines.append("Warning: \(warning)") }
        return lines
    }
}

/// Find a WAV by exact filename, stem, or suffix such as `MIC 1`.
public func resolveAudio(_ rec: Recording, _ label: String?) throws -> URL? {
    guard let label, !label.isEmpty else { return nil }
    let wanted = label.trimmingCharacters(in: .whitespacesAndNewlines)
    for entry in rec.audioFiles where wanted == entry.path.lastPathComponent || wanted == entry.stem { return entry.path }
    let matches = rec.audioFiles.filter { $0.stem.lowercased().hasSuffix(" " + wanted.lowercased()) }.map { $0.path }
    if matches.count == 1 { return matches[0] }
    if matches.isEmpty {
        throw ConversionError("No WAV named \(pyRepr(label)) in \(audioDirectory). Available: \(rec.audioFiles.map { $0.stem }.joined(separator: ", ")).")
    }
    throw ConversionError("\(pyRepr(label)) matches several WAVs: \(matches.map { $0.lastPathComponent }.joined(separator: ", ")).")
}

public struct PlanOptions: Sendable {
    public var cameras: [Int]? = nil
    public var audio: String? = nil
    public var extraAudio: [String]? = nil
    public var transitions = "dissolve"
    public var name: String? = nil
    public var event: String? = nil  // nil: same as name; "" : no event element
    public var includeProgram = false
    public var liveMix = false
    public init() {}
}

/// The program mix is embedded in both Program and ISO MP4s.
public func liveMixSource(_ rec: Recording, cameras: [Int]) throws -> URL? {
    let candidates = [rec.programMp4].compactMap { $0 } + cameras.compactMap { rec.source($0)?.mp4 }
    for path in candidates where try probeMp4(path).hasAudio { return path }
    return nil
}

public func makePlan(_ rec: Recording, _ options: PlanOptions = PlanOptions()) throws -> Plan {
    if options.liveMix && options.audio != nil {
        throw ConversionError("Choose either --live-mix or --audio, not both.")
    }
    guard ["dissolve", "cut", "program"].contains(options.transitions) else {
        throw ConversionError("transitions must be dissolve, cut or program.")
    }
    let available = rec.sources.filter { $0.kind == "Video" && $0.mp4 != nil }.map { $0.index }.sorted()
    if available.isEmpty { throw ConversionError("No camera ISO files were found in \(videoISODirectory).") }
    var cameras: [Int]
    if let chosen = options.cameras {
        cameras = chosen
    } else {
        let probe = try buildEditList(rec, cameras: available, transitions: "cut")
        let used = available.filter { probe.anglesUsed.contains("input-\($0)") }
        cameras = used.isEmpty ? Array(available.prefix(1)) : used
    }
    var deduped: [Int] = []
    for camera in cameras where !deduped.contains(camera) { deduped.append(camera) }
    cameras = deduped
    if cameras.isEmpty { throw ConversionError("Choose at least one camera input.") }
    let missing = cameras.filter { !available.contains($0) }
    if !missing.isEmpty {
        throw ConversionError("These inputs have no ISO recording: \(missing.map(String.init).joined(separator: ", ")). Available: \(available.map(String.init).joined(separator: ", ")).")
    }

    let edit = try buildEditList(rec, cameras: cameras, transitions: options.transitions)
    var angles: [Angle] = []
    for index in cameras {
        let source = rec.source(index)!
        source.mp4Info = try probeMp4(source.mp4!)
        if source.wav == nil {
            let fallback = source.mp4Info!.hasAudio ? "using the MP4's compressed audio." : "the MP4 has no audio either."
            rec.warnings.append("\(source.name): no WAV named '\(URL(fileURLWithPath: source.relative).stem).wav' in \(audioDirectory); \(fallback)")
        } else {
            _ = try probeWav(source.wav!)
        }
        angles.append(Angle(id: "input-\(index)", name: source.name, kind: "camera", video: source.mp4, audio: source.wav, sourceIndex: index))
    }
    for still in edit.stills where edit.anglesUsed.contains(still.id) {
        angles.append(Angle(id: still.id, name: still.name, kind: "still", video: rec.source(still.index)!.mp4, audio: nil, sourceIndex: still.index))
    }
    if let program = rec.programMp4, options.includeProgram || edit.cuts.contains(where: { $0.picture.kind == "program" }) {
        angles.append(Angle(id: "program", name: "Program", kind: "program", video: program, audio: nil, sourceIndex: nil))
    }

    var mainPath = try options.audio.flatMap { try resolveAudio(rec, $0) }
    if mainPath == nil && !options.liveMix {
        let first = rec.source(cameras[0])!
        mainPath = first.wav ?? rec.audioFiles.first?.path
    }
    let cameraWavs = Set(angles.compactMap { $0.audio?.resolvedPath })
    var extras: [URL]
    if let labels = options.extraAudio {
        extras = try labels.map { try resolveAudio(rec, $0)! }
    } else {
        let paired = Set(rec.sources.filter { $0.kind == "Video" }.map { URL(fileURLWithPath: $0.relative).stem })
        extras = rec.audioFiles.filter { !paired.contains($0.stem) }.map { $0.path }
    }
    if let main = mainPath, !cameraWavs.contains(main.resolvedPath), !extras.contains(where: { $0.resolvedPath == main.resolvedPath }) {
        extras.insert(main, at: 0)
    }
    for path in extras {
        if cameraWavs.contains(path.resolvedPath) || angles.contains(where: { $0.audio?.resolvedPath == path.resolvedPath }) { continue }
        _ = try probeWav(path)
        var label = path.stem
        let prefix = rec.name + " "
        if label.hasPrefix(prefix) && label.count > prefix.count { label = String(label.dropFirst(prefix.count)) }
        let base = "audio-" + slug(path.stem).trimmingCharacters(in: CharacterSet(charactersIn: "-")).lowercased()
        var unique = base
        var suffix = 2
        while angles.contains(where: { $0.id == unique }) { unique = "\(base)-\(suffix)"; suffix += 1 }
        angles.append(Angle(id: unique, name: label, kind: "audio", video: nil, audio: path, sourceIndex: nil))
    }

    var mainAngle = angles.first { mainPath != nil && $0.audio?.resolvedPath == mainPath!.resolvedPath }?.id
    if mainAngle == nil {
        guard let mix = try liveMixSource(rec, cameras: cameras) else {
            throw ConversionError("No recorded live mix audio was found in the Program or selected camera MP4s. Choose a WAV soundtrack or restore the recording's audio files.")
        }
        angles.append(Angle(id: "atem-live-mix", name: "ATEM live mix", kind: "program-audio", video: mix, audio: nil, sourceIndex: nil))
        mainAngle = "atem-live-mix"
        if !options.liveMix { rec.warnings.append("No WAV files found; the main soundtrack is the recorded ATEM live mix.") }
    }
    for angle in angles {
        if let audio = angle.audio {
            let info = try probeWav(audio)
            if info.timeReference == nil {
                rec.warnings.append("\(audio.lastPathComponent): no Broadcast Wave time reference; assuming a common recording start. Check sync.")
            } else if (Rational(info.timeReference!, info.sampleRate) - rec.startTime).magnitude > rec.frameDuration {
                rec.warnings.append("\(audio.lastPathComponent): start time differs from the log; automatic offset correction is not supported. Check sync in Final Cut.")
            }
            if info.duration + rec.frameDuration < rec.duration {
                rec.warnings.append("\(audio.lastPathComponent): audio ends before the project; check the tail for silence.")
            }
        }
        if let video = angle.video, angle.kind != "still" {
            let info = try probeMp4(video)
            if info.frameRate != rec.frameRate || info.width != rec.width || info.height != rec.height {
                throw ConversionError("\(video.lastPathComponent): video format differs from the recording. Mixed formats are not supported.")
            }
            if let tc = info.timecodeFrames, tc != rec.startFrames {
                rec.warnings.append("\(video.lastPathComponent): start time differs from the log; automatic offset correction is not supported. Check sync in Final Cut.")
            }
            if info.frames < rec.totalFrames {
                rec.warnings.append("\(video.lastPathComponent): video ends before the project; check the tail for missing picture.")
            }
        }
    }
    let base = options.name ?? rec.root.lastPathComponent
    return Plan(recording: rec, edit: edit, angles: angles, mainAudioAngle: mainAngle!, name: base,
                event: options.event ?? base, transitions: options.transitions)
}
