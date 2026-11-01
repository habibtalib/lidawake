import Foundation

/// Result of running a process to completion.
public struct ShellResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String
}

public enum Shell {
    /// Runs an executable with arguments (no shell, no PATH lookup) and waits for it.
    @discardableResult
    public static func run(_ executable: String, _ arguments: [String], stdin: String? = nil) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let input = Pipe()
        process.standardInput = input
        try process.run()
        if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
        try? input.fileHandleForWriting.close()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellResult(status: process.terminationStatus,
                           stdout: String(decoding: outData, as: UTF8.self),
                           stderr: String(decoding: errData, as: UTF8.self))
    }
}
