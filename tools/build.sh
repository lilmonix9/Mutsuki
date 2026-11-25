#!/usr/bin/env bash
# 构建脚本：本地与 CI 共用同一套步骤。
#
#   tools/build.sh            setup → import → test → export → smoke → render（全部）
#   tools/build.sh <步骤...>  只跑指定步骤，例如 tools/build.sh setup test
#   tools/build.sh update-baselines
#                             把 build/screenshots 复制为新的基准图。只在逐张看过截图、确认画面正确后使用。
#
# render 步骤需要 Xvfb 与 Mesa 的 Vulkan 软件驱动（Ubuntu：apt install xvfb mesa-vulkan-drivers）。
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

# 软件渲染截图测试：用 Mesa lavapipe（CPU 上的 Vulkan）运行导出的 Linux 版，
# 在固定机位截图，再做语义检查与基准图比对（见 app/tests/compare_images.gd）。
LVP_ICD="${LVP_ICD:-/usr/share/vulkan/icd.d/lvp_icd.json}"
BASELINES="$APP/tests/render_baselines"

step_render() {
  log "软件渲染截图测试（Mesa lavapipe）"
  [[ -f "$LVP_ICD" ]] || { echo "找不到 lavapipe 驱动：$LVP_ICD（apt install mesa-vulkan-drivers）" >&2; exit 1; }
  local shots="$OUT/screenshots" diff="$OUT/screenshot-diff" logf="$OUT/render.log"
  rm -rf "$shots" "$diff"
  mkdir -p "$shots"
  VK_DRIVER_FILES="$LVP_ICD" VK_ICD_FILENAMES="$LVP_ICD" \
    xvfb-run -a -s "-screen 0 1280x720x24" \
    "$OUT/linux/Mutsuki.x86_64" --resolution 1280x720 --audio-driver Dummy \
    -- --screenshot-dir="$shots" 2>&1 | tee "$logf"
  # 确认真的走了软件渲染与 Forward+，而不是悄悄换成别的设备或渲染器。
  grep -q "Forward+ - Using Device .*llvmpipe" "$logf" \
    || { echo "渲染设备不是 lavapipe/llvmpipe 上的 Forward+" >&2; exit 1; }
  "$GODOT" --headless --path "$APP" -s res://tests/compare_images.gd -- \
    --actual="$shots" --baseline="$BASELINES" --diff="$diff"
}

step_update-baselines() {
  log "用 build/screenshots 更新基准图"
  ls "$OUT"/screenshots/*.png >/dev/null
  cp "$OUT"/screenshots/*.png "$BASELINES/"
  git -C "$ROOT" status --short "$BASELINES"
  echo "提交前请逐张查看新基准图，并在提交说明里写明画面为什么变了。"
}

steps=("$@")
[[ ${#steps[@]} -eq 0 ]] && steps=(setup import test export smoke render)
for s in "${steps[@]}"; do
  case "$s" in
    setup|import|test|export|smoke|render|update-baselines) "step_$s" ;;
    *) echo "未知步骤：$s" >&2; exit 2 ;;
  esac
done
