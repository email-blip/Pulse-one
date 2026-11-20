# Antwort auf Codex-Review P1-003 R1, R2 und R3 (2026-11-20)

Geprüft gegen PR #17 (Stand `34fb7ad`). Alle Befunde aus R1 sind **bestätigt**. R2 und R3 sind eingearbeitet. Dieses Dokument beschreibt den **endgültigen Code** des Review-PRs; frühere Zwischenstände (z. B. Löschen alter Zeilen) gibt es nicht mehr.

- Tests: `Packages/PulseCore/Tests/PulseCoreTests/ReviewR1Tests.swift` (Swift Testing, Kernlogik) und `apps/PulseOne/IntegrationTests/HealthMigrationStoreTests.swift` (echtes SwiftData).
- Stufe nach Master-Directive §14: Implementiert. „Gebaut“ und „getestet“ gelten erst mit grüner CI; die Laufnummer steht im PR. Am iPhone ist nichts davon bestätigt.

## F1 / R2-1 / R3-2 – Handgelenktemperatur und verlustfreie Umstellung

- **Beleg:** `HealthKitAdapter` mappte `.appleSleepingWristTemperature` auf `.skinTemperatureDeviation`. Deren Bereich ist −5…5, also wurde ein absoluter Wert wie 34,6 °C als `implausible` gespeichert und fiel aus jeder Auswertung.
- **Korrektur Import:** Das Mapping geht auf `.skinTemperature` (absolut, 20…42 °C). Eine Abweichung wird nie importiert; sie entsteht später nur aus unserer eigenen Basislinie.
- **Bestehende Zeilen werden umgetypt, nicht gelöscht.** `HealthImportMigration` (PulseCore) wählt nur Zeilen mit `source == appleHealth`, `deviceID == "healthkit"` und `kind == skinTemperatureDeviation`. Jede bekommt in place:
  - Art `skinTemperature`,
  - den neuen Dedup-Schlüssel,
  - eine neu berechnete Qualität.
  - ID, Person, Wert, Zeit und Herkunft bleiben.
  - Entfernt wird nur eine Zeile, deren korrigierter Schlüssel schon gespeichert ist (bewiesene Dublette).
  - Ring-, manuelle und andere Health-Zeilen werden nie angefasst.
  - Zeilen älter als 30 Tage bleiben erhalten und werden genauso repariert.
- **Eine Transaktion:** `SampleStore.syncHealth` → `HealthSyncTransaction.run`.
  - Migration (`stageHealthMigration`) und Import (`stageIngest`) werden im selben `ModelContext` nur vorgemerkt, dann folgt genau ein `save()`.
  - Bei jedem Fehler: `context.rollback()`, und der gespeicherte Cursor bleibt alt. Der nächste Start wiederholt den ganzen Lauf.
  - Der Cursor rückt erst nach erfolgreichem Speichern vor. Ein zweiter Lauf findet nichts mehr.
- **Cursorformate (`HealthImportCursor`):**
  - Format 1 (ohne Marke): ein Neuimport des 30-Tage-Fensters, damit neuere Zeilen ihre Herkunft bekommen, plus die Umtypisierung.
  - Format 2: aktuell.
  - Ein unbekanntes, neueres Format wird nicht migriert. Seine Anker bleiben, und seine Nummer bleibt beim Schreiben erhalten.
- **Tests Kernlogik:** `absoluteWristValueIsPlausibleSkinTemperature`, `oldMappingAsDeviationWasRejected`, `oldCursorForcesOneReimportThenStaysStable`, `wrongRowsAreRetypedInPlaceNotDeleted`, `onlyAProvenDuplicateIsRemoved`, `rowOlderThanTheReimportWindowIsKept`, `failedWristQueryStillRepairsAndLaterImportDoesNotDuplicate`, `saveFailureRollsBackAndKeepsTheOldCursor`, `restartAfterFailureRepeatsAndSecondRunIsANoOp`, `unknownNewerFormatIsNotMigratedAndKeepsItsAnchors`.
- **Tests echtes SwiftData** (neues Target `PulseOneIntegrationTests`, In-Memory-`ModelContainer`, echte `StoredSample`/`SampleStore`, synthetische Werte):
  - `oldKeyBecomesTheCorrectKeyOnTheSameRow`: `@Attribute(.unique)`-Umschlüsselung.
  - `reimportInTheSameTransactionCreatesNoDuplicate`: Fetch mit vorgemerkten Änderungen.
  - `provenDuplicateIsRemovedAndTheCorrectRowStays`.
  - `rowOlderThanThirtyDaysIsKept`.
  - `injectedSaveFailureRollsBackThenRetrySucceeds`: echtes `context.rollback()`, danach Fetch und Wiederholung.
  - `repeatingAfterSuccessChangesNothing`.
  - `otherRowsAreNeverTouched`.

