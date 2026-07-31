# 앱 스위처 포커스 및 컴팩트 레이아웃 구현 계획

> **작업자 지침:** 이 계획은 `superpowers:executing-plans`로 항목별 실행한다. 각 동작 변경은 `superpowers:test-driven-development`의 RED → GREEN → REFACTOR 순서를 지킨다.

**목표:** 선택된 앱만 고정 높이 캡션을 표시하는 촘촘한 앱 스위처를 만들고, Command 키 릴리즈와 마우스 클릭 모두 선택 앱의 창을 실제로 앞으로 가져오게 한다.

**구조:** `SwitcherOverlayState` 옆에 순수 메타데이터 표시 정책을 두고, `SwitcherOverlayLayoutMetrics`가 앱 타일의 모든 고정 치수를 제공한다. SwiftUI 타일은 창 모드의 기존 렌더링을 그대로 유지하면서 앱 모드에서 아이콘 선택 컨테이너와 캡션을 분리한다. 활성화 경계는 대상 조회, cooperative activation 양도, `.activateAllWindows` 요청을 작은 AppKit 어댑터에서 순서대로 수행한다.

**기술:** Swift 5.10+, SwiftUI, AppKit, XCTest 호환 커스텀 테스트 러너, Xcode macOS 앱 타깃

**격리 작업공간:** `/Users/kendrick/projects/switchtab/.worktrees/application-switcher-focus-layout`

---

### 작업 1: 앱 메타데이터 표시 규칙을 테스트로 고정

**파일:**

- 수정: `SwitchTab/UI/Overlay/SwitcherOverlayState.swift`
- 수정: `SwitchTabTests/Services/SwitcherOverlayStateTests.swift`

- [ ] **1단계: 실패하는 메타데이터 정책 테스트 추가**

`SwitcherOverlayStateTests.run()`에 다음 테스트를 등록한다.

```swift
try testApplicationMetadataOnlyShowsForSelection()
try testApplicationMetadataOnlyShowsMultipleWindowCount()
```

선택 여부 테스트는 선택되지 않은 앱에 제목과 창 수가 모두 숨겨지고, 선택된 앱에는 제목이 표시됨을 요구한다.

```swift
static func testApplicationMetadataOnlyShowsForSelection() throws {
    let hidden = ApplicationSwitcherMetadataPolicy.presentation(
        isSelected: false,
        windowCountText: "3"
    )
    let selected = ApplicationSwitcherMetadataPolicy.presentation(
        isSelected: true,
        windowCountText: "3"
    )

    try expectEqual(hidden, .hidden)
    try expectTrue(selected.showsTitle)
    try expectEqual(selected.windowCountText, "3")
}
```

창 수 테스트는 `nil`, 숫자가 아닌 값, `0`, `1`을 숨기고 `2` 이상만 보이게 고정한다.

```swift
static func testApplicationMetadataOnlyShowsMultipleWindowCount() throws {
    let inputs: [String?] = [nil, "unknown", "0", "1", "2", "7"]
    let outputs = inputs.map {
        ApplicationSwitcherMetadataPolicy.presentation(
            isSelected: true,
            windowCountText: $0
        ).windowCountText
    }

    try expectEqual(outputs, [nil, nil, nil, nil, "2", "7"])
}
```

- [ ] **2단계: 테스트가 정책 부재로 실패함을 확인**

실행:

```bash
rtk swift test
```

예상: `ApplicationSwitcherMetadataPolicy`와 표시 값 타입이 없어 컴파일 실패.

- [ ] **3단계: 최소 순수 정책 구현**

`SwitcherOverlayState.swift`의 기존 표시 정책들과 함께 다음 값을 추가한다.

```swift
public struct ApplicationSwitcherMetadataPresentation: Equatable, Sendable {
    public let showsTitle: Bool
    public let windowCountText: String?

    public static let hidden = ApplicationSwitcherMetadataPresentation(
        showsTitle: false,
        windowCountText: nil
    )
}

public enum ApplicationSwitcherMetadataPolicy {
    public static func presentation(
        isSelected: Bool,
        windowCountText: String?
    ) -> ApplicationSwitcherMetadataPresentation {
        guard isSelected else {
            return .hidden
        }

        let visibleWindowCount = windowCountText
            .flatMap(Int.init)
            .flatMap { $0 >= 2 ? String($0) : nil }
        return ApplicationSwitcherMetadataPresentation(
            showsTitle: true,
            windowCountText: visibleWindowCount
        )
    }
}
```

