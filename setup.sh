#!/bin/bash

# Setup script for lancache (https://www.lancache.net).
# This script is tested and meant to work on a bare-bones Ubuntu 20.04 install.

# Configure this
docker_user="refjugeeks"
lancache_root="/lancache"
lancache_ip="192.168.178.240"

# Abort script on error
set -e

# Fancy colors for better readability of output
reset_colors="\033[0m"
yellow="\033[0;33m"
green="\033[0;32m"

echo -e "${yellow}Installing any outstanding OS updates.${reset_colors}"
apt update && \
    apt -y dist-upgrade

echo -e "${yellow}Installing some basic software and prerequisites for lancache-autofill.${reset_colors}"
apt -y install \
    zip \
    unzip \
    htop \
    mc \
    git \
    wondershaper \
    lib32gcc1 \
    lib32stdc++6 \
    lib32tinfo6 \
    lib32ncurses6 \
    php7.4-cli \
    php7.4-mbstring \
    php7.4-sqlite3 \
    php7.4-bcmath \
    composer \
    expect

echo -e "${yellow}Ensuring systemd-resolved does not block port 53.${reset_colors}"
systemctl stop systemd-resolved
rm /etc/resolv.conf
cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF
sed -i -E -e 's/#?DNSStubListener=yes/DNSStubListener=no/' \
    /etc/systemd/resolved.conf
systemctl start systemd-resolved

echo -e "${yellow}Installing docker runtime.${reset_colors}"
apt -y install \
    docker.io \
    docker-compose

echo -e "${yellow}Giving user ${green}${docker_user}${yellow} the rights to interact with docker.${reset_colors}"
usermod -aG docker ${docker_user}

echo -e "${yellow}Starting docker daemon.${reset_colors}"
systemctl enable --now docker

echo -e "${yellow}Creating lancache data directories.${reset_colors}"
mkdir -p ${lancache_root}/{cache,logs,autofill}

if [[ ! -d ${lancache_root}/autofill/.git ]]; then
    echo -e "${yellow}Cloning lancache-autofill to ${green}${lancache_root}/autofill${yellow}.${reset_colors}"
    git clone https://github.com/zeropingheroes/lancache-autofill.git ${lancache_root}/autofill
else
    echo -e "${yellow}lancache-autofill repo already cloned to ${green}${lancache_root}/autofill${yellow}, skipping.${reset_colors}"
fi

echo -e "${yellow}Starting lancache docker containers and ensuring they restart on boot.${reset_colors}"
docker run --name lancache-dns \
    --restart always \
    --detach \
    -p 53:53/udp \
    -e USE_GENERIC_CACHE=true \
    -e LANCACHE_IP=${lancache_ip} \
    lancachenet/lancache-dns:latest

docker run --name lancache \
    --restart always \
    --detach \
    -v ${lancache_root}/cache:/data/cache \
    -v ${lancache_root}/logs:/data/logs \
    -e CACHE_MEM_SIZE=2048m \
    -e CACHE_DISK_SIZE=7340032m \
    -e CACHE_SLICE_SIZE=2m \
    -p 80:80 \
    lancachenet/monolithic:latest

docker run --name lancache-sniproxy \
    --restart always \
    --detach \
    -p 443:443 \
    lancachenet/sniproxy:latest

echo -e "${yellow}lancache has been started. Please configure ${green}${lancache_ip}${yellow} as DNS server.${reset_colors}"
echo -e "${yellow}For lancache-autofill, please follow the readme: ${green}https://github.com/zeropingheroes/lancache-autofill/blob/master/README.md${reset_colors}"
