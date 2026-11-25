extends Node
## 截图模式：用于软件渲染回归测试。
## 启动参数（放在 -- 之后）：--screenshot-dir=<目录>
## 依次把相机放到固定机位，等画面稳定后保存 PNG，全部完成后退出。
## 截图期间隐藏 HUD（FPS 等数字每次都不同，会干扰比对）。

## 固定机位：名称 → [相机位置, 注视点]。改动机位须同步更新基准图。
const VIEWS := {
	"start": [Vector3(0, 2, 8), Vector3(0, 2, 0)],
	"overview": [Vector3(220, 160, 220), Vector3(0, 0, 0)],
	"pillar_1km": [Vector3(960, 60, 60), Vector3(1000, 50, 0)],
}
const SETTLE_FRAMES := 30

var out_dir := ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var main := get_parent()
	var cam: Camera3D = main.get_node("FlyCamera")
	cam.set_process(false)
	cam.set_process_unhandled_input(false)
	main.get_node("HUD").visible = false

	for view_name in VIEWS:
		var v: Array = VIEWS[view_name]
		cam.position = v[0]
		cam.look_at(v[1], Vector3.UP)
		for i in SETTLE_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := out_dir.path_join("%s.png" % view_name)
		var err := img.save_png(path)
		if err != OK:
			printerr("MUTSUKI_SCREENSHOT_FAILED %s err=%d" % [path, err])
			get_tree().quit(1)
			return
		print("MUTSUKI_SCREENSHOT %s %dx%d" % [path, img.get_width(), img.get_height()])
	get_tree().quit(0)
