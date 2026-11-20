# Gap-Analyse PULSE ONE gegen die Master-Directive (Stand 2026-11-20)

Ehrliche Bewertung von Claude. Stufen nach §14. „Erlebnis“ heißt: so, wie der Masterplan es beschreibt (§4–§8), nicht nur funktionsfähig.

| Masterplan | Stand | Bewertung |
|---|---|---|
| §15 FIRST DEVICE CONNECT (Ring finden, verbinden, Status, 1 echter Messwert) | Implementiert, gebaut, Simulator-UI getestet | Kern vorhanden. **Am echten R03 unbewiesen**; TestFlight-Weg vorbereitet, wartet auf Schlüssel. |
| §5.1 Farben, Cinematic Dark | Implementiert | Farben stimmen. Räumliche Beleuchtung, Materialien, Hologramm, Lichtbahnen, Partikel, Shader: **fehlen**. |
| §5.1 Sound + synchronisierte Haptik | Haptik nur beim Verbinden | **Kein Sound**, keine Haptik im Herzschlag. |
| §5.2 Living Twin (3D-Mensch, 4 Zustände) | Geplant | **Fehlt komplett.** Braucht ein lizenzierbares 3D-Menschmodell (Asset-Frage, evtl. Kosten). |
| §5.3 Heart Chamber (3D-Herz, Puls-synchron) | Geplant | **Fehlt.** Nur ein 2D-Puls-Orb als Platzhalter-Erlebnis. |
| §5.4 Sleep Universe, §5.5 Vital Orbit, §5.6 Time Machine | Geplant | **Fehlen.** Schlafdaten vom Ring noch nicht gelesen. |
| §6 Sportwelten (5 Welten) | Geplant | **Fehlen.** |
| §7 Vier Designprofile | Geplant | **Fehlen** (nur Dark). |
| §10 R03: Berechtigung, Suche, Identifizieren, Verbinden, Status, Werte, Speichern, Anzeigen, Abbruch, Wiederverbinden | Implementiert | Alles im Code; Puls-Verlauf (5-min-Log), SpO₂, Schritte, Schlaf noch nicht angebunden. |
| §11 HealthKit, Personenprofile | Geplant | **Fehlt.** |
| §12 Pulse Intelligence | Geplant | **Fehlt.** |
| §13 Kanal, Protokoll | Implementiert | `docs/pulse-one-coordination/`. |
| §14 Qualitätskriterien | eingehalten | Testansicht klar markiert, keine erfundenen Messwerte, CI mit Bedienungshilfen-Prüfung. |

## Fazit
Heute steht das technische Fundament (Ring-Anbindung, Datenmodell, Pipeline). Das im Masterplan beschriebene **Premium-3D-Erlebnis existiert noch nicht**. Der Masterplan selbst setzt FIRST DEVICE CONNECT als ersten Pflicht-Meilenstein; das Erlebnis folgt danach.

## Vorschlag Reihenfolge (nach dem Realtest)
1. **Heart Chamber** (RealityKit, 3D-Herz schlägt im echten Puls, Haptik + Ton synchron) – größter Wow-Effekt mit echten Daten.
2. **Designsystem-Ausbau**: Lichtbahnen, Partikel-Hintergrund (Metal-Shader), Sound-Design, Übergänge.
3. **Living Twin** – braucht Entscheidung zum 3D-Menschmodell (selbst modelliert/kostenlos lizenziert vs. gekauft).
4. Profile + Onboarding + HealthKit, dann Sleep Universe, Vital Orbit, Designprofile, Sportwelten.
