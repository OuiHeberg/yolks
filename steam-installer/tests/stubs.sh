#!/bin/bash
#
# Doublures communes des bancs de l'installateur Steam (aucun réseau, aucun
# compte Steam) : curl (le panel, GitHub), DepotDownloader, SteamCMD.
# À charger par `source`, avec ROOT (dossier de travail du banc) défini.
#
# Réglages lus par les doublures (variables d'environnement) :
#   STUB_TICKET, STUB_REDEEM (fichier JSON rendu par l'échange), STUB_REPORT
#   (fichier où le compte rendu est écrit), STUB_REDEEM_FAIL=1,
#   STUB_TOKEN_MARK (doit se trouver dans account.config), STUB_REJECT=1,
#   STUB_DEPOT (fichier « chemin<TAB>contenu » : le dépôt du serveur),
#   STUB_DD_ARGS / STUB_SCMD_ARGS (fichiers où les arguments sont notés).

stub_install() {
    mkdir -p "$ROOT/bin" "$ROOT/dd" "$ROOT/steamcmd" "$ROOT/steamclient/sdk32" "$ROOT/steamclient/sdk64"
    echo so32 > "$ROOT/steamclient/sdk32/steamclient.so"
    echo so64 > "$ROOT/steamclient/sdk64/steamclient.so"

    cat > "$ROOT/bin/curl" <<'STUB'
#!/bin/bash
# Le banc vérifie qu'aucun secret ne passe par la ligne de commande.
printf '%s\n' "$*" >> "${STUB_ARGV_LOG:-/dev/null}"
out=""; url=""; data=""; write=""; dump=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift ;;
        -w) write="$2"; shift ;;
        -D) dump="$2"; shift ;;
        --data-binary) data="$2"; shift ;;
        -H|--max-time|--max-filesize|--proto) shift ;;
        -*) ;;
        *) url="$1" ;;
    esac
    shift
done
body=""
case "$data" in
    @-) body="$(cat)" ;;
    @*) body="$(cat -- "${data#@}")" ;;
esac
code=200
case "$url" in
    https://panel.test/api/hooks/steam/ticket)
        n="$(cat "$STUB_COUNTER" 2> /dev/null || echo 0)"; echo $((n + 1)) > "$STUB_COUNTER"
        if [ "$n" -lt "${STUB_BUSY:-0}" ]; then code=429; printf '{"error":"slow_down"}' > "$out"
        elif [ "${STUB_FAILCAP:-0}" = "1" ]; then code=429; printf '{"error":"too_many_failures"}' > "$out"
        elif [ "${STUB_REDEEM_FAIL:-0}" = "1" ]; then code=404
        elif [ "$(printf '%s' "$body" | jq -r .ticket)" != "$STUB_TICKET" ]; then code=404
        else cp "$STUB_REDEEM" "$out"; fi ;;
    https://panel.test/api/hooks/steam/report)
        printf '%s' "$body" > "$STUB_REPORT" ;;
    https://raw.githubusercontent.com/*serverDZ.cfg)
        printf 'hostname = "x";\n' > "$out" ;;
    https://api.github.com/repos/*/releases/latest)
        printf '{"tarball_url":"https://api.github.com/tarball"}' ;;
    https://api.github.com/tarball)
        d="$(mktemp -d)"; mkdir -p "$d/top/dayzOffline.chernarusplus"; echo m > "$d/top/dayzOffline.chernarusplus/init.c"
        tar -czf "$out" -C "$d" top; rm -rf "$d" ;;
    *) echo "curl inattendu : $url" >&2; exit 6 ;;
esac
if [ -n "$dump" ]; then
    printf 'HTTP/1.1 %s\r\n' "$code" > "$dump"
    [ "$code" = 429 ] && [ -n "${STUB_RETRY_AFTER:-}" ] && printf 'Retry-After: %s\r\n' "$STUB_RETRY_AFTER" >> "$dump"
