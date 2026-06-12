# VPS Remote Management Service Control

Dieses Repository enthält Skripte zur einfachen, persistenten Einrichtung und Steuerung von **Claude Code** und **OpenAI Codex** Remote-Control Instanzen.

Mit diesen Skripten können beide Dienste über eine zentrale Konfiguration gesteuert, gestartet, gestoppt, lokal entwickelt und bei Bedarf vollständig deinstalliert werden.

---

## Features

- **Zentrale Konfiguration**: Steuerung über ein einziges Environment-File.
- **Secret Auto-Discovery**: Skripte suchen automatisch nach einem Secret-Verzeichnis (z. B. `/secret`, `../secret` oder `../SECRET`) und kopieren vordefinierte Umgebungsvariablen (`env.remotemanagement`, `env.patigon-remotemanagement`), um die Einrichtung zu beschleunigen (analog zu Capential).
- **Interaktiver VPS-Setup-Assistent**: Bei Ausführung von `prodstart` im Terminal wirst du interaktiv durch die Auswahl der Dienste, Installation fehlender CLI-Tools sowie den Anmeldevorgang geleitet.
- **Auto-Installation**: Fehlende Binaries für Claude und Codex werden auf Wunsch vollautomatisch heruntergeladen und installiert (npm/curl).
- **Login-Verifizierung**: Prüft vor dem Service-Start, ob gültige Anmeldedaten vorhanden sind, und startet bei Bedarf den geführten Login-Vorgang im Terminal.
- **Lokale Entwicklung (`devstart`)**: Starte Instanzen lokal im Vordergrund des Terminals mit interaktivem Logging und automatischem Cleanup (Ctrl+C). Verwendet das lokale `.env` im Projekt-Root und die Rechte werden automatisch abgesichert (`chmod 600`).
- **Autostart & Crash-Resistenz (Produktion)**: Automatischer systemd-Neustart nach System-Boot, Netzwerkunterbrechungen oder Abstürzen.
- **Bequeme Verwaltung**: Globale Befehle `prodstart`, `prodstop` und `devstart` direkt im Terminal.

---

## Voraussetzungen

### 1. Berechtigungen
- **VPS (Produktion)**: Das Skript `prodstart.sh` benötigt Root-Rechte (`sudo`), um systemd-Units zu registrieren und globale Befehle zu hinterlegen.
- **Lokale Entwicklung**: `devstart.sh` kann ohne Root-Rechte als normaler Benutzer ausgeführt werden.

---

## Installation & Erste Schritte (Produktion)

1. Klonen oder kopiere die Skripte auf deinen VPS.
2. Starte das Setup:
   ```bash
   sudo ./prodstart.sh
   ```
3. **Setup-Wizard**:
   - Wähle, welche Dienste aktiviert werden sollen (Claude, Codex oder beide).
   - Gib dein gewünschtes Workspace-Verzeichnis an.
   - **Auto-Install**: Falls Claude oder Codex fehlen, fragt das Skript, ob sie automatisch installiert werden sollen.
   - **Geführter Login**: Das Skript prüft deine Zugangsdaten. Falls du noch nicht eingeloggt bist, wird eine interaktive CLI-Sitzung gestartet, über die du dich per Web/QR-Code einloggen kannst.
   - **API-Key Abfrage**: Falls Codex mit einem API-Key verwendet werden soll, wirst du zur Eingabe aufgefordert, falls noch kein Schlüssel in der Konfiguration vorhanden ist.

---

## Lokale Entwicklung (Local Dev)

Für die lokale Entwicklung auf deinem Entwickler-Rechner (z. B. macOS oder Linux) nutzt du das lokale `.env` File im Projektverzeichnis.

1. Führe das Skript im Projektverzeichnis aus:
   ```bash
   ./devstart.sh
   ```
   *Hinweis: Wenn keine lokale `.env` existiert, sucht das Skript in den übergeordneten Ordnern nach einem `secret/`-Verzeichnis (z. B. `../secret/env.remotemanagement`) und kopiert es automatisch.*

2. Das Skript lädt die lokale `.env`, sucht nach `claude` und `codex` in deinem lokalen `$PATH` (um VPS-Pfade zu überschreiben) und startet beide Remote-Control-Prozesse interaktiv im Hintergrund deines Terminals.

3. **Beenden**: Drücke einfach `[Ctrl+C]` im Terminal. Alle gestarteten Prozesse werden sofort sauber beendet.

---

## Befehle & Verwaltung

Nach der ersten Installation auf dem VPS kannst du die Befehle von überall aus aufrufen:

### Dienste starten/aktualisieren (Produktion)
Führt bei interaktivem Terminal den Konfigurations-Assistenten aus und startet die systemd-Services neu. Bei nicht-interaktivem Aufruf werden direkt die Services geladen:
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

Die Datei wird unter `/etc/claude-remote/config.env` (Produktion) oder im Projekt-Root als `.env` (Entwicklung) abgelegt und automatisch abgesichert (`chmod 600`).

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
