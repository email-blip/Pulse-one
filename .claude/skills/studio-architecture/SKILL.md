---
name: studio-architecture
description: Studio standard for iOS app architecture, security, privacy and performance - module layout, Swift 6 concurrency, Observation, persistence, Keychain, privacy manifest, offline behaviour, performance tests with XCTMetric. Use when creating an app skeleton, adding a feature module, storing data, handling secrets, or investigating performance.
---

# Architecture, Security, Performance

## Activation
- New app or feature, new dependency, persistence, networking, secrets, background work, performance issue.

## Architecture
- Layout per app: `apps/<App>/Sources/{App,Features/<Feature>,DesignSystem,Services,Models}`, tests in `Tests/` (Swift Testing) and `UITests/`.
- Pure logic in a local Swift package `apps/<App>/Packages/<App>Core` (no UIKit/SwiftUI imports) – testable fast and later also on Linux/Windows toolchains.
- State: `@Observable` models owned by the feature root (`@State`), passed down; `@Environment` for services. No singletons except Apple's.
- Concurrency: Swift 6 language mode, complete checking. UI types `@MainActor`; services as `actor` or `Sendable` structs. No `DispatchQueue` in new code. No `@unchecked Sendable` without comment + DECISIONS entry.
- Dependencies through protocols at service boundaries (`SoundPlaying`, `HapticPlaying`, `Clock`) so tests inject fakes.
- Persistence: SwiftData or files in Application Support; schema versioned.

## Security & privacy
- Secrets: Keychain only (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` unless backup needed). Never in `UserDefaults`, Info.plist, or the repo.
- `PrivacyInfo.xcprivacy` in every app; list required-reason APIs actually used (e.g. `UserDefaults` → reason `CA92.1`).
- Data stays on device unless the owner approved otherwise; ATS on, no arbitrary loads.
- File protection `.completeUntilFirstUserAuthentication` minimum for user data.
- Logs via `Logger` (os) with `privacy: .private` for user values.

## Offline & resources
- App fully usable offline for local features; network failures shown as calm, designed states.
- Pause timers, `TimelineView`, audio engine and haptic engine when `scenePhase` is not `.active`.
- Low Power Mode → reduce effects (see `studio-graphics-3d`).

## Performance tests (run in CI)
```swift
func testLaunchPerformance() {
    measure(metrics: [XCTApplicationLaunchMetric()]) { XCUIApplication().launch() }
}
func testScrollHitches() {
    let app = XCUIApplication(); app.launch()
    measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric]) {
        app.scrollViews.firstMatch.swipeUp(velocity: .fast)
    }
}
```
Simulator numbers are relative only – track trends between runs, not absolute values.

## Quality checks
- [ ] Build with zero warnings in Swift 6 mode.
- [ ] Core package tests run and pass.
- [ ] Privacy manifest present and matches API use.
- [ ] No secrets: `git grep -nE "(BEGIN (EC|RSA) PRIVATE|api[_-]?key\s*=)"` returns nothing.
- [ ] Offline scenario screenshot exists.
