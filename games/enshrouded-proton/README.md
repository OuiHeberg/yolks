# `ghcr.io/ouiheberg/yolks:enshrouded-proton`

Image d'exécution des serveurs Enshrouded sous **GE-Proton 11-9**, avec fsync.
Prévue en second choix de l'egg Enshrouded **8034**, qui tourne aujourd'hui sous
`ghcr.io/ptero-eggs/yolks:wine_latest` (Wine stable, sans esync, fsync ni ntsync).

Construite et publiée par `.github/workflows/enshrouded-proton.yml`, seulement
depuis `main`. Avant de publier, le workflow rejoue sur l'image à publier tous
les contrôles du banc (voir « Contrôles »). Il pousse le tag daté, puis le tag
courant, vérifie que les deux mènent au digest poussé, et tire l'image par ce
digest, sans identifiant, pour la recontrôler.

| Tag | Rôle |
| --- | --- |
| `ghcr.io/ouiheberg/yolks:enshrouded-proton` | tag courant, à mettre dans l'egg |
| `ghcr.io/ouiheberg/yolks:enshrouded-proton-AAAAMMJJ-sha7-run-tentative` | tag daté de chaque publication, pour le retour arrière (`run` : numéro du run GitHub Actions, `tentative` : numéro de sa relance, pour qu'aucune autre publication, ni relance, ne l'écrase) |

## Commande de démarrage de l'egg pour cette image

C'est la commande Wine actuelle de l'egg 8034, avec les mêmes gardes (fichiers du
jeu absents = arrêt avec un message) et la même rotation du journal (`.log.1` à
`.log.3`), où `wine ./enshrouded_server.exe` devient
`${PROTON_PATH}/proton run enshrouded_server.exe`. Le chemin de l'exe reste
**relatif** : avec un chemin absolu, Proton passe par `umu.exe` et le serveur
reste bloqué. La garde du préfixe Wine sans certificats n'a pas lieu d'être sous
Proton, qui gère son propre préfixe.

<!-- startup:begin -->
```sh
mkdir -p ./logs; if [ ! -s ./enshrouded_server.exe ]; then echo "ERROR: the game files are missing (enshrouded_server.exe), the download from Steam did not complete. Proton is not started. Restart the server to try the download again (Auto Update must be enabled). If it keeps failing, contact support."; exit 1; fi; for i in 2 1; do test -f ./logs/enshrouded_server.log.$i && mv -f ./logs/enshrouded_server.log.$i ./logs/enshrouded_server.log.$((i+1)); done; test -f ./logs/enshrouded_server.log && mv -f ./logs/enshrouded_server.log ./logs/enshrouded_server.log.1; WINEDEBUG=-all ${PROTON_PATH}/proton run enshrouded_server.exe & ENS_PID=$!; tail -n 0 -F ./logs/enshrouded_server.log --pid=$ENS_PID
```
<!-- startup:end -->

Le banc de la PR lit la commande entre ces deux repères : la changer ici la fait
retester.

### Avant d'ajouter l'image à l'egg

Dans le panel, la commande de démarrage et l'image sont **copiées dans chaque
serveur**. La plupart des serveurs Enshrouded gardent la commande de l'egg, et
certains ont déjà une autre image (par exemple `ghcr.io/ptero-eggs/steamcmd:proton`).
Le vrai risque est ailleurs : dès que cette image entre dans la liste de l'egg,
un client peut la choisir en gardant la commande Wine, et son serveur s'arrête
sur `wine: command not found`. L'étape suivante est donc une commande d'egg qui
choisit Proton quand `PROTON_PATH` est défini (cette image) et Wine sinon, à
essayer aussi avec les images déjà en place. Elle n'est pas dans ce dépôt :
c'est une étape à part, à décider séparément.

## Ce que fait l'image

