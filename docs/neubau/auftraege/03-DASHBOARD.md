# Auftrag 03 – Dashboard / Zeitspuren / Diagramme

Du bist Team **03 Dashboard** im PULSE-ONE-Neubau. Zuerst `docs/neubau/auftraege/00-GEMEINSAM.md` lesen und befolgen. Skills: `swiftui-expert-skill`, `studio-motion`, `studio-visual-qa`.

**Deine Dateien:** `Sources/App/MainTabView.swift`, neu `Sources/Features/Dashboard/*`, neu `Sources/Features/Timeline/*`, `PulseCore/Insights/TodayLayout.swift` (wird durch `DashboardLayout` abgelöst); alt `Features/Today`, `Features/Health`, `Features/Scores` (entfernen, sobald ersetzt).

**M1-Lieferung:**
1. App-Shell: drei Tabs **Dashboard · Verlauf · Coach** (Coach-Tab-Inhalt liefern 04/05; du stellst den Platz bereit), Profil/Ring/Status oben rechts diskret.
2. Dashboard nach Referenz (Plan §4): ROOK-Bereich (Inhalt aus `CoachInsight` von 04: Schlagzeile, 2–3 Sätze, Vorlesen/Stopp über den Audio-Koordinator von 05, „Warum?“, Primärhandlung), darunter Kacheln aus `DashboardLayout`, dann Schlafvorschau.
3. Kacheln: Wert/letzter gültiger Wert mit Bezugszeit, Mini-Verlauf aus echten Punkten, Antippen → Verlauf mit Zoom-Übergang. Editor: lang drücken + ziehen mit sichtbarem Einfügeplatz, Größen, ein/aus, barrierefreie Alternative (Nach oben/unten), pro Profil gespeichert.
4. Verlauf: Tag/Woche/Monat/3 Monate/Jahr; im Tag Pan + Pinch-Zoom, gemeinsamer Cursor über alle Spuren (`TimelineState`), Auswahl des nächsten Originalpunkts mit Originalzeit, Quelle auf Nachfrage; Lücken sichtbar, nie Null; Aggregation kenntlich. Spuren: Puls, HRV, SpO₂, Stress, Schlafphasen, Bewegung, Training, Coach-Markierungen. Swift Charts (ChartProxy, `chartXSelection`, `chartScrollPosition`).
5. Hypnogramm: Stufen Wach/REM/Leicht/Tief + Unbekannt gesondert, echte Zeiten, Abschnitt antippen → Phase, Beginn, Ende, Dauer; dieselbe Achse wie Puls/HRV/SpO₂ darunter.
6. Neue Messung landet animiert an ihrer echten Zeitposition; historische Daten nicht als neu inszenieren.

Daten von 01 (`PulseCore/Timeline/*`); bis zu deren Merge mit den Szenario-Daten aus den Verträgen arbeiten, nicht mit eigenen Fantasiedaten.
**Abnahme:** UI-Test Kachel verschieben → App neu starten → Reihenfolge bleibt; Cursor zeigt Originalzeit; Lücke wählt nichts; Screenshots 3 Größen/XXXL/Reduce Motion; flüssiges Scrubbing mit Jahresdaten (Messung durch 06). PR „[03] Dashboard und Zeitspuren“.
