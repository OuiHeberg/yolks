#!/bin/bash
#
# Banc de l'installateur Steam commun (deploy/steam-installer/oh-steam-install).
#
# Lance le travail non privilégié EXACTEMENT comme oh_main le lance
# (environnement vidé, `--worker`), avec des doublures de curl, DepotDownloader
# et SteamCMD (tests/stubs.sh), et un crochet d'egg de test. Rien ne part sur le
# réseau, aucun compte Steam n'est utilisé.
#
# Usage : bash deploy/steam-installer/tests/oh-steam-install.test.sh   (jq et grep -P requis)
# Code de sortie 0 si tout passe. Lancé aussi par
# tests/Unit/Services/Steam/SteamInstallerScriptTest.php.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="$HERE/../oh-steam-install"
FAILS=0
CHECKS=0

check() {
    CHECKS=$((CHECKS + 1))
    if eval "$2"; then :; else
        FAILS=$((FAILS + 1))
        printf 'ÉCHEC : %s\n' "$1"
    fi
}

command -v jq > /dev/null || { echo "jq absent : banc sauté"; exit 0; }
echo x | grep -qP 'x' 2> /dev/null || { echo "grep -P absent : banc sauté"; exit 0; }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

TICKET="$(printf 'a%.0s' {1..64})"
REPORT_TOKEN="$(printf 'b%.0s' {1..64})"
TOKEN_MARK="FAUXJETONSTEAMNEPASAFFICHER"
ACCOUNT="compte_de_test"

# shellcheck source=stubs.sh
source "$HERE/stubs.sh"
stub_install

printf 'game.bin\tbin\nconfig/server.cfg\tdepot-config\nsaves/readme.txt\tdepot-readme\n' > "$ROOT/depot.tsv"

# Le crochet de test : il vérifie que le jeton a disparu, note ce qu'il voit,
# et corrige le résultat d'un objet.
cat > "$ROOT/hook.sh" <<'HOOK'
oh_hook() {
    {
        echo "token_left=$(find "$OH_WORK_DIR" -name account.config | wc -l)"
        echo "redeem_left=$([ -e "$OH_WORK_DIR/redeem.json" ] && echo 1 || echo 0)"
        echo "login=$OH_LOGIN"
        echo "pwd=$PWD"
        echo "install=$OH_INSTALL_DIR"
        echo "workshop_dir=$OH_WORKSHOP_DIR"
        echo "query_port=${QUERY_PORT:-}"
        echo "whoami_env_ticket=${OH_TICKET:-none}"
    } > "$HOOK_OUT"
    cp "$OH_WORKSHOP_LIST" "$HOOK_OUT.list"
    printf '222\tfailed\n' >> "$OH_ITEM_RESULTS"
    return 0
}
HOOK

DECL_ACCOUNT='{"app_id": 380870, "login_required": true, "branch": "public", "platform": "linux", "install_dir": "", "workshop": {"app_id": 108600, "enabled": true}, "preserve": ["config/server.cfg", "saves/"]}'
ITEMS='[
    {"id": "111", "title": "Premier\tobjet", "server_side": false, "update": true},
    {"id": "222", "title": "Second", "server_side": true, "update": true},
    {"id": "333", "title": "Déjà là", "server_side": false, "update": false},
    {"id": "999", "title": "Cassé", "server_side": false, "update": true},
    {"id": "12a", "title": "Invalide", "server_side": false, "update": true},
    {"id": "1;rm -rf /", "title": "Piège", "server_side": false, "update": true}
]'

