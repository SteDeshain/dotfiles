#!/bin/bash

# 在这个文件中定义网络设备的名称
# 如使用手机通过数据线链接至电脑分享网络的话，就可以在链接好之后，通过 "ip link" 就可以看到新网卡的名称，在这里把 ETHERNET 的值换成新网卡的名字，然后 ./switch2wired-dynamic.sh 即可实现使用手机共享的网络

export WIFI="wlan0"
export ETHERNET="enp7s0"
export BOND="bond0"
