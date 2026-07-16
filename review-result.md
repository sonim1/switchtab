# SwitchTab 전체 코드 리뷰 (2026-07-02)

macOS 메뉴바 창 전환 앱(현재 앱 내 창 전환, Cmd+`). Swift 6 SPM + Xcode 프로젝트 이중 구성.
전체 소스 약 5,500줄 + 테스트 30개 스위트. `swift run SwitchTabTestRunner` 전부 통과 확인함.

## 총평

구조가 상당히 좋다. 프로토콜 기반 DI가 일관되게 적용되어 있고(Registrar/Provider/Capturer/Persisting 전부 추상화),
정책 로직이 순수 타입(`*Policy`)으로 분리되어 테스트 가능하다. Sparkle을 기본 타깃에서 제외하고
빌드 스크립트로 패치하는 방식도 깔끔하다. 아래는 우선순위별 발견 사항.

---

## 🔴 정확성 버그 (우선 수정 권장)

### 1. 창 식별자가 불안정 → 최근 사용 순서(recency)가 틀어짐
`AccessibilityWindowProvider.swift:93` — `windowIdentifier = pid * 10_000 + (필터링된 배열 인덱스)`.

- `WindowItem.id`("pid-identifier")가 **창의 목록 내 위치**로 결정됨. 창 하나 닫히거나 AX 순서가 바뀌면
  뒤 창들의 id가 전부 밀림.
- `SwitcherRecencyStore`는 이 id를 UserDefaults에 **영구 저장**하므로, 재실행/창 변동 후 recency 정렬이
  엉뚱한 창을 앞으로 올릴 수 있음. pid 재사용 시 다른 앱 창과 충돌도 가능.
- 해결: 안정적 창 ID 사용. 옵션: ① `CGWindowID`(screenCaptureIdentifier)를 primary key로 승격
  ② private API `_AXUIElementGetWindow`(App Store 불가) ③ 최소한 recency key를 "앱 번들ID + 창 제목" 조합으로.

### 2. 최소화된 창을 선택해도 아무 일도 안 일어남
`WindowItem.swift:37` — `canFocus = availability == .available && !isMinimized`.
`WindowFocusService`가 최소화 창에 `.unavailableTarget`을 조용히 반환. 오버레이에는 최소화 창이
표시되는데 선택하면 무반응 → 사용자 입장에선 버그로 보임.
해결: `kAXMinimizedAttribute`를 false로 세팅해 복원 후 focus (일반 앱 전환기 관례).

### 3. 키코드 테이블이 ANSI/QWERTY 하드코딩
`ShortcutSetting.swift:1-230` — keyCode↔문자 매핑이 US 배열 고정. 비-QWERTY(한글 자판은 괜찮지만
AZERTY, Dvorak, 유럽 ISO 배열 등)에서 표시 라벨과 실제 키가 어긋남. `UCKeyTranslate` +
`TISCopyCurrentKeyboardLayoutInputSource`로 동적 변환 권장.

### 4. 통계/최근기록이 정상 종료 시에만 저장됨
`UsageMetricsStore` / `SwitcherRecencyStore` 모두 `flush()`가 `applicationWillTerminate`에서만 호출.
메뉴바 상주 앱은 강제종료·크래시·로그아웃 kill 빈도가 높아 데이터 유실 잦음.
해결: 오버레이 dismiss 시점 또는 debounce(수 초) flush 추가. 비용 거의 없음.

### 5. 썸네일-창 매칭 휴리스틱의 오매칭 가능성
`AccessibilityWindowProvider.swift:313-395` — AX 창과 CGWindow를 **제목 문자열**로 매칭, 실패 시
순서 기반 폴백. 제목 없는 창이 여러 개면 다른 창의 썸네일이 붙을 수 있음(주석으로 인지된 한계).
1번(안정적 CGWindowID 확보)을 해결하면 이 휴리스틱 자체가 사라짐 — 같은 뿌리 문제.

---

## 🟡 보안 / 배포 관련

### 6. Event tap 폴백 = 세션 전체 keyDown 가로채기
`HotkeyService.swift:180-261` — Carbon 등록 실패 시 `CGEvent.tapCreate(.cgSessionEventTap, .defaultTap)`으로
**모든 keyDown**을 능동 필터링. 등록된 핫키만 소비하고 나머지는 통과시키므로 동작은 정상이지만:
- 콜백 userInfo가 `Unmanaged.passUnretained(self)` — registrar가 tap 활성 상태로 해제되면 use-after-free.
  현재는 앱 수명과 같아 실해 없지만 잠재 지뢰. `deinit { unregisterAll() }` 추가 권장.
- 능동 tap은 보안 도구(EDR)에서 키로거 패턴으로 플래그될 수 있음. 핫키 외 이벤트는 즉시 통과하므로
  실질 위험은 없으나, 문서화해 둘 가치 있음.

### 7. App Store 배포 경로가 구조적으로 막혀 있음
entitlements 파일이 비어 있고("App Store-oriented builds") 앱 코어가 AX API(`AXUIElementPerformAction`,
`AXUIElementSetAttributeValue`)로 타 앱 창을 제어함. **샌드박스 필수인 App Store에서는 이 API가 동작 안 함.**
현실적으로 이 앱은 직접 배포(DMG + Sparkle) 전용. App Store 지원을 목표에서 명시적으로 빼거나,
빼지 않을 거면 지금 결정 필요 — 이후 작업 우선순위가 달라짐.

### 8. Sparkle 구성은 양호
EdDSA 공개키 필수 강제, HTTPS 피드, 개인키 저장소 외부 보관 계획 — 모두 올바름.
남은 것: 노터라이즈 + appcast 서명 자동화 (docs/superpowers/plans의 follow-up 문서에 이미 계획됨).

### 9. 디버그 로그 무한 증가
`AppDelegate.swift:367-393` — `~/Library/SwitchTabDebug.log`에 append만 하고 로테이션 없음.
DEBUG 빌드 한정이지만 실행 중인 앱 이름/pid가 기록됨. 크기 상한 또는 `os_log`(unified logging) 전환 권장.
`FileHandle`을 매 호출 열고 닫는 것도 낭비.

그 외 보안 표면: 네트워크는 Sparkle뿐, 저장은 UserDefaults뿐, 입력 검증 이슈 없음. 양호.

---

## 🟢 리팩토링 / 코드 품질

| 위치 | 내용 |
|---|---|
| `HotkeyService.swift:95` | `registeredSetting(for mode:)`가 mode 파라미터를 무시하고 항상 `registeredWindowSetting` 반환. 모드 추가 시 조용히 틀림 |
| `ShortcutSetting.swift` (748줄) | 파일 과대. `ShortcutKeyCodeResolver` 테이블(~230줄)을 별도 파일로 분리 |
| `AXWindowElementRegistry.shared` | Provider가 쓰고 FocusService가 읽는 숨은 전역 결합. 스냅샷과 함께 명시적으로 전달하는 편이 추적 쉬움 |
| `SwitcherOverlayController.swift:97` | `NSScreen.main` 기준 배치 — 멀티 모니터에서 전면 앱이 다른 화면에 있으면 오버레이가 엉뚱한 화면에 뜸. 전면 창 화면 또는 마우스 화면 기준 권장 |
| `UsageMetricsStore.swift:102` | `windowUsageStorageKey(dayKey:)`가 파라미터를 무시하고 캐시 반환 — `dayKey(for:)`가 먼저 캐시를 비워줘야만 맞는 암묵적 순서 결합. 깨지기 쉬움 |
| 테스트 러너 | 수제 러너 잘 작동하지만 실패 시 위치/diff 리포팅 빈약. swift-testing(`@Test`) 이관 고려 — SPM 6.0이면 바로 가능 |

## 잘 된 점

- 계층 분리: Model / Service / UI / Policy 명확. 정책이 순수 함수라 테스트 커버리지 실질적.
- 모든 외부 의존(AX, ScreenCaptureKit, Carbon, UserDefaults, NSWorkspace)이 프로토콜 뒤에 있음.
- 썸네일 파이프라인: 세대(generation) 기반 취소, 디코드 캐시, 변경 없으면 objectWillChange 생략 — 성능 배려 좋음.
- Carbon 우선 + event tap 폴백 이중화, 예약 단축키 실패 시 폴백 단축키 + 사용자 메시지.

---

## 다음 작업 추천 (우선순위순)

1. ~~**안정적 창 식별자 도입**~~ ✅ 완료 (2026-07-02) — `_AXUIElementGetWindow` 기반 `PrivateAXWindowNumberResolver` 추가.
   CGWindowID를 windowIdentifier·screenCaptureIdentifier로 직접 사용, 실패 시 기존 인덱스 방식 폴백.
   썸네일 제목 매칭 휴리스틱은 폴백 경로에만 남음. (버그 1·5 해결)
2. ~~**최소화 창 복원 지원**~~ ✅ 완료 — `canFocus`에 minimized 포함, `AXWindowFocuser`가 `kAXMinimizedAttribute`
   해제 후 포커스. (버그 2 해결)
3. **릴리즈 자동화 마무리** — 이미 계획 문서 있음(노터라이즈, appcast 서명, R2 업로드). 배포 가능 상태 만들기.
   ← **다음 작업으로 이것 추천** (Sparkle 개인키·Developer ID 인증서 필요)
4. ~~**flush 내구성**~~ ✅ 완료 — 창 선택 확정 시 recency/usage 즉시 flush. (버그 4 해결)
5. **키보드 레이아웃 대응** — 미착수. `UCKeyTranslate` 기반 동적 매핑 필요. 해외 사용자 받기 전 필수.
6. ~~**멀티 모니터 오버레이 배치**~~ ✅ 완료 — 포인터가 있는 화면에 오버레이 표시 (`activeScreenFrame` 정책 + 테스트).
7. **배포 전략 확정** — App Store 포기 여부 결정. 참고: 이번에 도입한 `_AXUIElementGetWindow`는 private API라
   App Store 제출 불가를 확정함 (어차피 샌드박스 제약으로 불가능했음).

## 2026-07-02 적용 완료 내역

- 안정적 창 ID (`AccessibilityWindowProvider.swift`) — recency 정렬 정확성 확보
- 최소화 창 복원 (`WindowItem.swift`, `WindowFocusService.swift`)
- 선택 시 즉시 flush (`AppDelegate.swift`)
- `EventTapHotkeyRegistrar.deinit`에서 tap 해제 — unretained self 포인터 use-after-free 예방
- `HotkeyService.registeredSetting(for:)` mode별 딕셔너리로 정리
- 디버그 로그 1MB 상한 (초과 시 새로 시작)
- 멀티 모니터: 포인터 화면 기준 오버레이 배치
- `ShortcutKeyCodeResolver`를 별도 파일로 분리 (748줄 → 510줄 + 237줄), pbxproj 등록
- 테스트: 신규 6개 추가, 전체 스위트 통과. 직접 배포 스크립트 `--prepare-only` 패치 검증 통과.
- `_AXUIElementGetWindow` 심볼 가용성 이 머신에서 확인됨.
