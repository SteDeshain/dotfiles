#!/bin/bash

cat > 10-${ETHERNET}-dynamic.network << EOF
[Match]
Name=${ETHERNET}

[Network]
DHCP=yes
EOF
