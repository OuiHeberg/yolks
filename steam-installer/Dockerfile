# ghcr.io/ouiheberg/yolks:steam-installer — image d'INSTALLATION COMMUNE des
# eggs qui déclarent une installation Steam (colonne eggs.steam), conteneur
# d'installation de Wings. Le script de chaque egg appelle oh-steam-install.
#
# Contient :
#  - oh-steam-install (deploy/steam-installer/oh-steam-install) : échange du
#    ticket, téléchargement du serveur et du Workshop, effacement du jeton,
#    crochet de l'egg, compte rendu ;
#  - DepotDownloader (SteamRE, licence GPL-2.0), version et empreinte
#    épinglées : téléchargements avec le jeton de session Steam connecté par QR ;
#  - SteamCMD (copie à jour, prise au build sans compte) pour le chemin
#    ANONYME, et pour l'ancien chemin des eggs (STEAM_USER / STEAM_PASS) ;
#  - steamclient.so 32 et 64 bits (/opt/steamclient), pour les crochets des
#    jeux qui le chargent depuis ~/.steam/sdk{32,64} ;
#  - oh-steam-selftest : contrôle sans réseau que DepotDownloader lit le
#    fichier de jeton tel que le panel le fabrique.
#
# Aucun secret n'est mis dans l'image. setpriv (util-linux) sert à lâcher root.
#
# À CONSTRUIRE ET PUBLIER PAR ARTHUR (non fait par la PR), puis rendre le
# paquet ghcr public, et lancer le contrôle :
#   docker run --rm --network none ghcr.io/ouiheberg/yolks:steam-installer oh-steam-selftest
# Mettre à jour DepotDownloader : changer les deux ARG (version, empreinte du
# zip linux-x64 de la release GitHub).
#
# Images de base épinglées par empreinte (debian:bookworm-slim, index relevé
# le 01/11/2026) : la reconstruire après une mise à jour de Debian demande de
# changer l'empreinte ; `apt-get upgrade` reprend de toute façon les correctifs
# publiés depuis.
ARG DEBIAN_IMAGE=debian:bookworm-slim@sha256:99c0b25c46d0214d5a2091092e7908907dcaecd6a962cde0ac700acee222b6f3
FROM --platform=linux/amd64 ${DEBIAN_IMAGE} AS fetch

ARG DEPOTDOWNLOADER_VERSION=3.4.0
ARG DEPOTDOWNLOADER_SHA256=a999dec66b4850fc961bd50366696d23c2d0fad7b18790e6a5647b2f19097a53
# L'amorce de SteamCMD (inchangée chez Valve depuis le 05/01/2018 : 2 428 561
# octets). Elle se met ensuite à jour elle-même, depuis Steam, paquets signés.
ARG STEAMCMD_SHA256=cebf0046bfd08cf45da6bc094ae47aa39ebf4155e5ede41373b579b8f1071e7c

ENV DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip lib32gcc-s1 lib32stdc++6

RUN curl -fsSL -o /tmp/depotdownloader.zip \
        "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_${DEPOTDOWNLOADER_VERSION}/DepotDownloader-linux-x64.zip" \
    && echo "${DEPOTDOWNLOADER_SHA256}  /tmp/depotdownloader.zip" | sha256sum -c - \
    && mkdir -p /out/depotdownloader \
    && unzip -q /tmp/depotdownloader.zip -d /out/depotdownloader \
    && chmod 755 /out/depotdownloader/DepotDownloader

# SteamCMD anonyme, le temps de récupérer steamclient.so (sa première mise à
# jour le télécharge). Aucun identifiant.
RUN mkdir -p /tmp/steamcmd \
    && curl -fsSL -o /tmp/steamcmd_linux.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
    && echo "${STEAMCMD_SHA256}  /tmp/steamcmd_linux.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/steamcmd_linux.tar.gz -C /tmp/steamcmd \
    && (cd /tmp/steamcmd && ./steamcmd.sh +quit || true) \
    && mkdir -p /out/steamclient/sdk32 /out/steamclient/sdk64 \
    && cp /tmp/steamcmd/linux32/steamclient.so /out/steamclient/sdk32/steamclient.so \
    && cp /tmp/steamcmd/linux64/steamclient.so /out/steamclient/sdk64/steamclient.so \
    && rm -rf /tmp/steamcmd/logs /tmp/steamcmd/appcache \
    && cp -a /tmp/steamcmd /out/steamcmd

FROM --platform=linux/amd64 ${DEBIAN_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/OuiHeberg/yolks"
LABEL org.opencontainers.image.description="Installateur Steam commun OuiPanel : oh-steam-install, DepotDownloader, SteamCMD, steamclient.so"

ENV DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        bash ca-certificates coreutils curl findutils grep gzip jq sed tar util-linux \
        libssl3 zlib1g libstdc++6 lib32gcc-s1 lib32stdc++6 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=fetch /out/depotdownloader /opt/depotdownloader
COPY --from=fetch /out/steamclient /opt/steamclient
COPY --from=fetch /out/steamcmd /opt/steamcmd
COPY --chmod=755 oh-steam-install oh-steam-selftest /usr/local/bin/

# DepotDownloader sans ICU (une dépendance de moins) et sans télémétrie.
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1

# Contrôle au build : le binaire démarre (sans réseau, sans compte), et les
# scripts se lisent.
RUN HOME=/tmp/dd-check /opt/depotdownloader/DepotDownloader -V && rm -rf /tmp/dd-check \
    && bash -n /usr/local/bin/oh-steam-install && bash -n /usr/local/bin/oh-steam-selftest

# Jamais le volume du client comme dossier courant : un fichier core (désactivé
# de toute façon par oh-steam-install) n'y atterrirait pas.
WORKDIR /
