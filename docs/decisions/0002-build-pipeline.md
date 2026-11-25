# 0002 · 构建流水线与 P0 空场景

- 日期：2026-11-25
- 状态：采用

## 选了什么

- **Godot 4.7.2-stable**，版本与 SHA-512 校验值固定在 `tools/godot-version.env`。理由：这是写作时 Voxel Tools（v1.7）自己 CI 构建所用的 Godot 版本，以后接入 Voxel Tools 时不必再换版本。
- 本次用**官方二进制和官方导出模板**。接入 Voxel Tools 后很可能要换成自编译的编辑器和模板（见 0001 风险 2），届时另写决策。
- **一个脚本 `tools/build.sh`**，本地和 CI 跑同样的步骤：setup → import → test → export → smoke。CI 只是调用它，避免两套逻辑分叉。
- **单文件便携版**：PCK 嵌入可执行文件（`embed_pck`），解压即运行，不做安装包。Windows 额外带 `Mutsuki.console.exe`（命令行包装），方便看日志和做冒烟测试。
- **测试**：无头 GDScript 测试（`app/tests/`）检查场景加载和相机移动逻辑；导出后在 Linux 与 Windows 上各自无头启动一次（冒烟测试），确认导出产物能跑起来。
- **渲染器**：先用 Godot 默认的 Forward+。核显上是否改用 Mobile 或 Compatibility 渲染器，留给 P0 的性能实验决定。
- **工作名 Mutsuki**（即仓库名）。项目名称仍是待确认项，正式命名后统一替换。

## 放弃了什么

- 第三方的 Godot CI Docker 镜像或 Action：省事，但多一层不受控的依赖，且以后要换自编译引擎时反而碍事。
- 安装包（NSIS 等）：P0 只需要便携版，项目书允许「便携版或安装包」。

## 尚未覆盖

- 软件渲染（Mesa llvmpipe/lavapipe）截图测试：本次冒烟测试是无头模式，不经过渲染器，只能证明「能启动」，不能证明「画得出」。属于 P0 云端基础的剩余部分。
- macOS：不在目标平台内。
