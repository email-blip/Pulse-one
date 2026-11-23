# Vorgaben von Johannes (über ChatGPT), 2026-11-23 – verdichtet

Original: Nachricht von Johannes im Projektchat, 2026-11-23 13:34. Bei Zweifel gilt das Original; der Koordinator hängt es jedem Team-Thread an. Diese Fassung hält jede verbindliche Regel fest, ohne die Fließtexte.

## A. Produkt
- Drei Bereiche: **Dashboard** (frei anordenbare Kacheln, Coach-Deutung zuerst, direkter Einstieg in Messwert, Schlaf, nächste Aktivität), **Verlauf** (synchronisierte Zeitspuren wie ein Audioeditor: verschieben, zoomen, Zeitcursor, Messpunkte untersuchen; Hypnogramm mit echten Phasen und Uhrzeiten; Ereignisse, Training, Coach-Erkenntnisse auf derselben Achse), **Coach** (derselbe Charakter, Tagesplan, animierte Übungen, gesprochene Ansagen, Gespräch ohne Wechsel zu einer anderen KI).
- Kein Ernährungsbereich. Keine getrennten Persönlichkeiten. Keine Sammlung isolierter KI-Werkzeuge. Arbeitsname **ROOK**.
- Am Ende: genau eine App-Shell, ein Datenmodell, ein Coach, ein Audio-Koordinator, eine Trainingszustandsmaschine.

## B. Bestand zuerst
Repo/Branch/SHA, laufende Arbeiten, aktive Threads, Dateibesitz, Sicherungspunkt, Datenbankversion, Rückfall-Installation erfassen. Kein unkontrolliertes Löschen, keine Vernichtung von Messdaten. Alte Oberflächen erst nach erfolgreichem Ersatz entfernen.

## C. Threadbaum
00 Leitstand/Architektur/Integration · 01 Daten/R03/HealthKit/Schlaf · 02 Design-System/Motion/Assets · 03 Dashboard/Zeitspuren/Diagramme · 04 Coach Intelligence/Interpretation/Gedächtnis · 05 Sprache/Training/Timer/Mitteilungen · 06 QA/Performance/Release. 00 ist einziger Integrator und einziger TestFlight-Uploader. Bestehende Threads zuordnen statt neue gleichartige. Keine erfundenen Teams oder Rückmeldungen.

## D. Verträge vor Parallelarbeit
Measurement, SleepSegment, TimelineState, CoachInsight, WorkoutSession, DashboardLayout (Felder siehe `VERTRAEGE.md`). Ein Zustand speist Bildschirm, Ansage, Mitteilung, Diagrammannotation, Trainingssteuerung (nie „Pause“ auf dem Bildschirm, während die Stimme weitertreibt).

## E. Design
Palette Obsidian #070D19, Bio Cyan #15D9F3, Neural Violet #9B70FF, Pulse Coral #FF644F, Ice White #E6F4FA. Große klare Typografie, starke Zahlenhierarchie, Tiefe durch Material und Licht, große Touchflächen, wenige wiederverwendete Komponenten, keine dekorative Dauerunruhe. Motion nur mit Bedeutung (neue Messung, Zeitraumwechsel, Punktauswahl, Kachelwechsel, Übungsbeginn, Phasenende, Insight → Belege). Neue Daten bewegen sich an ihre echte Zeitposition; historische Daten nicht als „gerade gemessen“ inszenieren. Keine künstliche EKG-Kurve aus BPM, keine erfundenen Zwischenpunkte. Reduce Motion: gleiche Funktionen, weniger Raumbewegung. Farbe nie einzige Bedeutung.

## F. Dashboard
Reihenfolge: Begrüßung + Deutung → eine Handlung → Kacheln → Schlafvorschau/Ereignisse. Coach-Bereich: Name + Identität, 2–3 Sätze, Vorlesen/Stoppen, „Warum?“, direkte Handlung. Kachel: Name, aktueller/letzter gültiger Wert, Einheit, kleiner Verlauf, Bezugszeitraum, Antippen → Verlauf. Bearbeiten: lang drücken + ziehen, sichtbarer Einfügeplatz, flüssiger Wechsel, ein/aus, Größen, pro Profil gespeichert, barrierefreie Alternative. Nicht unterstützte Messart erzeugt keine falsche Zahl; Coach zählt keine fehlenden Felder auf; technischer Status diskret erreichbar.

