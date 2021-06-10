#!/bin/bash

sudo rm /etc/systemd/network/10-*.net{work,dev}

source ./define-device.sh

./create-bond.sh

sudo ip link set ${WIFI} up
sudo ip link set ${ETHERNET} up
sudo ip link set ${BOND} up
sudo ./restart-network.sh
