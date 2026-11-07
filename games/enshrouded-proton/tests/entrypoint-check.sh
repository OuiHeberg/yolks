#!/bin/bash
# Contrôle de l'entrypoint de ghcr.io/ouiheberg/yolks:enshrouded-proton et de la
# commande de démarrage de README.md, SANS RÉSEAU, avec les réglages de Wings
# (UID 988, racine en lecture seule, /tmp en tmpfs). Le volume de test n'a pas
# le jeu, et seulement une fausse copie de SteamCMD (steamclient.so, sans
# steamcmd.sh) : ni SteamCMD ni Proton ne doivent être lancés.
#   bash games/enshrouded-proton/tests/entrypoint-check.sh ghcr.io/ouiheberg/yolks:enshrouded-proton
set -euo pipefail

IMAGE=${1:?usage : entrypoint-check.sh <image>}
here=$(cd "$(dirname "$0")" && pwd)

fail=0
ok() { echo "ok     $1"; }
ko() { echo "ÉCHEC  $1"; fail=1; }
expect() { # expect "ce qui est contrôlé" commande [arguments...]
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then ok "${what}"; else ko "${what}"; fi
}

startup=$(awk '/<!-- startup:begin -->/{f=1;next} /<!-- startup:end -->/{f=0} f && !/^```/' "${here}/../README.md")
[ -n "${startup}" ] || { ko "commande de démarrage introuvable dans README.md"; exit 1; }
bash -n -c "${startup}" || { ko "syntaxe de la commande de démarrage"; exit 1; }
ok "commande de démarrage lue dans README.md, syntaxe correcte"

vol=$(mktemp -d)
out=$(mktemp)
cleanup() {
    # Les fichiers écrits par l'UID 988 s'effacent depuis un conteneur.
    docker run --rm --network none --user 0 -v "${vol}:/v" --entrypoint find "${IMAGE}" /v -mindepth 1 -delete >/dev/null 2>&1 || true
    rmdir "${vol}" 2>/dev/null || true
    rm -f "${out}"
}
trap cleanup EXIT

mkdir -p "${vol}/steamcmd/linux64" "${vol}/steamcmd/linux32"
echo "faux steamclient 64 bits v1" > "${vol}/steamcmd/linux64/steamclient.so"
echo "faux steamclient 32 bits v1" > "${vol}/steamcmd/linux32/steamclient.so"
chmod -R a+rwX "${vol}"

rc=0
run() { # run <AUTO_UPDATE> : l'image lancée comme par Wings ; sortie dans $out, code dans $rc
    rc=0
    docker run --rm --network none --user 988:988 --read-only \
        --tmpfs /tmp:rw,exec,nosuid,size=100M --security-opt no-new-privileges \
        -v "${vol}:/home/container" \
        -e TZ=Europe/Paris -e AUTO_UPDATE="$1" -e SRCDS_APPID=2278520 -e WINDOWS_INSTALL=1 \
        -e STARTUP="${startup}" \
        "${IMAGE}" > "${out}" 2>&1 || rc=$?
    sed 's/^/    | /' "${out}"
}

echo "== 1. AUTO_UPDATE=0, jeu absent"
run 0
expect "code de sortie 1 (garde de la commande : jeu absent)" test "${rc}" = 1
expect "mise à jour sautée (AUTO_UPDATE=0)" grep -qF "Not updating game server as auto update was set to 0" "${out}"
expect "commande STARTUP affichée puis exécutée par eval" grep -qF ':/home/container$ mkdir -p ./logs;' "${out}"
expect "message de la garde : jeu absent" grep -qF "ERROR: the game files are missing (enshrouded_server.exe)" "${out}"
expect "dossier logs créé par la commande" test -d "${vol}/logs"
expect "steamclient.so 64 bits copié dans .steam/sdk64" cmp -s "${vol}/steamcmd/linux64/steamclient.so" "${vol}/.steam/sdk64/steamclient.so"
expect "steamclient.so 32 bits copié dans .steam/sdk32" cmp -s "${vol}/steamcmd/linux32/steamclient.so" "${vol}/.steam/sdk32/steamclient.so"
expect "steamservice.so pointe sur steamclient.so (sdk64)" test "$(readlink "${vol}/.steam/sdk64/steamservice.so" || true)" = steamclient.so
expect "dossier du préfixe Proton créé (.steam/compatdata/2278520)" test -d "${vol}/.steam/compatdata/2278520"
expect "Proton non lancé (pas de pfx)" test ! -e "${vol}/.steam/compatdata/2278520/pfx"

echo "== 2. AUTO_UPDATE=1 sans SteamCMD, steamclient.so mis à jour par SteamCMD"
echo "faux steamclient 64 bits v2" > "${vol}/steamcmd/linux64/steamclient.so"
run 1
expect "code de sortie 1 (garde de la commande : jeu absent)" test "${rc}" = 1
expect "avertissement SteamCMD absent, sans arrêt" grep -qF "WARNING: SteamCMD was not found in ./steamcmd" "${out}"
expect "message de la garde : jeu absent" grep -qF "ERROR: the game files are missing (enshrouded_server.exe)" "${out}"
expect "steamclient.so 64 bits recopié (v2)" cmp -s "${vol}/steamcmd/linux64/steamclient.so" "${vol}/.steam/sdk64/steamclient.so"
expect "Proton non lancé (pas de pfx)" test ! -e "${vol}/.steam/compatdata/2278520/pfx"

if [ "${fail}" -ne 0 ]; then
    echo "Des contrôles de l'entrypoint ont échoué."
    exit 1
fi
echo "OK : entrypoint et commande de démarrage"