fi
[ -n "$write" ] && printf '%s' "$code"
exit 0
STUB

    # jq enveloppé : ses arguments sont notés (aucun secret ne doit y passer).
    real_jq="$(command -v jq)"
    cat > "$ROOT/bin/jq" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "\${STUB_ARGV_LOG:-/dev/null}"
exec "$real_jq" "\$@"
STUB

    # DepotDownloader factice : le dépôt de STUB_DEPOT, en respectant
    # -filelist (expression régulière, insensible à la casse, comme le vrai) ;
    # un objet du Workshop avec des noms en majuscules, des métadonnées et un
    # lien symbolique.
    cat > "$ROOT/dd/DepotDownloader" <<'STUB'
#!/bin/bash
if [ "$1" = "-V" ]; then
    mkdir -p "$HOME/.local/share/IsolatedStorage/abcdefgh.ijk/lmnopqrs.tuv/Url.test/AssemFiles"
    exit 0
fi
printf '%s\n' "$*" >> "${STUB_DD_ARGS:-/dev/null}"
# Ni la réponse du panel ni le ticket ne doivent traîner pendant un téléchargement.
[ -e "$OH_WORK_DIR/redeem.json" ] && { echo "redeem.json encore présent"; exit 1; }
[ -e "$OH_WORK_DIR/ticket" ] && { echo "ticket encore présent"; exit 1; }
user=""; app=""; pub=""; dir=""; list=""
while [ $# -gt 0 ]; do
    case "$1" in
        -username) user="$2"; shift ;;
        -app) app="$2"; shift ;;
        -pubfile) pub="$2"; shift ;;
        -dir) dir="$2"; shift ;;
        -filelist) list="$2"; shift ;;
    esac
    shift
done
echo "Logging '$user' into Steam3..."
store="$(find "$HOME" -name account.config 2> /dev/null | head -1)"
if [ -z "$store" ] || [ "${STUB_REJECT:-0}" = "1" ]; then
    echo "Access token was rejected (Expired)."; exit 1
fi
grep -q "$STUB_TOKEN_MARK" "$store" || { echo "account.config illisible"; exit 1; }
if [ -n "$pub" ]; then
    [ "$pub" = "999" ] && { echo "Download failed"; exit 1; }
    mkdir -p "$dir/Addons" "$dir/Keys" "$dir/.DepotDownloader"
    echo "pbo-$pub" > "$dir/Addons/Mod.PBO"; echo key > "$dir/Keys/Author_$pub.BIKEY"
    echo cfg > "$dir/.DepotDownloader/depot.config"; ln -sf /etc/hostname "$dir/evil"
else
    [ -n "$list" ] && cp "$list" "$STUB_FILELIST_SEEN"
    re=""; [ -n "$list" ] && re="$(sed -n 's/^regex://p' "$list" | head -1)"
    mkdir -p "$dir/.DepotDownloader"; echo manifest > "$dir/.DepotDownloader/depot.manifest"
    while IFS=$'\t' read -r path content; do
        [ -n "$path" ] || continue
        if [ -n "$re" ] && ! printf '%s' "$path" | grep -qiP "$re"; then
            echo "Ignoré (liste) : $path"; continue
        fi
        mkdir -p "$(dirname "$dir/$path")"; printf '%s\n' "$content" > "$dir/$path"
    done < "$STUB_DEPOT"
fi
echo "Download complete"
STUB

    # SteamCMD factice : anonyme seulement ; app_update pose TOUT le dépôt
    # (pas de liste de fichiers, comme le vrai) ; workshop_download_item dans
    # le dossier Steam standard.
    cat > "$ROOT/steamcmd/steamcmd.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${STUB_SCMD_ARGS:-/dev/null}"
