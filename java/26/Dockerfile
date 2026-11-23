# Image ghcr.io/ouiheberg/yolks:java_26 des serveurs de jeu OuiPanel.
# Dockerfile repris de pelican-eggs/yolks@3680e41 (java/26/Dockerfile, licence MIT).
# Écarts avec l'amont : base épinglée sur une version précise (amont : eclipse-temurin:26-jdk-noble),
# étiquettes OuiHeberg, OH_JAVA4SHELL_ATTENUATION.
# Java 26 : fin de vie chez Adoptium depuis la sortie de Java 27 (dernière version
# 26.0.2.1+1, août 2026).

FROM        --platform=$TARGETOS/$TARGETARCH eclipse-temurin:26.0.2.1_1-jdk-noble

LABEL       author="Michael Parker" maintainer="OuiHeberg <contact@ouiheberg.com>" \
            org.opencontainers.image.source="https://github.com/OuiHeberg/yolks" \
            org.opencontainers.image.licenses=MIT \
            org.opencontainers.image.description="Yolk Java 26 Temurin (Dockerfile pelican-eggs/yolks@3680e41)"

# CVE-2026-114938 (Java4Shell) : aucune version corrigée de ce JDK ne sortira.
# L'entrypoint ajoute ces options à JDK_JAVA_OPTIONS (intrinsèque Base64 de HotSpot coupée).
ENV         OH_JAVA4SHELL_ATTENUATION="-XX:-UseBASE64Intrinsics"

RUN         apt update -y \
            && apt install -y \
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
                jq

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
