# Colmi-Protokoll (R02/R03-Familie)

Quelle: [tahnok/colmi_r02_client](https://github.com/tahnok/colmi_r02_client) (MIT), am R02 erprobt. Für den **R03 unbewiesen**, bis der echte Ring antwortet. Gadgetbridge listet R02/R03/R06 als gleiche Hardware ("Yawell"), R05/R09 zusätzlich mit Temperatur.

- Dienst: Nordic UART `6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E`; Schreiben `…0002`, Benachrichtigung `…0003`. Firmware: Device-Information `180A` / `2A26`.
- Paket: 16 Byte `[Befehl, 14 Byte Daten, Prüfsumme = Summe(0…14) & 0xFF]`.
- Befehle: 1 Uhr stellen (UTC, BCD), 3 Akku, 21 Puls-Verlauf (288 × 5 min je UTC-Tag), 22 Puls-Intervall, 67 Schritte, 105 Live-Messung starten/fortsetzen (Typ 1 Puls, 3 SpO₂, 10 HRV), 106 stoppen.
- Nur eine Verbindung gleichzeitig: QRing-App vorher schließen.
- Firmware-Updates sind erlaubt (Eigentümer). Unbekannte Antworten werden protokolliert, nicht verworfen.
- Code: `apps/PulseOne/Packages/PulseCore/Sources/PulseCore/ColmiProtocol.swift`.

Modelle (laut Community, unbestätigt): R02, R03, R05 (+Temp), R06, R09 (+Temp), R10, R12. R11 nicht einplanen. Klone mit gleichem Namen und anderer Hardware existieren.

## R03-Realtest 2026-11-21 (Build 1.0.1 (7), Firmware RY03_3.00.21_241028, Hardware RY03_V3.0)

Diagnosedatei von Johannes, iOS 26.6.1. Gegenprobe mit der QRing-App direkt danach: Puls 81 bpm, SpO₂ 97 %, HRV 34 ms gemessen. Ring und Sensor funktionieren also.

| Zeit | Richtung | Bytes | Bedeutung (Quelle) |
|---|---|---|---|
| 1,26 s | RX | `03 64 …` | Akku 100 % (tahnok) |
| 1,28 s | RX | `2f f4 …` | `CMD_PACKET_SIZE`, 244 Byte (Gadgetbridge, nur geloggt) |
| 11,13 s | TX | `69 01 01 …` | Start Echtzeit-Puls (tahnok) |
| 11,18 s | RX | `69 01 00 00 …` | Fehler 0, Wert 0 = „noch kein Wert“ |
| 27,30 s | RX | `73 0c 63 …` | Benachrichtigung Akku 99 %, lädt nicht (Gadgetbridge `NOTIFICATION_BATTERY_LEVEL`) |
| 31,62 s | TX | `69 01 03 …` | „Fortsetzen“ (in tahnok definiert, aber vom tahnok-Client nie gesendet) |
| 41,89 s | – | – | PULSE ONE gibt nach 30 s ohne Wert auf |

Danach kam vom Ring kein einziger Pulswert. Abgleich mit den Referenzen:
- **tahnok `client.py`**: sendet nur Start, wartet bis 20 × 2 s Stille, verwirft Nullwerte, sendet am Ende Stopp. Kein „Fortsetzen“.
- **Gadgetbridge `onHeartRateTest`**: sendet nur `69 01` (ohne Aktionsbyte), kein Fortsetzen, kein Stopp, kein Zeitlimit. `liveHeartRate`: Byte 2 = Fehler (1 = falsch getragen, 2 = vorübergehend, nur loggen), Byte 3 = Wert, 0 wird ignoriert.

Änderung (Build 8): kein „Fortsetzen“ mehr, Wartezeit 60 s statt 30 s, Fehlercodes 1/2 wie Gadgetbridge, zweite Startvariante B (`69 01`) als eigener Knopf. Welche Variante der R03 braucht, zeigt erst der nächste Realtest. Firmware RY03_3.00.21_241028 ist **noch nicht** als getestet eingetragen.
