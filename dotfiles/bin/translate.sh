#!/bin/bash

############
# 一些变量 #
############

# 翻译模式分为参数模式和剪贴板模式：
# 参数模式会翻译参数中的每一个 word (shell 术语 word), 将每一个 word 作为翻译的单位
# 剪贴板模式中，由于输入的特殊性：因为是读取 xclip 程序的输出作为翻译的输入，所以输入只会有一个 word, 此时就比较尴尬了
# 因为用户可能想要分别翻译剪贴板中的每一个单词，也有可能是将剪贴板中的内容作为一个整体(句子或短语)来翻译，我们的程序不知道用户到底想要哪种翻译方式
# 所以就有了下面的三个选项
# (在所有的翻译模式中，对于每一个翻译单位，先在本地辞典中翻译，如果没有找到，就在网络上翻译)

# 用于剪贴板模式。强制将输入看作一个个单词，分别翻译每一个单词(忽略 max_words)
force_words="false"

# 用于剪贴板模式。式强制将输入看作一整个句子，开启该选项会自动使用网络翻译(忽略 max_words)
force_sentence="false"

# 用于剪贴板模式。不使用上述强制选项(force_words 和 force_sentence)时，将输入认为是句子的最小单词数:
# 1. 如果输入的单词数小于等于它,那么就翻译一个个单词
# 2. 如果输入单词数大于它, 就将所有的内容看作一个整体进行翻译
max_words=3

# 强制所有的翻译使用网络翻译
force_online="false"

# 网络翻译的可允许延迟，单位为秒
time_out=10

# 选择要查询的辞典
declare -a dictionaries

# 选择结果输出至哪里，可选 "standardout"(默认), "-" 和 "notification"
# 为了后续可能的错误信息输出至正确的地方，该选项一定要放在第一个选项的位置
output="standardout"

# 该选项的用法是 --definition-formatter "dictionary" "formatter-command"
# 其中，"formatted-command" 表示翻译结果中 definition 字段的格式化程序，它的值必须是一段合法的 shell 程序，或者是指向一个包含有合法 shell 程序的文件的路径。该 shell 程序的标准输入是一个字符串，标准输出还是一个字符串
# 用户利用选项传递进命令来执行，在 bash 编程中是不可行的，因为无法处理好 shell-word 的分辨问题，无论是直接用命令作为选项值，还是使用一个文件
# TODO 以后使用别的脚本语言重写该脚本时再考虑这个问题吧，可以预见，对于如何解决这个问题别的脚本语言会非常的简单
declare -A definition_formatters

# 该选项的允许值和上面 definition_formatters 选项中 formatter-command 的值一样：可以是一段 shell 程序，也可以是一个文件的路径名。
# 用来生成网络翻译的 url 链接，由于各个网络翻译 API 接口及其用法都不相同，所以这里还是留给用户自己去指定。
# 程序的输入是要翻译的内容(中间可能会有空格)，输出要是一个合法的 url.
# TODO 以后使用别的语言重写时再考虑这个功能
# 同理，这里也不现实，所以我使用更死板的只能使用百度翻译 api 的方法，传递 app id 和密钥来生成 url
url_generator=""
baidu_appid=""
baidu_key=""

# 需要翻译的内容
declare -a words

# 返回状态码
EXIT_BAD_OPTION=2
EXIT_UNKNOWN=1

# TODO 检查用户的环境是否安装了一个通知服务器，否则发送通知的命令会永远被挂起

############
# 命令用法 #
############

usage() {
	echo "Translate: a simple wrapper for sdcv. It can read input from either the clipboard or the arguments, and send the results to either the notification serve or the standard out."
	echo "Usage: translate [OPTIONS] [WORD...]"
	# TODO more details
}

############
# 输出函数 #
############

