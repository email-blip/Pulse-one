# Backlog PULSE ONE (nach General Directive 3.0 §16)

Stand 2026-11-20. Reihenfolge = Priorität. Jeder Punkt endet mit Beleg (CI-Lauf, Screenshot, Gerätetest) und Stufe nach §18.

## M1 FIRST DEVICE CONNECT – blockiert durch Signierung
- [x] R03-Implementierung (Code, Simulator) – PR #1
- [x] TestFlight-Workflow `.github/workflows/testflight.yml` (API-Key-Signing, nur intern)
- [ ] **Blocker (Johannes):** App-ID, App-Record, API-Key, 3 GitHub-Secrets – Anleitung `docs/TESTFLIGHT-EINRICHTEN.md`
- [ ] Erster TestFlight-Build, Installation auf dem iPhone 16 Pro
- [ ] Realtest R03 nach Testprotokoll (Suche, Verbindung, Akku, Firmware, Live-Puls), Firmware in `TestedFirmware`
- [ ] Diagnose-Log teilbar (unbekannte Pakete), damit Fehler am Gerät belegbar sind

## M2 UNIVERSAL CONNECT – startet jetzt mit den hardwareunabhängigen Teilen
1. Kern: `DeviceAdapter`-Protokoll, `DeviceCapabilities` mit Integrationsstufen (entdeckt → verbunden → kompatibel → Datenzugriff → synchronisiert → Qualität geprüft), `DeviceRegistry` (hinzufügen, entfernen, umbenennen, Profil zuordnen)
2. Kern: normalisiertes Messwertmodell `HealthSample` (Profil, Typ, Wert, Einheit, Zeit, Zeitzone, Quelle, Gerät, Original-ID, Import, Qualität, Methode, Rohdatenreferenz), `MeasurementNormalizer` (Einheiten, Plausibilität), Dublettenschlüssel, idempotenter `SyncCoordinator`, `DataSourceResolver` (Quellenpriorität ohne Mittelwertbildung)
3. App: SwiftData-Schema v2 mit Übernahme von `StoredMeasurement`; Rohpakete getrennt
4. Colmi-R03-Adapter auf das Protokoll umstellen (vorhandenen Code nutzen); R09-Adapter vorbereitet (Protokollgleichheit unbewiesen; Temperatur-Typen getrennt: Haut / relative Abweichung / Kern)
5. HealthKit-Adapter: Berechtigungen je Typ, `HKAnchoredObjectQuery` für inkrementellen Import inkl. Löschungen, Quellenzuordnung; nur Owner-Profil
6. Geräteverwaltung (Tab DEVICES): Liste, Status, Akku, Sync-Status, Messwerte, letzte Messung, Diagnose
7. Manueller Adapter; Standard-GATT-Adapter (Heart Rate Service 0x180D, z. B. Polar H10)
8. Oura-API-V2-Architektur (OAuth2, Token in Keychain), ohne Live-Schaltung: braucht Oura-Konto/Client-ID von Johannes

Abnahme: R03 und Apple Health als reale Quellen auf dem iPhone.

## M3 PERSONAL PULSE
Profile (lokal, mehrere), Onboarding 14 Schritte (überspringbar, nachholbar), Ziele, Sportarten, Trainingsstand, Dashboard TODAY; Navigation TODAY / BODY / MOVE / TRENDS / DEVICES.

## M4 DAILY COACH
Übungsbibliothek, regelbasierter Tagesplaner (Morning Activation, Main Activity, Micro Moves, Evening Reset), Basislinien mit Zustand „zu wenig Daten“, Fortschritt, Benachrichtigungen mit Ruhezeiten.

## M5 PREMIUM EXPERIENCE
Asset-Pipeline (USDZ), anatomisches Herz, Living Twin (Asset-Vergleichsmatrix, nichts kaufen ohne Freigabe), Motion-System, gemeinsames Sound-/Haptiksystem, Bildschirmaufnahmen und Performance-Messung je 3D-Funktion.
Parallel ab jetzt (Directive §19.9): Evaluation Herz- und Mensch-Assets in `docs/ASSET-EVALUATION.md`.

## M6–M8
KI-Provider (eigene API, Backend-Vermittlung prüfen), HRV- und Schlaftrends, Oura live, R09 live; fünf Sportwelten; vier Themes, Performance, Datenschutz, Langzeittests.

## Offene Punkte für Johannes
- TestFlight-Schritte (M1-Blocker).
- Später, jeweils nur mit Freigabe: Oura-Developer-App, KI-API-Anbieter, Kauf von 3D-Assets.
