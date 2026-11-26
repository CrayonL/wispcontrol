#!/bin/sh
# 从正式压缩包测试。需要有 NET_ADMIN、独立网络命名空间及 jq/iptables/iproute2/dnsmasq 的临时容器。
set -eu
. /src/tests/router-fixture.sh
mkdir -p /fixture/old /fixture/new
tar xzf /src/wispcontrol.tar.gz -C /fixture/new
pkg=/fixture/new/wispcontrol
api=/koolshare/scripts/wisp_control.sh
assert_reply() { [ "$(cat /fixture/response)" = "$1" ]; }
status() { "$api" 1 status; sed 's/^status|//' /fixture/response | base64 -d; }
until_ok() {
    remaining=12
    until "$@"; do
        [ "$remaining" -gt 0 ] || { cat /tmp/wispcontrol-boot.log >&2; return 1; }
        sleep 1
        remaining=$((remaining - 1))
    done
}

if [ -f /prior.tar.gz ]; then
    tar xzf /prior.tar.gz -C /fixture/old
    if sh /fixture/old/wispcontrol/install.sh > /fixture/baseline; then exit 1; fi
    grep -q '缺少已有 WISP 配置' /fixture/baseline
fi
sh "$pkg/install.sh"
sh "$pkg/install.sh"
[ "$(cat /fixture/dbus/softcenter_module_wispcontrol_version)" = 0.0.1 ]
[ ! -e /jffs/wispcontrol/wpa.conf ]
[ ! -e /fixture/reboot-requested ]
status | jq -e '.enabled==false and .ssidHex=="" and .hasRoute==false'
"$api" 1 scan
grep -q '^scan|' /fixture/response
sed 's/^scan|//' /fixture/response | base64 -d | grep -q DEMO1
if "$api" 1 enable; then exit 1; fi
assert_reply 'error|missing_config'
"$api" 1 connect 44454d4f31 6162636465666768 6
assert_reply 'accepted|reboot'
[ ! -e /jffs/wispcontrol/wpa.previous.conf ]
[ "$(cat /fixture/nvram/wl0_channel)" = 6 ]
until_ok test -f /fixture/reboot-requested
rm /tmp/wispcontrol-reboot-pending

# 两个独立命名空间分别模拟上级路由器与下游电脑，路由器自身未接入外网。
unshare -n sleep 60 & upstream=$!
unshare -n sleep 60 & client=$!
sleep 1
up() { nsenter -t "$upstream" -n "$@"; }
lan() { nsenter -t "$client" -n "$@"; }
ip link add simradio type veth peer name up0
ip link set up0 netns "$upstream"
up ip link set lo up
up ip addr add 172.20.8.1/24 dev up0
up ip link set up0 up
up dnsmasq --conf-file=/dev/null --interface=up0 --bind-interfaces --no-resolv \
    --dhcp-range=172.20.8.20,172.20.8.40,255.255.255.0,5m --address=/probe.test/172.20.8.1 \
    --dhcp-leasefile=/fixture/up.leases --pid-file=/fixture/up.pid --user=root
ip link add br0 type bridge
ip addr add 192.168.50.1/24 dev br0
ip link set br0 up
ip link add lanport type veth peer name pc0
ip link set lanport master br0
ip link set lanport up
ip link set pc0 netns "$client"
lan ip addr add 192.168.50.2/24 dev pc0
lan ip link set pc0 up
lan ip route add default via 192.168.50.1
printf 'server=192.0.2.2\n' > /tmp/resolv.dnsmasq
printf 'nameserver 192.0.2.2\n' > /tmp/resolv.conf
chmod 644 /tmp/resolv.conf /tmp/resolv.dnsmasq
ln /tmp/resolv.dnsmasq /fixture/resolver-inode
dnsmasq --conf-file=/dev/null --interface=br0 --bind-interfaces --no-resolv \
    --servers-file=/tmp/resolv.dnsmasq --pid-file=/var/run/dnsmasq.pid --user=nobody
iptables -P FORWARD DROP
/koolshare/init.d/V99wispcontrol.sh
until_ok test -f /tmp/wispcontrol-run/resolv.dnsmasq.applied
until_ok grep -qx 1 /fixture/nvram/ntp_ready
[ /tmp/resolv.dnsmasq -ef /fixture/resolver-inode ]
status | jq -e '.enabled and .hasRoute and .state=="COMPLETED" and (.ip|startswith("172.20.8."))'
lan ping -c 1 -W 2 172.20.8.1
lan nslookup probe.test 192.168.50.1 | grep -q '172.20.8.1'
iptables -t nat -Z POSTROUTING
iptables -F
iptables -t nat -F
/jffs/scripts/firewall-start
/koolshare/init.d/N99wispcontrol.sh start_nat
lan ping -c 1 -W 2 172.20.8.1
[ "$(iptables -t nat -S POSTROUTING | grep -c MASQUERADE)" = 1 ]
ip_before=$(cat /tmp/wispcontrol-run/address)
if interface=wisp_sta4 ip=192.168.50.9 router=192.168.50.254 subnet=255.255.255.0 dns=192.168.50.254 /koolshare/wispcontrol/dhcp.sh renew; then exit 1; fi
[ "$(cat /tmp/wispcontrol-run/address)" = "$ip_before" ]
interface=wisp_sta4 ip="${ip_before%/*}" router=172.20.8.1 subnet=255.255.255.0 dns=172.20.8.1 /koolshare/wispcontrol/dhcp.sh renew
lan nslookup probe.test 192.168.50.1 | grep -q '172.20.8.1'
sh /koolshare/scripts/uninstall_wispcontrol.sh
[ ! -e /sys/class/net/wisp_sta4 ] && [ ! -e /koolshare/init.d/V99wispcontrol.sh ] || exit 1
[ ! -e /koolshare/init.d/N99wispcontrol.sh ] && [ ! -e /koolshare/wispcontrol ] || exit 1
[ -s /jffs/wispcontrol/wpa.conf ] && [ -f /jffs/wispcontrol/disabled ] || exit 1
[ "$(nvram get wl0_channel)" = 0 ]
cmp /jffs/scripts/firewall-start /fixture/original-hook
grep -Fxq 'server=192.0.2.2' /tmp/resolv.dnsmasq
[ /tmp/resolv.dnsmasq -ef /fixture/resolver-inode ]
grep -Fxq 'nameserver 192.0.2.2' /tmp/resolv.conf
sh "$pkg/install.sh"
status | jq -e '.enabled==false and .ssidHex=="44454d4f31"'
printf '%s\n' 'PASS fresh install, first profile, boot, real DHCP/DNS/NAT, firewall reload, renew, uninstall and reinstall'
