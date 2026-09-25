# Remote-Workspace: welche Repos ChatGPT/Desktop Commander sehen darf

Dieses Dokument beschreibt den **Live-Zustand auf der VPS** (`patigon@185.196.21.153`, Hostname `vmd171243`), der regelt, welche Projekte der Desktop-Commander-Service (`desktop-commander-remote.service`, läuft als `patigon-remote`) lesen und beschreiben kann. Stand: 2026-09-25, verifiziert per SSH.

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

| Repo | Bind-Mount | fstab | ACL rwx (Verzeichnis) | `.env` gesperrt |
|---|---|---|---|---|
| `capential` | ✅ | ✅ | ✅ | — (kein `.env` mit Secrets vorhanden geprüft) |
| `omniperc` | ✅ | ✅ | ✅ | — |
| `orthonovex` | ✅ | ✅ | ✅ | ✅ (`.env` → `Permission denied` für `patigon-remote`) |
| `unissito` | ✅ | ✅ | ✅ | — |

**Nicht** im Workspace, kein ACL-Eintrag, für `patigon-remote` unzugänglich (`Permission denied`):
- `/home/patigon/secret` (700, Owner-only)
- `/home/patigon/patigon` (persönlicher Ordner)
- alle anderen Projektverzeichnisse unter `/home/patigon` (z. B. weitere `patigon-*`-Checkouts), die nicht explizit onboarded wurden

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

## Offen / noch nicht umgesetzt: pro Repo eigener GitHub-Key

**Anforderung (noch nicht implementiert, Stand 2026-09-25):** Jedes ans Remote-Team freigegebene Repo soll einen **eigenen, auf genau dieses Repo beschränkten GitHub-Token mit Read/Write** in seiner eigenen `.env`/`config.env` bekommen — geprüft, aktuell hat **keines** der vier Repos (`capential`, `omniperc`, `orthonovex`, `unissito`) eine `GITHUB_*`/`GH_*`-Variable in `.env` oder `.env.example`.

Grund: verhindert, dass ein Agent, der in Repo A arbeitet, mit demselben Token auch in Repo B pushen/PRs öffnen kann — Blast Radius pro Repo statt ein globaler Schlüssel für alles.

**Empfehlung für Umsetzung (noch zu entscheiden/auszuführen):**
1. Pro Repo ein **fine-grained GitHub Personal Access Token** erstellen, Scope: nur dieses eine Repository, Contents (read/write) + Pull requests (read/write).
2. Key-Name-Konvention festlegen (z. B. `GITHUB_TOKEN` in jedem Repo) und in jedem `.env.example` dokumentieren.
3. In die jeweilige `.env` eintragen — **nicht committen**, jede `.env` bleibt gitignored.
4. Diese Datei (oder die betroffene `.env`) nach Erstellung ebenfalls per `chmod 600` sperren (Schritt 4 im Runbook oben), damit sie über die ACL-Ausnahme genauso geschützt ist wie andere Secrets.

Da das Erstellen von GitHub-Tokens eine manuelle Aktion im GitHub-UI (oder `gh auth`) mit explizitem Scope-Entscheid ist, ist das hier bewusst nicht automatisiert worden.
