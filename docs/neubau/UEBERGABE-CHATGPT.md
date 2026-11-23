# Übergabe an ChatGPT: PULSE ONE Neubau (Optik, Bewegung, KI-Ton)

Bitte diesen Text komplett an ChatGPT geben. Die ausführliche Analyse und der Bauplan stehen in `NEUBAU-PLAN.md`.

## Die App
PULSE ONE ist eine private iPhone-App (Swift/SwiftUI, iOS 18+, dunkles Design) für den Smart Ring Colmi R03. Sie liest per Bluetooth Puls (alle 5 Minuten), HRV, SpO₂, Stress (alle 30 Minuten), Schritte und Schlafphasen (Leicht, Tief, REM, Wach mit Uhrzeit) und zusätzlich Apple-Health-Daten. Eine KI namens **Nox** (Claude) deutet die Daten. Sie wird komplett neu gestaltet.

## Was dem Eigentümer am heutigen Stand nicht gefällt
1. Optik statisch und textlastig, wirkt wie eine Liste aus Textkarten, nicht wie Oura, QRing oder Whoop.
2. Keine Bewegung, nichts lebt, nichts reagiert auf neue Messungen.
3. Der Verlauf ist eine Liste („62 bpm · 3 Tage mit Daten“) statt Diagrammen mit echten Messzeitpunkten.
4. Schlaf zeigt nur die Dauer, kein Hypnogramm mit Phasen über die Uhrzeit.
5. Die KI redet über fehlende Daten („Für deine Basislinie fehlen mir Vergleichswerte“, „lernt noch“) statt zu deuten.
6. Der KI-Ton ist technisch und vorsichtig statt locker und konkret.

## Was er will
1. Lebendige, animierte Diagramme im Takt der Ringmessungen: welcher Wert wann gemessen wurde und was daraus folgt.
2. Startseite aus frei anordenbaren Kacheln für alle Werte (klein, breit, groß), jede mit Mini-Diagramm.
3. Schlaf mit Hypnogramm: alle Phasen mit Uhrzeit, darunter Puls/HRV/SpO₂ der Nacht.
4. Nox spricht locker und cool, auch per Sprache, deutet nur: „So geht's dir heute, so lief dein Tag.“ Rückfrage „Warum?“ jederzeit.
5. Mindestens so gut wie Oura, QRing, Whoop, Ultrahuman, Garmin, Apple Health, Ziel deutlich besser.
6. Moderner Stil, bessere Grafiken, viel Bewegung.

## Geplanter Aufbau
- Tabs: **Heute** (3 Score-Ringe Schlaf/Erholung/Aktivität, Nox-Satz, Kacheln) · **Verlauf** (interaktive Diagramme Tag/Woche/Monat/Jahr) · **Nox** (ein Gespräch mit Sprache) · **Coach** (Training).
- Besonderheiten: Nox-Symbole direkt im Diagramm an der Stelle, wo etwas passiert ist; neue Ringwerte „fliegen“ live ins Diagramm; Kurven übereinanderlegen.

## Was wir von dir (ChatGPT) brauchen
Bitte so konkret wie möglich, gern mit Bildern/Mockups:
1. **Screens als Mockup:** Heute (mit Kacheln), Kachel-Bearbeiten, Puls-Tagesdiagramm mit Messpunkten, Schlaf mit Hypnogramm, Wochenansicht, Nox-Gespräch, Coach.
2. **Farbwelt:** Hintergrund, Karten, je eine Farbe pro Messart (Puls, HRV, SpO₂, Stress, Schlafphasen, Schritte, Energie), Akzentfarbe.
3. **Schrift:** Schriftart/Stil für große Zahlen, Überschriften, Fließtext (iOS-Systemschriften bevorzugt).
4. **Kacheln:** Größen, Ecken, Inhalt je Kachel, wie Mini-Diagramme aussehen.
5. **Bewegung:** welche Animationen wo (Öffnen, Score-Ringe, Zahlen, Zeitraumwechsel, neuer Messwert, Übergang Kachel → Detail), Tempo, Stil (federnd, ruhig, verspielt?).
6. **Nox:** Beispiel-Texte im gewünschten Ton für Morgen, Mittag, Abend, eine „Warum?“-Antwort; Stimme/Charakter.
7. **Was du anders machen würdest** als im geplanten Aufbau oben.

Technische Grenzen: nur native iOS-Mittel (SwiftUI, Swift Charts, keine fremden Bibliotheken ohne Grund), dunkles Design, muss mit großer Schrift und „Bewegung reduzieren“ funktionieren.
