#!/usr/bin/env bash
# 构建脚本：本地与 CI 共用同一套步骤。
#
#   tools/build.sh            setup → import → test → export → smoke（全部）
#   tools/build.sh <步骤...>  只跑指定步骤，例如 tools/build.sh setup test
#
# 环境变量：
#   GODOT_CACHE   Godot 编辑器与导出模板的缓存目录（默认 .cache/godot）
#   GODOT_TPZ     已下载的导出模板 .tpz 路径（可选，省去下载）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=godot-version.env
source "$ROOT/tools/godot-version.env"

TAG="${GODOT_VERSION}-${GODOT_STATUS}"
CACHE="${GODOT_CACHE:-$ROOT/.cache/godot}/$TAG"
GODOT="$CACHE/Godot_v${TAG}_linux.x86_64"
TEMPLATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION}.${GODOT_STATUS}"
BASE_URL="https://github.com/godotengine/godot/releases/download/${TAG}"
APP="$ROOT/app"
OUT="$ROOT/build"

log() { printf '\n==> %s\n' "$*"; }

download_verified() { # url dest sha512
  local url="$1" dest="$2" sum="$3"
  if [[ ! -f "$dest" ]]; then
    curl -fL --retry 4 --retry-delay 5 -o "$dest.part" "$url"
    mv "$dest.part" "$dest"
  fi
  echo "$sum  $dest" | sha512sum -c - || { rm -f "$dest"; echo "校验失败：$dest" >&2; exit 1; }
}

step_setup() {
  log "准备 Godot $TAG"
  mkdir -p "$CACHE"
  if [[ ! -x "$GODOT" ]]; then
    local zip="$CACHE/editor.zip"
    download_verified "$BASE_URL/Godot_v${TAG}_linux.x86_64.zip" "$zip" "$GODOT_EDITOR_SHA512"
    unzip -o -q "$zip" -d "$CACHE"
    rm -f "$zip"
    chmod +x "$GODOT"
  fi
  # 只解出需要的导出模板（Linux x86_64 与 Windows x86_64），完整包有 1.3 GB。
  if [[ ! -f "$CACHE/templates/version.txt" ]]; then
    local tpz="${GODOT_TPZ:-$CACHE/templates.tpz}"
    download_verified "$BASE_URL/Godot_v${TAG}_export_templates.tpz" "$tpz" "$GODOT_TEMPLATES_SHA512"
    unzip -o -q "$tpz" -d "$CACHE" \
      'templates/version.txt' \
      'templates/linux_*.x86_64' \
      'templates/windows_*_x86_64*.exe'
    [[ -z "${GODOT_TPZ:-}" ]] && rm -f "$tpz"
  fi
  mkdir -p "$(dirname "$TEMPLATE_DIR")"
  rm -rf "$TEMPLATE_DIR"
  ln -s "$CACHE/templates" "$TEMPLATE_DIR"
  "$GODOT" --version
}

step_import() {
  log "导入项目资源"
  "$GODOT" --headless --path "$APP" --import
}

step_test() {
  log "运行自动测试"
  "$GODOT" --headless --path "$APP" -s res://tests/run_tests.gd
}

step_export() {
  log "导出 Linux 与 Windows 版"
  rm -rf "$OUT"
  mkdir -p "$OUT/linux" "$OUT/windows"
  "$GODOT" --headless --path "$APP" --export-release "Linux" "$OUT/linux/Mutsuki.x86_64"
  "$GODOT" --headless --path "$APP" --export-release "Windows" "$OUT/windows/Mutsuki.exe"
  for f in "$OUT/linux/Mutsuki.x86_64" "$OUT/windows/Mutsuki.exe"; do
    [[ -s "$f" ]] || { echo "导出失败：缺少 $f" >&2; exit 1; }
  done
  cp "$ROOT/tools/README-dist.txt" "$OUT/linux/README.txt"
  cp "$ROOT/tools/README-dist.txt" "$OUT/windows/README.txt"
  ls -la "$OUT"/*
}

step_smoke() {
  log "冒烟测试：无头启动导出的 Linux 版"
  "$ROOT/tools/smoke.sh" "$OUT/linux/Mutsuki.x86_64"
}

steps=("$@")
[[ ${#steps[@]} -eq 0 ]] && steps=(setup import test export smoke)
for s in "${steps[@]}"; do
  case "$s" in
    setup|import|test|export|smoke) "step_$s" ;;
    *) echo "未知步骤：$s" >&2; exit 2 ;;
  esac
done
