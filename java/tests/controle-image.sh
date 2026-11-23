#!/bin/bash
# Contrôles d'une image java_* déjà construite, rejoués par le banc et par la publication.
# Usage : java/tests/controle-image.sh <image> <dossier de java/>
#
# Aucun disque de serveur n'est monté : le démarrage façon Wings se fait dans un dossier
# vide créé pour l'occasion. Le réseau n'est utilisé que par ce démarrage (INTERNAL_IP).
set -uo pipefail

image="${1:?usage : controle-image.sh <image> <dossier>}"
dossier="${2:?usage : controle-image.sh <image> <dossier>}"
java_dir="$(cd "$(dirname "$0")/.." && pwd)"
dockerfile="$java_dir/$dossier/Dockerfile"
attendu=$("$java_dir/version.sh" "$dossier" | sed -n 's/^attendu=//p')
[ -n "$attendu" ] || { echo "ÉCHEC : version attendue introuvable pour $dossier"; exit 1; }
attenuation=$(sed -nE 's/^ENV[[:space:]]+OH_JAVA4SHELL_ATTENUATION="([^"]*)".*/\1/p' "$dockerfile")

echec=0
ok() { echo "OK : $*"; }
ko() { echo "ÉCHEC : $*"; echec=1; }
lancer() { docker run --rm --pull=never "$@"; }
cfg() { docker image inspect -f "$1" "$image"; }

echo "== $image (java/$dossier) : version attendue « $attendu »"

# 1. Ce que Wings lit dans l'image.
[ "$(cfg '{{.Config.User}}')" = container ] && ok "USER container" || ko "USER = $(cfg '{{.Config.User}}')"
[ "$(cfg '{{.Config.WorkingDir}}')" = /home/container ] && ok "WORKDIR /home/container" || ko "WORKDIR = $(cfg '{{.Config.WorkingDir}}')"
[ "$(cfg '{{.Config.StopSignal}}')" = SIGINT ] && ok "STOPSIGNAL SIGINT" || ko "STOPSIGNAL = $(cfg '{{.Config.StopSignal}}')"
[ "$(cfg '{{json .Config.Entrypoint}}')" = '["/usr/bin/tini","-g","--"]' ] && ok "ENTRYPOINT tini -g" || ko "ENTRYPOINT = $(cfg '{{json .Config.Entrypoint}}')"
[ "$(cfg '{{json .Config.Cmd}}')" = '["/entrypoint.sh"]' ] && ok "CMD /entrypoint.sh" || ko "CMD = $(cfg '{{json .Config.Cmd}}')"
env_image=$(cfg '{{range .Config.Env}}{{println .}}{{end}}')
grep -qx 'HOME=/home/container' <<<"$env_image" && ok "HOME=/home/container" || ko "HOME absent ou différent"

# 2. java -version, sans l'entrypoint.
sortie=$(lancer --network none --entrypoint java "$image" -version 2>&1)
echo "$sortie" | sed 's/^/    /'
grep -qF -- "$attendu" <<<"$sortie" && ok "java -version : $attendu" || ko "java -version ne donne pas « $attendu »"

# 3. Utilisateur, dossier, outils des yolks, fuseaux, locale.
outils="tini curl lsof openssl git tar sqlite3 fc-list ip zip unzip jq awk"
grep -q 'redis-tools' "$dockerfile" && outils="$outils redis-cli"
if lancer --network none --entrypoint bash -e OUTILS="$outils" "$image" -c '
    set -e
    [ "$(id -un)" = container ] || { echo "utilisateur : $(id -un)"; exit 1; }
    [ "$HOME" = /home/container ] && [ "$(pwd)" = /home/container ] && [ -w /home/container ]
    [ -x /entrypoint.sh ] && bash -n /entrypoint.sh
    for c in $OUTILS; do command -v "$c" >/dev/null || { echo "outil absent : $c"; exit 1; }; done
    [ -f /usr/share/zoneinfo/Europe/Paris ] || { echo "tzdata absent"; exit 1; }
    locale -a | grep -qix "en_US.utf8" || { echo "locale en_US.UTF-8 absente"; exit 1; }
'; then ok "utilisateur container, /home/container, outils : $outils"; else ko "utilisateur, dossier ou outils"; fi
sortie=$(lancer --network none --entrypoint java "$image" -XshowSettings:properties -version 2>&1)
grep -qE 'sun\.jnu\.encoding = UTF-8' <<<"$sortie" && ok "encodage UTF-8 (noms de fichiers)" || ko "sun.jnu.encoding n'est pas UTF-8"

