# Testbericht M1 „Durchstich“ (Team 06)

## Stand 2026-11-23 – Prüfgerüst, vor der Integration

**Ergebnis:** Das Prüfgerüst steht. Die neuen Bildschirme (02–05) sind noch nicht auf `main`, deshalb endet der Durchstich-Test im CI planmäßig mit „nicht integriert“ beim ersten Schritt. Das Video zeigt bis dahin nur den Start.

Geliefert (Stufe „implementiert“, nach grünem CI-Lauf „gebaut“):
- Szenario `neubauM1` (ein Tag + Nacht, Puls alle 5 Min., HRV/SpO₂ nachts, Stress/Schritte tagsüber, Lauf 17:00, Lücke 13:00–14:10) und `neubauM1Year` (365 Tage). Testansicht-Banner für beide.
- `DurchstichTests`: 15 Schritte, Bild je Schritt, Bericht `durchstich-report.md`.
- Video im CI: `scripts/qa/run-durchstich.sh` (simctl recordVideo, h264), Artefakt `durchstich-video-<Lauf>`.
- Screenshot-Matrix der 8 M1-Ansichten (Standard + XXXL, Reduce Motion auf drei) auf allen drei Geräten.
- Barrierefreiheits-Audit auf 7 neuen Ansichten.
- Performance: Scrubbing/Pannen mit Jahresdaten, CPU im Leerlauf; Werte im Lauf-Bericht.

**Offen / abhängig:**
1. Bildschirme mit den Kennungen aus `PRUEFLISTE.md` (03, 04, 05).
2. Schlafsegmente im Szenario (01, sobald das Modell existiert) – sonst bleibt Schritt 8 leer.
3. Korrektur „Ich bin krank“ muss im Testszenario lokal antworten (04), sonst hängt Schritt 10 am Netz.
4. Strikter Modus: 00 setzt `TEST_RUNNER_PULSE_M1_STRICT: "1"` im Integrations-PR; dann ist jeder fehlende Bildschirm rot.
5. 60 fps nur im Simulator messbar; am iPhone Sichtprüfung durch Johannes.

## Stand 2026-11-24 – Abnahme-PR

- Alle M1-PRs auf main (114e0dd). Strikter Modus an (`TEST_RUNNER_PULSE_M1_STRICT: "1"`, freigegeben von 00): jeder fehlende M1-Bildschirm ist rot.
- Neuer Schritt 16 „Sprachgespräch mit ROOK“ im Video (Wunsch von Johannes): Status Zuhören → Denken → Sprechen, beide Äußerungen im Transkript, zwei ROOK-Antworten, Unterbrechung, Gespräch beenden. Im Testmodus hält die App „Ich denke nach …“ 1,5 s, weil die lokale Testantwort sonst in Millisekunden kommt und die Phase weder im Video noch im Test zu sehen wäre (kleiner Patch an 05s `VoiceConversation`).

## Integrationslauf

_Wird nach dem Integrationslauf von 00 ergänzt: Lauf-Link, Video, Schritte ✓/✗, Performance-Werte, Audit-Funde._
