#!/bin/bash

cat > 10-${WIFI}-dynamic.network << EOF
[Match]
Name=${WIFI}

[Network]
DHCP=yes
EOF
