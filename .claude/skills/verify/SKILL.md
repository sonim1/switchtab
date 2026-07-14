---
name: verify
description: Verify SwitchTab changes via SwiftPM build + the custom SwitchTabTestRunner (+ Xcode app build when available). Use before claiming any change done.
---

# Verify (SwitchTab)

```bash
swift build
swift run SwitchTabTestRunner     # the test gate — NOT `swift test`
```

Xcode available → also build the `SwitchTab` scheme (Debug):
```bash
xcodebuild -project SwitchTab.xcodeproj -scheme SwitchTab -configuration Debug build
```

## Triage

- Runner not exercising your new test → tests are registered/discovered per `SwitchTabTests/TestRunner.swift` conventions; wire the new suite like existing ones and rerun.
- SwiftPM compiling Resources it shouldn't → update the `exclude:` list in Package.swift alongside your added resource.
- Swift 6 concurrency errors → read the enclosing type's isolation; fix by matching patterns, not by `@unchecked Sendable`.
- Behavior claims: window switching depends on Accessibility permission — runtime checks need the app actually running with permission granted. Can't do that here → report "compile+tests green; runtime not verified".

Completion = build + runner output pasted; Xcode-build status (or "Xcode unavailable"); runtime-verification status stated explicitly.
