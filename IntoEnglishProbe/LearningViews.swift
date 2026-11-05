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

@MainActor
final class Speaker: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
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
                            Text("작은 연습, 더 자연스러운 영어.")
                                .font(.caption2).foregroundStyle(EnglishTheme.muted).frame(maxWidth: .infinity).padding(.top, 10)
                            ForEach(store.messages) { message in
                                messageView(message)
                            }
                        }
                        if store.isSending {
                            HStack(spacing: 10) {
                                companionMark
                                ProgressView().tint(EnglishTheme.coral)
                                Text("뜻은 그대로, 표현을 다듬고 있어요…").font(.caption).foregroundStyle(EnglishTheme.muted)
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
        .sheet(isPresented: $showSettings) { AccountSettings(auth: auth, locked: store.isSending, onSignIn: {
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
                    Label(mode.title, systemImage: mode.symbol).font(.system(size: 13, weight: store.mode == mode ? .semibold : .regular))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(store.mode == mode ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(store.mode == mode ? EnglishTheme.ink : EnglishTheme.muted)
                }.buttonStyle(.plain).accessibilityAddTraits(store.mode == mode ? .isSelected : [])
            }
        }.padding(4).background(EnglishTheme.line.opacity(0.4), in: RoundedRectangle(cornerRadius: 13))
            .padding(.horizontal, 23).padding(.bottom, 8).disabled(busy)
    }
    private var welcome: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(EnglishTheme.peach).frame(width: 77, height: 64).rotationEffect(.degrees(-9))
                Image(systemName: "quote.bubble.fill").font(.system(size: 40)).foregroundStyle(EnglishTheme.coral.opacity(0.7)).rotationEffect(.degrees(-9))
                Image(systemName: "sparkle").font(.system(size: 17)).foregroundStyle(EnglishTheme.coral).offset(x: 49, y: -29)
                Image(systemName: "sparkle").font(.system(size: 13)).foregroundStyle(EnglishTheme.muted).offset(x: -46, y: 24)
            }.frame(height: 100).padding(.top, 6)
            Text("A LITTLE PRACTICE, EVERY DAY").font(.system(size: 8, weight: .semibold)).tracking(2.2).foregroundStyle(EnglishTheme.muted).padding(.top, 9)
            VStack(spacing: 3) {
                Text(store.mode == .sentence ? "하고 싶은 말," : "궁금한 표현,")
                Text(store.mode == .sentence ? "나답게 영어로." : "한마디면 충분해요.").foregroundStyle(EnglishTheme.coral)
            }.font(.system(size: 28, weight: .medium)).tracking(-1.1).padding(.top, 18)
            Text(store.mode == .sentence ? "영어가 떠오르지 않으면 한국어로만 적어도 좋아요.\n내 뜻은 그대로, 표현은 더 자연스럽게." : "영어도 한국어도, 떠오르는 그대로 적어보세요.\n단어의 뜻부터 쓰임새까지 함께 알아가요.")
                .font(.system(size: 11)).foregroundStyle(EnglishTheme.muted).lineSpacing(6).multilineTextAlignment(.center).padding(.top, 15)
            VStack(spacing: 9) {
                if store.mode == .sentence {
                    example("한국어만 적어도 괜찮아요", text: "좀 쉬고 싶어", symbol: "cup.and.saucer", korean: "")
                    example("업무 메일도 자신 있게", text: "Please check this file.", symbol: "briefcase", korean: "이 파일을 확인해 줄래요?")
                    example("의미가 애매하면 함께 확인해요", text: "I’m down.", symbol: "sparkles", korean: "")
                } else {
                    example("뜻과 예문을 함께", text: "serendipity", symbol: "sparkles", korean: "")
                    example("원어민이 쓰는 숙어", text: "on the same page", symbol: "text.bubble", korean: "")
                    example("한국어로 시작해도 돼요", text: "눈치", symbol: "arrow.left.arrow.right", korean: "")
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
                HStack(spacing: 8) { companionMark; Text("Into English").font(.caption.weight(.semibold)); Text("YOUR ENGLISH COMPANION").font(.system(size: 7)).tracking(1).foregroundStyle(EnglishTheme.muted) }
                ReplyCard(reply: reply, mood: message.mood, saved: store.isSaved(reply), onSave: { store.toggleSave(message) }, onCopy: { copy(reply.text) }, onSpeak: { speak(reply) }, onChoice: { choice in
                    draft.wrappedValue = choice; koreanDraft = ""; submit()
                }).disabled(store.isSending)
            }
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 11) {
            if store.mode == .sentence && signedIn {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        Text("어떤 느낌으로?").font(.system(size: 10)).foregroundStyle(EnglishTheme.muted).padding(.trailing, 3)
                        ForEach(WritingMood.allCases) { mood in
                            Button { store.mood = mood } label: {
                                Label(mood.title, systemImage: mood.symbol).font(.system(size: 10))
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(store.mood == mood ? EnglishTheme.peach : Color.clear, in: Capsule())
                                    .foregroundStyle(store.mood == mood ? EnglishTheme.coral : EnglishTheme.muted)
                            }.buttonStyle(.plain).accessibilityAddTraits(store.mood == mood ? .isSelected : [])
                        }
                    }
                }.disabled(busy)
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
                Text(signedIn ? "Using ChatGPT plan" : "ChatGPT 계정 연결 필요").font(.system(size: 8))
                if signedIn { Text("·"); Text(auth.models.first(where: { $0.slug == auth.selectedModel })?.display_name ?? "모델 확인 중").lineLimit(1) }
                Spacer()
                Button("사용량 관리 ↗") { UIApplication.shared.open(URL(string: "https://chatgpt.com/settings/usage")!) }.font(.system(size: 8))
            }.font(.system(size: 8)).foregroundStyle(EnglishTheme.muted)
        }.padding(.horizontal, 20).padding(.top, 13).padding(.bottom, 9).background(EnglishTheme.background)
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
        speaker.speak(hasKorean ? reply.example?.english ?? reply.text : reply.text)
    }
    private var savedSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("YOUR LITTLE COLLECTION").font(.system(size: 8, weight: .semibold)).tracking(2).foregroundStyle(EnglishTheme.muted)
                    Text("다시 꺼내 보고 싶은 표현").font(.title2.weight(.medium)).tracking(-0.9)
                    if store.archive.saved.isEmpty {
                        ContentUnavailableView("아직 저장한 표현이 없어요", systemImage: "bookmark", description: Text("답변의 책갈피를 눌러 나만의 표현집을 만들어 보세요."))
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
                    if store.chats.isEmpty { Text("오늘의 첫 영어를 시작해 보세요.").font(.footnote).foregroundStyle(EnglishTheme.muted) }
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
                .navigationTitle("나의 영어 공간").navigationBarTitleDisplayMode(.inline)
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
                        Label(account.email, systemImage: "person.crop.circle")
                        Label(account.permitsInference ? "내 ChatGPT 요금제로 사용 중" : "요금제 사용 권한이 없어요", systemImage: account.permitsInference ? "checkmark.seal" : "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(EnglishTheme.muted)
                    } else { Text("아직 연결된 계정이 없어요.").foregroundStyle(EnglishTheme.muted) }
                    if auth.credentials == nil || auth.credentials?.permitsInference == false {
                        Button("Continue with ChatGPT", action: onSignIn).disabled(auth.busy || locked)
                    }
                    Link("ChatGPT 사용량 관리 ↗", destination: URL(string: "https://chatgpt.com/settings/usage")!)
                }
                if auth.credentials?.permitsInference == true {
                    Section("AI 모델") {
                        if !auth.models.isEmpty {
                            Picker("사용할 모델", selection: $auth.selectedModel) {
                                ForEach(auth.models) { Text($0.display_name).tag($0.slug) }
                            }.disabled(auth.busy || locked)
                            .onChange(of: auth.selectedModel) { _, selected in
                                if let subject = auth.credentials?.subject { UserDefaults.standard.set(selected, forKey: "model.\(subject)") }
                            }
                        }
                        Button("사용 가능한 모델 새로고침") { Task { await auth.loadModels() } }.disabled(auth.busy || locked)
                        Text("연결된 계정에서 사용 가능한 모델만 표시해요. 요청은 해당 계정의 ChatGPT 사용 한도에 포함됩니다.")
                            .font(.caption).foregroundStyle(EnglishTheme.muted)
                    }
                }
                if let error = auth.error { Section { Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled) } }
                Section("Into English") {
                    HStack { Text("버전"); Spacer(); Text(version).foregroundStyle(EnglishTheme.muted) }
                    Text("대화와 저장한 표현은 이 기기에 보관돼요. AI 요청 시에는 현재 대화에 필요한 내용만 OpenAI로 전송합니다.").font(.caption).foregroundStyle(EnglishTheme.muted)
                    Text("한국어만 → 영어 표현\n영어만 → 문장 교정\n둘 다 → 한국어 의도를 반영").font(.footnote).lineSpacing(6)
                }
                if auth.credentials != nil {
                    Section {
                        Button("이 기기에서 계정 연결 해제", role: .destructive) { confirmDisconnect = true }.disabled(auth.busy || locked)
                        Text("대화 기록은 기기에 남으며 같은 계정으로 다시 연결하면 볼 수 있어요. 원격 권한 철회는 ChatGPT 설정에서 할 수 있습니다.").font(.caption).foregroundStyle(EnglishTheme.muted)
                    }
                }
            }.scrollContentBackground(.hidden).background(EnglishTheme.background).navigationTitle("설정").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
                .confirmationDialog("이 기기의 계정 연결을 해제할까요?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                    Button("연결 해제", role: .destructive) { auth.disconnect() }
                }
        }.tint(EnglishTheme.coral)
    }
}
