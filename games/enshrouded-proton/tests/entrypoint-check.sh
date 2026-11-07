#!/bin/bash
# Contrôle de l'entrypoint de ghcr.io/ouiheberg/yolks:enshrouded-proton et de la
# commande de démarrage de README.md, SANS RÉSEAU, avec les réglages de Wings
# (UID 988, racine en lecture seule, /tmp en tmpfs, no-new-privileges).
#  1-2. Volume sans le jeu, avec une fausse copie de SteamCMD (steamclient.so
#       seulement) : ni SteamCMD ni Proton ne doivent être lancés.
#  3.   Faux jeu, et faux proton (tests/fake-proton) par PROTON_PATH : la
#       commande du README tourne en entier (rotation du journal, arguments de
#       proton, tail), puis `docker stop` doit laisser le jeu « sauvegarder ».
#  4.   Faux SteamCMD qui intercepte SIGINT et sort en 0 : `docker stop`
#       pendant la mise à jour doit arrêter le conteneur sans lancer le jeu.
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
same() { [ "$(cat "$1" 2>/dev/null)" = "$2" ]; } # same <fichier> <contenu attendu>

startup=$(awk '/<!-- startup:begin -->/{f=1;next} /<!-- startup:end -->/{f=0} f && !/^```/' "${here}/../README.md")
[ -n "${startup}" ] || { ko "commande de démarrage introuvable dans README.md"; exit 1; }
bash -n -c "${startup}" || { ko "syntaxe de la commande de démarrage"; exit 1; }
ok "commande de démarrage lue dans README.md, syntaxe correcte"

name="oh-banc-enshrouded-$$"
vols=()
out=$(mktemp)
cleanup() {
    docker rm -f "${name}" >/dev/null 2>&1 || true
    local v
    for v in "${vols[@]}"; do
        # Les fichiers écrits par l'UID 988 s'effacent depuis un conteneur.
        docker run --rm --network none --user 0 -v "${v}:/v" --entrypoint find "${IMAGE}" /v -mindepth 1 -delete >/dev/null 2>&1 || true
        rmdir "${v}" 2>/dev/null || true
    done
    rm -f "${out}"
}
trap cleanup EXIT
new_volume() { # new_volume <variable> : dossier vide, noté pour le ménage
    local d
    d=$(mktemp -d)
    vols+=("${d}")
    printf -v "$1" '%s' "${d}"
}

# Réglages de Wings pour un conteneur de serveur.
wings=(--network none --user 988:988 --read-only
    --tmpfs /tmp:rw,exec,nosuid,size=100M --security-opt no-new-privileges)

rc=0
run() { # run <volume> <AUTO_UPDATE> : premier plan ; sortie dans $out, code dans $rc
    rc=0
    docker run --rm "${wings[@]}" -v "$1:/home/container" \
        -e TZ=Europe/Paris -e AUTO_UPDATE="$2" -e SRCDS_APPID=2278520 -e WINDOWS_INSTALL=1 \
        -e STARTUP="${startup}" \
        "${IMAGE}" > "${out}" 2>&1 || rc=$?
    sed 's/^/    | /' "${out}"
}

new_volume vol
mkdir -p "${vol}/steamcmd/linux64" "${vol}/steamcmd/linux32"
echo "faux steamclient 64 bits v1" > "${vol}/steamcmd/linux64/steamclient.so"
echo "faux steamclient 32 bits v1" > "${vol}/steamcmd/linux32/steamclient.so"
chmod -R a+rwX "${vol}"

echo "== 1. AUTO_UPDATE=0, jeu absent"
run "${vol}" 0
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
run "${vol}" 1
expect "code de sortie 1 (garde de la commande : jeu absent)" test "${rc}" = 1
expect "avertissement SteamCMD absent, sans arrêt" grep -qF "WARNING: SteamCMD was not found in ./steamcmd" "${out}"
expect "message de la garde : jeu absent" grep -qF "ERROR: the game files are missing (enshrouded_server.exe)" "${out}"
expect "steamclient.so 64 bits recopié (v2)" cmp -s "${vol}/steamcmd/linux64/steamclient.so" "${vol}/.steam/sdk64/steamclient.so"
expect "Proton non lancé (pas de pfx)" test ! -e "${vol}/.steam/compatdata/2278520/pfx"

