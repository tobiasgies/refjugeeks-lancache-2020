#!/bin/bash

# Setup script for lancache (https://www.lancache.net).
# This script is tested and meant to work on a bare-bones Debian 12 (Bookworm) install.

# Configure this
docker_user="refjugeeks"
lancache_root="/lancache"
lancache_ip="192.168.10.5"
upstream_dns="1.1.1.1;9.9.9.9"

# Abort script on error or undefined variable
set -euo pipefail

# Fancy colors for better readability of output
reset_colors="\e[0m"
yellow="\e[0;33m"
green="\e[0;32m"
red="\e[0;31m"

if [ $EUID != "0" ]; then
    echo -e "${red}ERROR: must be root to execute this script.${reset_colors}">&2
    exit 1
fi

echo -e "${yellow}Installing any outstanding OS updates.${reset_colors}"
apt update && \
    apt -y dist-upgrade

echo -e "${yellow}Installing some basic software and prerequisites for lancache-autofill.${reset_colors}"
apt -y install \
    zip \
    unzip \
    htop \
    iotop \
    iftop \
    mc \
    git \
    screen \
    net-tools \
    ethtool \
    ifenslave \
    wondershaper \
    smartmontools \
    lib32gcc-12-dev \
    lib32stdc++-12-dev \
    lib32tinfo6 \
    lib32ncurses6 \
    php8.2-cli \
    php8.2-mbstring \
    php8.2-sqlite3 \
    php8.2-bcmath \
    php8.2-xml \
    composer \
    expect \
    curl \
    ca-certificates \
    apt-transport-https

echo -e "${yellow}Ensuring systemd-resolved does not block port 53.${reset_colors}"
if systemctl is-active --quiet systemd-resolved.service; then
    systemctl stop systemd-resolved
    sed -i -E -e 's/#?DNSStubListener=yes/DNSStubListener=no/' \
        /etc/systemd/resolved.conf
    systemctl start systemd-resolved
fi   
rm /etc/resolv.conf
cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
nameserver 1.1.1.1
nameserver 9.9.9.9
nameserver 192.168.10.1
EOF
echo -e "${yellow}Installing docker runtime.${reset_colors}"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update
apt -y install \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

echo -e "${yellow}Giving user ${green}${docker_user}${yellow} the rights to interact with docker.${reset_colors}"
usermod -aG docker ${docker_user}

echo -e "${yellow}Adding user ${green}${docker_user}${yellow} to sudoers file.${reset_colors}"
echo "${docker_user} ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/${docker_user}

echo -e "${yellow}Starting docker daemon.${reset_colors}"
systemctl enable --now docker

echo -e "${yellow}Creating lancache data directories.${reset_colors}"
mkdir -p ${lancache_root}/{cache,logs,prefill,steam-tmp}

echo -e "${yellow}Downloading lancache-prefill tools.${reset_colors}"
curl -L "https://github.com/tpill90/steam-lancache-prefill/releases/download/v2.7.0/SteamPrefill-2.7.0-linux-x64.zip" -o ${lancache_root}/prefill/SteamPrefill.zip
curl -L "https://github.com/tpill90/battlenet-lancache-prefill/releases/download/v2.0.0/BattleNetPrefill-2.0.0-linux-x64.zip" -o ${lancache_root}/prefill/BattleNetPrefill.zip
curl -L "https://github.com/tpill90/epic-lancache-prefill/releases/download/v2.1.0/EpicPrefill-2.1.0-linux-x64.zip" -o ${lancache_root}/prefill/EpicPrefill.zip

# Disable exit on error because unzip returns 1 on warning. :-(
set +e
unzip -j -o ${lancache_root}/prefill/SteamPrefill.zip -d ${lancache_root}/prefill
unzip -j -o ${lancache_root}/prefill/BattleNetPrefill.zip -d ${lancache_root}/prefill
unzip -j -o ${lancache_root}/prefill/EpicPrefill.zip -d ${lancache_root}/prefill
set -e

rm ${lancache_root}/prefill/{SteamPrefill,BattleNetPrefill,EpicPrefill}.zip
chmod +x ${lancache_root}/prefill/{SteamPrefill,BattleNetPrefill,EpicPrefill}

echo -e "${yellow}Starting lancache docker containers and ensuring they restart on boot.${reset_colors}"
docker pull lancachenet/lancache-dns:latest
docker run --name lancache-dns \
    --restart always \
    --detach \
    -p 53:53/udp \
    -e USE_GENERIC_CACHE=true \
    -e LANCACHE_IP=${lancache_ip} \
    -e UPSTREAM_DNS="${upstream_dns}" \
    lancachenet/lancache-dns:latest

docker pull lancachenet/monolithic:latest
docker run --name lancache \
    --restart always \
    --detach \
    -v ${lancache_root}/cache:/data/cache \
    -v ${lancache_root}/logs:/data/logs \
    -e CACHE_MEM_SIZE=2048m \
    -e CACHE_DISK_SIZE=8388608m \
    -e CACHE_SLICE_SIZE=2m \
    -e UPSTREAM_DNS="${upstream_dns}" \
    -p 80:80 \
    -p 443:443 \
    lancachenet/monolithic:latest

echo -e "${yellow}lancache has been started. Please configure ${green}${lancache_ip}${yellow} as DNS server.${reset_colors}"
echo -e "${yellow}For usage of the lancache prefill tools, please follow the readme files:${reset_colors}"
echo -e "${yellow} - ${green}https://github.com/tpill90/steam-lancache-prefill/blob/master/README.md${reset_colors}"
echo -e "${yellow} - ${green}https://github.com/tpill90/battlenet-lancache-prefill/blob/master/README.md${reset_colors}"
echo -e "${yellow} - ${green}https://github.com/tpill90/epic-lancache-prefill/blob/master/README.md${reset_colors}"
