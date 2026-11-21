# Begleiter – Aktivierung (Konzept und Bauplan)

Stand 2026-11-21. Auftrag Johannes: morgens nach dem Wecken, mittags und abends kurze Aktivierungs-Einheiten mit eigenem Körpergewicht (vor allem Liegestütze, Klimmzüge, Unterarmstütz), genaue Vorgabe (Wiederholungen, Zeit, Runden), morgens 5–15 Minuten, sonst ~5 Minuten, angepasst an die Tagesaktivität; bei wenig Bewegung erinnert der Begleiter an kurze Übungen.
Vertrag: `PulseCore/Activation/ActivationModels.swift` (nur ergänzen, nicht umbenennen).

## 1. Kreativ- und Expertenrunde (Ergebnis)

| Rolle | Beitrag |
|---|---|
| Calisthenics-Trainerin | Leitern statt fester Übungen: Liegestütz Wand → schräg → Knie → voll → eng → Füße erhöht; Zug Tisch-Rudern → Hängen → Schulterblatt-Zug → langsam ablassen → Klimmzug; Rumpf Knie-Stütz → Unterarmstütz → Stütz mit Schultertippen → Hohlkörper. Morgens Zirkel, Satzziel ≈ 50–60 % des besten sauberen Satzes („Grease the Groove“): täglich machbar, nie bis zum Versagen. |
| Sportmedizin | Morgens 1 Minute Aufwärmen Pflicht (Gelenke, Puls). Kurze Nacht → 70 % Umfang. Auffälliges Muster oder Muster-Stufe ≥ 2 → nur sanft (Mobilität, Atmung). Gesundheitsfrage im Coach mit „ja“ → nur Stufe ≤ 2. Eingeschränkte Körperregion → Übung ausgeschlossen. Keine Diagnosen, keine Versprechen. |
| Trainingswissenschaft | Doppelte Progression: Ziel geschafft + „passend/zu leicht“ → bester Satz +1 (+2 bei „zu leicht“), Halten +5 s; verfehlt oder „zu schwer“ → −1. Ab Leiter-Schwelle (z. B. 15 saubere Liegestütze) nächste Stufe mit 60 % als Start. Einheiten zählen als leichte Last in der Coach-Woche (sRPE ≈ 3 × Minuten). |
| Verhaltensdesign | Konkrete Vorgabe in der Mitteilung („3 Runden: 12 Liegestütze, 4 Klimmzüge, 40 s Stütz – 6 Minuten“), ein Tipp zum Start, sichtbarer Fortschritt („Bester Satz Liegestütze: 18, vor 2 Wochen 14“). Kein Schuldton beim Auslassen. |
| UX | Geführte Einheit: große Zahl, ein Knopf „Geschafft“, Wiederholungen anpassbar, Halte-Timer und Pausen-Countdown, am Ende drei Knöpfe (Zu leicht / Passend / Zu schwer). Einstieg aus dem Guten-Morgen-Ablauf, der Begleiter-Seite und der Heute-Karte. |
| Sound & Haptik | Kurze Haptik bei Rundenwechsel und Ende des Countdowns; Ansagen optional über die vorhandene Sprachausgabe. |
| Daten | Aktivität aus stündlichen Schritten (Ring + Apple Health über den vorhandenen Reader), Regel wie im Coach: < 250 Schritte in einer beendeten Wachstunde = ruhig. Ab 2 ruhigen Stunden: Bewegungs-Snack (2–3 Minuten). |
| iOS-Plattform | Eine App kann Schritte im Hintergrund nicht laufend prüfen. Stufe 1: Erinnerung beim Öffnen der App und feste Einheiten-Mitteilungen mit konkreter Vorgabe. Stufe 2 (später, Lead): HealthKit-Hintergrundzustellung für Schritte (stündlich) weckt die App, die dann bei Ruhe eine Mitteilung plant – braucht Entitlement in `project.yml`. |
| Datenschutz | Alles lokal. Keine Übungsdaten aus dem Netz zur Laufzeit. |

## 2. Übungsquellen und Lizenz
- Eigene deutsche Texte im Format `Exercise` des Coach (Datei `Activation/ActivationLibrary.swift`), Herkunft „PULSE ONE (eigener Text)“.
- Coach-Bibliothek wird mitgenutzt (`ExerciseLibrary.exercise(id)`), nicht kopiert.
- free-exercise-db (yuhonas, Unlicense = gemeinfrei, abgeleitet aus exercises.json): als Nachschlagewerk geeignet, Texte englisch → nicht 1:1 übernommen.
- wger: Code AGPL, Übungsdaten Creative Commons je Eintrag (meist CC-BY-SA, Namensnennung + Weitergabe unter gleichen Bedingungen) → derzeit nicht eingebaut.

## 3. Regeln (Kern, reine Funktionen)
- Zeitbudget: morgens `morningMinutes` (5–15), mittags/abends `shortMinutes` (3–10), Snack 2–3 Minuten.
- Fokus rotiert pro Tag; Liegestütz und Unterarmstütz jeden Morgen, Zug immer wenn möglich (Stange → Klimmzug-Leiter, sonst Tisch-Rudern bzw. Band-Rudern).
- Mittags eher Beine + Kreislauf, abends eher Rumpf + Zug + Mobilität. Schon heute viel gemacht → Abend kürzer.
- Bereitschaft: `full` (erholt/normal), `reduced` (kurze Nacht, zu wenig Daten → 70–90 %), `gentle` (auffälliges Muster, Muster-Stufe ≥ 2).

## 4. Teams und Dateien
| Team | Inhalt | Dateien |
|---|---|---|
| K Kern | `ActivationLibrary`, `ActivationPlanner.plan`, `ActivationProgression.update`, `ActivityCheck.status`, Texte/Zusammenfassung | `PulseCore/Activation/*.swift` (ohne Models), Tests `ActivationTests.swift` |
| A App | Speicher (`ActivationRecords.swift`), `ActivationStore`, geführte Einheit, Einstellungen, Mitteilungen (Präfix `companion.activation.`), Einstiege (Begleiter-Seite, Guten-Morgen, Heute-Karte), Testszenario `companionActivation`, UI-Test | `Sources/Features/Companion/Activation/*`, `Sources/Persistence/ActivationRecords.swift`, `UITests/ActivationTests.swift` |
| Lead | Vertrag, Einhängepunkte (`CompanionPersistence.models`, Szenario, Screenshot-/Audit-Liste), Review, CI, PR; Abstimmung mit „Gesamte App professionell verzahnen“ (Coach-Wochenlast, ein gemeinsamer Bewegungs-Snack) | — |