Accessibility 라벨의 기존 실제 창 수 안내는 유지한다. 이 정책은 시각 표시만 제어한다.

- [ ] **4단계: 전체 테스트 통과 확인**

실행: `rtk swift test`

예상: 전체 통과, 실패 0.

- [ ] **5단계: 커밋**

```bash
rtk git add SwitchTab/UI/Overlay/SwitcherOverlayState.swift SwitchTabTests/Services/SwitcherOverlayStateTests.swift
rtk git commit -m "test: define application switcher metadata visibility"
```

---

### 작업 2: 앱 타일 치수와 고정 높이를 테스트로 고정

**파일:**

- 수정: `SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift`
- 수정: `SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift`

- [ ] **1단계: 실패하는 앱 레이아웃 수치 테스트 작성**

기존 `testApplicationModeUsesCompactLayoutMetrics()`를 승인된 기본 배율 수치로 갱신한다.

```swift
try expectEqual(applicationMetrics.tileSize, CGSize(width: 104, height: 119))
try expectEqual(applicationMetrics.thumbnailSize, CGSize(width: 96, height: 96))
try expectEqual(applicationMetrics.fallbackIconSize, CGSize(width: 96, height: 96))
try expectEqual(applicationMetrics.selectionContainerSize, CGSize(width: 104, height: 104))
try expectEqual(applicationMetrics.selectionCornerRadius, 26)
try expectEqual(applicationMetrics.captionHeight, 14)
try expectEqual(applicationMetrics.captionMaxWidth, 240)
try expectEqual(applicationMetrics.tileContentSpacing, 1)
try expectEqual(applicationMetrics.gridSpacing, 4)
try expectEqual(applicationMetrics.gridPadding, 16)
```

같은 테스트에서 창 전환 기본 수치 `168×158`, 간격 `14`, 패딩 `28`이 변하지 않았음을 계속 확인한다.

- [ ] **2단계: 선택 및 창 수 변화가 패널 높이를 바꾸지 않는 테스트 추가**

레이아웃은 메타데이터가 아닌 `itemCount`, 화면, 모드, 배율만 입력으로 받는다. 같은 앱 개수로 호출한 레이아웃 높이가 메타데이터 표시 정책 결과와 무관하게 동일하고, 캡션 공간이 항상 타일 높이에 포함됨을 확인한다.

```swift
static func testApplicationCaptionKeepsPanelHeightStable() throws {
    let layout = SwitcherOverlayLayoutPolicy.presentationLayout(
        itemCount: 8,
        screenSize: CGSize(width: 1440, height: 900),
        mode: .applicationSwitching
    )

    try expectEqual(layout.metrics.tileSize.height, 119)
    try expectEqual(
        layout.metrics.selectionContainerSize.height
            + layout.metrics.tileContentSpacing
            + layout.metrics.captionHeight,
        layout.metrics.tileSize.height
    )
}
```

- [ ] **3단계: 테스트 실패 확인**

실행: `rtk swift test`

예상: 새 metric 프로퍼티가 없고 기존 앱 타일이 `120×128`, 간격 `8`이므로 실패.

- [ ] **4단계: 앱 전용 metric을 최소 변경**

`SwitcherOverlayLayoutMetrics`에 다음 값을 추가한다.

```swift
public let selectionContainerSize: CGSize
public let selectionCornerRadius: CGFloat
public let captionHeight: CGFloat
public let captionMaxWidth: CGFloat
```

창 모드는 현재 타일 크기와 radius 7을 넣고 캡션 값은 0으로 둔다. 앱 모드는 배율 1에서 아래 상수를 사용하고 기존 `scaled(_:by:)`로 연속 배율한다.

```swift
private static let baseApplicationSelectionExtent: CGFloat = 104
private static let baseApplicationIconExtent: CGFloat = 96
private static let baseApplicationCaptionHeight: CGFloat = 14
private static let baseApplicationCaptionMaxWidth: CGFloat = 240
private static let baseApplicationTileContentSpacing: CGFloat = 1
private static let baseApplicationSelectionCornerRadius: CGFloat = 26
private static let baseApplicationGridSpacing: CGFloat = 4
```

앱 타일 높이는 `selectionExtent + spacing + captionHeight`, 폭은 `selectionExtent`에서 계산한다. 앱 `thumbnailSize`는 `96×96`으로 맞춰 선택 영역 안 사방 4pt가 동일하게 남도록 한다. 패널 padding은 기존 `gridPadding / 2`를 유지한다.

