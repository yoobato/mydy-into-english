import SwiftUI
import AVFoundation
import UIKit

enum EnglishTheme {
    static let background = Color(red: 0.98, green: 0.97, blue: 0.95)
    static let ink = Color(red: 0.22, green: 0.27, blue: 0.23)
    static let muted = Color(red: 0.56, green: 0.59, blue: 0.52)
    static let coral = Color(red: 0.81, green: 0.45, blue: 0.35)
    static let peach = Color(red: 0.97, green: 0.91, blue: 0.87)
    static let sage = Color(red: 0.91, green: 0.93, blue: 0.87)
    static let line = Color(red: 0.88, green: 0.89, blue: 0.84)
}

/// Keep tab text fully visible while pressed; only the background gives feedback.
private struct ModeTabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? EnglishTheme.line.opacity(0.45) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 9))
    }
}

@MainActor
final class Speaker: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    func speak(_ text: String, region: EnglishRegion) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: region.voice)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.86
        synthesizer.speak(utterance)
    }
}

struct IntoEnglishView: View {
    @StateObject private var auth = ProbeModel()
    @StateObject private var store = StudyStore()
    @StateObject private var speaker = Speaker()
    @State private var showSettings = false
    @State private var showSaved = false
    @State private var showHistory = false
    @State private var showKorean = false
    @State private var showMood = false
    @State private var drafts: [LearningMode: String] = [:]
    @State private var koreanDraft = ""
    @State private var toast: String?
    @FocusState private var composerFocused: Bool
    private var draft: Binding<String> { Binding(get: { drafts[store.mode] ?? "" }, set: { drafts[store.mode] = $0 }) }
    private var signedIn: Bool { auth.credentials?.permitsInference == true }
    private var busy: Bool { store.isSending || auth.busy }
    private var canSend: Bool { signedIn && !busy && (!(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty || (store.mode == .sentence && !koreanDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            modeTabs
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        if store.messages.isEmpty { welcome }
                        else {
                            ForEach(store.messages) { message in
                                messageView(message)
                            }
                        }
                        if store.isSending {
                            HStack(spacing: 10) {
                                companionMark
                                ProgressView().tint(EnglishTheme.coral)
                                Text("응답을 기다리는 중…").font(.caption).foregroundStyle(EnglishTheme.muted)
                            }.padding(.vertical, 8)
                        }
                        if let error = store.error ?? auth.error {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                                if store.messages.last?.isUser == true && !busy {
                                    Button("다시 시도") { Task { await store.send(text: "", korean: "", auth: auth, retry: true) } }
                                        .font(.footnote.weight(.semibold)).tint(EnglishTheme.coral)
                                }
                            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.horizontal, 23).padding(.top, 15).padding(.bottom, 14)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: store.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: store.isSending) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: composerFocused) { _, focused in if focused { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } } }
            }
        }
        .background(EnglishTheme.background.ignoresSafeArea())
        .foregroundStyle(EnglishTheme.ink)
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .overlay(alignment: .top) {
            if let toast { Text(toast).font(.footnote).padding(.horizontal, 18).padding(.vertical, 11)
                .background(EnglishTheme.ink, in: Capsule()).foregroundStyle(.white).padding(.top, 65)
                .transition(.move(edge: .top).combined(with: .opacity)).allowsHitTesting(false) }
        }
        .sheet(isPresented: $showSettings) { AccountSettings(auth: auth, store: store, draft: draft.wrappedValue, korean: koreanDraft, locked: store.isSending, onSignIn: {
            showSettings = false
            Task { try? await Task.sleep(for: .milliseconds(400)); await auth.signIn() }
        }) }
        .sheet(isPresented: $showSaved) { savedSheet }
        .sheet(isPresented: $showHistory) { historySheet }
        .sheet(item: $auth.browser, onDismiss: { auth.browserDismissed() }) { destination in
            LoginBrowser(url: destination.url, onDone: { auth.browserDismissed() }).ignoresSafeArea()
        }
        .task(id: auth.credentials?.subject) {
            store.switchAccount(auth.credentials?.subject)
            if signedIn && auth.models.isEmpty { await auth.loadModels() }
        }
        .tint(EnglishTheme.coral)
    }
    private var header: some View {
        HStack(spacing: 12) {
            Button { composerFocused = false; showHistory = true } label: { Image(systemName: "line.3.horizontal").font(.system(size: 18)) }
                .accessibilityLabel("최근 대화").disabled(busy)
            Spacer()
            HStack(spacing: 0) {
                Text("into english").font(.system(size: 22, weight: .semibold, design: .serif)).tracking(-0.8)
                Text(".").font(.title2.weight(.bold)).foregroundStyle(EnglishTheme.coral)
            }.accessibilityLabel("Into English")
            Spacer()
            Button { composerFocused = false; showSaved = true } label: { Image(systemName: "bookmark").font(.system(size: 17)) }.accessibilityLabel("저장한 표현")
            Button { composerFocused = false; showSettings = true } label: { Image(systemName: "person.crop.circle").font(.system(size: 20)) }
                .accessibilityLabel("계정과 모델 설정").disabled(busy)
        }.padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 20)
    }
    private var modeTabs: some View {
        HStack(spacing: 4) {
            ForEach(LearningMode.allCases) { mode in
                Button {
                    store.mode = mode; store.error = nil; showKorean = false; composerFocused = false
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: mode.symbol)
                        Text(mode.title)
                    }
                        .font(.system(size: 13, weight: .semibold))
                        .contentTransition(.identity)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(store.mode == mode ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(store.mode == mode ? EnglishTheme.ink : EnglishTheme.muted)
                }.buttonStyle(ModeTabButtonStyle())
                    .accessibilityIdentifier("mode-\(mode.rawValue)")
                    .accessibilityAddTraits(store.mode == mode ? .isSelected : [])
            }
        }.padding(4).background(EnglishTheme.line.opacity(0.4), in: RoundedRectangle(cornerRadius: 13))
            .padding(.horizontal, 23).padding(.bottom, 8).disabled(busy)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
    private var welcome: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(EnglishTheme.peach).frame(width: 77, height: 64).rotationEffect(.degrees(-9))
                Image(systemName: "quote.bubble.fill").font(.system(size: 40)).foregroundStyle(EnglishTheme.coral.opacity(0.7)).rotationEffect(.degrees(-9))
                Image(systemName: "sparkle").font(.system(size: 17)).foregroundStyle(EnglishTheme.coral).offset(x: 49, y: -29)
                Image(systemName: "sparkle").font(.system(size: 13)).foregroundStyle(EnglishTheme.muted).offset(x: -46, y: 24)
            }.frame(height: 100).padding(.top, 6)
            Text(store.mode.title).font(.system(size: 27, weight: .medium)).tracking(-1).padding(.top, 18)
            Text(store.mode == .sentence ? "한국어 또는 영어 문장을 입력하세요.\n한국어 뜻을 함께 적으면 의도를 반영해 다듬습니다." : "영어 또는 한국어 단어·숙어를 입력하세요.\n번역과 예문을 확인할 수 있습니다.")
                .font(.system(size: 12)).foregroundStyle(EnglishTheme.muted).lineSpacing(5).multilineTextAlignment(.center).padding(.top, 13)
            VStack(spacing: 9) {
                ForEach(Array((store.examples[store.mode] ?? []).enumerated()), id: \.element.id) { index, item in
                    example(item.label, text: item.text, symbol: item.symbol, korean: item.korean)
                        .accessibilityIdentifier("example-\(index)")
                }
            }.padding(.top, 26)

        }.frame(maxWidth: .infinity)
    }
    private func example(_ label: String, text: String, symbol: String, korean: String) -> some View {
        Button {
            draft.wrappedValue = text; koreanDraft = korean; showKorean = !korean.isEmpty
            if signedIn { submit() } else { composerFocused = true }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(EnglishTheme.coral).frame(width: 23)
                VStack(alignment: .leading, spacing: 5) {
                    Text(label).font(.system(size: 9)).foregroundStyle(EnglishTheme.muted)
                    Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(EnglishTheme.ink)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(EnglishTheme.muted)
            }.padding(.horizontal, 15).padding(.vertical, 13).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(EnglishTheme.line, lineWidth: 0.7))
        }.buttonStyle(.plain).disabled(busy)
    }
    private var companionMark: some View {
        Text("i").font(.system(size: 19, weight: .semibold, design: .serif)).italic().foregroundStyle(.white)
            .frame(width: 27, height: 27).background(EnglishTheme.coral, in: RoundedRectangle(cornerRadius: 9))
    }
    @ViewBuilder private func messageView(_ message: StudyMessage) -> some View {
        if message.isUser {
            HStack {
                Spacer(minLength: 35)
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.text).font(.system(size: 14)).textSelection(.enabled)
                    if !message.korean.isEmpty {
                        Divider(); Text(message.korean).font(.system(size: 11)).foregroundStyle(EnglishTheme.muted)
                    }
                }.padding(15).background(EnglishTheme.sage.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
            }
        } else if let reply = message.reply {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) { companionMark; Text("Into English").font(.caption.weight(.semibold)) }
                ReplyCard(reply: reply, mood: message.mood, saved: store.isSaved(reply), onSave: { store.toggleSave(message) }, onCopy: { copy(reply.text) }, onSpeak: { speak(reply) }, onChoice: { choice in
                    draft.wrappedValue = choice; koreanDraft = ""; submit()
                }).disabled(store.isSending)
            }
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 11) {
            if store.mode == .sentence && showMood {
                VStack(alignment: .leading, spacing: 9) {
                    Text("어떤 느낌으로?").font(.system(size: 11, weight: .semibold)).foregroundStyle(EnglishTheme.ink)
                    HStack(spacing: 5) {
                        ForEach(WritingMood.allCases) { mood in
                            Button { store.mood = mood; withAnimation { showMood = false } } label: {
                                Text(mood.title).font(.system(size: 12, weight: store.mood == mood ? .semibold : .regular))
                                    .lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(store.mood == mood ? EnglishTheme.coral : Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 9))
                                    .foregroundStyle(store.mood == mood ? Color.white : EnglishTheme.ink)
                            }.buttonStyle(.plain).accessibilityIdentifier("mood-\(mood.rawValue)")
                                .accessibilityAddTraits(store.mood == mood ? .isSelected : [])
                        }
                    }
                }.padding(12).background(EnglishTheme.sage.opacity(0.65), in: RoundedRectangle(cornerRadius: 14)).disabled(busy)
            }
            VStack(alignment: .leading, spacing: 10) {
                TextField(store.waitingForMeaning ? "어떤 뜻인지 조금 더 알려주세요…" : store.mode == .word ? "궁금한 영어 · 한국어 단어나 숙어…" : "한국어로 하고 싶은 말, 또는 영어 문장…", text: draft, axis: .vertical)
                    .font(.system(size: 13)).lineLimit(2...5).focused($composerFocused)
                    .accessibilityIdentifier("learning-input").accessibilityLabel("영어 또는 한국어 입력")
                if showKorean && store.mode == .sentence {
                    Divider()
                    HStack(spacing: 8) {
                        Text("KR").font(.system(size: 8, weight: .medium)).padding(4).background(EnglishTheme.sage, in: RoundedRectangle(cornerRadius: 4))
                        TextField("전하고 싶은 한국어 뜻 (선택)", text: $koreanDraft, axis: .vertical).font(.system(size: 11)).lineLimit(1...3)
                    }
                }
                HStack(spacing: 10) {
                    if store.mode == .sentence {
                        Button { withAnimation { showMood.toggle() } } label: {
                            Label(store.mood.title, systemImage: "slider.horizontal.3").font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 9).padding(.vertical, 7)
                                .background(EnglishTheme.peach, in: Capsule())
                        }.buttonStyle(.plain).foregroundStyle(EnglishTheme.coral).accessibilityIdentifier("tone-toggle")
                            .accessibilityLabel("느낌 선택: \(store.mood.title)")
                        Button { withAnimation { showKorean.toggle() } } label: {
                            Label(showKorean ? "한국어 뜻 접기" : "한국어 뜻 추가", systemImage: showKorean ? "minus.circle" : "plus.circle").font(.system(size: 9))
                        }.buttonStyle(.plain).foregroundStyle(EnglishTheme.muted)
                    } else { Label("언어 자동 감지", systemImage: "globe").font(.system(size: 9)).foregroundStyle(EnglishTheme.muted) }
                    Spacer()
                    Button(action: submit) {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 35, height: 35).background(canSend ? EnglishTheme.coral : EnglishTheme.coral.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).disabled(!canSend).accessibilityLabel("보내기").accessibilityIdentifier("learning-send")
                }
            }.padding(15).background(.white, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(composerFocused ? EnglishTheme.coral.opacity(0.6) : EnglishTheme.line, lineWidth: 0.8))
            if !signedIn {
                Button { composerFocused = false; Task { await auth.signIn() } } label: {
                    HStack { Image(systemName: "person.crop.circle"); Text("Continue with ChatGPT"); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.system(size: 12, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 13)
                        .frame(maxWidth: .infinity).background(EnglishTheme.ink, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                }.buttonStyle(.plain).disabled(busy)
            }
            HStack(spacing: 4) {
                Circle().fill(signedIn ? Color(red: 0.55, green: 0.65, blue: 0.43) : EnglishTheme.muted).frame(width: 4, height: 4)
                Text(signedIn ? "ChatGPT 연결됨" : "ChatGPT 계정 연결 필요").font(.system(size: 8))
                if signedIn { Text("·"); Text(auth.models.first(where: { $0.slug == auth.selectedModel })?.display_name ?? "모델 확인 중").lineLimit(1) }
                Spacer()
            }.font(.system(size: 8)).foregroundStyle(EnglishTheme.muted)
        }.padding(.horizontal, 20).padding(.top, 13).padding(.bottom, 9).background(EnglishTheme.background.shadow(color: .black.opacity(0.04), radius: 8, y: -4))
            .overlay(alignment: .top) { Rectangle().fill(EnglishTheme.line).frame(height: 1) }
    }
    private func submit() {
        guard canSend else { if !signedIn { showSettings = true }; return }
        let text = draft.wrappedValue, korean = koreanDraft
        guard text.count <= 2000, korean.count <= 2000 else { store.error = "2,000자 이내로 적어 주세요."; return }
        draft.wrappedValue = ""; koreanDraft = ""; composerFocused = false
        Task { await store.send(text: text, korean: korean, auth: auth) }
    }
    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        withAnimation { toast = "표현을 복사했어요" }
        Task { try? await Task.sleep(for: .seconds(2)); withAnimation { toast = nil } }
    }
    private func speak(_ reply: LearningReply) {
        let hasKorean = reply.text.range(of: "[가-힣]", options: .regularExpression) != nil
        speaker.speak(hasKorean ? reply.example?.english ?? reply.text : reply.text, region: store.region)
    }
    private var savedSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("저장한 표현").font(.title2.weight(.medium)).tracking(-0.9)
                    if store.archive.saved.isEmpty {
                        ContentUnavailableView("아직 저장한 표현이 없어요", systemImage: "bookmark", description: Text("답변의 책갈피 버튼으로 저장할 수 있습니다."))
                    }
                    ForEach(store.archive.saved) { item in
                        ReplyCard(reply: item.reply, mood: item.mood, saved: true, onSave: { store.removeSaved(item.id) }, onCopy: { copy(item.reply.text) }, onSpeak: { speak(item.reply) }, onChoice: { _ in })
                    }
                }.padding(22)
            }.background(EnglishTheme.background).navigationTitle("저장한 표현").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { showSaved = false } } }
        }.tint(EnglishTheme.coral)
    }
    private var historySheet: some View {
        NavigationStack {
            List {
                Button { store.newChat(); showHistory = false } label: { Label("새로운 대화", systemImage: "plus") }.disabled(busy)
                Section("최근 대화") {
                    if store.chats.isEmpty { Text("대화 기록이 없습니다.").font(.footnote).foregroundStyle(EnglishTheme.muted) }
                    ForEach(store.chats) { chat in
                        Button { store.open(chat); showHistory = false } label: {
                            HStack(spacing: 12) {
                                Image(systemName: chat.mode.symbol).foregroundStyle(EnglishTheme.coral)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(chat.title).lineLimit(1).font(.subheadline).foregroundStyle(EnglishTheme.ink)
                                    Text(chat.updatedAt, style: .date).font(.caption2).foregroundStyle(EnglishTheme.muted)
                                }
                            }.padding(.vertical, 5)
                        }.disabled(busy)
                    }
                }
            }.scrollContentBackground(.hidden).background(EnglishTheme.background)
                .navigationTitle("대화 기록").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { showHistory = false } } }
        }.tint(EnglishTheme.coral)
    }
}

