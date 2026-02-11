import Foundation
import os

class ScriptHookService {
    static let shared = ScriptHookService()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "ScriptHook")

    private init() {}

    /// Build a minimal environment for script execution to avoid triggering
    /// macOS TCC permission dialogs (Photos, Music, iCloud, etc.) that occur
    /// when the full parent-process environment is inherited.
    private static func minimalEnvironment() -> [String: String] {
        let current = ProcessInfo.processInfo.environment
        let keys = ["PATH", "HOME"]
        var env: [String: String] = [:]
        for key in keys {
            if let value = current[key] {
                env[key] = value
            }
        }
        return env
    }

    func execute(scriptPath: String, inputText: String, timeout: TimeInterval = 30.0) async -> String {
        let command = scriptPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return inputText }

        do {
            return try await runProcess(command: command, inputText: inputText, timeout: timeout)
        } catch {
            logger.error("Script execution failed: \(error.localizedDescription, privacy: .public)")
            return inputText
        }
    }

    private func runProcess(command: String, inputText: String, timeout: TimeInterval) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = ScriptHookService.minimalEnvironment()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let lock = NSLock()

            @Sendable func resumeOnce(with result: Result<String, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(with: result)
            }

            // Collect stdout/stderr asynchronously to avoid pipe buffer deadlock
            var stdoutData = Data()
            var stderrData = Data()
            let stdoutLock = NSLock()
            let stderrLock = NSLock()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    stdoutLock.lock()
                    stdoutData.append(chunk)
                    stdoutLock.unlock()
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    stderrLock.lock()
                    stderrData.append(chunk)
                    stderrLock.unlock()
                }
            }

            // Timeout: terminate, then force-kill after 5s if still running
            let timeoutWork = DispatchWorkItem { [weak self, weak process] in
                guard let process = process, process.isRunning else { return }
                self?.logger.warning("Script timed out, sending SIGTERM")
                process.terminate()

                DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) { [weak self, weak process] in
                    guard let process = process, process.isRunning else { return }
                    self?.logger.warning("Script still running after SIGTERM, sending SIGKILL")
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

            process.terminationHandler = { [weak self] proc in
                timeoutWork.cancel()

                // Stop readability handlers and read remaining data
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                stdoutLock.lock()
                stdoutData.append(remainingStdout)
                stdoutLock.unlock()
                stderrLock.lock()
                stderrData.append(remainingStderr)
                stderrLock.unlock()

                if proc.terminationStatus != 0 {
                    let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
                    self?.logger.error("Script exited with status \(proc.terminationStatus): \(stderrString, privacy: .public)")
                    resumeOnce(with: .success(inputText))
                    return
                }

                guard let output = String(data: stdoutData, encoding: .utf8) else {
                    self?.logger.error("Failed to decode script stdout as UTF-8")
                    resumeOnce(with: .success(inputText))
                    return
                }

                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self?.logger.warning("Script returned empty output, using original text")
                    resumeOnce(with: .success(inputText))
                    return
                }

                resumeOnce(with: .success(trimmed))
            }

            do {
                try process.run()

                // Write input and close stdin to send EOF
                let stdinHandle = stdinPipe.fileHandleForWriting
                if let data = inputText.data(using: .utf8) {
                    stdinHandle.write(data)
                }
                stdinHandle.closeFile()
            } catch {
                timeoutWork.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                resumeOnce(with: .success(inputText))
            }
        }
    }
}
