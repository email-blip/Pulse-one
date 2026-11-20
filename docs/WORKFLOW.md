# Studio Workflow

Iterative loop. A step is only done when its check passes.

| # | Step | Agent | Output | Check |
|---|---|---|---|---|
| 1 | Produktidee | `product` | `apps/<App>/PRODUCT.md` | Owner agrees with brief |
| 2 | UX-Konzept | `ui-designer` | screen list + states in `DESIGN.md` | every key moment mapped |
| 3 | Designsystem | `ui-designer` | `DesignSystem/` tokens | `studio-premium-ui` checks |
| 4 | Implementierung | `swift-engineer`, `av-experience` | code + Core tests | tests written with the code |
| 5 | Build | CI | green build, zero Swift warnings | `ios-ci.yml` |
| 6 | Simulator | CI | UI tests, accessibility audit, perf metrics | all green |
| 7 | Screenshot-Analyse | `ui-designer` | findings table (rubric) | all scores ≥ 4 |
| 8 | Korrektur | `swift-engineer` | fixes | back to 5 |
| 9 | Tests | `test-engineer` | coverage of new logic, flaky check | green twice |
| 10 | Review | `reviewer` | approve / changes | Definition of Done in CLAUDE.md |
| 11 | TestFlight | `release` | build on owner's iPhone | **owner approval** |

## Without a Mac – the loop in practice
1. Claude (cloud) edits code on a feature branch and pushes.
2. GitHub Actions (`macos-26`) builds, runs all tests, captures screenshots on 3 iPhones.
3. Screenshots land on `ci-screenshots/<branch>`; Claude fetches and reviews them; logs via the GitHub MCP job-log tools.
4. Repeat until green and rubric ≥ 4, then open/merge the PR.

## Saving CI minutes (private repo)
- Workflow runs only when `apps/`, `scripts/` or the workflow change; docs-only commits are free.
- `cancel-in-progress` kills superseded runs.
- Push batched changes, not every small edit. Use `workflow_dispatch` for a deliberate run.
- Check remaining minutes in GitHub → Settings → Billing before long sessions.

## Limits to keep in mind
- Haptics and real audio cannot be experienced in the simulator → verified by unit tests (pattern data, sync) and finally on the owner's iPhone via TestFlight.
- Simulator performance numbers are relative only.