echo "== 3. Commande du README avec un faux proton, puis docker stop"
new_volume vol3
mkdir -p "${vol3}/logs" "${vol3}/fakeproton"
cp "${here}/fake-proton" "${vol3}/fakeproton/proton"
echo "0 faux-proton" > "${vol3}/fakeproton/version"
echo "MZ faux jeu" > "${vol3}/enshrouded_server.exe"
echo "journal courant" > "${vol3}/logs/enshrouded_server.log"
echo "journal 1" > "${vol3}/logs/enshrouded_server.log.1"
echo "journal 2" > "${vol3}/logs/enshrouded_server.log.2"
echo "journal 3" > "${vol3}/logs/enshrouded_server.log.3"
chmod -R a+rwX "${vol3}"
chmod 755 "${vol3}/fakeproton/proton"

# Comme Wings : détaché, avec un tty et l'entrée ouverte.
docker run -d -t -i --name "${name}" "${wings[@]}" -v "${vol3}:/home/container" \
    -e TZ=Europe/Paris -e AUTO_UPDATE=0 -e SRCDS_APPID=2278520 -e WINDOWS_INSTALL=1 \
    -e PROTON_PATH=/home/container/fakeproton -e STARTUP="${startup}" \
    "${IMAGE}" >/dev/null
started=0
for _ in $(seq 1 60); do
    if grep -qF "'HostOnline' (up)!" "${vol3}/logs/enshrouded_server.log" 2>/dev/null; then started=1; break; fi
    [ "$(docker inspect -f '{{.State.Running}}' "${name}")" = true ] || break
    sleep 0.5
done
expect "faux jeu démarré (HostOnline dans le journal)" test "${started}" = 1
expect "signal d'arrêt du conteneur : SIGINT" test "$(docker inspect -f '{{.Config.StopSignal}}' "${name}")" = SIGINT
t0=$(date +%s)
docker stop -t 30 "${name}" >/dev/null
t1=$(date +%s)
code=$(docker inspect -f '{{.State.ExitCode}}' "${name}")
docker logs "${name}" > "${out}" 2>&1 || true
docker rm -f "${name}" >/dev/null 2>&1 || true
tr -d '\r' < "${out}" | sed 's/^/    | /'
echo "    (arrêt en $((t1 - t0)) s, code de sortie ${code})"
# Code attendu : celui de tail, 1 (le journal venait d'être déplacé par la
# rotation quand tail l'a ouvert), comme avec la commande Wine. 137 (SIGKILL)
# ou 130 (SIGINT) diraient que le conteneur a été tué.
expect "code de sortie ${code} : pas tué par un signal (ni 137 ni 130, moins de 128)" test "${code}" -lt 128
expect "arrêt en moins de 30 s" test "$((t1 - t0))" -lt 30
expect "le jeu a reçu SIGINT" same "${vol3}/fakeproton/signal" SIGINT
expect "le jeu a fini sa sauvegarde (./saved)" test -f "${vol3}/saved"
expect "fin de la sauvegarde dans le journal" grep -qF "world saved, exiting" "${vol3}/logs/enshrouded_server.log"
expect "SIGINT et SIGTERM reçus ignorés en héritage (trap de l'entrypoint)" same "${vol3}/fakeproton/inherited" "$(printf 'SIGINT=ignored\nSIGTERM=ignored')"
expect "proton lancé avec exactement 2 arguments : run enshrouded_server.exe (chemin relatif)" same "${vol3}/fakeproton/args" "$(printf 'run\nenshrouded_server.exe')"
expect "proton lancé depuis /home/container" same "${vol3}/fakeproton/cwd" /home/container
expect "WINEDEBUG=-all pour proton" grep -qx "WINEDEBUG=-all" "${vol3}/fakeproton/env"
expect "UMU_ID=0 pour proton" grep -qx "UMU_ID=0" "${vol3}/fakeproton/env"
expect "rotation : journal courant -> .log.1" same "${vol3}/logs/enshrouded_server.log.1" "journal courant"
expect "rotation : .log.1 -> .log.2" same "${vol3}/logs/enshrouded_server.log.2" "journal 1"
expect "rotation : .log.2 -> .log.3 (l'ancien .log.3 est remplacé)" same "${vol3}/logs/enshrouded_server.log.3" "journal 2"
expect "pas de .log.4" test ! -e "${vol3}/logs/enshrouded_server.log.4"
expect "tail : la ligne HostOnline du journal est dans la console" grep -qF "'HostOnline' (up)!" "${out}"

