import Foundation
import CryptoKit
import Security

struct ProbeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum OAuthTools {
    static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ProbeError("안전한 로그인 값을 생성하지 못했어요.")
        }
        return Data(bytes).base64URL
    }
    static func challenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
    }
    static func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(values.sorted(by: { $0.key < $1.key }).map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }
    static func callback(_ url: URL, expectedRedirect: URL, state: String, knownClientID: String?) throws -> (code: String, clientID: String) {
        guard url.scheme == expectedRedirect.scheme, url.host == "127.0.0.1",
              url.port == expectedRedirect.port, url.path == expectedRedirect.path,
              url.user == nil, url.password == nil, url.fragment == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            throw ProbeError("로그인 콜백 주소가 일치하지 않아요.")
        }
        // Reject duplicates instead of silently selecting an attacker-controlled value.
        let groups = Dictionary(grouping: items, by: \.name)
        guard !groups.values.contains(where: { $0.count > 1 }) else {
            throw ProbeError("중복된 로그인 응답을 거부했어요.")
        }
        let params = groups.mapValues { $0[0].value ?? "" }
        guard params["state"] == state else { throw ProbeError("로그인 state 검증에 실패했어요.") }
        if params["error"] != nil { throw ProbeError("로그인이 취소되었거나 권한이 허용되지 않았어요.") }
        guard let code = params["code"], !code.isEmpty else { throw ProbeError("로그인 코드가 없어요.") }
        let client = params["client_id"] ?? knownClientID
        guard let client, !client.isEmpty, client != "dynamic_agent_client" else {
            throw ProbeError("사용자별 client_id를 받지 못했어요.")
        }
        if let knownClientID, client != knownClientID { throw ProbeError("계정의 client_id가 변경되어 응답을 거부했어요.") }
        return (code, client)
    }
}

extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        let raw = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: raw + String(repeating: "=", count: (4 - raw.count % 4) % 4))
    }
}

struct Credentials: Codable {
    let clientID: String
    let subject: String
    let email: String
    let accessToken: String
    let refreshToken: String?
    let idToken: String
    let scopes: [String]
    let expiresAt: Date
    var permitsInference: Bool { scopes.contains("chatgpt.tokens.use.direct") }
}

enum Vault {
    private static let service = "kr.mydy.intoenglish.probe"
    static func read<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw ProbeError("Keychain을 읽지 못했어요 (\(status)).") }
        return try JSONDecoder().decode(type, from: data)
    }
    static func save<T: Encodable>(_ value: T, key: String) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw ProbeError("Keychain 갱신 실패 (\(update)).") }
        var entry = query
        entry[kSecValueData as String] = data
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw ProbeError("Keychain 저장에 실패했어요.") }
    }
    static func delete(_ key: String) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: key] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ProbeError("Keychain 삭제 실패 (\(status)).") }
    }
}

struct TokenReply: Decodable {
    let access_token: String
    let refresh_token: String?
    let id_token: String?
    let expires_in: Double
    let scope: String?
    let token_type: String
}

struct VerifiedIdentity { let subject: String; let email: String }

