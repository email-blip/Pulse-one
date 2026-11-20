---
name: studio-visual-qa
description: Automated visual quality assurance from CI simulator screenshots - capture matrix (device sizes, light/dark, Dynamic Type, Reduce Motion), how to fetch screenshots from the ci-screenshots branch, and a structured review rubric. Use after every UI change, before calling a UI task done, or when asked to check how the app looks.
---

# Visual QA (no Mac required)

## Activation
- Any change under `apps/*/` that affects views, assets, design tokens.
- Before marking a UI task done (Definition of Done step 3).

## How screenshots are produced
1. CI (`.github/workflows/ios-ci.yml`) runs UI test class `ScreenshotTests` on 3 simulators (smallest current iPhone, standard Pro, Pro Max – resolved by `scripts/pick-simulators.sh`).
2. Each test launches the app with `-uiTestScenario <name>`, `-appearance light|dark`, `-dynamicType default|xxxl`, `-reduceMotion YES|NO` and attaches a full-screen screenshot named `<scenario>__<appearance>__<type>.png` (`XCTAttachment`, `lifetime = .keepAlways`).
3. `scripts/export-screenshots.sh` extracts them from the `.xcresult` and the workflow pushes them to branch `ci-screenshots/<source-branch>` under `<device>/`, plus `index.md` listing commit SHA and run URL.

## How to review (Claude in the cloud)
```bash
git fetch origin "ci-screenshots/$(git branch --show-current)"
git worktree add /tmp/shots FETCH_HEAD   # then Read the PNGs
```
Look at every image (Read tool shows images). Compare against `apps/<App>/DESIGN.md`.

## Rubric (score 1–5 each, fix everything < 4)
1. **Distinctiveness** – signature element visible; would not be mistaken for a template.
2. **Hierarchy** – one clear focal point; scan order obvious.
3. **Typography** – scale consistent; no truncation/clipping at XXXL; line lengths sane.
4. **Color & contrast** – tokens only; dark mode designed, not inverted; contrast OK.
5. **Spacing & alignment** – on the 4-pt grid; consistent margins; safe areas respected.
6. **States** – empty, loading, error, offline scenarios exist and look intentional.
7. **Device fit** – nothing cut off on the smallest device; no awkward emptiness on Pro Max.

Write findings to the PR as a table: screenshot, dimension, score, issue, fix. Re-run CI after fixes and re-review only the changed cells.

## Quality checks
- [ ] All matrix cells present (missing image = failure, not a pass).
- [ ] Every finding < 4 fixed or explicitly accepted by the owner.
- [ ] Accessibility audit test (`performAccessibilityAudit`) green in the same run.
