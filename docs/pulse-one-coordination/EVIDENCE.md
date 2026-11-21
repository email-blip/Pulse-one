# EVIDENCE – Belege

Nur tatsächlich ausgeführte Befehle und Ergebnisse. Screenshots belegen Optik, nicht BLE-Kompatibilität.

## P1-NEU-001 (2026-11-20)

Umgebung Claude: Cloud-Container Linux, **kein Swift-Compiler, kein Xcode, kein Simulator, kein iPhone**. Kompiliert und getestet wird nur auf GitHub Actions (`macos-26`).

| Nachweis | Ergebnis |
|---|---|
| CI-Lauf 1 | rot: Kompilierfehler (Battery-Init nicht public) – behoben |
| CI-Lauf 2 | rot: 15 Bedienungshilfen-Befunde (Kontrast, Abschneiden, Dynamic Type, Namen) – behoben |
| CI-Lauf 3–4 | rot: Rest-Befunde; „Text clipped“ als Fehlalarm belegt (xxxl-Screenshots zeigen vollständigen Umbruch), Heart-Schalter zu kleine Trefferfläche – behoben |
| CI-Lauf 6 (Commit 0c1d4e5) | **grün**: Build, Swift-Testing-Kern, UI-Tests, Bedienungshilfen-Prüfung (4 Screens), Screenshots 3 Geräte × Standard/xxxl https://github.com/email-blip/Pulse-one/actions/runs/44773212667 |
| Screenshots | Branch `ci-screenshots/claude/project-thread-p4cjhd` |

Nicht vorhanden (ausdrücklich): signierte Installation, TestFlight, echter R03-Kontakt, echter Messwert vom Ring.

## R03-Realtest 1 (2026-11-21, Build 1.0.1 (7))

| Nachweis | Ergebnis |
|---|---|
| Verbindung, Dienste, Firmware lesen | erfolgreich (Diagnosedatei Johannes, 00:29Z) |
| Akku | 100 % per Befehl 3, 99 % per Benachrichtigung 0x73/0x0C |
| Pulsmessung PULSE ONE | 2 × fehlgeschlagen: Ring quittiert Start mit Wert 0, danach keine Werte |
| Gegenprobe QRing-App | Puls 81 bpm, SpO₂ 97 %, HRV 34 ms (Screenshots Johannes, 00:38–00:41Z) |
| Bewertung | Ring in Ordnung; PULSE-ONE-Ablauf weicht ab. Details und Änderung: `docs/colmi-protokoll.md` |

Status R03-Puls: **Gebaut**, nicht iPhone. Kein echter Messwert in PULSE ONE.

## R03-Realtest 2 (2026-11-21, Build 1.0.1 (8))

| Nachweis | Ergebnis |
|---|---|
| Firmware | RY03_3.00.28_250401 (vorher 3.00.21, Update über QRing) |
| Pulsmessung Variante A | erfolgreich, 61–63 bpm, erste Werte nach 25,6 s (Diagnosedatei Johannes 06:01Z) |
| Pulsmessung Variante B | erfolgreich, 63–64 bpm |
| Status R03-Puls | **iPhone** (echter Wert in PULSE ONE); „Abgenommen“ entscheidet Codex |
