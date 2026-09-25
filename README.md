# VPS Remote Management Service Control

Dieses Repository enthält Skripte zur persistenten Einrichtung von **Claude Code**, **OpenAI Codex** und **Desktop Commander für ChatGPT**.

Alle drei Dienste werden über eine zentrale Konfiguration gesteuert, gestartet und gestoppt.

---

## Features

- **Zentrale Konfiguration**: Steuerung über ein einziges Environment-File.
- **Secret Auto-Discovery**: Skripte suchen automatisch nach einem Secret-Verzeichnis (z. B. `/secret`, `../secret` oder `../SECRET`) und kopieren vordefinierte Umgebungsvariablen (`env.remotemanagement`, `env.patigon-remotemanagement`), um die Einrichtung zu beschleunigen (analog zu Capential).
- **Interaktiver VPS-Setup-Assistent**: Bei Ausführung von `prodstart` im Terminal wirst du interaktiv durch die Auswahl der Dienste, Installation fehlender CLI-Tools sowie den Anmeldevorgang geleitet.
- **Auto-Installation**: Fehlende Binaries für Claude und Codex werden auf Wunsch installiert. Desktop Commander wird als festgelegte npm-Version unter `/usr/local/bin` installiert.
- **Login-Verifizierung**: Prüft vor dem Service-Start, ob gültige Anmeldedaten vorhanden sind, und startet bei Bedarf den geführten Login-Vorgang im Terminal.
- **Lokale Entwicklung (`devstart`)**: Starte Instanzen lokal im Vordergrund des Terminals mit interaktivem Logging und automatischem Cleanup (Ctrl+C). Verwendet das lokale `.env` im Projekt-Root und die Rechte werden automatisch abgesichert (`chmod 600`).
- **Autostart & Crash-Resistenz (Produktion)**: Automatischer systemd-Neustart nach System-Boot, Netzwerkunterbrechungen oder Abstürzen.
- **Codex-Release-Retention**: Ein täglicher systemd-Timer entfernt veraltete Codex-Standalone-Releases des verwalteten Dienstbenutzers. Die aktuelle, jede laufende und eine zusätzliche Rollback-Version bleiben erhalten.
- **Desktop Commander läuft als der installierende Benutzer**: Standardmäßig läuft der ChatGPT-Zugang als genau der Benutzer, der `sudo prodstart` ausgeführt hat (kein separates Service-Konto, keine Workspace-ACL). Wer stattdessen das alte, isolierte Service-Konto (`patigon-remote` + Gruppe `ai-remote` + kuratierte Workspace-ACL) will, ruft `prodstart-isolated-desktop-commander` statt `prodstart` auf.
- **Bequeme Verwaltung**: Globale Befehle `prodstart`, `prodstop` und `devstart` direkt im Terminal.

---

## Voraussetzungen

### 1. Berechtigungen
- **VPS (Produktion)**: Das Skript `prodstart.sh` benötigt Root-Rechte (`sudo`), um systemd-Units zu registrieren und globale Befehle zu hinterlegen.
- **Lokale Entwicklung**: `devstart.sh` wird als normaler Benutzer ohne `sudo` ausgeführt.
- **Desktop Commander**: Node.js 18 oder neuer und npm werden benötigt. Fehlt Node.js, bietet der Wizard die Installation über `apt-get` oder `dnf` an; die installierte Version wird danach geprüft.

---

## Installation & Erste Schritte (Produktion)

1. Klonen oder kopiere die Skripte auf deinen VPS.
2. Starte das Setup:
   ```bash
   sudo ./scripts/prodstart.sh
   ```
