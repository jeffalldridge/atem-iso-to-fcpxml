import Foundation

public let maxLogBytes = 16 * 1024 * 1024

/// One recording session of the ATEM switcher log: a header snapshot plus sparse updates.
public struct Log {
    public let path: URL
    public let header: [String: Any]
    public let events: [[String: Any]]

    /// Sources in header order, keyed by `_index_`.
    public var sources: [(index: Int, source: [String: Any])] {
        var seen: [Int: Int] = [:]
        var out: [(Int, [String: Any])] = []
        for item in JSONValues.list(header["sources"]) ?? [] {
            guard let dict = item as? [String: Any], let index = JSONValues.int(dict["_index_"]) else { continue }
            if let position = seen[index] { out[position] = (index, dict) } else { seen[index] = out.count; out.append((index, dict)) }
        }
        return out.map { (index: $0.0, source: $0.1) }
    }

    public func source(_ index: Int) -> [String: Any]? { sources.first { $0.index == index }?.source }
}

func validateStateShape(_ row: [String: Any]) throws {
    for key in ["masterTimecode", "videoMode"] {
        if let value = row[key], !(value is String) { throw ConversionError("The log field \(key) must be text.") }
    }
    for key in ["sources", "mixEffectBlocks", "downstreamKeys", "upstreamKeys"] {
        guard let value = row[key] else { continue }
        guard let items = JSONValues.list(value) else { throw ConversionError("The log field \(key) must be an array.") }
        var indices = Set<Int>()
        for item in items {
            guard let dict = item as? [String: Any], let index = JSONValues.int(dict["_index_"]) else {
                throw ConversionError("Each \(key) entry must have an integer _index_.")
            }
            if indices.contains(index) { throw ConversionError("Duplicate _index_ in log field \(key).") }
            indices.insert(index)
            for field in ["file", "name", "type"] {
                if let fieldValue = dict[field], !(fieldValue is String) {
                    throw ConversionError("The log field \(key).\(field) must be text.")
                }
            }
            if key == "mixEffectBlocks" { try validateStateShape(dict) }
        }
    }
}

/// Read the ATEM log. A log can hold several sessions if the same name was recorded twice.
public func loadLog(_ path: URL, session: Int? = nil) throws -> Log {
    let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
    if let size = attributes[.size] as? Int, size > maxLogBytes {
        throw ConversionError("The .drp is larger than 16 MiB; that is not an ATEM switcher log.")
    }
    let handle = try FileHandle(forReadingFrom: path)
    defer { try? handle.close() }
    let raw = try handle.read(upToCount: maxLogBytes + 1) ?? Data()
    if raw.count > maxLogBytes { throw ConversionError("The .drp exceeds the 16 MiB limit.") }
    if raw.starts(with: [0x50, 0x4B]) {
        throw ConversionError("This .drp is a DaVinci Resolve project archive, not the ATEM switcher log. Use the .drp the ATEM wrote next to its recording.")
    }
    var text: String
    if raw.starts(with: [0xEF, 0xBB, 0xBF]), let decoded = String(data: raw.dropFirst(3), encoding: .utf8) {
        text = decoded
    } else if let decoded = String(data: raw, encoding: .utf8) {
        text = decoded
    } else {
        throw ConversionError("The .drp is not an ATEM newline-delimited JSON log.")
    }
    text = text.replacingOccurrences(of: "\r\n", with: "\n")
    var rows: [[String: Any]] = []
    for line in text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r" }) {
        if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: Data(line.utf8), options: [.fragmentsAllowed])
        } catch {
            throw ConversionError("The .drp is not an ATEM newline-delimited JSON log.")
        }
        guard let dict = object as? [String: Any] else { throw ConversionError("The .drp contains no JSON objects.") }
        rows.append(dict)
    }
    if rows.isEmpty { throw ConversionError("The .drp contains no JSON objects.") }
    var sessions: [[[String: Any]]] = []
    for row in rows {
        try validateStateShape(row)
        if row["sources"] != nil && row["videoMode"] != nil {
            sessions.append([row])
        } else if !sessions.isEmpty {
            sessions[sessions.count - 1].append(row)
        }
    }
    if sessions.isEmpty { throw ConversionError("The first line of the .drp is missing sources, masterTimecode or videoMode.") }
    if sessions.count > 1 && session == nil {
        throw ConversionError("This .drp holds \(sessions.count) recording sessions. Pick one with --session 1 to --session \(sessions.count), then check that the ISO file names match that session.", sessionCount: sessions.count)
    }
    let selected = session ?? 1
    guard selected >= 1 && selected <= sessions.count else {
        throw ConversionError("--session must be between 1 and \(sessions.count).")
    }
    let chosen = sessions[selected - 1]
    let header = chosen[0]
    if header["masterTimecode"] == nil { throw ConversionError("The session header is missing masterTimecode.") }
    if let version = header["version"], !(version is NSNull) {
        guard JSONValues.int(version) == 1 else {
            throw ConversionError("Unsupported ATEM log version \(pythonReprValue(version)); only version 1 is known.")
        }
    }
    return Log(path: path, header: header, events: Array(chosen.dropFirst()))
}

func pythonReprValue(_ value: Any) -> String {
    if let text = value as? String { return pyRepr(text) }
    return JSONValues.pythonString(value)
}
