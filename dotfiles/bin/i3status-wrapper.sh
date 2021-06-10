#!/bin/bash

#------------------------------------------------ utils ---------------------------------------------------#

#####################
# General functions #
#####################

update_status() {
	killall -USR1 i3status
}

#-------------------------------------------- status blocks -----------------------------------------------#

#############
# net-speed #
#############

# Auto detect interfaces
ifaces=$(ls /sys/class/net | grep -E '^(eno|enp|ens|enx|eth|wlan|wlp)')
#ifaces="wlan0 enp7s0"

last_time=0
last_rx=0
last_tx=0
rate=""

readable() {
  local bytes=$1
  local kib=$(( bytes >> 10 ))
  if [ $kib -lt 0 ]; then
    echo "? K"
  elif [ $kib -gt 1024 ]; then
    local mib_int=$(( kib >> 10 ))
    local mib_dec=$(( kib % 1024 * 976 / 10000 ))
    if [ "$mib_dec" -lt 10 ]; then
      mib_dec="0${mib_dec}"
    fi
    echo "${mib_int}.${mib_dec} M"
  else
    echo "${kib} K"
  fi
}

update_rate() {
  local time=$(date +%s)
  local rx=0 tx=0 tmp_rx tmp_tx

  for iface in $ifaces; do
    read tmp_rx < "/sys/class/net/${iface}/statistics/rx_bytes"
    read tmp_tx < "/sys/class/net/${iface}/statistics/tx_bytes"
    rx=$(( rx + tmp_rx ))
    tx=$(( tx + tmp_tx ))
  done

  local interval=$(( $time - $last_time ))
  if [ $interval -gt 0 ]; then
    rate="$(readable $(( (rx - last_rx) / interval )))↓ $(readable $(( (tx - last_tx) / interval )))↑"
  else
    rate=""
  fi

  last_time=$time
  last_rx=$rx
  last_tx=$tx
}

######################
# about dunst status #
######################

dunst_status="?"

update_dunst_status() {
	dunst_status=$([[ $(dunstctl is-paused) == "false" ]] && echo " " || echo " ")
}

toggle_dunst_status () {
	inputs=$1
	modifiers=$2

	if (( ${inputs["button"]} == 1 )); then
		dunstctl set-paused toggle
		update_status
	fi
}

##################
# operate volume #
##################

operate_volume () {
	inputs=$1
	modifiers=$2
	case ${inputs["button"]} in
		3)
			# toggle mute
			pactl set-sink-mute 0 toggle
			update_status
			;;
		4)
			# increase volume
			pactl set-sink-mute 0 false
			pactl set-sink-volume 0 +5%
			update_status
			;;
		5)
			# decrease volume
			pactl set-sink-mute 0 false
			pactl set-sink-volume 0 -5%
			update_status
			;;
		*)
			# Wrong input
			;;
	esac
}

#####################
# removable devices #
#####################

#------------------------------------------- core functions -----------------------------------------------#

#################
# handle output #
#################

(
i3status | (read line && echo "${line%\}},\"click_events\":true}" && # ignore header like '{ "version": 1 }'
	read line && echo "$line" &&	# ignore start '['
	read line && echo "$line" &&	# ignore first empty element '[]'
	while :; do
  		read line
	 	update_rate
  		update_dunst_status
  		# ${line#,\[} is equivalent to ${line#,[} where the back-slash \ is just an escape token
  		line_temp=${line#,[}
  		line_final=${line_temp%]}
  		echo ",[{\"name\":\"net-speed\",\"full_text\":\"${rate}\"},\
		  		${line_final},\
	      		{\"name\":\"dunst-status\",\"full_text\":\"${dunst_status}\"}\
		 	   ]" || exit 1
done)
) &

################
# handle input #
################

handle_mouse_inputs () {
	inputs=$1
	modifiers=$2
	case ${inputs["name"]} in
		"volume")
			operate_volume $inputs $modifiers
			;;
		"dunst-status")
			toggle_dunst_status $inputs $modifiers
			;;
		*)
			;;
	esac
}

cat\
| jq --stream --unbuffered --compact-output --null-input 'fromstream(1|truncate_stream(inputs))'\
| ( while :; do
		read line
		declare -A inputs=$(echo $line\
							| perl -pe 's/"modifiers":\[.+?\],?//g'\
							| sed --regexp-extended 's/"([^"]+)":/\["\1"\]=/g'\
							| tr '{},' '() ')
		#declare -A inputs=$(echo $line | sed --regexp-extended 's/"modifiers":[^,\}]+,?//g' | sed --regexp-extended 's/"([^"]+)":/\["\1"\]=/g' | tr '{},' '() ')
#		declare -a modifiers=$(echo $line | jq --compact-output 'getpath(["modifiers"])|@sh' | sed 's/^"/(/' | sed 's/"$/)/')
		declare -a modifiers=$(echo $line | pcre2grep --only-matching '"modifiers":\[.+?\]' | sed --regexp-extended 's/"modifiers":\[(.+)\]/(\1)/g' | tr ',' ' ')
		handle_mouse_inputs $inputs $modifiers
#		echo "${modifiers[@]}" > ~/outputs.txt
	done )
