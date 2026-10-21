import Foundation
import SussurroCore

@main
struct SussurroMCPMain {
    static func main() {
        do {
            let configuration = try MCPServerConfiguration.parse(
                arguments: CommandLine.arguments,
                environment: ProcessInfo.processInfo.environment
            )
            let transcriber = LocalWhisperTranscriber(
                whisperCLIURL: configuration.whisperCLIURL,
                modelURL: configuration.modelURL,
                language: configuration.language
            )
            let logger = PrivacySafeEventLogger(
                isEnabled: configuration.eventsEnabled,
                fileURL: configuration.eventsFileURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("sussurro-events-disabled")
            )
            let toolService = SussurroToolService(
                transcriber: transcriber,
                lastTranscriptionStore: LastTranscriptionStore(fileURL: configuration.lastTranscriptionFileURL),
                eventLogger: logger
            )
            let readinessReport = LocalReadinessReport.evaluate(.init(
                microphone: .unavailable,
                systemAudio: .unavailable,
                whisperCLIURL: configuration.whisperCLIURL,
                modelURL: configuration.modelURL,
                mcpExecutableURL: URL(fileURLWithPath: CommandLine.arguments[0])
            ))
            let handler = MCPRequestHandler(toolService: toolService, readinessReport: readinessReport)

            while let line = readLine(strippingNewline: true) {
                guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                do {
                    if let response = try handler.handle(data: Data(line.utf8)) {
                        FileHandle.standardOutput.write(response)
                        FileHandle.standardOutput.write(Data([0x0A]))
                    }
                } catch {
                    let response: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": NSNull(),
                        "error": ["code": -32700, "message": "Parse error: \(error.localizedDescription)"]
                    ]
                    let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write(Data([0x0A]))
                }
            }
        } catch {
            FileHandle.standardError.write(Data("sussurro-mcp: \(error.localizedDescription)\n".utf8))
            Foundation.exit(2)
        }
    }
}
