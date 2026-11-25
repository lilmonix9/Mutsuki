# 渲染基准图

软件渲染（Mesa lavapipe，Ubuntu 24.04）下各固定机位的参考截图，由 `tools/build.sh render` 比对。
机位定义在 `app/scripts/screenshot_runner.gd`，语义检查与阈值在 `app/tests/compare_images.gd`。

更新规则：

- 只有画面**按预期**变化时才更新（改了场景、机位、光照、Mesa 版本等）。
- 更新前逐张查看 `build/screenshots/`，确认画面正确；用 `tools/build.sh update-baselines` 复制，提交说明写明为什么变。
- 不得为了让测试通过而更新基准图。

`.gdignore` 让 Godot 不把这些图片导入为资源。
