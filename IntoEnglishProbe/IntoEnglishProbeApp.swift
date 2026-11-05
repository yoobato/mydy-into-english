import SwiftUI
import SafariServices

@main
struct IntoEnglishProbeApp: App {
    var body: some Scene { WindowGroup { IntoEnglishView().preferredColorScheme(.light) } }
}

struct LoginBrowser: UIViewControllerRepresentable {
    let url: URL
    let onDone: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onDone) }
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.delegate = context.coordinator
        controller.preferredControlTintColor = UIColor(red: 0.75, green: 0.36, blue: 0.25, alpha: 1)
        return controller
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDone: () -> Void
        init(_ onDone: @escaping () -> Void) { self.onDone = onDone }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onDone() }
    }
}
