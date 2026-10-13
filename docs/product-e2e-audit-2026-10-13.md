# SwitchTab 뷰별 E2E 감사와 개선 결과

작성일: 2026-10-13. 기준 소스: `84d88a8` / 설치 앱 `1.1.29 (40)`.
개선 소스: `a0ed7df`까지의 앱 변경. 검증 환경: macOS 26.5.1, Apple Silicon.

## 판단과 우선순위

가장 큰 문제는 창의 수명과 SwiftUI 뷰의 수명을 같다고 취급한 부분이었다. 설정 창은 닫혀도 유지되므로 `onDisappear`만으로 단축키 기록을 정리할 수 없었다. About과 Settings가 각각 프로세스 전체 활성화 정책을 변경하는 것도 두 창을 함께 사용하는 상황을 다루지 못했다.

이번 개선은 이 두 수명 문제를 먼저 고쳤다. 이후 실제 화면에서 확인한 권한 복구 안내, 선택 상태의 접근성, 밝은 모드 대비, 제품 설명과 사용 횟수의 정확성을 개선했다. 전환 알고리즘을 바꾸기보다, 기존 동작을 회귀 검증하고 책임이 잘못 놓인 코드를 옮기는 방향을 택했다.

자동 검증은 XCTest **96개, 기존 선택적 테스트 2개 skip, 실패 0개**다. unsigned Xcode Debug와 Developer ID 직접 배포용 Release 빌드가 통과했다. 릴리즈·보안·랜딩 관련 계약 테스트 19개도 통과했다. 아래 런타임 결과는 실제 서명한 앱과 별도 소유 테스트 창을 사용한 관찰이다.

## 발견하고 수정한 문제

| 우선순위 | 재현 조건과 영향 | 개선 | 근거 |
| --- | --- | --- | --- |
| P1 | 단축키 기록 중 Settings를 닫고 다시 열면 Recording이 남고 전역 단축키가 복구되지 않음 | 창 컨트롤러가 기록 coordinator를 소유하고 닫기·Practice 숨기기에서 명시적으로 취소 | `recording-before-close.ax.txt`, `recording-after-reopen.ax.txt`, `recording-close-global-switch.txt` |
| P1 | Settings와 About을 함께 열고 하나를 닫으면 남은 창이 있는데 accessory 정책으로 전환 | 두 창이 공유하는 coordinator에서 소유자를 Set으로 관리. 첫 창에서 regular, 마지막 창에서 accessory | 두 닫기 순서의 `*-close-policy.txt`, 마지막 창 정책 결과 |
| P2 | 두 보조 패널이 앱 비활성화 시 자동으로 숨겨짐 | 공유 패널 factory의 `hidesOnDeactivate=false`; 일반 창 레벨 유지 | 비활성 앱의 on-screen 창 수가 0에서 1로 바뀜. 실제 입력·스크롤 성공 |
| P2 | 오버레이의 파란 선택 표시는 AX에 선택 상태로 노출되지 않음 | 선택 trait와 Selected/Not selected 값, 기존 item ID를 AX 식별자로 제공 | 두 모드에서 선택 하나, 화살표 이동 후 선택 ID 변경, 취소 후 원래 다음 MRU ID 유지 |
| P2 | 권한 거부 상태의 System Settings 경로가 info 이미지의 hover 도움말에만 존재 | 전체 안내를 본문에 표시하고 권한별 그룹과 독립적인 Allow 버튼 유지 | 네 권한 조합에서 복구 버튼 수 2/1/1/0, 거부 상태의 전체 경로가 본문에 노출 |
| P2 | 밝은 모드에서 About 버튼은 어두운 면 위 검은 글자, Enabled와 오류 문구는 옅은 색 글자 | 시스템 배경·primary/secondary 의미 색상 사용. 오류 아이콘의 색과 문구 색 분리 | About light/dark, Enabled light, shortcut warning light의 전후 스크린샷 |
| P2 | 설명이 현재 앱 창 전환만 언급하고 전체 단축키 사용량처럼 집계를 표현 | 앱·창 전환을 모두 설명. 집계는 window shortcut uses로 명시하고 취소한 선택도 포함한다고 설명 | 0/1/복수 문구 회귀 테스트, 실제 About 내용. 기존 저장 키·카운터 그대로 |
| P2 | 선택적인 Screen Recording이 없으면 필수 조건이 부족한 듯한 헤더를 표시 | `Previews off / Window switching is available`와 선택적 미리보기 권한 설명 | 혼합 권한 fixture, 기존 focus 차단 여부가 바뀌지 않는 회귀 테스트 |

