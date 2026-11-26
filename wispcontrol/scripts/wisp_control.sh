#!/bin/sh
umask 077
case "${1:-}" in ''|*[!0-9]*) exit 1;; esac
[ "${#1}" -le 10 ] || exit 1
. /koolshare/scripts/base.sh
. /koolshare/scripts/wisp_control_lib.sh

respond() { http_response "$1" >/dev/null; }
reject() { respond "error|$1"; exit 1; }
encode() { base64 | tr -d '\n'; }

select_wisp_paths || reject ambiguous_config
[ "$(nvram get sw_mode)" = 1 ] || reject router_mode
case "${2:-}" in
    status) data=$(status_json) || reject status_failed; respond "status|$(printf '%s' "$data" | encode)"; exit;;
    scan|connect) ;;
    previous|enable|disable) [ -s "$SAVED/wpa.conf" ] || reject missing_config;;
    *) reject invalid_action;;
esac
exec 9>"$CONTROL_PREFIX-control.lock"
flock -n 9 || reject busy
[ ! -e "$PENDING_FILE" ] || reject reboot_pending
[ ! -d "$SAVED/ui-transaction" ] || reject unfinished_transaction
TXN=$SAVED/ui-transaction
mkdir "$TXN" || reject storage_failed
chmod 700 "$TXN" || reject storage_failed

cleanup() {
    # 路径固定，只清理本次操作自己的临时事务目录。
    rm -rf "$TXN"
}

scan_networks() {
    timeout -t 25 iw dev ath0 scan > "$TXN/scan.txt" 2> "$TXN/scan.error" 9>&- || return 1
    respond "scan|$(encode < "$TXN/scan.txt")"
}

prepare_candidate() {
    case "$ACTION_NAME" in
        connect)
            write_profile "$SSID_HEX" "$KEY_HEX" "$CHANNEL" > "$TXN/candidate" || return 1;;
        previous)
            [ -s "$SAVED/wpa.previous.conf" ] || return 1
            profile_channel "$SAVED/wpa.previous.conf" >/dev/null || return 1
            cp -p "$SAVED/wpa.previous.conf" "$TXN/candidate" || return 1;;
    esac
}

if [ "$2" = scan ]; then
    scan_networks || { cleanup; reject scan_failed; }
    cleanup
    exit 0
fi
[ "$(nvram get lan_ipaddr)/$(nvram get lan_netmask)" = 192.168.50.1/255.255.255.0 ] || { cleanup; reject lan_changed; }
ACTION_NAME=$2
SSID_HEX=${3:-}
KEY_HEX=${4:-}
CHANNEL=${5:-}
if [ "$ACTION_NAME" = connect ]; then
    [ "$#" -eq 5 ] || { cleanup; reject invalid_profile; }
else
    [ "$#" -eq 2 ] || { cleanup; reject invalid_profile; }
fi
prepare_candidate || { cleanup; reject invalid_profile; }
snapshot_config || { cleanup; reject backup_failed; }
if ! apply_config "$2"; then
    rollback_config || reject rollback_failed
    cleanup
    reject apply_failed
fi
if ! touch "$PENDING_FILE"; then
    rollback_config || reject rollback_failed
    cleanup
    reject pending_failed
fi
cleanup
respond 'accepted|reboot'
# 不继承 API 的锁与输出句柄，先让页面收到应答再重启。
nohup sh -c 'sleep 4; reboot' </dev/null >/tmp/wispcontrol-reboot.log 2>&1 9>&- &
