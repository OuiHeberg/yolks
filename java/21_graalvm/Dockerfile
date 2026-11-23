# Image ghcr.io/ouiheberg/yolks:java_21_graalvm des serveurs de jeu OuiPanel.
# JDK : GraalVM Community (licence GPLv2 avec exception Classpath), recopié tel quel de l'image
# officielle ghcr.io/graalvm/jdk-community (Oracle Linux 9), épinglée. Pas d'Oracle GraalVM
# (licence GFTC).
# Le JDK est posé sur Ubuntu 24.04, comme les images Temurin, pour garder les mêmes paquets et
# le même entrypoint : Dockerfile repris de pelican-eggs/yolks@3680e41 (java/21/Dockerfile,
# licence MIT), base remplacée, paquet « locales » ajouté, apt upgrade, racines eMudhra
# retirées du magasin du JDK.
#
# GraalVM Community pour JDK 21 n'est plus mis à jour depuis 21.0.2 (16/01/2024) : plus
# aucun correctif de sécurité depuis, aucune version corrigée de CVE-2026-114938 n'existe
# ni ne sortira. Graal 23.1 passe par le stub Base64 de HotSpot : -XX:-UseBASE64Intrinsics
# suffit à couper le code fautif.

FROM        --platform=$TARGETOS/$TARGETARCH ghcr.io/graalvm/jdk-community:21.0.2-ol9 AS graalvm
# Le dossier du JDK change de nom d'une version à l'autre (graalvm-community-java21,
# graalvm-community-java25i5…) : il est recopié sous un nom fixe. Il ne contient aucun lien
# symbolique.
RUN         test -x "$JAVA_HOME/bin/java" && cp -a "$JAVA_HOME" /graalvm

# Ubuntu 24.04, comme eclipse-temurin:*-jdk-noble ; reconstruite chaque semaine par le workflow.
FROM        --platform=$TARGETOS/$TARGETARCH ubuntu:noble

LABEL       author="Michael Parker" maintainer="OuiHeberg <contact@ouiheberg.com>" \
            org.opencontainers.image.source="https://github.com/OuiHeberg/yolks" \
            org.opencontainers.image.licenses=MIT \
            org.opencontainers.image.description="Yolk Java 21 GraalVM Community (Dockerfile pelican-eggs/yolks@3680e41)"

# Mêmes variables que les images eclipse-temurin : JDK sous /opt/java, locale en_US.UTF-8.
ENV         JAVA_HOME=/opt/java/graalvm \
            PATH=/opt/java/graalvm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
            LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# CVE-2026-114938 (Java4Shell) : pas de version corrigée de ce JDK (voir plus haut).
# L'entrypoint ajoute ces options à JDK_JAVA_OPTIONS.
ENV         OH_JAVA4SHELL_ATTENUATION="-XX:-UseBASE64Intrinsics"

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

COPY        --from=graalvm /graalvm /opt/java/graalvm
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
