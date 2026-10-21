import Foundation

/// Helpers that reproduce the Python reference converter's treatment of JSON values.
enum JSONValues {
    static func isBool(_ value: Any?) -> Bool {
        guard let value else { return false }
        return CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
    }

    /// Python `type(x) is int`: a JSON integer, never a bool or a float.
    static func int(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, !isBool(value) else { return nil }
        let type = String(cString: number.objCType)
        if type == "d" || type == "f" { return nil }
        return Int(number.stringValue)
    }

    static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        return value as? String
    }

    static func dict(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    static func list(_ value: Any?) -> [Any]? { value as? [Any] }

    /// Python truthiness.
    static func truthy(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        if let number = value as? NSNumber { return number.doubleValue != 0 }
        if let text = value as? String { return !text.isEmpty }
        if let array = value as? [Any] { return !array.isEmpty }
        if let dictionary = value as? [String: Any] { return !dictionary.isEmpty }
        return true
    }

    /// Python `a == b` for `_index_` lookups (numbers compare by value).
    static func equalIndex(_ a: Any?, _ b: Any?) -> Bool {
        guard let a, let b else { return false }
        if let x = a as? NSNumber, let y = b as? NSNumber { return x == y }
        if let x = a as? String, let y = b as? String { return x == y }
        return false
    }

    /// Python `str(value)` for the handful of places the reference stringifies a JSON value.
    static func pythonString(_ value: Any) -> String {
        if let text = value as? String { return text }
        if isBool(value) { return (value as! NSNumber).boolValue ? "True" : "False" }
        if let number = value as? NSNumber {
            let type = String(cString: number.objCType)
            if type == "d" || type == "f" {
                let d = number.doubleValue
                return d == d.rounded() && abs(d) < 1e16 ? String(format: "%.1f", d) : "\(d)"
            }
            return "\(number.intValue)"
        }
        if value is NSNull { return "None" }
        return "\(value)"
    }
}

/// Apply a sparse ATEM state patch; arrays are keyed by `_index_`.
func mergeState(_ target: inout [String: Any], _ patch: [String: Any]) {
    for (key, value) in patch {
        if let patchDict = JSONValues.dict(value), var existing = JSONValues.dict(target[key]) {
            mergeState(&existing, patchDict)
            target[key] = existing
        } else if let updates = JSONValues.list(value), !updates.isEmpty,
                  updates.allSatisfy({ ($0 as? [String: Any])?["_index_"] != nil }) {
            var items = JSONValues.list(target[key]) ?? []
            for update in updates {
                let update = update as! [String: Any]
                if let position = items.firstIndex(where: { JSONValues.equalIndex(($0 as? [String: Any])?["_index_"], update["_index_"]) }) {
                    var existing = items[position] as! [String: Any]
                    mergeState(&existing, update)
                    items[position] = existing
                } else {
                    items.append(update)
                }
            }
            target[key] = items
        } else {
            target[key] = value
        }
    }
}
