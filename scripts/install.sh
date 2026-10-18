#!/bin/sh
# 失败安全的持久化安装：insmod 成功才设 CC；失败保持现有 CC
set -eu
KO_SRC="$(cd "$(dirname "$0")/.." && pwd)/tcp_bbrx.ko"
DEST=/opt/bbrx
[ "$(id -u)" -eq 0 ] || { echo "需要 root"; exit 1; }
[ -f "$KO_SRC" ] || { echo "先跑 scripts/build.sh"; exit 1; }
mkdir -p "$DEST"; cp -f "$KO_SRC" "$DEST/tcp_bbrx.ko"
[ -f /etc/rc.local ] && cp -f /etc/rc.local "$DEST/rc.local.bak-$(date +%Y%m%d_%H%M%S)"
OLD=$(sysctl -n net.ipv4.tcp_congestion_control)
insmod "$DEST/tcp_bbrx.ko" 2>/dev/null || true
if grep -qw bbrx /proc/sys/net/ipv4/tcp_available_congestion_control; then
    sysctl -qw net.ipv4.tcp_congestion_control=bbrx
    echo "已启用 bbrx（原 CC=$OLD；回滚: sysctl -w net.ipv4.tcp_congestion_control=$OLD）"
else
    echo "模块加载失败，保持 $OLD（未做任何更改）"; exit 1
fi
if [ -f /etc/rc.local ] && ! grep -q bbrx /etc/rc.local; then
    sed -i "s#^exit 0#insmod $DEST/tcp_bbrx.ko 2>/dev/null \&\& sysctl -qw net.ipv4.tcp_congestion_control=bbrx || true\nexit 0#" /etc/rc.local
    echo "已写入 /etc/rc.local（失败安全）"
fi
