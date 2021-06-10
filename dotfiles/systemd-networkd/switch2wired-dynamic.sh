#!/bin/bash

sudo rm /etc/systemd/network/10-*.net{work,dev}

source ./define-device.sh

if [[ $1 ]]; then
	export ETHERNET="$1"
fi

./create-wired-dynamic.sh

sudo ip link set ${WIFI} down
sudo ip link set ${ETHERNET} up
sudo ip link set ${BOND} down
sudo ./restart-network.sh
