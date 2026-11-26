#!/bin/sh
set -eu
# 仅移除控制页；上网脚本、上级密码和当前 WISP 状态均保留。
rm -f /koolshare/webs/Module_wispcontrol.asp /koolshare/res/wisp_control.js
rm -f /koolshare/res/icon-wispcontrol.svg /koolshare/res/icon-wispcontrol.png
rm -f /koolshare/scripts/wisp_control.sh /koolshare/scripts/wisp_control_lib.sh
for field in name title description home_url version install; do
    dbus remove "softcenter_module_wispcontrol_$field"
done
rm -f /koolshare/scripts/uninstall_wispcontrol.sh
echo '已移除控制页；WISP 运行状态未改变。'
