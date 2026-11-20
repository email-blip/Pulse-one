# Vendored components (pinned)

Copied verbatim into `.claude/skills/` (only `agents/openai.yaml` removed – not used by Claude Code). Never auto-update. To update: re-run the audit (license, diff review, scripts, network calls), bump the commit here, record in `DECISIONS.md`.

| Skill folder | Source | Version | Commit | License | Audited | Notes |
|---|---|---|---|---|---|---|
| `swiftui-expert-skill` | github.com/AvdLee/SwiftUI-Agent-Skill (`skills/swiftui-expert-skill`) | 5.3.0 | 62bd760 | MIT | 2026-11-20 | Primary SwiftUI knowledge. Contains local Python scripts for Instruments traces (no network calls); macOS only. |
| `swift-testing-pro` | github.com/twostraws/Swift-Testing-Agent-Skill | 1.0.0 | 2d6bba1 | MIT | 2026-11-20 | Text only. |
| `swiftui-design-skill` | github.com/wholiver/swiftui-design-skill | 1.0.0 | 2c82638 | MIT | 2026-11-20 | Text only. Base for `studio-premium-ui`. |
| `swiftui-pro` | github.com/twostraws/SwiftUI-Agent-Skill | 2.0.0 | f2920b6 | MIT | 2026-11-20 | Text only. Used by the `reviewer` agent; overlaps with `swiftui-expert-skill`. |

## Deferred (needs a Mac)
| Component | Version | License | Notes |
|---|---|---|---|
| MobileBuildMCP (formerly cameroncooke/XcodeBuildMCP, now getsentry/MobileBuildMCP) | npm `mobilebuildmcp@2.7.1` | MIT | Sentry error telemetry – disable per its privacy docs. Requires macOS 14.5+, Xcode 16+. |

## Rejected
| Component | Reason |
|---|---|
| CharlesWiltgen/Axiom 27.8.1 (MIT) | 289 skills + 44 agents + hooks on every tool call; heavy overlap; tools need macOS. Revisit single tools (axbuild, xcui) once a Mac exists. |
| dpearson2699/swift-ios-skills 3.9.1 | PolyForm Perimeter license (not open source, restricts competing use). |
| cristianoaredes/build-ios-apps | No LICENSE file; repackaging of openai/plugins + rudrankriyam/app-store-connect-cli-skills; inactive since 2026-04. Evaluate the upstream asc skills directly for release work. |
