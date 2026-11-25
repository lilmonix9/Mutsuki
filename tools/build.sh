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
#   ENGINE_DIR    自编译引擎（Godot + Voxel Tools）所在目录，默认 .cache/engine。
#                 需要 godot.linuxbsd.editor.x86_64、godot.linuxbsd.template_release.x86_64、
#                 godot.windows.template_release.x86_64(.console).exe。
#                 CI 由 engine 任务编译后传入；本地用 tools/build-engine.sh 编译。
#   SKIP_WINDOWS=1  本地没有 Windows 模板时跳过 Windows 导出（CI 不允许跳过）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=engine.env
source "$ROOT/tools/engine.env"

ENGINE_DIR="${ENGINE_DIR:-$ROOT/.cache/engine}"
GODOT="$ENGINE_DIR/godot.linuxbsd.editor.x86_64"
TEMPLATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION}.${GODOT_STATUS}"
APP="$ROOT/app"
OUT="$ROOT/build"

log() { printf '\n==> %s\n' "$*"; }

# 把自编译的模板按官方文件名装进 Godot 的模板目录，导出预设就不必写死路径。
step_setup() {
  log "准备自编译引擎（$ENGINE_DIR）"
  [[ -f "$GODOT" ]] || { echo "缺少 $GODOT。先运行：tools/build-engine.sh linux-editor $ENGINE_DIR" >&2; exit 1; }
  chmod +x "$ENGINE_DIR"/godot.linuxbsd.* 2>/dev/null || true
  rm -rf "$TEMPLATE_DIR"
  mkdir -p "$TEMPLATE_DIR"
  echo "${GODOT_VERSION}.${GODOT_STATUS}" > "$TEMPLATE_DIR/version.txt"
  install_template() { # 源文件名 模板文件名
    if [[ -f "$ENGINE_DIR/$1" ]]; then
      cp "$ENGINE_DIR/$1" "$TEMPLATE_DIR/$2"
    else
      echo "缺少模板：$ENGINE_DIR/$1" >&2
      return 1
    fi
  }
  install_template godot.linuxbsd.template_release.x86_64 linux_release.x86_64
  if [[ "${SKIP_WINDOWS:-}" != 1 ]]; then
    install_template godot.windows.template_release.x86_64.exe windows_release_x86_64.exe
    install_template godot.windows.template_release.x86_64.console.exe windows_release_x86_64_console.exe
  fi
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
  local expected=("$OUT/linux/Mutsuki.x86_64")
  if [[ "${SKIP_WINDOWS:-}" != 1 ]]; then
    "$GODOT" --headless --path "$APP" --export-release "Windows" "$OUT/windows/Mutsuki.exe"
    expected+=("$OUT/windows/Mutsuki.exe")
  fi
  for f in "${expected[@]}"; do
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
