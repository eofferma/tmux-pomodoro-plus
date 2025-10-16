#!/usr/bin/env bash

get_tmux_option() {
	local option="$1"
	local default_value="$2"

	option_value=$(tmux show-option -gqv "$option")

	if [ -z "$option_value" ]; then
		echo "$default_value"
	else
		echo "$option_value"
	fi
}

set_tmux_option() {
	local option="$1"
	local value="$2"

	tmux set-option -gq "$option" "$value"
}

file_exists() {
	local file="$1"
	if [ -f "$file" ]; then
		return 0 # file exists
	fi

	return 1 # file does not exist
}

read_file() {
	local file="$1"
	if [ -f "$file" ]; then
		cat "$file"
	else
		echo 1
	fi
}

remove_file() {
	local file="$1"
	if [ -f "$file" ]; then
		rm "$file"
	fi
}

write_to_file() {
	local data="$1"
	local file="$2"
	echo "$data" >"$file"
}

if_inside_tmux() {
	if [ -n "${TMUX}" ]; then
		return 0
	fi
	return 1
}

refresh_statusline() {
	if_inside_tmux && tmux refresh-client -S >/dev/null 2>&1
}

minutes_to_seconds() {
	local minutes=$1
	echo $((minutes * 60))
}

notification_env_file() {
	local dir="${POMODORO_DIR:-/tmp}"
	echo "${dir}/notify_env.sh"
}

load_notification_env() {
	local env_file
	env_file=$(notification_env_file)

	if [ -z "${DISPLAY:-}" ] || [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
		if [ -f "$env_file" ]; then
			# shellcheck disable=SC1090
			. "$env_file"
		fi
	fi
}

cache_notification_env() {
	local env_file
	env_file=$(notification_env_file)

	if [ -n "${DISPLAY:-}" ] && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
		mkdir -p "$(dirname "$env_file")"
		{
			printf 'export DISPLAY=%q\n' "$DISPLAY"
			printf 'export DBUS_SESSION_BUS_ADDRESS=%q\n' "$DBUS_SESSION_BUS_ADDRESS"
		} >"$env_file"
	fi
}

notifications_muted() {
	case "$OSTYPE" in
	linux* | *bsd*)
		if command -v gsettings >/dev/null 2>&1; then
			local banners
			banners=$(gsettings get org.gnome.desktop.notifications show-banners 2>/dev/null)
			if [[ "$banners" == 'false' ]]; then
				return 0
			fi
		fi
		;;
	esac

	return 1
}

send_notification() {
	# Params: title, message, play_sound=false, duration_ms=5000
	# - Sound only plays when play_sound=true, @pomodoro_sound isn't "off", and GNOME banners are on.
	#   (play_sound is set true for events like "start working again" so you hear the cue.)
	# - duration_ms controls notify-send expire time.
	# - If GNOME "Do Not Disturb" is active (notifications_muted), we still send the banner but skip audio.
	local notifications_setting
	notifications_setting="$(get_notifications)"

	if [ "$notifications_setting" == 'on' ]; then
		local title=$1
		local message=$2
		local play_sound=${3:-false}
		local duration_ms=${4:-2000}
		local allow_sound=true

		if notifications_muted; then
			allow_sound=false
		fi

		sound=$(get_sound)
		export sound
		case "$OSTYPE" in
		linux* | *bsd*)
			load_notification_env
			local urgency="normal"
			if [[ "$duration_ms" =~ ^[0-9]+$ ]] && [ "$duration_ms" -ge 60000 ]; then
				urgency="critical"
			fi

			notify-send --urgency "$urgency" \
				--app-name "Pomodoro Timer" \
				--expire-time "$duration_ms" \
				--icon /home/farkore/.config/tmux/icon-pomodoro.png \
				"$title" "$message"
			cache_notification_env
			if $play_sound && [ "$allow_sound" = true ]; then
				if [[ "$sound" == "on" ]]; then
					mpg123 -q ~/.config/tmux/pomodoro.mp3
				elif [[ "$sound" != "off" ]]; then
					$sound
				fi
			fi
			;;
		darwin*)
			if [[ "$sound" != "off" ]] && $play_sound && [ "$allow_sound" = true ]; then
				osascript -e 'display notification "'"$message"'" with title "'"$title"'" sound name "'"$sound"'"'
			else
				osascript -e 'display notification "'"$message"'" with title "'"$title"'"'
			fi
			;;
		esac
	fi
}

debug_log() {
	# add log print into the code (debug_log "hello from tmux_pomodoro_plus)"
	# set true to enable log messages
	# follow the log using "tail -f /tmp/pomodoro/pomodoro.log"
	if true; then
		DIR="/tmp/pomodoro"
		FILE="pomodoro.log"
		mkdir -p $DIR
		echo "$(date +%T) " "$1" >>"$DIR/$FILE"
	fi
}
