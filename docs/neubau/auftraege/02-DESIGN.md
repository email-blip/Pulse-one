# Auftrag 02 – Design-System / Motion / Assets

Du bist Team **02 Design** im PULSE-ONE-Neubau. Zuerst `docs/neubau/auftraege/00-GEMEINSAM.md` lesen und befolgen. Skills: `studio-premium-ui`, `studio-motion`, `studio-haptics`, `studio-sound`, `studio-graphics-3d`, `swiftui-design-skill`.

**Deine Dateien:** neu `Sources/DesignKit/*`, `Sources/Assets.xcassets`, neu `Resources/Media/*`, `docs/media/MEDIA-REGISTER.md`, `scripts/assets/*`; alt `Sources/DesignSystem/*` (löst du ab, andere Teams stellen auf DesignKit um).

**M1-Lieferung:**
1. Tokens: Palette fest (Obsidian #070D19, Bio Cyan #15D9F3, Neural Violet #9B70FF, Pulse Coral #FF644F, Ice White #E6F4FA) plus abgeleitete Flächen/Linien/Textstufen und je eine Farbe pro Messart und Schlafphase (Farbe nie einzige Bedeutung: Muster/Form/Beschriftung zusätzlich). Schrift: große Zahlen (SF Pro Rounded oder Expanded, `monospacedDigit`), Überschriften, Text, mit Dynamic Type bis XXXL.
2. Komponenten nach Referenz-Mockup (Plan §4): ROOK-Kopf mit Orb (nativ, gesteuert nur über `RookPresence`), Schlagzeile, Primär-/Sekundärknopf, Kachel (klein/breit/groß; Name, Symbol, Zahl + Einheit, Bezug, Platz für Mini-Verlauf), Karte, Abschnittskopf, Chips.
3. Motion-Verträge: eine Datei mit Dauer/Federkurve je Bedeutung (neue Messung landet, Zeitraumwechsel, Punktauswahl, Kachel tauscht Platz, Übung beginnt, Phase endet, Insight → Belege) und Reduce-Motion-Ersatz. Haptik-Muster dazu. Keine Daueranimation.
4. Medienregister anlegen (Felder: ID, Quelle, Autor, Lizenz, Nachweis, Version, Prüfsumme, Format, Größe, Verwendung, Attribution). Prüfen, welche Quellen aus der Cloud erreichbar sind (Poly Haven, ambientCG, Quaternius, Kenney, NIH 3D); blockierte Hosts dem Leitstand melden. Rive: klären, ob `.riv`-Dateien ohne Kosten erstellbar sind; bis dahin kein Paket.
5. Drei Sounds aus einer Klangfamilie (Start, Phasenwechsel, Abschluss), CC0 oder selbst synthetisiert, ins Register.

**Abnahme:** Referenzansicht als Komponenten-Vorschau im Screenshot-Szenario (3 Größen, XXXL, Reduce Motion), Kontrast AA, PR „[02] DesignKit und Motion“. Als Erstes liefern, damit 03–05 darauf bauen.
**M2:** Körpermodell-Kandidat (MakeHuman/MPFB oder Quaternius, USDZ, reduziert), zwei fachlich geprüfte Übungsanimationen, ROOK-Zustände, Lizenznachweise und gemessene Dateigrößen.
