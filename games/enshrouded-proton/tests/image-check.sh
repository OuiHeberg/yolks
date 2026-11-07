#!/bin/bash
# Contrôle de ghcr.io/ouiheberg/yolks:enshrouded-proton, à lancer DANS l'image,
# sans réseau :
#   docker run --rm --network none -v "$PWD/games/enshrouded-proton/tests:/tests:ro" \
#     --entrypoint bash ghcr.io/ouiheberg/yolks:enshrouded-proton /tests/image-check.sh
set -u

fail=0
check() { # check "ce qui est contrôlé" commande [arguments...]
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then
        echo "ok     ${what}"
    else
        echo "ÉCHEC  ${what}"
        fail=1
    fi
}
absent() { ! grep -q "$@"; }
# La ligne qui suit « if umu_without_steam: » est devenue « pass » (patch du Dockerfile).
patched() { grep -A1 -F "if umu_without_steam:" "$1" | sed -n 2p | grep -qx " *pass"; }
# Rien, dans Proton, n'est modifiable par l'utilisateur du serveur.
read_only_tree() { [ -d "$1" ] && [ -z "$(find "$1"/ ! -type l -writable -print -quit 2>/dev/null)" ]; }

P=${PROTON_PATH:-}

check "utilisateur container, UID 988" test "$(id -u):$(id -un)" = "988:container"
check "USER=container" test "${USER:-}" = container
check "HOME=/home/container" test "${HOME:-}" = /home/container
check "dossier courant /home/container" test "$(pwd)" = /home/container
check "PROTON_PATH=/opt/proton" test "${P}" = /opt/proton
check "GE_PROTON_VERSION=11-9" test "${GE_PROTON_VERSION:-}" = 11-9
check "UMU_ID=0" test "${UMU_ID:-}" = 0
check "WINEDEBUG=-all" test "${WINEDEBUG:-}" = -all
check "STEAM_COMPAT_CLIENT_INSTALL_PATH=/home/container/steamcmd" test "${STEAM_COMPAT_CLIENT_INSTALL_PATH:-}" = /home/container/steamcmd
check "STEAM_COMPAT_DATA_PATH=/home/container/.steam/compatdata/2278520" test "${STEAM_COMPAT_DATA_PATH:-}" = /home/container/.steam/compatdata/2278520

check "proton : script présent et exécutable" test -x "${P}/proton"
check "proton : version GE-Proton${GE_PROTON_VERSION:-}" grep -qx "[0-9]* GE-Proton${GE_PROTON_VERSION:-}" "${P}/version"
check "proton : wine présent" test -x "${P}/files/bin/wine"
check "proton : wineserver présent" test -x "${P}/files/bin/wineserver"
check "proton : override lsteamclient=d absent" absent "lsteamclient=d" "${P}/proton"
check "proton : la ligne patchée est devenue pass" patched "${P}/proton"
check "proton : script lisible par Python" python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "${P}/proton"
check "proton : rien de modifiable par l'UID 988" read_only_tree "${P}"

check "libvulkan.so.1 présent" test -e /usr/lib/x86_64-linux-gnu/libvulkan.so.1
check "python3 présent" command -v python3
check "tini présent" test -x /usr/bin/tini
check "cmp présent (entrypoint)" command -v cmp
check "ip présent (entrypoint)" command -v ip
check "fuseau Europe/Paris lisible (tzdata)" test -f /usr/share/zoneinfo/Europe/Paris
check "entrypoint : présent et exécutable" test -x /entrypoint.sh
check "entrypoint : syntaxe" bash -n /entrypoint.sh

if [ "${fail}" -ne 0 ]; then
    echo "Des contrôles de l'image ont échoué."
    exit 1
fi
echo "OK : image enshrouded-proton"
