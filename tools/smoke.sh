#!/usr/bin/env bash
# 冒烟测试：无头启动一个导出的可执行文件，跑若干帧后退出。
# 通过条件：退出码为 0；日志里有启动标记 MUTSUKI_READY；没有脚本错误。
#   tools/smoke.sh <可执行文件>
set -euo pipefail

BIN="$1"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

set +e
"$BIN" --headless --quit-after 120 >"$LOG" 2>&1
code=$?
set -e
cat "$LOG"

fail() { echo "冒烟测试失败：$*" >&2; exit 1; }
[[ $code -eq 0 ]] || fail "退出码 $code"
grep -q "MUTSUKI_READY" "$LOG" || fail "没有看到启动标记 MUTSUKI_READY"
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load" "$LOG"; then
  fail "日志里有脚本或加载错误"
fi
echo "冒烟测试通过"