## F2 / R2-2 – Herkunft je Gerät, Summen nur vorläufig

- **Beleg:** Alle Health-Samples hatten `deviceID = "healthkit"`. `resolveTotal` addierte innerhalb einer Stunde alle Health-Beiträge, auch überlappende Werte mehrerer Geräte.
- **Herkunft:** `originDetail = HealthOrigin.detail(bundle:model:localIdentifier:)` hat die Form `bundle|modell|dev-<hash>`.
  - Der Hash ist FNV-1a 64 Bit über `HKDevice.localIdentifier`, stabil über Starts.
  - Seriennummer und Gerätename werden nicht gespeichert.
  - Fehlt die Kennung, steht dort `unbekannt`; sie wird nie aus dem Modell geraten.
  - Das Feld läuft durch `RawObservation`, `HealthSample` und `StoredSample` (optional, leichte SwiftData-Migration).
- **Summenregel (vorläufig):** Pro Stunde und Ursprung zählt nur ein `originDetail`, das mit der größten Summe. Ring und Health werden nie in derselben Stunde addiert. Das ist eine Heuristik, kein Nachbau von HKStatistics.
- **Pflichtmetadaten:** `ResolvedTotal.caveats` und `DailyValue.caveats` (`TotalCaveat`):
  - `healthRawSamples`: aus Health-Einzelwerten summiert.
  - `overlapDropped`: die Regel hat etwas weggelassen.
  - `unknownOrigin`: Werte ohne Geräteidentität, darunter alle Altzeilen ohne Herkunft.
  - `isProvisional` ist bei jeder Health-Summe wahr. Es wird kein genauer Apple-Health-Gesamtwert behauptet.
  - Jede spätere Summenanzeige (HEUTE) und der Export müssen `caveats` zeigen und mitführen; das ist Abnahmekriterium dieser Funktionen. Genaue Tageswerte erst mit `HKStatisticsCollectionQuery`.
- **Tests:** `overlappingIPhoneAndWatchStepsCountOnce`, `samplesOfOneOriginInOneHourStillAddUp`, `differentHoursMayUseDifferentDevices`, `ringAndHealthAreNeverAddedInTheSameHour`, `resyncFillsOriginOnExistingRowWithoutDuplicate`, `laterDeletionInHealthRemovesTheRow`, `sameAppSameModelDifferentDevicesStayApart`, `missingIdentityStaysUnknown`, `twoPhonesOfTheSameModelAreNotMerged`, `healthTotalsAreAlwaysMarkedProvisional`, `historicRowsWithoutOriginAreNotTreatedAsSolved`, `dailyValueKeepsTheCaveats`, `ringTotalsCarryNoHealthCaveat`.

## F3 / R2-3 / R3-1 – Bluetooth-Handshake und Lebenszyklus

- **Beleg R1:**
  - Nach `didConnect` gab es kein Zeitlimit mehr.
  - Fehler der Merkmalsuche wurden ignoriert.
  - `.ready` kam allein durch Notify, auch ohne Schreibkanal.
- **Handshake (`RingHandshake`, PulseCore):**
  - Reihenfolge: verbinden → Dienste → UART-Merkmale (Schreiben **und** Benachrichtigen, jeweils mit passender Eigenschaft) → Notify an → bereit.
  - Zeitlimits: 15 s Verbindung, 15 s Einrichtung.
  - Fehler brechen mit klarer Meldung ab.
  - `startHeartRate` verlangt `isReady` und einen Schreibkanal.
- **Freigabe der alten Verbindung (R3-1):** `cancelPeripheralConnection` blockiert nicht, und offene Operationen können noch abschließen (Apple-Doku). Deshalb gilt ein getrennter Link nur mit Nachweis als frei:
  - durch `didDisconnectPeripheral` für genau dieses Peripheral, oder
  - durch `CBPeripheral.state == .disconnected` (vom Treiber jede Sekunde geprüft), oder
  - wenn Bluetooth ausgeschaltet wird.