장식 이미지의 불필요한 AX 노출을 줄였고, Settings/Practice/About에 제목과 그룹 의미를 추가했다. `Shortcut` 탭 이름과 안내를 `Shortcuts`로 맞췄다.

중요한 관찰 보정: CUA는 인접한 여러 정적 텍스트를 긴 한 줄로 합쳐 표시할 수 있다. 원본 System Events AX 조회에서는 About의 개별 텍스트가 분리돼 있었다. 따라서 이를 “About 전체가 하나의 네이티브 AX 요소”라는 결함으로 집계하지 않았다. 제목 modifier 추가가 실제 VoiceOver 발화를 증명하지도 않는다.

## 뷰별 특징과 결과

### General

620×500 고정 콘텐츠 안에 스크롤이 있는 일반 설정이다. 시작 시 실행, 메뉴 아이콘, 연속적인 오버레이 크기 조절을 제공한다. 직접 배포 빌드에는 버전·수동 업데이트·자동 확인 설정이 추가된다. 업데이트 기능이 없는 빌드에서는 해당 섹션이 사라진다.

실제 앱에서 자동 확인 설정은 off였고, 아래쪽 항목은 스크롤 후 접근할 수 있었다. Check는 Sparkle의 “1.1.29 is currently the newest version available” 대화상자를 열었고 OK로 정상 복귀했다. 고정 높이 때문에 일부 항목이 초기 화면 아래에 있다는 사실 자체를 잘림 결함으로 보지 않았다.

별도 fixture에서는 로그인·아이콘 바인딩이 반대로 바뀌고 원래 값으로 복원되는 것을 확인했다. 슬라이더의 네이티브 Decrement는 100%→95%, Increment는 95%→100%로 동작했다. fixture의 로그인 서비스는 모의 서비스다. 실제 OS 로그인 항목 등록을 켰다 끄는 검증으로 해석하면 안 된다.

### Shortcuts

창 전환과 앱 전환을 독립적으로 켜고 기록·복원한다. 표시 값과 실제 등록 값은 다를 수 있으므로 오류·등록 메시지가 중요하다. 기본값에서는 Reset이 비활성화되는 것이 정상이다.

기록 중 닫기와 재오픈을 실제 앱에서 재현한 뒤 수정했다. 수정 후 전역 창 단축키가 오버레이를 다시 열었고 Recording이 사라졌다. 두 행을 번갈아 기록하면 한 행만 기록 상태를 소유했다. Escape는 기존 값을 유지했다.

plain K는 저장되지 않았고 “Shortcut must include at least one modifier”가 표시됐다. 기록은 종료된다. 초기 QA에서 기록이 계속되어야 한다고 잘못 가정했으나, 소스와 실제 오류 표시를 확인해 정상적인 거부 동작으로 판정했다. 유효한 Option+Control+K는 실제로 등록되어 C→B 포커스 전환을 수행했다. 이후 원래 Cmd+Backtick / Cmd+Tab으로 복원했다.

### Permissions

Accessibility는 관찰·포커스를 위한 권한이고 Screen Recording은 미리보기용 선택 권한이다. 둘을 동일한 기능 차단으로 설명하지 않아야 한다. 등록 상태를 나타내는 색에만 의존하지 않고 Enabled, 차단 기능, 경로와 Allow 동작을 읽을 수 있어야 한다.

원래는 경로가 info 이미지의 AX Help에는 있었지만 본문에는 없었다. 개선 후 두 경로가 hover 없이 보이고 줄바꿈되며, Allow는 별도의 버튼으로 탐색된다. 두 권한 모두 거부, 각각 하나만 거부, 모두 허용 상태를 실제 생산 뷰를 호스팅한 fixture에서 검사했다. 호스트 TCC 권한은 변경하지 않았다.

