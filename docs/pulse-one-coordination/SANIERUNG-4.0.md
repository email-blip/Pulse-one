# Sanierung nach Emergency Directive 4.0

Stand: 2026-11-20, Build 4 (TestFlight). Verfasser: Claude Code. Statusstufen nach §14:
Geplant → Implementiert → Gebaut (CI) → Simulator → iPhone → Abgenommen.

Kurzfassung: Die App kann einen R03 finden, verbinden, Akku und Firmware lesen. **Eine Pulsmessung ist auf dem iPhone nie gelungen.** Apple Health ist technisch angebunden, aber für den Nutzer kaum sichtbar. TODAY, Analyse, Claude, Coach und Einstellungen **existieren nicht**. Die Heart Chamber ist ein Prototyp. Ein grüner CI-Lauf hat das verdeckt.

## 1. Fehlerbericht (Johannes' Realtest, Build 4)

| # | Beobachtung | Ursache im Code (geprüft) |
|---|---|---|
| F1 | „Verbunden · misst Puls“, aber nie ein Wert | `ColmiCentral.startHeartRate()` setzt `.measuring` **sofort beim Senden** des Startbefehls, bevor der Ring geantwortet hat. Antworten mit Wert 0 werden still verworfen. Nach 60 s endet die Messung ohne Meldung. Es gibt keinen Zustand „fehlgeschlagen“ und keinen Zeitablauf. |
| F2 | 4 unbekannte Antworten | Werden nur gezählt, der Hex-Inhalt ist für den Nutzer nicht sichtbar oder exportierbar. Ursache der fehlenden Werte daher **nicht belegbar**. |
| F3 | Kein durchgehender Gesundheitsüberblick, kaum Verlauf | Es gibt keinen TODAY-Screen. Gespeicherte Werte erscheinen nur als Liste im Geräte-Screen. |
| F4 | Keine KI-Analyse | Nicht implementiert. |
| F5 | Apple Health nicht sichtbar | Adapter liest 10 Typen inkrementell, aber es gibt keinen Einrichtungsscreen, keine Typenerklärung und keine Anzeige der importierten Werte außer Zählern. |
| F6 | Keine Einstellungen | Nicht implementiert. |
| F7 | Heart Chamber: Haptik/Ton unbewiesen | Code vorhanden (CoreHaptics + AVAudioEngine), ohne echten Puls nur mit dem letzten gespeicherten Wert oder gar nicht aktiv. Ton respektiert den Stummschalter (Kategorie `.ambient`), das kann wie „kein Ton“ wirken. |
| F8 | Keine Interpretation, kein Coach | Nicht implementiert. |

## 2. Ehrliche Funktionsmatrix

| Funktion | Stufe | Beleg / Lücke |
|---|---|---|
| R03 finden, verbinden | **iPhone** | Johannes: R03_9903 verbunden |
| Firmware lesen | **iPhone** | RY03_3.00.21_241028 angezeigt |
| Akku lesen | **iPhone** | 100 % angezeigt |
| Uhrzeit setzen | Implementiert | Ring bestätigt; Wirkung unbewiesen |
| Live-Puls | **Fehlgeschlagen auf iPhone** | siehe F1/F2 |
| Puls-Verlauf (Ring-Log 0x15) | Parser implementiert, nicht angebunden | |
| SpO2, HRV, Schritte, Schlaf, Temperatur vom Ring | Nicht implementiert | Protokoll für R03 ungeprüft |
| Wiederverbinden | Implementiert | nicht gezielt getestet |
| Speichern mit Zeit + Herkunft (SwiftData) | Simulator | Dublettenschutz getestet |
| Apple Health lesen (10 Typen, Anker, Löschungen) | Gebaut | auf iPhone nicht bestätigt, keine sichtbare Auswertung |
| Apple Health: Einrichtung je Typ, Status, letzter Import | Nicht implementiert | |
| TODAY | Nicht implementiert | |
| Diagramme, Zeiträume | Nicht implementiert | |
| Analyse-Engine (Baselines, Trends) | Nicht implementiert | nur Tageswerte (`DailySeries`) |
| Claude-Verbindung, PULSE INTELLIGENCE | Nicht implementiert | |
| Coach | Nicht implementiert | |
| Einstellungen | Nicht implementiert | |
| Heart Chamber | Prototyp, Simulator | Haptik/Ton auf iPhone unbewiesen |
| BLE-Diagnose-Export | Nicht implementiert | |

