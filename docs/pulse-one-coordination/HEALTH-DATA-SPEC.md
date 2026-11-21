# PULSE ONE – Health Data Spec

Stand: 2026-11-20. Gilt für das Modul HealthDataFoundation und die Datenseite von DeviceIntegration. Bestehende Typen stehen in `Packages/PulseCore/Sources/PulseCore/Connect/HealthSample.swift`.

## 0. Ausgangslage Johannes (bestätigt 2026-11-20)
- **Keine Apple Watch.** Apple Health liefert nur iPhone-Daten (Schritte, Strecke, Etagen, Gehdaten, Gewicht, Trainings anderer Apps). Puls, SpO₂, HRV und Schlaf kommen **nur vom Ring**. Deshalb ist der Ring-Verlauf (Release 2) für die Analyse wichtiger als HealthKit.
- **Schreiben nach Apple Health:** Ring-Puls, Ring-SpO₂ und Ring-Schlaf ja; Schritte und HRV nein (Doppelzählung bzw. Methodenmischung). Geschriebene Werte tragen Metadaten mit der PULSE-ONE-Messungs-ID und werden beim Lesen als eigene Werte erkannt.
- Bewegungsaufzeichnung mit Karte (offene Sporttypen, GPS optional, Ring-Puls entlang der Route, GPX-Export, Privatzonen 200 m, Claude-Export ohne Koordinaten): Konzept `/mnt/project-files/konzept/IPHONE-HEALTH-BEWEGUNG.md`, nativ mit CoreLocation, MapKit (`MKGradientPolylineRenderer`) und HealthKit-Workouts.

## 1. Grundsätze
1. **Eine Messung = ein `HealthSample`**: Wert, Einheit, Start, Ende, Zeitzone, Quelle, Gerät, Profil, Methode, Qualität, Herkunft (`originalSampleID`, `rawDataReference`), Importzeit.
2. Originalwerte bleiben unverändert. Korrekturen (z. B. Profilzuordnung) werden protokolliert, nicht überschrieben.
3. Fehlende Daten bleiben fehlend. Es gibt **keine** Ersatz- oder Standardwerte (vgl. OPEN-SOURCE-REVIEW §4).
4. Testdaten nur mit `-uiTesting YES`, nie im echten Speicher.

## 2. Datenarten

Spalte „heute“: ob `SampleKind` den Typ schon kennt. „HK“: HealthKit-Typ. „Ring“: Colmi-Quelle laut Protokollstand.

| Datenart | SampleKind | heute | Einheit | Aggregation | HK | Ring R03 | Release |
|---|---|---|---|---|---|---|---|
| Herzfrequenz | `heart_rate` | ja | bpm | Punkt | heartRate | live 0x69/1 (unbelegt), Verlauf 0x15 | 1 |
| Ruhepuls | `resting_heart_rate` | ja | bpm | abgeleitet | restingHeartRate | – (selbst berechnet, Release 2) | 1 |
| HRV (SDNN) | `hrv_sdnn` | ja | ms | Punkt | heartRateVariabilitySDNN | Verlauf 0x39 (Methode unklar) | 1 |
| HRV (RMSSD) | **neu** `hrv_rmssd` | nein | ms | Punkt | – | aus RR (Typ 0x05) | 2 |
| SpO₂ | `spo2` | ja | % | Punkt | oxygenSaturation | live 0x69/3, Verlauf Big Data 0x2A | 1/2 |
| Atemfrequenz | **neu** `respiratory_rate` | nein | /min | Punkt | respiratoryRate | – | 1 |
| Hauttemperatur | `skin_temperature`, `…_deviation` | ja | °C | Punkt/abgeleitet | appleSleepingWristTemperature | R09 Big Data | 1 |
| Körpertemperatur | `body_temperature` | ja | °C | Punkt | bodyTemperature | – | 1 |
| Schritte | `steps` | ja | Anzahl | kumulativ | stepCount | 0x43 | 1 |
| Strecke | `distance` | ja | m | kumulativ | distanceWalkingRunning | 0x43 | 1 |
| Aktive Energie | `active_energy` | ja | kcal | kumulativ | activeEnergyBurned | 0x43 (Schätzung) | 1 |
| Ruheenergie | **neu** `basal_energy` | nein | kcal | kumulativ | basalEnergyBurned | – | 1 |
| Schlaf | `sleep_duration` + **neu** Phasen | teils | s | Intervall | sleepAnalysis | Big Data 0x27 | 1/2 |
| Training | `training_duration` + **neu** `Workout` | teils | s | Intervall | HKWorkout | – | 1 |
| VO₂max | **neu** `vo2max` | nein | ml/kg/min | Punkt | vo2Max | – | 1 |
| Gewicht | **neu** `body_mass` | nein | kg | Punkt | bodyMass | – | 1 |
| Größe | **neu** `height` | nein | m | Punkt | height | – | 1 |
| Körperfett | **neu** `body_fat` | nein | % | Punkt | bodyFatPercentage | – | 2 |
| Stress (Ring) | **neu** `stress_index_ring` | nein | Index 0–100 | Herstellerwert, 30 min | – | 0x37 | speichern; nur als Tagesmuster zeigen, markiert „Herstellerwert“, keine Einzelbewertung (Johannes 2026-11-21) |
| Geräteakku | `device_battery` | ja | % | Punkt | – | 0x03, 0x73 0C | 1 |

