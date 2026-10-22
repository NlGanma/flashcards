import Foundation

// Every popular local model runner — LM Studio, Ollama, llama.cpp's llama-server, Jan —
// serves the same OpenAI-style HTTP API, so one small client covers all of them and
// nothing ever leaves the machine.

/// Where the local model lives.
public struct LLMEndpoint: Codable, Hashable, Sendable {
    /// The API root, ending in `/v1`.
    public var baseURL: URL
    /// The model to ask for. Empty means "whatever the server has loaded".
    public var model: String

    public init(baseURL: URL, model: String = "") {
        self.baseURL = baseURL
        self.model = model
    }

    /// LM Studio's default, the runner most people install first.
    public static let lmStudio = LLMEndpoint(baseURL: URL(string: "http://127.0.0.1:1234/v1")!)

    /// Turn what people paste into an API root: "localhost:1234", "http://127.0.0.1:8080/",
    /// and a full ".../v1/chat/completions" all mean the same server.
    public static func baseURL(from text: String) -> URL? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = "http://" + raw }
        guard var components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }
        var path = components.path
        for suffix in ["/chat/completions", "/completions", "/models"] where path.hasSuffix(suffix) {
            path.removeLast(suffix.count)
        }
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/v1") { path += "/v1" }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

public struct ChatMessage: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable { case system, user, assistant }
    public var role: Role
    public var content: String

    public init(_ role: Role, _ content: String) {
        self.role = role
        self.content = content
    }
}

/// Just enough JSON to write a JSON Schema for `response_format` without `[String: Any]`.
///
/// Objects keep their members in order, and `jsonText` writes them in that order. That is
/// not cosmetic: llama.cpp makes the model write an object's keys in the order its schema
/// lists them, and a model forced to write `back` before `front` answers before it knows the
/// question — it swaps the two faces. A `Dictionary` (and so plain `JSONEncoder`) would
/// shuffle the keys on every launch.
public indirect enum JSONValue: Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([Member])

    public struct Member: Hashable, Sendable {
        public let key: String
        public let value: JSONValue

        public init(_ key: String, _ value: JSONValue) {
            self.key = key
            self.value = value
        }
    }

    /// The value of an object's member, or nil.
    public subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.last { $0.key == key }?.value
    }

    /// The same object with `key` set — replaced in place if present, appended if not.
    public func setting(_ key: String, to value: JSONValue) -> JSONValue {
        guard case .object(var members) = self else { return self }
        if let index = members.firstIndex(where: { $0.key == key }) {
            members[index] = Member(key, value)
        } else {
            members.append(Member(key, value))
        }
        return .object(members)
    }

    /// Compact JSON with object members in order.
    public var jsonText: String {
        switch self {
        case .string(let value): return Self.quoted(value)
        case .number(let value):
            if value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
            return "\(value)"
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        case .array(let values): return "[" + values.map(\.jsonText).joined(separator: ",") + "]"
        case .object(let members):
            return "{" + members.map { Self.quoted($0.key) + ":" + $0.value.jsonText }
                .joined(separator: ",") + "}"
        }
    }

    private static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20:
                out += String(format: "\\u%04x", scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else {
            // Decoded objects have no order to keep; sort so equal documents compare equal.
            let members = try container.decode([String: JSONValue].self)
            self = .object(members.sorted { $0.key < $1.key }.map { Member($0.key, $0.value) })
        }
    }

    /// Codable output for completeness. Request bodies are written with `jsonText`, which
    /// keeps member order on every Foundation version.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let members):
            try container.encode(Dictionary(members.map { ($0.key, $0.value) },
                                            uniquingKeysWith: { _, last in last }))
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
                     ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral,
                     ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    /// Literal order is kept: `["front": …, "back": …]` writes front first.
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(elements.map { Member($0.0, $0.1) })
    }
}

public struct ChatRequest: Sendable {
    public var messages: [ChatMessage]
    public var temperature: Double
    /// Constrain the reply to this JSON Schema. llama.cpp, LM Studio and Ollama compile it
    /// into a grammar, so a small model physically can't answer with malformed JSON. A
    /// server that rejects it is retried without it.
    public var schema: JSONValue?
    /// A ceiling on the reply. Without one, a model stuck in a loop keeps writing until
    /// its context is full, which on a laptop can take many minutes.
    public var maxTokens: Int?
    /// llama.cpp and LM Studio's penalty on recently repeated tokens; other servers ignore
    /// it. Tokens a schema forces (the JSON keys) have no alternative, so only free text is
    /// affected.
    public var repeatPenalty: Double?