# 统一的输出函数，根据脚本的 --output 选项，选择是输出至标准输出，还是输出至通知服务器。所以建议 --output 选项指定在第一个位置
# -e | --error 选项，作为错误信息输出
# -r | --replace 选项，只有在使用 dunstify 输出时才有意义，表示要替换的通知窗口的 id, 必须是一个正整数
# -t | --timeout 和 dunstify 的一样(单位是毫秒), 0 表示一直显示不消失
output() {
	local error="false"
	local replace_id=""
	local timeout=""
	# 这里使用数组来保存要输出的信息，是为了最大程度保留想要输出的内容的格式
	# 这样的话，数组中的每一个元素就会是一个 shell-word(区别于英文单词 word, 这里我用一个自造的词来表示 shell 术语中的 word), 所有的 shell-word 会原封不动地传递给真正进行输出的命令
	declare -a local info

	while [[ -n "$1" ]]; do
		case "$1" in
			-e | --error)
				error="true"
				;;
			-r | --replace)
				shift
				replace_id="$1"
				;;
			-t | --timeout)
				shift
				timeout="$1"
				;;
			*)
				info+=("$1")
				;;
		esac
		shift
	done

	if [[ "$output" == "standardout" || "$output" == "-" ]]; then
		if [[ "$error" == "true" ]]; then
			echo "${info[@]}" >&2
		else
			echo "${info[@]}"
		fi
	else
		# 查看用户是否安装了 dunstify
		type dunstify &> /dev/null
		if [[ $? == "0" ]]; then
			# 用户安装并且可以执行 dunstify, 并且可以使用通知 replace_id 来替换已有通知
			# 向标准输出打印通知窗口的 id
			local dunstify_options=" --printid"
			(( replace_id > 0 )) && dunstify_options+=" --replace $replace_id"
			[[ $timeout ]] && dunstify_options+=" --timeout $timeout"
			[[ "$error" == "true" ]] && dunstify_options+=" --urgency critical"
			# 这里 $dunstify_options 两边一定不能加双引号，因为加上引号之后，所有的选项就会被认为是一个 word, 选项就不会被正常读取
			dunstify $dunstify_options "${info[@]}"
		else
			# 用户的环境无法执行 dunstify, 所以使用 notify-send 替代
			# TODO 检查用户是否连 notify-send 都没有安装
			local notify_send_options=""
			(( timeout > 0 )) && notify_send_options+=" --expire-time $timeout"
			[[ "$error" == "true" ]] && notify_send_options+=" --urgency critical"
			notify-send $notify_send_options "${info[@]}"
			# 如果没有 dunstify, 则不向标准输出打印任何东西
		fi
	fi
}

# Print error information and usage information and exit
error() {
	local error_code=$EXIT_UNKNOWN
	local usage_info="false"
	declare -a local error_info

	while [[ -n "$1" ]]; do
		case "$1" in
			-e | --error-code)
				shift
				error_code="$1"
				;;
			-u | --usage)
				usage_info="true"
				;;
			*)
				error_info+=("$1")
				;;
		esac
		shift
	done

	# 这里在用法信息前面加上一个换行符，是为了防止把真正的错误信息和用法信息连在一起显示
	[[ "$usage_info" == "true" ]] && error_info+=("
$(usage)")
	output --error "${error_info[@]}"
	exit "$error_code"
}

# Print warning information without exiting
warn() {
	output --error "$@"
}

########################
# 判断选项值的断言函数 #
########################

assert_not_null() {
	local arg_name="$1"
	local arg_value="$2"
	if [[ ! "$arg_value" ]]; then
		error "The value for option \"$arg_name\" cannot be null." --error-code "$EXIT_BAD_OPTION" --usage
	fi
}

assert_positive_integer() {
	local arg_name="$1"
	local arg_value="$2"
	if [[ ! "$arg_value" =~ ^[0-9]+$ ]]; then
		error "The value for option \"$arg_name\" must ba a positive integer." --error-code "$EXIT_BAD_OPTION" --usage
	fi
}