# --- scénario 1 : compte, installation neuve, volume piégé -------------------
S="$ROOT/s1/server"; W="$ROOT/s1/work"
mkdir -p "$S/steamapps/workshop/content/108600/333" "$W" "$ROOT/outside"
echo old > "$S/steamapps/workshop/content/108600/333/marker"
echo SECRET > "$ROOT/outside/secret"
ln -s "$ROOT/outside" "$S/game-link"              # sort du volume : retiré
ln -s "$ROOT/outside" "$S/.DepotDownloader"       # métadonnées détournées : retiré
ln -s "config" "$S/inside-link"                   # reste dans le volume : gardé
ln -s "/home/container/saves" "$S/container-link" # chemin du conteneur du jeu : gardé
redeem "$DECL_ACCOUNT" "$ITEMS" 1
rm -f "$ROOT/report.json" "$ROOT/filelist-seen.txt" "$ROOT/dd-args.txt"
OUT="$(HOOK_OUT="$ROOT/s1/hook.out" run_worker "$S" "$W" "$ROOT/hook.sh" 2>&1)"; STATUS=$?
check "scénario 1 : succès (code $STATUS)" '[ "$STATUS" -eq 0 ]'
check "serveur téléchargé" '[ "$(cat "$S/game.bin")" = bin ]'
check "installation neuve : aucune liste de protection" '[ ! -e "$ROOT/filelist-seen.txt" ]'
check "DepotDownloader : app, plate-forme, dossier" 'grep -q -- "-app 380870 -os linux -osarch 64 -dir $S" "$ROOT/dd-args.txt"'
check "DepotDownloader : pas de branche publique explicite" '! grep -q -- "-branch" "$ROOT/dd-args.txt"'
check "objet 111 dans le dossier Steam standard" '[ -f "$S/steamapps/workshop/content/108600/111/Addons/Mod.PBO" ]'
check "objet 333 à jour, pas retéléchargé" '[ -f "$S/steamapps/workshop/content/108600/333/marker" ] && ! grep -q -- "-pubfile 333" "$ROOT/dd-args.txt"'
check "identifiants invalides jamais passés à DepotDownloader" '! grep -q -- "-pubfile 12a" "$ROOT/dd-args.txt" && ! grep -q "rm -rf" "$ROOT/dd-args.txt"'
check "lien sortant retiré, sa cible intacte" '[ ! -e "$S/game-link" ] && [ ! -L "$S/game-link" ] && [ "$(cat "$ROOT/outside/secret")" = SECRET ]'
check "lien .DepotDownloader retiré (vrai dossier ensuite)" '[ ! -L "$S/.DepotDownloader" ] && [ "$(ls -A "$ROOT/outside")" = secret ]'
check "lien interne gardé" '[ -L "$S/inside-link" ] && [ -L "$S/container-link" ]'
check "crochet : jeton déjà effacé" 'grep -q "^token_left=0$" "$ROOT/s1/hook.out" && grep -q "^redeem_left=0$" "$ROOT/s1/hook.out"'
check "crochet : contexte" 'grep -q "^login=account$" "$ROOT/s1/hook.out" && grep -q "^pwd=$S$" "$ROOT/s1/hook.out" && grep -q "^workshop_dir=$S/steamapps/workshop/content/108600$" "$ROOT/s1/hook.out"'
check "crochet : pas de ticket dans l'\''environnement" 'grep -q "^whoami_env_ticket=none$" "$ROOT/s1/hook.out"'
check "crochet : liste du Workshop (état, serveur seul, titre nettoyé)" 'grep -qP "^111\tdownloaded\t0\tPremier objet$" "$ROOT/s1/hook.out.list" && grep -qP "^222\tdownloaded\t1\tSecond$" "$ROOT/s1/hook.out.list" && grep -qP "^333\tunchanged\t0\t" "$ROOT/s1/hook.out.list" && grep -qP "^999\tfailed\t0\t" "$ROOT/s1/hook.out.list"'
check "crochet : aucune entrée invalide" '[ "$(wc -l < "$ROOT/s1/hook.out.list")" -eq 4 ]'
check "jeton effacé à la fin" '[ -z "$(find "$ROOT/s1" -name account.config)" ] && [ ! -e "$W/redeem.json" ] && [ ! -e "$W/ticket" ]'
check "jeton absent de la sortie" '! grep -q "$TOKEN_MARK" <<< "$OUT"'
check "nom du compte masqué dans la sortie" '! grep -q "$ACCOUNT" <<< "$OUT" && grep -q "\[compte Steam\]" <<< "$OUT"'
check "ticket absent de la sortie" '! grep -q "$TICKET" <<< "$OUT"'
check "compte rendu envoyé, connexion ok" '[ "$(jq -r .login "$ROOT/report.json")" = ok ] && [ "$(jq -r .report_token "$ROOT/report.json")" = "$REPORT_TOKEN" ]'
check "compte rendu : 111 installé" '[ "$(jq -r ".items[] | select(.id==\"111\") | .status" "$ROOT/report.json")" = installed ]'
check "compte rendu : 222 corrigé par le crochet" '[ "$(jq -r ".items[] | select(.id==\"222\") | .status" "$ROOT/report.json")" = failed ]'
check "compte rendu : 999 en échec" '[ "$(jq -r ".items[] | select(.id==\"999\") | .status" "$ROOT/report.json")" = failed ]'
check "compte rendu : rien pour l'\''objet inchangé" '[ "$(jq ".items | length" "$ROOT/report.json")" = 3 ]'

