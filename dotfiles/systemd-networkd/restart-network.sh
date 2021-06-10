#!/bin/bash

sudo systemctl reenable systemd-networkd
sudo systemctl reenable systemd-resolved
sudo systemctl restart systemd-networkd
sudo systemctl restart systemd-resolved

