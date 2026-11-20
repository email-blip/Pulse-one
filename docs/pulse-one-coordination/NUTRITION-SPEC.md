# PULSE NUTRITION – Fachkonzept (Master Directive 5.0, Teil VIII, Release 5)

Stand: 2026-11-20 · Status aller Punkte: **Geplant** (§14) · Verfasser: Claude Code
Perspektiven: F (Nutrition Scientist), G (AI Systems Architect), I (Security & Privacy), D (Grenzen bei Erkrankungen), J (QA).
Abhängig von: Release 3 (Claude-Anbindung), Profil/Körperdaten, Coach (Trainingstage).
Open-Source-Bewertung: `OPEN-SOURCE-TECHNICAL-AUDIT.md` (gemergt). Übernommen als **Konzept**: OpenNutriTracker (GPL, kein Code) – KI liefert nur Name und Menge;
healthos (MIT) – Formeln als reine Funktionen mit Plausibilitätsgrenzen und `nil` statt Fantasiewert; HealthTrack – Cache inkl. „nicht gefunden“, Energieziel mit Defizit-Obergrenze. Moment (ohne Lizenz) verworfen.

> Grundsatz: **Nährwerte kommen aus Datenbanken, nicht aus der KI.** Claude erkennt auf Fotos mögliche Lebensmittel und
> schätzt Portionen mit Spannweite. Die App rechnet die Nährwerte aus der Datenbank und zeigt sie als Schätzung, bis der Nutzer bestätigt.

Hinweis zur Prüfung: Die Doku-Seiten von Open Food Facts, USDA und wger waren aus der Cloud-Umgebung gesperrt. Angaben unten stammen aus Websuche
in den offiziellen Seiten (2026-11-20); mit „prüfen“ markierte Punkte vor der Umsetzung am Original verifizieren.

---

## 1. Ausgangslage im Code

Es gibt noch kein Ernährungsmodell. Vorhanden und nutzbar: `HealthSample` (Herkunft, Qualität, Einheit inkl. `kilocalories`/`kilojoules`),
`DataSourceKind.manual`, `HealthKitAdapter` (lesend). Neu: `PulseCore/Nutrition/` (Logik) und `Sources/Features/Nutrition/`.

## 2. Datenmodell

| Typ | Felder (Auszug) |
|---|---|
| `FoodItem` | id, Name de/en, Marke, Barcode (GTIN), Quelle (`off`/`usda`/`bls`/`custom`), Quell-ID, Nährwerte je 100 g/ml, Portionsgrößen, Datenqualität, Lizenz, Abrufdatum |
| `NutrientValues` | Energie kcal + kJ, Protein, Kohlenhydrate, davon Zucker, Fett, davon gesättigt, Ballaststoffe, Salz, optional Mikronährstoffe (Map Nährstoffcode → Wert + Einheit); fehlend = `nil`, nie 0 |
| `MealEntry` | Zeit, Mahlzeittyp, Positionen (FoodItem + Menge + Einheit), Erfassungsweg (manuell/Suche/Barcode/Foto/Rezept/Wiederholung), Status (`estimated`/`confirmed`), Foto-Referenz (lokal) |
| `Recipe` | Zutaten, Portionen, Zubereitungsverlust optional, berechnete Nährwerte |
| `FluidEntry` | Getränk, Menge ml, Wasser zählt / Koffein / Alkohol |
| `NutritionGoal` | Energie-Spanne, Protein-Spanne, Ballaststoffe, Wasser, Begründung, Gültig-ab |

`DataQuality` je FoodItem und Mahlzeit: `verified` (amtliche Datenbank), `community` (Open Food Facts, vollständig), `incomplete` (Felder fehlen),
`estimated` (Foto/Portion geschätzt), `user` (eigene Eingabe). Sichtbar als Kennzeichen an jedem Wert (Directive: „Datenqualität muss sichtbar sein“).

## 3. Ernährungstagebuch

