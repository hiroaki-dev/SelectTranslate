import Darwin
import Foundation

/// Runs a child process while draining stdout and stderr concurrently, so a child that
/// writes more than a pipe buffer (64KB on macOS) to either stream cannot deadlock us.
/// Blocks the calling thread; call it from a background task.
enum ChildProcessRunner {
    static let defaultStderrLimit = 64 * 1024

    enum RunError: Error {
        case timedOut(seconds: TimeInterval)
    }

    struct Result {
        let terminationStatus: Int32
        let stdout: Data
        /// Only the last `stderrLimit` bytes; earlier output is dropped.
        let stderr: Data

        var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
        var stderrText: String { String(decoding: stderr, as: UTF8.self) }
    }

    /// - Parameters:
    ///   - timeout: Seconds to wait for the process to exit before terminating it and throwing `RunError.timedOut`.
    ///   - stderrLimit: Maximum number of trailing stderr bytes to keep.
    ///   - killGracePeriod: Seconds to wait after `terminate()` before sending `SIGKILL`.
    ///   - outputDrainGracePeriod: Seconds to wait for stdout/stderr EOF after the process exits,
    ///     in case a grandchild inherited the pipes and keeps them open.
    static func run(
        _ process: Process,
        input: Data? = nil,
        timeout: TimeInterval,
        stderrLimit: Int = defaultStderrLimit,
        killGracePeriod: TimeInterval = 5,
        outputDrainGracePeriod: TimeInterval = 2
    ) throws -> Result {
        let stdinPipe = input == nil ? nil : Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        if let stdinPipe {
            process.standardInput = stdinPipe
            // Get EPIPE instead of a process-killing SIGPIPE if the child exits without reading stdin.
            _ = fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        try process.run()

        let stdoutBuffer = OutputBuffer(limit: nil)
        let stderrBuffer = OutputBuffer(limit: stderrLimit)
        let readers = DispatchGroup()
        drain(stdoutPipe.fileHandleForReading, into: stdoutBuffer, group: readers)
        drain(stderrPipe.fileHandleForReading, into: stderrBuffer, group: readers)

        if let input, let stdinPipe {
            // Write on its own thread so a child that never reads stdin cannot block us past the timeout.
            DispatchQueue.global(qos: .userInitiated).async {
                let handle = stdinPipe.fileHandleForWriting
                try? handle.write(contentsOf: input)
                try? handle.close()
            }
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + killGracePeriod) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
            _ = readers.wait(timeout: .now() + outputDrainGracePeriod)
            throw RunError.timedOut(seconds: timeout)
        }

        process.waitUntilExit()
        _ = readers.wait(timeout: .now() + outputDrainGracePeriod)

        return Result(
            terminationStatus: process.terminationStatus,
            stdout: stdoutBuffer.data,
            stderr: stderrBuffer.data
        )
    }

    private static func drain(_ handle: FileHandle, into buffer: OutputBuffer, group: DispatchGroup) {
        DispatchQueue.global(qos: .userInitiated).async(group: group) {
            // read(2) returns whatever is available, unlike FileHandle.read(upToCount:),
            // which waits for a full chunk or EOF.
            let fileDescriptor = handle.fileDescriptor
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = chunk.withUnsafeMutableBytes { Darwin.read(fileDescriptor, $0.baseAddress, $0.count) }
                if count > 0 {
                    buffer.append(Data(chunk[0..<count]))
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    break
                }
            }
        }
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int?
    private var storage = Data()

    init(limit: Int?) {
        self.limit = limit
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(chunk)
        if let limit, storage.count > limit {
            storage = Data(storage.suffix(limit))
        }
    }
}
