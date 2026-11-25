extends SceneTree
## 无头自动测试入口：godot --headless --path app -s res://tests/run_tests.gd [-- --expect-double]
## 任一检查失败则以退出码 1 结束。
## --expect-double：断言引擎是双精度编译（precision=double），用于双精度编辑器的测试。

var _failures := 0
var _checks := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://main.tscn")
	_check(scene != null, "main.tscn 能加载")
	var main: Node = scene.instantiate()
	root.add_child(main)
	await process_frame

	var cam: Camera3D = main.get_node("FlyCamera")
	_check(cam != null and cam.has_method("step"), "场景里有飞行相机")
	_check(main.get_node_or_null("Ground") != null, "参照地面已生成")
	_check(main.get_node_or_null("X_1000m") != null, "1 km 标尺已生成")

	_test_camera(cam)
	_test_voxel_module()
	_test_precision()

	print("测试：%d 项检查，%d 项失败" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_camera(cam: Camera3D) -> void:
	cam.reset()
	var start := cam.position

	# 向前飞 1 秒：沿 -Z 前进 speed 米。
	cam.step(Vector3(0, 0, -1), 1.0, false)
	_near(cam.position, start + Vector3(0, 0, -cam.speed), "向前飞 1 秒移动 speed 米")

	# 加速。
	cam.reset()
	cam.step(Vector3(0, 0, -1), 1.0, true)
	_near(cam.position, start + Vector3(0, 0, -cam.speed * cam.boost_multiplier), "Shift 加速倍数正确")

	# 上升不受朝向影响。
	cam.reset()
	cam.apply_look(Vector2(300, 0))
	cam.step(Vector3(0, 1, 0), 1.0, false)
	_near(cam.position, start + Vector3(0, cam.speed, 0), "上升始终沿世界竖直方向")

	# 左转 90° 后向前飞，应沿 -X 前进。
	cam.reset()
	cam.apply_look(Vector2(-PI / 2.0 / cam.mouse_sensitivity, 0))
	cam.step(Vector3(0, 0, -1), 1.0, false)
	_near(cam.position, start + Vector3(-cam.speed, 0, 0), "转向后沿视线方向前进")

	# 斜向移动不比直线快。
	cam.reset()
	cam.step(Vector3(1, 0, -1), 1.0, false)
	_check(absf(cam.position.distance_to(start) - cam.speed) < 1e-3, "斜向移动速度已归一化")

	# 俯仰角限制，不翻转。
	cam.reset()
	cam.apply_look(Vector2(0, -100000))
	_check(cam.rotation.x <= deg_to_rad(89.0) + 1e-5, "仰角不超过 89°")
	cam.apply_look(Vector2(0, 100000))
	_check(cam.rotation.x >= -deg_to_rad(89.0) - 1e-5, "俯角不超过 89°")

	# 调速有上下限。
	cam.reset()
	for i in 200:
		cam.adjust_speed(0.5)
	_check(is_equal_approx(cam.speed, cam.MIN_SPEED), "速度下限")
	for i in 200:
		cam.adjust_speed(2.0)
	_check(is_equal_approx(cam.speed, cam.MAX_SPEED), "速度上限")

	# 回到起点。
	cam.position += Vector3(123, 45, 6)
	cam.reset()
	_near(cam.position, start, "R 回到起点")
	_check(is_equal_approx(cam.speed, cam.base_speed), "R 恢复基础速度")


## Voxel Tools 是否编进了引擎、能否真的编辑与生成网格。
## 用 ClassDB 动态访问：模块缺失时这里报「失败」，而不是整个脚本解析出错。
func _test_voxel_module() -> void:
	for cls in ["VoxelBuffer", "VoxelTool", "VoxelMesherTransvoxel", "VoxelLodTerrain", "VoxelTerrain"]:
		_check(ClassDB.class_exists(cls), "Voxel Tools 类可用：%s" % cls)
	if not ClassDB.class_exists("VoxelBuffer"):
		return

	var sdf: int = ClassDB.class_get_integer_constant("VoxelBuffer", "CHANNEL_SDF")
	var depth32: int = ClassDB.class_get_integer_constant("VoxelBuffer", "DEPTH_32_BIT")
	var buf: Object = ClassDB.instantiate("VoxelBuffer")
	buf.create(16, 16, 16)
	buf.set_channel_depth(sdf, depth32)
	buf.fill_f(1.0, sdf)  # 全是空气（SDF > 0）

	var vt: Object = buf.get_voxel_tool()
	vt.channel = sdf
	vt.mode = ClassDB.class_get_integer_constant("VoxelTool", "MODE_ADD")
	vt.do_sphere(Vector3(8, 8, 8), 5.0)
	_check(vt.get_voxel_f(Vector3i(8, 8, 8)) < 0.0, "体素：球心在实体内（SDF < 0）")
	_check(vt.get_voxel_f(Vector3i(1, 1, 1)) > 0.0, "体素：角落仍是空气（SDF > 0）")

	var mesher: Object = ClassDB.instantiate("VoxelMesherTransvoxel")
	var mesh: Mesh = mesher.build_mesh(buf, [])
	_check(mesh != null and mesh.get_surface_count() > 0, "体素：Transvoxel 生成了网格")
	if mesh != null and mesh.get_surface_count() > 0:
		var size := mesh.get_aabb().size
		_check(absf(size.x - 10.0) < 1.5 and absf(size.y - 10.0) < 1.5 and absf(size.z - 10.0) < 1.5,
			"体素：半径 5 的球，网格包围盒约 10×10×10（实际 %s）" % size)


## 浮点精度：双精度下，1e7 m 处仍能分辨 1 mm；单精度下不能。
func _test_precision() -> void:
	var is_double := _engine_is_double()
	print("  信息  引擎精度：%s" % ("double" if is_double else "single"))
	if "--expect-double" in OS.get_cmdline_user_args():
		_check(is_double, "引擎是双精度编译")
		var far := Vector3(1.0e7, 0, 0) + Vector3(0.001, 0, 0)
		_check(absf((far.x - 1.0e7) - 0.001) < 1e-6, "双精度：距原点 10 000 km 处保留 1 mm 的位移")
		var t := Transform3D(Basis(), Vector3(1.0e6, 0, 1.0e6))
		var p := t * Vector3(0.0039, 0, 0)  # 约 3.9 mm，项目书茶杯的局部精度
		_check(absf((p.x - 1.0e6) - 0.0039) < 1e-6, "双精度：距原点 1000 km 处的局部变换保留 3.9 mm")


static func _engine_is_double() -> bool:
	return (Vector3(1.0e7, 0, 0) + Vector3(0.001, 0, 0)).x != 1.0e7


func _near(actual: Vector3, expected: Vector3, label: String) -> void:
	_check(actual.distance_to(expected) < 1e-3, "%s（实际 %s，期望 %s）" % [label, actual, expected])


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  通过  ", label)
	else:
		_failures += 1
		printerr("  失败  ", label)
