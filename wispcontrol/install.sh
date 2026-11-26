#!/bin/sh
set -eu
umask 077
ROOT=$(cd "$(dirname "$0")" && pwd)
[ "$(nvram get productid)" = TUF-BE6500 ] || { echo '设备型号不匹配'; exit 1; }
. "$ROOT/scripts/wisp_control_lib.sh"
select_wisp_paths || { echo '发现两套 WISP 配置，请先确认开机脚本使用的目录'; exit 1; }
[ -s "$SAVED/wpa.conf" ] && [ -x "$SAVED/restore.sh" ] || { echo '缺少已有 WISP 配置'; exit 1; }
[ -x /usr/bin/jq ] && [ -d /koolshare/webs ] || exit 1
version=$(cat "$ROOT/version")
profile_channel "$SAVED/wpa.conf" >/dev/null || { echo '当前网络信道无法识别'; exit 1; }
if [ ! -e "$SAVED/original-channel" ]; then
    channel=$(nvram get wl0_channel)
    valid_channel "$channel" || exit 1
    printf '%s\n' "$channel" > "$SAVED/original-channel"
fi
cp "$ROOT/scripts/wisp_control_lib.sh" /koolshare/scripts/wisp_control_lib.sh
cp "$ROOT/scripts/wisp_control.sh" /koolshare/scripts/wisp_control.sh
cp "$ROOT/webs/Module_wispcontrol.asp" /koolshare/webs/Module_wispcontrol.asp
cp "$ROOT/res/wisp_control.js" /koolshare/res/wisp_control.js
cp "$ROOT/res/icon-wispcontrol.svg" /koolshare/res/icon-wispcontrol.svg
cp "$ROOT/res/icon-wispcontrol.png" /koolshare/res/icon-wispcontrol.png
cp "$ROOT/uninstall.sh" /koolshare/scripts/uninstall_wispcontrol.sh
chmod 700 /koolshare/scripts/wisp_control.sh /koolshare/scripts/wisp_control_lib.sh
chmod 700 /koolshare/scripts/uninstall_wispcontrol.sh
chmod 644 /koolshare/webs/Module_wispcontrol.asp /koolshare/res/wisp_control.js
chmod 644 /koolshare/res/icon-wispcontrol.svg /koolshare/res/icon-wispcontrol.png
dbus set softcenter_module_wispcontrol_name=wispcontrol
dbus set softcenter_module_wispcontrol_title='WISP 无线上网'
dbus set softcenter_module_wispcontrol_description='管理 TUF-BE6500 已配置的 WISP，切换或恢复上级 Wi-Fi'
dbus set softcenter_module_wispcontrol_home_url=Module_wispcontrol.asp
dbus set "softcenter_module_wispcontrol_version=$version"
dbus set softcenter_module_wispcontrol_install=1
echo '控制页已安装；未切换网络、停用 WISP 或重启。'
