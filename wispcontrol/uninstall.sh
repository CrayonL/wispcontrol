#!/bin/sh
set -eu
umask 077
bin=/koolshare/wispcontrol
if [ -f "$bin/.managed" ]; then
    saved=/jffs/wispcontrol
    exec 6>/tmp/wispcontrol-control.lock
    flock -n 6 || { echo 'WISP 配置操作正在进行，请稍后卸载'; exit 1; }
    if [ -f "$saved/wpa.conf" ] && [ ! -e "$saved/disabled" ]; then
        . /koolshare/scripts/wisp_control_lib.sh
        channel=$(cat "$saved/original-channel")
        valid_channel "$channel" || exit 1
        nvram set "wl0_channel=$channel"
        nvram commit
    fi
    touch "$saved/disabled"
    "$bin/stop.sh"
    "$bin/hooks.sh" remove
    for script in boot restore firewall dhcp stop hooks; do rm -f "$bin/$script.sh"; done
    rm -f "$bin/.managed"
    rmdir "$bin"
fi
rm -f /koolshare/webs/Module_wispcontrol.asp /koolshare/res/wisp_control.js
rm -f /koolshare/res/icon-wispcontrol.svg /koolshare/res/icon-wispcontrol.png
rm -f /koolshare/scripts/wisp_control.sh /koolshare/scripts/wisp_control_lib.sh
for field in name title description home_url version install; do
    dbus remove "softcenter_module_wispcontrol_$field"
done
rm -f /koolshare/scripts/uninstall_wispcontrol.sh
echo '插件已卸载，已保存的无线配置保留。独立安装的旧版联网脚本继续由原启动项管理。'
