# CLAUDE.md – PULSE ONE

Native iPhone-App für Gesundheit, Sport und Regeneration. **ONE BODY. MANY WORLDS.**
Eigentümer: Johannes Sommer (technischer Laie, solo). Entwicklungsleitung: Codex (externer Agent, Nachrichten kommen über Johannes). Ausführender Entwickler: Claude Code.
Oberfläche Deutsch. Code, Kommentare, Commits Englisch.

Zuerst lesen: `docs/pulse-one-coordination/` (MASTER-DIRECTIVE, STATUS, OUTBOX-CODEX, INBOX-CLAUDE, EVIDENCE), dann `DECISIONS.md`, `docs/WORKFLOW.md`.

## Identität
- App-Name **PULSE ONE**, Bundle-ID `de.sommerlabs.pulseone`, App-Ordner `apps/PulseOne`.
- Neustart 2026-11-20: eigenständige native App. Die Expo-App MyBody (Repo MyBotty) bleibt unverändert und wird hier nicht verwendet. Nur Wissen übernehmen, Code neu in Swift.

## Nicht verhandelbar
- **Kein Mac.** Build, Tests, Simulator, Screenshots nur über GitHub Actions `macos-26` (`.github/workflows/ios-ci.yml`). Ein Lauf = 5 parallele Mac-Jobs, ≈ 15–20 Min. Wartezeit (Gratis-Limit: 5 Mac-Jobs gleichzeitig): Änderungen bündeln, sparsam pushen.
- Ohne ausdrückliche Freigabe von Johannes im Thread: keine kostenpflichtigen Dienste, keine App-Store-Veröffentlichung, keine Weitergabe echter Gesundheitsdaten an externe Dienste.
- Gesundheitsdaten bleiben auf dem Gerät (an Claude nur nach sichtbarer Vorschau). Kein zugelassenes Medizinprodukt, aber seit 2026-11-21 (Entscheidung Johannes) darf die Claude-Analyse ärztlich deuten: mögliche Diagnosen mit Wahrscheinlichkeit, Abklärung, Training, Reha, Behandlung, ohne Floskeln (`SafetyMode.clinical`). Pflicht bleiben: klare Dringlichkeit bei Warnzeichen (S5/S6), Unsicherheit als Wahrscheinlichkeit, verordnete Medikamente nie eigenmächtig umstellen lassen.
- **Keine simulierten Werte als Ringmessung.** Testszenarien nur mit `-uiTesting YES` und sichtbarem Banner „Testansicht“.
- Status ehrlich nach Master-Directive §14 (Geplant → Implementiert → Gebaut → Simulator → iPhone → Abgenommen). Kompiliert ≠ fertig, Simulator ≠ R03-kompatibel.
- Ring-Firmware-Updates sind dauerhaft erlaubt. Unbekannte Ring-Antworten protokollieren, nie abstürzen.
- Keine Secrets im Repo (Signing nur über GitHub Secrets).
- Nur APIs nutzen, die für das gepinnte SDK dokumentiert sind; im Zweifel prüfen (`swiftui-expert-skill/references/latest-apis.md`).
- Abhängigkeiten vermeiden; Drittanbieter nur mit Eintrag in `DECISIONS.md`.

## Toolchain (gepinnt)
- Xcode 26.6 auf `macos-26`, Swift 6, strict concurrency complete, Warnungen = Fehler. iOS 18.0 Deployment Target; neuere APIs nur hinter `if #available`.
- XcodeGen (`apps/PulseOne/project.yml`), `.xcodeproj` wird nie committet.
- Logik in `Packages/PulseCore` mit Swift Testing; UI-Tests, Screenshots, `performAccessibilityAudit` in `apps/PulseOne/UITests`.

## Geräte
- Colmi **R03** (vorhanden, erstes Testgerät). Colmi **R09** bestellt; Protokollgleichheit und Temperatur erst nach Realtest behaupten. „H03“/„H09“ sind Tippfehler.
- Protokoll: `docs/colmi-protokoll.md`. Getestete Firmware in `TestedFirmware.versions` eintragen.

## Arbeitsweise
- Feature-Branch → push → CI → Screenshots aus `ci-screenshots/<branch>` prüfen (`studio-visual-qa`) → PR → selbst squash-mergen, wenn CI grün (Wunsch des Eigentümers).
- Jede Codex-Antwort in `INBOX-CLAUDE.md` mit Auftrags-ID und Commit; Belege in `EVIDENCE.md`; `STATUS.md` aktuell halten.
- Skills: eigene `studio-*` haben Vorrang vor gepinnten Fremd-Skills (`VENDOR.lock.md`).
