#!/bin/bash
# borrow some code from https://github.com/lahwaacz/Scripts/blob/master/toggle-touchpad.sh

device="$(xinput --list --name-only | grep -P -i '(touchpad|synaptics)')"

if [[ "$(xinput --list-props "$device" | grep -P -o ".*Device Enabled.*\K.(?=$)")" == "1" ]]; then
	xinput disable "$device"
else
	xinput enable "$device"
fi