### Practice / How to Use

저장하고 싶은 단축키가 아니라 실제 등록된 단축키를 가르친다. Start Practice는 설정을 숨기고 이전 앱으로 돌아간다. 단순 요청 성공이나 오버레이 표시가 아니라 선택한 정확한 창의 포커스를 확인한 뒤 완료된다.

실제 테스트 창 전환 후 “Window switch verified”와 Practice Again을 확인했다. 다시 시도하고 Escape로 취소한 뒤 How to Use를 열면 “Practice cancelled”가 표시됐다. Settings와 About의 존재를 먼저 확인한 별도 시도에서는 Practice가 Settings만 숨기고 About은 regular 정책으로 유지했다.

처음 시도에서는 About 메뉴 클릭 직후 다음 메뉴를 바로 누르는 자동화가 창의 존재를 확인하지 못했다. 이 결과는 두 창 공존 테스트로 계산하지 않았다. 메뉴를 각각 실행하고 실제 두 창을 확인한 뒤 재검증했다. 숨긴 Settings에 연결된 CUA 핸들은 재조회 시 timeout될 수 있으므로 남은 창에 새로 연결했다.

### 창 오버레이

현재 앱 또는 앱 모드에서 선택한 앱의 창을 보여주는 썸네일 그리드다. 제목의 시각적 축약과 별개로 AX 이름은 전체 제목을 제공한다. 최소화 상태는 복원 안내를 제공한다. 창 닫기 기능은 이 모드에 있다.

실제 미리보기, 선택 trait·값·ID, 화살표 이동, Return 확정, release 확정, Escape 취소와 다음 MRU 유지가 확인됐다. 최소화한 A의 AXMinimized는 true→false가 되었고 A가 main/frontmost 창이 됐다. 선택한 A를 Cmd+W로 닫자 정확한 ID만 빠지고 3개 항목이 2개로 줄었다. 원래 main 창 B는 유지됐다.

### 앱 오버레이와 모드 전환

앱 모드는 아이콘 중심이며 선택 항목에 캡션과 필요한 창 수를 표시한다. 창 썸네일·창 닫기는 제공하지 않는다. 앱 종료는 정상 termination 요청으로 처리한다.

앱 모드도 선택 하나와 이동·취소·MRU 유지가 확인됐다. 테스트 앱을 선택해 앱→창으로 넘어가면 소유 테스트 창 목록을 보였고, Tab으로 앱 모드에 돌아갈 때 한 앱을 전진했다. Escape 후 원래 앱·창을 유지했다.

앱 타일의 실제 AXPress는 별도 view fixture를 정확히 활성화했다. Cmd+Q는 소유 fixture만 종료했고 해당 앱 ID가 목록에서 제거됐다. 저장 대화상자가 있는 사용자의 앱을 종료하는 실험은 하지 않았으며, 거부·저장 대화상자 처리 전체를 이 결과로 보장하지 않는다.

### About / Acknowledgments / 업데이트 대화상자

About은 버전, 빌드와 로컬 window-shortcut 사용 횟수의 스냅샷이다. 성공한 창 전환 수나 다운로드·활성 사용자 통계가 아니다. 반복과 취소된 선택을 포함하는 기존 집계를 유지했다.

두 시스템 appearance에서 본문과 버튼을 읽을 수 있고 Contact Support와 Acknowledgments는 별도 AX 버튼으로 남는다. Acknowledgments의 실제 modal을 열고 OK로 닫았다. Contact Support의 mailto 대상은 소스로 확인했으며 이메일을 생성·전송하는 동작으로 검증하지 않았다.

About 수치는 show 시점의 스냅샷이다. 열린 채로 단축키를 사용하면 즉시 갱신되지 않는다. 정보 창의 현재 계약으로 유지했으며, 라이브 통계를 원하는 경우의 개선 항목으로 분류했다.

## 코드와 구조의 정리