| Funktion | Umsetzung |
|---|---|
| Mahlzeit manuell | Name + Nährwerte direkt oder aus Suche |
| Lebensmittel suchen | lokal zuerst (eigene Einträge, Favoriten, Cache), dann Datenbanken §4 |
| Barcode scannen | VisionKit `DataScannerViewController` (iOS 16+, Apple-Framework, keine Abhängigkeit) für EAN-13/EAN-8/UPC → Open Food Facts |
| Foto | §5 |
| Portionen korrigieren | Gramm, Stück, Löffel, Tasse; Schieberegler mit Spannweite bei Schätzungen |
| Rezepte | Zutatenliste → Nährwerte je Portion |
| Häufige Mahlzeiten | „Wie gestern“, Favoriten, zuletzt verwendet |
| Getränke, Wasser | Schnellknöpfe 250/500 ml |
| Offline | Einträge offline möglich; Datenbankabruf wird nachgeholt |

## 4. Datenquellen

| Quelle | Zugriff | Grenzen | Lizenz / Bedingungen | Entscheidung |
|---|---|---|---|---|
| **Open Food Facts** (Markenprodukte, Barcode) | `GET https://world.openfoodfacts.org/api/v2/product/{barcode}?fields=…` ohne Anmeldung; Suche über Search-API | laut offizieller Doku **100 Anfragen/min** für Produktabrufe, **10/min** für Suche; eigener `User-Agent` Pflicht (`PulseOne/<Version> (iOS)`, ohne persönliche Daten) | Datenbank ODbL, Inhalte DbCL, Produktbilder CC BY-SA (prüfen); Namensnennung „Open Food Facts“; abgeleitete Datenbank wieder unter ODbL | **übernehmen** als Primärquelle für Barcodes. Lokaler Cache je Barcode; Suche entprellt (≥ 600 ms), keine Massenabfrage. Datenqualität `community`. Nährwerte sind Herstellerangaben, oft unvollständig. |
| **USDA FoodData Central** (Grundnahrungsmittel, Mikronährstoffe) | `https://api.nal.usda.gov/fdc/v1/foods/search`, `/food/{fdcId}`; API-Schlüssel über api.data.gov (kostenlos) | **1 000 Anfragen/Stunde** je Schlüssel; Überschreitung sperrt den Schlüssel 1 h | gemeinfrei (CC0 laut Sekundärquellen, **prüfen**), Quellenangabe erbeten | **adaptieren**: Foundation- und SR-Legacy-Daten für generische Lebensmittel. Englische Namen → Zuordnung über englischen Namen aus der Fotoanalyse oder eigene Übersetzungstabelle der ~500 häufigsten Lebensmittel. Schlüssel: Johannes registriert selbst, Speicherung im Keychain wie Claude. |
| **Bundeslebensmittelschlüssel BLS 4.0**, Max Rubner-Institut | Download, kein API; ca. 7 140 Lebensmittel, bis 138 Nährstoffe | – | laut Audit seit Dez. 2025 **kostenfrei**; genauer Lizenztext **vor Einbau prüfen** | **bevorzugte Offline-Quelle** für generische deutsche Lebensmittel (keine Abfrage an Dritte, deutsche Namen). Nach Lizenzprüfung einbetten, Eintrag in `DECISIONS.md`; dann USDA nur noch Rückfall. |
| Kommerzielle Datenbanken (z. B. Nutritionix, Edamam) | API | – | kostenpflichtig | **verwerfen** ohne Freigabe von Johannes |

Kosten: 0 € (OFF, USDA). Datenschutz: Barcode- und Suchanfragen verraten, was jemand isst; sie gehen ohne Profil- oder Gesundheitsdaten an OFF/USDA. Hinweis in den Einstellungen; Schalter „Online-Suche“ (Standard an, nur Barcode/Suchbegriff).

## 5. KI-Fotoanalyse

### 5.1 Ablauf

1. Foto aufnehmen (oder aus Fotos wählen). Bild bleibt lokal.
2. Vor dem Senden: Hinweis „Foto geht an Anthropic zur Erkennung“; einmalige Freigabe „Fotos senden“ (Kategorie Ernährung) + je Foto Bestätigung, abschaltbar.
3. Bild verkleinern auf längste Kante **1 568 px**, JPEG Qualität ca. 0,8, EXIF/GPS entfernen.
4. Claude Vision: Erkennung möglicher Lebensmittel + Portionsschätzung mit Spannweite (strukturiertes JSON, unten).
5. App gleicht jeden Eintrag mit Datenbanken ab (lokal → OFF-Suche → USDA), Nutzer wählt bei Mehrdeutigkeit.
6. Nährwerte = Datenbankwert × geschätzte Menge, angezeigt als Spanne („ca. 520–680 kcal, geschätzt“).
7. Nutzer bestätigt oder korrigiert → Status `confirmed`; Korrekturen verbessern die eigene Portionsliste, nicht die KI.

