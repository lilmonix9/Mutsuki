extends Node3D
## P0 空场景：一片地面加几根标尺柱子（10 m / 100 m / 1 km），只用来感受飞行与尺度。
## 这里没有体素，也不是正式架构，P1 会重新搭建。

const MARKER_DISTANCES := [10.0, 100.0, 1000.0]

@onready var _camera: Camera3D = $FlyCamera
@onready var _info: Label = $HUD/Info


func _ready() -> void:
	_build_reference_scene()
	print("MUTSUKI_READY version=%s godot=%s" % [
		ProjectSettings.get_setting("application/config/version"),
		Engine.get_version_info().string,
	])
	_maybe_start_screenshots()


func _process(_delta: float) -> void:
	var p := _camera.global_position
	_info.text = "位置 (%.1f, %.1f, %.1f) m   速度 %.1f m/s   FPS %d\n点击窗口环视 · WASD 移动 · 空格/Ctrl 升降 · Shift 加速 · 滚轮调速 · R 回起点 · Esc 释放鼠标" % [
		p.x, p.y, p.z, _camera.speed, Engine.get_frames_per_second(),
	]


## 启动参数带 --screenshot-dir=<目录> 时进入截图模式（见 screenshot_runner.gd）。
func _maybe_start_screenshots() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot-dir="):
			var runner: Node = preload("res://scripts/screenshot_runner.gd").new()
			runner.out_dir = arg.trim_prefix("--screenshot-dir=")
			add_child(runner)
			return


func _build_reference_scene() -> void:
	var ground := PlaneMesh.new()
	ground.size = Vector2(4000, 4000)
	_add_mesh("Ground", ground, Vector3.ZERO, Color(0.36, 0.45, 0.33))

	var origin := BoxMesh.new()
	origin.size = Vector3.ONE
	_add_mesh("Origin", origin, Vector3(0, 0.5, 0), Color(0.9, 0.9, 0.9))

	# 沿 +X（红）与 -Z（蓝）放标尺柱子，柱高为距离的 1/10。
	for d in MARKER_DISTANCES:
		var h: float = maxf(d / 10.0, 1.0)
		var pillar := BoxMesh.new()
		pillar.size = Vector3(h / 10.0, h, h / 10.0)
		_add_mesh("X_%dm" % d, pillar, Vector3(d, h / 2.0, 0), Color(0.85, 0.3, 0.25))
		_add_mesh("Z_%dm" % d, pillar, Vector3(0, h / 2.0, -d), Color(0.25, 0.45, 0.85))


func _add_mesh(node_name: String, mesh: Mesh, pos: Vector3, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
