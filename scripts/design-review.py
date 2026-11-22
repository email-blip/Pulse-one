#!/usr/bin/env python3
"""Claude design review of the walkthrough screenshots (owner approved 2026-11-22, ~0.15 $ per run).

Usage: design-review.py <screenshot dir> <output .md>

Sends the `explore__*.png` screenshots of the KI-Rundgang (test data only, "Testansicht", never real health
data) to Claude and writes a short German findings list. Report only: the script never fails the CI run; a
missing key, an API error or a refusal just writes a note into the report.
"""
import base64
import io
import os
import sys
from pathlib import Path

MODEL = "claude-sonnet-5-5"
MAX_SHOTS = 40          # cost cap: ~1k input tokens per downscaled screenshot
WIDTH = 590             # px; keeps text legible at ~1.5x points while cutting tokens and request size

PROMPT = """Du bist ein erfahrener iOS-Designer und prüfst Screenshots der iPhone-App PULSE ONE \
(Gesundheit, Sport, Regeneration; dunkles, ruhiges Design; Oberfläche auf Deutsch). \
Die Bilder stammen aus einem automatischen Rundgang mit Testdaten. Jedes Bild hat davor eine Zeile \
mit seinem Namen (Bereich und Bildschirm).

Finde echte Design- und Textfehler, die ein Nutzer bemerken würde:
- abgeschnittene oder überlappende Texte und Titel
- Elemente, die nicht zum dunklen Design passen (z. B. graue Standard-Formulare, helle Flächen)
- schlecht lesbarer Text (Kontrast, zu klein)
- doppelte oder widersprüchliche Inhalte, Rechtschreib- und Grammatikfehler
- Diagramme, die irreführend wirken (z. B. sehr enge Achsen)
- leere oder kaputt wirkende Bereiche

Nicht melden: das Banner „Testansicht“, die Uhrzeit in der Statusleiste, Geschmacksfragen ohne klaren Mangel.

Antworte auf Deutsch, laienverständlich, als Markdown-Liste. Pro Fund eine Zeile:
**Bildschirm**: was nicht stimmt, und in Klammern ein kurzer Vorschlag. Wichtigstes zuerst, höchstens 15 Funde.
Wenn alles in Ordnung ist, schreibe genau: Keine Auffälligkeiten."""


def load_images(folder: Path) -> list[tuple[str, str]]:
    from PIL import Image

    shots = sorted(folder.rglob("explore__*.png"), key=lambda p: p.stem.split("__")[2:3])[:MAX_SHOTS]  # walk order
    result = []
    for path in shots:
        with Image.open(path) as img:
            img = img.convert("RGB")
            if img.width > WIDTH:
                img = img.resize((WIDTH, round(img.height * WIDTH / img.width)), Image.LANCZOS)
            buf = io.BytesIO()
            img.save(buf, format="JPEG", quality=85)
        name = path.stem.removeprefix("explore__").replace("__", " / ").replace("-", " ")
        result.append((name, base64.standard_b64encode(buf.getvalue()).decode("ascii")))
    return result


def review(images: list[tuple[str, str]]) -> str:
    import anthropic

    content: list[dict] = []
    for name, data in images:
        content.append({"type": "text", "text": f"Bild: {name}"})
        content.append({"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": data}})
    content.append({"type": "text", "text": PROMPT})

    client = anthropic.Anthropic(timeout=300, max_retries=2)
    response = client.beta.messages.create(
        model=MODEL,
        max_tokens=8000,
        output_config={"effort": "medium"},
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        messages=[{"role": "user", "content": content}],
    )
    if response.stop_reason == "refusal":
        return "_Claude hat die Prüfung abgelehnt; kein Ergebnis._"
    text = "\n".join(block.text for block in response.content if block.type == "text").strip()
    usage = response.usage
    cost = (usage.input_tokens * 2 + usage.output_tokens * 10) / 1_000_000
    return f"{text}\n\n_{len(images)} Bilder, {usage.input_tokens} + {usage.output_tokens} Tokens, ca. {cost:.2f} $._"


def main() -> None:
    folder, out = Path(sys.argv[1]), Path(sys.argv[2])
    header = "# Designprüfung durch Claude\n\n"
    if not os.environ.get("ANTHROPIC_API_KEY"):
        body = "_Übersprungen: GitHub-Secret `ANTHROPIC_API_KEY` ist nicht gesetzt._"
    else:
        images = load_images(folder)
        if not images:
            body = "_Übersprungen: keine Rundgang-Screenshots gefunden._"
        else:
            try:
                body = review(images)
            except Exception as error:  # report only, never fail the run
                body = f"_Fehler bei der Prüfung: {type(error).__name__}: {error}_"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(header + body + "\n", encoding="utf-8")
    print(header + body)


if __name__ == "__main__":
    main()
