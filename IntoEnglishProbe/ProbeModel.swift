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
    @Published var selectedModel = "" {
        didSet {
            if !selectedModel.isEmpty, let subject = credentials?.subject {
                UserDefaults.standard.set(selectedModel, forKey: "model.\(subject)")
            }
        }
    }
    @Published var busy = false
    @Published var error: String?
    private var pending: PendingLogin?
    private let listener = LoopbackListener()
    private let api = PlanAPI()

    init(loadSavedAccount: Bool = true) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-signed-in") {
                credentials = Credentials(clientID: "synthetic-client", subject: "synthetic-ui-account", email: "test@example.invalid", accessToken: "synthetic-not-a-token", refreshToken: nil, idToken: "synthetic-id-token", scopes: ["chatgpt.tokens.use.direct"], expiresAt: .distantFuture)
                models = [ModelChoice(slug: AIConfiguration.model, display_name: AIConfiguration.modelName, visibility: "list"), ModelChoice(slug: "gpt-6-astra", display_name: "GPT-6 Astra", visibility: "list")]
                selectedModel = AIConfiguration.model
            }
            return
        }
        #endif
        guard loadSavedAccount else { return }
        do {
            credentials = try Vault.read(Credentials.self, key: "account")
        } catch { self.error = error.localizedDescription }
    }
    func signIn() async {
        guard !busy else { return }
        busy = true; error = nil
        do {
            let host: String
            if let saved = try Vault.read(String.self, key: "host") { host = saved }
            else { host = "urn:uuid:\(UUID().uuidString.lowercased())"; try Vault.save(host, key: "host") }
            let state = try OAuthTools.random(), nonce = try OAuthTools.random(), verifier = try OAuthTools.random()
            listener.onFailure = { [weak self] message in
                guard let self else { return }
                self.pending = nil; self.browser = nil; self.busy = false
                self.error = message
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
            browser = BrowserDestination(url: components.url!)
        } catch {
            pending = nil; listener.stop(); busy = false
            self.error = error.localizedDescription
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
                credentials = credential
                models = []; selectedModel = ""
                guard credential.permitsInference else {
                    throw ProbeError("로그인은 됐지만 ChatGPT 요금제 사용 권한은 허용되지 않았어요. AI 요청을 보내지 않았어요.")
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
        return true
    }
    func browserDismissed() {
        guard pending != nil else { return }
        pending = nil; listener.stop(); browser = nil; busy = false
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
        guard replacement.permitsInference else { throw ProbeError("세션 갱신 후 요금제 사용 권한이 없어 요청을 멈췄어요.") }
        return replacement
    }
    func loadModels() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let credential = try await activeCredential()
            models = try await api.models(credential)
            let preference = UserDefaults.standard.string(forKey: "model.\(credential.subject)")
            selectedModel = AIConfiguration.choose(models, preferred: preference)
            try AIConfiguration.validate(models, selected: selectedModel)
        } catch { self.error = error.localizedDescription }
    }
    func disconnect() {
        guard !busy else { return }
        do {
            try Vault.delete("account")
            credentials = nil; models = []; selectedModel = ""; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
