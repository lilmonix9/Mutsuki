extends SceneTree
## 无头自动测试入口：godot --headless --path app -s res://tests/run_tests.gd
## 任一检查失败则以退出码 1 结束。

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


func _near(actual: Vector3, expected: Vector3, label: String) -> void:
	_check(actual.distance_to(expected) < 1e-3, "%s（实际 %s，期望 %s）" % [label, actual, expected])


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  通过  ", label)
	else:
		_failures += 1
		printerr("  失败  ", label)