dir=""; login=""
while [ $# -gt 0 ]; do
    case "$1" in
        +force_install_dir) dir="$2"; shift ;;
        +login) login="$2"; shift ;;
        +app_update)
            [ "$login" = "anonymous" ] || { echo "Login Failure"; exit 5; }
            app="$2"; shift
            if [ "${STUB_SCMD_FAIL:-0}" = "1" ]; then echo "ERROR! Failed to install app '$app' (No subscription)"; else
                while IFS=$'\t' read -r path content; do
                    [ -n "$path" ] || continue
                    mkdir -p "$(dirname "$dir/$path")"; printf '%s\n' "$content" > "$dir/$path"
                done < "$STUB_DEPOT"
                echo "Success! App '$app' fully installed."
            fi ;;
        +workshop_download_item)
            wapp="$2"; id="$3"; shift 2
            if [ "$id" = "999" ]; then echo "ERROR! Download item $id failed (Failure)."; else
                mkdir -p "$dir/steamapps/workshop/content/$wapp/$id/Addons"
                echo "pbo-$id" > "$dir/steamapps/workshop/content/$wapp/$id/Addons/Mod.PBO"
                echo "Success. Downloaded item $id to \"$dir/steamapps/workshop/content/$wapp/$id\" (1 bytes)"
            fi ;;
    esac
    shift
done
exit 0
STUB
    chmod +x "$ROOT/bin/curl" "$ROOT/bin/jq" "$ROOT/dd/DepotDownloader" "$ROOT/steamcmd/steamcmd.sh"
}

# Lance le travail non privilégié de l'installateur commun, exactement comme
# oh_main le lance (environnement vidé), sans setpriv (le banc n'est pas root).
#   run_worker <serveur> <travail> [fichier du crochet] -- variables du banc
run_worker() {
    local server="$1" work="$2" hook="${3:-}"
    mkdir -p "$work/home"
    ( umask 077; printf '%s' "$TICKET" > "$work/ticket" )
    env -i PATH="$ROOT/bin:/usr/bin:/bin" LANG=C.UTF-8 HOME="$work/home" \
        OH_WORK_DIR="$work" OH_SERVER_DIR="$server" OH_TICKET_URL="https://panel.test/api/hooks/steam/ticket" \
        OH_HOOK="$hook" OH_VALIDATE="${OH_VALIDATE:-0}" OH_DD_BIN="$ROOT/dd/DepotDownloader" \
        OH_STEAMCMD_DIR="$ROOT/steamcmd" OH_STEAMCLIENT_DIR="$ROOT/steamclient" \
        QUERY_PORT=27016 RCON_PORT=2305 RCON_PASSWORD=rcon HOOK_OUT="${HOOK_OUT:-/dev/null}" \
        STUB_TICKET="$TICKET" STUB_REDEEM="$ROOT/redeem.json" STUB_REPORT="$ROOT/report.json" \
        STUB_TOKEN_MARK="$TOKEN_MARK" STUB_REJECT="${STUB_REJECT:-0}" STUB_REDEEM_FAIL="${STUB_REDEEM_FAIL:-0}" \
        STUB_DEPOT="$ROOT/depot.tsv" STUB_FILELIST_SEEN="$ROOT/filelist-seen.txt" \
        STUB_DD_ARGS="$ROOT/dd-args.txt" STUB_SCMD_ARGS="$ROOT/scmd-args.txt" STUB_SCMD_FAIL="${STUB_SCMD_FAIL:-0}" \
        STUB_BUSY="${STUB_BUSY:-0}" STUB_FAILCAP="${STUB_FAILCAP:-0}" STUB_RETRY_AFTER="${STUB_RETRY_AFTER:-}" \
        STUB_COUNTER="$work/.stub-counter" STUB_ARGV_LOG="$ROOT/argv.log" OH_RETRY_DELAY=0 \
        bash "$INSTALLER" --worker
}

# La réponse de l'échange du ticket.
#   redeem <déclaration JSON> <objets JSON> [avec compte : 1|0]
redeem() {
    local account='null'
    if [ "${3:-1}" = "1" ]; then
        account="$(jq -cn --arg a "$ACCOUNT" --arg c "$(printf 'config-%s' "$TOKEN_MARK" | base64 -w0)" '{name: $a, config: $c}')"
    fi
    jq -n --arg r "$REPORT_TOKEN" --argjson s "$1" --argjson w "$2" --argjson a "$account" \
        '{report_token: $r, steam: $s, account: $a, workshop: $w}' > "$ROOT/redeem.json"
}
