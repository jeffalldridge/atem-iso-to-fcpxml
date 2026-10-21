import Foundation

public let converterVersion = "1.2.0"
public let fcpxmlVersion = "1.10"  // Final Cut Pro 10.6 and later; 12.x re-exports as 1.14
public let crossDissolveUID = "FxPlug:4731E73A-8DAC-4113-9A30-AE85B1761265"

/// A tiny element tree whose serialization matches Python's `xml.etree` after `ET.indent`.
final class XMLElement {
    let name: String
    var attributes: [(String, String)]
    var children: [XMLElement] = []
    var text: String?

    init(_ name: String, _ attributes: [(String, String)] = []) {
        self.name = name
        self.attributes = attributes
    }

    @discardableResult
    func child(_ name: String, _ attributes: [(String, String)] = []) -> XMLElement {
        let element = XMLElement(name, attributes)
        children.append(element)
        return element
    }

    static func escapeText(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapeAttribute(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\r": out += "&#13;"
            case "\n": out += "&#10;"
            case "\t": out += "&#09;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    func serialize(level: Int, into out: inout String) {
        let indent = String(repeating: "    ", count: level)
        out += "<\(name)"
        for (key, value) in attributes { out += " \(key)=\"\(XMLElement.escapeAttribute(value))\"" }
        if children.isEmpty && text == nil {
            out += " />"
            return
        }
        out += ">"
        if let text { out += XMLElement.escapeText(text) }
        if !children.isEmpty {
            for child in children {
                out += "\n" + indent + "    "
                child.serialize(level: level + 1, into: &out)
            }
            out += "\n" + indent
        }
        out += "</\(name)>"
    }
}

private func formatName(_ rec: Recording) -> String? {
    let named: [Rational: String] = [Rational(24000, 1001): "2398", Rational(30000, 1001): "2997", Rational(60000, 1001): "5994"]
    var rate = named[rec.frameRate]
    if rate == nil {
        guard rec.frameRate.isInteger else { return nil }
        rate = String(rec.frameRate.numerator)
    }
    let sizes = [(1920, 1080), (1280, 720), (3840, 2160)]
    guard sizes.contains(where: { $0 == (rec.width, rec.height) }) else { return nil }
    return "FFVideoFormat\(rec.height)\(rec.interlaced ? "i" : "p")\(rate!)"
}

public func buildFCPXML(_ plan: Plan) throws -> Data {
    let rec = plan.recording
    let fd = rec.frameDuration
    let t0 = rec.startTime
    let duration = rec.duration
    let tcFormat = rec.dropFrame ? "DF" : "NDF"

    let root = XMLElement("fcpxml", [("version", fcpxmlVersion)])
    let resources = root.child("resources")
    var count = 0
    func nextID() -> String { count += 1; return "r\(count)" }
    var assets: [String: String] = [:]  // resolved path -> id
    var assetTimes: [String: (Rational, Rational)] = [:]
    var stillFormat: String?

    var formatAttrs = [("id", nextID()), ("frameDuration", fd.fcpxml), ("width", String(rec.width)), ("height", String(rec.height)), ("colorSpace", "1-1-1 (Rec. 709)")]
    if let name = formatName(rec) { formatAttrs.append(("name", name)) }
    if rec.interlaced { formatAttrs.append(("fieldOrder", "upper first")) }
    resources.child("format", formatAttrs)
    let formatID = formatAttrs[0].1

    func videoAsset(_ path: URL, _ info: Mp4Info?, still: Bool = false) throws -> (String, Rational, Rational) {
        let key = path.resolvedPath
        if let id = assets[key] { let times = assetTimes[key]!; return (id, times.0, times.1) }
        var start = Rational.zero, length = Rational.zero
        var attrs: [(String, String)]
        if still {
            attrs = [("id", nextID()), ("name", path.lastPathComponent), ("start", "0s"), ("duration", "0s"), ("hasVideo", "1"), ("videoSources", "1")]
            if let size = probeImageSize(path) {
                if stillFormat == nil {
                    stillFormat = nextID()
                    resources.child("format", [("id", stillFormat!), ("name", "FFVideoFormatRateUndefined"), ("width", String(size.width)), ("height", String(size.height)), ("colorSpace", "1-13-1")])
                }
                attrs.append(("format", stillFormat!))
            }
        } else {
            let info = try info ?? probeMp4(path)
            start = (info.timecodeFrames ?? 0) * fd
            length = info.frames * fd
            attrs = [("id", nextID()), ("name", path.lastPathComponent), ("start", start.fcpxml), ("duration", length.fcpxml), ("hasVideo", "1"), ("format", formatID), ("videoSources", "1")]
            if info.hasAudio { attrs += [("hasAudio", "1"), ("audioSources", "1"), ("audioChannels", "2"), ("audioRate", "48000")] }
        }
        let asset = resources.child("asset", attrs)
        asset.child("media-rep", [("kind", "original-media"), ("src", path.fileURI)])
        assets[key] = attrs[0].1
        assetTimes[key] = (start, length)
        return (attrs[0].1, start, length)
    }

    func audioAsset(_ path: URL) throws -> (String, Rational, Rational) {
        let key = path.resolvedPath
        if let id = assets[key] { let times = assetTimes[key]!; return (id, times.0, times.1) }
        let info = try probeWav(path)
        let start = Rational(info.timeReference ?? 0, info.sampleRate)
        let length = info.duration
        let attrs = [("id", nextID()), ("name", path.lastPathComponent), ("start", start.fcpxml), ("duration", length.fcpxml), ("hasAudio", "1"),
                     ("audioSources", "1"), ("audioChannels", String(info.channels)), ("audioRate", String(info.sampleRate))]
        let asset = resources.child("asset", attrs)
        asset.child("media-rep", [("kind", "original-media"), ("src", path.fileURI)])
        assets[key] = attrs[0].1
        assetTimes[key] = (start, length)
        return (attrs[0].1, start, length)
    }

    for angle in plan.angles {
        if let video = angle.video, angle.kind == "still" {
            _ = try videoAsset(video, nil, still: true)
        } else if let video = angle.video {
            let source = angle.sourceIndex.flatMap { rec.source($0) }
            let info = source?.mp4Info ?? (angle.kind == "program" ? rec.programInfo : nil)
            _ = try videoAsset(video, info)
        }
        if let audio = angle.audio { _ = try audioAsset(audio) }
    }

    var dissolveID: String?
    if plan.edit.cuts.contains(where: { $0.transitionIn != nil }) {
        dissolveID = nextID()
        resources.child("effect", [("id", dissolveID!), ("name", "Cross Dissolve"), ("uid", crossDissolveUID)])
    }

    let multicamID = nextID()
    let media = resources.child("media", [("id", multicamID), ("name", "\(plan.name) Multicam")])
    let multicam = media.child("multicam", [("format", formatID), ("tcStart", t0.fcpxml), ("tcFormat", tcFormat)])
    var compounds: [(id: String, name: String, duration: Rational)] = []
    // Angle offsets are relative to the multicam origin; tcStart supplies its displayed clock.
    // Using t0 again hides the clips in the Angle Editor and inflates the browser duration.
    for angle in plan.angles {
        let mcAngle = multicam.child("mc-angle", [("name", angle.name), ("angleID", angle.id)])
        if angle.kind == "program-audio" {
            let (videoID, videoStart, videoLength) = try videoAsset(angle.video!, probeMp4(angle.video!))
            mcAngle.child("asset-clip", [("ref", videoID), ("name", angle.name), ("offset", "0s"), ("start", videoStart.fcpxml), ("duration", min(duration, videoLength).fcpxml), ("srcEnable", "audio"), ("audioRole", "dialogue")])
        } else if angle.kind == "camera" || angle.kind == "program" {
            let (videoID, videoStart, videoLength) = try videoAsset(angle.video!, nil)
            let clipLength = min(duration, videoLength)
            if let audio = angle.audio {
                // Final Cut keeps a connected audio clip inside a multicam angle only through a compound clip.
                let compoundID = nextID()
                let compoundName = "\(angle.name) - ISO + WAV"
                compounds.append((compoundID, compoundName, clipLength))
                let compound = resources.child("media", [("id", compoundID), ("name", compoundName)])
                let sequence = compound.child("sequence", [("format", formatID), ("duration", clipLength.fcpxml), ("tcStart", "0s"), ("tcFormat", tcFormat), ("audioLayout", "stereo"), ("audioRate", "48k")])
                let spine = sequence.child("spine")
                let clip = spine.child("clip", [("name", angle.name), ("offset", "0s"), ("start", "0s"), ("duration", clipLength.fcpxml), ("format", formatID), ("tcFormat", tcFormat)])
                clip.child("video", [("ref", videoID), ("offset", "0s"), ("start", videoStart.fcpxml), ("duration", clipLength.fcpxml)])
                let (audioID, audioStart, audioLength) = try audioAsset(audio)
                clip.child("asset-clip", [("ref", audioID), ("lane", "-1"), ("offset", "0s"), ("name", audio.stem), ("start", audioStart.fcpxml), ("duration", min(clipLength, audioLength).fcpxml), ("audioRole", "dialogue")])
                mcAngle.child("ref-clip", [("ref", compoundID), ("name", compoundName), ("offset", "0s"), ("start", "0s"), ("duration", clipLength.fcpxml)])
            } else if angle.kind == "camera" {
                // A native asset-clip retains MP4 audio without unsupported connected items in the angle.
                mcAngle.child("asset-clip", [("ref", videoID), ("name", angle.name), ("offset", "0s"), ("start", videoStart.fcpxml), ("duration", clipLength.fcpxml), ("audioRole", "dialogue")])
            } else {
                let clip = mcAngle.child("clip", [("name", angle.name), ("offset", "0s"), ("start", "0s"), ("duration", clipLength.fcpxml), ("format", formatID), ("tcFormat", tcFormat)])
                clip.child("video", [("ref", videoID), ("offset", "0s"), ("start", videoStart.fcpxml), ("duration", clipLength.fcpxml)])
            }
        } else if angle.kind == "still" {
            let (stillID, _, _) = try videoAsset(angle.video!, nil, still: true)
            let compoundID = nextID()
            let compoundName = "\(angle.name) - Still"
            compounds.append((compoundID, compoundName, duration))
            let compound = resources.child("media", [("id", compoundID), ("name", compoundName)])
            let sequence = compound.child("sequence", [("format", formatID), ("duration", duration.fcpxml), ("tcStart", "0s"), ("tcFormat", tcFormat), ("audioLayout", "stereo"), ("audioRate", "48k")])
            let spine = sequence.child("spine")
            // Keep the rate-undefined still's clip/video shape inside a shared, editable compound.
            let clip = spine.child("clip", [("name", angle.video!.stem), ("offset", "0s"), ("start", "0s"), ("duration", duration.fcpxml), ("format", formatID), ("tcFormat", tcFormat)])
            clip.child("video", [("ref", stillID), ("offset", "0s"), ("start", "0s"), ("duration", duration.fcpxml)])
            mcAngle.child("ref-clip", [("ref", compoundID), ("name", compoundName), ("offset", "0s"), ("start", "0s"), ("duration", duration.fcpxml)])
        } else {
            let (audioID, audioStart, audioLength) = try audioAsset(angle.audio!)
            mcAngle.child("asset-clip", [("ref", audioID), ("name", angle.name), ("offset", "0s"), ("start", audioStart.fcpxml), ("duration", min(duration, audioLength).fcpxml), ("audioRole", "dialogue")])
        }
    }

    var container = root
    if let event = plan.event, !event.isEmpty { container = root.child("event", [("name", event)]) }
    let firstCamera = plan.angles.first { $0.kind == "camera" }?.id ?? plan.angles[0].id

    func mcSources(_ parent: XMLElement, _ videoAngle: String) {
        if videoAngle == plan.mainAudioAngle {
            parent.child("mc-source", [("angleID", videoAngle), ("srcEnable", "all")])
        } else {
            parent.child("mc-source", [("angleID", videoAngle), ("srcEnable", "video")])
            parent.child("mc-source", [("angleID", plan.mainAudioAngle), ("srcEnable", "audio")])
        }
    }

    // Browser compounds share the angle resources, so edits propagate into the live edit.
    // Let Final Cut assign UIDs and present its native matching-name import dialog.
    let browser = container.child("mc-clip", [("ref", multicamID), ("name", "\(plan.name) Multicam"), ("start", t0.fcpxml), ("duration", duration.fcpxml)])
    mcSources(browser, firstCamera)
    for compound in compounds {
        container.child("ref-clip", [("ref", compound.id), ("name", compound.name), ("start", "0s"), ("duration", compound.duration.fcpxml)])
    }
    var browserAssets: Set<String> = []
    for angle in plan.angles {
        for path in [angle.video, angle.audio] {
            guard let path else { continue }
            let key = path.resolvedPath
            guard browserAssets.insert(key).inserted else { continue }
            if angle.kind == "still" {
                // A still has no finite source duration; give its browser clip the recording range.
                let clip = container.child("clip", [("name", path.stem), ("start", "0s"), ("duration", duration.fcpxml), ("format", formatID), ("tcFormat", tcFormat)])
                clip.child("video", [("ref", assets[key]!), ("offset", "0s"), ("start", "0s"), ("duration", duration.fcpxml)])
                continue
            }
            let times = assetTimes[key]!
            var attrs = [("ref", assets[key]!), ("name", path.stem), ("start", times.0.fcpxml), ("duration", times.1.fcpxml)]
            if path == angle.video { attrs += [("format", formatID), ("tcFormat", tcFormat)] } else { attrs.append(("audioRole", "dialogue")) }
            container.child("asset-clip", attrs)
        }
    }

    let project = container.child("project", [("name", "\(plan.name) Live Edit")])
    let sequence = project.child("sequence", [("format", formatID), ("duration", duration.fcpxml), ("tcStart", "0s"), ("tcFormat", tcFormat), ("audioLayout", "stereo"), ("audioRate", "48k")])
    let notes = ["Converted from \(rec.name).drp by atem-iso-to-fcpxml \(converterVersion)."] + plan.summary().dropFirst()
    sequence.child("note").text = notes.joined(separator: "\n")
    let spine = sequence.child("spine")
    let programAsset = rec.programMp4.flatMap { assets[$0.resolvedPath] }
    for cut in plan.edit.cuts {
        let offset = cut.start * fd
        let length = (cut.end - cut.start) * fd
        if let transition = cut.transitionIn, let dissolveID {
            let element = spine.child("transition", [("name", "Cross Dissolve"), ("offset", (transition.start * fd).fcpxml), ("duration", ((transition.end - transition.start) * fd).fcpxml)])
            element.child("filter-video", [("ref", dissolveID), ("name", "Cross Dissolve")])
        }
        let clip: XMLElement
        if cut.picture.kind == "angle" || (cut.picture.kind == "program" && programAsset != nil) {
            clip = spine.child("mc-clip", [("ref", multicamID), ("name", "\(plan.name) Multicam"), ("offset", offset.fcpxml), ("start", (t0 + offset).fcpxml), ("duration", length.fcpxml)])
            mcSources(clip, cut.picture.kind == "angle" ? cut.picture.key : "program")
        } else {
            clip = spine.child("gap", [("name", "Gap"), ("offset", offset.fcpxml), ("start", (t0 + offset).fcpxml), ("duration", length.fcpxml)])
        }
        if cut.picture.kind != "angle" || !cut.picture.reason.isEmpty {
            let suffix = cut.picture.kind == "program" ? " (program recording)" : cut.picture.kind == "gap" ? " (no program recording or camera found)" : ""
            clip.child("marker", [("start", (t0 + offset).fcpxml), ("duration", fd.fcpxml), ("value", "ATEM: \(cut.picture.reason)\(suffix)")])
        } else if let transition = cut.transitionIn, transition.approximated {
            clip.child("marker", [("start", (t0 + offset).fcpxml), ("duration", fd.fcpxml), ("value", "ATEM \(transition.kind) transition shown as a cross dissolve")])
        }
    }

    var body = ""
    root.serialize(level: 0, into: &body)
    let payload = Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE fcpxml>\n\n" + body + "\n").utf8)
    // Match the Python entry point: reject invalid XML characters before opening an output file.
    let parser = XMLParser(data: payload)
    parser.shouldResolveExternalEntities = false
    guard parser.parse() else {
        throw ConversionError("The recording contains text that cannot be written as XML: \(parser.parserError?.localizedDescription ?? "invalid XML").")
    }
    return payload
}
