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

pull_and_stop_container() {
    image="${1:?"${red}container image parameter not set${reset_colors}"}"
    container="${2:?"${red}container name parameter not set${reset_colors}"}"
    echo -e "${yellow}Pulling latest ${green}${image}${yellow} image.${reset_colors}"
    docker pull "${image}:latest"
    if [ -n "$(docker ps -q -a -f "name=^${container}$")" ]; then
        echo -e "${green}${container}${yellow} container exists, stopping and removing.${reset_colors}"
        docker stop "${container}"
        docker rm -f "${container}" 
    fi
}

echo -e "${yellow}Installing any outstanding OS updates.${reset_colors}"
apt update && \
    apt -y dist-upgrade

echo -e "${yellow}Ensuring systemd-resolved does not block port 53.${reset_colors}"
if systemctl is-active --quiet systemd-resolved.service; then
    systemctl stop systemd-resolved
    sed -i -E -e 's/#?\s*DNSStubListener=yes/DNSStubListener=no/' \
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

echo -e "${yellow}Installing some basic software and prerequisites for lancache-autofill.${reset_colors}"
apt -y install \
    sudo \
    zip \
    unzip \
    htop \
    iotop \
    iftop \
    mc \
    git \
    screen \
    net-tools \
    smartmontools \
    curl \
    jq \
    ca-certificates \
    apt-transport-https

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

echo -e "${yellow}Installing zabbix agent.${reset_colors}"
wget https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_latest+debian12_all.deb
dpkg -i zabbix-release_latest+debian12_all.deb
apt update
rm zabbix-release_latest+debian12_all.deb
apt -y install zabbix-agent2

echo -e "${yellow}Adding zabbix agent config file.${reset_colors}"
cat > /etc/zabbix/zabbix_agent2.d/99-refjugeeks.conf <<EOF
LogFileSize=10
Server=127.0.0.1,192.168.10.10
ListenPort=10050
StatusPort=10049
ServerActive=
Hostname=
HostnameItem=system.hostname[fqdn]
EOF

echo -e "${yellow}Starting zabbix agent.${reset_colors}"
systemctl enable --now zabbix-agent2

echo -e "${yellow}Creating lancache data directories.${reset_colors}"
mkdir -p ${lancache_root}/{cache,logs,prefill/{epic,steam,bnet},steam-tmp}

echo -e "${yellow}Downloading lancache-prefill tools.${reset_colors}"
curl -L "https://github.com/tpill90/steam-lancache-prefill/releases/download/v2.8.0/SteamPrefill-2.8.0-linux-x64.zip" -o ${lancache_root}/prefill/SteamPrefill.zip
curl -L "https://github.com/tpill90/battlenet-lancache-prefill/releases/download/v2.0.0/BattleNetPrefill-2.0.0-linux-x64.zip" -o ${lancache_root}/prefill/BattleNetPrefill.zip
curl -L "https://github.com/tpill90/epic-lancache-prefill/releases/download/v2.1.0/EpicPrefill-2.1.0-linux-x64.zip" -o ${lancache_root}/prefill/EpicPrefill.zip

# Disable exit on error because unzip returns 1 on warning. :-(
set +e
unzip -j -o ${lancache_root}/prefill/SteamPrefill.zip -d ${lancache_root}/prefill/steam
unzip -j -o ${lancache_root}/prefill/BattleNetPrefill.zip -d ${lancache_root}/prefill/bnet
unzip -j -o ${lancache_root}/prefill/EpicPrefill.zip -d ${lancache_root}/prefill/epic
set -e

rm ${lancache_root}/prefill/{SteamPrefill,BattleNetPrefill,EpicPrefill}.zip
chmod +x ${lancache_root}/prefill/{steam/{SteamPrefill,update.sh},bnet/{BattleNetPrefill,update.sh},epic/{EpicPrefill,update.sh}}
chown -R ${docker_user}:${docker_user} ${lancache_root}/prefill

echo -e "${yellow}Starting lancache docker containers and ensuring they restart on boot.${reset_colors}"
pull_and_stop_container "lancachenet/lancache-dns" "lancache-dns"
echo -e "${yellow}Starting latest ${green}lancache-dns${yellow} container.${reset_colors}"
docker run --name lancache-dns \
    --restart unless-stopped \
    --detach \
    -p 53:53/udp \
    -e USE_GENERIC_CACHE=true \
    -e LANCACHE_IP=${lancache_ip} \
    -e UPSTREAM_DNS="${upstream_dns}" \
    lancachenet/lancache-dns:latest

pull_and_stop_container "lancachenet/monolithic" "lancache"
echo -e "${yellow}Starting latest ${green}lancache${yellow} container.${reset_colors}"
docker run --name lancache \
    --restart unless-stopped \
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

echo -e "${yellow}Removing old and dangling docker images and volumes.${reset_colors}"
docker system prune --all --volumes --force

echo -e "${yellow}lancache has been started. Please configure ${green}${lancache_ip}${yellow} as DNS server.${reset_colors}"
echo -e "${yellow}For usage of the lancache prefill tools, please follow the readme files:${reset_colors}"
echo -e "${yellow} - ${green}https://github.com/tpill90/steam-lancache-prefill/blob/master/README.md${reset_colors}"
echo -e "${yellow} - ${green}https://github.com/tpill90/battlenet-lancache-prefill/blob/master/README.md${reset_colors}"
echo -e "${yellow} - ${green}https://github.com/tpill90/epic-lancache-prefill/blob/master/README.md${reset_colors}"