- [ ] **5단계: 전체 테스트 통과 및 커밋**

실행: `rtk swift test`

예상: 전체 통과, 창 모드 수치 회귀 없음.

```bash
rtk git add SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift SwitchTabTests/Services/SwitcherOverlayPresentationTests.swift
rtk git commit -m "test: lock compact application tile geometry"
```

---

### 작업 3: 선택 아웃라인과 캡션을 분리해 렌더링

**파일:**

- 수정: `SwitchTab/UI/Overlay/SwitcherIconStripView.swift`
- 검증: `SwitchTab/UI/Overlay/SwitcherOverlayRootView.swift`
- 검증: `SwitchTab/UI/Overlay/SwitcherOverlayLayoutPolicy.swift`

- [ ] **1단계: 기존 창 타일 렌더링을 별도 경로로 유지**

현재 Button 전체에 적용된 배경·clip·stroke를 창 모드 경로로 옮긴다. 창 모드의 `windowContent`, 제목 헤더, 미리보기, 닫기 버튼, radius 7, hit area는 바꾸지 않는다.

- [ ] **2단계: 앱 아이콘 선택 컨테이너 구현**

앱 경로는 고정 크기 `VStack` 안에서 아이콘 컨테이너와 캡션 슬롯을 분리한다.

```swift
private func applicationContent(for item: SwitcherListItem) -> some View {
    let metadata = ApplicationSwitcherMetadataPolicy.presentation(
        isSelected: isSelected,
        windowCountText: item.subtitle
    )

    return VStack(alignment: .center, spacing: layoutMetrics.tileContentSpacing) {
        icon(for: item)
            .frame(
                width: layoutMetrics.selectionContainerSize.width,
                height: layoutMetrics.selectionContainerSize.height
            )
            .background(isSelected ? Color.accentColor.opacity(0.28) : Color.clear)
            .clipShape(
                RoundedRectangle(cornerRadius: layoutMetrics.selectionCornerRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: layoutMetrics.selectionCornerRadius)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.95) : Color.clear,
                        lineWidth: 2
                    )
            }

        Color.clear
            .frame(height: layoutMetrics.captionHeight)
            .overlay {
                if metadata.showsTitle {
                    applicationMetadata(for: item, windowCountText: metadata.windowCountText)
                }
            }
    }
    .frame(width: layoutMetrics.tileSize.width, height: layoutMetrics.tileSize.height)
}
```

선택 배경과 2pt 파란 아웃라인은 정확히 `104×104`, radius 26인 아이콘 컨테이너에만 적용한다. 캡션은 선택 영역 밖에 있어 파란색이 겹치지 않는다.

- [ ] **3단계: 선택 앱 캡션을 아이콘 중앙 아래에 표시**

캡션은 한 줄, 중앙 정렬, 최대 240pt이며 그리드 셀 폭에는 영향을 주지 않도록 고정 높이 슬롯의 overlay로 렌더링한다.

```swift
private func applicationMetadata(
    for item: SwitcherListItem,
    windowCountText: String?
) -> some View {
    HStack(alignment: .center, spacing: 3) {
        Text(item.title)
            .lineLimit(1)
            .truncationMode(.tail)
            .layoutPriority(1)

        if let windowCountText {
            Image(systemName: "rectangle.on.rectangle")
                .accessibilityHidden(true)
            Text(windowCountText)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
    .font(.system(size: layoutMetrics.titleFontSize, weight: .medium))
    .frame(width: layoutMetrics.captionMaxWidth)
}
```

창 수가 0, 1, 알 수 없음이면 정책이 `nil`을 전달하므로 제목만 보인다. 2 이상이면 선택된 제목 옆에만 glyph와 숫자가 보인다. 선택되지 않은 타일도 14pt의 투명 캡션 슬롯은 유지해 선택 이동 시 타일과 패널 높이가 바뀌지 않는다.

- [ ] **4단계: 빌드와 전체 테스트로 SwiftUI 타입 확인**

실행:

```bash
rtk swift test
rtk xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
```

예상: 테스트 전체 통과, `** BUILD SUCCEEDED **`.

- [ ] **5단계: 커밋**

```bash
rtk git add SwitchTab/UI/Overlay/SwitcherIconStripView.swift
rtk git commit -m "feat: focus application switcher metadata"
```

---

### 작업 4: cooperative activation 순서를 테스트로 재현하고 수정

**파일:**

- 수정: `SwitchTab/Services/ApplicationActivationService.swift`
- 수정: `SwitchTabTests/Services/ApplicationSwitchingTests.swift`

