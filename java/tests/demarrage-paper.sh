#!/bin/bash
# Vrai démarrage d'un serveur Paper dans une image java_*, jusqu'à « Done », puis « stop ».
# Usage : java/tests/demarrage-paper.sh <image> <dossier de java/>
#
# Comme Wings : entrypoint de l'image, commande de démarrage de l'egg 2 « Minecraft » (relevée
# le 23/11/2026) dans STARTUP, options de conteneur de Wings (tests/wings.sh : uid 4242 sans
# compte dans l'image, racine en lecture seule, /tmp en tmpfs, no-new-privileges, capacités
# retirées), dossier du serveur monté sur /home/container (ici un dossier vide créé pour le
# test, donné à l'uid 4242), arrêt par la commande « stop » sur l'entrée standard.
# Le jar Paper est épinglé (build et SHA-256 publiés par PaperMC).
# Besoin du réseau : Paper télécharge le serveur Mojang et ses bibliothèques au premier lancement.
set -euo pipefail

image="${1:?usage : demarrage-paper.sh <image> <dossier>}"
dossier="${2:?usage : demarrage-paper.sh <image> <dossier>}"
# shellcheck source=wings.sh
. "$(dirname "$0")/wings.sh"

case "$dossier" in
    17)                 version=1.20.4;  build=499; sha=cabed3ae77cf55deba7c7d8722bc9cfd5e991201c211665f9265616d9fe5c77b ;;
    21|22|21_graalvm)   version=1.21.11; build=132; sha=5ffef465eeeb5f2a3c23a24419d97c51afd7dbb4923ff42df9a3f58bba1ccfba ;;
    25|26|25_graalvm)   version=26.3;    build=258; sha=c5df5fb9f6155e48380c67c6e2b2dc2581b7db1a4b665d2c3818057b7efb6692 ;;
    *) echo "Pas de démarrage Paper prévu pour java_$dossier."; exit 0 ;;
esac

# Commande de démarrage de l'egg 2, telle quelle.
STARTUP=$(cat <<'FIN'
java -Xms128M -Xmx$(({{SERVER_MEMORY}}*84/100))M -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true -Dterminal.jline=false -Dterminal.ansi=true $(([[ -f {{SERVER_JARFILE}} ]] && printf %s "-jar {{SERVER_JARFILE}}") || (printf "@libraries/net/minecraftforge/forge/`ls libraries/net/minecraftforge/forge/ | sort -nr | awk 'NR==1'`/unix_args.txt"))
FIN
)

travail=$(mktemp -d)
serveur="$travail/serveur"
mkdir "$serveur"
journal="$travail/console.log"
entree="$travail/stdin"
nom="banc-paper-$$"

echo "== Paper $version (build $build) dans $image"
curl -fsSL --retry 3 -o "$serveur/paper.jar" "https://fill-data.papermc.io/v1/objects/$sha/paper-$version-$build.jar"
echo "$sha  $serveur/paper.jar" | sha256sum -c -
echo "eula=true" > "$serveur/eula.txt"
dossier_serveur "$image" "$serveur"

mkfifo "$entree"
debut=$(date +%s)
docker run --rm -i --pull=never --name "$nom" "${WINGS_OPTS[@]}" -v "$serveur:/home/container" \
    -e STARTUP="$STARTUP" -e SERVER_MEMORY=1280 -e SERVER_JARFILE=paper.jar \
    -e SERVER_IP=0.0.0.0 -e SERVER_PORT=25565 -e TZ=Europe/Paris \
    -e P_SERVER_UUID=00000000-0000-0000-0000-000000000000 \
    "$image" <"$entree" >"$journal" 2>&1 &
pid=$!
exec 3>"$entree"   # garde l'entrée standard ouverte jusqu'au « stop »

fin() {
    echo "--- fin de la console ---"; tail -n 40 "$journal" | sed 's/^/    /'
    docker rm -f "$nom" >/dev/null 2>&1 || true
}

# Attente de « Done (…)! For help, type "help" », 10 minutes au plus.
pret=0
for _ in $(seq 1 600); do
    if grep -q 'Done (' "$journal"; then pret=1; break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
done
if [ $pret -ne 1 ]; then
    echo "ÉCHEC : Paper n'a pas affiché « Done » ($(( $(date +%s) - debut )) s)"; fin; exit 1
fi
echo "OK : $(grep -m1 -o 'Done ([^)]*)' "$journal") ($(( $(date +%s) - debut )) s depuis docker run)"

# Arrêt propre par la console, comme la commande d'arrêt « stop » de l'egg.
echo stop >&3
code=124
for _ in $(seq 1 120); do
    if ! kill -0 "$pid" 2>/dev/null; then wait "$pid" && code=0 || code=$?; break; fi
    sleep 1
done
exec 3>&-
if [ $code -ne 0 ]; then
    echo "ÉCHEC : le serveur ne s'est pas arrêté proprement après « stop » (code $code)"; fin; exit 1
fi
grep -qi 'Stopping server' "$journal" || { echo "ÉCHEC : « Stopping server » absent de la console"; fin; exit 1; }
echo "OK : arrêt par « stop », code 0 (uid $WINGS_UID, racine en lecture seule, /tmp en tmpfs)"
grep -m3 -E 'container~|Picked up JDK_JAVA_OPTIONS|Paper version|This server is running' "$journal" | sed 's/^/    /' || true
