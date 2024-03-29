#!/bin/bash

# Abort script on error or unset variable
set -euo pipefail

# Fancy colors for better readability of output
reset_colors="\033[0m"
yellow="\033[0;33m"
green="\033[0;32m"

echo -e "${yellow}Stopping lancache docker containers.${reset_colors}"
docker stop lancache lancache-dns

echo -e "${yellow}Removing lancache docker containers.${reset_colors}"
docker rm lancache lancache-dns

echo -e "${yellow}Done. You can re-create the lancache containers by re-running ${green}setup.sh${yellow}.${reset_colors}"