- [ ] **1단계: 실패하는 AppKit 활성화 순서 테스트 작성**

실제 `NSRunningApplication`을 테스트에서 만들지 않도록 내부 대상 경계를 사용한다. 가짜 대상은 호출 순서를 기록한다.

```swift
static func testSystemActivatorYieldsBeforeActivatingAllWindows() throws {
    let target = FakeApplicationActivationTarget(activationResult: true)
    let provider = FakeApplicationActivationTargetProvider(target: target)
    let activator = NSRunningApplicationActivator(targetProvider: provider)

    let result = activator.activate(processIdentifier: 404)

    try expectTrue(result)
    try expectEqual(provider.processIdentifiers, [404])
    try expectEqual(target.events, ["yield", "activateAllWindows"])
}
```

종료된 대상은 양도나 활성화를 호출하지 않고 실패해야 한다.

```swift
static func testSystemActivatorRejectsTerminatedTargetBeforeYield() throws {
    let target = FakeApplicationActivationTarget(
        isTerminated: true,
        activationResult: true
    )
    let activator = NSRunningApplicationActivator(
        targetProvider: FakeApplicationActivationTargetProvider(target: target)
    )

    try expectTrue(!activator.activate(processIdentifier: 405))
    try expectEqual(target.events, [])
}
```

기존 coordinator 테스트는 `activate → record → flush` 및 실패 시 MRU 미기록을 계속 보장한다. 기존 오버레이 확인 테스트는 Command 릴리즈와 마우스 클릭이 동일 `onConfirm` 콜백에 도달함을 그대로 보장한다.

- [ ] **2단계: 새 테스트가 경계 부재로 실패함을 확인**

실행: `rtk swift test`

예상: activation target/provider 타입과 주입 initializer가 없어 컴파일 실패.

- [ ] **3단계: 테스트 가능한 최소 AppKit 대상 경계 추가**

`ApplicationActivationService.swift`에 내부 프로토콜을 둔다.

```swift
protocol ApplicationActivationTarget: AnyObject {
    var isTerminated: Bool { get }
    func yieldActivation()
    func activateAllWindows() -> Bool
}

protocol ApplicationActivationTargetProviding {
    func target(processIdentifier: Int) -> (any ApplicationActivationTarget)?
}
```

시스템 래퍼는 같은 `NSRunningApplication` 인스턴스에 대해 cooperative handoff 후 전체 창 활성화를 호출한다.

```swift
final class NSRunningApplicationActivationTarget: ApplicationActivationTarget {
    private let application: NSRunningApplication

    init(application: NSRunningApplication) {
        self.application = application
    }

    var isTerminated: Bool { application.isTerminated }

    func yieldActivation() {
        NSApp.yieldActivation(to: application)
    }

    func activateAllWindows() -> Bool {
        application.activate(options: .activateAllWindows)
    }
}
```

`NSRunningApplicationActivator`는 provider로 대상을 한 번 조회하고 순서를 고정한다.

```swift
struct NSRunningApplicationActivator: ApplicationActivating {
    let targetProvider: any ApplicationActivationTargetProviding

    init(
        targetProvider: any ApplicationActivationTargetProviding
            = NSRunningApplicationActivationTargetProvider()
    ) {
        self.targetProvider = targetProvider
    }

    func activate(processIdentifier: Int) -> Bool {
        guard let target = targetProvider.target(processIdentifier: processIdentifier),
              !target.isTerminated else {
            return false
        }

        target.yieldActivation()
        return target.activateAllWindows()
    }
}
```

입력 경로별 별도 활성화 코드는 추가하지 않는다. `SwitcherOverlayController.apply`가 먼저 오버레이와 Event Tap을 정리한 뒤 공통 `onConfirm`을 실행하는 기존 순서를 유지한다.

- [ ] **4단계: 활성화 및 전체 회귀 테스트 확인**

실행:

```bash
rtk swift test
rtk xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
```

예상: `yield → activateAllWindows → record → flush` 순서, 실패 시 MRU 미기록, 전체 테스트 통과, 앱 빌드 성공.

- [ ] **5단계: 커밋**

```bash
rtk git add SwitchTab/Services/ApplicationActivationService.swift SwitchTabTests/Services/ApplicationSwitchingTests.swift
rtk git commit -m "fix: hand off application activation before switching"
```

---

### 작업 5: 수동 QA 계약과 실제 macOS 동작 검증

**파일:**