# usage:
# assert_among_values "--argument" "$1" "value_a" "value_b" "vlaue_c"
assert_among_values() {
	local arg_name="$1"
	shift
	local arg_value="$1"
	shift
	
	local valid_values=""
	while [[ -n "$1" ]]; do
		if [[ "$1" == "$arg_value" ]]; then
			return 0
		fi
		valid_values+=" \"$1\""
		shift
	done
	# 去除开头多余的空格
	valid_values=${valid_values# }

	error "The value for option \"$arg_name\" must be one of $valid_values" --error-code "$EXIT_BAD_OPTION" --usage
}

# 检查输入数据是否是单纯的英语
assert_valid_english_word() {
	is_valid_english_word "$1"
	if [[ "$?" != "0" ]]; then
		error "The word \"$1\" is not a valid English word." --error-code "$EXIT_BAD_OPTION" --usage
	fi
}

is_valid_english_word() {
	local word="$1"

	# 首先去掉单词两边的空格
	# 命令替换两边无需加上一对双引号，shell 会自动确保一个命令替换的结果是一个 shell-word
	word=$(echo "$word" | trim)

	# 正则表达式检测
	# 叹号 ! 反引号 ` 双引号 " 都需要转意
	echo $word | grep "^[-a-zA-Z0-9_,.?\!\`\"'/ ]\+$" &> /dev/null
	# 单词长度为 0 也不是合法单词
	if [[ -z $word || $? != "0" ]]; then
		return 1
	else
		return 0
	fi

}

assert_valid_dictionary() {
	local dict_name="$1"
	sdcv --list-dicts | tail --lines +2 | sed 's/\s*[0-9]*$//g' | grep "^$dict_name\$" &> /dev/null
	if [[ "$?" != "0" ]]; then
		error "\"$dict_name\" is not a valid dictionary name. Use \"sdcv --list-dicts\" to show all valid dictionaries." --error-code "$EXIT_BAD_OPTION" --usage
	fi
}

############
# 工具函数 #
############

# 用于去除字符串两端连续空字符的过滤器
trim() {
	while read line; do
		echo "$line" | sed 's/^\s*//' | sed 's/\s*$//'
	done
}

read_from_file() {
	local file="$1"
	# 如果参数是一个合法的文件名，那么就从该文件中读取数据，作为要输入的数据
	if [[ -f "$file" ]]; then
		cat "$file"
	# 如果参数不是一个合法的文件名，那么就当作它就是要输入的数据本身
	else
		echo "$file"
	fi
}

# code borrowed from https://blog.kos.org.cn/post/66.html
urlencode() {
	local LANG=C
	local length="${#1}"
	i=0
	while :; do
		if [[ $length -gt $i ]]; then
			local c="${1:$i:1}"
			case $c in
				[a-zA-Z0-9.~_-])
					printf "$c"
					;;
				*)
					printf '%%%02X' "'$c"
					;; 
			esac
		else
			break
		fi
		let i++
	done
}


# 不同的辞典的结果，definition 字段的格式都是不同的，所以需要一个独立的函数来处理它，来应付不同的格式
#definition_formatter() {
	# TODO 根据用户选择的辞典，来处理不同的格式
	#input=$1
	#middle_res=${input#\"\\n}
	#echo ${middle_res%\"}
#}


generate_formatter() {
	local formatter_dictionary="$1"
	local formatter_command="$2"
	# FIXME
}

######################
# 程序真正开始的地方 #
######################