    public init(messages: [ChatMessage], temperature: Double = 0.3, schema: JSONValue? = nil,
                maxTokens: Int? = nil, repeatPenalty: Double? = nil) {
        self.messages = messages
        self.temperature = temperature
        self.schema = schema
        self.maxTokens = maxTokens
        self.repeatPenalty = repeatPenalty
    }
}

/// Anything that can stream a chat reply. The generator depends on this, not on HTTP,
/// so it can be tested without a server.
public protocol ChatStreaming: Sendable {
    /// The reply's text as it arrives, in pieces.
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<String, Error>
}

public enum LLMError: Error, LocalizedError, Equatable {
    /// Nothing is listening at that address — the runner isn't started, or its server is off.
    case unreachable(String)
    case http(status: Int, message: String)
    /// The server answered but said nothing.
    case emptyReply
    case badReply(String)

    public var errorDescription: String? {
        switch self {
        case .unreachable(let address):
            return "Couldn't reach a model server at \(address). Make sure it's running and its local server is turned on."
        case .http(let status, let message):
            return message.isEmpty ? "The model server returned an error (HTTP \(status))."
                                   : "The model server said: \(message)"
        case .emptyReply:
            return "The model didn't return anything. Try again, or try a different model."
        case .badReply(let detail):
            return "The model server sent something unexpected: \(detail)"
        }
    }
}

/// An OpenAI-compatible chat client for a server on this Mac (or the local network).
public final class LocalLLMClient: ChatStreaming, @unchecked Sendable {

    public let endpoint: LLMEndpoint
    private let session: URLSession

    /// A 7B model on a laptop can sit on a long prompt for a minute before the first token,
    /// so the idle timeout is generous; the whole reply may take several minutes.
    public static func makeSession(configuration: URLSessionConfiguration = .ephemeral) -> URLSession {
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 1800
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    public init(endpoint: LLMEndpoint, session: URLSession? = nil) {
        self.endpoint = endpoint
        self.session = session ?? Self.makeSession()
    }

    // MARK: - Models

    /// Chat models the server offers. Embedding models are left out — they can't answer.
    public func models(timeout: TimeInterval = 5) async throws -> [String] {
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent("models"))
        request.timeoutInterval = timeout
        let (data, response) = try await perform { try await self.session.data(for: request) }
        try Self.check(response, body: data)
        struct List: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard let list = try? JSONDecoder().decode(List.self, from: data) else {
            throw LLMError.badReply("the model list wasn't in the expected format")
        }
        return list.data.map(\.id).filter { !$0.lowercased().contains("embed") }
    }

    // MARK: - Chat

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    do {
                        try await self.run(request, into: continuation)
                    } catch let LLMError.http(status, _) where request.schema != nil
                                && (status == 400 || status == 422 || status == 501) {
                        // Older runners reject `response_format`; ask again without it and
                        // let the reply parser cope with free-form text.
                        var plain = request
                        plain.schema = nil
                        try await self.run(plain, into: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ request: ChatRequest,
                     into continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        let urlRequest = try makeRequest(request)
        let (bytes, response) = try await perform { try await self.session.bytes(for: urlRequest) }

        guard let http = response as? HTTPURLResponse else { throw LLMError.badReply("no HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 65_536 { break }
            }
            try Self.check(response, body: body)
            return
        }

        // A server that ignores `stream: true` answers with one JSON body instead of events.
        let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if !type.contains("event-stream") {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            let text = try Self.messageContent(in: body)
            guard !text.isEmpty else { throw LLMError.emptyReply }
            continuation.yield(text)
            return
        }

        var sawContent = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let payload = Self.eventPayload(line) else { continue }
            if payload == "[DONE]" { break }
            if let text = try Self.deltaContent(in: Data(payload.utf8)), !text.isEmpty {
                sawContent = true
                continuation.yield(text)
            }
        }
        if !sawContent { throw LLMError.emptyReply }
    }

