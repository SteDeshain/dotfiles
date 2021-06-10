#!/bin/bash

cat > 10-${BOND}.netdev << EOF
[NetDev]
Name=${BOND}
Kind=bond

[Bond]
Mode=active-backup
FailOverMACPolicy=active
PrimaryReselectPolicy=always
MIIMonitorSec=1s
EOF

cat > 10-${BOND}.network << EOF
[Match]
Name=${BOND}

[Network]
Address=192.168.0.3/24
Gateway=192.168.0.1
DNS=8.8.8.8
DNS=8.8.4.4
EOF

cat > 10-${WIFI}-${BOND}.network << EOF
[Match]
Name=${WIFI}

[Network]
Bond=${BOND}
EOF

cat > 10-${ETHERNET}-${BOND}.network << EOF
[Match]
Name=${ETHERNET}

[Network]
Bond=${BOND}
PrimarySlave=true
EOF