enum IdentityValidator {
    static func validateClaims(_ claims: [String: Any], clientID: String, nonce: String, now: Date = Date()) throws -> VerifiedIdentity {
        let audience = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        guard claims["iss"] as? String == "https://auth.openai.com", audience.contains(clientID),
              let exp = claims["exp"] as? Double, exp > now.timeIntervalSince1970,
              claims["nonce"] as? String == nonce,
              let subject = claims["sub"] as? String, !subject.isEmpty else {
            throw ProbeError("ID 토큰의 발급자·대상·만료·nonce 검증에 실패했어요.")
        }
        if let nbf = claims["nbf"] as? Double, nbf > now.timeIntervalSince1970 + 60 {
            throw ProbeError("아직 유효하지 않은 ID 토큰이에요.")
        }
        if audience.count > 1, claims["azp"] as? String != clientID { throw ProbeError("ID 토큰의 azp가 일치하지 않아요.") }
        return VerifiedIdentity(subject: subject, email: claims["email"] as? String ?? "연결된 ChatGPT 계정")
    }
    static func verify(_ jwt: String, clientID: String, nonce: String, session: URLSession) async throws -> VerifiedIdentity {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let headerData = Data(base64URL: parts[0]), let claimsData = Data(base64URL: parts[1]),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let claims = try JSONSerialization.jsonObject(with: claimsData) as? [String: Any],
              let signature = Data(base64URL: parts[2]), let kid = header["kid"] as? String,
              let algorithm = header["alg"] as? String, ["RS256", "ES256"].contains(algorithm) else {
            throw ProbeError("지원하지 않는 ID 토큰 형식이에요.")
        }
        let (discoveryData, discoveryResponse) = try await session.data(from: URL(string: "https://auth.openai.com/.well-known/openid-configuration")!)
        guard (discoveryResponse as? HTTPURLResponse)?.statusCode == 200,
              let discovery = try JSONSerialization.jsonObject(with: discoveryData) as? [String: Any],
              discovery["issuer"] as? String == "https://auth.openai.com",
              let address = discovery["jwks_uri"] as? String, let jwksURL = URL(string: address),
              jwksURL.scheme == "https", jwksURL.host == "auth.openai.com", jwksURL.user == nil else {
            throw ProbeError("공식 인증 메타데이터를 검증하지 못했어요.")
        }
        let (keysData, keysResponse) = try await session.data(from: jwksURL)
        guard (keysResponse as? HTTPURLResponse)?.statusCode == 200,
              let jwks = try JSONSerialization.jsonObject(with: keysData) as? [String: Any],
              let keys = jwks["keys"] as? [[String: Any]],
              let key = keys.first(where: { $0["kid"] as? String == kid }),
              key["use"] == nil || key["use"] as? String == "sig",
              key["alg"] == nil || key["alg"] as? String == algorithm else { throw ProbeError("공식 서명 키를 확인하지 못했어요.") }
        let message = Data("\(parts[0]).\(parts[1])".utf8)
        guard try verifySignature(message: message, signature: signature, key: key, algorithm: algorithm) else {
            throw ProbeError("ID 토큰 서명이 유효하지 않아요.")
        }
        return try validateClaims(claims, clientID: clientID, nonce: nonce)
    }
    static func verifySignature(message: Data, signature: Data, key: [String: Any], algorithm: String) throws -> Bool {
        if algorithm == "ES256" {
            guard key["kty"] as? String == "EC", key["crv"] as? String == "P-256",
                  let x = key["x"] as? String, let y = key["y"] as? String,
                  let xd = Data(base64URL: x), let yd = Data(base64URL: y), xd.count == 32, yd.count == 32 else { return false }
            let publicKey = try P256.Signing.PublicKey(x963Representation: Data([4]) + xd + yd)
            return publicKey.isValidSignature(try P256.Signing.ECDSASignature(rawRepresentation: signature), for: message)
        }
        guard algorithm == "RS256", key["kty"] as? String == "RSA",
              let n = key["n"] as? String, let e = key["e"] as? String,
              let modulus = Data(base64URL: n), let exponent = Data(base64URL: e), modulus.count >= 256 else { return false }
        let der = tagged(0x30, integer(modulus) + integer(exponent))
        guard let rsa = SecKeyCreateWithData(der as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, nil) else { return false }
        return SecKeyVerifySignature(rsa, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, signature as CFData, nil)
    }
    private static func integer(_ bytes: Data) -> Data {
        var value = Data(bytes.drop(while: { $0 == 0 }))
        if value.isEmpty { value = Data([0]) }
        if value.first! & 0x80 != 0 { value.insert(0, at: 0) }
        return tagged(0x02, value)
    }
    private static func tagged(_ tag: UInt8, _ payload: Data) -> Data {
        var length = payload.count
        if length < 128 { return Data([tag, UInt8(length)]) + payload }
        var bytes = [UInt8]()
        while length > 0 { bytes.insert(UInt8(length & 255), at: 0); length >>= 8 }
        return Data([tag, 0x80 | UInt8(bytes.count)]) + Data(bytes) + payload
    }
}
