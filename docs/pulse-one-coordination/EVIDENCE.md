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
