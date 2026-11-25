#!/usr/bin/env bash
# 从源码编译 Godot + Voxel Tools。本地与 CI 共用。
#
#   tools/build-engine.sh <名称> <输出目录>
#
# 名称：
#   linux-editor          Linux 编辑器（单精度）：导入、测试、导出都用它
#   linux-editor-double   Linux 编辑器（双精度）：用于双精度实验与测试
#   linux-template        Linux 发布模板（单精度）
#   windows-template      Windows 发布模板（单精度），只能在 Windows 上用 MSVC 编译
#
# 环境变量：ENGINE_WORK（源码与工具链目录，默认 .cache/engine-work）、SCONS_JOBS
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=engine.env
source "$ROOT/tools/engine.env"

NAME="${1:?用法：build-engine.sh <名称> <输出目录>}"
OUTDIR="${2:?用法：build-engine.sh <名称> <输出目录>}"
WORK="${ENGINE_WORK:-$ROOT/.cache/engine-work}"
JOBS="${SCONS_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

case "$NAME" in
  linux-editor)        PLATFORM=linuxbsd; TARGET=editor;           PRECISION=single ;;
  linux-editor-double) PLATFORM=linuxbsd; TARGET=editor;           PRECISION=double ;;
  linux-template)      PLATFORM=linuxbsd; TARGET=template_release; PRECISION=single ;;
  windows-template)    PLATFORM=windows;  TARGET=template_release; PRECISION=single ;;
  *) echo "未知名称：$NAME" >&2; exit 2 ;;
esac

log() { printf '\n==> %s\n' "$*"; }
mkdir -p "$WORK" "$OUTDIR"
SRC="$WORK/godot"

log "获取源码：Godot $GODOT_VERSION ($GODOT_COMMIT) + Voxel Tools $VOXEL_VERSION ($VOXEL_COMMIT)"
fetch_commit() { # dir url commit
  local dir="$1" url="$2" commit="$3"
  if [[ "$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)" != "$commit" ]]; then
    rm -rf "$dir"
    git init -q "$dir"
    git -C "$dir" fetch -q --depth 1 "$url" "$commit"
    git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
  fi
  [[ "$(git -C "$dir" rev-parse HEAD)" == "$commit" ]] || { echo "源码版本不符：$dir" >&2; exit 1; }
}
fetch_commit "$SRC" https://github.com/godotengine/godot.git "$GODOT_COMMIT"
fetch_commit "$SRC/modules/voxel" https://github.com/Zylann/godot_voxel.git "$VOXEL_COMMIT"

if [[ "$PLATFORM" == linuxbsd ]]; then
  BR="$WORK/x86_64-godot-linux-gnu_sdk-buildroot"
  if [[ ! -x "$BR/bin/scons" ]]; then
    log "获取 Linux 工具链（buildroot）"
    curl -fL --retry 4 --retry-delay 5 -o "$WORK/buildroot.tar.bz2" "$BUILDROOT_URL"
    echo "$BUILDROOT_SHA256  $WORK/buildroot.tar.bz2" | sha256sum -c -
    tar -xjf "$WORK/buildroot.tar.bz2" -C "$WORK"
    rm -f "$WORK/buildroot.tar.bz2"
    (cd "$BR" && ./relocate-sdk.sh)
  fi
  export PATH="$BR/bin:$PATH"
fi

log "编译 $NAME（platform=$PLATFORM target=$TARGET precision=$PRECISION，$JOBS 线程）"
cd "$SRC"
scons platform="$PLATFORM" target="$TARGET" precision="$PRECISION" \
  production=yes tests=no debug_symbols=no -j"$JOBS"

suffix=""; [[ "$PRECISION" == double ]] && suffix=".double"
case "$PLATFORM" in
  linuxbsd) files=("godot.linuxbsd.$TARGET$suffix.x86_64") ;;
  windows)  files=("godot.windows.$TARGET$suffix.x86_64.exe" "godot.windows.$TARGET$suffix.x86_64.console.exe") ;;
esac
for f in "${files[@]}"; do
  [[ -s "bin/$f" ]] || { echo "编译产物缺失：bin/$f" >&2; ls -la bin >&2; exit 1; }
  cp "bin/$f" "$OUTDIR/"
done
ls -la "$OUTDIR"
