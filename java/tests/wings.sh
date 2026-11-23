#!/bin/bash
# À sourcer. Options de conteneur posées par Wings sur un serveur
# (OuiHeberg/ouipanel.com-wings2024, environment/docker/container.go) : uid du système de
# Wings, système de fichiers racine en lecture seule, /tmp en tmpfs de 100 Mo,
# no-new-privileges, capacités retirées. L'uid 4242 n'existe dans aucune image (contrôlé par
# controle-image.sh) : ni « container » (1000 ou 1001 selon la base), ni « ubuntu » (1000).

WINGS_UID=4242
WINGS_GID=4242
WINGS_OPTS=(
    --user "$WINGS_UID:$WINGS_GID"
    --read-only
    --tmpfs /tmp:rw,exec,nosuid,size=100M
    --security-opt no-new-privileges
    --cap-drop setpcap --cap-drop mknod --cap-drop audit_write --cap-drop net_raw
    --cap-drop dac_override --cap-drop fowner --cap-drop fsetid --cap-drop net_bind_service
    --cap-drop sys_chroot --cap-drop setfcap
)

# Donne un dossier de l'hôte à l'uid de Wings, comme le dossier d'un serveur sur un nœud.
# Le chown est fait en root par l'image testée elle-même : ni sudo, ni autre image.
# Usage : dossier_serveur <image> <dossier>
dossier_serveur() {
    docker run --rm --pull=never --network none --user 0 --entrypoint chown \
        -v "$2:/serveur" "$1" -R "$WINGS_UID:$WINGS_GID" /serveur
}