# --- scénario 2 : mise à jour d'un serveur existant : `preserve` -------------
S="$ROOT/s2/server"; W="$ROOT/s2/work"
mkdir -p "$S/config" "$S/saves/world" "$W"
echo old-bin > "$S/game.bin"
echo "ma config" > "$S/config/server.cfg"
echo "ma partie" > "$S/saves/world/data"
ln -s "saves/world" "$S/.DepotDownloader"        # métadonnées détournées DANS le volume : retiré aussi
redeem "$DECL_ACCOUNT" '[]' 1
rm -f "$ROOT/report.json" "$ROOT/filelist-seen.txt"
OUT="$(run_worker "$S" "$W" "" 2>&1)"; STATUS=$?
check "scénario 2 : succès" '[ "$STATUS" -eq 0 ]'
check "liste de protection passée" 'grep -q "^regex:" "$ROOT/filelist-seen.txt"'
check "binaire mis à jour" '[ "$(cat "$S/game.bin")" = bin ]'
check "configuration du client gardée" '[ "$(cat "$S/config/server.cfg")" = "ma config" ]'
check "dossier gardé (rien d'\''écrit dedans)" '[ "$(cat "$S/saves/world/data")" = "ma partie" ] && [ ! -e "$S/saves/readme.txt" ]'
check "protection annoncée" 'grep -q "Gardés tels quels" <<< "$OUT"'
check "métadonnées dans un vrai dossier, pas au travers du lien" '[ -d "$S/.DepotDownloader" ] && [ ! -L "$S/.DepotDownloader" ] && [ ! -e "$S/saves/world/depot.manifest" ]'

# --- scénario 3 : jeton refusé par Steam -------------------------------------
S="$ROOT/s3/server"; W="$ROOT/s3/work"; mkdir -p "$S" "$W"; rm -f "$ROOT/report.json"
redeem "$DECL_ACCOUNT" "$ITEMS" 1
OUT="$(STUB_REJECT=1 HOOK_OUT="$ROOT/s3/hook.out" run_worker "$S" "$W" "$ROOT/hook.sh" 2>&1)"; STATUS=$?
check "scénario 3 : échec" '[ "$STATUS" -ne 0 ]'
check "message « reconnecter »" 'grep -q "Reconnectez votre compte Steam" <<< "$OUT"'
check "compte rendu : token_rejected" '[ "$(jq -r .login "$ROOT/report.json")" = token_rejected ]'
check "crochet non lancé" '[ ! -e "$ROOT/s3/hook.out" ]'
check "jeton effacé après refus" '[ -z "$(find "$ROOT/s3" -name account.config)" ]'

