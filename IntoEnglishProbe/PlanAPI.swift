import Foundation

final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct ModelChoice: Decodable, Identifiable {
    let slug: String
    let display_name: String
    let visibility: String?
    var id: String { slug }
}
struct Completion {
    let text: String
}

struct ResponseStream {
    private var dataLines = [String]()
    private(set) var text = ""
    private(set) var completed = false
    mutating func line(_ line: String) throws {
        guard !line.isEmpty else { try flush(); return }
        if line.hasPrefix("data:") { dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
    }
    mutating func finish() throws {
        try flush()
        guard completed else { throw ProbeError("AI 스트림이 완료되기 전에 연결이 끝났어요. 성공으로 처리하지 않았어요.") }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProbeError("AI 응답이 비어 있어요.") }
    }
    private mutating func flush() throws {
        guard !dataLines.isEmpty else { return }
        let data = dataLines.joined(separator: "\n"); dataLines.removeAll()
        if data == "[DONE]" { return }
        guard let bytes = data.data(using: .utf8), let event = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else {
            throw ProbeError("AI 스트림 형식을 읽지 못했어요.")
        }
        switch event["type"] as? String {
        case "response.output_text.delta": text += event["delta"] as? String ?? ""
        case "response.completed":
            guard let response = event["response"] as? [String: Any], response["status"] as? String == "completed" else {
                throw ProbeError("AI 요청의 완료 상태를 확인하지 못했어요.")
            }
            completed = true
            if text.isEmpty, let output = response["output"] as? [[String: Any]] {
                text = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }
                    .filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }.joined()
            }
        case "error", "response.failed", "response.incomplete":
            let response = event["response"] as? [String: Any]
            let detail = event["error"] as? [String: Any] ?? response?["error"] as? [String: Any]
            let raw = detail?["code"] as? String ?? ""
            let code = raw.range(of: "^[A-Za-z0-9_-]{1,100}$", options: .regularExpression) != nil ? raw : "incomplete_response"
            throw ProbeError("AI 요청이 완료되지 않았어요 (\(code)). 다시 보내려면 전송 버튼을 눌러 주세요.")
        default: break
        }
        if text.utf8.count > 262144 { throw ProbeError("응답 크기 제한을 초과했어요.") }
    }
}

/// Inspect the body, since intermediaries may omit or replace the SSE content type.
/// A JSON fallback still requires an actual completed OpenAI response with text.
struct ProbePayload {
    enum Format { case unknown, sse, json }
    private var format: Format = .unknown
    private var jsonLines: [String] = []
    private var size = 0
    private var stream = ResponseStream()
    mutating func line(_ raw: String) throws {
        let line = raw.replacingOccurrences(of: "\u{FEFF}", with: "")
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if format == .unknown {
            if trimmed.isEmpty { return }
            if trimmed.hasPrefix("data:") || trimmed.hasPrefix("event:") || trimmed.hasPrefix(":") { format = .sse }
            else if trimmed.hasPrefix("{") { format = .json }
            else { throw ProbeError("AI 응답 본문이 SSE 또는 JSON 형식이 아니에요.") }
        }
        switch format {
        case .sse: try stream.line(line)
        case .json:
            size += line.utf8.count
            guard size <= 262144 else { throw ProbeError("JSON 응답 크기 제한을 초과했어요.") }
            jsonLines.append(line)
        case .unknown: break
        }
    }
    mutating func finish() throws -> ResponseStream {
        if format == .json {
            let data = Data(jsonLines.joined(separator: "\n").utf8)
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                throw ProbeError("JSON 응답을 읽지 못했어요.")
            }
            let event: [String: Any]
            if object["type"] as? String == "response.completed" {
                event = object
            } else if object["object"] as? String == "response", object["status"] as? String == "completed" {
                event = ["type": "response.completed", "response": object]
            } else {
                throw ProbeError("JSON 응답이 왔지만 AI 요청 완료를 확인할 수 없어요.")
            }
            let eventData = try JSONSerialization.data(withJSONObject: event)
            try stream.line("data: " + String(decoding: eventData, as: UTF8.self))
            try stream.line("")
        }
        try stream.finish()
        return stream
    }
}

