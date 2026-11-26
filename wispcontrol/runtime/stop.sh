#!/bin/sh
set -eu
run=/tmp/wispcontrol-run
bin=/koolshare/wispcontrol
if [ "${1:-}" != startup-failed ]; then
    exec 9>/tmp/wispcontrol-start.lock
    flock 9
fi
[ -s "$run/interface" ] || exit 0
sta=$(cat "$run/interface")
case "$sta" in wisp_sta) ;; wisp_sta*) case "${sta#wisp_sta}" in *[!0-9]*) exit 1;; esac;; *) exit 1;; esac

stop_owned() {
    [ -s "$1" ] || return 0
    pid=$(cat "$1")
    case "$pid" in ''|*[!0-9]*|0|1) return 1;; esac
    [ -r "/proc/$pid/cmdline" ] || return 0
    tr '\000' '\n' < "/proc/$pid/cmdline" | grep -Fxq "$2" || { echo '进程已被替换，停止卸载' >&2; return 1; }
    kill "$pid"
    attempts=5
    while [ -r "/proc/$pid/stat" ] && [ "$(awk '{print $3}' "/proc/$pid/stat" 2>/dev/null)" != Z ]; do
        [ "$attempts" -gt 0 ] || return 1
        sleep 1
        attempts=$((attempts - 1))
    done
}
stop_owned "$run/udhcpc.pid" "$bin/dhcp.sh"
stop_owned "$run/wpa.pid" /jffs/wispcontrol/wpa.conf
interface=$sta "$bin/dhcp.sh" deconfig
if [ -d "/sys/class/net/$sta" ]; then
    ip link set dev "$sta" down
    iw dev "$sta" del
fi
"$bin/firewall.sh" remove
rm -f "$run/interface" "$run/udhcpc.pid" "$run/wpa.pid"
