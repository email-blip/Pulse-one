# PULSE ONE – Integration Wellen 1–4 (gemeinsamer Build)

Integrations-Lead: Thread „PULSE ONE in Wellen ausbauen“ (Welle 1). Stand 2026-11-21 06:10Z.
Ziel: alle Wellen auf `main`, danach **ein** TestFlight-Build. Nur der Lead startet TestFlight.

## Navigation (DESIGN-SYSTEM-5.0 §2)
Tab-Leiste: **Heute · Gesundheit · Analyse · Coach · Ernährung**.
Profil-Knopf oben rechts in jedem Tab → Sheet mit Profil, Geräte, Ring messen, Diagnose, Einstellungen.
Ring messen zusätzlich als Karte auf „Heute“.

| Tab | Root-View (Datei) | Eigentümer |
|---|---|---|
| Heute | `Features/Today/TodayScreen.swift` | W1 |
| Gesundheit | `Features/Health/HealthScreen.swift` | W1 |
| Analyse | `Features/Intelligence/IntelligenceHubView.swift` → `IntelligenceHubView()`; dazu `IntelligenceSettingsView()` im Profil-Sheet | W2 |
| Coach | `Features/Coach/CoachScreen.swift` → `CoachScreen()` | W3 |
| Ernährung | `Features/Nutrition/NutritionScreen.swift` → `NutritionScreen()` | W4 |

Optional je Modul eine Karte für „Heute“: `CoachTodayCard()`, `NutritionTodayCard()`, `EveningNoteCard()` (W2) (ohne Parameter, eigene Datei im Modulordner). Der Lead bindet sie auf Heute ein, sobald sie auf `main` sind.

Szenario-Routing (`-uiTestScenario intelligence|coach|nutrition` → Tab auswählen) macht der Lead in `MainTabView`, nicht in RootView. Der Lead legt die drei Root-Views zuerst als Platzhalter an (PR „Grundgerüst“). Teams **ersetzen nur ihre Datei** und fügen eigene Dateien in ihrem Ordner hinzu.

## Vertrag je Modul
- Root-View: `struct <Name>Screen: View` mit `init()` ohne Parameter. Eigener `NavigationStack` darin. Der Tab-Container setzt Titel/Symbol, nicht das Modul.
- Ordner App: `apps/PulseOne/Sources/Features/<Intelligence|Coach|Nutrition>/`
- Ordner Kern (Logik + Swift-Testing): `apps/PulseOne/Packages/PulseCore/Sources/PulseCore/<Intelligence|Coach|Nutrition>/`, Tests `Tests/PulseCoreTests/<Modul>Tests.swift`.
- Umgebung, die jedes Modul lesen darf: `@Environment(SourcesStore.self)`, `@Environment(ProfileStore.self)`, `@Environment(\.modelContext)`, `@Environment(\.reduceMotionEffective)`, `@Environment(\.freezeAnimations)`.
- Daten lesen: `SampleReader(context:)` (App, `Sources/Data/SampleReader.swift`):
  `func samples(_ kinds: Set<SampleKind>, since: Date, profileID: UUID?) -> [HealthSample]` (nur `valid`/`plausible`).
  Tageswerte: `DailySeries.build(...)`, Normalband: `PersonalBaseline.compute(...)`, Verläufe: `TrendSeries` (PulseCore, kommt mit Welle 1).
- Eigene SwiftData-Modelle in `Sources/Persistence/<Modul>*.swift` plus `enum <Modul>Persistence { static let models: [any PersistentModel.Type] }`. In `Sources/Persistence/PulseSchema.swift` steht `static let models = core + …`: dort **eine Zeile** `+ <Modul>Persistence.models` ergänzen (einzige erlaubte Änderung außerhalb des Modulordners). Nur optionale Felder oder Defaults (leichte Migration).
- Profil: `ProfileStore.profile` (`displayName`, `birthYear`, `sex`, `heightCm`, `weightKg`), nur lesen. Sportarten/Trainingstage führt der Coach selbst (`CoachPreferences`).
- Normalband (PulseCore `Insights/PersonalBaseline.swift`):
  `PersonalBaseline.status(for days: [DailyValue], kind:, before day: Date, calendar:, windowDays: Int = 28) -> BaselineStatus`
  `enum BaselineStatus { case forming(daysAvailable: Int, daysNeeded: Int); case ready(PersonalBaseline) }`
  `PersonalBaseline { kind, median, lower (p25), upper (p75), dayCount; func position(of: Double) -> BandPosition }`, `enum BandPosition { below, within, above }` mit `description` („im üblichen Bereich“ usw.). Mindestens 7 Tage, Tage vor `day`.
- Design: nur `Palette`, `Typography`, `Spacing`, `Radius`, `Card`, `PrimaryButtonStyle`, `SecondaryButtonStyle` und die Komponenten in `Sources/DesignSystem/Components.swift` (`ScreenBackground`, `MetricCard`, `EmptyState`, `SectionHeader`, `TestBanner`, `StatementBadge` für die Aussagetypen §6). Keine Rohfarben, keine Ampelfarben.
- Testansicht: jedes Modul liefert ein Szenario (`intelligence`, `coach`, `nutrition`), Start mit `-uiTesting YES -uiTestScenario <name>`. Im Szenario-Modus `TestBanner()` oben zeigen. Root bekommt `.accessibilityIdentifier("screen.<szenario>")` **nur wenn** `LaunchOptions.current.scenario == "<szenario>"`, sonst keinen.
  Szenario in `UITests/ScreenshotTests.swift` (`scenarios`) und ein `audit(scenario:)` in `AccessibilityTests.swift` ergänzen. Testdaten nur im In-Memory-Store über eine eigene `static func insert…(into:)` im Modulordner; der Lead ruft sie in `TestScenario.insertSampleHistory` auf.
- Geheimnisse: Claude-API-Schlüssel nur im Schlüsselbund (Keychain), Eingabe in der App, nie im Repo/Log.
- Netzwerk: nur Claude-API (W2) und Open Food Facts/USDA (W4), jeweils mit sichtbarer Vorschau, was gesendet wird.
- Texte Deutsch, beschreibend, keine Diagnosen, keine Prognosen. Aussagetypen sichtbar (gemessen / berechnet / Deutung von Claude / Vorschlag).

## Nicht anfassen (nur Lead)
`project.yml` (Kamera-Text für Barcode trägt der Lead ein; weitere Info.plist-Texte an den Lead schicken), `PulseOneApp.swift`, `App/MainTabView.swift`, `TestScenario.swift` (außer dem einen Aufruf), Workflows, `MARKETING_VERSION`. Brauchst du dort etwas: Nachricht an den Lead.

## Ablauf
1. Lead merged „Grundgerüst“ (Tabs, Platzhalter, PulseSchema, ProfileStore, SampleReader, Components). Ziel: ~07:30Z. Bis dahin Kern-Logik + Tests in PulseCore bauen (keine Abhängigkeit).
2. Danach: Branch von `main`, eigene PRs, CI grün, selbst squash-mergen. Vor jedem Push `git fetch origin main && git merge origin/main`.
3. Keine TestFlight-Läufe. Wenn fertig: Nachricht an den Lead mit PR-Nummer, Commit, CI-Link, Testanleitung (3–6 Schritte für Johannes).
4. Lead startet einen Build und schreibt die gemeinsame Testanleitung.
