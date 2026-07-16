# Blockers

## Live macOS permission and focus-flow validation

- 막힌 항목: Accessibility 권한, Screen Recording 권한, 실제 현재 앱 창 전환, 실제 창 썸네일 표시, System Settings 권한 복구 흐름의 end-to-end 수동 검증.
- 왜 내가 해결할 수 없는지: macOS TCC 권한은 사용자가 System Settings에서 직접 승인해야 하며, 앱이 대신 권한을 부여하거나 토글할 수 없다.
- 사용자가 해야 할 일: SwitchTab을 실행한 뒤 Accessibility와 Screen Recording 권한을 직접 허용하고, 앱을 재실행한다.
- 사용자가 제공해야 하는 자료 또는 결정: 권한 허용 여부와, 실제 실행 환경에서 Cmd+` 또는 설정된 대체 단축키 사용이 가능한지.
- 해결 후 다시 진행할 수 있는 다음 단계: `swift test`와 Xcode Debug build를 다시 실행한 뒤, 실제 앱에서 현재 앱 창 2개 이상을 열고 overlay 표시, 선택 이동, release-to-confirm focus, thumbnail 표시를 확인한다.
- 임시 우회를 하지 않은 이유: TCC DB 조작, System Settings 자동 클릭, 권한 상태 위조는 실제 사용자 흐름을 검증하지 못하고 macOS 보안 모델을 우회한다.

## Signed and notarized release validation

- 막힌 항목: `scripts/build-direct-distribution.sh --release`의 실제 Developer ID 서명, notarization, stapling, Gatekeeper 검증.
- 왜 내가 해결할 수 없는지: Apple Developer ID 인증서와 notarytool keychain profile은 사용자 계정/키체인 권한과 연결되어 있으며 내가 생성하거나 대체할 수 없다.
- 사용자가 해야 할 일: 유효한 `DEVELOPER_ID_APPLICATION` 값과 `NOTARYTOOL_KEYCHAIN_PROFILE`을 준비하고, release 검증 실행을 승인한다.
- 사용자가 제공해야 하는 자료 또는 결정: 사용할 Developer ID 인증서 이름, notarytool keychain profile 이름, release artifact 출력 위치.
- 해결 후 다시 진행할 수 있는 다음 단계: `SPARKLE_PUBLIC_ED_KEY`, `DEVELOPER_ID_APPLICATION`, `NOTARYTOOL_KEYCHAIN_PROFILE`을 설정하고 `scripts/build-direct-distribution.sh --release`를 실행해 DMG, checksum, notarization, stapling, Gatekeeper 결과를 확인한다.
- 임시 우회를 하지 않은 이유: ad-hoc 서명이나 dummy notary profile은 실제 배포 안전성을 검증하지 못한다.

## Sparkle appcast and update channel publication

- 막힌 항목: public auto-update 채널에 필요한 Sparkle update archive, signed `appcast.xml`, 호스팅/배포 경로 검증.
- 왜 내가 해결할 수 없는지: appcast signing key, update feed hosting 권한, 배포 URL 운영 결정이 필요하며 현재 release 스크립트는 DMG/checksum 생성까지만 자동화한다.
- 사용자가 해야 할 일: Sparkle appcast 생성/서명/호스팅 방식을 결정하고 필요한 signing key와 update feed 배포 권한을 준비한다.
- 사용자가 제공해야 하는 자료 또는 결정: production `SWITCHTAB_UPDATE_FEED_URL`, Sparkle appcast signing key 관리 방식, update archive 호스팅 위치, release publication 절차.
- 해결 후 다시 진행할 수 있는 다음 단계: release artifact 생성 뒤 Sparkle update archive와 signed appcast를 만들고, HTTPS feed URL에서 앱이 업데이트를 조회할 수 있는지 검증한다.
- 임시 우회를 하지 않은 이유: 서명되지 않은 appcast, 임시 HTTP feed, dummy key는 auto-update 신뢰 체인을 검증하지 못하고 사용자 업데이트 보안을 약화한다.
