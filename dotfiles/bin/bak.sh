#!/bin/bash

assert_not_null() {
	arg_name="$1"
	arg_value="$2"
	if [[ ! -n "$arg_value" ]]; then
		echo "The value for option \"$arg_name\" must not be null." >&2
	fi
}

assert_file_exists() {
	file="$1"
	if [[ ! -e "$file" ]]; then
		echo "The file/directory \"$file\" does not exist." >&2
	fi
}

suffix=".bak"
mode="backup"
declare -a files

while [[ -n "$1" ]]; do
	case "$1" in
		-s | --suffix)
			shift
			assert_not_null "--suffix" "$1"
			suffix="$1"
			;;
		-u | --unbackup)
			mode="unbackup"
			;;
		*)
			assert_file_exists "$1"
			files+=("$1")
			;;
	esac
	shift
done

if [[ "$mode" == "backup" ]]; then
	for file in "${files[@]}"; do
		echo "$file" | grep ".*$suffix$" &> /dev/null
		[[ $? == "1" ]] && mv "$file" "${file}${suffix}"
	done
else
	for file in "${files[@]}"; do
		mv "$file" "${file%${suffix}}"
	done
fi
