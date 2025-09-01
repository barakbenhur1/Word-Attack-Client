//
//  Log.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 29/08/2025.
//

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Foundation
import os

struct DevLog {
    static let shared = DevLog()

    private let fileURL: URL
    private let handle: FileHandle?
    private let oslog = Logger(subsystem: "com.barak.wordguess", category: "game")

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("dev.log")

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: fileURL)
        _ = try? handle?.seekToEnd()
    }

    private func writeFile(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        handle?.write(data)
        // On some iOS versions, you may want: try? handle?.synchronize() for immediate flush.
    }
    
    /// Colored to file (Terminal), plain to Xcode console + os.Logger.
    func colorInfo(_ message: String, color: String = "\u{001B}[35m") {
        let colored = message
        writeFile(colored)            // raw ANSI -> Terminal shows color
        print(stripANSI((message)))                // plain for Xcode (no escape junk)
        oslog.info("\(message, privacy: .public)")  // filterable in Console.app
    }
}

enum Trace {
    private static let canShowColor: Bool = {
        // Only enable on real terminals, not in log aggregators / some IDE consoles
        let isTTY = isatty(STDOUT_FILENO) == 1
        let env = ProcessInfo.processInfo.environment
        let term = env["TERM"] ?? ""
        let noColor = env["NO_COLOR"] != nil
        return isTTY && !term.isEmpty && term != "dumb" && !noColor
    }()
    
#if DEBUG
    static var enabled = false //true
#else
    static var enabled = false
#endif
    typealias Closure = () -> String
    static func log(_ tag: String, _ s: @autoclosure Closure, _ color: String = Fancy.gray) {
        guard enabled else { return }
        if canShowColor { print("\(color)\(tag) \(s())\(Fancy.reset)") }
        else { DevLog.shared.colorInfo("\(color)\(tag) \(s())\(Fancy.reset)") }
    }
}

enum Fancy {
    static var reset: String  { "\u{001B}[0m" }
    static var gray: String   { "\u{001B}[90m" }
    static var blue: String   { "\u{001B}[34m" }
    static var green: String  { "\u{001B}[32m" }
    static var yellow: String { "\u{001B}[33m" }
    static var mag: String { "\u{001B}[35m" }
    static var cyan: String   { "\u{001B}[36m" }
    static var red: String    { "\u{001B}[31m" }
}

fileprivate func stripANSI(_ s: String) -> String {
    let pattern = "\u{001B}\\[[0-9;]*m"   // matches ESC[ ... m
    return s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
}
