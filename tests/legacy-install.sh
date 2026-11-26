#!/bin/sh
set -eu
. /src/tests/router-fixture.sh
install_dir=/fixture/package
mkdir "$install_dir"
tar xzf /src/wispcontrol.tar.gz -C "$install_dir"
pkg=$install_dir/wispcontrol
old=/jffs/codex-wisp
mkdir "$old"
printf '#!/bin/sh\nexit 1\n' > "$old/restore.sh"
chmod 700 "$old/restore.sh"
printf 'network={\n    ssid=44454d4f31\n    scan_freq=2437\n}\n' > "$old/wpa.conf"
echo 11 > "$old/original-channel"
printf '#!/bin/sh\nexec %s/restore.sh\n' "$old" > /koolshare/init.d/V99codex-wisp.sh
sha256sum "$old/restore.sh" "$old/wpa.conf" "$old/original-channel" /koolshare/init.d/V99codex-wisp.sh > /fixture/legacy-digests
sh "$pkg/install.sh"
[ ! -e /jffs/wispcontrol ] && [ ! -e /koolshare/init.d/V99wispcontrol.sh ] || exit 1
cmp /jffs/scripts/firewall-start /fixture/original-hook
/koolshare/scripts/wisp_control.sh 1 status
sed 's/^status|//' /fixture/response | base64 -d | jq -e '.enabled and .ssidHex=="44454d4f31"'
sh /koolshare/scripts/uninstall_wispcontrol.sh
sha256sum -c /fixture/legacy-digests
mkdir /jffs/wispcontrol
if sh "$pkg/install.sh" > /fixture/conflict; then exit 1; fi
grep -q '发现两套 WISP 配置' /fixture/conflict
echo 'PASS legacy configuration, boot hook, channel, firewall hook and conflict detection'
