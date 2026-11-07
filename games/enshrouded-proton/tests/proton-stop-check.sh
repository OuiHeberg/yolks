#!/bin/bash
# Arrêt sous le VRAI Proton de ghcr.io/ouiheberg/yolks:enshrouded-proton, SANS
# RÉSEAU, avec les réglages de Wings (UID 988, racine en lecture seule, /tmp en
# tmpfs, tty) et la commande de démarrage de README.md. Le jeu est remplacé par
# tests/fake-game.c, compilé pour Windows : un programme console qui écrit
# « HostOnline » puis attend, et qui à un Ctrl+C « sauvegarde » 8 s et sort.
# Vérifie que `docker stop` (SIGINT) atteint le programme Windows à travers tini,
# bash, le script proton et Wine, et que le conteneur s'arrête seul.
#   x86_64-w64-mingw32-gcc -O2 -static -s -o /tmp/enshrouded_server.exe games/enshrouded-proton/tests/fake-game.c
#   bash games/enshrouded-proton/tests/proton-stop-check.sh ghcr.io/ouiheberg/yolks:enshrouded-proton /tmp/enshrouded_server.exe
set -euo pipefail

IMAGE=${1:?usage : proton-stop-check.sh <image> <enshrouded_server.exe>}
EXE=${2:?usage : proton-stop-check.sh <image> <enshrouded_server.exe>}
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

name="oh-banc-enshrouded-proton-$$"
vol=$(mktemp -d)
out=$(mktemp)
cleanup() {
    docker rm -f "${name}" >/dev/null 2>&1 || true
    docker run --rm --network none --user 0 -v "${vol}:/v" --entrypoint find "${IMAGE}" /v -mindepth 1 -delete >/dev/null 2>&1 || true
    rmdir "${vol}" 2>/dev/null || true
    rm -f "${out}"
}
trap cleanup EXIT

cp "${EXE}" "${vol}/enshrouded_server.exe"
chmod -R a+rwX "${vol}"

docker run -d -t -i --name "${name}" \
    --network none --user 988:988 --read-only \
    --tmpfs /tmp:rw,exec,nosuid,size=100M --security-opt no-new-privileges \
    -v "${vol}:/home/container" \
    -e TZ=Europe/Paris -e AUTO_UPDATE=0 -e SRCDS_APPID=2278520 -e WINDOWS_INSTALL=1 \
    -e STARTUP="${startup}" \
    "${IMAGE}" >/dev/null

# Premier démarrage : Proton crée son préfixe avant de lancer le jeu.
started=0
for _ in $(seq 1 300); do
    if grep -qF "'HostOnline' (up)!" "${vol}/logs/enshrouded_server.log" 2>/dev/null; then started=1; break; fi
    [ "$(docker inspect -f '{{.State.Running}}' "${name}")" = true ] || break
    sleep 1
done
expect "jeu de test lancé par Proton (HostOnline dans le journal)" test "${started}" = 1
expect "préfixe Proton créé dans .steam/compatdata/2278520/pfx" test -d "${vol}/.steam/compatdata/2278520/pfx"

# Relevé des processus : parent, groupe, session, signaux ignorés et interceptés.
docker exec "${name}" bash -c '
    echo "pid ppid pgid sid comm SigIgn SigCgt"
    for d in /proc/[0-9]*; do
        [ -r "$d/stat" ] || continue
        read -r -a st < <(sed "s/^.*) //" "$d/stat")
        echo "${d#/proc/} ${st[1]} ${st[2]} ${st[3]} $(cat "$d/comm" | tr " " "_") $(awk "/^SigIgn/{print \$2}" "$d/status") $(awk "/^SigCgt/{print \$2}" "$d/status")"
    done' > "${out}" 2>&1 || true
column -t "${out}" 2>/dev/null | sed 's/^/    | /' || sed 's/^/    | /' "${out}"
game=$(awk '$5 == "enshrouded_serv" {print $1; exit}' "${out}")
game_pgid=$(awk '$5 == "enshrouded_serv" {print $3; exit}' "${out}")
game_cgt=$(awk '$5 == "enshrouded_serv" {print $7; exit}' "${out}")
entry_pgid=$(awk '$5 == "bash" && $2 == 1 {print $3; exit}' "${out}")
expect "processus du jeu trouvé" test -n "${game}"
expect "le jeu est dans le groupe de l'entrypoint (il reçoit le SIGINT relayé par tini)" test -n "${game_pgid}" -a "${game_pgid}" = "${entry_pgid}"
expect "Wine intercepte SIGINT dans le jeu (SigCgt)" test -n "${game_cgt}" -a "$(( 0x${game_cgt:-0} & 2 ))" -ne 0

t0=$(date +%s)
docker stop -t 120 "${name}" >/dev/null
t1=$(date +%s)
code=$(docker inspect -f '{{.State.ExitCode}}' "${name}")
docker logs "${name}" 2>&1 | tr -d '\r' | tail -n 30 | sed 's/^/    | /' || true
echo "    (arrêt en $((t1 - t0)) s, code de sortie ${code})"
echo "    événements console reçus par le jeu (type, ms depuis son lancement) :"
tr -d '\r' < "${vol}/ctrl-events" 2>/dev/null | sed 's/^/    | /' || echo "    | (aucun)"
first_event=$(tr -d '\r' < "${vol}/ctrl-events" 2>/dev/null | awk 'NR == 1 {print $1}')
expect "premier événement reçu par le jeu : Ctrl+C (CTRL_C_EVENT = 0)" test "${first_event}" = 0
expect "le jeu a fini sa sauvegarde de 8 s (./saved)" test -f "${vol}/saved"
expect "l'arrêt a attendu la sauvegarde (8 s ou plus)" test "$((t1 - t0))" -ge 8
# Code attendu : celui de tail, 1 (le journal venait d'être déplacé par la
# rotation quand tail l'a ouvert), comme avec la commande Wine. 137 (SIGKILL)
# ou 130 (SIGINT) diraient que le conteneur a été tué.
expect "code de sortie ${code} : pas tué par un signal (ni 137 ni 130, moins de 128)" test "${code}" -lt 128
expect "arrêt en moins de 120 s" test "$((t1 - t0))" -lt 120

if [ "${fail}" -ne 0 ]; then
    echo "Des contrôles de l'arrêt sous Proton ont échoué."
    exit 1
fi
echo "OK : arrêt propre sous Proton"
