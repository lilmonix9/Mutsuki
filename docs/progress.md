# 进度

## 当前阶段

**P0 · 云端基础与技术实验** —— 云端基础进行中，技术实验尚未开始。

## 已完成

- 2026-11-25 项目书 Draft 0.4 存入 `docs/vision.md`。
- 2026-11-25 项目记忆文件：`AGENTS.md`、`docs/decisions/`、`progress.md`、`to-experience.md`、`backlog.md`、`docs/format/`。
- 2026-11-25 决策 0001（引擎暂定 Godot 4 + Voxel Tools）、0002（构建流水线）。
- 2026-11-25 P0 空场景（`app/`）：地面、10 m / 100 m / 1 km 标尺、自由飞行相机、HUD。不含任何体素代码。
- 2026-11-25 构建流水线：`tools/build.sh` 与 `.github/workflows/build.yml`。导出 Linux 与 Windows 便携版，作为 Actions artifact 上传。
  - **云端已通过**（2026-11-25，Actions run #1 `45624670276`，提交 `af510d1`）：15 项无头测试通过；Linux 与 Windows 导出成功；两个平台的冒烟测试都通过（Windows 在 windows-2025 上实际启动并输出 `MUTSUKI_READY`）。产物 `Mutsuki-linux-x86_64`、`Mutsuki-windows-x86_64` 可在该 run 的 Artifacts 下载。

## 进行中

无。

## 下一步（按顺序）

1. **软件渲染测试环境**（P0 云端基础的剩余部分）：CI 里用 Mesa lavapipe/llvmpipe 跑真实渲染，固定机位截图，作为以后截图比对的基础。
2. **接入 Voxel Tools 的构建**：在 CI 里编译带 Voxel Tools 模块的 Godot 4.7.2 编辑器与导出模板，同时试双精度（`precision=double`），回答项目书第 8 节的待确认项。
3. **第一项实验：多精度体素的真实编辑与存储**，重点回答「Voxel Tools 的渲染 LOD 是否等同于多分辨率编辑与存储」。

## 已知问题

- Actions 警告：`actions/checkout@v4` 等基于 Node.js 20，已被强制跑在 Node.js 24 上；目前不影响结果，见 backlog。
- Actions artifact 默认只保留 90 天，长期保存要靠 GitHub Releases（见 backlog）。
- 冒烟测试为无头模式，不经过渲染器（见决策 0002）。
- `docs/vision.md` 第 7 节「第 2 t节」有一个多余的 t，原样保留，等产品负责人确认是否修改。
