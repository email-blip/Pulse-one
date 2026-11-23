# Auftrag 05 – Sprache / Training / Timer / Mitteilungen

Du bist Team **05 Sprache/Training** im PULSE-ONE-Neubau. Zuerst `docs/neubau/auftraege/00-GEMEINSAM.md` lesen und befolgen. Skills: `studio-sound`, `studio-haptics`, `studio-motion`.

**Deine Dateien:** neu `Sources/Audio/*`, neu `Sources/Features/Training/*`, `Sources/Features/Coach/*` (außer `Conversation/`), `Sources/Features/Companion/Services/*`, `App/NotificationDelegate.swift`, `PulseCore/Activation/*`, `PulseCore/Coach/*`; Live-Activity-Ziel später über 00 (`project.yml`).

**M1-Lieferung:**
1. **Audio-Koordinator** (genau einer): eine Warteschlange für Begrüßung, Deutung und Trainingsansagen; AVSpeechSynthesizer mit bester verfügbarer deutscher Stimme (Premium/Enhanced, wenn installiert); Tempo abgestimmt; Stopp/Pause/Weiter; Unterbrechung durch Anruf, Kopfhörer-Verlust → anhalten, sensible Inhalte nicht über Lautsprecher fortsetzen; keine Überlappung; Begrüßung nicht bei jedem Tabwechsel. `RookPresence` (speaking/listening) setzen. Aussprachetests für Zahlen, „HRV“, Uhrzeiten, Übungsnamen.
2. **Trainingssession** auf `WorkoutSession` (Vertrag): großer Übungsname, Bewegung (vorerst nativ animierte Figur/Platzhalter von 02, später 3D), Timer aus Zeitstempeln, nächste Phase, Start/Pause/Fortsetzen/Überspringen/Beenden, Ansagen aus `AnnouncementState` (Pause/Überspringen verwerfen veraltete Ansagen), Haptik/Sounds von 02, `catchUp` nach Sperren, Phasenende als lokale Mitteilung.
3. Coach-Tab: Tagesplan aus der bestehenden Coach-Logik im neuen Design, „Einheit starten“ führt in die Session; Pläne berücksichtigen Ziele, Niveau, Ausrüstung, Zeit, Einschränkungen und Korrekturen von 04.
4. Nach der Einheit: Zusammenfassung, Anstrengung 1–10, gemessene Reaktion getrennt von Durchführung, Eintrag im Tagesverlauf (Spur `training`).
5. Mitteilungen: konkrete Aktion, keine Mahnung für Erledigtes, Ruhezeiten/„heute nicht“, kein identischer Push ohne neuen Stand.

**Abnahme:** Tests Pause → keine Ansage; Sperren 2 Min. → richtige Restzeit; Abschluss erscheint im Verlauf; PR „[05] Audio-Koordinator und Training“.
**M2:** Live Activity, AlarmKit wo verfügbar, Spracheingabe (iOS-18-Pfad, Mikrofon nur bewusst), gesprochener Rückblick mit `NarrationCue` → Cursor (mit 03).
