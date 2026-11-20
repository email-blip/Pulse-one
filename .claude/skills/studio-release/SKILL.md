---
name: studio-release
description: Studio standard for code signing, TestFlight and App Store Connect without a Mac - API keys as GitHub Secrets, versioning, upload job, review checklist, and the approval gates. Use when preparing a TestFlight build, setting up signing, bumping versions, or preparing App Store metadata.
---

# Release & TestFlight

## Hard rules
- **Owner approval required** in the current thread before: any upload to App Store Connect, adding external testers, submitting for review, anything that costs money.
- Internal TestFlight upload counts as non-public but still needs the owner's "go" the first time per app; afterwards per the owner's standing approval recorded in `DECISIONS.md`.
- Keys never leave GitHub Secrets. Never print them in logs (`set +x`, masked secrets).

## One-time setup (owner + Claude)
1. Apple Developer Program active (owner).
2. App Store Connect → Users and Access → Integrations → App Store Connect API → create a key with role "App Manager" (owner, guided step by step). Store as GitHub Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (base64).
3. Bundle ID `de.sommerlabs.<app>` registered; app record created in App Store Connect (owner, guided).
4. Signing: automatic signing with the API key (`xcodebuild -allowProvisioningUpdates -authenticationKeyPath … -authenticationKeyID … -authenticationKeyIssuerID …`) on the CI runner. Alternative: Xcode Cloud (25 compute h/month included in the membership).

## Per release
- Version: `MARKETING_VERSION` semantic (1.2.0); `CURRENT_PROJECT_VERSION` = CI run number.
- CI job `testflight` (manual `workflow_dispatch` only): archive → export IPA (`method: app-store-connect`) → upload with `xcrun altool --upload-app` using the API key → post build number in the PR.
- Release notes "Was ist neu" in German, ≤ 4 bullets, no medical claims for health apps.

## App Store readiness checklist
- [ ] Privacy manifest + App Privacy answers consistent.
- [ ] Encryption export: `ITSAppUsesNonExemptEncryption = NO` if only Apple standard crypto.
- [ ] All permission strings (`NS…UsageDescription`) in German, specific, honest.
- [ ] Screenshots from the CI matrix in required sizes (6.9" and 6.5" iPhone).
- [ ] App icon 1024 px, no alpha; launch screen matches design.
- [ ] Sign in/demo account notes for review if needed.
- [ ] Health apps: no diagnosis wording (App Review 1.4.1, 5.1.3).