### 5.2 Aufruf und Schema

```json
{
  "model": "claude-sonnet-5-5",
  "max_tokens": 4000,
  "output_config": {"effort": "low", "format": {"type": "json_schema", "schema": {
    "type": "object", "additionalProperties": false, "required": ["items", "isFood", "notes"],
    "properties": {
      "isFood": {"type": "boolean"},
      "items": {"type": "array", "items": {"type": "object", "additionalProperties": false,
        "required": ["nameDe", "nameEn", "category", "portionGramsLow", "portionGramsLikely", "portionGramsHigh", "confidence", "visibleCues"],
        "properties": {
          "nameDe": {"type": "string"}, "nameEn": {"type": "string"},
          "category": {"type": "string", "enum": ["grain","vegetable","fruit","dairy","meat","fish","egg","legume","nut","fat_oil","sweet","beverage","mixed_dish","sauce","other"]},
          "portionGramsLow": {"type": "number"}, "portionGramsLikely": {"type": "number"}, "portionGramsHigh": {"type": "number"},
          "confidence": {"type": "string", "enum": ["low","medium","high"]},
          "visibleCues": {"type": "string"}}}},
      "notes": {"type": "string"}}}}},
  "messages": [{"role": "user", "content": [
    {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": "<…>"}},
    {"type": "text", "text": "<Anweisung v1: nur sichtbare Lebensmittel, keine Nährwerte, Spannweiten, Unsicherheit benennen>"}]}]
}
```

- Claude liefert **keine Kalorien**; das Schema hat dafür kein Feld.
- Lokale Prüfung: low ≤ likely ≤ high, Werte 1–2 000 g (Schema kann Zahlengrenzen nicht erzwingen), `isFood == false` → Hinweis statt Eintrag.
- Modellwahl: Vorgabe Sonnet 5.5 (Erkennung ist keine schwere Denkaufgabe), Opus 5.5 wählbar.
- Laut Anthropic-Doku: JPEG/PNG/GIF/WebP, max. 10 MB je Bild, Mengen-Zählen und Größenschätzung sind ausdrücklich ungenau → Spannweiten und Nutzerbestätigung sind Pflicht, keine „exakten“ Werte.

### 5.3 Kosten je Foto (Vision-Token = ⌈Breite/28⌉ × ⌈Höhe/28⌉)

1 568 × 1 176 px ≈ 56 × 42 = **2 352 Bildtoken** + ca. 800 Token Text/Schema-Prompt + ca. 600 Token Antwort.
- Sonnet 5.5 (2 $ / 10 $): ≈ 0,0063 + 0,006 ≈ **0,012 $ je Foto** → 3 Fotos/Tag ≈ 1,10 $/Monat.
- Opus 5.5 (4 $ / 20 $): ≈ **0,025 $ je Foto** → ≈ 2,20 $/Monat.

## 6. Persönliche Ernährungsziele

Berechnung lokal, Claude formuliert nur.

| Größe | Methode | Grenze |
|---|---|---|
| Grundumsatz | Mifflin-St Jeor aus Gewicht, Größe, Alter, Geschlecht | als Schätzung gekennzeichnet |
| Gesamtbedarf | Grundumsatz × PAL (aus Aktivitätsprofil) oder Grundumsatz + aktive Energie aus Apple Health (7-Tage-Mittel) | Quelle sichtbar |
| Ziel Gewicht senken | Defizit höchstens 500 kcal/Tag und höchstens ca. 0,5–1 % Körpergewicht pro Woche | **nie** unter geschätzten Grundumsatz; kein Ziel bei BMI < 18,5 |
| Ziel Gewicht halten/aufbauen | Bedarf bzw. + 200–300 kcal an Trainingstagen | |
| Protein | Referenz DGE 0,8 g/kg (ab 65: 1,0 g/kg); bei regelmäßigem Krafttraining Spanne bis ca. 1,6 g/kg | Spanne, keine Einzelzahl |
| Ballaststoffe, Wasser | DGE-Orientierungswerte (mind. 30 g; ca. 1,5 l Getränke) | |

