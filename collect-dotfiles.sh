#!/bin/bash

wd=$(pwd)
dotfiles_dir="$wd/dotfiles"
repobak_dir="$wd/repo-backups"
locbak_dir="$wd/local-backups"

if [[ ! -f "$wd/list.txt" ]]; then
	echo "The file \"list.txt\" does not exist." >&2
	exit 1
fi

[[ -d "$dotfiles_dir" ]] || mkdir "$dotfiles_dir"
[[ -d "$repobak_dir" ]] || mkdir "$repobak_dir"
[[ -d "$locbak_dir" ]] || mkdir "$locbak_dir"

collect() {
	local cur_wd=$(pwd)

	cd "$dotfiles_dir"
	if [[ $(echo *) != '*' ]]; then
		# it's not an empty dir, backup all files
		# use relative path here
		tar czf "$repobak_dir/$(date +%s-%Y%m%d-%H.%M.%S)-$RANDOM.tar.gz" * &> /dev/null
		rm -r *
	fi

	cd "$cur_wd"

	cat "$wd/list.txt" | (while read line; do
		# 忽略注释行
		[[ "$line" =~ ^\#.* ]] && continue

		local items=($(echo $line))
		if [[ "${items[0]}" =~ .*/$ ]]; then
			# it's a directory
			local repo_dir="$dotfiles_dir/${items[0]%/}"
			mkdir "$repo_dir"
			unset 'items[0]'
			cp "${items[@]}" "$repo_dir"
		else
			# it's a single file
			cp "${items[1]}" "$dotfiles_dir/${items[0]}"
		fi
	done)
}

distribute() {
	local local_bak_file="$locbak_dir/$(date +%s-%Y%m%d-%H.%M.%S)-$RANDOM.tar"

	cat "$wd/list.txt" | (while read line; do
		# ignore commentary line
		[[ "$line" =~ ^#.* ]] && continue

		local items=($(echo $line))
		if [[ "${items[0]}" =~ .*/$ ]]; then
			# it's a directory
			local local_dir="$(dirname ${items[1]})"
			if [[ ! -d "$local_dir" ]]; then
				echo "The directory \"$local_dir\" does not exist." >&2
				continue
			fi
			repo_files=($dotfiles_dir/${items[0]}*)
			for i in "${repo_files[@]}"; do
				# backup local files
				# use absolute path for every appended file
				[[ -f "$local_bak_file" ]] \
					&& tar rf "$local_bak_file" "$local_dir/$(basename $i)" &> /dev/null \
					|| tar cf "$local_bak_file" "$local_dir/$(basename $i)" &> /dev/null
				# and then copy new files
				cp "$i" "$local_dir"
				#echo "copying \"$i\" to \"$local_dir\""
			done
		else
			# it's a single file
			[[ -f "$local_bak_file" ]] \
				&& tar rf "$local_bak_file" "${items[1]}" &> /dev/null \
				|| tar cf "$local_bak_file" "${items[1]}" &> /dev/null
			cp "$dotfiles_dir/${items[0]}" "${items[1]}"
			#echo "copying \"$dotfiles_dir/${items[0]}\" to \"${items[1]}\""
		fi
	done)

	[[ -f $local_bak_file ]] && gzip $local_bak_file
}

usage() {
	echo "usage: $0 [-d | -c]"
}

while [[ -n "$1" ]]; do
	case "$1" in
		-d | --distribute)
			distribute
			exit 0
			;;
		-c | --collect)
			collect
			exit 0
			;;
		# ability to restore local-backups and repo-backups
		*)
			echo "Wrong options!" >&2
			usage >&2
			exit 1
			;;
	esac
	shift
done

collect