# 读取选项
# TODO 使用配置文件，实现和选项相同的功能
while [[ -n "$1" ]]; do
	case "$1" in
		-W | --force-online)
			force_online="true"
			;;
		-w | --force-words)
			force_words="true"
			;;
		-s | --force-sentence)
			force_sentence="true"
			;;
		-m | --max-words)
			shift
			assert_not_null "--max-words" "$1"
			assert_positive_integer "--max-words" "$1"
			max_words="$1"
			;;
		--baidu-appid)
			shift
			assert_not_null "--baidu-appid" "$1"
			baidu_appid="$1"
			;;
		--baidu-key)
			shift
			assert_not_null "--baidu-key" "$1"
			baidu_key="$1"
			;;
		-d | --dictionary)
			shift
			assert_not_null "--dictionary" "$1"
			assert_valid_dictionary "$1"
			dictionaries+=("$1")
			;;
		-f | --definition-formatter)
			shift
			formatter_dictionary="$1"
			assert_not_null "--definitoin-formatter" "$formatter_dictionary"
			shift
			assert_not_null "--definitoin-formatter" "$1"
			# 这里不再需要将命令替换使用双引号引用起来，shell 会自动将命令替换的所有结果(哪怕包含空格)作为一个整体都赋值给前面的变量
			# 因为命令替换的结果是一个 word (shell 术语 word)
			formatter_command=$(read_from_file "$1")
			generate_formatter "$formatter_dictionary" "$formatter_command"
			;;
		-u | --url-generator)
			shift
			assert_not_null "--url-generator" "$1"
			url_generator=$(read_from_file "$1")
			;;
		-o | --output)
			shift
			assert_among_values "--output" "$1" "standardout" "notification" "-"
			output="$1"
			;;
		-? | -h | --help)
			output $(usage)
			exit 0
			;;
		# 把其他所有的参数，都当作要翻译的单位
		*)
			# 命令替换两边无需加上一对双引号，shell 会自动确保一个命令替换的结果是一个 shell-word
			words+=($(echo "$1" | trim))
			;;
	esac
	shift
done

