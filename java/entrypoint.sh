#!/bin/bash

#
# Copyright (c) 2021 Matthew Penner
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

# OuiHeberg : repris de pelican-eggs/yolks@3680e41 (java/entrypoint.sh, licence MIT).
# Seul ajout : le bloc CVE-2026-114938 ci-dessous, actif seulement dans les images
# qui posent OH_JAVA4SHELL_ATTENUATION.

# Default the TZ environment variable to UTC.
TZ=${TZ:-UTC}
export TZ

# Set environment variable that holds the Internal Docker IP
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Switch to the container's working directory
cd /home/container || exit 1

# OuiHeberg, CVE-2026-114938 (Java4Shell) : le décodage Base64 AVX-512 de HotSpot (et celui
# du compilateur Graal à partir de Graal 25.1) écrit hors limites (Java 17.0.6 et plus,
# processeurs AVX-512 VBMI). Une image dont le JDK n'a pas de version corrigée pose dans
# OH_JAVA4SHELL_ATTENUATION les options qui coupent ce code. Elles sont ajoutées à la fin de
# JDK_JAVA_OPTIONS, que le lanceur java des JDK 9 et plus lit à chaque démarrage : les
# options déjà posées par l'egg sont gardées. À retirer d'une image dès que son JDK est corrigé.
if [ -n "${OH_JAVA4SHELL_ATTENUATION:-}" ]; then
    export JDK_JAVA_OPTIONS="${JDK_JAVA_OPTIONS:+${JDK_JAVA_OPTIONS} }${OH_JAVA4SHELL_ATTENUATION}"
fi

# Print Java version
printf "\033[1m\033[33mcontainer~ \033[0mjava -version\n"
java -version

# Convert all of the "{{VARIABLE}}" parts of the command into the expected shell
# variable format of "${VARIABLE}" before evaluating the string and automatically
# replacing the values.
PARSED=$(echo "$STARTUP" | sed -e 's/{{/${/g' -e 's/}}/}/g')

# Display the command we're running in the output, and then execute it with eval
printf "\033[1m\033[33mcontainer~ \033[0m"
echo "$PARSED"
# shellcheck disable=SC2086
eval "$PARSED"