| 책임 | 변경 전 | 변경 후 / 이유 |
| --- | --- | --- |
| 기록 수명 | 자식 SwiftUI 행의 onDisappear에 의존 | 창 소유자가 coordinator를 주입하고 명시적으로 cancel. coordinator는 소유권을 먼저 비우고 종료 callback 실행 |
| 프로세스 활성화 | Settings/About의 무조건적인 개별 regular/accessory 변경 | `AuxiliaryWindowActivationPolicyCoordinator` 하나와 두 소유자. 반복 show/close와 미등록 close는 멱등 |
| 패널 정책 | NSPanel 기본 비활성화 숨김 | 두 보조 창의 factory에 정책 한 줄. 오버레이 controller의 패널 정책과 독립 |
| 접근성 식별 | 문자열·표시 형태에 의존하는 자동화 | 모델의 기존 item ID를 AXIdentifier로 제공. 별도 선택 상태나 저장 키를 만들지 않음 |
| 권한 상세 | 첫 줄 추출 + tooltip 이미지 | 전체 상세 본문. 중복 경로와 이미지 제거 |
| 색상 | 특정 appearance를 가정한 white/green/yellow 텍스트 | 시스템 의미 색상. 상태는 문구로 전달하고 장식 아이콘 색은 유지 |

기존 공개 coordinator 이름은 typealias로 호환된다. 사용량 데이터, 단축키 저장 형식, 독립 모드 MRU, 선택·확정 알고리즘, 최소화 복원과 미리보기 예산은 바꾸지 않았다. 새 런타임 의존성이나 원격 앱 추적은 추가하지 않았다.

## 검증 기록

근거 파일은 기본 checkout의 `.omo/evidence/product-e2e-2026-10-13/`에 있고 저장소에는 포함하지 않는다. 민감할 수 있는 설정 백업과 실행 파일도 그 로컬 디렉터리에만 둔다.

| 영역 | 방법 | 결과 / 파일 |
| --- | --- | --- |
| baseline | 기존 앱 + 전체 SwiftPM suite | 86 cases, 2 skip, 실패 0 / `e2e-baseline-2026-10-13.log`는 `.omo/`에 있음 |
| 기록·창 정책 | 실패하는 회귀 추가 후 수정 | `recording-red.log`, `activation-red.log`, `panel-visibility-red.log` |
| 집계·선택 권한 안내 | 실제 이전 문구 실패 후 변경 | `about-copy-red-targeted.log`, `optional-preview-red.log` |
| 최종 라이브러리 | 전체 XCTest | 96 cases, 2 기존 선택적 skip, 실패 0 / `final-unit.log` |
| 앱 컴파일·서명 | Xcode Debug, direct Release, strict codesign verify | `xcode-debug-build.log`, `candidate-build.log`, `candidate-binary-sha256.txt` |
| 계약·구문 | 19개 계약 스크립트와 shell syntax | `contracts-and-syntax.log`, 도구·문서 작성 후 `final-tooling-contracts-and-syntax.log`도 통과; 두 fixture build와 잘못된 옵션 거부 확인 |
| QA 도구·배포 준비 | 추적되는 fixture 새 실행과 bounded driver, prepare-only | `candidate/tracked-fixture-window-nav-cancel.txt`, `tracked-fixture-quit.txt`, `prepare-only.log` |
| 창 취소·Return·복원 | 실제 글로벌 입력과 native AX | `candidate/window-nav-cancel.txt`, `window-return.txt`, `minimized-return.txt` |
| 앱 취소·handoff·활성화·종료 | 실제 글로벌 입력과 native AX | `app-nav-cancel.txt`, `mode-handoff.txt`, `app-click-owned-view.txt`, `quit-owned-app.txt` |
| 창 닫기 | 소유된 선택 ID를 확인하고 Cmd+W | `close-owned-window.txt` |
| 기록 종료·복구 | 실제 창 닫기, 재오픈, 등록 shortcut 사용 | `recording-*.ax.txt`, `recording-close-global-switch.txt`, `custom-shortcut-confirmation.txt` |
| 보조 창 공존 | 두 닫기 순서, 마지막 닫기, Practice hide | `*-close-policy.txt`, `practice-both-windows-before.txt`, `practice-hide-*` |
| appearance·권한·바인딩 | 생산 뷰의 독립 fixture와 native AX/스크린샷 | `candidate/permissions-*`, `about-fixture-*`, `shortcut-warning-light.*`, `general-fixture-*` |
| Practice 결과 | 정확한 창으로 전환 후 가이드 재오픈, 취소 후 재오픈 | `practice-after-first-switch.ax.txt`, `practice-cancelled.ax.txt` |

