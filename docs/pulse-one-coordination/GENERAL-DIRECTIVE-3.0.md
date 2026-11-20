# PULSE ONE – General Directive 3.0 (Codex)

> Von Johannes am 2026-11-20 16:49 UTC im Projekt übermittelt, wortgetreu. Ersetzt als Steuerungsdokument die Reihenfolge der MASTER-DIRECTIVE (§15–17); deren Regeln gelten weiter, soweit sie nicht widersprechen.
>
> Lesart Claude: „MyBody-Codebasis“ meint hier den bestehenden PULSE-ONE-Stand in diesem Repo (aus dem die zitierte Gap-Analyse stammt). Die Expo-App MyBody im Repo MyBotty bleibt nach Johannes' Entscheidung vom 2026-11-20 15:32 unverändert. Kein Neustart.

PULSE ONE – GENERAL DIRECTIVE 3.0

Verbindliche Entwicklungsanweisung an Codex und Claude Code

Stand: 20. November 2026
Ausgangsprojekt: MyBody
Produktname: PULSE ONE
Leitmotiv: ONE BODY. MANY WORLDS.
Entwicklungsleiter: Codex
Ausführender Hauptentwickler: Claude Code

⸻

1. VERBINDLICHE GRUNDSATZENTSCHEIDUNG

PULSE ONE wird eine native, modulare iOS-Plattform für persönliche Gesundheitsdaten, körperliche Aktivität, Training, Regeneration und individuelle Bewegungsbegleitung.

Die App verbindet reale Sensordaten mit einer intelligenten Trainingssteuerung und einer außergewöhnlich hochwertigen interaktiven 3D-Oberfläche.

Das Produkt darf weder zu einem gewöhnlichen Fitness-Dashboard noch zu einer technisch eindrucksvollen, aber funktional wertlosen 3D-Demo werden.

Codex übernimmt die Entwicklungsleitung und kontrolliert Claude Code hinsichtlich Architektur, Funktionsumfang, Designqualität, Tests und Entwicklungsfortschritt.

Claude Code bleibt der ausführende Entwickler.

Die bestehende MyBody-Codebasis wird weiterentwickelt. Kein unnötiger Neustart, keine parallele Neuentwicklung.

⸻

2. BESTÄTIGTER AUSGANGSSTAND

Laut Claudes Gap-Analyse vom 20.11.2026:

Implementiert beziehungsweise gemeldet:

* Grundlegende Colmi-R03-Bluetooth-Anbindung
* Gerätesuche und Verbindung
* Verbindungsstatus
* Erste Messwertverarbeitung
* Datenmodell und Pipeline
* Simulator-UI-Test
* CI mit Accessibility-Prüfung
* Koordinationsverzeichnis docs/pulse-one-coordination/

Nicht durch reale Hardware bestätigt:

* Tatsächliche R03-Verbindung am iPhone
* Zuverlässige Übertragung echter Messwerte
* Installierbare TestFlight-Version

Noch nicht implementiert:

* HealthKit
* Mehrpersonenprofile
* Vollständiges Onboarding
* Oura-Integration
* Universelle Geräteadapter
* Individueller Tagescoach
* KI-gestützte Trainingsbegleitung
* Anatomisches 3D-Herz
* Realistischer 3D-Mensch
* Sleep Universe
* Vital Orbit
* Time Machine
* Sportwelten
* Vier vollständige Designprofile
* Umfassendes Sound- und Haptiksystem

Diese Angaben stammen aus Claudes Bericht und müssen durch Code, Tests und Build-Artefakte überprüft werden.

⸻

3. NEUE ENTWICKLUNGSSTRATEGIE

Organisiere die Entwicklung in drei fachliche Stränge:

A – PULSE CONNECT

Geräte, Datenquellen, Bluetooth, HealthKit, Profile und Messdatenbank.

B – PULSE INTELLIGENCE

Gesundheitsanalysen, individuelle Basislinien, Trainingsplanung, täglicher Coach, KI und Motivation.

C – PULSE EXPERIENCE

3D-Mensch, Herz, Animationen, Grafik, Sound, Haptik, Navigation und Sportwelten.

Diese Stränge werden fachlich parallel geplant und in sinnvoller Reihenfolge umgesetzt.

Vermeide gleichzeitige unkoordinierte Schreibzugriffe auf dieselben Projektdateien.

