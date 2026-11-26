#!/bin/sh
set -eu
umask 077
ROOT=$(cd "$(dirname "$0")" && pwd)
[ "$(nvram get productid)" = TUF-BE6500 ] || { echo '设备型号不匹配'; exit 1; }
. "$ROOT/scripts/wisp_control_lib.sh"
select_wisp_paths || { echo '发现两套 WISP 配置，请先确认开机脚本使用的目录'; exit 1; }
[ -x /usr/bin/jq ] && [ -d /koolshare/webs ] || exit 1
exec 9>"$CONTROL_PREFIX-control.lock"
flock -n 9 || { echo 'WISP 配置操作正在进行'; exit 1; }
external=0
if [ -x "$SAVED/restore.sh" ]; then
    [ -s "$SAVED/wpa.conf" ] || { echo '已有启动脚本的无线配置缺失，请先修复原环境'; exit 1; }
    external=1
elif [ "$SAVED" != /jffs/wispcontrol ]; then
    echo '旧 WISP 环境缺少启动脚本，请先检查原配置'
    exit 1
fi
version=$(cat "$ROOT/version")
if [ -s "$SAVED/wpa.conf" ]; then profile_channel "$SAVED/wpa.conf" >/dev/null || { echo '当前网络信道无法识别'; exit 1; }; fi
if [ "$external" = 0 ]; then
    [ -x /usr/bin/wpa_supplicant ] && [ -x /usr/bin/wpa_cli ] || { echo '缺少固件无线认证工具'; exit 1; }
    for tool in iw ip iptables udhcpc flock; do
        which "$tool" >/dev/null || { echo "缺少固件工具：$tool"; exit 1; }
    done
    if [ -e /koolshare/wispcontrol ] && [ ! -f /koolshare/wispcontrol/.managed ]; then
        echo '联网程序安装目录已被占用'; exit 1
    fi
    mkdir -p "$SAVED" /koolshare/wispcontrol
    chmod 700 "$SAVED" /koolshare/wispcontrol
    touch /koolshare/wispcontrol/.managed
    for file in "$ROOT"/runtime/*.sh; do
        dest=/koolshare/wispcontrol/${file##*/}
        cp "$file" "$dest.new" && chmod 700 "$dest.new" && mv -f "$dest.new" "$dest" || exit 1
    done
fi
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
if [ "$external" = 0 ]; then /koolshare/wispcontrol/hooks.sh install; fi
dbus set softcenter_module_wispcontrol_name=wispcontrol
dbus set softcenter_module_wispcontrol_title='WISP 无线上网'
dbus set softcenter_module_wispcontrol_description='让 TUF-BE6500 通过上级 2.4 GHz Wi-Fi 上网，支持首次配置和开机自动连接'
dbus set softcenter_module_wispcontrol_home_url=Module_wispcontrol.asp
dbus set "softcenter_module_wispcontrol_version=$version"
dbus set softcenter_module_wispcontrol_install=1
echo 'WISP 安装完成。首次使用请打开控制页，扫描并保存上级 Wi-Fi。'