Ausschlüsse: keine Diäten für Erkrankungen (Diabetes, Nierenerkrankung, Essstörung, Schwangerschaft) ohne fachliche Grundlage;
bei solchen Angaben im klinischen Kontext → nur Tagebuch, keine Zielvorschläge, Hinweis auf Ernährungsberatung/Arzt.
Allergien und Unverträglichkeiten (Profil) sind **harte Filter** für Vorschläge; Allergene aus OFF (`allergens_tags`) werden angezeigt, aber mit Hinweis „Herstellerangabe, Verpackung prüfen“.

## 7. Mahlzeitenplanung

Tagesvorschläge, Wochenplan, Rezeptideen, Einkaufsliste, Trainingstag-Anpassung (mehr Kohlenhydrate um Haupteinheiten), Vorlieben, Resteverwertung, Nährstoffübersicht.
Umsetzung: Claude erzeugt Plan als strukturiertes JSON (Rezepte mit Zutaten + Mengen), **die App rechnet Nährwerte** aus Datenbanken und prüft Allergien, Ausschlüsse und Zielspanne.
Abweichung > 15 % vom Ziel → Plan wird zur Nachbesserung zurückgegeben oder markiert. Einkaufsliste aggregiert Zutaten; Export als Text/Teilen-Menü.
Kosten Wochenplan (Opus 5.5): ca. 6k ein / 12k aus ≈ **0,26 $**.

## 8. Langzeitanalyse

Lokal berechnet (Release-2-Engine): Regelmäßigkeit (Mahlzeitzeiten, erfasste Tage), Makroverteilung, Energiezufuhr-Trend, Zusammenhang mit Training und
Wohlbefinden (Spearman, als beobachteter Zusammenhang), Gewichtsentwicklung (aus Health), **Datenvollständigkeit** (Tage mit ≥ 3 Mahlzeiten oder als „vollständig“ markiert).
Tage ohne vollständige Erfassung gehen nicht in Durchschnitte ein (sonst wirkt die Zufuhr zu niedrig). Ernährungsanalyse über Claude: `CLAUDE-INTELLIGENCE-SPEC.md` §4.

## 9. Apple Health

Schreiben von `dietaryEnergyConsumed`, Makros und Wasser nach Health erst nach eigener Entscheidung (Option, Standard aus), nur bestätigte Einträge.

## 10. Arbeitspakete

| PR | Inhalt | Abnahme |
|---|---|---|
| R5-1 | Datenmodell, Tagebuch manuell, Getränke, Favoriten | Screenshots, Unit |
| R5-2 | OFF-Client (User-Agent, Cache, Ratenbegrenzer), Barcode-Scanner | iPhone: 10 echte Produkte |
| R5-3 | USDA-Client + Übersetzungstabelle, Suche kombiniert | Suche „Haferflocken“, „Apfel“ liefert generische Werte |
| R5-4 | Fotoanalyse (Vision, Schema, Abgleich, Spannweiten, Bestätigung) | 10 Testfotos; nie exakte kcal ohne Bestätigung |
| R5-5 | Ziele (Rechner + Grenzen) | Unit-Tests Grenzfälle |
| R5-6 | Rezepte, Mahlzeiten-/Wochenplan, Einkaufsliste | |
| R5-7 | Langzeitanalyse + Claude-Ernährungsanalyse | **Abnahme R5: 14 Tage alltagstaugliches Tagebuch mit KI-Unterstützung** |

## 11. Risiken

| Risiko | Gegenmaßnahme |
|---|---|
| Falsche Kalorien aus Fotos | KI liefert nur Erkennung + Spannweite; Nährwerte aus Datenbank; Bestätigungspflicht |
| Unvollständige OFF-Daten | Feld `nil` statt 0, Qualitätskennzeichen, Alternative vorschlagen |
| Rate-Limits | Cache, Entprellung, lokale Favoriten |
| Gestörtes Essverhalten wird verstärkt | keine extremen Defizite, Ziel abschaltbar („nur Tagebuch“), keine Bewertungen wie „schlecht“ |
| Allergie übersehen | harte Filter + Hinweis „Verpackung prüfen“ |