⸻

TEIL A – PULSE CONNECT

4. UNIVERSAL DEVICE PLATFORM

PULSE ONE darf nicht fest auf den Colmi R03 zugeschnitten werden.

Entwickle eine herstellerübergreifende Geräteverwaltung.

Unterstützte Quellen

Colmi R03

Erstes vorhandenes Testgerät. Bestehende Implementierung überprüfen und auf echter Hardware validieren.

Colmi R09

Zweites bestelltes Gerät. Temperaturmessung und weitere Funktionen anhand der tatsächlichen Firmware und Protokollunterstützung prüfen.

Apple Health

Native HealthKit-Anbindung für autorisierte Gesundheits- und Trainingsdaten.

Oura Ring

Integration über die offizielle Oura API mit OAuth2. Keine unbestätigte direkte Bluetooth-Integration voraussetzen.

Weitere Wearables

Erweiterbare Unterstützung für:

* Smart Rings
* Sensorarmbänder
* Oberarmsensoren
* Brustgurte
* Ohrclips
* Sensorbrillen
* Bewegungssensoren
* Weitere BLE-Geräte mit dokumentierten Standards oder Protokollen

Tier-Wearables

Architektonisch als eigene Profil- und Gerätekategorie vorsehen, aber nicht mit menschlichen Gesundheitsalgorithmen vermischen.

Architektur

Implementiere beziehungsweise konsolidiere:

* DeviceRegistry
* DeviceAdapter
* DeviceCapabilities
* BLEConnectionManager
* HealthKitAdapter
* OuraAPIAdapter
* MeasurementNormalizer
* SyncCoordinator
* DataSourceResolver
* DeviceDiagnostics

Jeder Adapter muss dokumentieren, welche Messwerte tatsächlich unterstützt werden.

Eine Bluetooth-Verbindung allein gilt nicht als erfolgreiche Sensorintegration.

Geräteverwaltung

Nutzer müssen Geräte selbst hinzufügen, koppeln, entfernen und einem Profil zuordnen können.

Die App zeigt:

* Gerätename
* Gerätetyp
* Verbindungsstatus
* Batteriestand, falls verfügbar
* Synchronisierungsstatus
* Unterstützte Messwerte
* Letzte erfolgreiche Messung
* Fehler und Diagnosehinweise

⸻

5. EINHEITLICHE GESUNDHEITSDATENBANK

Baue eine lokale, strukturierte Gesundheitsdatenhaltung mit SwiftData oder einer begründet geeigneteren Persistenz.

Jeder Messwert enthält mindestens:

* Profil-ID
* Quelle
* Gerät
* Messwerttyp
* Wert
* Einheit
* Messzeitpunkt
* Importzeitpunkt
* Quellenkennung
* Qualitätsstatus
* Messmethode, soweit bekannt

Unterstützte Messwertgruppen:

* Herzfrequenz
* Ruhepuls
* HRV
* Sauerstoffsättigung
* Hauttemperatur
* Schritte
* Aktivität
* Schlafdauer
* Schlafphasen
* Trainingsbelastung
* Trainingsdauer
* GPS und Höhenmeter, soweit verfügbar
* Manuelle Trainingsdaten

Implementiere Datenvalidierung, Einheitenkonvertierung, Dublettenerkennung und nachvollziehbare Quellenpriorisierung.

Verhindere, dass mehrfach synchronisierte Messwerte mehrfach gezählt werden.

Trenne Rohmessungen, berechnete Kennzahlen und KI-generierte Interpretationen.

⸻

6. MULTIPROFIL UND ONBOARDING

Die App wird für beliebige Nutzer entwickelt.

Implementiere einen hochwertigen Erststart-Assistenten:

1. Willkommen bei PULSE ONE
2. Profil erstellen
3. Körperdaten
4. Trainingsstand
5. Gesundheitsbezogene Einschränkungen
6. Persönliche Ziele
7. Bevorzugte Sportarten
8. Verfügbare Trainingszeit
9. Coach-Persönlichkeit
10. Designprofil
11. Apple Health verbinden
12. Bluetooth-Geräte hinzufügen
13. Digitalen Zwilling konfigurieren
14. Persönliches Dashboard öffnen

Unterstütze mehrere lokal verwaltete Profile.

