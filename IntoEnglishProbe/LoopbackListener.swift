import Foundation
import Network

/// Experimental iOS loopback transport; binds only to 127.0.0.1, never LAN interfaces.
@MainActor
final class LoopbackListener {
    private var listener: NWListener?
    private var ready: CheckedContinuation<URL, Error>?
    private var timeout: Task<Void, Never>?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private(set) var redirect: URL?
    var onCallback: ((URL) -> Bool)?
    var onFailure: ((String) -> Void)?

    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener.port else { self.fail("로컬 콜백 포트를 열지 못했어요."); return }
                    let url = URL(string: "http://127.0.0.1:\(port.rawValue)/auth/callback")!
                    self.redirect = url
                    self.ready?.resume(returning: url)
                    self.ready = nil
                    self.timeout = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(300)) } catch { return }
                        self?.fail("로그인 대기 시간이 지났어요. 다시 시도해 주세요.")
                    }
                case .failed: self.fail("기기 내 콜백 리스너를 시작하지 못했어요.")
                default: break
                }
            }
                }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                guard let self else { connection.cancel(); return }
                guard self.connections.count < 8 else { connection.cancel(); return }
                self.connections[ObjectIdentifier(connection)] = connection
                connection.start(queue: .main)
                self.receive(connection, accumulated: Data())
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    self?.close(connection)
                }
            }
                }
            listener.start(queue: .main)
        }
    }
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor in
            guard let self else { connection.cancel(); return }
            let bytes = accumulated + (data ?? Data())
            guard bytes.count <= 16384 else { self.respond(connection, status: "431 Request Header Fields Too Large", success: false); return }
            if let header = String(data: bytes, encoding: .utf8), header.contains("\r\n\r\n") {
                let lines = header.components(separatedBy: "\r\n")
                let request = (lines.first ?? "").split(separator: " ")
                guard request.count == 3, request[0] == "GET", request[1].hasPrefix("/auth/callback?"),
                      let redirect = self.redirect,
                      lines.contains(where: { $0.lowercased() == "host: 127.0.0.1:\(redirect.port!)" }),
                      let url = URL(string: "http://127.0.0.1:\(redirect.port!)\(request[1])") else {
                    self.respond(connection, status: "400 Bad Request", success: false); return
                }
                let accepted = self.onCallback?(url) ?? false
                self.respond(connection, status: accepted ? "200 OK" : "400 Bad Request", success: accepted)
                if accepted {
                    self.timeout?.cancel()
                    self.listener?.cancel()
                    self.listener = nil
                }
            } else if complete || error != nil { self.close(connection) }
            else { self.receive(connection, accumulated: bytes) }
        }
    }
        }
    private func respond(_ connection: NWConnection, status: String, success: Bool) {
        let text = success ? "Login received. Return to Into English." : "Invalid callback. Return to Into English and try again."
        let body = "<!doctype html><meta name=viewport content='width=device-width'><title>Into English</title><p>\(text)</p>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in Task { @MainActor in self?.close(connection) } })
    }
    private func close(_ connection: NWConnection) {
        connection.cancel()
        connections.removeValue(forKey: ObjectIdentifier(connection))
    }
    private func fail(_ message: String) {
        let handler = onFailure
        stop()
        handler?(message)
    }
    func stop() {
        ready?.resume(throwing: ProbeError("로그인 준비가 취소되었어요."))
        ready = nil
        timeout?.cancel(); timeout = nil
        listener?.cancel(); listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        onCallback = nil; onFailure = nil
    }
}
