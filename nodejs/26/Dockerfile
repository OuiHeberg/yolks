FROM        --platform=$TARGETOS/$TARGETARCH node:26.12.1-trixie-slim

LABEL       author="Michael Parker" maintainer="OuiHeberg <contact@ouiheberg.com>" \
            org.opencontainers.image.source="https://github.com/OuiHeberg/yolks" \
            org.opencontainers.image.description="Yolk Node.js 26 (Dockerfile pelican-eggs/yolks@9db46b2, base node:26.12.1-trixie-slim)"

RUN         useradd -m -d /home/container container
STOPSIGNAL SIGINT

RUN         apt update \
            && apt -y install \
                ffmpeg \
                iproute2 \
                git \
                sqlite3 \
                libsqlite3-dev \
                python3 \
                python3-dev \
                ca-certificates \
                dnsutils \
                tzdata \
                zip \
                tar \
                curl \
                build-essential \
                libtool \
                iputils-ping \
                libnss3 \
                tini

RUN         npm install --global npm@latest typescript ts-node @types/node tsx

RUN         npm install -g corepack --force
RUN         corepack enable
RUN         corepack prepare pnpm@latest --activate

USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

COPY        --chown=container:container ./../entrypoint.sh /entrypoint.sh
RUN         chmod +x /entrypoint.sh

ENTRYPOINT    ["/usr/bin/tini", "-g", "--"]
CMD         ["/entrypoint.sh"]