## 3. Button-Audit (alle sichtbaren Bedienelemente)

| Ort | Element | Tatsächliche Wirkung | Bewertung |
|---|---|---|---|
| Verbinden | Ring suchen | Scan 20 s | ok |
| Verbinden | Ring in Trefferliste | verbindet | ok |
| Verbinden | Alle Bluetooth-Geräte zeigen | Filter | ok |
| Verbinden | Suche stoppen | stoppt Scan | ok |
| Verbinden | Erneut verbinden mit … | verbindet gemerkten Ring | ok |
| Verbinden | Abbrechen | trennt | ok |
| Verbinden | **Puls jetzt messen** | sendet Startbefehl, zeigt sofort „misst Puls“ | **irreführend** → PR 1 |
| Verbinden | Messung beenden | sendet Stopp | ok |
| Verbinden | Trennen | trennt | ok |
| Verbinden | Heart Chamber öffnen | öffnet Prototyp | als Prototyp kennzeichnen → PR 8 |
| Verbinden | Geräte & Datenquellen | öffnet Geräte | ok |
| Geräte | Ring hinzufügen | startet Scan, schließt | ok |
| Geräte | Apple Health verbinden | Freigabe + Import | funktioniert, Ergebnis kaum sichtbar → PR 2 |
| Geräte | Jetzt synchronisieren (nur Health) | Import | ok |
| Geräte | Umbenennen / Entfernen | ändert Registry | ok |
| Geräte | Trennen / Verbinden | Ring | ok |
| Geräte | Bevorzugte Quelle je Messwert | speichert Präferenz | ok, Wirkung erst mit TODAY sichtbar |
| Heart Chamber | Darstellung, Haptik, Ton, Schließen | wirken | Ton/Haptik ohne echten Puls unbewiesen |

Keine Platzhalter-Buttons ohne Funktion gefunden. Ein Button sagt aber etwas, das nicht stimmt („misst Puls“).

## 4. R03-Messkette (BLE-Kommando bis Anzeige)

1. Tipp „Puls jetzt messen“ → `69 01 01 …` (Start, Typ HR) auf 6E400002.
2. Erwartet laut colmi_r02_client (am R02 geprüft): Antworten `69 01 00 <bpm>` auf 6E400003; die ersten Sekunden oft `bpm = 0` (Sensor sucht), Fehlercode in Byte 2.
3. App: `bpm = 0` wird verworfen, `bpm > 0` wird gespeichert und angezeigt.
4. Alle 20 s `69 01 03` (weiter), nach 60 s `6A 01 00 00` (Stopp).

Mögliche Bruchstellen, **alle unbelegt**, bis ein Mitschnitt vorliegt:
- a) Der R03 mit Firmware 3.00.21 antwortet anders (andere Bytes, anderer Befehl, anderer Dienst).
- b) Der Ring liefert nur Nullwerte, weil er schlecht sitzt oder länger braucht. Ohne Rückmeldung wirkt das wie „nichts“.
- c) Die 4 unbekannten Pakete sind die eigentliche Antwort, in einem Format, das die App nicht kennt.
- d) Der Ring erwartet „weiter“ häufiger als alle 20 s.
- e) Ein zweiter Datendienst (in offenen Projekten für neuere Colmi-Firmware beschrieben) wird nicht abonniert. **Nicht** auf Verdacht verwenden.

Vorgehen ohne erfundene Kommandos: Erst ein vollständiger, exportierbarer BLE-Mitschnitt (PR 1). Dann entscheiden wir anhand echter Bytes. Erst danach weitere Datenarten (Verlauf 0x15, SpO2, HRV), jeweils mit Mitschnitt belegt.

