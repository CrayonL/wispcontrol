#!/bin/sh
set -eu
umask 077
bin=/koolshare/wispcontrol
saved=/jffs/wispcontrol
run=/tmp/wispcontrol-run
wireless_wait=90
dhcp_tries=5
dhcp_timeout=3
dhcp_retry=20

fail() { printf '%s\n' "$1" >&2; exit 1; }
wait_wireless() {
    remaining=$wireless_wait
    until [ "$(nvram get wlready)" = 1 ] && [ -e /sys/class/net/br0 ]; do
        [ "$remaining" -gt 0 ] || fail '等待无线接口超时'
        sleep 1
        remaining=$((remaining - 1))
    done
}

start_station() {
    set -- /sys/class/net/wisp_sta*
    [ ! -e "$1" ] || fail '无线客户端接口已存在，跳过重复创建'
    iw phy phy1 interface add wisp_sta type managed
    set -- /sys/class/net/wisp_sta*
    [ "$#" -eq 1 ] && [ -e "$1" ] || fail '无线驱动未创建唯一的客户端接口'
    sta=${1##*/}
    [ ! -e "$1/master" ] || fail '无线客户端接口已加入网桥'
    iw dev "$sta" info | grep -q 'type managed' || fail '无线接口类型不符'
    printf '%s\n' "$sta" > "$run/interface"
    trap 'result=$?; if [ "$result" != 0 ]; then "$bin/stop.sh" startup-failed; fi' EXIT
    printf '1\n' > "/proc/sys/net/ipv6/conf/$sta/disable_ipv6"
    "$bin/firewall.sh"
    ip link set dev "$sta" up
    /usr/bin/wpa_supplicant -B -D nl80211 -i "$sta" -c "$saved/wpa.conf" -P "$run/wpa.pid" 9>&-
    udhcpc -b -i "$sta" -p "$run/udhcpc.pid" -s "$bin/dhcp.sh" \
        -t "$dhcp_tries" -T "$dhcp_timeout" -A "$dhcp_retry" 9>&-
}

exec 9>/tmp/wispcontrol-start.lock
flock -n 9 || exit 0
[ -s "$saved/wpa.conf" ] && [ ! -e "$saved/disabled" ] || exit 0
[ "$(nvram get productid)" = TUF-BE6500 ] && [ "$(nvram get sw_mode)" = 1 ] || fail '机型或路由模式不匹配'
[ "$(nvram get lan_ipaddr)/$(nvram get lan_netmask)" = 192.168.50.1/255.255.255.0 ] || fail 'LAN 地址或掩码已变化'
wait_wireless
mkdir -p "$run"
chmod 700 "$run"
start_station
