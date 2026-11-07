#!/bin/bash

## ghcr.io/ouiheberg/yolks:enshrouded-proton : entrypoint au format des yolks
## (comme ptero-eggs/yolks wine) : dossier du serveur, mise à jour SteamCMD au
## démarrage, steamclient.so à la place attendue par Proton, puis exécution de
## la commande STARTUP de l'egg (voir README.md).
cd /home/container || exit 1

echo "Running on Debian $(cat /etc/debian_version), Proton $(cut -d' ' -f2 "${PROTON_PATH}/version" 2>/dev/null)"

# Make internal Docker IP address available to processes.
INTERNAL_IP=$(ip route get 1 2>/dev/null | awk '{print $(NF-2);exit}')
export INTERNAL_IP

## Un arrêt (SIGINT ou SIGTERM) reçu d'ici au lancement du jeu est noté, puis
## respecté juste avant la commande de démarrage : sans cela, un SteamCMD qui
## intercepte SIGINT et sort en 0 laissait le script lancer le jeu, et l'arrêt
## demandé pendant la mise à jour était perdu.
stop=
trap 'stop=1' INT TERM

## Mise à jour du jeu par le SteamCMD du volume (posé par le script
## d'installation de l'egg), en anonyme, si AUTO_UPDATE est vide ou vaut 1.
## VALIDATE non vide : validation des fichiers (comme l'image Wine).
if [ -z "${AUTO_UPDATE}" ] || [ "${AUTO_UPDATE}" == "1" ]; then
    if [ -z "${SRCDS_APPID}" ]; then
        echo "No appid set. Starting Server"
    elif [ ! -x ./steamcmd/steamcmd.sh ]; then
        echo "WARNING: SteamCMD was not found in ./steamcmd, the game server was not updated. Reinstall the server to get it back."
    else
        ./steamcmd/steamcmd.sh +force_install_dir /home/container +login anonymous \
            $( [[ "${WINDOWS_INSTALL}" == "1" ]] && printf %s '+@sSteamCmdForcePlatformType windows' ) \
            +app_update "${SRCDS_APPID}" $( [[ -z ${VALIDATE} ]] || printf %s "validate" ) +quit
    fi
else
    echo "Not updating game server as auto update was set to 0. Starting Server"
fi

## lsteamclient (Proton) charge le client Steam Linux depuis ~/.steam/sdk64 (et
## sdk32). Le script d'installation de l'egg l'y copie ; SteamCMD, lui, met à
## jour celui de ./steamcmd/linux64 : la copie est refaite quand elle diffère.
for a in 64 32; do
    src="./steamcmd/linux${a}/steamclient.so"
    dst="${HOME}/.steam/sdk${a}"
    if [ -f "${src}" ]; then
        mkdir -p "${dst}"
        cmp -s "${src}" "${dst}/steamclient.so" || cp --remove-destination "${src}" "${dst}/steamclient.so"
        [ -e "${dst}/steamservice.so" ] || ln -sfn steamclient.so "${dst}/steamservice.so"
    fi
done
mkdir -p "${STEAM_COMPAT_DATA_PATH}"

# Replace Startup Variables
MODIFIED_STARTUP=$(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo ":/home/container$ ${MODIFIED_STARTUP}"

## Arrêt : Docker envoie SIGINT (STOPSIGNAL) à tini, qui le relaie à tout le
## groupe de processus. Sans ce trap, `tail` et ce script mourraient aussitôt,
## tini (PID 1) sortirait, et le noyau tuerait le jeu pendant sa sauvegarde.
## Ignorés ici (et par tail et le script proton, qui en héritent), SIGINT et
## SIGTERM n'arrêtent que le jeu : Wine remet son propre gestionnaire de SIGINT
## et le transmet au jeu comme un Ctrl+C. Le conteneur s'arrête quand le jeu a
## fini (tail --pid). Un jeu bloqué fait attendre l'arrêt : Wings le tue
## (SIGKILL) au bout de 10 minutes, et le bouton « Kill » du panel le fait tout
## de suite. Posé APRÈS SteamCMD, qui reste interruptible.
## Le contrôle de l'arrêt noté vient juste après : un signal reçu avant le trap
## est vu ici, un signal reçu après est ignoré (voir README.md, « Arrêt du
## serveur »).
trap '' INT TERM
if [ -n "${stop}" ]; then
    echo "Stop requested during the startup update: the game server is not started."
    exit 0
fi

# Run the Server
eval ${MODIFIED_STARTUP}
