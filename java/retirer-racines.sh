#!/bin/bash
# Retire du magasin de certificats du JDK ($JAVA_HOME) les racines de racines-retirees.txt
# (Comodo AAA et emSign ECC Root CA - G3, retirées par Debian et Ubuntu après la compromission
# d'eMudhra). Lancé en root à la construction des images dont le JDK ne reçoit plus de mises à
# jour (16, 22, 26, GraalVM 21), par un « RUN --mount » qui ne laisse rien dans l'image.
#
# Pourquoi c'est sans risque pour les chaînes Sectigo qui passent par la contre-signature
# « USERTrust RSA <- AAA » : le validateur de Java accepte comme ancre un certificat de la
# chaîne qui a le même nom et la même clé qu'une racine du magasin, et la racine USERTrust RSA
# reste. Le banc le vérifie (java/tests/racines-tls.sh).
set -euo pipefail

liste="$(dirname "$0")/racines-retirees.txt"
magasin="$JAVA_HOME/lib/security/cacerts"
[ -f "$magasin" ] || magasin="$JAVA_HOME/jre/lib/security/cacerts"
[ -f "$magasin" ] || { echo "magasin du JDK introuvable sous $JAVA_HOME" >&2; exit 1; }

# « empreinte<TAB>alias » pour chaque entrée du magasin.
entrees() {
    keytool -list -v -keystore "$magasin" -storepass changeit 2>/dev/null \
        | awk '/^Alias name: /{ sub(/^Alias name: /, ""); a = $0 } /^[[:space:]]*SHA256: /{ print $2 "\t" a }'
}

grep -v -E '^(#|$)' "$liste" | while read -r empreinte nom; do
    entrees | awk -F'\t' -v e="$empreinte" '$1 == e { print $2 }' | while IFS= read -r alias; do
        keytool -delete -alias "$alias" -keystore "$magasin" -storepass changeit -noprompt
        echo "Retirée du magasin du JDK : $nom (alias « $alias »)"
    done
done

restantes=$(entrees | cut -f1 | grep -xF -f <(grep -v -E '^(#|$)' "$liste" | awk '{ print $1 }') || true)
[ -z "$restantes" ] || { echo "Racine encore présente dans $magasin : $restantes" >&2; exit 1; }
echo "Magasin du JDK sans les racines de racines-retirees.txt : $magasin"
