import Foundation

/// What the program output showed during an interval.
public struct Picture: Sendable {
    public var kind: String  // angle | program | gap
    public var key: String = ""
    public var reason: String = ""
    /// Python `Picture.__eq__`: kind and key only.
    func same(as other: Picture) -> Bool { kind == other.kind && key == other.key }
}

public struct Transition: Sendable {
    public let start: Int
    public let end: Int
    public let kind: String
    public let approximated: Bool
}

public struct Cut: Sendable {
    public var start: Int
    public var end: Int
    public var picture: Picture
    public var transitionIn: Transition?
}

public struct EditList: Sendable {
    public let cuts: [Cut]
    public let anglesUsed: [String]
    public let stills: [(id: String, index: Int, name: String, file: String)]
}

func slug(_ text: String) -> String {
    var out = ""
    var pending = false
    for scalar in text.unicodeScalars {
        let ascii = scalar.value < 128 && (scalar.properties.isAlphabetic || ("0"..."9").contains(Character(scalar))) && scalar.value < 128
        let alnum = (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
        _ = ascii
        if alnum {
            if pending { out.append("-"); pending = false }
            out.unicodeScalars.append(scalar)
        } else {
            pending = true
        }
    }
    if pending { out.append("-") }
    return out
}

public func angleID(source: [String: Any], index: Int) -> String {
    if JSONValues.string(source["type"]) == "Still" {
        let file = JSONValues.string(source["file"]) ?? ""
        return "still-\(index)-\(slug(URL(fileURLWithPath: file).stem))"
    }
    return "input-\(index)"
}

private func programBlock(_ state: [String: Any]) -> [String: Any] {
    let blocks = (JSONValues.list(state["mixEffectBlocks"]) ?? []).compactMap { $0 as? [String: Any] }
    return blocks.first { JSONValues.int($0["_index_"]) == 0 } ?? blocks.first ?? [:]
}

private func pictureFor(_ state: [String: Any], selected: Set<String>, fallback: (String) -> Picture) -> Picture {
    let block = programBlock(state)
    var sources: [Int: [String: Any]] = [:]
    for item in JSONValues.list(state["sources"]) ?? [] {
        if let dict = item as? [String: Any], let index = JSONValues.int(dict["_index_"]) { sources[index] = dict }
    }
    var reasons: [String] = []
    if let ftb = block["fadeToBlack"], !(ftb is NSNull) {
        let inactive = (ftb as? String) == "Inactive" || ((ftb as? NSNumber).map { $0.doubleValue == 0 } ?? false)
        if !inactive { reasons.append("fade to black") }
    }
    let upstream = (JSONValues.list(block["upstreamKeys"]) ?? []).compactMap { $0 as? [String: Any] }
    if upstream.contains(where: { JSONValues.truthy($0["onAir"]) }) { reasons.append("upstream key on air") }
    let downstream = (JSONValues.list(state["downstreamKeys"]) ?? []).compactMap { $0 as? [String: Any] }
    if downstream.contains(where: { key in
        if JSONValues.truthy(key["onAir"]) { return true }
        guard let fader = key["faderState"] else { return false }
        if fader is NSNull { return false }
        return (fader as? String) != "Idle"
    }) { reasons.append("downstream key on air") }
    let index = JSONValues.int(block["source"])
    let source = index.flatMap { sources[$0] }
    if source == nil {
        let shown = block["source"].map { $0 is NSNull ? "None" : JSONValues.pythonString($0) } ?? "None"
        reasons.append("unknown program source \(shown)")
    } else if let type = JSONValues.string(source!["type"]), type == "Video" || type == "Still" {
        if !selected.contains(angleID(source: source!, index: index!)) {
            let name = JSONValues.truthy(source!["name"]) ? JSONValues.pythonString(source!["name"]!) : "None"
            reasons.append(type == "Still" ? "\(name) still image not found" : "\(name) not included in the multicam")
        }
    } else {
        let label = JSONValues.truthy(source!["name"]) ? JSONValues.pythonString(source!["name"]!)
            : (source!["type"].map { $0 is NSNull ? "None" : JSONValues.pythonString($0) } ?? "None")
        reasons.append("\(label) generator")
    }
    if !reasons.isEmpty { return fallback(reasons.joined(separator: "; ")) }
    return Picture(kind: "angle", key: angleID(source: source!, index: index!))
}

/// Turn the ATEM event log into cuts and transitions on a frame grid.
public func buildEditList(_ rec: Recording, cameras: [Int], transitions: String = "dissolve") throws -> EditList {
    let fps = rec.frameRate
    let day = Timecode.framesPerDay(fps: fps, drop: rec.dropFrame)
    var state = rec.log.header
    var selected = Set(cameras.map { "input-\($0)" })
    var stills: [(id: String, index: Int, name: String, file: String)] = []
    for entry in rec.log.sources {
        if JSONValues.string(entry.source["type"]) == "Still", let source = rec.source(entry.index), source.mp4 != nil {
            let id = angleID(source: entry.source, index: entry.index)
            selected.insert(id)
            let name = JSONValues.truthy(entry.source["name"]) ? JSONValues.pythonString(entry.source["name"]!) : "Media Player \(entry.index)"
            let file = JSONValues.string(entry.source["file"]) ?? ""
            if let position = stills.firstIndex(where: { $0.id == id }) { stills[position] = (id, entry.index, name, file) } else { stills.append((id, entry.index, name, file)) }
        }
    }
    let allowProgram = rec.programMp4 != nil
    let firstCamera = cameras.first { rec.source($0)?.mp4 != nil }.map { "input-\($0)" }

    func fallback(_ reason: String) -> Picture {
        if allowProgram { return Picture(kind: "program", reason: reason) }
        if let firstCamera {
            let name = rec.source(Int(firstCamera.dropFirst(6))!)!.name
            return Picture(kind: "angle", key: firstCamera, reason: "\(reason); program recording not found, showing \(name)")
        }
        return Picture(kind: "gap", reason: reason)
    }

    // 1. Replay the log into (start, end, state snapshot) intervals on the frame grid.
    var intervals: [(Int, Int, [String: Any])] = []
    var previousRaw = rec.startFrames
    var wraps = 0, cursor = 0
    for event in rec.log.events {
        guard let label = event["masterTimecode"] else { continue }
        let raw = try Timecode.parse(JSONValues.string(label) ?? "", fps: fps).frames
        let delta = raw - previousRaw
        if delta < -(day / 2) {
            wraps += day
        } else if delta < 0 || delta > day / 2 {
            throw ConversionError("Events in the .drp are not in chronological order.")
        }
        previousRaw = raw
        let at = min(max(raw + wraps - rec.startFrames, 0), rec.totalFrames)
        if at > cursor {
            intervals.append((cursor, at, state))
            cursor = at
        }
        mergeState(&state, event)
        if recordingStopped(event) { break }
    }
    if cursor < rec.totalFrames { intervals.append((cursor, rec.totalFrames, state)) }

    // 2. Classify every interval.
    typealias Classified = (start: Int, end: Int, picture: Picture, inTransition: Bool, kind: String)
    var classified: [Classified] = []
    for (start, end, snap) in intervals {
        let block = programBlock(snap)
        let type = block["transitionType"]
        let kind = JSONValues.truthy(type) ? JSONValues.pythonString(type!) : "Mix"
        classified.append((start, end, pictureFor(snap, selected: selected, fallback: fallback), JSONValues.truthy(block["transitionActive"]), kind))
    }

    // Unrelated sparse updates can split an active mix; treat a contiguous run as one transition.
    var joined: [Classified] = []
    for interval in classified {
        if let last = joined.last, interval.inTransition, last.inTransition, last.end == interval.start,
           last.picture.same(as: interval.picture), last.picture.reason == interval.picture.reason, last.kind == interval.kind {
            joined[joined.count - 1] = (last.start, interval.end, last.picture, true, last.kind)
        } else {
            joined.append(interval)
        }
    }
    classified = joined

    // 3. Resolve transition intervals against their neighbors and merge equal pictures.
    var cuts: [Cut] = []
    func append(_ start: Int, _ end: Int, _ picture: Picture, _ transition: Transition? = nil) {
        if let last = cuts.last, transition == nil, last.picture.same(as: picture), last.picture.reason == picture.reason, last.end == start {
            cuts[cuts.count - 1].end = end
        } else if end > start {
            cuts.append(Cut(start: start, end: end, picture: picture, transitionIn: transition))
        }
    }
    for (i, item) in classified.enumerated() {
        let (start, end, picture, inTransition, kind) = item
        if !inTransition { append(start, end, picture); continue }
        let before = cuts.last?.picture
        let after: Picture? = i + 1 < classified.count ? classified[i + 1].picture : nil
        let reason = "ATEM \(kind) transition"
        if let before, let after, before.same(as: after), before.kind == "angle" {
            append(start, end, before)
        } else if before == nil || after == nil || before!.kind != "angle" || after!.kind != "angle" || !before!.reason.isEmpty || !after!.reason.isEmpty {
            let extra = after?.reason ?? ""
            append(start, end, fallback(reason + (extra.isEmpty ? "" : "; \(extra)")))
        } else if transitions == "program" {
            append(start, end, fallback(reason))
        } else {
            var length = end - start
            if transitions == "dissolve" && length % 2 == 1 { length += 1 }
            let half = length / 2
            let cutPoint = start + half
            let nextLength = classified[i + 1].end - classified[i + 1].start
            let last = cuts[cuts.count - 1]
            if transitions == "cut" || last.end - last.start < half || end - start + nextLength < length {
                cuts[cuts.count - 1].end = cutPoint
                append(cutPoint, end, after!)
            } else {
                cuts[cuts.count - 1].end = cutPoint
                append(cutPoint, end, after!, Transition(start: cutPoint - half, end: cutPoint + half, kind: kind, approximated: kind.lowercased() != "mix"))
            }
        }
    }
    cuts = cuts.filter { $0.end > $0.start }
    var used: [String] = []
    for cut in cuts where cut.picture.kind == "angle" && !used.contains(cut.picture.key) { used.append(cut.picture.key) }
    return EditList(cuts: cuts, anglesUsed: used, stills: stills)
}
