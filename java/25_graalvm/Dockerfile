# Image ghcr.io/ouiheberg/yolks:java_25_graalvm des serveurs de jeu OuiPanel.
# JDK : GraalVM Community (licence GPLv2 avec exception Classpath), recopié tel quel de l'image
# officielle ghcr.io/graalvm/jdk-community (Oracle Linux 9), épinglée. Pas d'Oracle GraalVM
# (licence GFTC).
# Le JDK est posé sur Ubuntu 24.04, comme les images Temurin, pour garder les mêmes paquets et
# le même entrypoint : Dockerfile repris de pelican-eggs/yolks@3680e41 (java/25/Dockerfile,
# licence MIT), base remplacée, paquet « locales » ajouté, apt upgrade.
#
# GraalVM Community 25 Innovation 5 (graal 25.5.5.0.3, JDK 25.0.5.0.3 du 24/10/2026) ne
# contient pas le correctif de CVE-2026-114938, ni côté HotSpot (8393212) ni côté Graal
# (GR-79579, sur master seulement). Depuis Graal 25.1, le compilateur Graal a SON PROPRE
# décodage Base64 AVX-512, que -XX:-UseBASE64Intrinsics ne coupe pas : -XX:UseAVX=2 retire
# les instructions AVX-512 à HotSpot et à Graal.
# Les étiquettes « 25iN-… » ne sont pas suivies par Dependabot : nouvelle version à poser à la main.

FROM        --platform=$TARGETOS/$TARGETARCH ghcr.io/graalvm/jdk-community:25i5-25.0.5.0.3-ol9 AS graalvm
# Le dossier du JDK change de nom d'une version à l'autre (graalvm-community-java21,
# graalvm-community-java25i5…) : il est recopié sous un nom fixe. Il ne contient aucun lien
# symbolique.
RUN         test -x "$JAVA_HOME/bin/java" && cp -a "$JAVA_HOME" /graalvm

# Ubuntu 24.04, comme eclipse-temurin:*-jdk-noble ; reconstruite chaque semaine par le workflow.
FROM        --platform=$TARGETOS/$TARGETARCH ubuntu:noble

LABEL       author="Michael Parker" maintainer="OuiHeberg <contact@ouiheberg.com>" \
            org.opencontainers.image.source="https://github.com/OuiHeberg/yolks" \
            org.opencontainers.image.licenses=MIT \
            org.opencontainers.image.description="Yolk Java 25 GraalVM Community (Dockerfile pelican-eggs/yolks@3680e41)"

# Mêmes variables que les images eclipse-temurin : JDK sous /opt/java, locale en_US.UTF-8.
ENV         JAVA_HOME=/opt/java/graalvm \
            PATH=/opt/java/graalvm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
            LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# CVE-2026-114938 (Java4Shell) : pas de version corrigée de ce JDK (voir plus haut).
# L'entrypoint ajoute ces options à JDK_JAVA_OPTIONS.
ENV         OH_JAVA4SHELL_ATTENUATION="-XX:-UseBASE64Intrinsics -XX:UseAVX=2"

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
                tini \
                zip \
                unzip \
                jq \
            && echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen \
            && locale-gen en_US.UTF-8 \
            && rm -rf /var/lib/apt/lists/*

COPY        --from=graalvm /graalvm /opt/java/graalvm
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
