# Abgleich General Directive 3.0 ↔ Repository (Stand main 6ec57da, 2026-11-20)

Geprüft am Code, an Tests und an CI-Lauf 6 (https://github.com/email-blip/Pulse-one/actions/runs/44773212667, grün).
Umfang: 2.604 Zeilen Swift (App + Kern), 33 Swift-Testing-Tests im Kern, 9 UI-/Screenshot-/Audit-Tests.

## §2 „Implementiert bzw. gemeldet“ – Prüfung

| Aussage | Beleg im Repo | Ergebnis |
|---|---|---|
| Grundlegende R03-BLE-Anbindung | `Sources/Bluetooth/ColmiCentral.swift` (CoreBluetooth, Nordic UART), `PulseCore/ColmiProtocol.swift` | stimmt, **nur Simulator/Unit-Tests**, kein Gerätekontakt |
| Gerätesuche und Verbindung | Scan 20 s, Connect 15 s, UART-Prüfung, Wiederverbinden mit Backoff (`ReconnectPolicy`) | stimmt, ungetestet am Gerät |
| Verbindungsstatus | `ConnectionState` (deutsche Zustände) + Tests | stimmt |
| Erste Messwertverarbeitung | Akku, Firmware, Live-Puls (Befehl 105/106), Plausibilitätsgrenzen in `VitalReading` | stimmt; Puls-Verlauf-Parser vorhanden, **nicht angebunden** |
| Datenmodell und Pipeline | `StoredMeasurement` (SwiftData): Wert, Einheit, Zeit, Quelle, Gerät, Modell, Firmware | **teilweise**: keine Profil-ID, keine Original-Sample-ID, kein Importzeitpunkt, keine Qualität, keine Zeitzone, keine Rohdaten, keine Dublettenvermeidung → Meilenstein 2 |
| Simulator-UI-Test | 9 UI-Tests, Screenshots 3 Geräte × Standard/xxxl | stimmt |
| CI mit Accessibility-Prüfung | `performAccessibilityAudit` auf 4 Screens; `textClipped` als belegter Fehlalarm ausgenommen (DECISIONS.md) | stimmt, mit dieser Ausnahme |
| Koordinationsverzeichnis | `docs/pulse-one-coordination/` | stimmt |

## §2 „Noch nicht implementiert“ – Prüfung

| Punkt | Ergebnis |
|---|---|
| HealthKit, Mehrpersonenprofile, Onboarding, Oura, universelle Geräteadapter, Tagescoach, KI | stimmt: **nicht vorhanden** (kein HealthKit-Import, kein Profil-Modell, kein Adapter-Protokoll) |
| Anatomisches 3D-Herz | **teilweise überholt**: Heart Chamber existiert seit PR #1 (RealityKit, prozedurales stilisiertes Herz, BPM-gesteuert, Drehen/Zoom, Haptik/Ton, Hinweis „kein EKG“). Erfüllt §12 **nicht** bei „anatomisch plausibles Modell“ und „historische Herzfrequenzdaten“. Stufe: im Simulator getestet. |
| Realistischer 3D-Mensch, Sleep Universe, Vital Orbit, Time Machine, Sportwelten, vier Designprofile | stimmt: nicht vorhanden |
| Umfassendes Sound-/Haptiksystem | stimmt: nur Herz-Feedback und Verbindungs-Haptik, kein gemeinsames System |

## Korrektur zur Ausgangsannahme
Die Directive spricht von der „MyBody-Codebasis“. Der geprüfte Stand ist die native App **PULSE ONE im Repo `email-blip/Pulse-one`** (Neustart auf Johannes' Anweisung, 2026-11-20 15:32 UTC). Die Expo-App MyBody (Repo MyBotty) bleibt unverändert. Weiterentwickelt wird dieser Stand, ohne erneuten Neustart.

## Capability-Matrix Colmi R03

| Funktion | Zustand | Grundlage |
|---|---|---|
| Gerätesuche | implementiert, ungetestet | Name `R03_xxxx` + UART-Dienst |
| Geräteidentifikation | implementiert, ungetestet | `ColmiModel.detect`, Firmware 180A/2A26 |
| Verbindung | implementiert, ungetestet | |
| Batteriestatus | implementiert, ungetestet | Befehl 3 |
| Live-Puls | implementiert, ungetestet | Befehle 105/106, 60 s Limit |
| Historische Pulsdaten | Parser implementiert, nicht angebunden | Befehl 21, Referenz colmi_r02_client (R02) |
| Schritte | Protokoll unbekannt (nur Fremdquelle) | Befehl 67 laut colmi_r02_client, nicht implementiert |
| Schlafdaten | Protokoll unbekannt | „Big Data“-Befehle laut Gadgetbridge, nicht implementiert |
| SpO₂ | Protokoll unbekannt | laut Gadgetbridge, nicht implementiert |
| Temperatur | Protokoll unbekannt, beim R03 vermutlich nicht unterstützt | Gadgetbridge nennt Temperatur nur für R09/R05 |

„bestätigt“ hat heute keine Funktion, weil der Test am echten Ring fehlt.