- 수정: `specs/001-macos-switchtab/quickstart.md`
- 수정: `specs/001-macos-switchtab/contracts/switcher-behavior.md`
- 증거: `.build/qa/application-switcher-focus-layout/`

- [ ] **1단계: 승인 기준을 한국어 구현 결과와 일치하도록 문서화**

계약에 다음을 추가한다.

- 선택되지 않은 앱은 아이콘만 표시
- 선택된 앱 제목은 아이콘 바로 아래 중앙 정렬
- 창 수 0/1/알 수 없음은 숨김, 2 이상만 표시
- 선택 아웃라인은 제목이 아닌 아이콘 컨테이너만 덮음
- 선택 이동과 비동기 창 수 갱신 시 패널 높이 고정
- Command 릴리즈와 마우스 클릭 모두 실제 frontmost 앱 변경

- [ ] **2단계: 정적 검증 실행**

```bash
rtk swift test
rtk xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
rtk git diff --check
```

예상: 전체 테스트 통과, 앱 빌드 성공, whitespace 오류 없음.

- [ ] **3단계: 실제 앱 실행과 시각 QA**

Debug 앱을 실행하고 Finder, Safari, TextEdit를 포함해 다음을 확인한다.

1. Cmd-Tab을 누른 채 Tab/Shift-Tab/화살표/hover로 이동해도 패널 높이가 고정된다.
2. 선택되지 않은 앱에는 제목과 창 수가 없다.
3. 선택된 제목이 아이콘 중앙 바로 아래에 있고 파란 영역과 겹치지 않는다.
4. 창 1개 앱은 제목만, 창 2개 이상 앱은 제목 옆 glyph/숫자가 보인다.
5. Command 릴리즈 후 선택 앱과 `NSWorkspace.frontmostApplication`이 일치한다.
6. 마우스 클릭 후에도 동일하게 대상 앱 창이 앞으로 온다.
7. 기존 Option-Tilde 창 전환의 제목, 미리보기, 닫기, 크기가 변하지 않는다.

스크린샷과 선택/실제 frontmost 앱 식별 결과를 `.build/qa/application-switcher-focus-layout/`에 저장한다. `.build` 증거는 커밋하지 않는다.

- [ ] **4단계: 문서 커밋**

```bash
rtk git add specs/001-macos-switchtab/quickstart.md specs/001-macos-switchtab/contracts/switcher-behavior.md
rtk git commit -m "docs: add focused application switcher acceptance"
```

---

### 작업 6: 리뷰, 다음 patch 버전, PR 및 자동 릴리스

**파일:**

- 검토: 이 브랜치의 `origin/main...HEAD` 전체 diff
- 자동 갱신 예상: `SwitchTab.xcodeproj/project.pbxproj`
- 검증: `.github/workflows/ci.yml`, `.github/workflows/automatic-release.yml`, `.github/workflows/release.yml`

- [ ] **1단계: 완료 전 검증과 코드 리뷰**

`superpowers:verification-before-completion`, `/review`, `/ship` 지침을 순서대로 적용한다. diff가 이 계획의 UI, 정책, 활성화, 테스트, 문서에만 한정됐는지 확인한다.

- [ ] **2단계: 전체 검증 재실행**

```bash
rtk swift test
rtk xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
rtk git diff --check
rtk git status --short --branch
```

- [ ] **3단계: patch 릴리스 준비**

현재 기준 버전은 `1.1.3` / build `14`다. 저장소의 자동 버전 정책으로 다음 patch인 `1.1.4`와 증가된 build number를 준비한다. 수동으로 별도 changelog 체계를 만들지 않고 저장소의 PR/자동 릴리스 워크플로를 따른다.

- [ ] **4단계: 푸시, PR, CI, 머지**

`/ship` 절차로 브랜치를 푸시하고 PR을 만든다. CI 전체 통과와 fresh review를 확인한 뒤 main에 머지한다. 외부 상태 변경은 사용자가 이미 요청한 “다음 버전 릴리스” 범위 안에서만 수행한다.

- [ ] **5단계: 자동 릴리스와 배포 후 검증**

main push가 만든 annotated `v1.1.4` 태그와 `release.yml` 실행을 확인한다. GitHub Release, notarized DMG, checksum/manifest, Sparkle appcast, 공개 다운로드 URL, Homebrew 연동 결과를 저장소 계약에 따라 검증한다. 실패하면 원인과 재시도 가능한 안전 단계만 수행하고, 기존 릴리스 자산을 덮어쓰지 않는다.