# --- scénario 4 : jeu sans compte, SteamCMD anonyme ---------------------------
S="$ROOT/s4/server"; W="$ROOT/s4/work"
mkdir -p "$S/config" "$W"
echo "ma config" > "$S/config/server.cfg"
DECL_ANON='{"app_id": 896660, "login_required": false, "branch": "public_test", "platform": "linux", "install_dir": "", "workshop": {"app_id": 892970, "enabled": true}, "preserve": ["config/server.cfg"]}'
redeem "$DECL_ANON" '[{"id": "444", "title": "Objet", "server_side": false, "update": true}, {"id": "999", "title": "Cassé", "server_side": false, "update": true}]' 0
rm -f "$ROOT/report.json" "$ROOT/scmd-args.txt" "$ROOT/dd-args.txt"
OUT="$(HOOK_OUT="$ROOT/s4/hook.out" run_worker "$S" "$W" "$ROOT/hook.sh" 2>&1)"; STATUS=$?
check "scénario 4 : succès" '[ "$STATUS" -eq 0 ]'
check "SteamCMD anonyme, branche, plate-forme" 'grep -q "+@sSteamCmdForcePlatformType linux +force_install_dir $S +login anonymous +app_update 896660 -beta public_test +quit" "$ROOT/scmd-args.txt"'
check "DepotDownloader jamais lancé" '[ ! -s "$ROOT/dd-args.txt" ]'
check "configuration gardée malgré SteamCMD" '[ "$(cat "$S/config/server.cfg")" = "ma config" ] && [ ! -e "$S/.ouipanel-preserve" ]'
check "serveur posé" '[ "$(cat "$S/game.bin")" = bin ]'
check "objet anonyme dans le dossier standard" '[ -f "$S/steamapps/workshop/content/892970/444/Addons/Mod.PBO" ]'
check "crochet : connexion anonyme" 'grep -q "^login=anonymous$" "$ROOT/s4/hook.out"'
check "compte rendu : anonymous, 444 installé, 999 en échec" '[ "$(jq -r .login "$ROOT/report.json")" = anonymous ] && [ "$(jq -r ".items[] | select(.id==\"444\") | .status" "$ROOT/report.json")" = installed ] && [ "$(jq -r ".items[] | select(.id==\"999\") | .status" "$ROOT/report.json")" = failed ]'

# --- scénario 5 : SteamCMD échoue : les fichiers mis de côté reviennent -------
S="$ROOT/s5/server"; W="$ROOT/s5/work"; mkdir -p "$S/config" "$W"
echo "ma config" > "$S/config/server.cfg"
redeem "$DECL_ANON" '[]' 0
rm -f "$ROOT/report.json"
OUT="$(STUB_SCMD_FAIL=1 run_worker "$S" "$W" "" 2>&1)"; STATUS=$?
check "scénario 5 : échec signalé" '[ "$STATUS" -ne 0 ] && [ "$(jq -r .login "$ROOT/report.json")" = failed ]'
check "configuration remise après l'\''échec" '[ "$(cat "$S/config/server.cfg")" = "ma config" ] && [ ! -e "$S/.ouipanel-preserve" ]'

# --- scénario 6 : réponses du panel refusées ----------------------------------
for bad in \
    '{"app_id": 1, "login_required": true, "branch": "a b", "platform": "linux", "install_dir": ""}' \
    '{"app_id": 1, "login_required": true, "branch": "public", "platform": "macos", "install_dir": ""}' \
    '{"app_id": 1, "login_required": true, "branch": "public", "platform": "linux", "install_dir": "../x"}' \
    '{"app_id": "1;id", "login_required": true, "branch": "public", "platform": "linux", "install_dir": ""}'; do
    S="$ROOT/s6/server"; W="$ROOT/s6/work"; rm -rf "$ROOT/s6"; mkdir -p "$S" "$W"; rm -f "$ROOT/dd-args.txt"
    redeem "$bad" '[]' 1
    OUT="$(run_worker "$S" "$W" "" 2>&1)"; STATUS=$?
    check "réponse refusée : $bad" '[ "$STATUS" -ne 0 ] && grep -q "Réponse du panel illisible" <<< "$OUT" && [ ! -s "$ROOT/dd-args.txt" ] && [ -z "$(find "$ROOT/s6" -name account.config)" ]'
done

# --- scénario 7 : compte requis mais absent ----------------------------------
S="$ROOT/s7/server"; W="$ROOT/s7/work"; mkdir -p "$S" "$W"; rm -f "$ROOT/dd-args.txt" "$ROOT/scmd-args.txt"
redeem "$DECL_ACCOUNT" '[]' 0
OUT="$(run_worker "$S" "$W" "" 2>&1)"; STATUS=$?
check "scénario 7 : refus sans téléchargement" '[ "$STATUS" -ne 0 ] && grep -q "demande un compte Steam" <<< "$OUT" && [ ! -s "$ROOT/dd-args.txt" ] && [ ! -s "$ROOT/scmd-args.txt" ]'