# 如果没有参数，则翻译剪贴板中的内容
if [[ ${#words[@]} == "0" ]]; then
	xclip_content=$(xclip -out -selection "clipboard")
	if [[ "$force_words" == "true" ]]; then
		# 利用 shell 的特性，自动使用空格为每个元素进行分隔
		words=($xclip_content)
	elif [[ "$force_sentence" == "true" ]]; then
		words=("$xclip_content")
	else
		words=($xclip_content)
		if (( ${#words[@]} > $max_words )); then
			words=("$xclip_content")
		fi
	fi
fi

if [[ ${#words[@]} == "0" ]]; then
	exit 0
fi

# 然后检查 words 中所有的单词的合法性
declare -a tmp_words
for word in "${words[@]}"; do
	is_valid_english_word "$word"
	[[ "$?" == "0" ]] && tmp_words+=("$word") || warn "\"$word\" is not a English word."
done
unset words
words=("${tmp_words[@]}")

# 先构建 sdcv 命令的通用选项
declare -a sdcv_options
# 这里用数组而不是字符串，是为了清晰地分开每一个 shell-word, 因为辞典名中间可能有空格，这时用字符串的话，辞典名就不能被正确解析了
#sdcv_options=""
# 只使用精确搜索
sdcv_options+=("--exact-search")
sdcv_options+=("--non-interactive")
sdcv_options+=("--utf8-input")
sdcv_options+=("--utf8-output")
# sdcv 的 --json 选项不能用，有 bug，只能用简写的 -j 选项
sdcv_options+=("-j")
# 根据 dictionaries 的值，筛选结果
# 如果没有指定该选项，则表示查找所有的辞典
# (不建议先搜索所有的辞典，然后在得到的结果中，使用 jq 来查找目标辞典们的结果，因为 jq 相对来说很慢)
for dict in "${dictionaries[@]}"; do
	sdcv_options+=("--use-dict")
	sdcv_options+=("$dict")
done

declare -a bg_processes
# 开始翻译
for word in "${words[@]}"; do
	json_result=""
	sdcv_return=0
	if [[ $force_online == "false" ]]; then
		json_result=$(sdcv "${sdcv_options[@]}" "$word")
		# 通过 sdcv 的返回值来判断单词是否在辞典中，可惜 sdcv 的手册没有说明它在哪种情况下会返回什么值
		sdcv_return=$?
	else
		sdcv_return=1
	fi
	# 只判断 sdcv 的返回值
	if [[ $sdcv_return == "0" ]]; then
		# 进行本地翻译
		literal_value=$(echo "$json_result" \
	   		| jq --raw-output --compact-output '[.[] | . as {dict: $dict, definition: $df} | {($dict): $df}]' \
	   		| perl -pe 's/^\[(.*)\]$/(\1,)/g' \
	   		| perl -pe 's/({(?<!\\)".*?(?<!\\)":(?<!\\)".*?(?<!\\)"}),?/\1 /g' \
			| perl -pe 's/{(?<!\\)"(.*?)(?<!\\)":(?<!\\)"(.*?)(?<!\\)"}/["\1"]="\2"/g')
		# sdcv 已经很贴心地把结果中的双引号用反斜杠转意了，但是这还不够
		# 因为结果中的解释文本中可能还有反引号，$符号，这两个符号可能会使 shell 造成混淆，试图进行命令替换等操作，所以我们还需手动对它们进行转意
		declare -A dicts=$(echo $literal_value | sed 's/`/\\`/g' | sed 's/\$/\\\$/g')

# 由于在转意换行符的下一行添加注释会出现 bug 使脚本不能执行，所以我把上面的代码在下面的注释中全部复制一遍，方便打注释
#		declare -A dicts=$(echo "$json_result" \
#		   	该行：生成形式如 [{"dictA":"defA"},{"dictB":"defB"}]
#	   		| jq --raw-output --compact-output '[.[] | . as {dict: $dict, definition: $df} | {($dict): $df}]' \
#	   		为方便之后的处理，先将两边的方括号换成圆括号，同时在最后一个元素后加一个逗号
#	   		就像这样：[{"dictA":"defA"},{"dictB":"defB"}] --> ({"dictA":"defA"},{"dictB":"defB"},)
#	   		| perl -pe 's/^\[(.*)\]$/(\1,)/g' \
#	   		将每个元素之间的逗号换成空格，同时避免匹配到 definition 中的逗号
#	   		就像这样：({"dictA":"defA"},{"dictB":"defB"},) --> ({"dictA":"defA"} {"dictB":"defB"} )
#	   		| perl -pe 's/({(?<!\\)".*?(?<!\\)":(?<!\\)".*?(?<!\\)"}),?/\1 /g' \
#	   		然后进行最后的格式转换：({"dictA":"defA"} {"dictB":"defB"} ) -->  (["dictA"]="defA" ["dictB"]="defB" )
#	   		| perl -pe 's/{(?<!\\)"(.*?)(?<!\\)":(?<!\\)"(.*?)(?<!\\)"}/["\1"]="\2"/g')
		
		# 分别输出每一个辞典的解释
		for dict_name in "${!dicts[@]}"; do
			formatter=${definition_formatters[$dict_name]}
			if [[ $formatter ]]; then
				# current dictionary has a formatter
				# TODO implement formatter code
				error "Definition formatter is not supported yet."
			else
				# print original definition
				output "\"$word\" -- $dict_name" "${dicts[$dict_name]}"
			fi
		done
	else
		# 尝试进行网络翻译
		if [[ $baidu_appid && $baidu_key ]]; then
			# 注意，output 可能不会向标准输出打印任何东西，所以 notification_id 可能为 null, 所以后面使用它时最好在用双引号引起来
			notification_id=$(output --timeout 0 "Searching \"$word\" online...")
			(
				salt="${RANDOM}${RANDOM}"
				combined_string="${baidu_appid}${word}${salt}${baidu_key}"
				sign=$(echo -n "$combined_string" | md5sum | cut --delimiter " " --fields 1)
				word_encoded=$(urlencode "$word")
				url="http://api.fanyi.baidu.com/api/trans/vip/translate?q=$word_encoded&from=en&to=zh&appid=$baidu_appid&salt=$salt&sign=$sign"
				online_result=$(curl --max-time "$time_out" --silent "$url")
				if [[ "$?" == "0" ]]; then
					online_definition=$(echo "$online_result" | jq '.trans_result[0].dst')
					output --replace "$notification_id" "\"$word\" online" "$online_definition"
				else
					output --error --replace "$notification_id" "Searching \"$word\" online..." "Error happens while searcing online..."
				fi
			) &
			bg_processes+=($!)
		else
			warn "No Baidu app id or Baidu key for translating \"$word\"."
		fi
	fi
done

# 等待所有的后台进程结束之后，才结束脚本
for pid in "${bg_processes[@]}"; do
	wait $pid
done
