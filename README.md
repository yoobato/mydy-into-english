# Into English

한국어 사용자를 위한 개인용 영어 학습 iOS 앱. 아이보리·코랄 톤의 채팅 화면에서 단어·숙어를 알아보고, 하고 싶은 말을 자연스러운 영어로 다듬습니다.

## 기능

- **단어 / 숙어:** 영어 ↔ 한국어 자동 감지, 뜻·뉘앙스·발음·품사·예문·대체 표현
- **문장 다듬기:** 한국어만 입력하면 영어 표현, 영어만 입력하면 교정, 둘 다 입력하면 한국어 의도를 반영
- **무드:** 캐주얼 / 공손하게 / 격식있게. 입력창의 느낌 버튼을 눌러 선택 영역 펼치기
- **의도 확인:** 모호한 문장은 먼저 질문하고 선택 또는 자유 입력으로 답한 뒤 교정
- 복사, 기기 영어 TTS, 표현 저장·해제, 계정별 최근 대화와 새 대화
- 앱 실행 시 새 대화로 시작, 이전 대화는 기록에서 다시 열기
- 실행·탭 전환·새 대화 때 직전과 겹치지 않는 단어·숙어·문장 예시 (추가 AI 호출 없음)
- 미국·영국·캐나다·호주·지역 중립 영어 설정을 번역·교정·예문과 TTS에 반영. 철자·표현 외에 현지에서 자연스러운 공손함·직접성·완곡함 등 어투 적용
- 모델 GPT-6.1 Sol, 추론 강도 Light(low) 고정. 계정이 모델을 제공하지 않으면 안내 후 중단
- 설정에서 현재 지침·다음 요청 미리보기·실제로 최근 전송한 요청 본문 확인

## AI 연결과 데이터

개발자 공용 API 키와 별도 백엔드를 사용하지 않습니다. 각 사용자가 자기 ChatGPT 계정으로 로그인하고 요금제 사용 권한을 승인합니다. 해당 계정의 모델 목록으로 GPT-6.1 Sol 이용 권한을 확인합니다. 앱 요청과 프롬프트 미리보기는 GPT-6.1 Sol·Light로 고정하며 이전 모델·추론 강도 선택값은 사용하지 않습니다.

- OAuth PKCE S256, state, nonce, OpenAI OIDC/JWKS 서명·클레임 검증
- 기기 내부 127.0.0.1 콜백. Safari 로그인 창을 닫거나 5분이 지나면 대기 종료
- 인증정보와 기기 host ID는 `WhenUnlockedThisDeviceOnly` Keychain에 저장
- 인증 URL·코드·토큰은 로그·Git·브라우저 저장소에 보관하지 않음
- `/v1/responses`에 `store:false`, `stream:true`. SSE를 바이트 단위로 읽어 이벤트 구분과 UTF-8 경계를 보존
- 실제 완료 이벤트와 유효한 답변을 확인한 뒤 표시. 오류 시 다른 결제 경로로 전환하거나 자동 재전송하지 않음
- AI 지침과 사용자 입력을 별도 메시지로 전달. HTML을 실행하지 않고 타입이 있는 답변으로 렌더링
- 대화·저장한 표현·최근 요청 본문은 계정별 기기 파일에 보호하여 저장. 필요한 최근 대화만 OpenAI로 전송
- 로컬 계정 연결 해제 후에는 해당 계정 기록을 표시하지 않으며, 같은 계정으로 재연결하면 기록 복원

사용량 화면과 로컬 집계 기능을 제거했습니다. 이전 파일을 읽을 때 사용량 항목은 버리고 대화·저장한 표현·최근 요청은 유지합니다. 계정 연결 해제는 iOS Alert로 확인하며, 계정 왼쪽에는 ChatGPT 공식 웹 자산의 아이콘을 표시합니다.

앱 자체는 초기 버전입니다. 개인용 iPhone에서 로그인·모델 조회·실제 AI 응답을 확인했으나 모든 계정·요금제 및 일반 App Store 배포의 지원을 보장하지 않습니다. 아내의 기기·계정은 별도로 검증해야 합니다.

## 개발 및 실행

Xcode 27.2, iOS 17 이상, XcodeGen을 사용합니다. 외부 패키지 의존성이 없습니다.

```sh
xcodegen generate
open IntoEnglishProbe.xcodeproj
```

`IntoEnglishProbe` scheme과 실행할 iPhone을 선택해 실행합니다. 내부 target 이름은 초기 검증 프로젝트에서 이어졌지만 표시 이름은 Into English입니다. 기존 설치 사용자의 로그인을 유지하기 위해 bundle identifier와 Keychain service는 유지합니다. 개발 팀은 자신의 팀으로 설정합니다.