Jedes Profil besitzt eigene Geräte, Ziele, Aktivitäten, Einstellungen und Daten.

HealthKit-Daten dürfen nicht durch einen lokalen Profilwechsel einer anderen Person zugeordnet werden.

Onboarding-Schritte müssen überspringbar und später nachholbar sein.

⸻

TEIL B – PULSE INTELLIGENCE

7. PULSE COACH – ZENTRALE PRODUKTFUNKTION

PULSE ONE soll ein persönlicher Bewegungsbegleiter werden.

Der Coach erstellt täglich individuelle Aktivitätsprogramme.

Berücksichtige:

* Alter
* Körpergröße
* Gewicht
* Trainingsstand
* Trainingsziele
* Bevorzugte Sportarten
* Schlaf
* Ruhepuls
* HRV
* Belastungsverlauf
* Erholung
* Subjektive Tagesform
* Verfügbare Zeit
* Gesundheitliche Einschränkungen
* Tatsächlich erledigte Aktivitäten

Tagesprogramm

Jeder Tag erhält eine strukturierte Planung.

Morning Activation

Kurze Aktivierung am Morgen.

Beispiele: Mobilität, leichtes Krafttraining, Dehnen, Aktivierungsübungen.

Main Activity

Eine bevorzugte Sportart oder passende Alternative.

Beispiele: Reiten, Laufen, Radfahren, Krafttraining, Rudern, Fußball, Wandern.

Micro Moves

Kurze Bewegungseinheiten während des Tages.

Evening Reset

Regeneration, Mobilität oder Entspannung.

Jede Einheit enthält Dauer, Intensität, Wiederholungen, Pausen, Alternativen und Abschlussstatus.

Trainingslogik

Entwickle zunächst einen nachvollziehbaren regelbasierten Trainingsplaner.

Dieser nutzt persönliche Basislinien und dokumentierte Trainingsprinzipien.

Das System muss zwischen ausreichenden und unzureichenden Messdaten unterscheiden.

Keine pauschalen Trainingsvorgaben allein anhand von Körpergröße und Gewicht.

Keine erfundenen Readiness-Werte.

Lernfähigkeit

Der Coach berücksichtigt:

* Erledigte Übungen
* Ausgelassene Übungen
* Tatsächliche Belastung
* Subjektives Feedback
* Trainingsfortschritt
* Erholungsverlauf

Passe künftige Empfehlungen entsprechend an.

⸻

8. KI-COACH UND EIGENE API

Entwickle eine austauschbare KI-Schnittstelle.

Der Nutzer stellt später eine eigene API-Konfiguration zur Verfügung.

Implementiere:

* AIProvider-Protokoll
* Sichere API-Konfiguration
* Strukturierte Prompts
* Validierte JSON-Ausgaben
* Datenschutzfilter
* Fehlerbehandlung
* Offline-Fallback
* Versionierte Coach-Entscheidungen

API-Schlüssel dürfen nicht im Repository gespeichert werden.

Bei direkter Verbindung zu einem externen KI-Dienst dürfen Schlüssel nicht ungeschützt in der App verteilt werden. Prüfe eine sichere Backend-Vermittlung.

Die KI übernimmt:

* Natürliche Kommunikation
* Erklärung von Trainingsempfehlungen
* Motivation
* Anpassung innerhalb definierter Trainingsgrenzen
* Wochenrückblicke
* Zielgespräche

Die fachliche Belastungssteuerung bleibt durch nachvollziehbare Regeln abgesichert.

Persönlichkeit

Der Coach spricht locker, erwachsen, motivierend und direkt.

Beispiel:

„Morgen! Heute machen wir’s smart. Fünf Minuten mobilisieren, später eine lockere Reitrunde. Wenn du nicht aufs Pferd kommst, hab ich einen guten Alternativplan.“

Keine künstliche Euphorie.

Keine Schuldgefühle bei ausgelassenen Übungen.

⸻

9. PUSH, LIVE ACTIVITIES UND MOTIVATION

Implementiere:

* Morgendliche Tagesplanung
* Individuelle Aktivitätserinnerungen
* Bewegungspausen
* Trainingsstart
* Laufende Trainingseinheit
* Abschlussfeedback
* Abendrückblick
* Wochenanalyse
* Konfigurierbare Ruhezeiten

