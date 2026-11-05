import XCTest
import CryptoKit
import Network
@testable import IntoEnglishProbe

final class ProbeTests: XCTestCase {
    func testKeychainRoundTrip() throws {
        let key = "test-" + UUID().uuidString
        defer { try? Vault.delete(key) }
        try Vault.save("synthetic-test-value", key: key)
        XCTAssertEqual(try Vault.read(String.self, key: key), "synthetic-test-value")
    }
    func testPKCEUsesRFC7636Vector() {
        XCTAssertEqual(OAuthTools.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
    func testCallbackRejectsStateHostDuplicatesAndClientSubstitution() throws {
        let redirect = URL(string: "http://127.0.0.1:1455/auth/callback")!
        let valid = URL(string: "http://127.0.0.1:1455/auth/callback?state=good&code=abc&client_id=oaiapp_test")!
        XCTAssertEqual(try OAuthTools.callback(valid, expectedRedirect: redirect, state: "good", knownClientID: nil).clientID, "oaiapp_test")
        for address in [
            "http://127.0.0.1:1455/auth/callback?state=evil&code=abc&client_id=oaiapp_test",
            "http://localhost:1455/auth/callback?state=good&code=abc&client_id=oaiapp_test",
            "http://127.0.0.1:1455/auth/callback?state=good&state=good&code=abc&client_id=oaiapp_test",
            "http://127.0.0.1:1455/auth/callback?state=good&code=abc&client_id=dynamic_agent_client",
            "http://127.0.0.1:1455/auth/callback?state=good&code=abc&client_id=oaiapp_other"
        ] {
            XCTAssertThrowsError(try OAuthTools.callback(URL(string: address)!, expectedRedirect: redirect, state: "good", knownClientID: "oaiapp_test"))
        }
    }
    func testSignedIdentityRejectsModifiedSignatureAndUnsignedAlgorithm() throws {
        let privateKey = P256.Signing.PrivateKey()
        let publicData = privateKey.publicKey.x963Representation
        let key: [String: Any] = ["kty": "EC", "crv": "P-256", "x": Data(publicData[1..<33]).base64URL, "y": Data(publicData[33..<65]).base64URL]
        let message = Data("a signed ID-token body".utf8)
        let signature = try privateKey.signature(for: message).rawRepresentation
        XCTAssertTrue(try IdentityValidator.verifySignature(message: message, signature: signature, key: key, algorithm: "ES256"))
        XCTAssertFalse(try IdentityValidator.verifySignature(message: Data("changed".utf8), signature: signature, key: key, algorithm: "ES256"))
        XCTAssertFalse(try IdentityValidator.verifySignature(message: message, signature: signature, key: key, algorithm: "none"))
    }
    func testIdentityClaimsRejectWrongAudienceNonceAndExpiredToken() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let valid: [String: Any] = ["iss": "https://auth.openai.com", "aud": "client", "exp": 2000.0, "nonce": "nonce", "sub": "person"]
        XCTAssertEqual(try IdentityValidator.validateClaims(valid, clientID: "client", nonce: "nonce", now: now).subject, "person")
        for (field, value) in [("iss", "https://untrusted.example" as Any), ("aud", "another-client" as Any), ("nonce", "bad" as Any), ("exp", 900.0 as Any)] {
            var changed = valid; changed[field] = value
            XCTAssertThrowsError(try IdentityValidator.validateClaims(changed, clientID: "client", nonce: "nonce", now: now))
        }
    }
    func testPartialStreamCannotReportSuccess() throws {
        var parser = ResponseStream()
        try parser.line("data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hi\"}")
        try parser.line("")
        XCTAssertEqual(parser.text, "Hi")
        XCTAssertThrowsError(try parser.finish())
        try parser.line("data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"usage\":{\"input_tokens\":5,\"output_tokens\":1}}}")
        try parser.line("")
        XCTAssertNoThrow(try parser.finish())
    }
    func testFailedResponseCannotReportSuccess() throws {
        var parser = ResponseStream()
        try parser.line("data: {\"type\":\"response.failed\"}")
        XCTAssertThrowsError(try parser.line(""))
    }
    func testPayloadAcceptsSSEWithoutDependingOnContentType() throws {
        var parser = ProbePayload()
        try parser.line(": keepalive")
        try parser.line("event: response.completed")
        try parser.line("data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[{\"content\":[{\"type\":\"output_text\",\"text\":\"connected\"}]}]}}")
        try parser.line("")
        XCTAssertEqual(try parser.finish().text, "connected")
    }
    func testPayloadAcceptsOnlyCompletedResponseJSON() throws {
        var parser = ProbePayload()
        try parser.line("{\"object\":\"response\",\"status\":\"completed\",\"output\":[{\"content\":[{\"type\":\"output_text\",\"text\":\"connected\"}]}]}")
        XCTAssertEqual(try parser.finish().text, "connected")
        for body in ["{\"object\":\"response\",\"status\":\"in_progress\"}", "{\"error\":{\"message\":\"not allowed\"}}", "{\"status\":\"completed\",\"text\":\"spoofed\"}"] {
            var invalid = ProbePayload()
            try invalid.line(body)
            XCTAssertThrowsError(try invalid.finish())
        }
        var html = ProbePayload()
        XCTAssertThrowsError(try html.line("<!doctype html>"))
    }
    func testByteFramingPreservesEmptyCRLFLinesAndUnicode() throws {
        let body = "event: response.output_text.delta\r\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"연결 성공\"}\r\n\r\nevent: response.completed\r\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\r\n\r\ndata: [DONE]\r\n\r\n"
        var decoder = ProbeByteDecoder()
        for byte in body.utf8 { try decoder.byte(byte) }
        XCTAssertEqual(try decoder.finish().text, "연결 성공")
        XCTAssertEqual(decoder.lineCount, 8)
    }
    @MainActor
    func testActualURLSessionBytesWithMissingContentType() async throws {
        let body = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"connected\"}\n\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"
        let server = try await HTTPFixture(body: body)
        defer { server.stop() }
        let (bytes, response) = try await URLSession.shared.bytes(from: server.url)
        XCTAssertNil((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"))
        var decoder = ProbeByteDecoder()
        for try await byte in bytes { try decoder.byte(byte) }
        XCTAssertEqual(try decoder.finish().text, "connected")
    }
    @MainActor
    func testLoopbackAcceptsCallbackWithoutReflectingSecrets() async throws {
        let listener = LoopbackListener()
        let url = try await listener.start()
        defer { listener.stop() }
        var received: URL?
        listener.onCallback = { received = $0; return true }
        let callback = URL(string: url.absoluteString + "?state=test&code=fake&client_id=fake")!
        let (data, response) = try await URLSession.shared.data(from: callback)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertNotNil(received)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("code=fake"))
    }
}

@MainActor
private final class HTTPFixture {
    private let listener: NWListener
    private var connections: [NWConnection] = []
    private(set) var url: URL!
    init(body: String) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.connections.append(connection)
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { _, _, _, _ in
                    let header = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data((header + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
            }
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: continuation.resume(returning: listener.port!.rawValue)
                case .failed(let error): continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: .main)
        }
        url = URL(string: "http://127.0.0.1:\(port)/fixture")!
    }
    func stop() { listener.cancel(); for connection in connections { connection.cancel() } }
}

private final class RevocationStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static var deliveryDelay: TimeInterval = 0
    static var delayForResponse: ((Data) -> TimeInterval)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            let deliver = {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            }
            let delay = Self.delayForResponse?(data) ?? Self.deliveryDelay
            if delay > 0 { DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: deliver) }
            else { deliver() }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class SessionRevocationTests: XCTestCase {
    private let discovery = Data(#"{"issuer":"https://auth.openai.com","revocation_endpoint":"https://auth.openai.com/oauth/revoke"}"#.utf8)
    private var credential: Credentials {
        Credentials(clientID: "oaiapp_synthetic", subject: "synthetic-session-test", email: "session@example.invalid", accessToken: "synthetic-access", refreshToken: "synthetic-refresh", idToken: "synthetic-id", scopes: ["chatgpt.tokens.use.direct"], expiresAt: .distantFuture)
    }
    private func api() -> PlanAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RevocationStub.self]
        return PlanAPI(session: URLSession(configuration: configuration))
    }
    private func body(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
    override func tearDown() { RevocationStub.handler = nil; RevocationStub.deliveryDelay = 0; RevocationStub.delayForResponse = nil; super.tearDown() }
    func testRevocationAcceptsEmpty200AndPostsOnlyToTrustedEndpoint() async throws {
        var calls = 0
        RevocationStub.handler = { request in
            calls += 1
            if calls == 1 { return (200, self.discovery) }
            XCTAssertEqual(request.url?.absoluteString, "https://auth.openai.com/oauth/revoke")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.url?.query)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(self.body(request), OAuthTools.form(["token": "synthetic-refresh", "token_type_hint": "refresh_token", "client_id": "oaiapp_synthetic"]))
            return (200, Data())
        }
        try await api().revokeSession(credential)
        XCTAssertEqual(calls, 2)
    }
    func testRevocationRetriesTemporaryFailure() async throws {
        var posts = 0
        RevocationStub.handler = { request in
            if request.httpMethod != "POST" { return (200, self.discovery) }
            posts += 1
            return (posts == 1 ? 503 : 200, Data())
        }
        try await api().revokeSession(credential)
        XCTAssertEqual(posts, 2)
    }
    func testRevocationRejectsUntrustedEndpointBeforeSendingToken() async {
        var calls = 0
        RevocationStub.handler = { _ in
            calls += 1
            return (200, Data(#"{"issuer":"https://auth.openai.com","revocation_endpoint":"https://untrusted.example/revoke"}"#.utf8))
        }
        do { try await api().revokeSession(credential); XCTFail("Untrusted endpoint accepted") }
        catch { XCTAssertEqual(calls, 1) }
        for address in ["http://auth.openai.com/revoke", "https://auth.openai.com@untrusted.example/revoke", "https://auth.openai.com/revoke?token=secret", "https://auth.openai.com:444/revoke"] {
            XCTAssertThrowsError(try PlanAPI.validatedRevocationEndpoint(address))
        }
    }
    @MainActor
    func testDisconnectKeepsCredentialsOnFailureAndRegistrationAfterSuccess() async throws {
        let priorAccount = try Vault.read(Credentials.self, key: "account")
        let priorRegistrations = try Vault.read([AccountRegistration].self, key: "registrations")
        defer {
            if let priorAccount { try? Vault.save(priorAccount, key: "account") } else { try? Vault.delete("account") }
            if let priorRegistrations { try? Vault.save(priorRegistrations, key: "registrations") } else { try? Vault.delete("registrations") }
        }
        let model = ProbeModel(loadSavedAccount: false, api: api())
        model.credentials = credential
        try Vault.save(credential, key: "account")
        var reject = true
        RevocationStub.handler = { request in
            if request.httpMethod != "POST" { return (200, self.discovery) }
            return (reject ? 400 : 200, Data())
        }
        await model.disconnect()
        XCTAssertNotNil(model.credentials)
        XCTAssertNotNil(try Vault.read(Credentials.self, key: "account"))
        XCTAssertNotNil(model.error)
        reject = false
        await model.disconnect()
        XCTAssertNil(model.credentials)
        XCTAssertNil(try Vault.read(Credentials.self, key: "account"))
        XCTAssertEqual(model.rememberedRegistration?.clientID, credential.clientID)
        XCTAssertEqual(model.rememberedRegistration?.subject, credential.subject)
        let registrationData = try JSONEncoder().encode(model.registrations)
        XCTAssertFalse(String(decoding: registrationData, as: UTF8.self).contains("synthetic-refresh"))
        XCTAssertNil(model.error)
    }
    @MainActor
    func testSwitchingTabsKeepsReplyInTheRequestConversation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mockAPI = api()
        let auth = ProbeModel(loadSavedAccount: false, api: mockAPI)
        auth.credentials = credential
        auth.models = [ModelChoice(slug: AIConfiguration.model, display_name: AIConfiguration.modelName, visibility: "list")]
        auth.selectedModel = AIConfiguration.model
        let store = StudyStore(directory: directory, api: mockAPI)
        store.switchAccount(credential.subject)
        let received = expectation(description: "Inference request started")
        RevocationStub.deliveryDelay = 0.3
        RevocationStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/responses")
            received.fulfill()
            let reply = #"{"kind":"sentence","text":"Sounds good.","meaning":"좋아요."}"#
            let response: [String: Any] = ["object": "response", "status": "completed", "output": [["content": [["type": "output_text", "text": reply]]]]]
            return (200, try JSONSerialization.data(withJSONObject: response))
        }
        store.mode = .word
        let request = Task { await store.send(text: "좋아요", korean: "", auth: auth, in: .sentence, mood: .polite) }
        await fulfillment(of: [received], timeout: 3)
        XCTAssertEqual(store.sendingModes, [.sentence])
        store.mode = .word
        XCTAssertTrue(store.messages.isEmpty)
        await request.value
        XCTAssertNil(store.error)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertFalse(store.isSending)
        XCTAssertTrue(store.sendingModes.isEmpty)
        store.mode = .sentence
        XCTAssertEqual(store.messages.last?.reply?.text, "Sounds good.")
        XCTAssertEqual(store.messages.last?.mood, .polite)
        XCTAssertEqual(store.chats.count, 1)
        XCTAssertEqual(store.chats.first?.mode, .sentence)
    }

    private func completion(kind: String, text: String) throws -> Data {
        let reply = try JSONSerialization.data(withJSONObject: ["kind": kind, "text": text, "meaning": "테스트 답변"])
        let response: [String: Any] = ["object": "response", "status": "completed", "output": [["content": [["type": "output_text", "text": String(decoding: reply, as: UTF8.self)]]]]]
        return try JSONSerialization.data(withJSONObject: response)
    }
    @MainActor
    func testTabsSendConcurrentlyAndFinishIndependently() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mockAPI = api(), auth = ProbeModel(loadSavedAccount: false)
        auth.credentials = credential
        auth.models = [ModelChoice(slug: AIConfiguration.model, display_name: AIConfiguration.modelName, visibility: "list")]
        auth.selectedModel = AIConfiguration.model
        let store = StudyStore(directory: directory, api: mockAPI); store.switchAccount(credential.subject)
        let sentenceStarted = expectation(description: "Sentence started"), wordStarted = expectation(description: "Word started")
        var requests = [String]()
        let lock = NSLock()
        RevocationStub.delayForResponse = { data in String(decoding: data, as: UTF8.self).contains("WORDREPLY") ? 0.5 : 1.2 }
        RevocationStub.handler = { request in
            let isWord = String(decoding: self.body(request), as: UTF8.self).contains("apple")
            lock.lock(); requests.append(isWord ? "word" : "sentence"); lock.unlock()
            if isWord { wordStarted.fulfill() } else { sentenceStarted.fulfill() }
            return (200, try self.completion(kind: isWord ? "word" : "sentence", text: isWord ? "WORDREPLY" : "SENTENCEREPLY"))
        }
        let sentence = Task { await store.send(text: "안녕하세요", korean: "", auth: auth) }
        await fulfillment(of: [sentenceStarted], timeout: 3)
        store.mode = .word
        let word = Task { await store.send(text: "apple", korean: "", auth: auth) }
        await fulfillment(of: [wordStarted], timeout: 3)
        XCTAssertEqual(store.sendingModes, [.word, .sentence])
        await store.send(text: "duplicate blocked", korean: "", auth: auth)
        await word.value
        XCTAssertFalse(store.isSending(in: .word))
        XCTAssertTrue(store.isSending(in: .sentence))
        XCTAssertEqual(store.messages.last?.reply?.text, "WORDREPLY")
        await sentence.value
        store.mode = .sentence
        XCTAssertEqual(store.messages.last?.reply?.text, "SENTENCEREPLY")
        XCTAssertEqual(store.chats.count, 2)
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(store.isSending)
    }
    @MainActor
    func testOneTabFailureDoesNotStopOrClearTheOtherTab() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mockAPI = api(), auth = ProbeModel(loadSavedAccount: false)
        auth.credentials = credential
        auth.models = [ModelChoice(slug: AIConfiguration.model, display_name: AIConfiguration.modelName, visibility: "list")]
        auth.selectedModel = AIConfiguration.model
        let store = StudyStore(directory: directory, api: mockAPI); store.switchAccount(credential.subject)
        let sentenceStarted = expectation(description: "Sentence started")
        var failWord = true
        RevocationStub.delayForResponse = { data in String(decoding: data, as: UTF8.self).contains("SENTENCEREPLY") ? 0.7 : 0.05 }
        RevocationStub.handler = { request in
            let isWord = String(decoding: self.body(request), as: UTF8.self).contains("apple")
            if isWord && failWord { return (500, Data()) }
            if !isWord { sentenceStarted.fulfill() }
            return (200, try self.completion(kind: isWord ? "word" : "sentence", text: isWord ? "WORDREPLY" : "SENTENCEREPLY"))
        }
        let sentence = Task { await store.send(text: "안녕하세요", korean: "", auth: auth) }
        await fulfillment(of: [sentenceStarted], timeout: 3)
        store.mode = .word
        await store.send(text: "apple", korean: "", auth: auth)
        XCTAssertNotNil(store.currentError)
        XCTAssertTrue(store.isSending(in: .sentence))
        store.mode = .sentence
        XCTAssertNil(store.currentError)
        await sentence.value
        XCTAssertEqual(store.messages.last?.reply?.text, "SENTENCEREPLY")
        store.mode = .word
        XCTAssertNotNil(store.currentError)
        failWord = false
        await store.send(text: "", korean: "", auth: auth, retry: true)
        XCTAssertNil(store.currentError)
        XCTAssertEqual(store.messages.count, 2)
        XCTAssertEqual(store.messages.last?.reply?.text, "WORDREPLY")
    }
    @MainActor
    func testSimultaneousRequestsShareOneCredentialRefresh() async throws {
        let prior = try Vault.read(Credentials.self, key: "account")
        defer { if let prior { try? Vault.save(prior, key: "account") } else { try? Vault.delete("account") } }
        let auth = ProbeModel(loadSavedAccount: false, api: api())
        auth.credentials = Credentials(clientID: credential.clientID, subject: credential.subject, email: credential.email, accessToken: "expired", refreshToken: "synthetic-refresh", idToken: "synthetic-id", scopes: credential.scopes, expiresAt: .distantPast)
        var posts = 0
        RevocationStub.deliveryDelay = 0.2
        RevocationStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/accounts/oauth/token")
            posts += 1
            return (200, Data(#"{"access_token":"fresh-access","refresh_token":"rotated-refresh","expires_in":3600,"token_type":"bearer","scope":"chatgpt.tokens.use.direct"}"#.utf8))
        }
        async let first = auth.activeCredential()
        async let second = auth.activeCredential()
        let results = try await (first, second)
        XCTAssertEqual(results.0.accessToken, "fresh-access")
        XCTAssertEqual(results.1.accessToken, "fresh-access")
        XCTAssertEqual(auth.credentials?.refreshToken, "rotated-refresh")
        XCTAssertEqual(posts, 1)
    }

}
