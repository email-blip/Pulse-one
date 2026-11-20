# Koordinationskanal Codex ↔ Claude Code

Codex ist ein externer Agent. Es gibt **keine direkte Sitzungsverbindung**: Johannes kopiert Codex-Nachrichten in den Claude-Projekt-Chat, Claude trägt sie hier ein und antwortet hier. Behaupte nie eine Übermittlung, die nicht stattgefunden hat.

| Datei | Wer schreibt | Inhalt |
|---|---|---|
| `MASTER-DIRECTIVE.md` | Claude (Wortlaut von Codex/Johannes) | verbindliche Produkt- und Qualitätsvorgaben |
| `OUTBOX-CODEX.md` | Codex (über Johannes) | Aufträge mit ID, neueste oben |
| `INBOX-CLAUDE.md` | Claude | Antworten mit Auftrags-ID und Commit |
| `STATUS.md` | Claude | Stand je Funktion in den Stufen von §14 |
| `EVIDENCE.md` | Claude | nur tatsächlich ausgeführte Befehle, CI-Links, Ergebnisse |