Nutze UserNotifications und gegebenenfalls ActivityKit.

Die Häufigkeit der Benachrichtigungen muss vom Nutzer steuerbar sein.

⸻

TEIL C – PULSE EXPERIENCE

10. VERBINDLICHER VISUELLER QUALITÄTSSTANDARD

PULSE ONE soll sich wie eine hochwertige native 3D-Anwendung anfühlen.

Nicht akzeptabel sind:

* Statische Bilder als angebliche 3D-Animation
* Einfache Kreise als endgültige Herzvisualisierung
* Überladene Standard-Dashboards
* Unmotivierte Glow-Effekte
* Billige Partikelanimationen
* Unpassende Stock-Assets
* Lange, blockierende Übergänge
* Grafische Effekte ohne funktionalen Nutzen

Technische Werkzeuge

Prüfe und verwende bei Eignung:

* SwiftUI
* RealityKit
* RealityView
* Metal
* Metal Shading Language
* Core Animation
* Core Haptics
* AVFoundation
* USD/USDZ
* Blender
* Reality Composer Pro
* Skeletal Animation
* Blend Shapes
* Physically Based Rendering
* GPU-Partikelsysteme
* Shader-basierte Materialübergänge

Verwende moderne stabile APIs, die mit der festgelegten iOS-Mindestversion kompatibel sind.

Keine unkontrollierte Abhängigkeit von experimentellen Frameworks.

⸻

11. LIVING TWIN – INTERAKTIVER 3D-MENSCH

Der digitale Zwilling wird zum visuellen Markenzeichen.

Vier verbindliche Zustände:

HUMAN

Realistischer 3D-Mensch mit:

* Anatomisch plausiblen Proportionen
* Hochwertigen Materialien
* Natürlich wirkender Beleuchtung
* Subtiler Atemanimation
* Freier Rotation
* Zoom
* Interaktiven Körperregionen

REVEAL

Die Körperoberfläche wird kontrolliert transparent.

Effekte:

* Animierte Scanlinien
* Räumliche Lichtbahnen
* Materialtransformation
* Sichtbar werdende anatomische Strukturen
* Flüssige Kamerafahrt

HOLOGRAM

Holografische Darstellung mit:

* Cyanfarbenen Konturen
* Violetten Lichtakzenten
* Transparenz
* Emission
* Räumlichen Partikeln
* Datenorbits

ORGAN FOCUS

Auswahl eines Körperbereichs mit Kamerafokus und passenden Daten.

Asset-Anweisung

Claude muss hochwertige lizenzierbare 3D-Menschmodelle evaluieren.

Prüfe Blender-kompatible Modelle, USDZ-Export, Rigging, Texturqualität und mobile Performance.

Erstelle eine Asset-Vergleichsmatrix mit:

* Visueller Qualität
* Anatomischer Eignung
* Animierbarkeit
* Dateigröße
* Lizenz
* Preis
* RealityKit-Kompatibilität

Keine kostenpflichtigen Assets ohne Freigabe kaufen.

⸻

12. HEART CHAMBER – ANATOMISCHES 3D-HERZ

Ersetze den bisherigen 2D-Puls-Orb langfristig durch ein echtes anatomisches 3D-Herz.

Anforderungen:

* Anatomisch plausibles Modell
* Räumliche Geometrie
* Hochwertige Materialien
* Animierte Kontraktion
* BPM-gesteuerte Frequenz
* Rotation
* Zoom
* Dynamische Beleuchtung
* Optionaler Herzschlagton
* Optionale synchronisierte Haptik
* Historische Herzfrequenzdaten

Eine BPM-gesteuerte Animation ist keine gemessene EKG-Kurve.

Der Nutzer muss diese Unterscheidung erkennen können.

⸻

13. WEITERE 3D-ERLEBNISSE

Sleep Universe

Räumliche Schlaf-Zeitlandschaft mit tatsächlichen Schlafdaten.

Vital Orbit

Interaktive Datenorbits um den digitalen Zwilling.

Time Machine

Historische Navigation durch Messwerte und Trainingszustände.

Sportwelten

Football Arena: Stadion, Belastung und Regeneration.

Strength Lab: Muskelkarte, Übungen und Kraftprogression.

Endurance Flow: Strecken, Pace und Herzfrequenzzonen.

