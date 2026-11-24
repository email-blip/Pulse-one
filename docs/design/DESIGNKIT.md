# DesignKit – Kurzanleitung für Teams 03–05

Besitzer: Team 02. Code: `apps/PulseOne/Sources/DesignKit/`. Vorschau: UI-Test-Szenario `designKit` (`-uiTesting YES -uiTestScenario designKit`), Screenshots `designKit__dark__default|xxxl[__reduced]`.

Neue Bildschirme nutzen nur DesignKit. `Sources/DesignSystem/*` (Palette, Typography, Card, …) ist Altbestand: `Palette` liest schon die neuen Werte, wird aber entfernt, sobald 03–05 umgestellt haben.

## Tokens

| Bereich | Typ | Inhalt |
|---|---|---|
| Farben | `DKColor` | Marke fest (`obsidian`, `bioCyan`, `neuralViolet`, `pulseCoral`, `iceWhite`), Flächen `background` < `surface` (Karten, Kacheln) < `surfaceRaised` (Knöpfe) < `surfaceSelected`, Linien `hairline`/`lineStrong` (nur Deko), Text `textPrimary`/`textSecondary`/`textTertiary`, `onAccent`, Rollen `accent`/`coach`/`alert` |
| Messarten | `MetricStyle.of(kind)` | Farbe + SF Symbol + deutscher Kurzname je `SampleKind`. Immer Symbol oder Name mit anzeigen, Farbe nie allein |
| Schlafphasen | `SleepPhaseStyle.of(phase)`, `SleepPhaseFill`, `SleepPhaseLegend` | Farbe + Muster (Wach gestreift, REM gepunktet, Leicht/Tief voll, Unbekannt gestrichelter Rand) + Zeile `level` (0 Wach oben … 3 Tief, 4 Unbekannt) |
| Schrift | `DKFont` | `headline` (largeTitle bold), `title`, `section`, `body`, `bodyEmphasis`, `label`, `unit`, `caption` (immer groß + `DKTracking.caption`), `wordmark`, `number(size:)` = SF Pro Expanded, `monospacedDigit`, Größe aus `@ScaledMetric(relativeTo: .largeTitle)` |
| Abstände | `DKSpace`, `DKRadius`, `DKSize` | 4-pt-Raster, Seitenrand `DKSpace.page` = 20, Karten-Radius 24, Touch ≥ 44 |

Kontrast: `python3 scripts/assets/check-contrast.py` (Text ≥ 4,5:1, Grafik ≥ 3:1 auf allen Flächen; aktuell 65 Paare OK).

## Komponenten

| Komponente | Zweck |
|---|---|
| `RookOrb(presence:size:)` | ROOK-Zeichen, liest nur `RookPresence`; später durch Rive ersetzbar |
| `RookHeader(presence:onReadAloud:isSpeaking:)` | Orb + „ROOK“ + „Vorlesen“/„Stopp“ |
| `CoachHeadline(headline:interpretation:)` | Schlagzeile + 1–2 Sätze |
| `DKPrimaryButtonStyle(fullWidth:)`, `DKSecondaryButtonStyle`, `DKPillButtonStyle`, `DKTextButtonStyle`, `TrailingIconLabelStyle` | „Meine Einheit starten ↗“, „Warum?“, „Vorlesen“, „Kacheln anordnen“ |
| `MetricTile(kind:value:unit:reference:size:) { Sparkline(...) }` | Kachel klein/breit/groß nach `DashboardTileSize`; `value: nil` zeigt „–“ |
| `Sparkline(values:tint:)` | Mini-Verlauf, `nil` = Lücke, wird nie überbrückt |
| `DKCard(isCoach:)`, `DKSectionHeader(title:actionTitle:…)`, `DKChip`, `DKReference`, `FlowLayout`, `.dkPageBackground()` | Karte, Abschnittskopf, Auswahlchip, „NACHT · 07:00“, umbrechende Reihe, Seitenhintergrund |

Große Schrift: Komponenten stapeln sich selbst (`ViewThatFits`); Kachelraster bei `isAccessibilitySize` einspaltig.

## Bewegung, Haptik, Klang

Jede animierte Änderung wählt ein `MotionEvent` und nutzt `.dkMotion(event, value:)` (Animation + Haptik aus einer Zustandsänderung) bzw. `event.resolvedTransition(reduceMotion:)`. Keine eigenen Dauern/Kurven.

| Ereignis | Animation | Reduce Motion | Haptik | Klang |
|---|---|---|---|---|
| `measurementLands` | Feder 0,55 s, Bounce 0,12; Zahl rollt, Punkt kommt von rechts | Überblendung 0,2 s | – | – |
| `rangeChange` | Feder 0,45 s, kein Bounce | Überblendung 0,2 s | selection | – |
| `pointSelect` | Feder 0,18 s | sofort | selection | – |
| `tileSwap` | Feder 0,38 s, Bounce 0,18 | Überblendung 0,2 s | impact leicht | – |
| `workoutStart` | Feder 0,6 s, Skalierung 0,92 → 1 | Überblendung 0,25 s | start | `po-start` |
| `phaseEnd` | Feder 0,42 s, alt links raus, neu rechts rein | Überblendung 0,2 s | impact weich | `po-phase` |
| `insightToEvidence` | Feder 0,4 s, von unten | Überblendung 0,2 s | impact weich, schwach | – |
| `press` | Feder 0,22 s, Skalierung 0,97 | nur Abdunkeln | – | – |

Abschluss einer Einheit: `DKSound.complete` + `.success`-Haptik (Team 05). Klänge über `DKSoundPlayer.shared.play(_:)` (`.ambient`, Stummschalter wird respektiert; Team 05 darf die Audio-Session für Sprache übernehmen). Daueranimation nur am Orb, solange ROOK zuhört/denkt/spricht; nie unter Reduce Motion, nie in Screenshots (`freezeAnimations`).
