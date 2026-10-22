import Foundation
import Testing
@testable import VocabKit

/// Answers requests from a canned table, so the client can be exercised without a server.
final class StubURLProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var contentType = "text/event-stream"
        var body: String
    }

    nonisolated(unsafe) static var replies: [String: [Reply]] = [:]
    nonisolated(unsafe) static var requests: [(path: String, body: [String: Any])] = []
    private static let lock = NSLock()

    static func reset(_ table: [String: [Reply]]) {
        lock.lock(); defer { lock.unlock() }
        replies = table
        requests = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let reply: Reply? = {
            Self.lock.lock(); defer { Self.lock.unlock() }
            Self.requests.append((path, Self.jsonBody(of: request)))
            guard var queue = Self.replies[path], !queue.isEmpty else { return nil }
            let next = queue.removeFirst()
            Self.replies[path] = queue.isEmpty ? [next] : queue
            return next
        }()
        guard let reply else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": reply.contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func jsonBody(of request: URLRequest) -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

func sse(_ pieces: [String]) -> String {
    pieces.map { piece in
        let escaped = String(data: try! JSONEncoder().encode(piece), encoding: .utf8)!
        return "data: {\"choices\":[{\"delta\":{\"content\":\(escaped)}}]}\n\n"
    }.joined() + "data: [DONE]\n\n"
}

@Suite("Local model client", .serialized)
struct LocalLLMClientTests {

    let endpoint = LLMEndpoint(baseURL: URL(string: "http://127.0.0.1:1234/v1")!, model: "qwen")

    private func collect(_ client: LocalLLMClient, _ request: ChatRequest) async throws -> String {
        var text = ""
        for try await piece in client.stream(request) { text += piece }
        return text
    }

    @Test func pastedAddressesBecomeAnAPIRoot() {
        #expect(LLMEndpoint.baseURL(from: "localhost:1234")?.absoluteString == "http://localhost:1234/v1")
        #expect(LLMEndpoint.baseURL(from: " http://127.0.0.1:8080/ ")?.absoluteString == "http://127.0.0.1:8080/v1")
        #expect(LLMEndpoint.baseURL(from: "http://box.local:11434/v1/chat/completions")?.absoluteString
                == "http://box.local:11434/v1")
        #expect(LLMEndpoint.baseURL(from: "") == nil)
        #expect(LLMEndpoint.baseURL(from: "ftp://x") == nil)
    }

    @Test func streamsDeltasInOrder() async throws {
        StubURLProtocol.reset(["/v1/chat/completions": [.init(body: sse(["{\"ca", "rds\":", "[]}"]))]])
        let client = LocalLLMClient(endpoint: endpoint, session: StubURLProtocol.session())
        let text = try await collect(client, ChatRequest(messages: [ChatMessage(.user, "hi")]))
        #expect(text == "{\"cards\":[]}")
    }

    @Test func sendsModelMessagesAndSchema() async throws {
        StubURLProtocol.reset(["/v1/chat/completions": [.init(body: sse(["ok"]))]])
        let client = LocalLLMClient(endpoint: endpoint, session: StubURLProtocol.session())
        _ = try await collect(client, ChatRequest(messages: [ChatMessage(.system, "s"), ChatMessage(.user, "u")],
                                                  schema: ["type": "object"]))
        let body = try #require(StubURLProtocol.requests.first?.body)
        #expect(body["model"] as? String == "qwen")
        #expect(body["stream"] as? Bool == true)
        #expect((body["messages"] as? [[String: String]])?.map { $0["role"] ?? "" } == ["system", "user"])
        let format = try #require(body["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
    }

    @Test func omitsAnEmptyModelName() async throws {
        StubURLProtocol.reset(["/v1/chat/completions": [.init(body: sse(["ok"]))]])
        let client = LocalLLMClient(endpoint: LLMEndpoint(baseURL: endpoint.baseURL),
                                    session: StubURLProtocol.session())
        _ = try await collect(client, ChatRequest(messages: [ChatMessage(.user, "u")]))
        #expect(StubURLProtocol.requests.first?.body["model"] == nil)
    }

    @Test func retriesWithoutTheSchemaWhenTheServerRejectsIt() async throws {
        StubURLProtocol.reset(["/v1/chat/completions": [
            .init(status: 400, contentType: "application/json",
                  body: #"{"error":{"message":"response_format not supported"}}"#),
            .init(body: sse(["plain"]))
        ]])
        let client = LocalLLMClient(endpoint: endpoint, session: StubURLProtocol.session())
        let text = try await collect(client, ChatRequest(messages: [ChatMessage(.user, "u")],
                                                         schema: ["type": "object"]))
        #expect(text == "plain")
        #expect(StubURLProtocol.requests.count == 2)
        #expect(StubURLProtocol.requests[1].body["response_format"] == nil)
    }

    @Test func reportsTheServersOwnErrorMessage() async throws {
        StubURLProtocol.reset(["/v1/chat/completions": [
            .init(status: 404, contentType: "application/json", body: #"{"error":"model 'qwen' not found"}"#)
        ]])
        let client = LocalLLMClient(endpoint: endpoint, session: StubURLProtocol.session())
        await #expect(throws: LLMError.http(status: 404, message: "model 'qwen' not found")) {
            try await collect(client, ChatRequest(messages: [ChatMessage(.user, "u")]))
        }
    }

    @Test func acceptsAServerThatIgnoresStreaming() async throws {
        StubURLProtocol.reset(["/v1/chat/completions": [
            .init(contentType: "application/json",
                  body: #"{"choices":[{"message":{"role":"assistant","content":"whole reply"}}]}"#)
        ]])
        let client = LocalLLMClient(endpoint: endpoint, session: StubURLProtocol.session())
        #expect(try await collect(client, ChatRequest(messages: [ChatMessage(.user, "u")])) == "whole reply")
    }

    @Test func anEmptyStreamIsAnError() async throws {
        StubURLProtocol.reset(["/v1/chat/completions": [.init(body: "data: [DONE]\n\n")]])
        let client = LocalLLMClient(endpoint: endpoint, session: StubURLProtocol.session())
        await #expect(throws: LLMError.emptyReply) {
            try await collect(client, ChatRequest(messages: [ChatMessage(.user, "u")]))
        }
    }

    @Test func noServerIsReportedAsUnreachable() async throws {
        StubURLProtocol.reset([:])
        let client = LocalLLMClient(endpoint: endpoint, session: StubURLProtocol.session())
        await #expect(throws: LLMError.unreachable("127.0.0.1:1234")) {
            try await collect(client, ChatRequest(messages: [ChatMessage(.user, "u")]))
        }
    }

    @Test func listsChatModelsOnly() async throws {
        StubURLProtocol.reset(["/v1/models": [.init(contentType: "application/json", body: """
            {"data":[{"id":"qwen2.5-7b-instruct"},{"id":"text-embedding-nomic-embed-text-v1.5"}]}
            """)]])
        let client = LocalLLMClient(endpoint: endpoint, session: StubURLProtocol.session())
        #expect(try await client.models() == ["qwen2.5-7b-instruct"])
    }

    @Test func discoveryReturnsOnlyServersThatAnswer() async {
        StubURLProtocol.reset(["/v1/models": [.init(contentType: "application/json",
                                                    body: #"{"data":[{"id":"llama"}]}"#)]])
        let servers = await LLMServerDiscovery.discover(
            candidates: [("Down", URL(string: "http://127.0.0.1:9/v2")!),
                         ("Up", URL(string: "http://127.0.0.1:8080/v1")!)],
            session: StubURLProtocol.session())
        #expect(servers.map(\.name) == ["Up"])
        #expect(servers.first?.models == ["llama"])
    }

    @Test func jsonTextKeepsMemberOrderAndEscapes() throws {
        let value: JSONValue = ["z": 1, "a": [true, .null, 2.5], "q": "say \"hi\"\n\u{1}\\ 你好"]
        #expect(value.jsonText == #"{"z":1,"a":[true,null,2.5],"q":"say \"hi\"\n\u0001\\ 你好"}"#)
        // And it is valid JSON that reads back to the same text.
        let parsed = try JSONSerialization.jsonObject(with: Data(value.jsonText.utf8)) as? [String: Any]
        #expect(parsed?["q"] as? String == "say \"hi\"\n\u{1}\\ 你好")
        #expect(value.setting("a", to: false).jsonText == #"{"z":1,"a":false,"q":"say \"hi\"\n\u0001\\ 你好"}"#)
    }

    @Test func eventLinesWithoutASpaceStillParse() {
        #expect(LocalLLMClient.eventPayload("data:{\"a\":1}") == "{\"a\":1}")
        #expect(LocalLLMClient.eventPayload(": keep-alive") == nil)
        #expect(LocalLLMClient.eventPayload("event: message") == nil)
    }
}