    func makeRequest(_ request: ChatRequest) throws -> URLRequest {
        var body: JSONValue = [:]
        if !endpoint.model.isEmpty { body = body.setting("model", to: .string(endpoint.model)) }
        body = body.setting("messages", to: .array(request.messages.map {
            ["role": .string($0.role.rawValue), "content": .string($0.content)]
        }))
        body = body.setting("temperature", to: .number(request.temperature))
        body = body.setting("stream", to: true)
        if let maxTokens = request.maxTokens { body = body.setting("max_tokens", to: .number(Double(maxTokens))) }
        if let penalty = request.repeatPenalty { body = body.setting("repeat_penalty", to: .number(penalty)) }
        if let schema = request.schema {
            body = body.setting("response_format", to: [
                "type": "json_schema",
                "json_schema": ["name": "flashcards", "strict": true, "schema": schema]
            ])
        }
        var urlRequest = URLRequest(url: endpoint.baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = Data(body.jsonText.utf8)
        return urlRequest
    }

    // MARK: - Wire format

    /// The data of one server-sent event line, or nil for comments, blank keep-alives and
    /// `event:` lines. Some servers omit the space after the colon.
    static func eventPayload(_ line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        return line.dropFirst(5).trimmingCharacters(in: .whitespaces)
    }

    private struct ErrorBody: Decodable {
        struct Detail: Decodable { let message: String? }
        let error: Detail?
        let message: String?

        enum CodingKeys: String, CodingKey { case error, message }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message = try? container.decode(String.self, forKey: .message)
            // `error` is an object for OpenAI-style servers and a bare string for Ollama.
            if let text = try? container.decode(String.self, forKey: .error) {
                error = Detail(message: text)
            } else {
                error = try? container.decode(Detail.self, forKey: .error)
            }
        }
    }

    /// Text of one streamed chunk. Reasoning models stream their thinking in a separate
    /// field, which is deliberately ignored.
    static func deltaContent(in data: Data) throws -> String? {
        struct Chunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable { let content: String? }
                let delta: Delta?
            }
            let choices: [Choice]?
        }
        if let failure = try? JSONDecoder().decode(ErrorBody.self, from: data),
           let message = failure.error?.message {
            throw LLMError.http(status: 200, message: message)
        }
        guard let chunk = try? JSONDecoder().decode(Chunk.self, from: data) else { return nil }
        return chunk.choices?.first?.delta?.content
    }

    static func messageContent(in data: Data) throws -> String {
        struct Reply: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message?
            }
            let choices: [Choice]
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw LLMError.badReply("the reply wasn't in the expected format")
        }
        return reply.choices.first?.message?.content ?? ""
    }

    private static func check(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw LLMError.badReply("no HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            let decoded = try? JSONDecoder().decode(ErrorBody.self, from: body)
            let message = decoded?.error?.message ?? decoded?.message
                ?? String(data: body.prefix(300), encoding: .utf8) ?? ""
            throw LLMError.http(status: http.statusCode,
                                message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Map the connection failures that all mean "no server there" to one error.
    private func perform<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as URLError {
            switch error.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
                 .notConnectedToInternet, .timedOut, .dnsLookupFailed:
                let host = endpoint.baseURL.host ?? endpoint.baseURL.absoluteString
                let port = endpoint.baseURL.port.map { ":\($0)" } ?? ""
                throw LLMError.unreachable(host + port)
            default:
                throw error
            }
        }
    }
}

// MARK: - Discovery

/// Finds model servers running on this Mac by trying each runner's default port.
public enum LLMServerDiscovery {

    public struct Server: Hashable, Sendable, Identifiable {
        public let name: String
        public let endpoint: LLMEndpoint
        public let models: [String]
        public var id: URL { endpoint.baseURL }
    }

    public static let knownServers: [(name: String, url: URL)] = [
        ("LM Studio", URL(string: "http://127.0.0.1:1234/v1")!),
        ("Ollama", URL(string: "http://127.0.0.1:11434/v1")!),
        ("llama.cpp", URL(string: "http://127.0.0.1:8080/v1")!),
        ("Jan", URL(string: "http://127.0.0.1:1337/v1")!)
    ]

    /// Every known server that answers, in `knownServers` order. Probes run in parallel
    /// with a short timeout, so a Mac with nothing running answers in about a second.
    public static func discover(candidates: [(name: String, url: URL)] = knownServers,
                                session: URLSession? = nil) async -> [Server] {
        let probeSession = session ?? LocalLLMClient.makeSession()
        let found = await withTaskGroup(of: (Int, Server?).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask {
                    let client = LocalLLMClient(endpoint: LLMEndpoint(baseURL: candidate.url),
                                                session: probeSession)
                    guard let models = try? await client.models(timeout: 1.5) else { return (index, nil) }
                    return (index, Server(name: candidate.name, endpoint: client.endpoint, models: models))
                }
            }
            var results: [(Int, Server?)] = []
            for await result in group { results.append(result) }
            return results
        }
        return found.sorted { $0.0 < $1.0 }.compactMap(\.1)
    }
}