echo "== 4. docker stop pendant la mise à jour SteamCMD"
new_volume vol4
mkdir -p "${vol4}/steamcmd" "${vol4}/fakeproton"
cp "${here}/fake-proton" "${vol4}/fakeproton/proton"
echo "0 faux-proton" > "${vol4}/fakeproton/version"
echo "MZ faux jeu" > "${vol4}/enshrouded_server.exe"
# Faux SteamCMD : il note ses arguments, attend, et à SIGINT finit en 1 s puis
# sort en 0, comme un SteamCMD qui s'arrête proprement. Sans le contrôle de
# l'entrypoint, le jeu serait lancé juste après.
cat > "${vol4}/steamcmd/steamcmd.sh" <<'EOF'
#!/bin/bash
trap 'echo SIGINT > ./steamcmd/signal; sleep 1; exit 0' INT
echo "$*" > ./steamcmd/args
while :; do sleep 0.1; done
EOF
chmod -R a+rwX "${vol4}"
chmod 755 "${vol4}/steamcmd/steamcmd.sh" "${vol4}/fakeproton/proton"

docker run -d -t -i --name "${name}" "${wings[@]}" -v "${vol4}:/home/container" \
    -e TZ=Europe/Paris -e AUTO_UPDATE=1 -e SRCDS_APPID=2278520 -e WINDOWS_INSTALL=1 \
    -e PROTON_PATH=/home/container/fakeproton -e STARTUP="${startup}" \
    "${IMAGE}" >/dev/null
started=0
for _ in $(seq 1 60); do
    if [ -s "${vol4}/steamcmd/args" ]; then started=1; break; fi
    [ "$(docker inspect -f '{{.State.Running}}' "${name}")" = true ] || break
    sleep 0.5
done
expect "faux SteamCMD lancé (AUTO_UPDATE=1)" test "${started}" = 1
expect "SteamCMD : app_update 2278520, plateforme windows" grep -qF "+@sSteamCmdForcePlatformType windows +app_update 2278520 +quit" "${vol4}/steamcmd/args"
t0=$(date +%s)
docker stop -t 30 "${name}" >/dev/null
t1=$(date +%s)
code=$(docker inspect -f '{{.State.ExitCode}}' "${name}")
docker logs "${name}" > "${out}" 2>&1 || true
docker rm -f "${name}" >/dev/null 2>&1 || true
tr -d '\r' < "${out}" | sed 's/^/    | /'
echo "    (arrêt en $((t1 - t0)) s, code de sortie ${code})"
expect "code de sortie 0 (arrêt demandé pendant la mise à jour, pas tué)" test "${code}" = 0
expect "arrêt en moins de 30 s" test "$((t1 - t0))" -lt 30
expect "SteamCMD a reçu SIGINT" same "${vol4}/steamcmd/signal" SIGINT
expect "message : arrêt demandé pendant la mise à jour" grep -qF "Stop requested during the startup update" "${out}"
expect "commande de démarrage non affichée" bash -c '! grep -qF ":/home/container\$ " "$1"' _ "${out}"
expect "jeu non lancé (faux proton jamais appelé)" test ! -e "${vol4}/fakeproton/args"
expect "commande de démarrage non exécutée (pas de dossier logs)" test ! -e "${vol4}/logs"

if [ "${fail}" -ne 0 ]; then
    echo "Des contrôles de l'entrypoint ont échoué."
    exit 1
fi
echo "OK : entrypoint et commande de démarrage"
