# Colmi-Protokoll (R02/R03-Familie)

Quelle: [tahnok/colmi_r02_client](https://github.com/tahnok/colmi_r02_client) (MIT), am R02 erprobt. Für den **R03 unbewiesen**, bis der echte Ring antwortet. Gadgetbridge listet R02/R03/R06 als gleiche Hardware ("Yawell"), R05/R09 zusätzlich mit Temperatur.

- Dienst: Nordic UART `6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E`; Schreiben `…0002`, Benachrichtigung `…0003`. Firmware: Device-Information `180A` / `2A26`.
- Paket: 16 Byte `[Befehl, 14 Byte Daten, Prüfsumme = Summe(0…14) & 0xFF]`.
- Befehle: 1 Uhr stellen (UTC, BCD), 3 Akku, 21 Puls-Verlauf (288 × 5 min je UTC-Tag), 22 Puls-Intervall, 67 Schritte, 105 Live-Messung starten/fortsetzen (Typ 1 Puls, 3 SpO₂, 10 HRV), 106 stoppen.
- Nur eine Verbindung gleichzeitig: QRing-App vorher schließen.
- Firmware-Updates sind erlaubt (Eigentümer). Unbekannte Antworten werden protokolliert, nicht verworfen.
- Code: `apps/PulseOne/Packages/PulseCore/Sources/PulseCore/ColmiProtocol.swift`.

Modelle (laut Community, unbestätigt): R02, R03, R05 (+Temp), R06, R09 (+Temp), R10, R12. R11 nicht einplanen. Klone mit gleichem Namen und anderer Hardware existieren.
