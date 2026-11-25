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

## Integrationslauf (Lauf 220, 2026-11-25)

**Ergebnis:** Alle sechs Jobs grün auf 7978851, die Version, die als 28dda05 nach `main` gemergt wurde (#69 enthält #65). Strikter Modus an.
Stufe: **Simulator**. Am iPhone ist noch nichts abgenommen.

- Lauf: https://github.com/email-blip/Pulse-one/actions/runs/45524294690
- Video: Artefakt `durchstich-video-220` (iPhone 17 Pro, 75 MB, h264). Bilder je Schritt in `shots-220-durchstich`.
- **Durchstich `testWalkthrough`: bestanden, alle 16 Schritte ✓** (strikt, also wäre jeder fehlende Bildschirm rot).
  Schritt 16 „Sprachgespräch mit ROOK“: Status Zuhören → Denken → Sprechen, beide Äußerungen im Transkript, zwei ROOK-Antworten,
  Unterbrechung über den Statuswert „Unterbrochen: 1“ nachgewiesen (#67), Gespräch beendet.
- Screenshot-Matrix M1 auf allen drei Geräten grün (Standard und XXXL, Reduce Motion auf drei Ansichten).
- Barrierefreiheit: alle Audits grün.
  - Dashboard und Kachel-Editor werden je Kachelreihe geprüft. Ergebnis: „Kacheln voll sichtbar geprüft: 9 von 9“ für beide.
  - Kontrastbefunde ohne Element werden nur nach der von Johannes freigegebenen Regel geduldet (24.11., „Ja, eng begrenzt“): bei
    verdecktem Text unter der Tab-Leiste, mit Zählbindung, jeder Fall als Lauf-Hinweis „Audit geduldet“.
  - Belege und Herleitung: `/mnt/project-files/pulse-one/neubau/qa/audit-213/` (BEFUNDE.md, VORSCHLAG.md, VORSCHLAG-2.md).

### Performance (Simulator, nur berichtend)
| Test | Wert |
|---|---|
| Scrubbing Jahr (~105 000 Punkte), Zeit je Zug | 3,58 s im Mittel (vorher 27,7–33,9 s) |
| Scrubbing, CPU je Zug | 2,18 s |
| Scrubbing, Spitzen-Speicher | 394 MB (vorher 1,05 GB) |
| Chart-Zähler nach dem Scrubbing | „Charts 15× (366 Marks), Schritte 257 (82 ms), Laden 17 719 ms“ |
| Leerlauf-CPU mit verborgenem Dashboard, 5 s | 0,003 s, also praktisch keine Daueranimation |
| Pannen: Bildrate und Hitches | keine Werte. Der Simulator liefert die System-Scroll-Signposts nicht, also offen bis zur Messung am iPhone |

Das Laden des Jahres im Verlauf (17,7 s) ist der größte offene Wert. Für die 60 fps gilt: erst nach einer Messung am iPhone.

### Unterwegs gefundene und behobene Fehler
- Schritt 16: Die Unterbrechung lief, aber der Test las den Status zu spät (Rennen). 05 hat den Zähler „Unterbrochen: N“ ergänzt (#67).
- Mitternacht: Die Szenario-Nacht (22:40–06:55) lag nach 00:00 UTC in der Zukunft, und der Ring-Mapper verwarf sie. Folge: keine
  Schlafspur. Behoben über `M1.launch`: Die App läuft in einer festen Zeitzone, in der es etwa 20:00 ist. Ein erster Versuch über
  das Szenario (bd055c6) war falsch und ist zurückgenommen.
- Geräte-Ansicht „Letzter Messwert“: Der Kontrastbefund trat nur im zweiten Audit-Versuch nach Zeitüberschreitung auf. 00 lässt die
  App vor dem zweiten Versuch 3 s ruhen.

### Offen
1. iPhone-Abnahme durch Johannes: Ablauf, Ton, Sprachgespräch mit echtem Mikrofon, 60 fps beim Scrubben.
2. Ladezeit des Jahresverlaufs (17,7 s im Simulator) mit 03 klären.
3. Pannen-Hitches nur am Gerät messbar.
