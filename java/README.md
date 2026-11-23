# Images Java des serveurs de jeu OuiPanel

Images `ghcr.io/ouiheberg/yolks:java_*` pour les eggs Pterodactyl/Wings (Minecraft, Hytale…).
Elles nous évitent de dépendre d'images tierces : une faille Java se corrige ici, en changeant
une ligne `FROM`, sans attendre que quelqu'un d'autre reconstruise son image.

Dockerfiles et `entrypoint.sh` repris de [pelican-eggs/yolks@3680e41](https://github.com/pelican-eggs/yolks/tree/3680e41e0286cf0ff4276fe59f69334e4b3d2bc9/java)
(licence MIT, voir `LICENSE.md` à la racine). Écarts avec l'amont : base Java épinglée sur
une version précise, étiquettes OuiHeberg, `apt upgrade` à chaque construction, atténuation de
CVE-2026-114938 pour les JDK sans correctif, racines eMudhra retirées des JDK en fin de vie
(voir plus bas), et pour Java 16 et GraalVM un JDK recopié sur `ubuntu:noble`.

## Images

| Étiquette | Base | Java | CVE-2026-114938 (Java4Shell) |
|---|---|---|---|
| `java_8` | `eclipse-temurin:8u512-b09-jdk-noble` | 8u512 | non concerné |
| `java_11` | `eclipse-temurin:11.0.33_10-jdk-noble` | 11.0.33 | non concerné |
| `java_16` | JDK de `eclipse-temurin:16.0.2_7-jdk-focal` sur `ubuntu:noble` | 16.0.2 (fin de vie) | non concerné (code absent avant 17.0.6) |
| `java_17` | `eclipse-temurin:17.0.21.1_2-jdk-noble` | 17.0.21.1 | corrigé |
| `java_21` | `eclipse-temurin:21.0.13.1_2-jdk-noble` | 21.0.13.1 | corrigé |
| `java_22` | `eclipse-temurin:22.0.2_9-jdk-noble` | 22.0.2 (fin de vie) | pas de correctif, atténué |
| `java_25` | `eclipse-temurin:25.0.5.1_2-jdk-noble` | 25.0.5.1 | corrigé |
| `java_26` | `eclipse-temurin:26.0.2.1_1-jdk-noble` | 26.0.2.1 (fin de vie) | pas de correctif, atténué |
| `java_21_graalvm` | `ghcr.io/graalvm/jdk-community:21.0.2-ol9` | GraalVM CE 21.0.2 (fin de vie) | pas de correctif, atténué |
| `java_25_graalvm` | `ghcr.io/graalvm/jdk-community:25i5-25.0.5.0.3-ol9` | GraalVM CE 25.0.5.0.3 | pas encore de correctif, atténué |

Chaque image est aussi publiée sous une étiquette versionnée, pour un retour arrière :
`java_21-21.0.13.1`, `java_8-8u512`, `java_25_graalvm-25.0.5.0.3`…
`linux/amd64` seulement, comme les images Node.

Communs à toutes : utilisateur `container`, `HOME` et `WORKDIR` `/home/container`,
`STOPSIGNAL SIGINT`, `tini -g` puis `/entrypoint.sh` (remplace les `{{VARIABLE}}` de la
commande de démarrage et l'exécute). Paquets de l'amont : curl, lsof, ca-certificates,
openssl, git, tar, sqlite3, fontconfig, tzdata, iproute2, libfreetype6, tini, zip, unzip,
jq, et redis-tools pour 8, 11, 16, 17, 21, 22 et `java_21_graalvm`. Chaque construction (donc
chaque lundi) fait `apt upgrade` : le système reçoit les correctifs Ubuntu même quand la base
Java n'est plus reconstruite par Docker Hub (16, 22, 26).

**GraalVM** : GraalVM Community seulement (pas d'Oracle GraalVM, licence GFTC). Le JDK est
recopié tel quel de l'image officielle (Oracle Linux 9) et posé sur `ubuntu:noble`, avec les
mêmes paquets et le même entrypoint que les images Temurin.

**Java 16** : la dernière image Temurin 16 est sur Ubuntu 20.04, qui ne reçoit plus de
correctifs depuis mai 2025. Son JDK est recopié de la même façon sur `ubuntu:noble`.

## Racines de certificats retirées (eMudhra)

Après la compromission d'eMudhra (17/10/2026), Debian et Ubuntu ont retiré « Comodo AAA »
(`CN=AAA Certificate Services`) et « emSign ECC Root CA - G3 ». Les JDK en fin de vie les
ont encore : `java/retirer-racines.sh` les retire du magasin du JDK à la construction de
`java_16`, `java_22`, `java_26` et `java_21_graalvm`, par empreinte SHA-256
(`java/racines-retirees.txt`). Les autres racines emSign restent, comme chez Debian. Le
magasin du système (Ubuntu à jour) ne les a déjà plus. Le banc vérifie leur absence des deux
magasins dans les 10 images, puis fait de vraies connexions TLS depuis Java : une chaîne
Sectigo envoyée par « USERTrust RSA <- AAA » reste acceptée (la racine USERTrust RSA suffit),
et les sites de démonstration de la compromission sont refusés. Le contrôle de révocation
(`checkRevocation`, `enableCRLDP`) n'est pas activé : il bloquerait les connexions quand un
serveur de CRL ne répond pas.

## CVE-2026-114938 (Java4Shell)

Écriture hors limites dans le décodage Base64 AVX-512 de HotSpot : Java 17.0.6 et plus, sur
processeur AVX-512 VBMI (Intel Ice Lake et plus récents, AMD Zen 4 et plus récents).
Corrigé dans Temurin 17.0.21.1, 21.0.13.1, 25.0.5.1 (et 27.0.1.1).

Pour les JDK sans version corrigée, l'image pose `OH_JAVA4SHELL_ATTENUATION` et l'entrypoint
ajoute ces options à la fin de `JDK_JAVA_OPTIONS` (les options de l'egg sont gardées) :

- `java_22`, `java_26`, `java_21_graalvm` : `-XX:-UseBASE64Intrinsics` ;
- `java_25_graalvm` : `-XX:-UseBASE64Intrinsics -XX:UseAVX=2`. Depuis Graal 25.1, le
  compilateur Graal a son propre décodage Base64 AVX-512, avec le même défaut (corrigé dans
  Graal par GR-79579, pas encore publié dans une version Community) et que
  `-XX:-UseBASE64Intrinsics` ne coupe pas. `-XX:UseAVX=2` retire l'AVX-512 à HotSpot et à Graal.

La console affiche alors `NOTE: Picked up JDK_JAVA_OPTIONS: …` à chaque démarrage. Retirer la
ligne `ENV OH_JAVA4SHELL_ATTENUATION` d'une image dès que son JDK est corrigé.

## En cas de nouvelle faille Java

1. Fusionner la PR de Dependabot qui monte la base (une PR par dossier, ouverte dans la
   journée où l'étiquette paraît sur Docker Hub), ou changer soi-même la ligne `FROM`.
   Dependabot ne suit pas `java/8` (étiquettes `8uNNN-bNN`) ni `java/25_graalvm`
   (étiquettes `25iN-…`) : pour ces deux-là, changer le `FROM` à la main. La PR lance le banc :
   construction, contrôles, vrai démarrage Paper.
2. La fusion sur `main` lance le workflow `build java`, qui republie l'étiquette courante et
   l'étiquette versionnée, puis tire l'image sans identifiant et la contrôle.
3. Les serveurs prennent la nouvelle image à leur prochain démarrage (Wings tire l'image à
   chaque démarrage). Aucun redémarrage n'est forcé.

Si le JDK corrigé n'existe pas encore, une atténuation peut être posée de la même façon :
`ENV OH_JAVA4SHELL_ATTENUATION="…"` dans le Dockerfile concerné (malgré son nom, la variable
accepte n'importe quelles options de la JVM 9 et plus).

## Publication et visibilité du paquet

- Sur une pull request : banc seulement, rien n'est publié.
- Sur `main` (push dans `java/`, chaque lundi 03:00 UTC, ou lancement à la main) : publication.
- Les images Java sont des étiquettes du paquet `ghcr.io/ouiheberg/yolks`, **déjà public**
  (images Node, Steam, DayZ, Enshrouded) : Wings les tire sans identifiant.
- Un paquet ghcr **créé** par GitHub Actions est **privé** par défaut. Si un jour une image
  est publiée sous un autre nom de paquet, Arthur doit le rendre public (Package settings,
  Danger Zone, Change visibility), sinon Wings ne peut pas le tirer.

## Tests

- `java/version.sh <dossier>` : version de Java lue dans le `FROM` (étiquette versionnée et
  texte attendu de `java -version`).
- `java/tests/wings.sh` : options de conteneur de Wings (uid 4242 absent des images, racine en
  lecture seule, `/tmp` en tmpfs de 100 Mo, `no-new-privileges`, capacités retirées), reprises
  de `environment/docker/container.go` de notre Wings.
- `java/tests/controle-image.sh <image> <dossier>` : configuration lue par Wings, `java -version`,
  utilisateur et dossier, outils, locale, démarrage `STARTUP='java -version'`, démarrage façon
  Wings (options ci-dessus, dossier du serveur à l'uid 4242), options Java4Shell, absence des
  racines retirées.
- `java/tests/demarrage-paper.sh <image> <dossier>` : vrai serveur Paper (jar épinglé) avec la
  commande de démarrage de l'egg 2 et les options de Wings, jusqu'à « Done », puis `stop`
  (17, 21, 22, 25, 26, GraalVM).
- `java/tests/racines-tls.sh <image> <dossier>` : connexions TLS depuis le Java de l'image
  (`java/tests/VerifTls.java`), Sectigo acceptée et eMudhra refusée.
