# `ghcr.io/ouiheberg/yolks:enshrouded-proton`

Image d'exécution des serveurs Enshrouded sous **GE-Proton 11-9**, avec fsync.
Prévue en second choix de l'egg Enshrouded **8034**, qui tourne aujourd'hui sous
`ghcr.io/ptero-eggs/yolks:wine_latest` (Wine stable, sans esync, fsync ni ntsync).

Construite et publiée par `.github/workflows/enshrouded-proton.yml` :

| Tag | Rôle |
| --- | --- |
| `ghcr.io/ouiheberg/yolks:enshrouded-proton` | tag courant, à mettre dans l'egg |
| `ghcr.io/ouiheberg/yolks:enshrouded-proton-AAAAMMJJ-sha7` | tag daté de chaque publication, pour le retour arrière |

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

La commande de démarrage est **commune à tous les serveurs de l'egg**. Ajouter
l'image en second choix demande donc soit une commande propre à chaque serveur
passé sous Proton, soit une commande d'egg qui choisit Proton quand
`PROTON_PATH` est défini et Wine sinon. C'est une étape à part, sur décision
d'Arthur.

## Ce que fait l'image

- `entrypoint.sh` (format des yolks) : `cd /home/container`, mise à jour du jeu
  par le SteamCMD du volume (`./steamcmd`, posé par le script d'installation de
  l'egg) en anonyme si `AUTO_UPDATE` est vide ou vaut `1` (`VALIDATE` non vide =
  validation des fichiers, comme l'image Wine), copie de
  `steamcmd/linux64/steamclient.so` et `linux32` dans `~/.steam/sdk64` et
  `sdk32` quand elle diffère, puis `eval` de `STARTUP`.
- Variables de l'image : `PROTON_PATH=/opt/proton`, `GE_PROTON_VERSION=11-9`,
  `UMU_ID=0`, `WINEDEBUG=-all`,
  `STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/container/steamcmd`,
  `STEAM_COMPAT_DATA_PATH=/home/container/.steam/compatdata/2278520`.
- Le préfixe Proton est dans `.steam/compatdata/2278520`, que le `.pteroignore`
  de l'egg exclut déjà des sauvegardes (`.steam`). Le préfixe Wine (`.wine`)
  n'est pas touché : il resservira tel quel en cas de retour à l'image Wine. Le
  monde (`savegame`) et `enshrouded_server.json` sont les mêmes pour les deux
  images.
- Utilisateur `container` (UID 988), `HOME=/home/container`. Aucun secret.

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
- `tests/image-check.sh`, lancé **dans** l'image sans réseau : utilisateur 988,
  variables, Proton (`proton`, `version`, `wine`, `wineserver`), patch,
  `libvulkan.so.1`, entrypoint.
- `tests/entrypoint-check.sh <image>`, lancé sur l'hôte sans réseau avec les
  réglages de Wings (UID 988, racine en lecture seule, `/tmp` en tmpfs) : mise à
  jour sautée avec `AUTO_UPDATE=0`, avertissement sans SteamCMD avec
  `AUTO_UPDATE=1`, copie et mise à jour de `steamclient.so`, `eval` de la
  commande ci-dessus, et sa garde quand le jeu manque.

## Retour arrière

- Pour un serveur : remettre l'image `ghcr.io/ptero-eggs/yolks:wine_latest` et
  la commande Wine de l'egg. Le monde et `.wine` sont restés en place.
- Pour l'image : mettre dans l'egg un tag daté précédent
  (`enshrouded-proton-AAAAMMJJ-sha7`), ou annuler le commit fautif sur `main`
  (le workflow republie alors le tag courant).