# 4. Démarrage minimal : entrypoint de l'image, STARTUP, utilisateur de l'image, rien de monté.
sortie=$(lancer -e STARTUP='java -version' "$image" 2>&1); code=$?
[ $code -eq 0 ] && [ "$(grep -cF -- "$attendu" <<<"$sortie")" -ge 2 ] \
    && ok "docker run -e STARTUP='java -version' (code 0)" || { echo "$sortie" | sed 's/^/    /'; ko "démarrage STARTUP='java -version' (code $code)"; }

# 5. Démarrage façon Wings : uid sans compte dans l'image, dossier du serveur monté (vide),
#    variables {{…}} remplacées par l'entrypoint.
vide=$(mktemp -d)
sortie=$(lancer --user "$(id -u):$(id -g)" -v "$vide:/home/container" \
    -e STARTUP='java -Xms128M -Xmx{{SERVER_MEMORY}}M -version' -e SERVER_MEMORY=1024 \
    -e SERVER_IP=0.0.0.0 -e SERVER_PORT=25565 -e TZ=Europe/Paris "$image" 2>&1); code=$?
if [ $code -eq 0 ] && grep -qF -- 'java -Xms128M -Xmx1024M -version' <<<"$sortie" && [ "$(grep -cF -- "$attendu" <<<"$sortie")" -ge 2 ]; then
    ok "démarrage façon Wings (uid $(id -u), {{SERVER_MEMORY}} remplacé)"
else
    echo "$sortie" | sed 's/^/    /'; ko "démarrage façon Wings (code $code)"
fi

# 6. CVE-2026-114938 : options posées par l'entrypoint, et seulement là où l'image le demande.
if [ -n "$attenuation" ]; then
    sortie=$(lancer -e STARTUP='java -XX:+PrintFlagsFinal -version' "$image" 2>&1)
    grep -qE 'bool UseBASE64Intrinsics +:?= false' <<<"$sortie" \
        && ok "Java4Shell : UseBASE64Intrinsics = false" || ko "Java4Shell : UseBASE64Intrinsics n'est pas à false"
    if grep -q 'UseAVX=2' <<<"$attenuation"; then
        grep -qE 'int UseAVX +:?= 2 ' <<<"$sortie" && ok "Java4Shell : UseAVX = 2" || ko "Java4Shell : UseAVX n'est pas à 2"
    fi
    sortie=$(lancer -e JDK_JAVA_OPTIONS=-Doh.egg=1 -e STARTUP='echo "options=[$JDK_JAVA_OPTIONS]"' "$image" 2>&1)
    grep -qF -- "options=[-Doh.egg=1 $attenuation]" <<<"$sortie" \
        && ok "Java4Shell : options de l'egg gardées, « $attenuation » ajouté" || ko "Java4Shell : JDK_JAVA_OPTIONS inattendu"
else
    sortie=$(lancer -e STARTUP='echo "options=[${JDK_JAVA_OPTIONS:-}]"' "$image" 2>&1)
    grep -qF -- 'options=[]' <<<"$sortie" && ok "JDK_JAVA_OPTIONS vide (JDK corrigé ou non concerné)" || ko "JDK_JAVA_OPTIONS inattendu"
fi

# 7. Informations, sans effet sur le résultat.
echo "INFO : taille $(( $(cfg '{{.Size}}') / 1000000 )) Mo (non compressée)"
racines=$(lancer --network none --entrypoint bash "$image" -c '
    if [ -f "$JAVA_HOME/jre/lib/security/cacerts" ]; then ks="$JAVA_HOME/jre/lib/security/cacerts"; else ks="$JAVA_HOME/lib/security/cacerts"; fi
    keytool -list -v -keystore "$ks" -storepass changeit 2>/dev/null | grep -E "^Owner: CN=(emSign|AAA Certificate Services)" | sed "s/^Owner: //; s/,.*//"' | paste -sd ';' -)
echo "INFO : racines eMudhra / Comodo AAA dans le magasin du JDK : ${racines:-aucune}"

[ $echec -eq 0 ] && echo "== $image : tous les contrôles sont passés" || echo "== $image : au moins un contrôle a échoué"
exit $echec
