# ghcr.io/ouiheberg/yolks:dayz — image d'exécution des serveurs DayZ (egg 13944)
#
# Copie de ptero-eggs/yolks@3e6a1bc (games/dayz, David Wolfe « Red-Thirten »,
# licence MIT), gardée aussi proche que possible de l'original. Deux
# différences, dans entrypoint.sh :
#  - la mise à jour SteamCMD au démarrage est sautée quand le serveur n'a pas
#    d'identifiants Steam (compte connecté par QR dans le panel), au lieu de
#    refuser de démarrer ;
#  - les mods installés depuis l'onglet « Steam » du panel (liste
#    .ouipanel/workshop-mods.txt écrite par le crochet d'installation de
#    l'egg) sont ajoutés à -mod= et -serverMod=.
#
# C'est la seule image PROPRE À DAYZ : l'installation passe par l'image
# commune ghcr.io/ouiheberg/yolks:steam-installer (deploy/steam-installer).
#
# À CONSTRUIRE ET PUBLIER PAR ARTHUR (non fait par la PR), par exemple dans
# OuiHeberg/yolks (games/dayz/) avec le workflow existant, puis rendre le
# paquet ghcr public (Package settings → Change visibility).
# Image de base épinglée par empreinte (index relevé le 01/11/2026).
FROM        --platform=linux/amd64 debian:bookworm-slim@sha256:99c0b25c46d0214d5a2091092e7908907dcaecd6a962cde0ac700acee222b6f3

LABEL       author="David Wolfe (Red-Thirten)" maintainer="OuiHeberg"
LABEL       org.opencontainers.image.source="https://github.com/OuiHeberg/yolks"
LABEL       org.opencontainers.image.licenses=MIT

## Update base packages and install dependencies
ENV         DEBIAN_FRONTEND=noninteractive
RUN         dpkg --add-architecture i386 \
            && apt update \
            && apt upgrade -y \
            && apt install -y \
                curl \
                tzdata \
                locales \
                iproute2 \
                gettext-base \
                ca-certificates \
                libssl-dev \
                lib32gcc-s1 \
                libsdl2-2.0-0 \
                libsdl2-2.0-0:i386 \
                libstdc++6 \
                libstdc++6:i386 \
                lib32stdc++6 \
                libcap2 \
                libnss-wrapper \
                tini

## OuiPanel (01/11/2026) : le client RCon bercon de l'image d'origine est
## RETIRÉ. Son binaire 1.0.0 n'est plus publié (404 ; le dépôt ne publie plus
## que des sources v0.1.x) et l'original l'installe avec `curl -sSL` sans -f :
## il pose en /usr/local/bin une page « Not Found ». Rien dans entrypoint.sh
## ne s'en sert.

## Configure locale
RUN         update-locale lang=en_US.UTF-8 \
            && dpkg-reconfigure --frontend noninteractive locales

## Prepare NSS Wrapper for the entrypoint as a workaround for DayZ requiring a valid UID
ENV         NSS_WRAPPER_PASSWD=/tmp/passwd NSS_WRAPPER_GROUP=/tmp/group
RUN         touch ${NSS_WRAPPER_PASSWD} ${NSS_WRAPPER_GROUP} \
            && chgrp 0 ${NSS_WRAPPER_PASSWD} ${NSS_WRAPPER_GROUP} \
            && chmod g+rw ${NSS_WRAPPER_PASSWD} ${NSS_WRAPPER_GROUP}
ADD         passwd.template /passwd.template

## Setup user and working directory
RUN         useradd -m -d /home/container -s /bin/bash container
USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

STOPSIGNAL  SIGINT

## Copy over and execute entrypoint.sh via Tini
COPY        --chown=container:container ./entrypoint.sh /entrypoint.sh
RUN         chmod +x /entrypoint.sh
ENTRYPOINT  ["/usr/bin/tini", "-g", "--"]
CMD         ["/entrypoint.sh"]
