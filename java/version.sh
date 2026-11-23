#!/bin/bash
# Version de Java d'une image, lue dans la ligne FROM de java/<dossier>/Dockerfile.
# C'est la seule source : Dependabot ne met à jour que cette ligne.
#
# Usage : java/version.sh <dossier>      (8, 17, 21_graalvm…)
# Sortie, au format de $GITHUB_OUTPUT :
#   courte=21.0.13.1               étiquette versionnée : java_21-21.0.13.1
#   attendu=(build 21.0.13.1+2)    texte que `java -version` doit afficher
set -euo pipefail

dossier="${1:?usage : version.sh <dossier de java/>}"
fichier="$(dirname "$0")/$dossier/Dockerfile"
[ -f "$fichier" ] || { echo "introuvable : $fichier" >&2; exit 1; }

# Première ligne FROM qui porte le JDK (pour GraalVM, l'étape « AS graalvm »).
ligne=$(grep -m1 -E '^FROM[[:space:]].*(eclipse-temurin|graalvm/jdk-community):' "$fichier" || true)
[ -n "$ligne" ] || { echo "aucune base Java dans $fichier" >&2; exit 1; }
image=$(awk '{ for (i = 2; i <= NF; i++) if ($i !~ /^--/) { print $i; exit } }' <<<"$ligne")
tag=${image##*:}

courte=""
case "$image" in
    eclipse-temurin:*)
        if [[ $tag =~ ^8u([0-9]+)-b([0-9]+)-jdk- ]]; then
            # 8u512-b09-jdk-noble : « openjdk version "1.8.0_512" … (build 1.8.0_512-b09) »
            courte="8u${BASH_REMATCH[1]}"
            attendu="(build 1.8.0_${BASH_REMATCH[1]}-b${BASH_REMATCH[2]})"
        elif [[ $tag =~ ^([0-9]+(\.[0-9]+)*)_([0-9]+)-jdk- ]]; then
            # 17.0.21.1_2-jdk-noble : « Temurin-17.0.21.1+2 (build 17.0.21.1+2) »
            courte="${BASH_REMATCH[1]}"
            attendu="(build ${BASH_REMATCH[1]}+${BASH_REMATCH[3]})"
        fi
        ;;
    ghcr.io/graalvm/jdk-community:*)
        # 21.0.2-ol9, 25i5-25.0.5.0.3-ol9 : « openjdk version "25.0.5.0.3" »
        if [[ $tag =~ ^([0-9]+i[0-9]+-)?([0-9]+(\.[0-9]+)+)-ol[0-9]+$ ]]; then
            courte="${BASH_REMATCH[2]}"
            attendu="openjdk version \"${BASH_REMATCH[2]}\""
        fi
        ;;
esac
[ -n "$courte" ] || { echo "étiquette non reconnue : $image" >&2; exit 1; }

echo "courte=$courte"
echo "attendu=$attendu"
