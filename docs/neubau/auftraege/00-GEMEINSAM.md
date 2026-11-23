# Gemeinsame Regeln für alle Teams 01–06 (PULSE ONE Neubau)

Lies zuerst im Repo `email-blip/Pulse-one` (Branch `main`): `CLAUDE.md`, `docs/neubau/NEUBAU-PLAN.md` (verbindlich), `docs/neubau/VERTRAEGE.md`, `DECISIONS.md`. Die vollständigen Vorgaben von Johannes (über ChatGPT) liegen in `docs/neubau/VORGABEN-CHATGPT-2026-11-23.md`.

- Leitstand ist der Thread „00 Leitstand“ (früher „App komplett neu wie Oura gestalten“). Er besitzt Verträge, App-Einstieg, `project.yml`, Datenbankschema, Workflows, `DECISIONS.md` und lädt als Einziger zu TestFlight hoch.
- Schreibe nur Dateien deines Teams (Tabelle §7 im Plan). Brauchst du eine fremde Datei, mach einen kleinen Patch im eigenen PR und nenne im PR-Text das Besitzer-Team. Verträge in `PulseCore/Contracts/` nur benutzen, nicht ändern; Änderungswunsch an den Leitstand.
- Eigener Branch (vorgegeben), von `main` aus. **Jeder Push mit Änderungen unter `apps/` oder `scripts/` startet die volle CI** (belegt alle 5 Gratis-Mac-Jobs, 15–20 Min., ein neuer Push bricht den alten Lauf ab). Deshalb lokal fertig machen und gebündelt pushen, höchstens etwa alle 2 Stunden; reine `docs/`-Pushes starten nichts. PR öffnen, wenn ein Paketteil fertig ist. PR-Titel beginnt mit deiner Teamnummer, z. B. „[03] Dashboard-Kacheln“. **Nicht selbst mergen**: Der Leitstand merged grüne PRs in der Reihenfolge des Plans.
- Kein neues Paket ohne `DECISIONS.md`-Eintrag (über den Leitstand). Keine kostenpflichtigen Dienste.
- Keine simulierten Werte als Ringmessung: Testdaten nur mit `-uiTesting YES` und Banner „Testansicht“.
- Alte Oberflächen deines Bereichs entfernst du im selben PR, in dem du sie ersetzt. Keine Messdaten löschen; SwiftData-Modelle nur über den Leitstand ändern (`scripts/schema-guard.py --update`).
- ROOK-Ton (Plan §9) gilt für jeden sichtbaren oder gesprochenen Text.
- Reduce Motion, große Schrift (XXXL) und VoiceOver sind Teil jeder Abnahme.
- Status ehrlich nach Stufen: Konzept / implementiert / gebaut / Simulator / iPhone / abgenommen. Ein Mockup beweist keine Ring-Integration.
- Meldung an Johannes kurz, Deutsch, Handy-tauglich. Ergebnis immer mit PR-Link und Nachweisstufe.