Expedition Mode: Gelände, GPS und Höhenprofile.

Rowing Dynamics: Boot, Wasser, Schlagfrequenz und Leistungsdaten.

Jede Sportwelt benötigt eigene Interaktionen und eine eigenständige visuelle Gestaltung.

⸻

14. DESIGN UND NAVIGATION

Hauptnavigation:

* TODAY
* BODY
* MOVE
* TRENDS
* DEVICES

Farben

* Obsidian: #070D19
* Bio Cyan: #15D9F3
* Neural Violet: #9B70FF
* Pulse Coral: #FF644F
* Ice White: #E6F4FA

Vier Designprofile

* Neon Performance
* Obsidian Elite
* Nature Balance
* Clinical Light

Themes werden über gemeinsame Design Tokens und Komponenten umgesetzt.

Animation

Definiere ein konsistentes Motion-System für:

* Mikrointeraktionen
* Navigation
* Kartenübergänge
* Kamerafahrten
* Materialtransformation
* Hologramme
* Partikel
* Datenvisualisierung

Berücksichtige Reduce Motion, Batterieverbrauch und unterschiedliche iPhone-Leistungsklassen.

⸻

15. SOUND UND HAPTIK

Entwickle ein gemeinsames Feedbacksystem.

* Verbindungsbestätigung
* Trainingsstart
* Übungsabschluss
* Zielerreichung
* Herzschlaganimation
* Szenenwechsel

Verwende Core Haptics und AVFoundation.

Sound und Haptik müssen separat deaktivierbar sein.

Verwende nur geeignete lizenzierte oder selbst erstellte Audiodateien.

⸻

TEIL D – ENTWICKLUNGSSTEUERUNG

16. VERBINDLICHE NEUE REIHENFOLGE

Meilenstein 1 – FIRST DEVICE CONNECT

* R03-Implementierung prüfen
* Echten Ring am iPhone verbinden
* Tatsächlichen Messwert nachweisen
* iOS-Signierung abschließen
* Installierbare Testversion bereitstellen

Abnahme: Echte Hardware, echter Messwert, echte iPhone-Installation.

Meilenstein 2 – UNIVERSAL CONNECT

* Erweiterbare Geräteadapter
* Apple Health
* Geräteverwaltung
* Messdatenbank
* Datenquellenpriorisierung
* R09-Vorbereitung
* Oura-Adapterarchitektur

Abnahme: Mindestens R03 und Apple Health als reale Datenquellen nutzbar.

Meilenstein 3 – PERSONAL PULSE

* Mehrpersonenprofile
* Onboarding
* Sportpräferenzen
* Ziele
* Trainingsstand
* Persönliches Dashboard

Abnahme: Ein neuer Nutzer kann die App ohne Entwicklerunterstützung einrichten.

Meilenstein 4 – DAILY COACH

* Übungsbibliothek
* Regelbasierter Tagesplaner
* Individuelle Aktivitätsprogramme
* Fortschrittskontrolle
* Push-Erinnerungen
* Coach-Oberfläche

Abnahme: Ein echter Nutzer erhält einen nachvollziehbaren Tagesplan und kann ihn vollständig bearbeiten.

Meilenstein 5 – PREMIUM EXPERIENCE

* Professionelle Asset-Pipeline
* Rendering- und Motion-System
* Anatomisches 3D-Herz
* Living Twin
* Holografische Übergänge
* Sound und Haptik

Abnahme: Interaktive 3D-Erlebnisse auf echter iPhone-Hardware.

Meilenstein 6 – ADVANCED INTELLIGENCE

* Eigene KI-API
* Erweiterte Analysen
* HRV- und Schlaftrends
* Belastungssteuerung
* Oura-Integration
* R09-Integration
* Langfristige Personalisierung

Abnahme: Nachvollziehbare Empfehlungen auf Grundlage mehrerer realer Datenquellen.

Meilenstein 7 – SPORT UNIVERSE

* Fünf Sportwelten
* Sportartspezifische Analysen
* Trainingserfassung
* Historische Vergleiche

Meilenstein 8 – RELEASE QUALITY

* Vier Themes
* Performanceoptimierung
* Accessibility
* Datenschutz
* Langzeittests
* TestFlight
* Veröffentlichungsvorbereitung

⸻

17. VERPFLICHTENDE VISUELLE ABNAHME

