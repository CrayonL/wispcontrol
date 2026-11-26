#!/bin/sh
# 仅在断网的临时容器内使用。veth 代替射频，固件 RPC、NVRAM 和整机重启由替身提供。
set -eu
[ -f /.dockerenv ] && [ ! -e /koolshare ] && [ ! -e /jffs ] || exit 2
mkdir -p /koolshare/scripts /koolshare/webs /koolshare/init.d /koolshare/res /jffs/scripts /fixture/bin /fixture/nvram /fixture/dbus
export PATH="/fixture/bin:$PATH"
cat > /fixture/bin/nvram <<'EOF'
#!/bin/sh
case "$1" in
    get) cat "/fixture/nvram/$2";;
    set) printf '%s' "${2#*=}" > "/fixture/nvram/${2%%=*}";;
    commit) :;;
    *) exit 1;;
esac
EOF
cat > /fixture/bin/dbus <<'EOF'
#!/bin/sh
case "$1" in
    set) printf '%s' "${2#*=}" > "/fixture/dbus/${2%%=*}";;
    remove) rm -f "/fixture/dbus/$2";;
    *) exit 1;;
esac
EOF
cat > /fixture/bin/iw <<'EOF'
#!/bin/sh
case "$*" in
    'dev ath0 scan') printf 'BSS 02:00:00:00:00:01(on ath0)\n\tfreq: 2437\n\tSSID: DEMO1\n';;
    'phy phy1 interface add wisp_sta type managed') ip link set simradio name wisp_sta4;;
    'dev wisp_sta4 info') echo 'type managed';;
    'dev wisp_sta4 del') ip link del wisp_sta4;;
    *) exit 1;;
esac
EOF
cat > /fixture/bin/wpa_supplicant <<'EOF'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do
    case "$1" in -c) conf=$2; shift;; -P) pidfile=$2; shift;; esac
    shift
done
grep -Fxq '    ssid=44454d4f31' "$conf"
grep -Fxq '    psk="abcdefgh"' "$conf"
grep -Fxq '    scan_freq=2437' "$conf"
mkdir -p /tmp/wispcontrol-run/ctrl
sh -c 'trap "exit 0" TERM; while :; do sleep 1; done' fixture "$conf" </dev/null >/dev/null 2>&1 &
echo "$!" > "$pidfile"
EOF
cat > /usr/bin/wpa_cli <<'EOF'
#!/bin/sh
printf 'wpa_state=COMPLETED\nip_address=%s\nfreq=2437\n' "$(ip -4 -o addr show dev wisp_sta4 | awk '{print $4}' | cut -d/ -f1)"
EOF
cat > /fixture/bin/timeout <<'EOF'
#!/bin/sh
[ "$1" != -t ] || shift
exec busybox timeout "$@"
EOF
printf '#!/bin/sh\ntouch /fixture/reboot-requested\n' > /fixture/bin/reboot
printf '#!/bin/sh\n[ "$*" = restart_ntpc ]\n' > /fixture/bin/service
printf '#!/bin/sh\n[ "$*" = "-c 1 -s -h clock.test" ] && nvram set ntp_ready=1\n' > /fixture/bin/ntpclient
chmod +x /fixture/bin/* /usr/bin/wpa_cli
ln -s /fixture/bin/wpa_supplicant /usr/bin/wpa_supplicant
echo 'http_response() { printf "%s" "$1" > /fixture/response; }' > /koolshare/scripts/base.sh
for field in productid=TUF-BE6500 sw_mode=1 wlready=1 lan_ipaddr=192.168.50.1 lan_netmask=255.255.255.0 wl0_channel=0 ntp_ready=0 ntp_server0=clock.test; do nvram set "$field"; done
echo '#!/bin/sh' > /jffs/scripts/firewall-start
echo 'echo existing-hook >> /fixture/hook-ran' >> /jffs/scripts/firewall-start
chmod 755 /jffs/scripts/firewall-start
cp /jffs/scripts/firewall-start /fixture/original-hook
