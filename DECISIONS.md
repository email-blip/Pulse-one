# Decisions

| Date | Decision | Reason |
|---|---|---|
| 2026-11-20 | PULSE ONE is a new, standalone native app (Swift 6/SwiftUI, RealityKit later) in its own repo. MyBody (Expo, repo MyBotty) stays untouched. Supersedes MyBotty ADR-001 (hybrid). | Owner decision in the project thread 2026-11-20 15:32 UTC: start fresh from the master directive with its own identity. |
| 2026-11-20 | Bundle ID `de.sommerlabs.pulseone`, display name "PULSE ONE". | Owner prefix `de.sommerlabs`; separate identity from MyBody. |
| 2026-11-20 | Build/test/screenshots on GitHub Actions `macos-26` using the ios-studio pipeline (copied, not rebuilt); XcodeGen 2.48.0; Xcode 26.6. | No Mac; free option. Xcode 27 not on the runner yet. |
| 2026-11-20 | Persistence with SwiftData; every value stores unit, timestamp, source, device, model, firmware. No "simulated" source exists. | Directive §10.7, §11; no invented values. |
| 2026-11-20 | Bluetooth permission is requested on the first "Ring suchen" tap, not at launch. Auto-reconnect only when permission already exists. | Directive §10.1; the user sees why before the system prompt. |
| 2026-11-20 | Colmi support is claimed only after the UART service is discovered; capability levels expected → discovered → verified. | Codex review: BLE connected ≠ data works; names alone prove nothing. |
| 2026-11-20 | Dark-only UI until the four design profiles land; screenshot matrix is dark × Dynamic Type. | Cinematic Dark is the base identity (§5.1); Clinical Light is a profile (§7). |
| 2026-11-20 | Live heart-rate measurement stops automatically after 60 s. | Protects the ring battery; keep-alive interval still to be verified on the R03. |
| 2026-11-20 | Heart Chamber heart is procedural (RealityKit `MeshDescriptor` from `HeartGeometry`), no third-party 3D asset. Stylised, not anatomically exact. | No asset licence needed; a licensed anatomical model can replace it later (see docs/ASSETS.md). |
| 2026-11-20 | Heart motion and lub-dub are derived from the BPM value only and are labelled "kein EKG". Live: haptic/sound per beat; stored value: motion only. | Directive §5.3 and honesty rules: no invented ECG signal. |
| 2026-11-20 | Heart sound is synthesised (`HeartSound`), off by default, `.ambient` session (respects silent switch). Haptics on by default. | No audio assets; owner wants sound + haptics, but sound must never surprise. |
| 2026-11-20 | Accessibility audit: `textClipped` issues are ignored; clipping is checked on the xxxl screenshot matrix instead. Contrast issues inside the orb and the 3D heart are ignored. | CI run 3 flagged one-line captions as clipped although the xxxl screenshots show them wrapping completely; rendered visuals carry their own label/value. All other audit types stay blocking. |
| 2026-11-20 | Normalised samples live in SwiftData `StoredSample` with a unique dedup key (source, device, kind, source id). `StoredMeasurement` stays for the current history card until the TODAY screen replaces it. | Idempotent sync and no double counting (GD 3.0 §5) without breaking the working screen. |
| 2026-11-20 | Device registry stored as JSON in Application Support (complete file protection), not SwiftData. | Small, rarely changing list; Codable core type stays testable without SwiftData. |
| 2026-11-20 | Apple Health: read-only, first import limited to 30 days, then incremental per type with HKQueryAnchor; only for the owner profile. Integration stage stops at "synchronisiert"; "Qualität geprüft" needs a real-device check. | GD 3.0 Phase A; Health never reveals denied read access, so an empty import is not proof of access. |
