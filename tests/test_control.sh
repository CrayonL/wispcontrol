#!/bin/sh
set -eu
umask 077
. "$(dirname "$0")/../wispcontrol/scripts/wisp_control_lib.sh"
select_wisp_paths
TEST_ROOT=/tmp/wisp-control-check.$$
mkdir "$TEST_ROOT"
SAVED=$TEST_ROOT/saved
TXN=$TEST_ROOT/transaction
mkdir "$SAVED" "$TXN"
trap 'rm -rf "$TEST_ROOT"' EXIT

nvram() {
    case "$1" in
        get) cat "$TEST_ROOT/channel";;
        set) printf '%s\n' "${2#wl0_channel=}" > "$TEST_ROOT/channel";;
        commit) [ ! -e "$TEST_ROOT/fail_commit" ];;
        *) return 1;;
    esac
}
sync() { return 0; }
must_reject() { if validate_profile "$1" "$2" "$3"; then echo 'Invalid input accepted'; exit 1; fi; }

# 标准配置，以及不会被 Shell 解释的引号、反斜线和命令替换字符。
write_profile 44454d4f31 6162636465666768 1 > "$SAVED/wpa.conf"
[ "$(profile_ssid "$SAVED/wpa.conf")" = 44454d4f31 ]
[ "$(profile_channel "$SAVED/wpa.conf")" = 1 ]
write_profile e4b8ade69687 6122625c6324642566286729 6 > "$TXN/candidate"
grep -F 'psk="a\"b\\c$d%f(g)"' "$TXN/candidate" >/dev/null
[ "$(profile_channel "$TXN/candidate")" = 6 ]
must_reject 00zz 6162636465666768 1
must_reject 44454d4f31 61626364 1
must_reject 44454d4f31 616263646566670a 1
must_reject 44454d4f31 6162636465666768 '1;reboot'
must_reject 44454d4f31 6162636465666768 0
printf '0\n' > "$TEST_ROOT/channel"
printf '0\n' > "$SAVED/original-channel"

# 更换网络保存上一份；回滚恢复当前配置、上一份和频道。
snapshot_config
apply_config connect
[ "$(profile_channel "$SAVED/wpa.conf")" = 6 ]
[ "$(profile_channel "$SAVED/wpa.previous.conf")" = 1 ]
[ "$(cat "$TEST_ROOT/channel")" = 6 ]
cp -p "$SAVED/wpa.previous.conf" "$TXN/candidate"
apply_config previous
[ "$(profile_channel "$SAVED/wpa.conf")" = 1 ]
[ "$(profile_channel "$SAVED/wpa.previous.conf")" = 6 ]
write_profile e4b8ade69687 6122625c6324642566286729 6 > "$TXN/candidate"
rollback_config
[ "$(profile_channel "$SAVED/wpa.conf")" = 1 ]
[ ! -e "$SAVED/wpa.previous.conf" ]
[ "$(cat "$TEST_ROOT/channel")" = 0 ]

# 停用/启用不删除 Wi-Fi，保存失败时可完整还原。
apply_config disable
[ -e "$SAVED/disabled" ] && [ -s "$SAVED/wpa.conf" ]
apply_config enable
[ ! -e "$SAVED/disabled" ] && [ "$(cat "$TEST_ROOT/channel")" = 1 ]
touch "$TEST_ROOT/fail_commit"
if apply_config connect; then echo 'Commit failure was ignored'; exit 1; fi
rm "$TEST_ROOT/fail_commit"
rollback_config
[ "$(profile_channel "$SAVED/wpa.conf")" = 1 ]
[ ! -e "$SAVED/wpa.previous.conf" ]
[ "$(cat "$TEST_ROOT/channel")" = 0 ]
echo 'PASS: validation, quoting, profile backup, enable/disable, failed commit rollback'
