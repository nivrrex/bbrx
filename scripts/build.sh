#!/bin/sh
# 对当前运行内核构建并自检
set -eu
cd "$(dirname "$0")/.."
make
[ -f tcp_bbrx.ko ] || { echo "构建失败：没有 tcp_bbrx.ko"; exit 1; }
modinfo ./tcp_bbrx.ko | grep -E '^name|^vermagic'
echo "OK: $(pwd)/tcp_bbrx.ko"
