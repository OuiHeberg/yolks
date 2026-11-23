#!/bin/bash
# Racines retirées (java/racines-retirees.txt) : vraies connexions TLS faites par le Java de
# l'image, avec son magasin de certificats.
# Usage : java/tests/racines-tls.sh <image> <dossier de java/>
#
#  - Sectigo, chaîne envoyée « … <- USERTrust RSA <- AAA Certificate Services » : doit être
#    ACCEPTÉE (le retrait de « Comodo AAA » ne casse pas Sectigo : la racine USERTrust RSA suffit).
#    Au moins un des deux sites doit répondre, et sa chaîne doit bien passer par AAA.
#  - Sites de démonstration de la compromission d'eMudhra (chaînes vers emSign ECC G3 et vers
#    AAA) : doivent être REFUSÉS. Un site de démonstration injoignable n'est pas un échec.
# Besoin du réseau : lancé par le banc seulement.
set -uo pipefail

image="${1:?usage : racines-tls.sh <image> <dossier>}"
dossier="${2:?usage : racines-tls.sh <image> <dossier>}"
tests="$(cd "$(dirname "$0")" && pwd)"

sectigo=(www.comodoca.com www.ionos.fr)
emudhra=(dv-g3b-emudhra.we-have-a-problem.com dv-g3b-aaa-emudhra.we-have-a-problem.com)

echo "== Connexions TLS de java_$dossier ($image)"
sortie=$(docker run --rm --pull=never --entrypoint bash -v "$tests:/tests:ro" "$image" -c '
    mkdir -p /tmp/v && javac -encoding UTF-8 -d /tmp/v /tests/VerifTls.java || exit 9
    for h in "$@"; do
        java -cp /tmp/v VerifTls "$h" > "/tmp/v/$h.txt" 2>&1
        code=$?
        sed "s/^/    /" "/tmp/v/$h.txt"
        echo "code=$h=$code"
    done' _ "${sectigo[@]}" "${emudhra[@]}" 2>&1)
rc=$?
echo "$sortie"
[ $rc -ne 9 ] || { echo "ÉCHEC : compilation de VerifTls.java"; exit 1; }
code_de() { sed -n "s/^code=$1=//p" <<<"$sortie"; }
# Lignes affichées pour un hôte : celles qui précèdent sa ligne « code=… ».
bloc_de() {
    awk -v fin="code=$1=" 'index($0, "code=") == 1 { if (index($0, fin) == 1) { printf "%s", b; exit } b = ""; next } { b = b $0 "\n" }' <<<"$sortie"
}

echec=0
accepte_via_aaa=0
for h in "${sectigo[@]}"; do
    case "$(code_de "$h")" in
        0) if grep -q 'AAA Certificate Services' <<<"$(bloc_de "$h")"; then
               accepte_via_aaa=1; echo "OK : Sectigo accepté, chaîne envoyée par AAA : $h"
           else
               echo "OK : Sectigo accepté : $h (chaîne envoyée sans AAA)"
           fi ;;
        2) echo "ÉCHEC : chaîne Sectigo refusée : $h"; echec=1 ;;
        *) echo "INFO : $h injoignable" ;;
    esac
done
[ $accepte_via_aaa -eq 1 ] || { echo "ÉCHEC : aucune chaîne Sectigo passant par AAA n'a pu être vérifiée"; echec=1; }

for h in "${emudhra[@]}"; do
    case "$(code_de "$h")" in
        2) echo "OK : chaîne eMudhra refusée : $h" ;;
        0) echo "ÉCHEC : chaîne eMudhra ACCEPTÉE : $h"; echec=1 ;;
        *) echo "INFO : site de démonstration injoignable : $h" ;;
    esac
done

[ $echec -eq 0 ] && echo "== java_$dossier : connexions TLS conformes" || echo "== java_$dossier : connexions TLS non conformes"
exit $echec
