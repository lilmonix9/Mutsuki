# 进度

## 当前阶段

**P0 · 云端基础与技术实验** —— 云端基础进行中，技术实验尚未开始。

## 已完成

- 2026-11-25 项目书 Draft 0.4 存入 `docs/vision.md`。
- 2026-11-25 项目记忆文件：`AGENTS.md`、`docs/decisions/`、`progress.md`、`to-experience.md`、`backlog.md`、`docs/format/`。
- 2026-11-25 决策 0001（引擎暂定 Godot 4 + Voxel Tools）、0002（构建流水线）。
- 2026-11-25 P0 空场景（`app/`）：地面、10 m / 100 m / 1 km 标尺、自由飞行相机、HUD。不含任何体素代码。
- 2026-11-25 构建流水线：`tools/build.sh` 与 `.github/workflows/build.yml`。导出 Linux 与 Windows 便携版，作为 Actions artifact 上传。
  - **本地**已完整跑通：15 项无头测试通过，两个平台导出成功，Linux 版冒烟测试通过。
  - **云端尚未运行过**：仓库推送被拒（GitHub 403，Claude GitHub App 对本仓库没有权限），见下方已知问题。Windows 冒烟测试只在 CI 里跑，所以目前也还没验证过。

## 进行中

无。

## 下一步（按顺序）

1. **等 GitHub 权限修好后**：推送，确认 Actions 两个 job 都通过、产物可下载。这一步通过之前，P0 的「云端自动产出便携版」不算过关。
2. **软件渲染测试环境**（P0 云端基础的剩余部分）：CI 里用 Mesa lavapipe/llvmpipe 跑真实渲染，固定机位截图，作为以后截图比对的基础。
3. **接入 Voxel Tools 的构建**：在 CI 里编译带 Voxel Tools 模块的 Godot 4.7.2 编辑器与导出模板，同时试双精度（`precision=double`），回答项目书第 8 节的待确认项。
4. **第一项实验：多精度体素的真实编辑与存储**，重点回答「Voxel Tools 的渲染 LOD 是否等同于多分辨率编辑与存储」。

## 已知问题

- **推送被拒**：`git push` 返回 403，「Claude doesn't have GitHub access to lilmonix9/Mutsuki」。需要产品负责人在 https://claude.ai/connect-github 重新连接 GitHub，并确认 Claude GitHub App 已安装到本仓库。本地提交已就绪，等待推送。
- 冒烟测试为无头模式，不经过渲染器（见决策 0002）。
- `docs/vision.md` 第 7 节「第 2 t节」有一个多余的 t，原样保留，等产品负责人确认是否修改。
