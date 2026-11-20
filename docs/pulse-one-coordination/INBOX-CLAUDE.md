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
