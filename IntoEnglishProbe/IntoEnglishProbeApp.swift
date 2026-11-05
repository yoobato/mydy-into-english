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

struct ChatGPTSignInLabel: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("ChatGPTMark").resizable().scaledToFit().frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text("ChatGPT 계정으로 시작하기").font(.system(size: 14, weight: .semibold))
        }.frame(maxWidth: .infinity)
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            EnglishTheme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image("BrandMark").resizable().scaledToFit().frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                HStack(spacing: 0) {
                    Text("into english").foregroundStyle(EnglishTheme.ink)
                    Text(".").foregroundStyle(EnglishTheme.coral)
                }.font(.system(size: 26, weight: .semibold, design: .serif))
            }.accessibilityElement(children: .ignore).accessibilityLabel("Into English")
        }
    }
}
