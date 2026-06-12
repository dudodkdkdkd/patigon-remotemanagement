# VPS Remote Management Service Control

Dieses Repository enthält Skripte zur einfachen, persistenten Einrichtung und Steuerung von **Claude Code** und **OpenAI Codex** Remote-Control Instanzen.

Mit diesen Skripten können beide Dienste über eine zentrale Konfiguration gesteuert, gestartet, gestoppt, lokal entwickelt und bei Bedarf vollständig deinstalliert werden.

---

## Features

- **Zentrale Konfiguration**: Steuerung über ein einziges Environment-File.
- **Secret Auto-Discovery**: Skripte suchen automatisch nach einem Secret-Verzeichnis (z. B. `/secret`, `../secret` oder `../SECRET`) und kopieren vordefinierte Umgebungsvariablen (`env.patigon`, `env.patigon-remotemanagement`), um die Einrichtung zu beschleunigen (analog zu Capential).
- **Lokale Entwicklung (`devstart`)**: Starte Instanzen lokal im Vordergrund des Terminals mit interaktivem Logging und automatischem Cleanup (Ctrl+C). Verwendet das lokale `.env` im Projekt-Root.
- **Autostart & Crash-Resistenz (Produktion)**: Automatischer systemd-Neustart nach System-Boot, Netzwerkunterbrechungen oder Abstürzen.
- **Wahlfreie Dienste**: Aktiviere Claude, Codex oder beide gleichzeitig.
- **Bequeme Verwaltung**: Globale Befehle `prodstart`, `prodstop` und `devstart` direkt im Terminal.

---

## Voraussetzungen

### 1. Claude CLI & Vorbereitung
- Installiere das Claude CLI (standardmäßig unter `/root/.local/bin/claude` auf dem VPS oder in deinem lokalen User-Pfad).
- Lege dein Workspace-Verzeichnis an und akzeptiere den Trust-Dialog einmalig interaktiv:
  ```bash
  mkdir -p /opt/claude-workspace
  cd /opt/claude-workspace
  claude  # Trust-Dialog akzeptieren, dann mit Strg+C beenden
  ```
- Stelle sicher, dass du eingeloggt bist (Credentials befinden sich in `~/.claude/.credentials.json`).

### 2. Codex CLI & Vorbereitung
- Installiere das Codex CLI global über npm:
  ```bash
  npm install -g @openai/codex
  ```
- **Bei Verwendung des Abonnements (Standard):**
  Führe das CLI einmalig aus, um den Anmeldevorgang im Browser abzuschließen:
  ```bash
  codex  # Login abschließen, dann beenden
  ```
- **Bei Verwendung eines API-Keys:**
  Trage den API-Key einfach in deiner `.env`/`config.env` ein.

---

## Lokale Entwicklung (Local Dev)

Für die lokale Entwicklung auf deinem Entwickler-Rechner (z. B. macOS oder Linux) nutzt du das lokale `.env` File im Projektverzeichnis.

1. Führe das Skript im Projektverzeichnis aus:
   ```bash
   ./devstart.sh
   ```
   *Hinweis: Wenn keine lokale `.env` existiert, sucht das Skript in den übergeordneten Ordnern nach einem `secret/`-Verzeichnis (z. B. `../secret/env.patigon`) und kopiert es automatisch.*

2. Das Skript lädt die lokale `.env`, sucht nach `claude` und `codex` in deinem lokalen `$PATH` (um VPS-Pfade zu überschreiben) und startet beide Remote-Control-Prozesse interaktiv im Hintergrund deines Terminals.

3. **Beenden:** Drücke einfach `[Ctrl+C]` im Terminal. Alle gestarteten Prozesse werden sofort sauber beendet.

---

## Production-VPS (systemd-Service)

Für den 24/7 Betrieb auf deinem Linux-VPS:

1. Klonen oder kopiere die Skripte auf deinen VPS.
2. Starte die Installation:
   ```bash
   sudo ./prodstart.sh
   ```
   *Hinweis: Falls `/etc/claude-remote/config.env` fehlt, sucht das Skript nach einem Secret-Verzeichnis und kopiert die Konfiguration. Alternativ wird ein Template erzeugt. Zudem werden die Skripte als globale Befehle registriert.*

3. Passe bei Bedarf die Konfiguration an:
   ```bash
   sudo nano /etc/claude-remote/config.env
   ```
4. Aktualisiere und starte die Dienste:
   ```bash
   sudo prodstart
   ```

---

## Befehle & Verwaltung

Nach der ersten Installation auf dem VPS kannst du die Befehle von überall aus aufrufen:

### Dienste starten/aktualisieren (Produktion)
```bash
sudo prodstart
```

### Dienste stoppen (Produktion)
```bash
sudo prodstop
```

### Lokale Instanzen starten (Entwicklung)
```bash
devstart
```

### Vollständige Deinstallation
Stoppt alle Dienste, entfernt die Konfigurationen sowie die globalen Befehle restlos vom System:
```bash
sudo prodstop --purge
```

---

## Konfiguration (`config.env` oder `.env`)

| Variable | Beschreibung | Standardwert |
|---|---|---|
| `RUN_CLAUDE` | `true`/`false` - Aktiviert den Claude Code Remote-Control Dienst. | `true` |
| `RUN_CODEX` | `true`/`false` - Aktiviert den Codex Remote-Control Dienst. | `false` |
| `WORKSPACE_DIR` | Das Verzeichnis, aus dem die Remote-Sitzung gestartet wird. | `/opt/claude-workspace` |
| `CLAUDE_PATH` | Pfad zur Claude CLI (VPS-Standard). | `/root/.local/bin/claude` |
| `CODEX_PATH` | Pfad zur Codex CLI (VPS-Standard). | `/usr/local/bin/codex` |
| `CODEX_AUTH_TYPE` | Authentifizierung für Codex: `subscription` (Abo) oder `api_key`. | `subscription` |
| `OPENAI_API_KEY` | Der OpenAI API-Key (nur bei `CODEX_AUTH_TYPE=api_key`). | `your_openai_api_key_here` |

---

## Logs & Fehlerbehebung

### Logs live mitlesen (VPS)
```bash
sudo journalctl -u claude-remote -f
sudo journalctl -u codex-remote -f
```

### Status der Dienste prüfen (VPS)
```bash
sudo systemctl status claude-remote
sudo systemctl status codex-remote
```
