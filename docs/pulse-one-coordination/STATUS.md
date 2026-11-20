# STATUS PULSE ONE

Stufen nach §14: Geplant → Implementiert → Gebaut (CI) → Simulator getestet → Auf iPhone getestet → Vom Nutzer abgenommen.

**Meilenstein:** §15 FIRST DEVICE CONNECT – **offen**.

| Funktion | Stufe | Beleg / Lücke |
|---|---|---|
| Native App baut (Swift 6, iOS 18) | Implementiert | erster CI-Lauf ausstehend |
| Colmi-Protokoll (Pakete, Parser) | Implementiert, Swift-Testing-Tests geschrieben | Referenz colmi_r02_client (R02); am R03 unbewiesen |
| Bluetooth-Berechtigung | Implementiert | Simulator hat kein Bluetooth → erst auf dem iPhone prüfbar |
| R03 finden / identifizieren | Implementiert (Name + UART-Dienst) | kein echtes Gerät getestet |
| Verbinden, Status, Abbruch, Wiederverbinden | Implementiert | kein echtes Gerät getestet |
| Akku, Firmware, Live-Puls lesen | Implementiert | kein echtes Gerät getestet |
| Werte mit Zeit + Herkunft speichern (SwiftData) | Implementiert | |
| Anzeige (Orb, Status, Gerät, gespeicherte Werte) | Implementiert | Screenshots nach CI-Lauf |
| Installierbar auf iPhone (TestFlight) | Geplant | **Blocker:** Apple-Developer-Konto in Freischaltung |
| Puls-Verlauf vom Ring (5-min-Log) | Parser implementiert, nicht angebunden | nach Realtest |
| Personenprofile, Onboarding, HealthKit | Geplant | nach FIRST DEVICE CONNECT |
| Living Twin, Heart Chamber, Designprofile, Sportwelten | Geplant | nach FIRST DEVICE CONNECT |
| Colmi R09 | Geplant | Ring nicht geliefert; Protokollgleichheit unbewiesen |

## Bekannte Lücken / Designabweichungen
- Nur Cinematic Dark; „Clinical Light“ kommt mit den Designprofilen.
- Kein Sound bisher; Haptik nur beim Verbinden.
- Keine Performance-Metrik-Tests (spart CI-Minuten), folgen mit 3D.

## Nächste Schritte
1. Erster CI-Lauf grün, Screenshots prüfen.
2. Sobald das Apple-Konto aktiv ist: Signing-Secrets, TestFlight-Upload, Installation auf Johannes' iPhone, R03-Realtest, Firmware in `TestedFirmware` eintragen.
3. Danach: Profile + Onboarding, dann RealityKit (Heart Chamber zuerst, weil an echten Puls gekoppelt).

## Offene Entscheidungen
- Keine.
