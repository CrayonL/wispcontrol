#!/bin/sh
set -eu
umask 077
run=/tmp/wispcontrol-run
lan=192.168.50.0/24
mode=${1:-install}
exec 8>/tmp/wispcontrol-firewall.lock
flock 8
[ -s "$run/interface" ] || exit 0
sta=$(cat "$run/interface")
case "$sta" in wisp_sta) ;; wisp_sta*) case "${sta#wisp_sta}" in *[!0-9]*) exit 1;; esac;; *) exit 1;; esac

ensure_chain() {
    iptables -t "$1" -S "$2" >/dev/null 2>&1 || iptables -t "$1" -N "$2"
}

rule() {
    table=$1; chain=$2; placement=$3; shift 3
    if iptables -t "$table" -C "$chain" "$@" 2>/dev/null; then
        if [ "$mode" = remove ]; then iptables -t "$table" -D "$chain" "$@"; fi
    elif [ "$mode" != remove ]; then
        iptables -t "$table" "$placement" "$chain" "$@"
    fi
}

drop_chain() {
    if iptables -t "$1" -S "$2" >/dev/null 2>&1; then
        iptables -t "$1" -F "$2"
        iptables -t "$1" -X "$2"
    fi
}

if [ "$mode" != remove ]; then
    [ ! -e /jffs/wispcontrol/disabled ] && [ -d "/sys/class/net/$sta" ] || exit 0
    [ ! -e "/sys/class/net/$sta/master" ] || exit 1
    ensure_chain filter WISPCTL_IN
    ensure_chain filter WISPCTL_FWD
    ensure_chain nat WISPCTL_PRE
    rule filter WISPCTL_IN -A -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    rule filter WISPCTL_IN -A -p udp --sport 67 --dport 68 -j ACCEPT
    rule filter WISPCTL_IN -A -j DROP
    rule filter WISPCTL_FWD -A -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    rule filter WISPCTL_FWD -A -j DROP
    # 有线 WAN 未接线时，固件会重定向 DNS 和 HTTP。保留无线出口的正常转发。
    rule nat WISPCTL_PRE -A -p udp --dport 53 -j ACCEPT
    rule nat WISPCTL_PRE -A -p tcp --dport 80 -j ACCEPT
fi
rule filter INPUT -I -i "$sta" -j WISPCTL_IN
rule filter FORWARD -I -i "$sta" -j WISPCTL_FWD
rule filter FORWARD -I -i br0 -o "$sta" -s "$lan" -j ACCEPT
rule nat POSTROUTING -I -s "$lan" -o "$sta" -j MASQUERADE
rule nat PREROUTING -I -i br0 -s "$lan" -j WISPCTL_PRE
if [ "$mode" = remove ]; then
    drop_chain filter WISPCTL_IN
    drop_chain filter WISPCTL_FWD
    drop_chain nat WISPCTL_PRE
fi
