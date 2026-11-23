# Auftrag 04 – Coach Intelligence / Interpretation / Gedächtnis

Du bist Team **04 Intelligence** im PULSE-ONE-Neubau. Zuerst `docs/neubau/auftraege/00-GEMEINSAM.md` lesen und befolgen. Skill: `claude-api` für Modell-IDs und Parameter.

**Deine Dateien:** `PulseCore/Companion/*`, `PulseCore/Intelligence/*`, `PulseCore/Insights/*` (außer `TodayLayout`, `PersonalBaseline`), `Sources/Features/Intelligence/*`, neu `Sources/Features/Coach/Conversation/*`; alt `Features/Companion` (ohne `Services/`), `Features/Nutrition`, `Features/HeartChamber` (entfernen; SwiftData-Modelle bleiben bis zur Migration von 00).

**M1-Lieferung:**
1. Ein Coach **ROOK**: neue Prompts für Check-ins (morgens/mittags/abends) und Gespräch nach Plan §9: Deutung → Richtung → Handlung, ≤3 Sätze, locker/direkt, Fachbro-Ton; streichen: „sag ehrlich, was fehlt“, „gemessen: …“-Aufzählungen, Basislinien-Pflichtsätze. Ohne Grundlage: normal begrüßen, Interaktion anbieten.
2. Ausgabe als `CoachInsight` (Vertrag) mit `EvidenceRef`s, `CoachAction`, `recheckAt`, `NarrationCue`s (Sätze mit Zeitanker für den Verlauf). Strenge Prüfung im Hintergrund bleibt (`ResponseValidator`, `SafetyRules`): keine erfundenen Werte, keine Diagnose-Prozente, Warnzeichen → klarer kurzer Hinweis.
3. Textwächter (Test + CI-Skript): verbotene Routinesätze in Prompts, UI-Texten und Beispielantworten („kein Arzt“, „nicht lesen“, „Basislinie fehlt“, „lernt noch“, „fehlen mir“).
4. „Warum?“-Ansicht: Messwerte, Vergleichszeitraum, Ereignisse, Berechnung, Alternativen, Unsicherheit; Belege springen in den Verlauf (`TimelineState`).
5. Rückmeldungen: „Das passt nicht“, „Ich bin krank“, „Heute nur zehn Minuten“, „Leichtere Variante“, „Warum diese Empfehlung?“ → `revise(…)`, angepasste Handlung (an 05 für Training).
6. Gespräch im Coach-Tab (ein Verlauf, kein zweiter Charakter); Sprechstunde, Expertenrunde, Detektiv, Labor, Nachtforscher, Kleidungsberater aus dem produktiven Pfad entfernen.
7. Zwei Demo-Fälle für Abnahme (Testansicht): positive Entwicklung, auffällige Veränderung mit Abklärungshinweis.

**Abnahme:** Tests für beide Fälle, Korrektur mit Revision, Wächter grün; keine Mehrkosten über den freigegebenen Rahmen (~2,50 $/Monat); PR „[04] ROOK Deutung und Warum“.
**M2/M3:** Nachfassen (Empfehlung/Antwort/Beobachtung getrennt speichern), gezielte Rückfrage, Belastungs-Echo, Gedächtnis.