## G. Verlauf
Tag, Woche, Monat, 3 Monate, Jahr. Im Tag: Pan, Pinch-Zoom, gemeinsamer senkrechter Cursor, Auswahl per Berühren/Ziehen, Übergang Übersicht ↔ Originalauflösung. Spuren: Puls, HRV, SpO₂, Schlafphasen, Bewegung, Training, Notizen, Coach-Erkenntnisse – eine absolute Zeitdomäne. Auswahl zeigt echte Messzeit, Wert, Einheit, Quelle auf Nachfrage, zugehörige Deutung. Cursor zwischen Punkten → kein künstlicher Wert. Lücken sichtbar, nicht als Null, keine langen Verbindungslinien. Große Zeiträume performant aggregieren, Spitzen erhalten, Aggregation kenntlich. Messzeit, Importzeit, Animationszeit unterscheiden. Swift Charts (ChartProxy, Auswahl, Scrollposition); Canvas/Metal nur mit belegtem Bedarf.

## H. Schlaf
Kette Ringhistorie → Rohpakete → Phasencodes → Intervalle → Persistenz → Hypnogramm → Auswahl → Coach. Gegen Gadgetbridge und R03-Mitschnitte prüfen; REM firmwareabhängig, nicht pauschal ausschließen. Wach/REM/Leicht/Tief soweit geliefert, unbekannte Phasen gesondert, echte Zeiten, Dauer des Abschnitts, gleiche Achse wie Puls/Bewegung, Tageswechsel und Sommerzeit korrekt. Dauer aus Intervallen; Zeit im Bett ≠ Schlaf. Keine 90-Minuten-Schablone, keine dekorativen REM-Abschnitte.

## I. Coach
Interpretation → Richtung → nächste Handlung, max. 3 kurze Sätze. Direkt, locker, natürlich, aufmerksam, gelegentlich trockener Humor; keine Werbesprache, keine Schuld, keine übertriebene Begeisterung. Nicht routinemäßig: „Ich bin kein Arzt“, „Ich konnte diesen Wert nicht lesen“, Sync-Berichte, Zahlenwiederholung, Vorbehaltstexte. „Warum?“: Messwerte, Vergleichszeitraum, Ereignisse, Berechnung, Alternativen, Unsicherheit. Keine erfundene Sicherheit, keine unbelegten Diagnosen/Ursachen/Prozente; Warnzeichen klar zur Abklärung; keine Medikamentenänderung. Ohne Messgrundlage: normal begrüßen, Interaktion anbieten. Verarbeitet „Das passt nicht“, „Ich bin krank“, „Heute nur zehn Minuten“, „Keine Klimmzugstange“, „Leichtere Variante“, „Warum diese Empfehlung?“.
Fachbro-Ergänzung: herzlich, direkt, gelegentlich frech; „Bro/Junge/mein Freund“ selten. Fragt „Fühlst du dich auch so?“ und passt an. Fordern, fördern, bremsen; konkretes Lob. Meldet sich nur mit Anlass; „Heute Ruhe“, „Weniger antreiben“, „Sei direkter“, „Erinnere mich später“. Ignorieren ≠ Zustimmung. Bettgeh-Erinnerung nach Tagesplan; Wecken nur über eingerichteten Wecker. Nachfassen morgens → nachmittags → abends; Empfehlung, Antwort und spätere Beobachtung getrennt speichern. Regelmäßige Fragen: Was entwickelt sich gut? Was verändert sich auffällig? Welche Erklärung passt? Was ist heute sinnvoll? Was prüfen wir später?

## J. Sprache
AVSpeechSynthesizer mit bester deutscher Systemstimme, zentraler Audio-Koordinator, Stopp/Pause/Weiter, Unterbrechungen und Ausgabewechsel. Beim Öffnen: Beitrag sofort zeigen, Begrüßung nach Sprachpräferenz, nicht bei jedem Tabwechsel, keine Überlappung. Training: Übung ankündigen, Technikhinweise, Phasenwechsel, Abschluss; veraltete Ansagen bei Pause/Überspringen verwerfen. Kopfhörerverlust/Anruf: unterbrechen, sensible Inhalte nicht über Lautsprecher fortsetzen. Spracheingabe iOS-18-tauglich, neuere APIs mit Availability, Mikrofon nur bei bewusster Interaktion. Externe Premium-Stimme nur später mit Kosten/Empfänger-Offenlegung. Aussprachetests für Zahlen, „HRV“, Uhrzeiten, Übungsnamen. Später sherpa-onnx prüfen.

