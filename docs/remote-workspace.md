# Remote-Workspace: welche Repos ChatGPT/Desktop Commander sehen darf

Dieses Dokument beschreibt den **Live-Zustand auf der Produktions-VPS** (Zugangsdaten siehe privates `secret`-Repo, nicht hier), der regelt, welche Projekte der Desktop-Commander-Service (`desktop-commander-remote.service`, läuft als `patigon-remote`) lesen und beschreiben kann. Stand: 2026-09-25, verifiziert per SSH.

> **Hinweis:** Dieses Repo (`patigon-remotemanagement`) ist öffentlich. Keine IPs, Hostnames, Tokens oder sonstigen konkreten Zugangsdaten hier eintragen — nur Mechanik/Architektur dokumentieren.

Ziel des Designs: **ausgewählte Projekt-Repos voll les-/schreibbar für ChatGPT, aber ohne Secrets** (`.env`, `config.env`, `secret/`, persönlicher `patigon`-Ordner).

## Architektur

```
/home/patigon/<repo>/                  ← echtes Git-Repo, Owner patigon, CI-Runner arbeitet hier
        ▲ bind mount (in /etc/fstab, überlebt Reboot)
/opt/ai-workspace-mounts/<repo>/       ← Mountpoint, identische Inodes wie oben (kein Kopieren)
        ▲ symlink
/opt/ai-workspace/<repo>               ← das ist WORKSPACE_DIR aus /etc/claude-remote/config.env
```

`WORKSPACE_DIR=/opt/ai-workspace` zeigt **nicht** direkt auf `/home/patigon`, sondern auf einen kuratierten Ordner mit einem Symlink pro freigegebenem Repo. Nur was hier verlinkt ist, ist für Desktop Commander sichtbar.

### Warum nicht einfach `WORKSPACE_DIR=/home/patigon` setzen?

`scripts/prodstart.sh` macht beim Start automatisch (Zeilen ~283-285):
```bash
chgrp -R "$REMOTE_GROUP" "$WORKSPACE_DIR"
chmod -R g+rwX "$WORKSPACE_DIR"
find "$WORKSPACE_DIR" -type d -exec chmod g+s {} +
```
Das ist **pauschal und ohne Ausnahme für Secrets**. Würde `WORKSPACE_DIR` direkt auf `/home/patigon` zeigen, bekäme die Gruppe `ai-remote` (und damit `patigon-remote`/ChatGPT) automatisch Schreibzugriff auf **alles** darunter — inklusive `secret/`, persönlichem Kram und jeder `.env`-Datei in jedem Projekt.

Der Symlink-Umweg über `/opt/ai-workspace` umgeht das: `chmod -R`/`chgrp -R` von GNU coreutils **folgen Symlinks bei der Rekursion nicht**. Ein `prodstart`-Rerun verändert also nur `/opt/ai-workspace` selbst (und harmlos die Symlinks), fasst aber die eigentlichen Repo-Inhalte unter `/opt/ai-workspace-mounts/*` bzw. `/home/patigon/*` **nicht an**. Die feingranularen ACLs unten (Punkt 2) bleiben über `prodstart`-Reruns hinweg stabil.

### Zugriffsmodell (zwei Ebenen)

1. **Verzeichnis-ACL** (rekursiv, inkl. Default-ACL für neue Dateien):
   ```bash
   setfacl -R -m g:ai-remote:rwx -d -m g:ai-remote:rwx /home/patigon/<repo>
   ```
   Gibt der Gruppe `ai-remote` volles rwx auf alles im Repo, auch künftig neu angelegte Dateien.

2. **Secret-Dateien einzeln sperren** — trotz Punkt 1:
   ```bash
   chmod 600 /home/patigon/<repo>/.env
   ```
   Wichtig: `chmod` auf eine Datei mit ACL-Einträgen schreibt die ACL-**Maske** neu (nicht die einzelnen Named-Entries). Effekt: der ACL-Eintrag `group:ai-remote:rwx` bleibt zwar formal stehen, ist aber **effektiv `---`**, weil die Maske alles kappt. Verifiziert per `getfacl`:
   ```
   group:ai-remote:rwx	#effective:---
   mask::---
   ```
   Kein Löschen von ACL-Einträgen nötig — ein simples `chmod 600` auf die konkrete Secret-Datei reicht, auch nachträglich.

## Aktueller Stand (verifiziert per `sudo -u patigon-remote`)

| Repo | Bind-Mount | fstab | ACL rwx (Verzeichnis) | Alle `.env`-Dateien für Agent lesbar |
|---|---|---|---|---|
| `capential` | ✅ | ✅ | ✅ | ✅ (Root `.env`, `frontend/.env`) |
| `omniperc` | ✅ | ✅ | ✅ | ✅ (`backend/.env`) |
| `orthonovex` | ✅ | ✅ | ✅ | ✅ (Root `.env`, `backend/.env`, `frontend/.env`) |
| `unissito` | ✅ | ✅ | ✅ | ✅ (`unissito-mcp/.env`) |

