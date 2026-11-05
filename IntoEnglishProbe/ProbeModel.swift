import Foundation
import SwiftUI

struct BrowserDestination: Identifiable { let id = UUID(); let url: URL }
struct PendingLogin {
    let state: String
    let nonce: String
    let verifier: String
    let redirect: URL
}

@MainActor
final class ProbeModel: ObservableObject {
    @Published var credentials: Credentials?
    @Published var browser: BrowserDestination?
    @Published var models: [ModelChoice] = []
    @Published var selectedModel = ""
    @Published var busy = false
    @Published var error: String?
    @Published var result: Completion?
    @Published var events: [String] = []
    @Published var loginStatus = "미확인"
    @Published var permissionStatus = "미확인"
    @Published var modelsStatus = "미확인"
    @Published var responseStatus = "미확인"
    private var pending: PendingLogin?
    private let listener = LoopbackListener()
    private let api = PlanAPI()

    init() {
        do {
            credentials = try Vault.read(Credentials.self, key: "account")
            if let credentials {
                loginStatus = "저장된 계정"
                permissionStatus = credentials.permitsInference ? "허용됨" : "미허용"
                record("이 기기의 Keychain에서 계정을 불러왔어요. AI 요청은 아직 보내지 않았어요.")
            }
        } catch { self.error = error.localizedDescription }
    }
    func signIn() async {
        guard !busy else { return }
        busy = true; error = nil; result = nil
        loginStatus = "준비 중"
        do {
            let host: String
            if let saved = try Vault.read(String.self, key: "host") { host = saved }
            else { host = "urn:uuid:\(UUID().uuidString.lowercased())"; try Vault.save(host, key: "host") }
            let state = try OAuthTools.random(), nonce = try OAuthTools.random(), verifier = try OAuthTools.random()
            listener.onFailure = { [weak self] message in
                guard let self else { return }
                self.pending = nil; self.browser = nil; self.busy = false
                self.loginStatus = "실패"; self.error = message
                self.record("기기 내 로그인 콜백을 받지 못했어요.")
            }
            listener.onCallback = { [weak self] url in self?.acceptCallback(url) ?? false }
            let redirect = try await listener.start()
            pending = PendingLogin(state: state, nonce: nonce, verifier: verifier, redirect: redirect)
            var components = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: credentials?.clientID ?? "dynamic_agent_client"),
                URLQueryItem(name: "ext_agent_host_id", value: host),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "redirect_uri", value: redirect.absoluteString),
                URLQueryItem(name: "scope", value: "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"),
                URLQueryItem(name: "resource", value: "https://api.openai.com/v1"),
                URLQueryItem(name: "state", value: state), URLQueryItem(name: "nonce", value: nonce),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "code_challenge", value: OAuthTools.challenge(verifier))
            ]
            if credentials == nil { components.queryItems?.append(URLQueryItem(name: "agent_name_hint", value: "Into English")) }
            loginStatus = "로그인 대기"
            record("127.0.0.1의 기기 내부 콜백이 준비됐어요. ChatGPT 로그인과 사용 권한 승인을 기다립니다.")
            browser = BrowserDestination(url: components.url!)
        } catch {
            pending = nil; listener.stop(); busy = false
            loginStatus = "실패"; self.error = error.localizedDescription
        }
    }
    private func acceptCallback(_ url: URL) -> Bool {
        guard let attempt = pending else { return false }
        let callback: (code: String, clientID: String)
        do {
            callback = try OAuthTools.callback(url, expectedRedirect: attempt.redirect, state: attempt.state, knownClientID: credentials?.clientID)
        } catch {
            // An invalid local request must not replace credentials or complete authentication.
            self.error = error.localizedDescription
            return false
        }
        pending = nil
        browser = nil
        loginStatus = "서명 검증 중"
        record("콜백의 주소와 state를 확인했어요. 코드 교환 및 ID 토큰 서명을 검증합니다.")
        let prior = credentials
        Task {
            defer { listener.stop(); busy = false }
            do {
                let tokens = try await api.token(["grant_type": "authorization_code", "client_id": callback.clientID,
                    "code": callback.code, "code_verifier": attempt.verifier,
                    "redirect_uri": attempt.redirect.absoluteString, "resource": "https://api.openai.com/v1"])
                guard let idToken = tokens.id_token else { throw ProbeError("ID 토큰이 없어 로그인을 완료하지 않았어요.") }
                let identity = try await IdentityValidator.verify(idToken, clientID: callback.clientID, nonce: attempt.nonce, session: api.session)
                if let prior, prior.subject != identity.subject { throw ProbeError("다른 계정의 응답이에요. 기존 연결을 해제하고 다시 로그인해 주세요.") }
                let credential = Credentials(clientID: callback.clientID, subject: identity.subject, email: identity.email,
                    accessToken: tokens.access_token, refreshToken: tokens.refresh_token, idToken: idToken,
                    scopes: (tokens.scope ?? "").split(separator: " ").map(String.init),
                    expiresAt: Date().addingTimeInterval(tokens.expires_in))
                try Vault.save(credential, key: "account")
                credentials = credential; loginStatus = "검증 완료"
                permissionStatus = credential.permitsInference ? "허용됨" : "미허용"
                models = []; selectedModel = ""; modelsStatus = "미확인"; responseStatus = "미확인"
                record("계정 서명 검증과 Keychain 저장을 완료했어요.")
                guard credential.permitsInference else {
                    throw ProbeError("로그인은 됐지만 ChatGPT 요금제 사용 권한은 허용되지 않았어요. AI 요청을 보내지 않았어요.")
                }
                record("ChatGPT 요금제 사용 권한을 확인했어요. 모델 목록과 AI 요청은 아래 버튼으로 따로 검사하세요.")
            } catch {
                if credentials?.idToken != prior?.idToken && credentials != nil { loginStatus = "검증 완료" }
                else { loginStatus = "실패" }
                self.error = error.localizedDescription
                record("로그인 검증 단계가 끝났어요. 화면의 상태와 오류를 확인해 주세요.")
            }
        }
        return true
    }
    func browserDismissed() {
        guard pending != nil else { return }
        pending = nil; listener.stop(); browser = nil; busy = false
        loginStatus = credentials == nil ? "취소됨" : "저장된 계정"
        record("사용자가 로그인 창을 닫았어요. AI 요청은 보내지 않았어요.")
    }
    func activeCredential() async throws -> Credentials {
        guard let current = credentials else { throw ProbeError("먼저 ChatGPT 계정을 연결해 주세요.") }
        guard current.permitsInference else { throw ProbeError("ChatGPT 요금제 사용 권한이 필요해요.") }
        guard current.expiresAt <= Date().addingTimeInterval(60) else { return current }
        guard let refresh = current.refreshToken else { throw ProbeError("세션이 만료되었어요. 다시 로그인해 주세요.") }
        let updated = try await api.token(["grant_type": "refresh_token", "client_id": current.clientID,
            "refresh_token": refresh, "resource": "https://api.openai.com/v1"])
        let replacement = Credentials(clientID: current.clientID, subject: current.subject, email: current.email,
            accessToken: updated.access_token, refreshToken: updated.refresh_token ?? current.refreshToken,
            idToken: current.idToken,
            scopes: updated.scope.map { $0.split(separator: " ").map(String.init) } ?? current.scopes,
            expiresAt: Date().addingTimeInterval(updated.expires_in))
        try Vault.save(replacement, key: "account")
        credentials = replacement
        permissionStatus = replacement.permitsInference ? "허용됨" : "미허용"
        guard replacement.permitsInference else { throw ProbeError("세션 갱신 후 요금제 사용 권한이 없어 요청을 멈췄어요.") }
        return replacement
    }
    func loadModels() async {
        guard !busy else { return }
        busy = true; error = nil; modelsStatus = "확인 중"
        defer { busy = false }
        do {
            let credential = try await activeCredential()
            models = try await api.models(credential)
            // Preserve the account catalog's ordering; never assume API-key model access applies here.
            let preference = UserDefaults.standard.string(forKey: "model.\(credential.subject)")
            selectedModel = models.first(where: { $0.slug == preference })?.slug
                ?? models.first(where: { $0.slug == "gpt-6.1-sol" })?.slug
                ?? models.first(where: { $0.slug.contains("sol") })?.slug
                ?? models.first?.slug ?? ""
            modelsStatus = "\(models.count)개 확인"
            record("이 계정에서 사용할 수 있는 모델 목록을 조회했어요. 추론 요청은 아직 보내지 않았어요.")
        } catch { modelsStatus = "실패"; self.error = error.localizedDescription }
    }
    func sendProbe() async {
        guard !busy, models.contains(where: { $0.slug == selectedModel }) else { return }
        busy = true; error = nil; result = nil; responseStatus = "응답 대기"
        defer { busy = false }
        do {
            let credential = try await activeCredential()
            let completion = try await api.probe(credential, model: selectedModel)
            result = completion; responseStatus = "완료 확인"
            record("response.completed와 실제 응답을 확인했어요. 이 요청의 ChatGPT 요금제 사용 검증에 성공했어요.")
        } catch { responseStatus = "실패"; self.error = error.localizedDescription; record("AI 요청이 완료되지 않았어요. 다른 결제 방식으로 전환하거나 자동 재시도하지 않았어요.") }
    }
    func disconnect() {
        guard !busy else { return }
        do {
            try Vault.delete("account")
            credentials = nil; models = []; selectedModel = ""; result = nil; error = nil
            loginStatus = "미확인"; permissionStatus = "미확인"; modelsStatus = "미확인"; responseStatus = "미확인"
            events = ["이 기기의 저장된 계정을 삭제했어요. 권한 자체를 철회하려면 ChatGPT 설정에서 앱 연결을 해제하세요."]
        } catch { self.error = error.localizedDescription }
    }
    private func record(_ message: String) { events.append(message) }
}