/// Preserve empty SSE separator lines and fragmented UTF-8 instead of using AsyncBytes.lines.
struct ProbeByteDecoder {
    private var lineBytes = Data()
    private var payload = ProbePayload()
    private(set) var byteCount = 0
    private(set) var lineCount = 0
    mutating func byte(_ value: UInt8) throws {
        byteCount += 1
        guard byteCount <= 1048576 else { throw ProbeError("검증용 응답 전체 크기 제한을 초과했어요.") }
        if value == 10 {
            try flushLine()
        } else {
            lineBytes.append(value)
            guard lineBytes.count <= 262144 else { throw ProbeError("응답 한 줄의 크기 제한을 초과했어요.") }
        }
    }
    private mutating func flushLine() throws {
        if lineBytes.last == 13 { lineBytes.removeLast() }
        guard let line = String(data: lineBytes, encoding: .utf8) else { throw ProbeError("응답의 UTF-8 문자를 읽지 못했어요.") }
        lineBytes.removeAll(keepingCapacity: true)
        lineCount += 1
        try payload.line(line)
    }
    mutating func finish() throws -> ResponseStream {
        if !lineBytes.isEmpty { try flushLine() }
        return try payload.finish()
    }
}

final class PlanAPI {
    let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpCookieStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    func token(_ form: [String: String]) async throws -> TokenReply {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OAuthTools.form(form)
        let (data, response) = try await session.data(for: request)
        try check(response, body: data)
        let result = try JSONDecoder().decode(TokenReply.self, from: data)
        guard result.token_type.lowercased() == "bearer", !result.access_token.isEmpty, result.expires_in > 0 else { throw ProbeError("토큰 응답을 검증하지 못했어요.") }
        return result
    }
    func models(_ credential: Credentials) async throws -> [ModelChoice] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        try check(response, body: data)
        struct Catalog: Decodable { let models: [ModelChoice] }
        let models = try JSONDecoder().decode(Catalog.self, from: data).models.filter { $0.visibility == "list" }
        guard !models.isEmpty else { throw ProbeError("이 계정으로 선택할 수 있는 모델이 없어요.") }
        return models
    }
    func respond(_ credential: Credentials, snapshot: RequestSnapshot) async throws -> Completion {
        guard credential.permitsInference else { throw ProbeError("ChatGPT 요금제 사용 권한이 없어요.") }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: snapshot.body)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProbeError("HTTP 응답을 확인하지 못했어요.") }
        if !(200..<300).contains(http.statusCode) {
            var body = Data()
            for try await byte in bytes { body.append(byte); if body.count >= 8192 { break } }
            try check(response, body: body)
        }
        var decoder = ProbeByteDecoder()
        do {
            for try await byte in bytes { try decoder.byte(byte) }
            let parser = try decoder.finish()
            return Completion(text: parser.text)
        } catch {
            let mediaType = http.value(forHTTPHeaderField: "Content-Type")?.components(separatedBy: ";").first ?? "없음"
            let safeType = String(mediaType.filter { $0.isLetter || $0.isNumber || "/-+.".contains($0) }.prefix(80))
            throw ProbeError("\(error.localizedDescription)\nHTTP \(http.statusCode) · Content-Type: \(safeType) · \(decoder.byteCount) bytes / \(decoder.lineCount) lines")
        }
    }
    private func check(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ProbeError("HTTP 응답을 확인하지 못했어요.") }
        guard !(200..<300).contains(http.statusCode) else { return }
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let raw = (json?["error"] as? [String: Any])?["code"] as? String ?? ""
        // Never surface raw bodies, authorization URLs, tokens, or user-provided error descriptions.
        let code = raw.range(of: "^[A-Za-z0-9_-]{1,100}$", options: .regularExpression) != nil ? raw : "unclassified"
        let hint: String
        switch code {
        case "subscription_sharing_user_not_eligible": hint = "이 계정 또는 요금제는 현재 이 연동을 사용할 수 없어요."
        case "subscription_sharing_usage_limit_exceeded": hint = "ChatGPT 또는 이 앱의 사용 한도에 도달했어요. ChatGPT 사용량 설정을 확인해 주세요."
        case "subscription_sharing_unsupported_capability", "subscription_sharing_route_not_supported": hint = "이 연동에서 지원하지 않는 모델·요청·경로예요."
        case "invalid_grant", "invalid_refresh_token", "refresh_token_reused": hint = "로그인 세션을 갱신할 수 없어요. 연결을 해제한 뒤 다시 로그인해 주세요."
        default: hint = "접근 권한 또는 서비스 상태를 확인해야 해요."
        }
        throw ProbeError("HTTP \(http.statusCode) · \(code)\n\(hint)")
    }
}