기존 aggregate testAllSuites를 단독 실행한 한 번의 시도에서 AppKit `InvalidTransition idle -> failed(deinit)`가 발생했다. 테스트를 지우거나 skip하지 않았다. UI와 무관한 문구 회귀는 별도의 XCTest로 실제 이전 문자열 실패를 확인했고 전체 suite는 반복된 소스 변경 이후에도 정상 통과했다. 이 간헐적 하네스 문제는 추후 분리 조사 대상이다.

또한 in-process SwiftPM 호스팅 프로토타입은 SwiftUI AX 내용 대신 AppKit 창 컨트롤만 관찰해 제거했다. 그 실패를 제품 결함이나 접근성 검증 결과로 계산하지 않았다. 네이티브 AX 검증은 실제 외부 관찰로 수행했다.

## 통합적으로 다음 개선을 선택한다면

| 우선순위 | 개선 | 선택 이유와 완료 조건 |
| --- | --- | --- |
| 다음 접근성 검증 | 실제 VoiceOver 발화·키보드 탐색, 선택 이동·취소·닫기 | AX 속성만으로 screen reader 사용성을 보장할 수 없음. 중복 발화와 단축키 충돌을 직접 관찰하고 재현한 경우 수정 |
| 다음 호환성 검증 | macOS 14/15/26, multi-display, Spaces/fullscreen, Finder/Safari | 이번 환경은 26.5.1과 소유 앱이다. OS·앱별 포커스/미리보기 경계는 별도 장치·세션 matrix로 확장 |
| 다음 엔지니어링 개선 | legacy static run() suite를 기능별 XCTest로 분리 | 하나의 aggregate 사례가 원인을 숨김. 기존 assertion을 보존하고 독립 필터·이름을 제공; AppKit 예외를 최소 재현 |
| 선택적 UX | About의 사용 횟수 live refresh | show 시점 스냅샷은 정확하지만 지속적인 dashboard 용도에는 부족. 표시 중에만 갱신하고 midnight·종료·취소 집계 계약을 유지 |
| 선택적 QA 자동화 | 서명/TCC가 준비된 별도 macOS 검증 환경 | CI 빌드와 실제 글로벌 입력 검증을 분리. 안정된 ID, 모의 권한 UI, 소유 창을 기준으로 안전하게 반복 |

이번 범위의 필수 회귀와 생산 뷰 검증은 완료했다. 위 표는 별도 환경 또는 제품 요구가 필요한 후속 작업의 우선순위다.

## 검증의 경계와 운영 상태

VoiceOver 발화, 실제 권한 허용·철회·재시작, OS 로그인 등록 변경, 여러 OS/Spaces/디스플레이 전체, 저장 대화상자에서 앱 종료 거부는 직접 확인하지 않았다. 권한 거부 UI는 주입한 상태로 확인했고 실제 머신은 기존 허용 상태를 유지했다. WCAG 전체 적합성을 인증한 보고서가 아니다.

이 작업은 로컬 `improvement/product-e2e` 브랜치와 서명한 검증 빌드에 대한 결과다. 사용 중이던 공개 `1.1.29 (40)` 번들을 복구했고 strict 서명 검증과 보관본의 실행 파일 해시 일치를 확인했다. 기본 단축키 Cmd+Backtick / Cmd+Tab과 Practice 미완료·미닫음 상태를 복원했으며, 소유 QA 앱을 종료하고 modifier를 해제했다. 사용 횟수는 실제 QA 입력을 포함하므로 이전 값으로 덮어쓰지 않았다. 공개 릴리즈와 GitHub 배포 상태는 변경하지 않았다. `restored-owned-preferences.txt`, `restored-practice-content.txt`가 복원 근거이며 재현 절차는 [네이티브 QA runbook](native-product-qa.md)을 따른다.
