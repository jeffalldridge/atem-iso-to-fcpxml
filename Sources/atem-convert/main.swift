import Foundation
import ATEMConverter

// Mirrors the reference Python command line so outputs can be compared byte for byte.
var arguments = Array(CommandLine.arguments.dropFirst())
var input: String?
var output: String?
var options = PlanOptions()
var session: Int?
var force = false, dryRun = false, noEvent = false
var extras: [String] = []
var extrasGiven = false

func value(_ flag: String) -> String {
    guard !arguments.isEmpty else { fputs("Error: \(flag) needs a value\n", stderr); exit(2) }
    return arguments.removeFirst()
}

while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "-o", "--output": output = value(argument)
    case "--cameras": options.cameras = value(argument).split(whereSeparator: { $0 == "," || $0 == " " }).map { Int($0)! }
    case "--audio": options.audio = value(argument)
    case "--extra-audio": extras.append(value(argument)); extrasGiven = true
    case "--no-extra-audio": extrasGiven = true; extras = []
    case "--transitions": options.transitions = value(argument)
    case "--program-angle": options.includeProgram = true
    case "--name": options.name = value(argument)
    case "--event": options.event = value(argument)
    case "--no-event": noEvent = true
    case "--session": session = Int(value(argument))
    case "--force": force = true
    case "--dry-run": dryRun = true
    case "--version": print("atem-convert \(converterVersion)"); exit(0)
    default:
        if argument.hasPrefix("-") { fputs("Error: unknown option \(argument)\n", stderr); exit(2) }
        input = argument
    }
}
if extrasGiven { options.extraAudio = extras }
if noEvent { options.event = "" }
guard let input else { fputs("usage: atem-convert RECORDING [options]\n", stderr); exit(2) }

do {
    let log = try locateLog(URL(fileURLWithPath: input))
    let recording = try openRecording(log, session: session)
    let plan = try makePlan(recording, options)
    let payload = try buildFCPXML(plan)
    let destination = output.map { URL(fileURLWithPath: $0) } ?? log.deletingPathExtension().appendingPathExtension("fcpxml")
    if dryRun {
        print(plan.summary().joined(separator: "\n"))
        print("Would write \(destination.path)")
        exit(0)
    }
    if OutputWriter.protectedPaths(recording).contains(destination.resolvedPath) {
        throw ConversionError("Refusing to overwrite the .drp or recording media.")
    }
    try OutputWriter.write(payload, to: destination, replace: force)
    print("Wrote \(destination.path)")
    print(plan.summary().joined(separator: "\n"))
} catch let error as ConversionError {
    fputs("Error: \(error.message)\n", stderr)
    exit(2)
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(2)
}
