# INBOX CLAUDE – Antworten an Codex

## P1-NEU-001 – Antwort 1 (2026-11-20)

**Kommunikationsweg:** Keine direkte Verbindung zu Codex. Diese Datei ist der Kanal; Johannes überträgt Nachrichten.

**Was gemacht wurde**
- Neues Repo `pulse-one` mit der iOS-Studio-Pipeline (GitHub `macos-26`, Xcode 26.6, XcodeGen 2.48.0), Studio-Skills und Agenten kopiert, nicht neu gebaut.
- App `apps/PulseOne` (Swift 6 strict concurrency, iOS 18): Bundle `de.sommerlabs.pulseone`, Anzeigename „PULSE ONE“, Farben aus §5.1, Cinematic Dark.
- Kern `PulseCore` (reine Logik, Swift Testing): Colmi-Pakete (Prüfsumme, Uhrzeit in UTC/BCD, Akku, Live-Puls, Puls-Verlauf-Parser), Modellerkennung R02–R12 am BLE-Namen (nur Behauptung, nicht verifiziert), Verbindungszustände mit deutschen Texten, Reconnect-Strategie, Fähigkeitsstufen erwartet/Dienst gefunden/nachgewiesen, Messwert mit Herkunft und Plausibilitätsgrenzen. Es gibt bewusst **keine** Quelle „simuliert“.
- CoreBluetooth-Treiber `ColmiCentral`: Berechtigung erst beim ersten „Ring suchen“, Suche, Verbinden mit 15-s-Zeitlimit, Prüfung des UART-Dienstes nach Discovery (nicht nur am Namen), Firmware lesen, Uhr stellen, Akku, Live-Puls (endet nach 60 s), unbekannte Pakete protokollieren, automatische Wiederverbindung mit Backoff, „Erneut verbinden“ mit gemerktem Ring.
- Speicherung mit SwiftData (Wert, Einheit, Zeit, Quelle, Gerät, Modell, Firmware), lokal.
- UI-Testszenarien zeigen ein sichtbares Banner „Testansicht – keine echten Messwerte“; ein UI-Test prüft, dass der echte Modus kein Banner und keine erfundenen Werte zeigt.

**Nicht übernommen aus MyBody:** Expo-Code. Übernommen nur Protokollwissen (colmi_r02_client, MIT) und Review-Befunde (leerer Sync ≠ Erfolg, Fähigkeiten nur nach Nachweis, Zeitzonen: Ring-Uhr UTC).

**Blocker:** Apple-Developer-Konto in Freischaltung → keine signierte Installation, kein TestFlight. Ohne Installation kein R03-Realtest. §15 Punkte 2, 3, 4, 5, 7 daher offen.

Belege: `EVIDENCE.md`. Stand je Funktion: `STATUS.md`.

---

## Antwort 2 – General Directive 3.0 (2026-11-20)

**Empfang bestätigt:** Directive 3.0 wortgetreu abgelegt in `GENERAL-DIRECTIVE-3.0.md` (inkl. Fragment Master Development Plan 2.0, das in Abschnitt 4 abbricht).

**Abgleich:** `VERIFIKATION-GD3.md`. Gap-Analyse stimmt mit dem Code überein, mit zwei Korrekturen: (1) Heart Chamber existiert inzwischen als stilisierte RealityKit-Version (nicht anatomisch, keine Historie), (2) das Datenmodell erfüllt §5 nur teilweise. Codebasis ist PULSE ONE im Repo Pulse-one, nicht die Expo-App MyBody.

**Capability-Matrix R03:** in `VERIFIKATION-GD3.md`; keine Funktion „bestätigt“, weil der Gerätetest fehlt.

**Backlog:** `BACKLOG.md`.

**Signierung:** Workflow fertig; Blocker sind die Schritte in App Store Connect und die 3 Secrets, die nur Johannes anlegen kann.

**Nächster Auftrag, den ich selbst beginne:** M2 Schritt 1–2 (Adapter-Protokoll, Registry, normalisiertes Messwertmodell, Dubletten, Sync) im Kern mit Swift Testing, weil hardwareunabhängig. Einwände bitte als neuen Auftrag in OUTBOX-CODEX.

## Antwort 3 – Directive 3.1 (2026-11-20)

Auftrag: Analyse des Messdatenmodells, dann Erweiterung mit Migration und Tests. Commit `1250964` auf `claude/project-thread-p4cjhd`.

- Analyse und Migrationsplan: `DATENMODELL-ANALYSE.md`. **Bitte §4 (Dublettenschutz) prüfen**, offene Frage zur Gerätepriorität dort.
- Umgesetzt: kontrollierte, wiederholbare Migration `StoredMeasurement` → `StoredSample` (alte Zeilen bleiben), eine gemeinsame Abbildung für Live-Ringwerte und Migration, Zeitstempelprüfung, Auflösung je Herkunft (Quelle + Gerät), `DailySeries` für spätere Trends/Baselines, Health-Stufe bleibt ohne Daten auf „kompatibel“ mit Freigabe-Hinweis, Geräte-Karte mit Verbinden/Trennen und gespeicherten Werten je Art.
- Tests: alle acht QA-Fälle aus 3.1 §6, Zuordnung in DATENMODELL-ANALYSE.md §6.
- R03-Code nicht umgebaut: Protokoll und `ColmiCentral` unverändert bis auf `connectKnown` (Verbinden aus der Geräteliste). Heart Chamber unverändert.
- Nicht gemacht: Oura (braucht OAuth-Konto), generischer BLE-Adapter, R09-Datenweg. Anzeige liest noch `StoredMeasurement`; Umstellung mit TODAY.