3. **Setup-Wizard**:
   - Wähle Dienste mit `1`, `2`, `3`, einer Kombination wie `1,3` oder `all`. Enter übernimmt die vorhandene Auswahl.
   - Gib dein gewünschtes Workspace-Verzeichnis an.
   - **Auto-Install**: Falls Claude oder Codex fehlen, fragt das Skript, ob sie automatisch installiert werden sollen.
   - **Geführter Login**: Das Skript prüft deine Zugangsdaten. Falls du noch nicht eingeloggt bist, wird eine interaktive CLI-Sitzung gestartet, über die du dich per Web/QR-Code einloggen kannst.
   - **API-Key Abfrage**: Falls Codex mit einem API-Key verwendet werden soll, wirst du zur Eingabe aufgefordert, falls noch kein Schlüssel in der Konfiguration vorhanden ist.
   - **Desktop Commander**: Der Wizard installiert die festgelegte Version und richtet die systemd-Unit ein. Standardmäßig läuft der Dienst als der Benutzer, der `sudo prodstart` ausgeführt hat (`$SUDO_USER`) mit dessen echtem Home-Verzeichnis - kein separates Service-Konto. Beim ersten Start zeigt er den Pairing-Code aus `journalctl`; bestätige den Code im Browser und drücke danach Enter.
   - **Legacy-Modus (isoliertes Service-Konto)**: Für das alte Modell mit dediziertem, eingeschränktem `patigon-remote`-Konto und kuratierter Workspace-ACL (Details in [`docs/remote-workspace.md`](docs/remote-workspace.md)) `sudo ./scripts/prodstart-isolated-desktop-commander.sh` (bzw. global `sudo prodstart-isolated-desktop-commander`) statt `prodstart` ausführen. Das setzt `DESKTOP_COMMANDER_ISOLATED_USER=true` in `config.env` und ruft danach denselben Wizard auf.

### ChatGPT verbinden und prüfen