## 5. Ring-Dateninventar (Stand heute)

| Datenart | verfügbar | live | Verlauf | belegt am R03 |
|---|---|---|---|---|
| Akku | ja | – | – | **ja** |
| Firmware | ja | – | – | **ja** |
| Puls | laut Protokoll | angefragt, **kein Wert** | Log 0x15, nicht angebunden | nein |
| SpO2, HRV | laut Protokoll (Typ 3, 10) | nicht angefragt | unbekannt | nein |
| Schritte | laut Protokoll (0x43) | – | nicht angebunden | nein |
| Schlaf, Stress, Temperatur | unbekannt | – | – | nein |

Nicht belegte Datenarten zeigt die App nicht als „verfügbar“. Der Adapter-Katalog bleibt bei „Protokoll unbekannt“.

## 6. Apple Health (Prüfung)

Vorhanden: 10 Mengen-Typen + Schlaf, Leserecht, Anker je Typ, Löschungen, 30 Tage Erstimport, Dubletten-Schutz, Herkunft.
Fehlt (§5): Einrichtungsscreen mit Zweck je Typ; Ruhepuls-Herkunft sichtbar; Training, aktive/ruhende Energie getrennt, VO2max, Atemfrequenz, Gewicht, Größe; Status „letzter Import“, Fehlertext, Anzahl je Typ; Hinweis, dass iOS verweigerte Leserechte verbirgt (leere Daten ≠ Fehler). Hintergrund-Abruf (`HKObserverQuery` + Background Delivery) erst nach Messung im Alltag; **keine Echtzeit-Versprechen**.

## 7. Claude-API-Paket (Spezifikation)

- Einstellungen → Künstliche Intelligenz → Claude verbinden: Schlüssel eingeben (SecureField), Speicherung nur im **Keychain** (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, kein iCloud-Sync), Verbindungstest (`GET /v1/models`), Modellwahl aus dieser Liste, Schlüssel ersetzen/löschen. Der Schlüssel erscheint nie in Logs, Diagnose-Export, Screenshots oder Repo.
- Aufruf direkt vom iPhone über URLSession (`POST /v1/messages`), es gibt kein offizielles Swift-SDK. Strukturierte Ausgabe per JSON-Schema mit den 9 Abschnitten aus §9, Prüfung vor Anzeige.
- Vor jedem Senden: Vorschau, welche Kategorien und welcher Zeitraum hinausgehen, plus geschätzte Kosten. Nur Tages- und Wochenkennzahlen, keine Rohdaten, keine Namen oder Geräte-IDs. `HealthAnalysisContext` mit Versionsnummer.
- Risiko direkter Aufruf: Der Schlüssel liegt auf dem Gerät. Für eine private App mit einem Nutzer ist das vertretbar. Für eine verteilte App braucht es einen eigenen Server, der den Schlüssel hält. Das ist **nicht** geplant ohne Freigabe.

**Kosten (müssen vor Nutzung freigegeben werden):**

| Modell | Preis je 1 Mio. Token (Eingabe / Ausgabe) | geschätzt je Analyse* | 1 Analyse täglich / Monat |
|---|---|---|---|
| Claude Opus 5.5 (beste Qualität, Vorgabe) | 4 $ / 20 $ | ca. 0,10–0,15 $ | ca. 3–5 $ |
| Claude Sonnet 5.5 | 2 $ / 10 $ | ca. 0,05–0,08 $ | ca. 1,50–2,50 $ |
| Claude Haiku 5.5 (günstig) | 0,10 $ / 0,50 $ | unter 0,01 $ | unter 0,30 $ |

\*Annahme: ca. 8 000 Token Kontext, ca. 3 000 Token Antwort inkl. Denkanteil. Nachfragen kosten zusätzlich. Abrechnung über ein Anthropic-Konsolenkonto mit Guthaben (Prepaid, Limit einstellbar). Die App zeigt nach jeder Analyse die tatsächlichen Token und Kosten.

