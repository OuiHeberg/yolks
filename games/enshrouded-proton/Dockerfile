# ghcr.io/ouiheberg/yolks:enshrouded-proton : image d'exécution des serveurs
# Enshrouded sous GE-Proton 11-9, prévue en second choix de l'egg Enshrouded
# 8034 (qui tourne aujourd'hui sous ghcr.io/ptero-eggs/yolks:wine_latest).
#
# Pourquoi : sous Wine stable, sans esync, fsync ni ntsync, wineserver prend
# beaucoup de CPU. GE-Proton active fsync (appel futex_waitv, noyau 5.16 ou
# plus). Test du 07/11/2026, même monde des deux côtés, 5 minutes au repos :
# 49 % de CPU sous Wine contre 35 % sous Proton, et 11 752 changements de
# contexte par seconde pour wineserver contre 182.
#
# Recette reprise de jsknnr/enshrouded-server@a06a798b (PR #153, licence MIT) :
#  - GE-Proton 11-9 (GloriousEggroll), dont l'archive est vérifiée par
#    l'empreinte SHA-512 publiée avec la release (fichier .sha512sum) ;
#  - libvulkan1 : le script proton de GE-Proton 11 charge libvulkan.so.1 au
#    démarrage ;
#  - UMU_ID=0 met Proton en mode « umu sans Steam », qui ajoute
#    WINEDLLOVERRIDES=lsteamclient=d : le serveur ne charge alors plus le pont
#    Steam (« Failed to create Steamworks »). Cette ligne est retirée du script
#    proton. La construction échoue si la ligne n'y est plus (nouvelle version
#    de Proton : revoir le patch) ou si elle y reste ;
#  - WINEDEBUG=-all ;
#  - lancement par `proton run enshrouded_server.exe` en chemin RELATIF (commande
#    de démarrage de l'egg, voir README.md) : avec un chemin absolu, Proton
#    passe par umu.exe et le serveur reste bloqué sur un futex.
#
# Différences avec l'image du test du 07/11/2026 :
#  - LABEL, --platform et apt-get upgrade, comme games/dayz ;
#  - tzdata, pour que la variable TZ envoyée par Wings s'applique, comme dans
#    l'image Wine actuelle ;
#  - préfixe Proton dans .steam/compatdata/2278520 au lieu de .proton : le
#    .pteroignore de l'egg exclut déjà .steam des sauvegardes (comme .wine) ;
#  - steamclient.so recopié dans .steam/sdk64 et sdk32 quand SteamCMD le met à
#    jour (voir entrypoint.sh) ;
#  - STOPSIGNAL SIGINT, comme ptero-eggs/yolks:wine_latest et :dayz, et SIGINT
#    et SIGTERM ignorés par l'entrypoint pendant que le jeu tourne (voir plus
#    bas et entrypoint.sh) : l'arrêt laisse le jeu sauvegarder ;
#  - LANG=en_US.UTF-8, la locale générée (l'image Wine ne la pose que dans
#    /etc/default/locale, que le serveur ne lit pas ; le test du 07/11 tournait
#    sans LANG) ;
#  - pas d'architecture i386 : aucun paquet :i386 n'est installé (lib32gcc-s1,
#    pour SteamCMD, est un paquet amd64).
#
# Aucun secret dans l'image. Mettre à jour GE-Proton : changer les deux ARG
# (version, et empreinte SHA-512 lue dans le fichier
# GE-Proton<version>-x86_64.sha512sum de la release), puis vérifier que le
# patch lsteamclient s'applique toujours : la construction le dit.
#
# Image de base épinglée par empreinte (index de debian:13-slim relevé le
# 07/11/2026, celui du test) : la changer pour reprendre une nouvelle base ;
# `apt-get upgrade` reprend de toute façon les correctifs publiés depuis.
FROM        --platform=linux/amd64 debian:13-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

LABEL       maintainer="OuiHeberg"
LABEL       org.opencontainers.image.source="https://github.com/OuiHeberg/yolks"
LABEL       org.opencontainers.image.description="Enshrouded sous GE-Proton 11-9 (fsync), image d'exécution OuiPanel"

ARG         GE_PROTON_VERSION=11-9
ARG         GE_PROTON_SHA512=30160946a5e4ffdf1f29d6f83a3d27108f6aa71b6aa59095b2c2260fe3a003b62acf8fdcb02a3dfc602b28473f5679d8a3eaee5a8adb141c1dfa01c42888da2d