# --- scénario 8 : sous-dossier d'installation ---------------------------------
S="$ROOT/s8/server"; W="$ROOT/s8/work"; mkdir -p "$S" "$W" "$ROOT/outside8"
ln -s "$ROOT/outside8" "$S/game"
redeem '{"app_id": 1, "login_required": true, "branch": "public", "platform": "windows", "install_dir": "game/server"}' '[]' 1
rm -f "$ROOT/dd-args.txt"
OUT="$(run_worker "$S" "$W" "" 2>&1)"; STATUS=$?
check "scénario 8 : succès dans un vrai sous-dossier" '[ "$STATUS" -eq 0 ] && [ -d "$S/game/server" ] && [ ! -L "$S/game" ] && [ -f "$S/game/server/game.bin" ]'
check "la cible du lien remplacé est intacte" '[ -z "$(ls -A "$ROOT/outside8")" ]'
check "plate-forme windows passée" 'grep -q -- "-os windows" "$ROOT/dd-args.txt"'

# --- scénario 9 : ticket refusé par le panel ----------------------------------
S="$ROOT/s9/server"; W="$ROOT/s9/work"; mkdir -p "$S" "$W"; rm -f "$ROOT/report.json"
redeem "$DECL_ACCOUNT" '[]' 1
OUT="$(STUB_REDEEM_FAIL=1 run_worker "$S" "$W" "" 2>&1)"; STATUS=$?
check "scénario 9 : échec sans téléchargement ni compte rendu" '[ "$STATUS" -ne 0 ] && [ ! -e "$S/game.bin" ] && [ ! -e "$ROOT/report.json" ]'

# --- scénario 10 : panel occupé (429), puis disponible -------------------------
S="$ROOT/s10/server"; W="$ROOT/s10/work"; mkdir -p "$S" "$W"; rm -f "$ROOT/report.json"
redeem "$DECL_ACCOUNT" '[]' 1
OUT="$(STUB_BUSY=2 run_worker "$S" "$W" "" 2>&1)"; STATUS=$?
check "scénario 10 : deux 429 puis succès" '[ "$STATUS" -eq 0 ] && [ "$(grep -c "nouvel essai" <<< "$OUT")" -eq 2 ] && [ "$(jq -r .login "$ROOT/report.json")" = ok ]'

# --- scénario 11 : panel toujours occupé : abandon sans téléchargement ----------
S="$ROOT/s11/server"; W="$ROOT/s11/work"; mkdir -p "$S" "$W"; rm -f "$ROOT/dd-args.txt"
redeem "$DECL_ACCOUNT" '[]' 1
OUT="$(STUB_BUSY=9 run_worker "$S" "$W" "" 2>&1)"; STATUS=$?
check "scénario 11 : six essais puis abandon" '[ "$STATUS" -ne 0 ] && [ "$(cat "$W/.stub-counter")" -eq 6 ] && [ ! -s "$ROOT/dd-args.txt" ]'

# --- scénario 11 bis : 429 « too_many_failures » : déjà traité, pas de nouvel essai
S="$ROOT/s11b/server"; W="$ROOT/s11b/work"; mkdir -p "$S" "$W"
redeem "$DECL_ACCOUNT" '[]' 1
OUT="$(STUB_FAILCAP=1 run_worker "$S" "$W" "" 2>&1)"; STATUS=$?
check "scénario 11 bis : un seul essai" '[ "$STATUS" -ne 0 ] && [ "$(cat "$W/.stub-counter")" -eq 1 ] && ! grep -q "nouvel essai" <<< "$OUT"'

# --- scénario 11 ter : Retry-After respecté ------------------------------------
S="$ROOT/s11c/server"; W="$ROOT/s11c/work"; mkdir -p "$S" "$W"
redeem "$DECL_ACCOUNT" '[]' 1
OUT="$(STUB_BUSY=1 STUB_RETRY_AFTER=1 run_worker "$S" "$W" "" 2>&1)"; STATUS=$?
check "scénario 11 ter : attente de Retry-After, puis succès" '[ "$STATUS" -eq 0 ] && grep -q "nouvel essai dans 1 s" <<< "$OUT"'

