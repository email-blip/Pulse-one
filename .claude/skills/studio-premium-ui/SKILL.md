---
name: studio-premium-ui
description: Studio standard for premium, non-generic iOS UI and design systems in SwiftUI. Use when starting a new app or screen, defining colors/typography/spacing/shape tokens, choosing a visual direction, or when a screen looks generic, flat, template-like or "AI-made".
---

# Premium UI & Design System

Builds on `swiftui-design-skill` (anti-slop rules, 5-dimension review). This skill adds the studio's design-system contract and checks.

## Activation
- New app, new screen, new reusable component.
- Any change to colors, fonts, spacing, corner radii, materials, icons.
- A screenshot review (`studio-visual-qa`) flagged "generic" or "inconsistent".

## Workflow
1. **Direction first.** Write a one-paragraph design direction in `apps/<App>/DESIGN.md`: mood (3 adjectives), one reference outside software (e.g. "risograph print", "night aquarium"), signature element (the one thing people remember), and what we deliberately avoid.
2. **Tokens before views.** Create `DesignSystem/` in the app with:
   - `Palette` – semantic colors (`surface`, `surfaceRaised`, `ink`, `inkMuted`, `accent`, `accentInk`, `danger`), each with light + dark values in the asset catalog. Views never use raw `Color(red:…)` or `.blue`.
   - `Typography` – a small scale (display, title, headline, body, caption, mono) mapped to `Font.TextStyle` so Dynamic Type scales it. Custom fonts only via `Font.custom(_:size:relativeTo:)`.
   - `Spacing` – 4-pt based scale (`xs 4, s 8, m 12, l 16, xl 24, xxl 32, xxxl 48`).
   - `Shape` – 2–3 corner radii, used consistently (continuous corners).
   - `Motion` – named springs/durations (see `studio-motion`).
3. **Components** consume tokens only. One file per component, with `#Preview` for light, dark and `.accessibilityExtraExtraExtraLarge`.

## Standards
- Signature element present on the main screen (custom shape, shader, illustration, typographic treatment) – not just a tinted list.
- Max 1 accent hue + neutrals; contrast ≥ 4.5:1 for body text, ≥ 3:1 for large text and icons (check in both modes).
- Hierarchy through size/weight/space, not through more colors or boxes. Avoid card-in-card, default grey `List` look without intent, SF Symbol + title + chevron rows everywhere, purple-blue gradients, emoji as icons.
- Touch targets ≥ 44×44 pt. Text never truncated at XXXL Dynamic Type – layouts switch to vertical via `ViewThatFits` or `@Environment(\.dynamicTypeSize)`.
- Respect safe areas; content may extend under bars only intentionally.
- Liquid Glass / new materials only behind `if #available(iOS 26, *)` with a designed fallback.

## Quality checks
- [ ] `DESIGN.md` exists and the screen matches it.
- [ ] `grep -rn "Color(red\|\.font(.system(size" apps/<App>` returns nothing outside `DesignSystem/`.
- [ ] Screenshot matrix reviewed with `studio-visual-qa`; no "generic" finding open.
- [ ] Contrast checked for every text/background token pair in both modes.

## Example (token use)
```swift
struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title).font(Typography.caption).foregroundStyle(Palette.inkMuted)
            Text(value).font(Typography.display).foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
        }
        .padding(Spacing.l)
        .background(Palette.surfaceRaised, in: .rect(cornerRadius: Shape.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
```