struct ReplyCard: View {
    let reply: LearningReply
    let mood: WritingMood
    let saved: Bool
    let onSave: () -> Void
    let onCopy: () -> Void
    let onSpeak: () -> Void
    let onChoice: (String) -> Void
    @State private var showChanges = true
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if reply.kind == .clarification {
                VStack(alignment: .leading, spacing: 13) {
                    Label("어떤 뜻을 전하고 싶었나요?", systemImage: "sparkles").font(.system(size: 10, weight: .medium)).foregroundStyle(EnglishTheme.coral)
                    Text(reply.question).font(.system(size: 15, weight: .medium)).lineSpacing(5).textSelection(.enabled)
                    if !reply.explanation.isEmpty { Text(reply.explanation).font(.footnote).foregroundStyle(EnglishTheme.muted) }
                    ForEach(reply.choices, id: \.self) { choice in
                        Button { onChoice(choice) } label: {
                            HStack { Text(choice).font(.system(size: 12)); Spacer(); Image(systemName: "arrow.up.right").font(.caption2) }
                                .padding(12).background(EnglishTheme.peach.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).foregroundStyle(EnglishTheme.ink)
                    }
                    Text("위에서 고르거나, 아래에 직접 적어도 좋아요.").font(.system(size: 9)).foregroundStyle(EnglishTheme.muted)
                }.padding(19)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label(reply.kind == .word ? "표현 알아보기" : "이렇게 말해보세요", systemImage: "sparkle")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(EnglishTheme.muted)
                    Text(reply.text).font(.system(size: 23, weight: .medium)).tracking(-0.5).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if !reply.meaning.isEmpty { Text(reply.meaning).font(.system(size: 12)).foregroundStyle(EnglishTheme.muted).lineSpacing(4).textSelection(.enabled) }
                    if !reply.pronunciation.isEmpty || !reply.partOfSpeech.isEmpty {
                        Text([reply.partOfSpeech, reply.pronunciation].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(EnglishTheme.muted)
                    }
                }.padding(19)
                if !reply.explanation.isEmpty || reply.example != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        if !reply.explanation.isEmpty { Text(reply.explanation).font(.system(size: 12)).lineSpacing(5).textSelection(.enabled) }
                        if let example = reply.example {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(example.english).font(.system(size: 13, weight: .medium)).textSelection(.enabled)
                                Text(example.korean).font(.system(size: 11)).foregroundStyle(EnglishTheme.muted)
                            }.padding(.top, 3)
                        }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(EnglishTheme.sage.opacity(0.35))
                }
                if !reply.changes.isEmpty {
                    DisclosureGroup("어디가 달라졌나요?", isExpanded: $showChanges) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(reply.changes.enumerated()), id: \.offset) { item in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.element.before + " → " + item.element.after).font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                                    Text(item.element.reason).font(.system(size: 11)).foregroundStyle(EnglishTheme.muted)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 9)
                    }.font(.system(size: 11, weight: .medium)).padding(17)
                }
                if !reply.alternatives.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("이런 표현도 좋아요").font(.system(size: 9)).foregroundStyle(EnglishTheme.muted)
                        ForEach(Array(reply.alternatives.enumerated()), id: \.offset) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.element.text).font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                                Text(item.element.note).font(.system(size: 10)).foregroundStyle(EnglishTheme.muted)
                            }
                        }
                    }.padding(.horizontal, 18).padding(.vertical, 14)
                }
                Divider().overlay(EnglishTheme.line)
                HStack(spacing: 18) {
                    Button(action: onCopy) { Label("복사", systemImage: "square.on.square") }
                    Button(action: onSpeak) { Label("듣기", systemImage: "speaker.wave.2") }
                    Button(action: onSave) { Image(systemName: saved ? "bookmark.fill" : "bookmark") }
                        .foregroundStyle(saved ? EnglishTheme.coral : EnglishTheme.muted).accessibilityLabel(saved ? "저장 취소" : "표현 저장")
                    Spacer(minLength: 2)
                    Text(reply.kind == .word ? "EN ↔ KR" : mood.title).font(.system(size: 9))
                }.font(.system(size: 10)).foregroundStyle(EnglishTheme.muted).buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 14)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 15))
            .clipShape(RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(EnglishTheme.line, lineWidth: 0.7))
    }
}

