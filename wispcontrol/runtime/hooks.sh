#!/bin/sh
set -eu
umask 077
runtime=/koolshare/wispcontrol
boot=/koolshare/init.d/V99wispcontrol.sh
nat=/koolshare/init.d/N99wispcontrol.sh
event=/jffs/scripts/firewall-start
line='[ ! -x /koolshare/wispcontrol/firewall.sh ] || /koolshare/wispcontrol/firewall.sh # wispcontrol'
owned='# Created by wispcontrol'

check_link() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        [ "$(readlink "$1")" = "$2" ] || { echo "启动项已被其他程序占用：$1" >&2; return 1; }
    fi
}

edit_event() {
    [ ! -L "$event" ] || { echo "自定义 firewall-start 是符号链接，请保留原脚本并检查挂钩" >&2; return 1; }
    if [ "$1" = install ] && [ -f "$event" ] && grep -Fqx "$line" "$event"; then return; fi
    if [ "$1" = remove ]; then
        [ -f "$event" ] && grep -Fqx "$line" "$event" || return 0
        if [ "$(cat "$event")" = "$(printf '%s\n' '#!/bin/sh' "$line" "$owned")" ]; then rm "$event"; return; fi
    fi
    scratch="$event.wispcontrol.$$"
    mkdir "$scratch"
    tmp="$scratch/hook"
    trap 'rm -f "$tmp"; rmdir "$scratch"' EXIT
    if [ -f "$event" ]; then
        cp -p "$event" "$tmp"
        awk -v line="$line" -v action="$1" '
            NR == 1 && action == "install" {
                if (/^#!/) { print; print line; next }
                print "#!/bin/sh"; print line
            }
            $0 != line { print }
            END { if (NR == 0 && action == "install") { print "#!/bin/sh"; print line } }
        ' "$event" > "$tmp"
    else
        printf '%s\n' '#!/bin/sh' "$line" "$owned" > "$tmp"
    fi
    chmod +x "$tmp"
    mv -f "$tmp" "$event"
}

check_link "$boot" "$runtime/boot.sh"
check_link "$nat" "$runtime/firewall.sh"
case "${1:-}" in
    install)
        mkdir -p /jffs/scripts
        edit_event install
        [ -L "$nat" ] || ln -s "$runtime/firewall.sh" "$nat"
        [ -L "$boot" ] || ln -s "$runtime/boot.sh" "$boot";;
    remove)
        edit_event remove
        rm -f "$boot" "$nat";;
    *) exit 1;;
esac