Installiere einmalig den Remote-Desktop-Commander-Connector in ChatGPT und melde dich mit demselben Desktop-Commander-Konto an, mit dem die VPS gekoppelt wurde. Der Connector verwendet `https://mcp.desktopcommander.app/mcp`. Die [offizielle Remote-Setup-Anleitung](https://github.com/desktop-commander/remote-desktop-commander/blob/main/docs/SETUP.md) beschreibt die ChatGPT-Verbindung und Gerätefreigabe.

Teste danach in ChatGPT mit Desktop Commander `hostname`, `whoami` und `pwd`. Erwartet werden der VPS-Hostname, der Benutzer, der `sudo prodstart` ausgeführt hat (Standardmodus) bzw. `patigon-remote` (Legacy-Modus), und das konfigurierte `WORKSPACE_DIR`. Lasse anschließend die Repositories im Workspace auflisten. Erst dieser echte Dateisystem- und Terminaltest bestätigt den Zugriff; ein aktiver systemd-Dienst allein reicht dafür nicht.

**Standardmodus (dynamischer Benutzer):** Desktop Commander läuft als derselbe reale Login-Benutzer, der `sudo prodstart` ausgeführt hat, mit dessen eigenem Home-Verzeichnis - keine separate Gruppen-ACL, kein kuratierter Workspace nötig, weil der Benutzer ohnehin schon Owner seiner eigenen Dateien ist. Das bedeutet auch: voller Zugriff auf alles, was dieser Benutzer sehen kann, inklusive `secret/`, `.ssh` und anderer Projekte in seinem Home. Claude und Codex laufen weiterhin als `root`.

**Legacy-Modus (isoliertes Service-Konto, opt-in via `prodstart-isolated-desktop-commander`):** Desktop Commander läuft als eigener, eingeschränkter Benutzer `patigon-remote`. Der bekommt Gruppenrechte nur auf `WORKSPACE_DIR` - `prodstart` setzt dazu rekursiv die Gruppe `ai-remote`, Schreibrechte für die Gruppe und das Setgid-Bit auf Verzeichnissen. `WORKSPACE_DIR` ist in diesem Modus auf der Produktions-VPS kein direkter Projektordner, sondern ein kuratierter Symlink-Ordner über Bind-Mounts einzelner freigegebener Repos, mit `.env`-Dateien gezielt per `chmod`/ACL-Maske gesperrt. Details, aktuelle Freigabeliste und das Runbook zum Hinzufügen/Entziehen eines Repos stehen in [`docs/remote-workspace.md`](docs/remote-workspace.md).

---

## Lokale Entwicklung (Local Dev)

Für die lokale Entwicklung auf deinem Entwickler-Rechner (z. B. macOS oder Linux) nutzt du das lokale `.env` File im Projektverzeichnis.
Setze darin `WORKSPACE_DIR` auf ein Verzeichnis, das dein normaler Benutzer beschreiben kann (z. B. dein Projektverzeichnis); der VPS-Standard `/opt/ai-workspace` ist lokal möglicherweise nicht beschreibbar.

1. Führe das Skript im Projektverzeichnis aus:
   ```bash
   ./scripts/devstart.sh
   ```
   *Hinweis: Wenn keine lokale `.env` existiert, sucht das Skript in den übergeordneten Ordnern nach einem `secret/`-Verzeichnis (z. B. `../secret/env.remotemanagement`) und kopiert es automatisch.*

2. Das Skript lädt die lokale `.env`, findet die aktivierten Binaries im lokalen `$PATH` und startet sie im Hintergrund des Terminals. Desktop Commander nutzt dabei deinen lokalen Benutzer und dessen gespeicherte Gerätefreigabe.

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

### Deinstallation mit optionaler Gerätebereinigung
`prodstop` stoppt und deaktiviert die Units, behält aber die Dienst-Auswahl und Desktop-Commander-Gerätefreigabe. `prodstart` startet die ausgewählten Dienste später erneut. `--purge` entfernt zusätzlich die bisher verwalteten CLI-Tools und fragt bei interaktiver Ausführung separat, ob die Desktop-Commander-Installation, lokale Device-Credentials und der Service-User entfernt werden sollen:
```bash
sudo prodstop --purge
```

Eine Cloud-seitige Gerätefreigabe wird im Desktop-Commander-Dashboard separat widerrufen.

---

## Konfiguration (`config.env` oder `.env`)

Die Datei wird unter `/etc/claude-remote/config.env` (Produktion) oder im Projekt-Root als `.env` (Entwicklung) abgelegt und automatisch abgesichert (`chmod 600`).

| Variable | Beschreibung | Standardwert |
|---|---|---|
| `RUN_CLAUDE` | `true`/`false` - Aktiviert den Claude Code Remote-Control Dienst. | `true` |
| `RUN_CODEX` | `true`/`false` - Aktiviert den Codex Remote-Control Dienst. | `false` |
| `RUN_DESKTOP_COMMANDER` | Aktiviert Desktop Commander für ChatGPT. | `false` |
| `WORKSPACE_DIR` | Das Verzeichnis, aus dem die Remote-Sitzung gestartet wird. | `/opt/ai-workspace` |
| `CLAUDE_PATH` | Pfad zur Claude CLI (VPS-Standard). | `/root/.local/bin/claude` |
| `CODEX_PATH` | Pfad zur Codex CLI (VPS-Standard). | `/usr/local/bin/codex` |
| `DESKTOP_COMMANDER_PATH` | Pfad zur Desktop-Commander-CLI; Produktion installiert sie unter `/usr/local/bin`. | `/usr/local/bin/desktop-commander` |
| `DESKTOP_COMMANDER_VERSION` | Fest installierte npm-Version. | `0.2.51` |
| `DESKTOP_COMMANDER_ISOLATED_USER` | `false` = dynamischer Modus (Dienst läuft als `$SUDO_USER`, Werte unten werden ignoriert/überschrieben). `true` = Legacy-Modus mit dediziertem Service-Konto. | `false` |
| `DESKTOP_COMMANDER_USER` | Nur im Legacy-Modus relevant: Systembenutzer für den Remote-Device-Dienst. | `patigon-remote` |
| `DESKTOP_COMMANDER_HOME` | Nur im Legacy-Modus relevant: Home und Speicherort der Device-Credentials. | `/var/lib/patigon-remotemanagement` |
| `CODEX_AUTH_TYPE` | Authentifizierung für Codex: `subscription` (Abo) oder `api_key`. | `subscription` |
| `OPENAI_API_KEY` | Der OpenAI API-Key (nur bei `CODEX_AUTH_TYPE=api_key`). | `your_openai_api_key_here` |

---

## Logs & Fehlerbehebung

### Logs live mitlesen (VPS)
```bash
sudo journalctl -u claude-remote -f
sudo journalctl -u codex-remote -f
sudo journalctl -u desktop-commander-remote -f
```

### Status der Dienste prüfen (VPS)
```bash
sudo systemctl status claude-remote
sudo systemctl status codex-remote
sudo systemctl status desktop-commander-remote
sudo systemctl status codex-release-cleanup.timer
```

### Codex-Release-Cleanup prüfen

Das Produktionssetup bereinigt ausschließlich `/root/.codex`, weil der verwaltete
Codex-Dienst als `root` läuft. Andere Benutzerverzeichnisse werden nicht durchsucht.

```bash
sudo /usr/local/lib/patigon-remotemanagement/cleanup_codex_releases.sh \
  --codex-home /root/.codex --dry-run
```
