# Image ghcr.io/ouiheberg/yolks:java_16 des serveurs de jeu OuiPanel.
# Dockerfile repris de pelican-eggs/yolks@3680e41 (java/16/Dockerfile, licence MIT).
# Écarts avec l'amont : JDK épinglé sur une version précise (amont : eclipse-temurin:16-jdk-focal)
# et recopié sur Ubuntu 24.04, étiquettes OuiHeberg, apt upgrade, racines eMudhra retirées.
# Java 16 : fin de vie chez Adoptium (dernière version 16.0.2+7, juillet 2021). Sa dernière
# image Temurin est sur Ubuntu 20.04, hors support standard depuis mai 2025 : plus aucun
# correctif Ubuntu. Le JDK (dossier /opt/java/openjdk, sans lien vers le système) est donc
# recopié tel quel sur ubuntu:noble, comme pour les images GraalVM, et reconstruit chaque
# semaine avec les correctifs Ubuntu.

FROM        --platform=$TARGETOS/$TARGETARCH eclipse-temurin:16.0.2_7-jdk-focal AS jdk

FROM        --platform=$TARGETOS/$TARGETARCH ubuntu:noble

LABEL       author="Michael Parker" maintainer="OuiHeberg <contact@ouiheberg.com>" \
            org.opencontainers.image.source="https://github.com/OuiHeberg/yolks" \
            org.opencontainers.image.licenses=MIT \
            org.opencontainers.image.description="Yolk Java 16 Temurin (Dockerfile pelican-eggs/yolks@3680e41)"

# Mêmes variables que les images eclipse-temurin : JDK sous /opt/java, locale en_US.UTF-8.
ENV         JAVA_HOME=/opt/java/openjdk \
            PATH=/opt/java/openjdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
            LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# Paquets de l'amont, plus « locales » (apporté d'habitude par l'image eclipse-temurin).
# Mises à jour Ubuntu reprises à chaque construction (chaque lundi), comme games/dayz.
ARG         DEBIAN_FRONTEND=noninteractive
RUN         apt update -y \
            && apt upgrade -y \
            && apt install -y \
                locales \
                curl \
                lsof \
                ca-certificates \
                openssl \
                git \
                tar \
                sqlite3 \
                fontconfig \
                tzdata \
                iproute2 \
                libfreetype6 \
                redis-tools \
                tini \
                zip \
                unzip \
                jq \
            && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
            && locale-gen en_US.UTF-8 \
            && rm -rf /var/lib/apt/lists/*

COPY        --from=jdk /opt/java/openjdk /opt/java/openjdk
# Racines de certificats retirées par Debian et Ubuntu après la compromission d'eMudhra
# (java/racines-retirees.txt) : ce JDK ne recevra plus de mise à jour de son magasin.
RUN         --mount=type=bind,source=.,target=/oh-src \
            bash /oh-src/retirer-racines.sh
RUN         java -version

## Setup user and working directory
RUN         useradd -m -d /home/container -s /bin/bash container
USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

STOPSIGNAL SIGINT

COPY        --chown=container:container ./../entrypoint.sh /entrypoint.sh
RUN         chmod +x /entrypoint.sh
ENTRYPOINT    ["/usr/bin/tini", "-g", "--"]
CMD         ["/entrypoint.sh"]
