# Image ghcr.io/ouiheberg/yolks:java_17 des serveurs de jeu OuiPanel.
# Dockerfile repris de pelican-eggs/yolks@3680e41 (java/17/Dockerfile, licence MIT).
# Écarts avec l'amont : base épinglée sur une version précise (amont : eclipse-temurin:17-jdk-noble),
# étiquettes OuiHeberg.

FROM        --platform=$TARGETOS/$TARGETARCH eclipse-temurin:17.0.21.1_2-jdk-noble

LABEL       author="Michael Parker" maintainer="OuiHeberg <contact@ouiheberg.com>" \
            org.opencontainers.image.source="https://github.com/OuiHeberg/yolks" \
            org.opencontainers.image.licenses=MIT \
            org.opencontainers.image.description="Yolk Java 17 Temurin (Dockerfile pelican-eggs/yolks@3680e41)"

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
