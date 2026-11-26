#!/bin/sh
# services-start 须及时返回；无线硬件的就绪等待在后台执行。
if [ -s /jffs/wispcontrol/wpa.conf ] && [ ! -e /jffs/wispcontrol/disabled ]; then
    umask 077
    nohup /koolshare/wispcontrol/restore.sh > /tmp/wispcontrol-boot.log 2>&1 </dev/null &
fi
