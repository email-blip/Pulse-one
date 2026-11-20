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