Codex darf keine 3D-Funktion allein aufgrund eines erfolgreichen Builds abnehmen.

Fordere:

1. Tatsächliche Screenshots
2. Bildschirmaufnahmen der Animationen
3. Asset-Herkunft und Lizenz
4. Rendering-Technik
5. Performance-Messung
6. Speicherverbrauch
7. Test auf echter Hardware, sobald verfügbar

Bewerte:

* Anatomische Plausibilität
* Modellqualität
* Materialwirkung
* Beleuchtung
* Animationsqualität
* Übergänge
* Lesbarkeit
* Interaktion
* Framerate
* Batterieverbrauch

Erteile bei unzureichender Qualität konkrete Nachbesserungsaufträge.

⸻

18. QUALITÄTS- UND SICHERHEITSREGELN

Keine erfundenen Messwerte.

Keine medizinischen Diagnosen.

Keine ungeprüften BLE-Protokollannahmen.

Keine unlizenzierte Hardware- oder Asset-Nutzung.

Keine API-Schlüssel im Repository.

Keine externe Übermittlung sensibler Gesundheitsdaten ohne Einwilligung.

Keine unkoordinierten parallelen Änderungen.

Keine unbelegten Fertigmeldungen.

Jede Funktion wird eingestuft als:

* Geplant
* Implementiert
* Gebaut
* Im Simulator getestet
* Auf echter Hardware getestet
* Abgenommen

⸻

19. AUFTRAG AN CODEX – JETZT AUSFÜHREN

1. Übermittle Claude Code diese General Directive 3.0.
2. Bestätige die tatsächliche Übermittlung.
3. Gleiche sie mit dem aktuellen Repository ab.
4. Prüfe Claudes Gap-Analyse anhand des Codes.
5. Erstelle einen priorisierten Entwicklungs-Backlog.
6. Kläre den Blocker der iOS-Signierung.
7. Führe FIRST DEVICE CONNECT zum echten Hardwaretest.
8. Beginne anschließend die Universal-Connect-Architektur.
9. Starte parallel eine technische und gestalterische Evaluation für Heart Chamber und Living Twin.
10. Steuere Claude Code in überprüfbaren Einzelaufträgen weiter.

Ziel: PULSE ONE wird ein echter, intelligenter, individuell konfigurierbarer Gesundheits- und Bewegungsbegleiter mit einer außergewöhnlich hochwertigen visuellen Identität.

Die vorhandene MyBody-Entwicklung bleibt erhalten. Codex führt Claude Code. Claude Code implementiert. Codex kontrolliert.

---

## Anhang: Master Development Plan 2.0 (Fragment)

> Im selben Beitrag vorangestellt; der Text bricht in Abschnitt 4 nach „Ent“ ab. Inhaltlich deckt die General Directive 3.0 ihn ab.

PULSE ONE – MASTER DEVELOPMENT PLAN 2.0

Verbindlicher Weiterbauauftrag für Codex und Claude Code

Stand: 20. November 2026

1. Projektleitung und Ausgangslage

Codex übernimmt die technische Projektleitung. Claude Code bleibt der ausführende Entwickler des bestehenden Projekts MyBody, das zu PULSE ONE weiterentwickelt wird.

Erhalte das bestehende Repository und sämtliche funktionierenden Komponenten.

Die vorliegende Gap-Analyse von Claude Code ist der Ausgangspunkt, aber kein unabhängig verifizierter Testbericht.

Aktuell gemeldeter Stand:

* Colmi-R03-BLE-Anbindung implementiert
* Projekt gebaut und Simulatoroberfläche getestet
* Realtest mit dem R03 noch nicht nachgewiesen
* iPhone-/TestFlight-Installation noch nicht abgeschlossen
* Premium-3D-Erlebnis noch nicht umgesetzt
* HealthKit fehlt
* Mehrpersonenprofile fehlen
* Onboarding fehlt
* KI-Tagescoach fehlt
* Sportwelten fehlen

Überprüfe diese Aussagen anhand des tatsächlichen Repositories.

Arbeite mit Claude Code weiter. Beginne keine konkurrierende Neuimplementierung.

2. Neue verbindliche Produktstrategie

PULSE ONE wird ein universeller, personalisierter Gesundheits-, Bewegungs- und Trainingsbegleiter.