# --- scénario 12 : réponse refusée ici, mais jeton de compte rendu valable ------
S="$ROOT/s12/server"; W="$ROOT/s12/work"; mkdir -p "$S" "$W"; rm -f "$ROOT/report.json"
redeem '{"app_id": 1, "login_required": true, "branch": "a b", "platform": "linux", "install_dir": ""}' '[]' 1
OUT="$(run_worker "$S" "$W" "" 2>&1)"; STATUS=$?
check "scénario 12 : le panel apprend l'\''échec (pas « en cours » 6 h)" '[ "$STATUS" -ne 0 ] && [ "$(jq -r .login "$ROOT/report.json")" = failed ] && [ "$(jq -r .report_token "$ROOT/report.json")" = "$REPORT_TOKEN" ]'

# --- scénario 13 : dossier d'installation impossible à créer : compte rendu -----
S="$ROOT/s13/server"; W="$ROOT/s13/work"; mkdir -p "$S" "$W"; chmod 555 "$S"; rm -f "$ROOT/report.json"
redeem '{"app_id": 1, "login_required": true, "branch": "public", "platform": "linux", "install_dir": "game"}' '[]' 1
OUT="$(run_worker "$S" "$W" "" 2>&1)"; STATUS=$?
chmod 755 "$S"
check "scénario 13 : échec signalé au panel" '[ "$STATUS" -ne 0 ] && [ "$(jq -r .login "$ROOT/report.json")" = failed ] && [ -z "$(find "$ROOT/s13" -name account.config)" ]'

# --- scénario 14 : crochet annoncé mais absent, ou sans oh_hook : échec visible --
S="$ROOT/s14/server"; W="$ROOT/s14/work"; mkdir -p "$S" "$W"; rm -f "$ROOT/report.json"
redeem "$DECL_ACCOUNT" '[]' 1
OUT="$(run_worker "$S" "$W" "$ROOT/crochet-absent.sh" 2>&1)"; STATUS=$?
check "scénario 14 : crochet absent = échec, jamais « installé »" '[ "$STATUS" -ne 0 ] && grep -q "crochet de l'\''egg est introuvable" <<< "$OUT" && [ "$(jq -r .login "$ROOT/report.json")" = failed ]'
printf 'autre_fonction() { :; }\n' > "$ROOT/sans-oh-hook.sh"
S="$ROOT/s14b/server"; W="$ROOT/s14b/work"; mkdir -p "$S" "$W"; rm -f "$ROOT/report.json"
redeem "$DECL_ACCOUNT" '[]' 1
OUT="$(run_worker "$S" "$W" "$ROOT/sans-oh-hook.sh" 2>&1)"; STATUS=$?
check "scénario 14 bis : crochet sans oh_hook = échec" '[ "$STATUS" -ne 0 ] && grep -q "ne définit pas oh_hook" <<< "$OUT" && [ "$(jq -r .login "$ROOT/report.json")" = failed ]'

# --- scénario 15 : ticket émis mais adresse du panel mal réglée : rend 3, et le dit
OUT="$(env -i PATH="$ROOT/bin:/usr/bin:/bin" OH_TICKET="$TICKET" OH_TICKET_URL="https://panel.test/sous-dossier/api/hooks/steam/ticket" bash "$INSTALLER" 2>&1)"; STATUS=$?
check "scénario 15 : adresse avec un chemin = code 4 et message" '[ "$STATUS" -eq 4 ] && grep -q "Adresse du panel invalide" <<< "$OUT" && grep -q "rien n'\''a été téléchargé" <<< "$OUT"'
OUT="$(env -i PATH="$ROOT/bin:/usr/bin:/bin" OH_TICKET="unavailable" OH_TICKET_URL="https://panel.test/api/hooks/steam/ticket" bash "$INSTALLER" 2>&1)"; STATUS=$?
check "scénario 15 ter : ticket non émis par le panel = code 4, message juste" '[ "$STATUS" -eq 4 ] && grep -q "n'\''a pas pu préparer la connexion Steam" <<< "$OUT" && ! grep -qi "aucun compte" <<< "$OUT"'
OUT="$(env -i PATH="$ROOT/bin:/usr/bin:/bin" OH_TICKET="" OH_TICKET_URL="https://panel.test/api/hooks/steam/ticket" bash "$INSTALLER" 2>&1)"; STATUS=$?
check "scénario 15 bis : sans ticket = code 3, en silence" '[ "$STATUS" -eq 3 ] && [ -z "$OUT" ]'

