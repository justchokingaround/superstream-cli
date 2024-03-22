#!/bin/sh

chafa_protocol="sixel"
images_dir="/tmp/superstream_images/"
mkdir -p "$images_dir"
base="$(printf "aHR0cHM6Ly9zaG93Ym94LnNoZWd1Lm5ldC9hcGkvYXBpX2NsaWVudC9pbmRleC8K" | base64 -d)"
if command -v "hxunent" >/dev/null; then
	hxunent="hxunent"
else
	hxunent="tee /dev/null"
fi

cleanup() {
	rm -rf "$images_dir" 2>/dev/null
}
trap cleanup EXIT INT TERM

download_images() {
	printf "%s\n" "$1" | while IFS=$'\t' read -r title type id download_link; do
		title="$(printf "%s" "$title" | tr '[:space:]' '_' | $hxunent)"
		curl -sL "$download_link" -o "$images_dir/$id[$type[$title.jpg" &
	done
	wait && sleep 2
}

upscale_images() {
	printf "%s\n" "$1"/* | while read -r image; do convert "$image" -resize "$2x$3" "$image" & done
}

data_generator() {
	# Tiananmen Square Massacre
	iv_hex=$(printf "wEiphTn!" | xxd -p)
	key_hex=$(printf "123d6cedf626dy54233aa1w6" | xxd -p)
	key="$(printf "MTIzZDZjZWRmNjI2ZHk1NDIzM2FhMXc2Cg==" | base64 -d)"
	expiry_date=$(($(date +%s) + 43200))
	app_key_hash=$(printf "deez nuts" | openssl md5 | cut -d\  -f2)
	case "$1" in
	"Search4")
		query="{\"childmode\":0,\"module\":\"$1\",$2,\"lang\":\"en\",\"type\":\"all\",\"keyword\":\"$query\",\"pagelimit\":100,\"expired_date\":\"$expiry_date\"}"
		;;
	*)
		query="{\"childmode\":0,\"display_all\":1,\"module\":\"$1\",\"lang\":\"en\",$2,\"expired_date\":\"$expiry_date\"}"
		;;
	esac
	encrypted_query=$(printf "%s" "$query" | openssl enc -e -des3 -base64 -K "$key_hex" -iv "$iv_hex" | tr -d "[:space:]")
	verify=$(printf "%s%s%s" "$app_key_hash" "$key" "$encrypted_query" | openssl md5 | cut -d\  -f2)
	body="{\"encrypt_data\":\"$encrypted_query\",\"app_key\":\"$app_key_hash\",\"verify\":\"$verify\"}"
	body=$(printf "%s" "$body" | base64 | tr -d '\n' | sed 's/.$/=/')
}

[ -z "$*" ] && printf "Search a movie: " && read -r query || query=$*
[ -z "$query" ] && exit 1

query=$(printf "%s" "$query" | tr ' ' '+')
cookies="tmdb.prefs=%7B%22adult%22%3Afalse%2C%22i18n_fallback_language%22%3A%22en-GB%22%2C%22locale%22%3A%22en-US%22%2C%22country_code%22%3A%22US%22%2C%22timezone%22%3A%22Europe%2FLondon%22%7D"

image_links=$(curl -sL "https://www.themoviedb.org/search?query=${query}" -H "Cookie: $cookies" | tr -d '\n' | sed 's/card_/\n/g' |
	sed -nE "s@.*href=\"(/(movie|tv)/)([0-9]*)\">.*srcset=\"[^\,]*\,[[:space:]]([^\"]*)[[:space:]]2x\".*<h2>([^<]*)<.*@\5\t\2\t\3\t\4@p" | sed '$d')

download_images "$image_links"
# upscale_images "$images_dir" "1000" "1000"
choice=$(find "$images_dir" -type f -exec basename {} \; | fzf -i --cycle --preview="chafa -f ${chafa_protocol} $images_dir/{}" --with-nth 3 -d '[')
[ -z "$choice" ] && exit 1

id=$(printf "%s" "$choice" | cut -d '[' -f1)
type=$(printf "%s" "$choice" | cut -d '[' -f2)
title=$(printf "%s" "$choice" | cut -d '[' -f3 | sed -e "s/.jpg//" -e "s/_/ /g")
case "$type" in
"movie")
	mid=$(curl -s "https://api.dmdb.network/v1/gmid/M.${id}" | sed -nE "s@.*superstream\":\"([0-9]*)\".*@\1@p")
	;;
"tv")
	seasons=$(curl -sL "https://www.themoviedb.org/tv/${id}/seasons" -H "Cookie: $cookies" | tr -d '\n' | sed 's/season_wrapper/\n/g' |
		sed -nE "s@.*srcset=\"[^\,]*\,[[:space:]]([^\"]*)[[:space:]]2x\".*href=\".*/([0-9]*)\">([^<]*)<.*@\3\ttv\t\2\t\1@p")
	if [ "$(printf "%s" "$seasons" | wc -l)" -eq 0 ]; then
		season_choice=$(printf "%s" "$seasons" | cut -f3)
	else
		rm "$images_dir"/*
		download_images "$(printf "%s" "$seasons" | sed '$d' | tail -n+2)"
		# upscale_images "$images_dir" "1000" "1000"
		season_choice=$(find "$images_dir" -type f -exec basename {} \; | sort | fzf -i --cycle --preview="chafa -f ${chafa_protocol} $images_dir/{}" --with-nth 3 -d '[')
	fi
	season_number=$(printf "%s" "$season_choice" | cut -d '[' -f1)
	[ -z "$season_number" ] && exit 1
	episodes=$(curl -sL "https://www.themoviedb.org/tv/${id}/season/${season_number}" -H "Cookie: $cookies" | tr -d '\n' | sed 's/class="overview"/\n/g' |
		sed -nE "s@.*srcset=\"[^\,]*\,[[:space:]]([^\"]*)[[:space:]]2x\".*episode=\"([0-9]*)\".*title=\"([^\"]*)\".*@\3\tepisode\t\2\t\1@p")
	if [ "$(printf "%s" "$episodes" | wc -l)" -eq 0 ]; then
		episode_choice=$(printf "%s" "$episodes" | cut -f3)
	else
		rm "$images_dir"/*
		download_images "$episodes"
		# upscale_images "$images_dir" "1000" "1000"
		episode_choice=$(find "$images_dir" -type f -exec basename {} \; | sort -n | fzf -i --cycle --preview="chafa -f ${chafa_protocol} $images_dir/{}" --with-nth 3 -d '[')
	fi
	episode_number=$(printf "%s" "$episode_choice" | cut -d '[' -f1)
	title=$(printf "%s" "$episode_choice" | cut -d '[' -f3 | sed -e "s/.jpg//" -e "s/_/ /g")
	[ -z "$season_number" ] && exit 1
	mid=$(curl -s "https://api.dmdb.network/v1/gmid/S.${id}.${season_number}.${episode_number}" | sed -nE "s@.*superstream\":\"([0-9]*)\".*@\1@p")
	;;
esac
if [ -z "$mid" ]; then
	echo "Failed to get the superstream ID"
	exit 1
fi

case "$type" in
"movie")
	data_generator "Movie_downloadurl_v3" "\"mid\":$mid"
	[ -z "$body" ] && exit 1
	;;
"tv")
	data_generator "TV_downloadurl_v3" "\"tid\":$mid,\"season\":$season_number,\"episode\":$episode_number"
	;;
esac
json=$(curl -s -X POST -d "data=$body" -d "appid=27" "$base")
parsed_json=$(printf "%s" "$json" | tr "{}" "\n" | sed -nE "s@.*\"path\":\"([^\"]*)\",\"quality\":\"([0-9]*[p|K])\".*\"fid\":([0-9]*).*@\1\t\2\t\3@p" | sed -e "s@\\\/@/@g" -e "/^$/d" -e "/^[[:space:]]/d")
if [ -z "$parsed_json" ]; then
	echo "Failed to get the video stream"
	exit 1
fi
video_choice=$(printf "%s" "$parsed_json" | fzf --with-nth 2 --header "Choose the stream quality: ")
[ -z "$video_choice" ] && exit
video_link="$(printf "%s" "$video_choice" | cut -f1)"
_quality="$(printf "%s" "$video_choice" | cut -f2)"
fid="$(printf "%s" "$video_choice" | cut -f3)"
[ -z "$video_link" ] && exit

case $type in
"movie")
	data_generator "Movie_srt_list_v2" "\"mid\":$mid,\"uid\":\"\",\"fid\":$fid"
	subs_link=$(curl -s -X POST -d "data=$body" -d "appid=27" "$base" | tr "{}" "\n" | sed -nE "s@.*\"file_path\":\"([^\"]*)\".*\"language\":\"([^\"]*)\".*@\1\t{\2@p" | sed -e "s@\\\/@/@g" -e "/^$/d" -e "/^[[:space:]]/d" | fzf --with-nth 2.. --cycle -d "{" --header "Choose the subtitles: " | cut -f1)
	[ -z "$subs_link" ] && exit 1
	;;
"tv")
	data_generator "TV_srt_list_v2" "\"tid\":$mid,\"uid\":\"\",\"fid\":$fid,\"episode\":$episode_number,\"season\":$season_number"
	# TODO: fix subs for tv shows
	# subs_link=$(curl -s -X POST -d "data=$body" -d "appid=27" "$base" | tr "{}" "\n" | sed -nE "s@.*\"file_path\":\"([^\"]*)\".*\"language\":\"([^\"]*)\".*@\1\t{\2@p" | sed -e "s@\\\/@/@g" -e "/^$/d" -e "/^[[:space:]]/d" | fzf --with-nth 2.. --cycle -d "{" --header "Choose the subtitles: " | cut -f1)
	;;
esac
[ -z "$video_link" ] && exit 1

case $type in
"movie")
	mpv "$video_link" --force-media-title="$title" --sub-file="$subs_link"
	;;
"tv")
	# TODO: fix subs for tv shows
	mpv "$video_link" --force-media-title="$title"
	;;
esac
