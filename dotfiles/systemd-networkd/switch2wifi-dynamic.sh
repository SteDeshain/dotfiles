#!/bin/bash

sudo rm /etc/systemd/network/10-*.net{work,dev}

source ./define-device.sh

./create-wifi-dynamic.sh

sudo ip link set ${WIFI} up
sudo ip link set ${ETHERNET} down
sudo ip link set ${BOND} down
sudo ./restart-network.sh