Neue Arten erweitern `SampleKind` und `SampleUnit`. Neue `rawValue`s sind stabil, weil sie in SwiftData gespeichert werden.

## 3. Qualität und Kontext
- `SampleQuality` (6 Stufen, Review 3.2) bleibt. **Neu:** `MeasurementContext` mit den Werten `rest`, `sleep`, `activity`, `workout`, `unknown`. Er kommt aus Schlaf- und Trainingsintervallen sowie der HealthKit-Metadaten `HKMetadataKeyHeartRateMotionContext`.
- Plausibilitätsbereiche stehen in `SampleKind.plausibleRange`. Werte außerhalb werden als `implausible` gespeichert, nicht verworfen, und erscheinen in keiner Auswertung.
- Unsicherheit: Jede Quelle bekommt eine dokumentierte Messmethode. Ring-SpO₂ ist eine Fingermessung ohne klinische Validierung und wird so gekennzeichnet.

## 4. Dubletten und Quellen
Wie bisher: Schlüssel A (Quelle + ID), B (Gerät + Art + Zeit), C (Art + Zeitfenster quellenübergreifend, nur für die Anzeige). Quellenwahl ohne Mittelwertbildung (`SourcePolicy`). HealthKit-Werte, die PULSE ONE selbst geschrieben hätte, werden über `HKSource` erkannt. Schreiben ist heute aus.

## 5. Langzeitarchiv und Aggregate
- **Rohdaten:** `StoredSample`, unbegrenzt aufbewahrt. Schätzung: Ring-Puls alle 5–15 min ≈ 100–300 Werte/Tag, also ≈ 0,1 Mio. Zeilen pro Jahr. Mit `#Index` (iOS 18) auf `(kindRaw, start)` und `(profileID, kindRaw, start)` ist das für SwiftData unkritisch.
- **Aggregate (neu, Release 1/2):** `StoredAggregate` mit eindeutigem Schlüssel `profil|art|stufe|lokalerBeginn|quelle` und den Stufen Stunde, Tag, Woche, Monat. Felder: n, min, max, Mittel, Median, Summe, Abdeckung (Minuten mit Daten / Minuten im Fenster), `computedAt`, `algorithmVersion`.
- **Berechnung:** Nach jedem Import werden nur die betroffenen lokalen Tage neu berechnet. Woche und Monat entstehen aus den Tageswerten. Für HealthKit-Summen (Schritte, Energie, Strecke) gilt `HKStatisticsCollectionQueryDescriptor`, weil dort iPhone und Uhr korrekt verrechnet werden. Dazu kommen 7 Tage Lookback und einmal im Monat eine Vollberechnung (Konzept PulsHealth).
- **Zeitzone:** Tage sind **lokale Kalendertage** in der Zeitzone der Messung (`timeZoneIdentifier`), nicht UTC.
- **Abdeckung und Lücken:** Pro Art und Tag wird erwartet / vorhanden / Lücken > Taktung × 3 gespeichert. Die erwartete Taktung kommt aus der Ring-Einstellung (`0x16`) oder wird beobachtet.

## 6. Migration und Sicherung
- Ab Release 1: `VersionedSchema` V1 (heutiger Stand) → V2 (Aggregate, neue Arten, Kontext). Jede Migration bekommt einen Test mit einem Speicher der Vorversion.
- **Export:** JSON-Lines je Art plus `manifest.json` (Version, Zeitraum, Anzahl, Prüfsumme) als ZIP über das Teilen-Menü. CSV für Tabellen.
- **Wiederherstellung:** Import derselben Datei, idempotent über die Dublettenschlüssel.
- **Löschung:** je Quelle, je Zeitraum, alles. Aggregate werden danach neu berechnet.

## 7. Profile
Personenbezug über `ProfileAssignment` mit Zeiträumen (Review 3.2). Apple Health gehört immer dem iPhone-Besitzer. Ein Ring kann zeitweise einer anderen Person zugeordnet sein.
