import Foundation

public struct MCPRequestHandler: Sendable {
    private let toolService: SussurroToolService
    private let readinessReport: LocalReadinessReport

    public init(
        toolService: SussurroToolService,
        readinessReport: LocalReadinessReport = .evaluate(.init(
            microphone: .unavailable,
            systemAudio: .unavailable,
            whisperCLIURL: nil,
            modelURL: nil,
            mcpExecutableURL: nil
        ))
    ) {
        self.toolService = toolService
        self.readinessReport = readinessReport
    }

    public func handle(jsonObject request: [String: Any]) throws -> [String: Any]? {
        guard let method = request["method"] as? String else {
            return errorResponse(id: request["id"], code: -32600, message: "Invalid Request")
        }
        guard let id = request["id"] else { return nil }

        switch method {
        case "initialize":
            let params = request["params"] as? [String: Any]
            let protocolVersion = params?["protocolVersion"] as? String ?? "2025-06-18"
            return response(id: id, result: [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "sussurro", "version": "0.1.0"]
            ])
        case "tools/list":
            return response(id: id, result: ["tools": Self.tools])
        case "tools/call":
            return response(id: id, result: callTool(params: request["params"] as? [String: Any] ?? [:]))
        default:
            return errorResponse(id: id, code: -32601, message: "Method not found")
        }
    }

    public func handle(data: Data) throws -> Data? {
        guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = try handle(jsonObject: request)
        else { return nil }
        return try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
    }

    private func callTool(params: [String: Any]) -> [String: Any] {
        do {
            guard let name = params["name"] as? String else {
                throw MCPToolError.invalidArguments("missing tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let structured: [String: Any]
            switch name {
            case "transcribe_audio":
                let path = try requiredString("audio_path", in: arguments)
                structured = transcriptionObject(try toolService.transcribeAudio(at: URL(fileURLWithPath: path)))
            case "structure_text":
                let text = try requiredString("text", in: arguments)
                structured = try toolService.structureText(text, schemaData: schemaData(in: arguments))
            case "structure_audio":
                let path = try requiredString("audio_path", in: arguments)
                structured = try toolService.structureAudio(at: URL(fileURLWithPath: path), schemaData: schemaData(in: arguments))
            case "get_last_transcription":
                if let record = try toolService.getLastTranscription() {
                    structured = transcriptionObject(record)
                } else {
                    structured = ["transcription": NSNull()]
                }
            case "get_local_readiness":
                structured = try readinessObject()
            default:
                throw MCPToolError.invalidArguments("unknown tool '\(name)'")
            }
            let json = try JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys])
            return [
                "content": [["type": "text", "text": String(data: json, encoding: .utf8) ?? "{}"]],
                "structuredContent": structured,
                "isError": false
            ]
        } catch {
            return [
                "content": [["type": "text", "text": error.localizedDescription]],
                "isError": true
            ]
        }
    }

    private func requiredString(_ name: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[name] as? String, !value.isEmpty else {
            throw MCPToolError.invalidArguments("missing non-empty '\(name)'")
        }
        return value
    }

    private func schemaData(in arguments: [String: Any]) throws -> Data {
        guard let schema = arguments["schema"] as? [String: Any] else {
            throw MCPToolError.invalidArguments("missing JSON object 'schema'")
        }
        return try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
    }

    private func transcriptionObject(_ record: TranscriptionRecord) -> [String: Any] {
        [
            "text": record.text,
            "language": record.language ?? NSNull(),
            "audio_path": record.audioPath,
            "created_at": ISO8601DateFormatter().string(from: record.createdAt)
        ]
    }

    private func readinessObject() throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(readinessReport)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPToolError.invalidArguments("could not encode readiness")
        }
        return object
    }

    private static let tools: [[String: Any]] = [
        tool(
            name: "transcribe_audio",
            description: "Transcribe a local audio file with the configured local whisper.cpp model.",
            properties: ["audio_path": ["type": "string", "description": "Absolute local audio file path"]],
            required: ["audio_path"]
        ),
        tool(
            name: "structure_text",
            description: "Extract labeled values from text into a user-provided JSON schema and validate locally.",
            properties: [
                "text": ["type": "string"],
                "schema": ["type": "object", "description": "Phase 1 JSON schema"]
            ],
            required: ["text", "schema"]
        ),
        tool(
            name: "structure_audio",
            description: "Transcribe local audio, extract labeled values, and validate against a user-provided JSON schema.",
            properties: [
                "audio_path": ["type": "string", "description": "Absolute local audio file path"],
                "schema": ["type": "object", "description": "Phase 1 JSON schema"]
            ],
            required: ["audio_path", "schema"]
        ),
        tool(
            name: "get_last_transcription",
            description: "Return the last transcription produced by the app or MCP server.",
            properties: [:],
            required: []
        ),
        tool(
            name: "get_local_readiness",
            description: "Check local model, executable, and permission readiness without reading audio or transcript content.",
            properties: [:],
            required: []
        )
    ]

    private static func tool(name: String, description: String, properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required,
                "additionalProperties": false
            ]
        ]
    }

    private func response(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }
}

private enum MCPToolError: LocalizedError {
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case let .invalidArguments(message): return "Invalid tool arguments: \(message)."
        }
    }
}