## /etc/machine-id est créé à la construction (comme chez jsknnr), donc commun à
## tous les conteneurs de l'image : sous Wings la racine est en lecture seule,
## il ne peut pas être régénéré au démarrage, et libdbus, que Wine peut charger,
## en a besoin. Le retirer n'est donc pas simple : il est gardé.
ENV         DEBIAN_FRONTEND=noninteractive
RUN         apt-get update \
            && apt-get upgrade -y \
            && apt-get install --no-install-recommends -y \
                procps ca-certificates winbind dbus libfreetype6 libvulkan1 curl \
                locales lib32gcc-s1 python3 tini iproute2 tzdata \
            && echo 'LANG="en_US.UTF-8"' > /etc/default/locale \
            && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
            && locale-gen \
            && rm -f /etc/machine-id && dbus-uuidgen --ensure=/etc/machine-id \
            && rm -rf /var/lib/apt/lists/* && apt-get clean

## GE-Proton : archive vérifiée, puis patch lsteamclient. Les deux contrôles
## (ligne présente une seule fois avant, absente après) font échouer la
## construction si le script proton a changé. L'archive 11-9 livre 15 fichiers
## en 0666 (files/share/xalia) : l'écriture est retirée au groupe et aux autres,
## pour que rien dans Proton ne soit modifiable par l'utilisateur du serveur.
RUN         curl -fsSL -o /tmp/ge.tar.gz \
                "https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton${GE_PROTON_VERSION}/GE-Proton${GE_PROTON_VERSION}-x86_64.tar.gz" \
            && echo "${GE_PROTON_SHA512}  /tmp/ge.tar.gz" | sha512sum -c - \
            && tar xzf /tmp/ge.tar.gz --no-same-owner -C /opt && rm -f /tmp/ge.tar.gz \
            && mv "/opt/GE-Proton${GE_PROTON_VERSION}-x86_64" "/opt/GE-Proton${GE_PROTON_VERSION}" \
            && chmod -R go-w "/opt/GE-Proton${GE_PROTON_VERSION}" \
            && test "$(grep -cF 'append_to_env_str(self.env, "WINEDLLOVERRIDES", "lsteamclient=d", ";")' "/opt/GE-Proton${GE_PROTON_VERSION}/proton")" = 1 \
            && sed -i 's/append_to_env_str(self.env, "WINEDLLOVERRIDES", "lsteamclient=d", ";")/pass/' "/opt/GE-Proton${GE_PROTON_VERSION}/proton" \
            && ! grep -q "lsteamclient=d" "/opt/GE-Proton${GE_PROTON_VERSION}/proton" \
            && python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "/opt/GE-Proton${GE_PROTON_VERSION}/proton" \
            && ln -s "/opt/GE-Proton${GE_PROTON_VERSION}" /opt/proton

## Utilisateur des volumes de Wings (pterodactyl, UID 988).
RUN         useradd -m -d /home/container -u 988 -s /bin/bash container

USER        container
ENV         USER=container \
            HOME=/home/container \
            LANG=en_US.UTF-8 \
            GE_PROTON_VERSION=${GE_PROTON_VERSION} \
            PROTON_PATH=/opt/proton \
            UMU_ID=0 \
            STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/container/steamcmd \
            STEAM_COMPAT_DATA_PATH=/home/container/.steam/compatdata/2278520 \
            WINEDEBUG=-all
WORKDIR     /home/container

## L'arrêt « ^C » de l'egg devient un arrêt Docker (ContainerStop de Wings, sans
## signal fixé, sans délai) : Docker envoie STOPSIGNAL à tini, qui le relaie au
## groupe de processus. Wine intercepte SIGINT et le transmet au jeu comme un
## Ctrl+C (CTRL_C_EVENT), qui sauvegarde et s'arrête. SIGTERM, lui, n'a pas de
## gestionnaire dans Wine.
STOPSIGNAL  SIGINT

COPY        --chmod=755 ./entrypoint.sh /entrypoint.sh
ENTRYPOINT  ["/usr/bin/tini", "-g", "--"]
CMD         ["/bin/bash", "/entrypoint.sh"]