struct AccountSettings: View {
    @ObservedObject var auth: ProbeModel
    @ObservedObject var store: StudyStore
    let draft: String
    let korean: String
    let locked: Bool
    let onSignIn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDisconnect = false
    private var version: String { "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))" }
    var body: some View {
        NavigationStack {
            Form {
                Section("나의 ChatGPT 계정") {
                    if let account = auth.credentials {
                        HStack(spacing: 10) {
                            Image("ChatGPTMark").resizable().scaledToFit().frame(width: 24, height: 24)
                                .accessibilityLabel("ChatGPT").accessibilityIdentifier("chatgpt-account-icon")
                            Text(account.email).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Button("연결 해제", role: .destructive) { confirmDisconnect = true }
                                .font(.caption).buttonStyle(.borderless).disabled(auth.busy || locked)
                                .accessibilityIdentifier("account-disconnect")
                        }
                    } else { Text("아직 연결된 계정이 없어요.").foregroundStyle(EnglishTheme.muted) }
                    if auth.credentials == nil || auth.credentials?.permitsInference == false {
                        Button("Continue with ChatGPT", action: onSignIn).disabled(auth.busy || locked)
                    }
                }
                Section("영어 설정") {
                    Picker("영어 지역", selection: $store.region) {
                        ForEach(EnglishRegion.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("english-region").disabled(locked)
                    Text("번역·문장 교정·예문에 선택한 지역의 철자·표현·어투를 적용하고 필요한 문법도 교정합니다.").font(.caption).foregroundStyle(EnglishTheme.muted)
                }
                if auth.credentials?.permitsInference == true {
                    Section("AI") {
                        if !auth.models.isEmpty {
                            Picker("모델", selection: $auth.selectedModel) {
                                ForEach(auth.models) { Text($0.display_name).tag($0.slug) }
                            }.accessibilityIdentifier("ai-model").disabled(auth.busy || locked)
                        }
                        if ReasoningEffort.supports(auth.selectedModel) {
                            Picker("추론 강도", selection: $store.effort) {
                                ForEach(ReasoningEffort.allCases) { Text($0.title).tag($0) }
                            }.accessibilityIdentifier("ai-reasoning").disabled(locked)
                        } else {
                            LabeledContent("추론 강도", value: "모델 기본값")
                            Text("이 모델은 기본 추론 강도로 요청합니다.").font(.caption).foregroundStyle(EnglishTheme.muted)
                        }
                        Button("모델 목록 새로고침") { Task { await auth.loadModels() } }.disabled(auth.busy || locked)
                    }
                }
                if let error = auth.error { Section { Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled) } }
                Section("Into English") {
                    HStack { Text("버전"); Spacer(); Text(version).foregroundStyle(EnglishTheme.muted) }
                    NavigationLink("AI에 보내는 프롬프트") {
                        PromptView(store: store, model: auth.selectedModel, draft: draft, korean: korean)
                    }
                    Text("대화와 저장한 표현은 이 기기에 보관됩니다.").font(.caption).foregroundStyle(EnglishTheme.muted)
                }
            }.scrollContentBackground(.hidden).background(EnglishTheme.background).navigationTitle("설정").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
                .alert("이 기기의 계정 연결을 해제할까요?", isPresented: $confirmDisconnect) {
                    Button("취소", role: .cancel) {}
                    Button("연결 해제", role: .destructive) { auth.disconnect() }
                } message: { Text("기록은 기기에 남습니다. 원격 권한 철회는 ChatGPT 설정에서 할 수 있습니다.") }
        }.tint(EnglishTheme.coral)
    }
}

struct PromptView: View {
    @ObservedObject var store: StudyStore
    let model: String
    let draft: String
    let korean: String
    private var preview: RequestSnapshot {
        let request = store.preview(text: draft, korean: korean)
        return RequestSnapshot(date: Date(), model: model, instructions: request.instructions, input: request.input, reasoning: store.effort.value(for: model))
    }
    var body: some View {
        List {
            Section {
                Text("공통 지침은 instructions에, 입력과 필요한 대화 기록은 input에 담습니다. 사용자 입력 뒤에 별도로 붙이는 문구는 없습니다.")
                    .font(.footnote)
            }
            Section("현재 설정의 공통 지침 · \(store.mode.title)") {
                Text(preview.instructions).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            }
            Section("다음 요청 미리보기 · 현재 입력 포함") {
                Text(preview.formatted).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            }
            if let last = store.archive.lastRequest {
                Section("최근 전송 요청 · \(last.date.formatted(date: .abbreviated, time: .shortened))") {
                    Text(last.formatted).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
            }
        }.scrollContentBackground(.hidden).background(EnglishTheme.background)
            .navigationTitle("전송 프롬프트").navigationBarTitleDisplayMode(.inline)
    }
}