# --- aucun secret dans la ligne de commande d'un processus ----------------------
check "le ticket ne passe jamais en argument (curl, jq)" '[ -s "$ROOT/argv.log" ] && ! grep -q "$TICKET" "$ROOT/argv.log"'
check "le jeton de compte rendu non plus" '! grep -q "$REPORT_TOKEN" "$ROOT/argv.log"'
check "ni le jeton Steam" '! grep -q "$TOKEN_MARK" "$ROOT/argv.log" && ! grep -q "$(printf "config-%s" "$TOKEN_MARK" | base64 -w0)" "$ROOT/argv.log"'

# --- point d'entrée et contrôles de forme -------------------------------------
OUT="$(env -i PATH="$ROOT/bin:/usr/bin:/bin" OH_TICKET="" OH_TICKET_URL="" bash "$INSTALLER" 2>&1)"; STATUS=$?
check "sans ticket : code 3 (l'\''egg prend son ancien chemin)" '[ "$STATUS" -eq 3 ]'
OUT="$(env -i PATH="$ROOT/bin:/usr/bin:/bin" OH_TICKET="__OUIPANEL_STEAM_TICKET__" OH_TICKET_URL="https://panel.test/api/hooks/steam/ticket" bash "$INSTALLER" 2>&1)"; STATUS=$?
check "repère non remplacé : code 3" '[ "$STATUS" -eq 3 ]'
OUT="$(env -i PATH="$ROOT/bin:/usr/bin:/bin" OH_TICKET="$TICKET" OH_TICKET_URL="http://panel.test/api/hooks/steam/ticket" bash "$INSTALLER" 2>&1)"; STATUS=$?
check "adresse en http : code 4 (connexion prévue mais inutilisable), jamais l'\''ancien chemin" '[ "$STATUS" -eq 4 ] && grep -q "Adresse du panel invalide" <<< "$OUT"'
OUT="$(env -i PATH="$ROOT/bin:/usr/bin:/bin" OH_TICKET="$TICKET" OH_TICKET_URL="https://panel.test/api/hooks/steam/ticket" bash "$INSTALLER" --env LD_PRELOAD 2>&1)"; STATUS=$?
check "variable dangereuse refusée" '[ "$STATUS" -eq 1 ] && grep -q "Variable refusée" <<< "$OUT"'