Verifiziert per `sudo -u patigon-remote head -c1 <datei>` über den echten `/opt/ai-workspace/...`-Pfad (nicht nur `getfacl` angeschaut — ACL-Anzeige und tatsächliche Lesbarkeit über den Symlink/Bind-Mount-Pfad können auseinanderfallen, siehe Gotcha unten).

**Bewusste Design-Entscheidung (2026-09-25):** `.env`-Dateien werden für `patigon-remote` **nicht** einzeln gesperrt — alle sieben oben sind offen (`mask::rw-`). Mehrere davon waren ursprünglich per `chmod 600`/ACL-Maske (`mask::---`) gesperrt (Mechanik siehe Punkt 2 oben — funktioniert weiterhin, falls man einzelne Dateien wieder schützen will); das wurde bewusst aufgehoben, weil der Agent pro Repo einen GitHub-Push-Token direkt aus der echten `.env` lesen soll (siehe nächster Abschnitt) und eine Teil-Sperre einzelner Variablen als nicht lohnend bewertet wurde. Wer das wieder einschränken will: `chmod 600` pro Datei.

**Gotcha 3:** Beim erstmaligen Öffnen wurden nur `orthonovex/.env` (Root) und `omniperc/backend/.env` tatsächlich entsperrt/geprüft — `capential/.env`, `capential/frontend/.env`, `orthonovex/backend/.env`, `orthonovex/frontend/.env` und `unissito-mcp/.env` blieben unbemerkt gesperrt, bis ein Test über ChatGPT/Desktop Commander das aufdeckte. **Lektion:** Bei „alle `.env` öffnen" wirklich *jede* Datei einzeln mit `getfacl` prüfen (`grep '^mask'`), nicht nur eine pro Repo stichprobenartig — die Maske sitzt pro Datei, nicht pro Repo.

**Nicht** im Workspace, kein ACL-Eintrag, für `patigon-remote` unzugänglich (`Permission denied`):
- `/home/patigon/secret` (700, Owner-only)
- `/home/patigon/patigon` (persönlicher Ordner)
- alle anderen Projektverzeichnisse unter `/home/patigon` (z. B. weitere `patigon-*`-Checkouts), die nicht explizit onboarded wurden

**Gotcha, live erlebt:** Nicht jedes Repo hat seine echte Config im Root. Vor dem Anlegen/Ändern einer `.env` immer erst prüfen, wo die *tatsächlich gelesene* Datei liegt (`.env.example` daneben ist ein guter Hinweis) — sonst legt man eine wirkungslose Datei an der falschen Stelle an. Live falsch geraten: `omniperc` (echte Config liegt in `backend/.env`, nicht im Root) und `unissito` (echte Config liegt in `unissito-mcp/.env`, es gibt gar kein Root-`.env`).

**Gotcha 2:** Vor jedem Kopieren einer `secret/`-Vorlage über eine *bestehende* Live-`.env` erst per Key-Namen diffen (`grep -oE '^[A-Z_]+=' datei | sort`). Bei `capential` enthielt die Secret-Vorlage ~50 zusätzliche Keys gegenüber der Live-Datei, darunter Trading/Broker-Flags — ein blindes Überschreiben hätte Produktionsverhalten ändern können. Nur nach expliziter Bestätigung überschrieben, vorher Backup nach `/home/patigon/backups/` gezogen.

## Runbook: neues Repo freigeben

1. Mountpoint anlegen + Bind-Mount + persistieren:
   ```bash
   sudo mkdir -p /opt/ai-workspace-mounts/<repo>
   sudo mount --bind /home/patigon/<repo> /opt/ai-workspace-mounts/<repo>
   echo "/home/patigon/<repo> /opt/ai-workspace-mounts/<repo> none bind 0 0" | sudo tee -a /etc/fstab
   ```
2. Symlink in den Workspace:
   ```bash
   sudo ln -s /opt/ai-workspace-mounts/<repo> /opt/ai-workspace/<repo>
   sudo chown -h root:ai-remote /opt/ai-workspace/<repo>
   ```
3. ACL auf dem echten Repo-Pfad setzen (nicht auf dem Symlink/Mountpoint — dort landet sie automatisch mit, aber die Quelle ist maßgeblich):
   ```bash
   sudo setfacl -R -m g:ai-remote:rwx -d -m g:ai-remote:rwx /home/patigon/<repo>
   ```
4. Jede Secret-Datei im Repo einzeln sperren (mindestens `.env`, ggf. `config.env`, alles was `secret/` heißt):
   ```bash
   sudo chmod 600 /home/patigon/<repo>/.env
   ```
5. Verifizieren:
   ```bash
   sudo -u patigon-remote bash -c 'ls /opt/ai-workspace && touch /opt/ai-workspace/<repo>/.dc_test && rm /opt/ai-workspace/<repo>/.dc_test'
   sudo -u patigon-remote cat /opt/ai-workspace/<repo>/.env   # muss "Permission denied" liefern
   ```