## K. Training
Ziele, Niveau, Ausrüstung, Zeit, Einschränkungen nutzen; nichts Pauschales. Einheit: Übung, Variante, Zeit/Wiederholungen, Arbeit/Pause, animierte Demonstration, Alternative, Technikhinweise. Start/Pause/Fortsetzen/Überspringen/Beenden. Große Übung, sichtbare Bewegung, klarer Timer, nächste Phase, deutlicher Start-/Endreiz. Timer aus Zeitstempeln, nach Sperren korrekt, Phasenende per lokaler Mitteilung, AlarmKit nur ab unterstützter iOS-Version, Live Activity als Anzeige derselben Session. Danach: Zusammenfassung, Anstrengung abfragen, gemessene Reaktion, nächster Vorschlag. Durchführung, Pulsreaktion, langfristige Wirkung trennen; fehlender Pulsanstieg ≠ „zu leicht“/„faul“. Bewegungsclips fachlich prüfen.

## L. Automatik und Ring
Freigegeben: automatische minimierte Claude-Zusammenfassungen, begrenzte KI-Kosten, Ring im Hintergrund. Getrennt prüfen: BLE verbunden / Historie synchronisiert / neue Messung / nutzbarer Live-Stream. CoreBluetooth-Hintergrund + State Restoration, HealthKit-Änderungshinweise, BackgroundTasks, App-Öffnen; keine doppelten Checks. Gesperrt, Suspendierung, Reichweite, Reconnect, Bluetooth aus/an, Neustart, manuell beendet prüfen. TN3115 differenziert; AccessorySetupKit nicht pauschal Pflicht. Mitteilungen mit konkreter Aktion, keine Mahnung für Erledigtes, Ruhezeiten/Limits/„heute nicht“; kein identischer Push ohne neuen Erkenntnisstand.

## M. Schritte und Abnahme
A Bestand + Marktvergleich → B Plan → C durchgängiger Prototyp (öffnen → Begrüßung → Kachel → Cursor → Schlafphase → Rückfrage → Einheit → Pause → Abschluss) → D reale Daten/Migration → E Sprache/Training → F Integration (nur 00) → G TestFlight (Version/Buildnummer prüfen, Upload und Verfügbarkeit getrennt bestätigen). Abnahme-Video mit 12 Punkten (Plan §8) plus Prüfungen: volle Nacht, Nacht mit Lücke, unbekannter Code, Doppel-Sync, falsches Profil, veralteter Wert, unregelmäßige Abstände, Sommerzeit/Zeitzone, offline, KI-Fehler/Budgetende, Anruf/Kopfhörer, abgelehnte Berechtigungen, XXXL, Reduce Motion. Performance: flüssiges Scrubbing, 60 fps als Ziel, keine Daueranimation unsichtbarer Ansichten.

## N. Medienbibliothek
Kuratierte, lokal gebündelte Assets (offline). Quellen: Poly Haven, ambientCG, MakeHuman/MPFB, Mixamo, Quaternius, NIH 3D, Kenney, LottieFiles, Freesound (CC0/CC BY), Sonniss GDC. Bibliotheks-, Datei- und API-Lizenz getrennt prüfen. Laufzeit: SwiftUI/Charts, RealityKit/Metal, Rive für Charakterzustände, Lottie nur bei Bedarf, AVSpeechSynthesizer, Core Haptics/AVFoundation; Inferno/AudioKit nur mit Zusatznutzen; nicht alles vorsorglich installieren. Register je Asset: ID, Quelle, Autor, Lizenz, Nachweis, Version, Prüfsumme, Format, Größe, Verwendung, Attribution; Original und optimierte Fassung getrennt. 3D-Pipeline: auswählen → Rig/Bewegung prüfen → Materialien vereinheitlichen → reduzieren → USDZ → iPhone-Test. Einheitlicher Stil (keine Mischung Comic/Anatomie/Stock). Klangfamilie: Begrüßung, Start, Pause, Phasenwechsel, Abschluss, wichtiger Hinweis; nicht jeder Messpunkt braucht Ton. Keine Gesundheitsdaten an Asset-Plattformen.
Erste Medienlieferung: Körpermodell-Kandidat, zwei geprüfte Bewegungsanimationen, ein interaktiver Begleiterzustand, drei Sounds, eine deutsche Stimme, gesprochener Rückblick mit synchronem Zeitcursor, positive und auffällige Deutung mit „Warum?“ – mit Asset-IDs, Lizenznachweisen, Dateigrößen und Video.

## O. Besondere Funktionen (später, M3)
Belastungs-Echo, gezielte Rückfrage, Audio-Zeitverlauf, nachfassender Coach, persönliche Wirkungskarte, Gesundheitschronik mit Wendepunkten, „fitter oder nur weniger belastet?“. Jede mit Daten, Vergleichbarkeit, Berechnung, Grenzen, Testfällen, Abnahmekriterien.
