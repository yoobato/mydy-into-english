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