Ein Repo wieder entziehen: Symlink in `/opt/ai-workspace` löschen reicht für Desktop Commander (WORKSPACE_DIR-Sicht), lässt aber Mount + ACL bestehen — für vollständigen Rückbau zusätzlich `umount`, fstab-Zeile entfernen, `setfacl -R -b` auf dem Repo.

## Pro-Repo GitHub-Zugang: Fine-grained PAT pro Repo, in der echten `.env`

**Anforderung:** Jedes ans Remote-Team freigegebene Repo soll einen **eigenen, auf genau dieses Repo beschränkten GitHub-Zugang mit Read/Write** haben — verhindert, dass ein Agent, der in Repo A arbeitet, mit demselben Credential auch in Repo B pushen/PRs öffnen kann.

**Status (Stand 2026-09-25): umgesetzt und end-to-end verifiziert.**

### Verworfene Alternative: SSH-Deploy-Key pro Repo

Erste Idee war ein SSH-Deploy-Key pro Repo (GitHub Deploy Keys sind von Natur aus auf ein Repo beschränkt). Dafür existierten bereits vier Keys `chatgpt-<repo>-<hostname>` (read/write) auf GitHub plus passende private Keys in `secret/deploy-keys/chatgpt/`. Verworfen, weil: `patigon-remote` hat kein Home-Verzeichnis und damit keine `~/.ssh/config` — SSH-Host-Aliase (`Host github-<repo>`) sind aber per-User-Konfiguration in `~/.ssh/config`, nicht am Repo hängend. Das hätte einen eigenen Home-Ordner + `.ssh/config`-Aufbau für den Service-Account gebraucht. **Diese Deploy-Keys wurden inzwischen von GitHub entfernt und die privaten Key-Dateien aus `secret/` gelöscht** — nicht mehr verwenden, falls sie irgendwo in altem Kontext auftauchen.

### Gewählter Mechanismus: fine-grained PAT + HTTPS

Statt SSH: pro Repo ein **fine-grained GitHub Personal Access Token**, gespeichert als `AGENT_GITHUB_TOKEN=` direkt in der **echten, vom jeweiligen Service tatsächlich gelesenen `.env`-Datei** (nicht in einer separaten Datei — siehe "bewusste Design-Entscheidung" oben, warum `.env`-Sperren dafür aufgehoben wurden).

- **Token-Setup pro Repo:** GitHub → Settings → Developer settings → Fine-grained tokens → Only select repositories (genau 1 Repo) → Permissions: **Contents: Read and write**, **Pull requests: Read and write**. Kein Ablaufdatum (Service-Credential, keine manuelle Rotation vorgesehen) — GitHub warnt davor, hier bewusst in Kauf genommen.
- **Namenskonvention:** `<repo>-read-write-vps` (z. B. `orthonovex-read-write-vps`), damit auf einen Blick klar ist, wofür der Token ist.
- **Variablenname:** `AGENT_GITHUB_TOKEN` — **nicht** `GITHUB_TOKEN`, weil dieser Name in mindestens einem Repo (`unissito`) schon für ein anderes Feature (Source-Ingestion der MCP-App) belegt war. Vor dem Eintragen in ein neues Repo immer erst prüfen, ob `GITHUB_TOKEN`/`AGENT_GITHUB_TOKEN` dort schon zweckentfremdet ist.
- **Backup der Vorlagen:** Werte liegen zusätzlich in `secret/env.<repo>.<component>` (bzw. `secret/env.unissito`), damit sie bei einem VPS-Rebuild nicht verloren gehen. `secret`-Repo ist **privat** — dort dürfen echte Token-Werte stehen (im Gegensatz zu `patigon-remotemanagement`, siehe Hinweis oben).

**Echte Speicherorte** (verifiziert, nicht das Root-Schema blind angenommen):

| Repo | Datei mit `AGENT_GITHUB_TOKEN` |
|---|---|
| `capential` | `capential/.env` (Root) |
| `omniperc` | `omniperc/backend/.env` |
| `orthonovex` | `orthonovex/.env` (Root) + `orthonovex/backend/.env` |
| `unissito` | `unissito/unissito-mcp/.env` |

**Verwendung durch den Agenten (Push, ohne `origin` anzufassen):**
```bash
cd /opt/ai-workspace/<repo>
TOKEN=$(grep -oP '(?<=^AGENT_GITHUB_TOKEN=).*' <pfad-zur-echten-.env>)
git push "https://x-access-token:${TOKEN}@github.com/dudodkdkdkd/<github-repo-name>.git" <branch>:<branch>
```
Der bestehende `origin`-Remote (SSH, genutzt von `patigon` selbst und vom Deploy-Workflow) bleibt dabei komplett unangetastet — kein Risiko für die bestehende CI/Deploy-Pipeline.

**End-to-End getestet (2026-09-25):** Als `patigon-remote` echten Branch auf `patigon-orthonovex` gepusht (siehe Befehl oben), auf GitHub verifiziert, danach Branch lokal und remote wieder gelöscht. Funktioniert.