## 8. TODAY und PULSE INTELLIGENCE (Entwurf)

**TODAY** (neuer Start-Tab): Kopf mit Gruß, Datum, Quellenstatus (Ring/Health, letzte Aktualisierung). Darunter Karten je Messwert: Wert, Einheit, Zeitpunkt, Quelle, Mini-Verlauf, Einordnung relativ zum eigenen 30-Tage-Band, Verfügbarkeit („keine Daten“ statt erfundener Zahl). Tipp auf eine Karte → Detail mit Swift Charts, Zeiträume Heute / 7 / 30 / 90 Tage / frei, Antippen eines Punkts zeigt Wert und Herkunft.

**PULSE INTELLIGENCE** (eigener Tab): Zeitraum und Quellen wählen → Vorschau der gesendeten Kategorien → Analyse → 9 Abschnitte, klar getrennt: Messwerte · berechnete Kennzahlen · statistische Beobachtungen · KI-Deutung · Empfehlungen. Nachfragen, Empfehlung „in den Tagesplan übernehmen“, gespeicherte Analysen mit Zeit, Zeitraum, Modell, Datenversion, Vergleich.

**Tabs danach:** Heute · Verlauf · Intelligence · Geräte · Einstellungen. Die Heart Chamber wird aus „Heute“ geöffnet und als „Prototyp“ markiert.

## 9. Sanierungsplan (kleine PRs, in dieser Reihenfolge)

| PR | Inhalt | Abnahme |
|---|---|---|
| 0 | Dieses Dokument, STATUS korrigiert | gelesen |
| 1 | **Ring-Messkette:** Messzustände (angefordert → läuft erst nach erster Ring-Antwort → Wert empfangen / fehlgeschlagen mit Grund / Verbindung verloren), Zeitablauf 30 s ohne Wert; Wertanzeige mit Einheit, Uhrzeit, Quelle; **BLE-Diagnose** (alle Dienste/Merkmale, jedes gesendete und empfangene Paket mit Zeit, Export über Teilen-Menü ohne Geräte-ID) | Szenario A mit echtem R03; Johannes schickt einen Mitschnitt |
| 2 | Apple-Health-Einrichtung: Typen mit Zweck, fehlende Typen ergänzt, Importstatus je Typ, letzter Import, Fehler | Szenario B |
| 3 | Analyse-Kern: Baselines (30-Tage-Median + Band), Abweichung, Trend, Vollständigkeit, getrennte Ergebnistypen; Tests | CI |
| 4 | TODAY + Detailansichten mit Swift Charts und Zeiträumen; Tab-Struktur; Einstellungen-Grundgerüst | Szenario D |
| 5 | Ring-Verlauf (0x15) und weitere Ringdaten, **nur** nach Auswertung des Mitschnitts | Szenario A |
| 6 | Claude verbinden (Keychain, Test, Modelle, Kostenanzeige) | Szenario C, nach Kostenfreigabe |
| 7 | PULSE INTELLIGENCE (Kontext v1, Vorschau, strukturierte Antwort, Speicherung, Nachfragen) | Szenario C |
| 8 | Heart Chamber als Prototyp kennzeichnen, Zustand „kein Puls“, Haptik/Ton-Test-Knopf | iPhone |
| 9 | Coach (Ziele, Regeln, Claude formuliert) | später |

Nach PR 1 und nach PR 4 je ein TestFlight-Build (kostenlos, GitHub-Minuten).

## 10. Was Johannes tun muss

1. Nach PR 1: neuen Build installieren, eine Messung starten, Diagnose exportieren und in den Chat schicken (Anleitung kommt mit dem Build).
2. Vor PR 6: Freigabe der Claude-Kosten und Anlegen eines Anthropic-Kontos mit Guthaben (Anleitung kommt dann). Den Schlüssel gibt er **nur in der App** ein, nie im Chat.
