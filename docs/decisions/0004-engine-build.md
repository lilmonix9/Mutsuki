# 0004 · 自编译引擎：Godot 4.7.2 + Voxel Tools 1.7（C++ 模块）

- 日期：2026-11-25
- 状态：采用（P0 期间；P0 结束时随最终选型复核）
- 关联：0001（引擎暂定）、0002（构建流水线，本篇取代其中「用官方二进制与模板」一项）

## 选了什么

- **Voxel Tools 以 C++ 模块编进引擎**，不用 GDExtension 版。理由：
  - 模块版是作者的主要开发形态，测试最充分；GDExtension 版官方说明「测试较少、可能有 bug」，且缺 FastNoise2。
  - **双精度只有模块版做得到**：GDExtension 跑在官方单精度引擎上；而大世界坐标稳定是锁定的产品要求。
  - 代价是要自己编译编辑器和导出模板，由 CI 承担。
- **版本固定在 `tools/engine.env`**：Godot `4.7.2-stable`（提交 ed1daf0bf）、Voxel Tools `v1.7`（提交 2ac9f5f8）。这正是 Voxel Tools 1.7 自己 CI 所用的组合（含 Float64 编辑器），不是我们自行拼凑。
- **Linux 用 Godot 官方 buildroot 工具链**（与 Voxel Tools 上游相同）：自带编译器与旧版 glibc，产物能在较老的发行版上运行。下载包 SHA-256 已固定。Windows 在 windows-2025 上用 MSVC 编译，SCons 版本与 buildroot 一致（4.11.1）。
- **编译四个变体**：Linux 编辑器（单精度）、Linux 编辑器（双精度）、Linux 发布模板、Windows 发布模板。脚本 `tools/build-engine.sh`，本地与 CI 共用。
- **按版本缓存**：缓存键是 `engine.env` 与 `build-engine.sh` 的哈希，版本不变就不重编。
- **自编译模板按官方文件名装进 Godot 的模板目录**，导出预设不用写死路径。
- **主构建暂用单精度**。双精度编辑器单独跑全部测试，并断言双精度真的生效。是否切到双精度，由「大世界坐标精度」实验决定。

- **包含屏幕阅读器支持（AccessKit）**，与官方发布版一致；用 Godot 源码自带的脚本安装，版本由源码固定。

## 暂不做

- Windows 上的 ANGLE（OpenGL 兼容层）与 Direct3D 12（`d3d12=no`）：Forward+ 走 Vulkan，用不到。兼容渲染器若成为核显方案再加。
- 调试版模板、双精度导出模板：目前没有用途，需要时加一个矩阵项即可。
- 编译期警告当错误（`werror`）：那是上游开发者的检查，我们不改引擎源码。

## 风险

- 首次编译慢（每个变体约 30–60 分钟）；改动 `engine.env` 都会触发全部重编。
- Actions 缓存 7 天不用会被清除，届时自动重编，不影响正确性。
