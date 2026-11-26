#!/bin/sh
PROFILE_FILES='wpa.conf wpa.previous.conf disabled'

select_wisp_paths() {
    SAVED=/jffs/wispcontrol
    # 软件中心会在离线安装结束时清理 /tmp/模块名。
    RUNTIME=/tmp/wispcontrol-run
    # 旧版开机钩子仍引用原目录和控制套接字，升级时须与它共享配置、锁和待重启标记。
    legacy=/jffs/codex-wisp
    if [ -d "$legacy" ]; then
        if [ -e "$SAVED" ] && ! [ "$SAVED" -ef "$legacy" ]; then return 1; fi
        SAVED=$legacy
        RUNTIME=/tmp/${legacy##*/}-test
    elif [ -x "$SAVED/restore.sh" ]; then
        RUNTIME=/tmp/wispcontrol
    fi
    CONTROL_PREFIX=/tmp/${SAVED##*/}
    PENDING_FILE=$CONTROL_PREFIX-reboot-pending
}

valid_channel() {
    case "$1" in 0|1|2|3|4|5|6|7|8|9|10|11|12|13) return 0;; *) return 1;; esac
}

profile_ssid() {
    [ -f "$1" ] || return 0
    sed -n 's/^[[:space:]]*ssid=\([0-9a-fA-F]*\)$/\1/p' "$1" | head -n 1
}

profile_channel() {
    freq=$(sed -n 's/^[[:space:]]*scan_freq=\([0-9]*\)$/\1/p' "$1")
    case "$freq" in 2412|2417|2422|2427|2432|2437|2442|2447|2452|2457|2462|2467|2472) ;;
        *) return 1;; esac
    printf '%s\n' "$(((freq - 2407) / 5))"
}

validate_profile() {
    printf '%s' "$1" | grep -Eq '^([0-9a-f]{2}){1,32}$' || return 1
    # WPA2 口令为 8–63 个可打印 ASCII 字符；传输用十六进制避免 Shell 解释。
    printf '%s' "$2" | grep -Eq '^([2-6][0-9a-f]|7[0-e]){8,63}$' || return 1
    valid_channel "$3" && [ "$3" != 0 ]
}

write_profile() {
    validate_profile "$1" "$2" "$3" || return 1
    secret=$(printf '%b' "$(printf '%s' "$2" | sed 's/../\\x&/g')") || return 1
    escaped=$(printf '%s' "$secret" | sed 's/\\/\\\\/g;s/"/\\"/g') || return 1
    printf 'ctrl_interface=%s/ctrl\nupdate_config=0\nnetwork={\n' "$RUNTIME" || return 1
    printf '    ssid=%s\n    psk="%s"\n' "$1" "$escaped" || return 1
    printf '    key_mgmt=WPA-PSK\n    proto=RSN\n    pairwise=CCMP\n' || return 1
    printf '    scan_freq=%s\n    scan_ssid=1\n}\n' "$((2407 + 5 * $3))" || return 1
    unset secret escaped
}

snapshot_config() {
    mkdir "$TXN/before" || return 1
    for entry in $PROFILE_FILES; do
        [ ! -e "$SAVED/$entry" ] || cp -p "$SAVED/$entry" "$TXN/before/$entry" || return 1
    done
    nvram get wl0_channel > "$TXN/channel" || return 1
    valid_channel "$(cat "$TXN/channel")"
}

rollback_config() {
    rollback_ok=0
    for entry in $PROFILE_FILES; do
        if [ -e "$TXN/before/$entry" ]; then
            cp -p "$TXN/before/$entry" "$SAVED/$entry" || rollback_ok=1
        else
            rm -f "$SAVED/$entry" || rollback_ok=1
        fi
    done
    nvram set "wl0_channel=$(cat "$TXN/channel")" || rollback_ok=1
    nvram commit || rollback_ok=1
    return "$rollback_ok"
}

apply_config() {
    action=$1
    if [ "$action" = connect ] || [ "$action" = previous ]; then
        if [ -s "$SAVED/wpa.conf" ]; then
            cp -p "$SAVED/wpa.conf" "$SAVED/wpa.previous.conf" || return 1
        fi
        cp -p "$TXN/candidate" "$SAVED/wpa.conf" || return 1
    fi
    if [ "$action" = disable ]; then
        channel=$(cat "$SAVED/original-channel") || return 1
        valid_channel "$channel" || return 1
        touch "$SAVED/disabled" || return 1
    else
        channel=$(profile_channel "$SAVED/wpa.conf") || return 1
        rm -f "$SAVED/disabled" || return 1
    fi
    nvram set "wl0_channel=$channel" || return 1
    nvram commit || return 1
    sync
}

status_json() {
    enabled=true
    [ -s "$SAVED/wpa.conf" ] && [ ! -e "$SAVED/disabled" ] || enabled=false
    state=STOPPED
    ip_addr=
    freq=
    has_route=false
    set -- /sys/class/net/wisp_sta*
    if [ -s "$SAVED/wpa.conf" ] && [ "$#" -eq 1 ] && [ -e "$1" ] && [ -d "$RUNTIME/ctrl" ]; then
        status=$(/usr/bin/wpa_cli -p "$RUNTIME/ctrl" -i "${1##*/}" status) || return 1
        state=$(printf '%s\n' "$status" | sed -n 's/^wpa_state=//p')
        ip_addr=$(printf '%s\n' "$status" | sed -n 's/^ip_address=//p')
        freq=$(printf '%s\n' "$status" | sed -n 's/^freq=//p')
        ip route show default | grep -q " dev ${1##*/} " && has_route=true
    elif [ "$enabled" = true ] && [ "$#" -eq 1 ] && [ -e "$1" ]; then
        state=STARTING
    fi
    pending=false
    [ ! -e "$PENDING_FILE" ] || pending=true
    jq -cn --argjson enabled "$enabled" --argjson pending "$pending" --argjson hasRoute "$has_route" \
        --arg state "$state" --arg ip "$ip_addr" --arg frequency "$freq" \
        --arg ssidHex "$(profile_ssid "$SAVED/wpa.conf")" \
        --arg previousHex "$(profile_ssid "$SAVED/wpa.previous.conf")" \
        '{enabled:$enabled,pending:$pending,hasRoute:$hasRoute,state:$state,ip:$ip,frequency:$frequency,ssidHex:$ssidHex,previousHex:$previousHex}'
}