Das Produkt besteht aus fünf zentralen Systemen:

1. Universal Device & Health Hub
2. Personal Profile & Onboarding
3. PULSE Intelligence
4. PULSE Daily Coach
5. PULSE Immersive Experience

Diese Systeme müssen technisch unabhängig, aber über gemeinsame Datenmodelle miteinander verbunden sein.

3. PHASE A – Universelle Geräte- und Datenarchitektur

Höchste technische Priorität.

Baue eine erweiterbare Architektur für verschiedene Datenquellen.

Implementiere folgende Adapter:

* Colmi R03 BLE Adapter
* Colmi R09 BLE Adapter, zunächst vorbereitet
* Apple HealthKit Adapter
* Oura API V2 Adapter
* Standard Bluetooth GATT Adapter
* Manual Data Adapter
* Erweiterungsschnittstelle für weitere Gerätehersteller

Jeder Adapter muss definieren:

* Unterstützte Geräte
* Unterstützte Messwerttypen
* Berechtigungen
* Verbindungsmethode
* Pairing-Status
* Synchronisierungsfähigkeit
* Historische Daten
* Live-Daten
* Fehlerzustände
* Wiederverbindung
* Firmware-/Protokollkompatibilität

Implementiere eine zentrale Device Registry.

Ein Nutzer kann mehrere Geräte hinzufügen, entfernen, umbenennen und einem Profil zuordnen.

Die App muss unterscheiden zwischen:

* Gerät entdeckt
* Gerät verbunden
* Gerät kompatibel
* Datenzugriff verfügbar
* Synchronisierung erfolgreich
* Datenqualität geprüft

Eine Bluetooth-Verbindung allein darf nicht als vollständige Integration gelten.

Datenmodell

Erstelle ein normalisiertes Gesundheitsdatenmodell mit:

* Profilkennung
* Messwerttyp
* Messwert
* Einheit
* Messzeitpunkt
* Datenquelle
* Gerätekennung
* Original-Sample-ID
* Importzeitpunkt
* Datenqualität
* Messmethode
* Zeitzoneninformation
* Rohdatenreferenz

Bewahre Rohdaten, soweit sinnvoll und zulässig, getrennt von normalisierten Messwerten auf.

Implementiere idempotente Synchronisierung, Konfliktbehandlung und Dublettenvermeidung.

Verwende keine unkontrollierte Mittelwertbildung zwischen verschiedenen Sensorquellen.

Colmi R03

Nutze den bereits vorhandenen Code.

Prüfe auf einem echten iPhone:

* Gerätesuche
* Geräteidentifikation
* Verbindung
* Live-Puls
* Historische Pulsdaten
* Schritte
* Schlafdaten
* SpO₂
* Batteriestatus

Jede Funktion ist einzeln auf reale Unterstützung zu prüfen.

Erstelle eine Capability-Matrix mit den Zuständen:

* bestätigt
* implementiert, ungetestet
* Protokoll unbekannt
* nicht unterstützt

Colmi R09

Bereite die Geräteintegration vor.

Verifiziere nach Erhalt des Rings die tatsächlichen Sensorfunktionen und das BLE-Protokoll.

Prüfe insbesondere die Temperaturdaten. Unterscheide Hauttemperatur, relative Temperaturabweichung und Körperkerntemperatur.

Apple HealthKit

Implementiere:

* Datentypbezogene Berechtigungen
* Import historischer Messwerte
* Inkrementelle Synchronisierung
* Quellenzuordnung
* Umgang mit gelöschten oder geänderten HealthKit-Daten
* Schlaf, Herzfrequenz, HRV, Schritte, Aktivität, Workouts und weitere unterstützte Datentypen

Verwende die offiziellen HealthKit-Schnittstellen und berücksichtige deren Datenschutzbeschränkungen.

Oura Ring

Implementiere die Integrationsarchitektur für die offizielle Oura API V2.

Nutze OAuth2 mit sicherem Tokenmanagement.

Berücksichtige Mitgliedschaftsvoraussetzungen, API-Freigaben, Datenverfügbarkeit und Synchronisierungsverzögerungen.

Keine ungeprüfte direkte Bluetooth-Integration.

4. PHASE B – Multiprofil und persönliches Onboarding

PULSE ONE muss für unterschiedliche Nutzer geeignet sein.

Ent
