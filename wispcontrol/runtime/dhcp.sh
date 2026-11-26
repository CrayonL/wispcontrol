#!/bin/sh
set -efu
umask 077
run=/tmp/wispcontrol-run
metric=500
exec 7>/tmp/wispcontrol-lease.lock
flock 7
[ -s "$run/interface" ] && [ "${interface:-}" = "$(cat "$run/interface")" ] || exit 1

# 将 DHCP 的掩码转为前缀，同时拒绝无效地址和与管理 LAN 重叠的租约。
lease_prefix() {
    awk -v addr="$ip" -v mask="$subnet" -v gw="$gateway" -v servers="${dns:-}" '
        function ipv4(s, a,i,v) {
            if (split(s,a,".") != 4) return -1
            for (i=1;i<=4;i++) {
                if (a[i] !~ /^(0|[1-9][0-9]?[0-9]?)$/ || a[i]+0>255) return -1
                v=v*256+a[i]
            }
            return v
        }
        function usable(v) { return v>0 && v<3758096384 && int(v/16777216)!=127 }
        BEGIN {
            a=ipv4(addr); g=ipv4(gw); m=ipv4(mask); lan=ipv4("192.168.50.1")
            if (!usable(a) || !usable(g) || a==g || m<=0) exit 1
            step=4294967296-m; prefix=32
            for (n=step;n>1;n/=2) { if (n%2) exit 1; prefix-- }
            if (int(a/step)!=int(g/step) || int(a/step)==int(lan/step) || int(a/256)==int(lan/256)) exit 1
            if (step>2 && (a%step==0 || a%step==step-1 || g%step==0 || g%step==step-1)) exit 1
            count=split(servers,list," "); for(i=1;i<=count;i++) if (!usable(ipv4(list[i]))) exit 1
            print prefix
        }'
}

reload_dns() {
    [ -s /var/run/dnsmasq.pid ] || return 0
    pid=$(cat /var/run/dnsmasq.pid)
    case "$pid" in ''|*[!0-9]*|0|1) return 1;; esac
    [ "$(cat "/proc/$pid/comm")" = dnsmasq ] && kill -HUP "$pid"
}

sync_clock() {
    [ "$(nvram get ntp_ready)" != 1 ] || return 0
    exec 6>"$run/clock.lock"
    flock -n 6 || return 0
    if ! pidof ntp >/dev/null; then service restart_ntpc; fi
    for setting in ntp_server0 ntp_server1; do
        [ "$(nvram get ntp_ready)" != 1 ] || return 0
        host=$(nvram get "$setting")
        [ -n "$host" ] || continue
        timeout -t 12 ntpclient -c 1 -s -h "$host" && [ "$(nvram get ntp_ready)" = 1 ] && return 0
    done
    logger -t wispcontrol '无线 WAN 已连接，固件时间同步尚未完成'
}

install_dns() {
    name=$1; format=$2
    if [ ! -f "$run/$name.applied" ] || ! cmp -s "/tmp/$name" "$run/$name.applied"; then
        if [ -f "/tmp/$name" ]; then cp "/tmp/$name" "$run/$name.before"; else rm -f "$run/$name.before"; fi
    fi
    for server in $dns; do printf "$format\n" "$server"; done > "$run/$name.next"
    # 固件的 cp 会重建文件，dnsmasq 降权后仍须能够读取这两个公共解析文件。
    (umask 022; cat "$run/$name.next" > "/tmp/$name")
    mv "$run/$name.next" "$run/$name.applied"
}

release_dns() {
    for name in resolv.conf resolv.dnsmasq; do
        [ -f "$run/$name.applied" ] || continue
        if cmp -s "/tmp/$name" "$run/$name.applied"; then
            if [ -f "$run/$name.before" ]; then cat "$run/$name.before" > "/tmp/$name"; else rm -f "/tmp/$name"; fi
        fi
        rm -f "$run/$name.applied" "$run/$name.before"
    done
}

remove_route() {
    prev=$(ip -4 route show default dev "$interface" | awk -v m="$metric" '$1=="default" && $2=="via" && $0 ~ (" metric " m "([ ]|$)") {print $3; exit}')
    if [ -n "$prev" ]; then ip route del default via "$prev" dev "$interface" metric "$metric"; fi
}

apply_lease() {
    set -- ${router:-}
    gateway=${1:-}
    case "${ip:-}${subnet:-}$gateway${dns:-}" in *[!0-9.\ ]*) echo 'DHCP 参数格式无效' >&2; return 1;; esac
    prefix=$(lease_prefix) || { echo '上级 DHCP 地址、网关、掩码或 DNS 无效，或与 LAN 重叠' >&2; return 1; }
    cidr=$ip/$prefix
    if [ -s "$run/address" ] && [ "$(cat "$run/address")" != "$cidr" ]; then
        ip -4 addr flush dev "$interface" scope global
    fi
    ip addr replace "$cidr" dev "$interface"
    printf '%s\n' "$cidr" > "$run/address"
    if ! ip -4 route show default | grep -F "default via $gateway dev $interface " | grep -Eq " metric $metric( |$)"; then
        remove_route
        ip route add default via "$gateway" dev "$interface" metric "$metric"
    fi
    if [ -n "${dns:-}" ]; then
        install_dns resolv.conf 'nameserver %s'
        install_dns resolv.dnsmasq 'server=%s'
    else
        release_dns
        echo '上级 DHCP 未提供 DNS，沿用固件解析设置' >&2
    fi
    reload_dns
    sync_clock 7>&- </dev/null > "$run/clock.log" 2>&1 &
}

case "${1:-}" in
    bound|renew) apply_lease;;
    deconfig)
        if [ -d "/sys/class/net/$interface" ]; then
            remove_route
            ip -4 addr flush dev "$interface" scope global
        fi
        rm -f "$run/address"
        if [ -f "$run/resolv.conf.applied" ] || [ -f "$run/resolv.dnsmasq.applied" ]; then release_dns; reload_dns; fi;;
    *) exit 0;;
esac
