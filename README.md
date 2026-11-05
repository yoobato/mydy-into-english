# Into English

한국어 사용자를 위한 영어 번역·문장 교정 iOS 앱. [소개 페이지](https://into-english.mydy.kr/) · [GitHub](https://github.com/yoobato/mydy-into-english)

## 기능

- 단어·숙어 영한/한영 번역, 뜻·예문·사용 맥락
- 한국어 문장의 영어 표현, 영어 문법 교정, 한국어 의도 반영 및 모호한 의미 재질문
- 캐주얼·공손하게·격식있게 느낌과 미국·영국·캐나다·호주·지역 중립 영어
- 계정에서 제공하는 AI 모델과 지원하는 추론 강도 선택
- 표현 복사·저장·듣기, 대화 기록, 실행 시 새 대화, 바뀌는 입력 예시
- 설정에서 실제 전송 프롬프트 확인

각자의 ChatGPT 계정과 이용 권한으로 AI를 요청합니다. 공용 API 키나 중계 서버를 사용하지 않습니다. 인증정보는 Keychain, 대화·저장한 표현·최근 요청은 기기에 보관합니다. 필요한 입력과 대화 맥락만 OpenAI로 전송합니다.

## 개발

Xcode 27.2, iOS 17 이상, XcodeGen. 외부 패키지 의존성은 없습니다.

```sh
xcodegen generate
open IntoEnglishProbe.xcodeproj
```

Scheme은 `IntoEnglishProbe`입니다. 기존 로그인을 유지하도록 bundle identifier와 Keychain service는 변경하지 않습니다. `project.yml`이 프로젝트 설정의 원본입니다.

```sh
xcodebuild -project IntoEnglishProbe.xcodeproj -scheme IntoEnglishProbe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build test
```

테스트는 합성 데이터만 사용하며 실제 계정의 AI 한도를 소비하지 않습니다. 인증 검증, 스트림 처리, 기록 호환성, 프롬프트와 화면 동작을 확인합니다.

버전은 `1.0.0`이며 앱 빌드마다 `BuildNumber.txt`를 1 증가시킵니다. 완료된 변경은 검증 후 커밋·푸시합니다. 빌드 결과·인증정보·사용자 기록은 커밋하지 않습니다. 세부 규칙은 [AGENTS.md](AGENTS.md)에 있습니다.

## 파일 구성

- `IntoEnglishProbe/`: 앱 소스와 에셋
- `IntoEnglishProbeTests/`, `IntoEnglishUITests/`: 테스트
- `Scripts/`: 버전 관리와 이미지 내보내기
- `design/app-icon-b.png`: 확정 앱 아이콘 원본
- `docs/`: GitHub Pages 소개 페이지와 SNS 공유 이미지

이미지 내보내기: `swift Scripts/generate-icon.swift`
소개 페이지 로컬 확인: `python3 -m http.server 8765 --directory docs`
GitHub Pages: `main` 브랜치 `/docs`, `into-english.mydy.kr`, HTTPS 사용

## 배포 상태

현재 개인 기기에서 테스트 중입니다. App Store·TestFlight 공개 배포 전 지원 계정 안내, 심사용 접근 방법, AI 전송 동의 및 개인정보처리방침을 준비해야 합니다. 저장소의 오픈소스 라이선스도 선택해야 합니다.

## 연동 문서와 자산

- [ChatGPT 로그인·모델·AI 요청](https://developers.openai.com/siwc/token-sharing-open-source)
- [Apple 심사 지침](https://developer.apple.com/app-store/review/guidelines/)
- [ChatGPT 계정 아이콘 출처](https://chatgpt.com/cdn/assets/favicon-180x180.9e0103ce69.png): OpenAI 소유, 계정 연결 표시용
