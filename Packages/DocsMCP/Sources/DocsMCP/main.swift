import DocsCore
import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct MCPRequest: Codable {
    let jsonrpc: String
    let id: RequestID?
    let method: String
    let params: [String: JSONValue]?
}

enum RequestID: Codable {
    case string(String)
    case int(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            self = .int(try container.decode(Int.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        }
    }
}

enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case let .int(value) = self { return value }
        return nil
    }
}

struct MCPResponse: Encodable {
    let jsonrpc = "2.0"
    let id: RequestID?
    let result: [String: JSONValue]?
    let error: MCPErrorPayload?
}

struct MCPErrorPayload: Encodable {
    let code: Int
    let message: String
}

@main
struct DocsMCPServer {
    static func main() async {
        do {
            let store = try DocsStore()
            let engine = SearchEngine(store: store)
            let server = MCPServer(engine: engine)
            try server.run()
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

final class MCPServer {
    private let engine: SearchEngine
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(engine: SearchEngine) {
        self.engine = engine
    }

    func run() throws {
        while let line = readLine(strippingNewline: true) {
            if line.isEmpty {
                continue
            }

            let data = Data(line.utf8)
            do {
                let request = try decoder.decode(MCPRequest.self, from: data)
                let response = try handle(request: request)
                try write(response: response)
            } catch {
                let response = MCPResponse(
                    id: nil,
                    result: nil,
                    error: MCPErrorPayload(code: -32603, message: error.localizedDescription)
                )
                try write(response: response)
            }
        }
    }

    private func handle(request: MCPRequest) throws -> MCPResponse {
        switch request.method {
        case "initialize":
            return MCPResponse(
                id: request.id,
                result: [
                    "protocolVersion": .string("2025-11-25"),
                    "serverInfo": .object([
                        "name": .string("apple-docs-explorer"),
                        "version": .string("0.1.0")
                    ]),
                    "capabilities": .object([
                        "tools": .object([:])
                    ])
                ],
                error: nil
            )
        case "tools/list":
            return MCPResponse(
                id: request.id,
                result: [
                    "tools": .array(toolDefinitions)
                ],
                error: nil
            )
        case "tools/call":
            return try callTool(request: request)
        default:
            return MCPResponse(
                id: request.id,
                result: nil,
                error: MCPErrorPayload(code: -32601, message: "Unknown method \(request.method)")
            )
        }
    }

    private func callTool(request: MCPRequest) throws -> MCPResponse {
        guard
            let params = request.params,
            let name = params["name"]?.stringValue,
            case let .object(arguments)? = params["arguments"]
        else {
            return MCPResponse(
                id: request.id,
                result: nil,
                error: MCPErrorPayload(code: -32602, message: "Missing tool name or arguments")
            )
        }

        let payload: [String: JSONValue]
        switch name {
        case "search_apple_docs":
            let query = arguments["query"]?.stringValue ?? ""
            let framework = arguments["framework"]?.stringValue
            let limit = arguments["limit"]?.intValue ?? 10
            let response = try engine.search(SearchQuery(text: query, framework: framework, limit: limit))
            payload = toolResult(from: response.results)
        case "get_doc_entry":
            guard let assetID = arguments["asset_id"]?.stringValue else {
                throw DocsError.unsupported("asset_id is required")
            }
            let entry = try engine.entry(assetID: assetID)
            payload = entryPayload(entry)
        case "lookup_symbol":
            let name = arguments["name"]?.stringValue ?? ""
            let framework = arguments["framework"]?.stringValue
            let response = try engine.lookupSymbol(name: name, framework: framework, limit: arguments["limit"]?.intValue ?? 10)
            payload = toolResult(from: response.results)
        case "related_docs":
            guard let assetID = arguments["asset_id"]?.stringValue else {
                throw DocsError.unsupported("asset_id is required")
            }
            let results = try engine.related(assetID: assetID, limit: arguments["limit"]?.intValue ?? 10)
            payload = toolResult(from: results)
        default:
            throw DocsError.unsupported("Unknown tool \(name)")
        }

        return MCPResponse(id: request.id, result: payload, error: nil)
    }

    private func toolResult(from results: [SearchResult]) -> [String: JSONValue] {
        let items = results.map { result in
            JSONValue.object([
                "asset_id": .string(result.assetID),
                "title": .string(result.title),
                "framework": .string(result.framework),
                "doc_type": .string(result.docType),
                "snippet": .string(result.snippet),
                "score": .int(result.score)
            ])
        }

        let structured = JSONValue.object([
            "results": .array(items)
        ])

        return [
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string("Returned \(results.count) Apple documentation result(s).")
                ])
            ]),
            "structuredContent": structured,
            "isError": .bool(false)
        ]
    }

    private func entryPayload(_ entry: DocEntry?) -> [String: JSONValue] {
        guard let entry else {
            return [
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("No entry found.")
                    ])
                ]),
                "structuredContent": .object([
                    "entry": .null
                ]),
                "isError": .bool(false)
            ]
        }

        return [
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(entry.snippetSource)
                ])
            ]),
            "structuredContent": .object([
                "entry": .object([
                    "asset_id": .string(entry.assetID),
                    "title": .string(entry.title),
                    "framework": .string(entry.framework),
                    "doc_type": .string(entry.docType),
                    "content": entry.content.map(JSONValue.string) ?? .null,
                    "raw_document_json": .string(entry.rawDocumentJSON)
                ])
            ]),
            "isError": .bool(false)
        ]
    }

    private func write(response: MCPResponse) throws {
        let data = try encoder.encode(response)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    private var toolDefinitions: [JSONValue] {
        [
            .object([
                "name": .string("search_apple_docs"),
                "description": .string("Search the locally installed Apple documentation asset."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object(["type": .string("string")]),
                        "framework": .object(["type": .string("string")]),
                        "limit": .object(["type": .string("integer")])
                    ])
                ])
            ]),
            .object([
                "name": .string("get_doc_entry"),
                "description": .string("Fetch a single Apple documentation entry by stable asset_id."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "asset_id": .object(["type": .string("string")])
                    ])
                ])
            ]),
            .object([
                "name": .string("lookup_symbol"),
                "description": .string("Look up an Apple symbol by name, optionally scoped to a framework."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object(["type": .string("string")]),
                        "framework": .object(["type": .string("string")]),
                        "limit": .object(["type": .string("integer")])
                    ])
                ])
            ]),
            .object([
                "name": .string("related_docs"),
                "description": .string("Return related Apple docs for the supplied asset_id."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "asset_id": .object(["type": .string("string")]),
                        "limit": .object(["type": .string("integer")])
                    ])
                ])
            ])
        ]
    }
}