## 버전 및 빌드 번호

- 앱 버전: **1.0.0**
- `BuildNumber.txt`: 마지막으로 사용한 빌드 번호. 처음 0에서 시작해 첫 빌드가 1
- 앱 target의 pre-build 단계에서 파일 잠금을 잡아 번호를 정확히 1 증가
- post-build 단계에서 빌드된 앱의 Info.plist에 버전과 해당 빌드 번호를 기록한 뒤 서명
- 시뮬레이터·테스트·실기기 빌드 및 실패한 빌드 시도도 번호를 소비. 번호를 되돌리지 않음
- `project.yml` 변경 후 `xcodegen generate`. 빌드 후 변경된 `BuildNumber.txt`도 함께 커밋

## 검증

```sh
xcodebuild -project IntoEnglishProbe.xcodeproj -scheme IntoEnglishProbe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build test
```

테스트는 실제 사용자 계정·요금제를 소비하지 않습니다. 인증 보안, Keychain, loopback, 실제 URLSession을 통한 SSE 처리, 부분·실패 응답 거부, 한국어 답변 형식, 의도 확인 맥락, 사용자 입력 역할 분리, 비로그인 전송 차단, 새 실행의 대화 초기화와 기록 보존, 이전 파일 호환성, 지역별 프롬프트와 추론 요청 본문, 화면 탭·설정·한 줄 톤 선택을 검증합니다. UI 테스트는 저장된 계정을 읽지 않는 전용 실행 인자로 동작합니다.

AI 모델의 실제 번역·교정 품질은 실기기에서 추가로 확인합니다. 추천 예제를 누르면 로그인된 계정으로 실제 요청을 보내며, 고정된 데모 답변을 사용하지 않습니다.

## 저장소 정책

완료된 개발 변경은 검증 후 이 저장소에 커밋·푸시합니다. 토큰, 사용자 기록, 프로비저닝 프로파일, 인증서, 빌드 결과는 커밋하지 않습니다. 자세한 지속 지침은 [AGENTS.md](AGENTS.md)에 있습니다.

## 공식 연동 문서

- [로그인](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [모델과 AI 요청](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [계정·토큰 갱신](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
- [현재 제약](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)

## 저장소 이름과 플랫폼 결정

저장소는 [`yoobato/mydy-into-english`](https://github.com/yoobato/mydy-into-english)로 이름을 변경했습니다. 앞으로 완료된 변경은 이 주소로 커밋·푸시합니다.

2026-11-05 PWA 전환 검토 결과, 서버에서 사용자별 ChatGPT 로그인을 받아 구독 사용량으로 처리하는 일반 웹서비스는 OpenAI의 별도 접근 승인 경로가 필요합니다. 사용자의 조건부 지시에 따라 현재 동작이 검증된 iOS 앱을 유지합니다. 기존 앱·로그인·빌드 번호는 변경하지 않았습니다.

## 소개 페이지 및 아이콘 시안

- `docs/`: GitHub Pages 정적 소개 페이지 (개인 테스트 상태를 명시; 실제 AI 요청 없는 인터랙티브 예시)
- GitHub Pages 소스: `main` 브랜치 `/docs`, 도메인 `into-english.mydy.kr`
- DNS: `CNAME into-english → yoobato.github.io`, TTL 기본값. 기존 동일 이름 A/AAAA 레코드가 있다면 충돌 여부 확인
- DNS 반영 뒤 GitHub Pages의 HTTPS 인증서 발급 및 HTTPS 강제 상태 확인
- 로컬 확인: `python3 -m http.server 8765 --directory docs`
- `design/icon-studies-v1.png`: A/B/C 아이콘 검토용 시안. B안을 확정하고 `design/app-icon-b.png` 원본을 앱과 웹 아이콘에 적용
- 저장소는 Public이며, 오픈소스 라이선스 선택은 별도 결정 필요. Public 상태만으로 수정·재배포 권한을 부여하지 않음

- SNS 메타데이터: Open Graph·Twitter large-image, 설명·절대 이미지 URL·1200×630 PNG·alt 텍스트
- 자산 재생성: `swift Scripts/generate-icon.swift` (확정 B 원본으로 앱 아이콘·웹 아이콘·SNS 카드 렌더링)
- ChatGPT 계정 아이콘 출처: https://chatgpt.com/cdn/assets/favicon-180x180.9e0103ce69.png (OpenAI 소유, 계정 연결 표시 용도)
