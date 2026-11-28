#!/usr/bin/env bash
# 远坐标测试（app/tests/far_coords_test.gd）：在距原点 1000 km 处放置并拾取体素。
#
#   tools/far_test.sh <Godot 编辑器> double   双精度：必须全部通过，且日志确认 precision=double、voxel=true
#   tools/far_test.sh <Godot 编辑器> single   单精度（反向对照）：对照组必须通过、远处必须失败。
#                                            单精度若也通过，说明测试不够灵敏，判为失败。
set -euo pipefail

GODOT="$1"
EXPECT="$2"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

set +e
timeout 600 "$GODOT" --headless --path "$ROOT/app" -s res://tests/far_coords_test.gd >"$LOG" 2>&1
code=$?
set -e
grep -vE "^\s*$" "$LOG"

fail() { echo "远坐标测试判定失败：$*" >&2; exit 1; }
grep -q "MUTSUKI_FAR_TEST precision=$EXPECT voxel=true" "$LOG" \
  || fail "引擎不是预期的 $EXPECT 精度，或没有 Voxel Tools"
case "$EXPECT" in
  double)
    [[ $code -eq 0 ]] || fail "双精度应全部通过，退出码 $code（1 = 远处失败，2 = 对照组失败）" ;;
  single)
    [[ $code -eq 1 ]] || fail "单精度应「对照组通过、远处失败」（退出码 1），实际 $code" ;;
  *) fail "未知期望：$EXPECT" ;;
esac
echo "远坐标测试判定通过（$EXPECT）"