- **Solange der Nachweis fehlt, wird nicht verbunden.**
  - Ein neuer Verbindungswunsch wartet höchstens `cancelAckTimeout` (2 s).
  - Fehlt der Nachweis dann noch, bricht er mit `releaseTimeout` ab: „Die alte Verbindung zum Ring ist noch nicht beendet. Bitte gleich noch einmal tippen oder Bluetooth kurz aus- und einschalten.“
  - Es wird **nicht blind neu verbunden**. Das nächste Tippen sendet das Trennen erneut und wartet wieder.
  - Ein später `didDisconnect` beweist nur die Freigabe und startet nichts von selbst.
  - Ein `didDisconnect` während eines neuen Verbindungsaufbaus ändert nichts. CoreBluetooth meldet Fehlschläge vor `didConnect` über `didFailToConnect` (eigenes Ereignis `connectFailed`).
- **Kein Sitzungsschutz nur über die UUID:**
  - `didConnect` wird nur angenommen, wenn ein Schritt es erwartet und keine Freigabe aussteht; sonst wird abgelehnt und getrennt.
  - Notify-Status und Ringantworten zählen nur, wenn das Characteristic-**Objekt** (`===`) das ist, das die laufende Merkmalsuche geliefert hat. Objekte einer früheren Suche mit derselben UUID werden verworfen.
- **Grenze:** CoreBluetooth hat keine Sitzungs-ID. Der Objektvergleich setzt voraus, dass CoreBluetooth je Merkmalsuche neue Objekte liefert; das ist durch Gerätemitschnitt zu bestätigen. Die CoreBluetooth-Anbindung selbst ist ohne Gerät nicht testbar. Im Diagnose-Mitschnitt stehen die Zeilen „Bereit: …“, „Einrichtung abgebrochen: …“, „Alte Verbindung bestätigt beendet“ und „… laut Bluetooth-Status beendet“.
- **Abgrenzung:** Das schließt Robustheitslücken. Es ist **nicht** die belegte Ursache des R03-Pulsfehlers; dafür fehlt weiter der Gerätemitschnitt. Keine Protokolländerung.
- **Tests:**
  - Handshake-Kette: `fullChainBecomesReady`, `connectWithoutAnswerTimesOut`, `missingNotifyAckTimesOut`, `missingWriteOrNotifyFails`, `discoveryErrorsFail`, `notifyRefusedFails`, `notifyBeforeCharacteristicsDoesNotMakeReady`, `readyStaysReadyOnTicks`.
  - Lebenszyklus: `lateDidConnectAfterManualDisconnectIsRejected`, `newConnectWaitsForTheOldLinkAndLateCallbacksCannotFinishIt`, `automaticReconnectAcceptsTheReturningRing`, `failureStaysVisibleUntilTheNextRequest`, `connectFailureEndsTheAttempt`, `failedHandshakeKeepsItsMessageWhileTheLinkIsReleased`.
  - Codex-Gegenbeispiel mit spätem `disconnected` nach dem Timeout: `missingCancelAckAbortsTheQueuedConnectInsteadOfConnectingBlindly`.
  - Freigabe: `strayDisconnectDoesNotResetANewAttempt`, `observedReleaseStartsTheQueuedConnect`, `requestWhileReleaseIsStillUnprovenRetriesTheCancel`.

## Visuelle Befunde

| Befund | Stand |
|---|---|
| Häkchen bei „implementiert, ungetestet“ | Behoben: Häkchen nur bei „bestätigt“, Sanduhr bei „ungetestet“, Fragezeichen bei „Protokoll unbekannt“ (`DevicesScreen.symbol(for:)`) |
| „3:32 PM“ | Ursache: Simulator in US-Sprache. Screenshots laufen jetzt mit `-AppleLanguages (de) -AppleLocale de_DE`. Auf einem deutschen iPhone zeigt die App ohnehin 24 h, weil sie das Systemformat nutzt. |
| Heart Chamber nicht anatomisch | Bestätigt. Die App sagt jetzt „Schematisches Herzmodell, keine anatomische Darstellung“. Ein besseres Asset kommt erst nach den Kernfunktionen und nach Lizenzprüfung. |

## Nebenbefund TestFlight 5

Der Upload wurde abgelehnt: „bundle version must be higher than … ‘1’“. Grund: XcodeGen schreibt ohne Angabe `CFBundleVersion = 1` in die Info.plist, der Workflow-Wert `CURRENT_PROJECT_VERSION` kam dort nie an. Schon Build 4 lief deshalb als Nummer 1. Korrektur in `project.yml`: `CFBundleVersion: $(CURRENT_PROJECT_VERSION)`, `CFBundleShortVersionString: $(MARKETING_VERSION)`. Signierung und Secrets bleiben unverändert.
