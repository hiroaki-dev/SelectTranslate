import XCTest
@testable import SelectTranslate

final class ChildProcessRunnerTests: XCTestCase {
    private func shellProcess(_ script: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        return process
    }

    func testCompletesWhenStderrExceedsPipeBufferBeforeStdout() throws {
        // More than the 64KB pipe buffer goes to stderr before anything is written to stdout,
        // which deadlocked the old stdout-then-stderr sequential reads (issue #26).
        let process = shellProcess("head -c 300000 /dev/zero | tr '\\0' x >&2; printf translated")

        let result = try ChildProcessRunner.run(process, timeout: 10)

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.stdoutText, "translated")
        XCTAssertFalse(result.stderrText.isEmpty)
    }

    func testCompletesWhenStdoutExceedsPipeBuffer() throws {
        let process = shellProcess("head -c 300000 /dev/zero | tr '\\0' y; echo error >&2")

        let result = try ChildProcessRunner.run(process, timeout: 10)

        XCTAssertEqual(result.stdout.count, 300_000)
        XCTAssertEqual(result.stderrText, "error\n")
    }

    func testKeepsOnlyTheTailOfStderr() throws {
        let process = shellProcess("head -c 100000 /dev/zero | tr '\\0' x >&2; printf 'ERROR: last line' >&2")

        let result = try ChildProcessRunner.run(process, timeout: 10, stderrLimit: 1024)

        XCTAssertEqual(result.stderr.count, 1024)
        XCTAssertTrue(result.stderrText.hasSuffix("ERROR: last line"))
    }

    func testPassesInputToStdin() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        let input = String(repeating: "翻訳", count: 50_000)

        let result = try ChildProcessRunner.run(process, input: Data(input.utf8), timeout: 10)

        XCTAssertEqual(result.stdoutText, input)
    }

    func testReportsNonZeroExitStatus() throws {
        let process = shellProcess("echo failure >&2; exit 3")

        let result = try ChildProcessRunner.run(process, timeout: 10)

        XCTAssertEqual(result.terminationStatus, 3)
        XCTAssertEqual(result.stderrText, "failure\n")
    }

    func testTerminatesProcessAfterTimeout() {
        let process = shellProcess("exec sleep 30")
        let start = Date()

        XCTAssertThrowsError(try ChildProcessRunner.run(process, timeout: 0.5)) { error in
            guard case ChildProcessRunner.RunError.timedOut = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
        XCTAssertFalse(process.isRunning)
    }

    func testKillsProcessThatIgnoresTerminate() {
        let process = shellProcess("trap '' TERM; while :; do sleep 0.1; done")
        let start = Date()

        XCTAssertThrowsError(try ChildProcessRunner.run(process, timeout: 0.5, killGracePeriod: 0.5))
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
        XCTAssertFalse(process.isRunning)
    }

    func testDoesNotWaitForeverWhenGrandchildKeepsPipesOpen() throws {
        // The shell exits right away, but the background sleep inherits stdout/stderr.
        let process = shellProcess("printf done; sleep 5 &")
        let start = Date()

        let result = try ChildProcessRunner.run(process, timeout: 10, outputDrainGracePeriod: 0.5)

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(result.stdoutText, "done")
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}