- `entrypoint.sh` (format des yolks) : `cd /home/container`, mise à jour du jeu
  par le SteamCMD du volume (`./steamcmd`, posé par le script d'installation de
  l'egg) en anonyme si `AUTO_UPDATE` est vide ou vaut `1` (`VALIDATE` non vide =
  validation des fichiers, comme l'image Wine), copie de
  `steamcmd/linux64/steamclient.so` et `linux32` dans `~/.steam/sdk64` et
  `sdk32` quand elle diffère, puis `eval` de `STARTUP`.
- Variables de l'image : `PROTON_PATH=/opt/proton`, `GE_PROTON_VERSION=11-9`,
  `UMU_ID=0`, `WINEDEBUG=-all`, `LANG=en_US.UTF-8`,
  `STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/container/steamcmd`,
  `STEAM_COMPAT_DATA_PATH=/home/container/.steam/compatdata/2278520`.
- Le préfixe Proton est dans `.steam/compatdata/2278520`, que le `.pteroignore`
  de l'egg exclut des sauvegardes (`.steam`). Ce `.pteroignore` n'est écrit
  qu'à l'installation, par le script de l'egg, depuis le 26/10/2026 : un serveur
  installé avant n'en a pas, et sa sauvegarde contiendrait aussi le préfixe
  Proton (en plus du jeu et de `.wine`, qu'elle contient déjà). Le préfixe Wine
  (`.wine`) n'est pas touché : il resservira tel quel en cas de retour à l'image
  Wine. Le monde (`savegame`) et `enshrouded_server.json` sont les mêmes pour
  les deux images.
- Utilisateur `container` (UID 988), `HOME=/home/container`. Aucun secret.

## Arrêt du serveur

L'arrêt `^C` de l'egg devient un arrêt Docker : Wings appelle `ContainerStop`
sans fixer de signal (avec le délai Docker `-1`, sans limite), et Docker envoie
le `STOPSIGNAL` de l'image, **SIGINT** (comme `wine_latest` et `:dayz`), à
tini, qui le relaie à tout le groupe de processus.

Juste avant la commande de démarrage, l'entrypoint ignore SIGINT et SIGTERM
(`trap '' INT TERM`). `tail` et le script `proton` en héritent, et ne meurent
donc plus au signal. Wine, lui, installe toujours son propre gestionnaire de
SIGINT et le transmet au jeu comme un Ctrl+C (`CTRL_C_EVENT`) : le jeu
sauvegarde et s'arrête, `tail --pid` rend la main, et le conteneur s'arrête
sans être tué. Son code de sortie est 1 : c'est celui de `tail`, qui n'a pas
trouvé le journal à son lancement (la rotation venait de le déplacer), comme
avec la commande Wine. Sans ce trap, `tail` et l'entrypoint mouraient aussitôt, tini
(PID 1) sortait, et le noyau tuait le jeu pendant sa sauvegarde.

Wings n'attend pas sans limite. Il attend l'arrêt du conteneur par
`WaitForStop` avec `terminate` : passé le délai, il le tue (SIGKILL), sans
sauvegarde. Le délai dépend de la cause de l'arrêt (sources du Wings de
OuiHeberg) :

| Cause | Délai | Source |
| --- | --- | --- |
| « Stop » et « Restart » | 10 minutes | `server/power.go` |
| suspension du serveur, disque plein | 1 minute | `server/update.go`, `server/listeners.go` |
| réinstallation, import | 10 secondes | `server/install.go`, `server/import.go` |

Un jeu bloqué fait donc attendre un « Stop » jusqu'à 10 minutes. Un arrêt de
dockerd ou un redémarrage du nœud couperait sans doute le jeu au bout de
10 secondes : Wings ne fixe pas `StopTimeout` à la création du conteneur
(`environment/docker/container.go`), et Docker applique alors son délai par
défaut, 10 secondes, avant SIGKILL (sauf avec `live-restore`, qui garde les
conteneurs pendant un redémarrage de dockerd). Dans les cas à 1 minute ou
moins, la sauvegarde du monde peut être coupée. Le bouton « Kill » du panel
envoie SIGKILL tout de suite.

La mise à jour SteamCMD du démarrage, qui passe avant le trap, reste
interruptible. Un arrêt reçu pendant cette mise à jour est noté par
l'entrypoint, qui sort en 0 sans afficher ni lancer la commande de démarrage,
même si SteamCMD intercepte le signal et sort en 0.

Un « Stop » envoyé dans les secondes qui suivent un « Start » (plus longtemps
au premier démarrage, le temps que Proton crée son préfixe) peut rester sans
effet jusqu'au « Kill », ou jusqu'aux 10 minutes de Wings. Le jeu n'a pas
encore posé son gestionnaire de Ctrl+C, et le SIGINT, ignoré jusque-là, est
perdu.

## Prérequis du nœud

fsync repose sur l'appel système `futex_waitv` : noyau **5.16 ou plus**, et un
profil seccomp qui le laisse passer (le profil par défaut de Docker 29 le
permet). Sans lui, Wine se rabat sur esync ou sur rien, et le gain disparaît.
Contrôle dans un conteneur de l'image, avec des arguments vides : `-1 EINVAL` =
l'appel existe et passe le seccomp ; `-1 ENOSYS` = noyau trop ancien ;
`-1 EPERM` = refusé par le seccomp.

```sh
docker run --rm --network none --entrypoint python3 ghcr.io/ouiheberg/yolks:enshrouded-proton -I -c 'import ctypes, errno; l = ctypes.CDLL(None, use_errno=True); r = l.syscall(449, 0, 0, 0, 0, 0); print(r, errno.errorcode.get(ctypes.get_errno()))'
```

## Contrôles

- À la construction : empreinte SHA-512 de l'archive GE-Proton, ligne
  `lsteamclient=d` présente une seule fois avant le patch et absente après,
  script `proton` toujours lisible par Python.
- Signal d'arrêt de l'image : `SIGINT` (`docker inspect`).
- `tests/image-check.sh`, lancé **dans** l'image sans réseau : utilisateur 988,
  variables, Proton (`proton`, `version`, `wine`, `wineserver`,
  `files/share/default_pfx`, pas de `steampipe_fixups.json`), patch, rien de
  modifiable par l'UID 988, `libvulkan.so.1`, locale, entrypoint.
- `tests/entrypoint-check.sh <image>`, lancé sur l'hôte sans réseau avec les
  réglages de Wings (UID 988, racine en lecture seule, `/tmp` en tmpfs) :
  - mise à jour sautée avec `AUTO_UPDATE=0`, avertissement sans SteamCMD avec
    `AUTO_UPDATE=1`, copie et mise à jour de `steamclient.so`, garde de la
    commande quand le jeu manque ;
  - la commande ci-dessus en entier avec un faux `proton`
    (`tests/fake-proton`, par `PROTON_PATH`) : rotation du journal, arguments
    (`run enshrouded_server.exe`, chemin relatif), `tail`, puis `docker stop` :
    le faux jeu reçoit SIGINT, finit sa sauvegarde, et le conteneur sort sans
    être tué (code inférieur à 128).
  - `docker stop` pendant la mise à jour, avec un faux SteamCMD qui intercepte
    SIGINT et sort en 0 : le conteneur sort en 0 sans lancer le jeu.
- `tests/proton-stop-check.sh <image> <exe>` : la même chose sous le **vrai**
  Proton de l'image, avec un programme console Windows (`tests/fake-game.c`,
  compilé par mingw-w64 dans le banc) à la place du jeu. Le contrôle vérifie
  trois choses :
  - le programme est dans le groupe de processus de l'entrypoint ;
  - Wine intercepte SIGINT dans ce processus ;
  - `docker stop` lui envoie un Ctrl+C, il finit sa sauvegarde et le conteneur
    sort sans être tué.

## Retour arrière

- Pour un serveur : remettre l'image `ghcr.io/ptero-eggs/yolks:wine_latest` et
  la commande Wine de l'egg. Le monde et `.wine` sont restés en place.
- Pour l'image : mettre dans l'egg un tag daté précédent
  (`enshrouded-proton-AAAAMMJJ-sha7-run-tentative`), ou annuler le commit fautif sur `main`
  (le workflow republie alors le tag courant).
