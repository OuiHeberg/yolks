# Image ghcr.io/ouiheberg/yolks:java_16 des serveurs de jeu OuiPanel.
# Dockerfile repris de pelican-eggs/yolks@3680e41 (java/16/Dockerfile, licence MIT).
# Écarts avec l'amont : base épinglée sur une version précise (amont : eclipse-temurin:16-jdk-focal),
# étiquettes OuiHeberg.
# Java 16 : fin de vie chez Adoptium (dernière version 16.0.2+7, juillet 2021), base
# Ubuntu 20.04 elle aussi hors support standard.

FROM        --platform=$TARGETOS/$TARGETARCH eclipse-temurin:16.0.2_7-jdk-focal

LABEL       author="Michael Parker" maintainer="OuiHeberg <contact@ouiheberg.com>" \
            org.opencontainers.image.source="https://github.com/OuiHeberg/yolks" \
            org.opencontainers.image.licenses=MIT \
            org.opencontainers.image.description="Yolk Java 16 Temurin (Dockerfile pelican-eggs/yolks@3680e41)"

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
                redis-tools \
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
