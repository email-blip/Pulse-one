# PULSE ONE – Medienregister

Besitzer: Team 02 (Design). Jede Datei, die mit der App ausgeliefert wird oder als Ausgangsmaterial dient, steht hier mit Herkunft und Lizenz. Ohne Eintrag kommt keine Datei in `apps/PulseOne/Sources/Resources/Media/`.

Regeln (Neubau-Plan §10, Vorgaben Johannes 2026-11-23):
- Erlaubt: CC0, eigene Erzeugung, oder eine Lizenz, die kommerzielle Nutzung in einer App ohne Weitergabe als Bibliothek erlaubt (Nachweis verlinken).
- Prüfsumme = SHA-256 der Datei, wie sie im Repo liegt. Größe in Byte.
- Keine Gesundheitsdaten an Asset-Plattformen; Suchen nur mit allgemeinen Begriffen.
- Bibliotheksclips (Bewegungen) sind Rohmaterial, keine geprüfte Trainingsanleitung: fachliche Prüfung steht in „Verwendung“.
- Ein Stil: dunkle Obsidian-Bühne, kühles Licht (Bio Cyan / Ice White), Akzente Neural Violet / Pulse Coral; keine Comicfiguren neben realistischen Körpern.

## 1. Ausgelieferte Dateien

| ID | Datei | Quelle | Autor | Lizenz | Nachweis | Version | Prüfsumme (SHA-256) | Format | Größe | Verwendung | Attribution |
|---|---|---|---|---|---|---|---|---|---|---|---|
| snd.start | `Sources/Resources/Media/Sounds/po-start.wav` | selbst synthetisiert, `scripts/assets/synth-sounds.py` | PULSE ONE (Team 02) | CC0 (eigene Erzeugung, kein Fremdmaterial) | Skript im Repo, deterministisch | 1 (2026-11-23) | `19bd2c6de7a34e30cd95cdfb22ef2832db48d7052ab7f8f0fedceb7f472bc686` | WAV 48 kHz 16 bit mono, 0,90 s | 86 444 | Einheit beginnt (`MotionEvent.workoutStart`) | keine nötig |
| snd.phase | `Sources/Resources/Media/Sounds/po-phase.wav` | dto. | dto. | CC0 | dto. | 1 | `487b4a9b2f83fcbf2aaa930a7bd3d5f8471850b59cd81639f7335abac78b60ff` | WAV, 0,60 s | 57 644 | nächster Abschnitt (`MotionEvent.phaseEnd`) | keine nötig |
| snd.complete | `Sources/Resources/Media/Sounds/po-complete.wav` | dto. | dto. | CC0 | dto. | 1 | `6a95ffb5b1144499e374a948b34ddcfbea2a79e22b8ba176df44a5e8fd74c3e5` | WAV, 1,30 s | 124 844 | Einheit abgeschlossen (`DKSound.complete`) | keine nötig |

Klangfamilie: gläserne Glocke (Sinus-Grundton + leise 2./3. Teiltöne, weicher Einsatz, Ausklingen), E-Dur (E5, G♯5, B5, E6), gleicher kleiner Raum, Spitzenpegel −6 dBFS (Phase −9 dB). Wiedergabe `.ambient`: folgt dem Stummschalter, mischt sich mit Musik. Später (M2) dazu: Begrüßung, Pause, wichtiger Hinweis aus derselben Familie.

## 2. Quellen: Erreichbarkeit aus der Cloud-Umgebung (geprüft 2026-11-23)

| Quelle | Seite / API | Datei-Download | Lizenz | Ergebnis |
|---|---|---|---|---|
| Poly Haven | `api.polyhaven.com` 200 | `dl.polyhaven.org` 200 | Assets CC0; API-Bedingungen zusätzlich | **nutzbar** (HDRIs, Materialien, Modelle) |
| ambientCG | `ambientcg.com` API 200 | **blockiert**: Download leitet auf `acg-download.struffelproductions.com` um (Proxy) | CC0 | Host-Freigabe nötig |
| Quaternius (Universal Animation Library 1+2) | `quaternius.com` 200 | **blockiert**: Download über `quaternius.itch.io` / `itch.io` (Proxy) | Standardfassung CC0 | Host-Freigabe nötig (oder über Johannes' PC) |
| Kenney | `kenney.nl` 200 nur mit Browser-Kennung (Bot-Filter der Seite, nicht Proxy) | ungetestet, gleiche Seite | CC0 | nutzbar mit Browser-User-Agent |
| NIH 3D | `3d.nih.gov` 200 (Startseite); Einträge/Downloads 404/blockiert, `nih3d.nih.gov` blockiert | – | je Modell verschieden | Host `nih3d.nih.gov` freigeben; erst bei Herz-/Organmodellen (M2+) nötig |
| MakeHuman / MPFB | `makehumancommunity.org` blockiert, `github.com/makehumancommunity` 403 | – | Kernassets CC0 | Host-Freigabe nötig; Alternative: MPFB-Export über Blender auf Johannes' PC |
| Blender | `download.blender.org` 200 | 200 | GPL (Werkzeug, nicht ausgeliefert) | nutzbar für die USDZ-Pipeline |
| Freesound, Sonniss, Mixamo, LottieFiles, Rive | blockiert | – | – | in M1 nicht gebraucht; Mixamo nur über Johannes' Adobe-ID |

**An den Leitstand:** Für M2 (Körpermodell, Übungsanimationen) bitte freigeben: `acg-download.struffelproductions.com`, `itch.io`, `quaternius.itch.io` (+ deren Download-CDN), `makehumancommunity.org`, `static.makehumancommunity.org`, `nih3d.nih.gov`. Sonst lädt Johannes die Dateien auf seinem PC herunter und legt sie in den Projektordner.

## 3. Rive (Plan §10: „kostenlos erstellbar?“)

Stand Rive-Preisseite/Doku (über Websuche, rive.app selbst ist aus der Cloud blockiert): Der **Free-Plan** (0 $) erlaubt 3 Dateien und **exportiert `.riv` nur mit Rive-Startbild (Splash)**; ohne Splash ab Plan „Cadet“ (ca. 9 $/Monat jährlich). Exportierte Dateien laufen dauerhaft weiter, auch nach Kündigung. Die iOS-Runtime ist MIT.

**Folgerung:** Ohne Kosten keine produktionsreife `.riv`-Datei (Splash in der App ist nicht akzeptabel). ROOK bleibt nativ (`RookOrb`, gesteuert nur über `RookPresence`). Rive kommt nur, wenn Johannes einen Monat Cadet (≈ 9 $) freigibt, um die Datei einmal ohne Splash zu exportieren; dann `DECISIONS.md`-Eintrag über den Leitstand. Quellen: rive.app/pricing, rive.app/docs/editor/exporting.

## 4. Kandidaten (noch nicht im Repo)

| ID | Kandidat | Quelle | Lizenz | Zweck | Status |
|---|---|---|---|---|---|
| hdri.studio | Studio Small 09 (Sergej Majboroda) | Poly Haven | CC0 | Lichtumgebung für Körpermodell (RealityKit IBL), 1k | Kandidat M2 |
| body.base | MPFB-Grundkörper, neutral, reduziert | MakeHuman/MPFB | CC0 (Kern) | Living Twin / Übungsfigur | wartet auf Host-Freigabe |
| anim.ual | Gehen, Kniebeuge, Ausfallschritt | Quaternius UAL Standard | CC0 | Übungsanimation, fachliche Prüfung nötig | wartet auf Host-Freigabe |