(
    export OUIPANEL_INSTALL_TEST=1
    # shellcheck disable=SC1090
    source "$INSTALLER"
    bad=0
    oh_valid_ticket "$TICKET" || bad=1
    oh_valid_ticket "${TICKET}0" && bad=1
    oh_valid_ticket_url "https://ouipanel.com/api/hooks/steam/ticket" || bad=1
    oh_valid_ticket_url "https://ouipanel.com:8443/api/hooks/steam/ticket" || bad=1
    for u in "http://ouipanel.com/api/hooks/steam/ticket" "https://ouipanel.com/api/hooks/steam/ticket?x=1" "https://a@b/api/hooks/steam/ticket"; do
        oh_valid_ticket_url "$u" && bad=1
    done
    oh_valid_relpath "serverDZ.cfg" || bad=1
    oh_valid_relpath "mpmissions/" || bad=1
    oh_valid_relpath "profiles/BattlEye/beserver.cfg" || bad=1
    for p in "../x" "a/../b" "/etc" "" "a b" '$(id)' "*.cfg" ".hidden/../x" "a//b"; do
        oh_valid_relpath "$p" && bad=1
    done
    # Un joker ne devient pas les fichiers du dossier courant.
    cd "$ROOT" && touch "$ROOT/fichier_ok" && for p in "*" "fichier_*" "a/*" "?ichier_ok"; do
        oh_valid_relpath "$p" && bad=1
    done
    case "$-" in *f*) bad=1 ;; esac   # le globbing de l'appelant est intact
    # OH_RETRY_DELAY n'entre jamais tel quel dans un calcul : une valeur
    # piégée est remplacée par 10 (aucune commande exécutée).
    export OH_WORK_DIR="$ROOT/retry-check"; mkdir -p "$OH_WORK_DIR"
    curl() { local n; n="$(cat "$OH_WORK_DIR/n" 2> /dev/null || echo 0)"; echo $((n + 1)) > "$OH_WORK_DIR/n"; [ "$n" -eq 0 ] && printf 503 || printf 200; }
    sleep() { printf '%s' "$1" > "$OH_WORK_DIR/slept"; }
    printf '{}' > "$OH_WORK_DIR/body"
    OH_RETRY_DELAY='x[$(touch "$ROOT/injected")]'
    oh_post "$OH_WORK_DIR/body" "$OH_WORK_DIR/out" "https://panel.test/api/hooks/steam/ticket" > /dev/null || bad=1
    [ ! -e "$ROOT/injected" ] || bad=1
    slept="$(cat "$OH_WORK_DIR/slept" 2> /dev/null)"
    [[ "$slept" =~ ^1[0-4]$ ]] || bad=1
    # « 08 » et « 09 » : pas de zéro de tête (octal pour $(( ))) : délai de 10.
    for delay in 08 09; do
        rm -f "$OH_WORK_DIR/n" "$OH_WORK_DIR/slept"
        OH_RETRY_DELAY="$delay"
        oh_post "$OH_WORK_DIR/body" "$OH_WORK_DIR/out" "https://panel.test/api/hooks/steam/ticket" > /dev/null 2>&1 || bad=1
        [[ "$(cat "$OH_WORK_DIR/slept" 2> /dev/null)" =~ ^1[0-4]$ ]] || bad=1
    done
    # Retry-After « 08 » : lu en base 10, attente de 8 s.
    curl() { local n; n="$(cat "$OH_WORK_DIR/n" 2> /dev/null || echo 0)"; echo $((n + 1)) > "$OH_WORK_DIR/n"
        if [ "$n" -eq 0 ]; then printf 'HTTP/1.1 429\r\nRetry-After: 08\r\n' > "$OH_WORK_DIR/post-headers.txt"; printf 429; else printf 200; fi; }
    rm -f "$OH_WORK_DIR/n" "$OH_WORK_DIR/slept"
    OH_RETRY_DELAY=0
    oh_post "$OH_WORK_DIR/body" "$OH_WORK_DIR/out" "https://panel.test/api/hooks/steam/ticket" > /dev/null 2>&1 || bad=1
    [ "$(cat "$OH_WORK_DIR/slept" 2> /dev/null)" = 8 ] || bad=1
    unset -f curl sleep
    oh_valid_branch "public" || bad=1
    for b in "a b" "a;b" "" "-betapassword"; do
        [ "$b" = "-betapassword" ] && continue
        oh_valid_branch "$b" && bad=1
    done
    oh_valid_env_name "QUERY_PORT" || bad=1
    for n in PATH LD_PRELOAD OH_TICKET BASH_ENV lower "1X" DOTNET_ROOT; do
        oh_valid_env_name "$n" && bad=1
    done
    [ "$(oh_regex_escape 'a.b(c)/d$')" = 'a\.b\(c\)/d\$' ] || bad=1
    exit $bad
)
VALIDATIONS=$?
check "validations (ticket, adresse, chemins, branche, variables, échappement)" '[ "$VALIDATIONS" -eq 0 ]'

check "le script ne lance rien quand il est chargé par un banc" '[ -z "$(OUIPANEL_INSTALL_TEST=1 bash -c "source \"$INSTALLER\"; echo -n" 2>&1)" ]'

printf '%d contrôles, %d échec(s)\n' "$CHECKS" "$FAILS"
[ "$FAILS" -eq 0 ]
