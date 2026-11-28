extends SceneTree
## 远坐标测试：在距原点 1000 km 处放置体素并拾取（项目书第 8 节待确认项、第 4 节坐标压力测试）。
##   godot --headless --path app -s res://tests/far_coords_test.gd
##
## 三个场景，各自放置一个体素再用三种方式拾取：
##   near           原点附近（对照组：用来证明测试环境本身没问题）
##   far_coords     地形节点在原点，体素坐标在 1000 km 外
##   far_transform  地形节点本身放在 1000 km 外（「物件即小世界」的情形），体素在局部坐标
## 拾取方式：
##   1. 世界坐标 → 体素坐标换算（编辑器把点击位置换算成体素）
##   2. VoxelTool.raycast（体素 DDA 射线）
##   3. 物理碰撞射线（编辑器鼠标点选通常走这条）
## 两个远处场景都在 X 方向 1000 km 外；拾取偏移也取在 X 方向，才真正考验远处那一维的精度。
## 关键偏移取在体素边界内外 1 cm：单精度在 1000 km 处的分辨率只有 6.25 cm，必然判错；
## 双精度应全部正确。单精度若也能通过，说明测试不够灵敏。
##
## 退出码：0 全部通过；1 只有远处失败（对照组通过）；2 对照组失败（环境或用法有问题，结论无效）。

const FAR := 1_000_000  # 体素边长 1 m，即 1000 km
const TIMEOUT_MS := 30000
const AIR := 0
const SOLID := 1

var _failures := {"near": 0, "far": 0}
var _lib: VoxelBlockyLibrary


func _initialize() -> void:
	await process_frame  # _initialize 时根节点还没进入场景树，先等一帧
	var is_double := (Vector3(1.0e7, 0, 0) + Vector3(0.001, 0, 0)).x != 1.0e7
	print("MUTSUKI_FAR_TEST precision=%s voxel=%s" % [
		"double" if is_double else "single", ClassDB.class_exists("VoxelTerrain")])

	_lib = VoxelBlockyLibrary.new()
	_lib.add_model(VoxelBlockyModelEmpty.new())  # 0：空气
	_lib.add_model(VoxelBlockyModelCube.new())   # 1：实心方块
	_lib.bake()

	await _run_case("near", "near", Vector3.ZERO, Vector3i(2, 4, 3))
	await _run_case("far_coords", "far", Vector3.ZERO, Vector3i(FAR + 2, 4, 3))
	await _run_case("far_transform", "far", Vector3(FAR, 0, 0), Vector3i(2, 4, 3))

	print("远坐标测试：对照组失败 %d 项，远处失败 %d 项" % [_failures["near"], _failures["far"]])
	if _failures["near"] > 0:
		quit(2)
	elif _failures["far"] > 0:
		quit(1)
	else:
		quit(0)


func _run_case(case_name: String, group: String, node_pos: Vector3, vox: Vector3i) -> void:
	print("[%s] 地形节点位置 %s，目标体素 %s" % [case_name, node_pos, vox])
	var terrain := VoxelTerrain.new()
	var mesher := VoxelMesherBlocky.new()
	mesher.library = _lib
	terrain.mesher = mesher
	# 没有生成器时地形不会加载任何区块。用平地生成器，地面放在 -100 m，测试区域全是空气。
	var gen := VoxelGeneratorFlat.new()
	gen.channel = VoxelBuffer.CHANNEL_TYPE
	gen.voxel_type = SOLID
	gen.height = -100.0
	terrain.generator = gen
	terrain.max_view_distance = 32
	terrain.position = node_pos
	root.add_child(terrain)

	var world_min: Vector3 = terrain.global_transform * Vector3(vox)  # 目标体素的最小角（世界坐标）
	var viewer := VoxelViewer.new()
	viewer.view_distance = 32
	viewer.position = world_min + Vector3(0.5, 0.5, 4.0)
	root.add_child(viewer)

	var vt: VoxelTool = terrain.get_voxel_tool()
	vt.channel = VoxelBuffer.CHANNEL_TYPE

	# 等区域加载到可编辑。
	var area := AABB(Vector3(vox) - Vector3(2, 2, 2), Vector3(6, 6, 14))
	var start := Time.get_ticks_msec()
	while not vt.is_area_editable(area) and Time.get_ticks_msec() - start < TIMEOUT_MS:
		await process_frame
	if not _check(group, vt.is_area_editable(area), "[%s] 目标区域已加载、可编辑" % case_name):
		_cleanup(terrain, viewer)
		return

	# ---- 放置 ----
	vt.mode = VoxelTool.MODE_SET
	vt.value = SOLID
	vt.do_point(vox)
	_check(group, vt.get_voxel(vox) == SOLID, "[%s] 放置：目标体素为实心" % case_name)
	_check(group, vt.get_voxel(vox + Vector3i(1, 0, 0)) == AIR and vt.get_voxel(vox + Vector3i(0, 0, 1)) == AIR,
		"[%s] 放置：相邻体素仍为空气" % case_name)

	# ---- 拾取 1：世界坐标 → 体素坐标 ----
	var to_local := terrain.global_transform.affine_inverse()
	for off in [Vector3(0.01, 0.5, 0.01), Vector3(0.99, 0.5, 0.99), Vector3(0.5, 0.5, 0.5)]:
		var local: Vector3 = to_local * (world_min + off)
		var got := Vector3i(local.floor())
		_check(group, got == vox, "[%s] 换算：体素内偏移 %s 的世界点 → %s（期望 %s）" % [case_name, off, got, vox])
	for off in [Vector3(1.01, 0.5, 0.5), Vector3(-0.01, 0.5, 0.5)]:
		var local2: Vector3 = to_local * (world_min + off)
		var got2 := Vector3i(local2.floor())
		_check(group, got2 != vox, "[%s] 换算：体素外偏移 %s 的世界点不落在目标体素（得到 %s）" % [case_name, off, got2])

	# ---- 拾取 2：VoxelTool.raycast，沿 -Z 从体素前方 5 m 射入 ----
	var dir := Vector3(0, 0, -1)
	for xoff in [0.5, 0.01, 0.99]:
		var origin := world_min + Vector3(xoff, 0.5, 6.0)
		var hit: VoxelRaycastResult = vt.raycast(origin, dir, 20.0)
		var ok := hit != null and hit.position == vox and hit.previous_position == vox + Vector3i(0, 0, 1)
		_check(group, ok, "[%s] 体素射线：x 偏移 %.2f 命中目标体素（命中 %s）" % [
			case_name, xoff, hit.position if hit != null else "无"])
	for xoff in [1.01, -0.01]:
		var origin2 := world_min + Vector3(xoff, 0.5, 6.0)
		var miss: VoxelRaycastResult = vt.raycast(origin2, dir, 20.0)
		_check(group, miss == null, "[%s] 体素射线：x 偏移 %.2f 从旁边擦过、不命中（命中 %s）" % [
			case_name, xoff, miss.position if miss != null else "无"])

	# ---- 拾取 3：物理碰撞射线（等碰撞体生成）----
	# 横向偏移取 0.3：单精度在 1000 km 处表示不了 x.3（只能到 6.25 cm 的整数倍），取 0.5 会碰巧精确。
	var p_from := world_min + Vector3(0.3, 0.5, 6.0)
	var p_to := p_from + dir * 20.0
	var face_z := world_min.z + 1.0  # 射线应打在体素 +Z 面上
	var result := {}
	start = Time.get_ticks_msec()
	while result.is_empty() and Time.get_ticks_msec() - start < TIMEOUT_MS:
		await physics_frame
		var space := root.get_world_3d().direct_space_state
		result = space.intersect_ray(PhysicsRayQueryParameters3D.create(p_from, p_to))
	if _check(group, not result.is_empty(), "[%s] 物理射线：命中碰撞体" % case_name):
		var hp: Vector3 = result.position
		_check(group, absf(hp.z - face_z) < 0.001,
			"[%s] 物理射线：命中点在体素正面上，误差 < 1 mm（误差 %.4f m）" % [case_name, absf(hp.z - face_z)])
		_check(group, absf(hp.x - (world_min.x + 0.3)) < 0.001 and absf(hp.y - (world_min.y + 0.5)) < 0.001,
			"[%s] 物理射线：命中点横向误差 < 1 mm（%.4f, %.4f m）" % [
				case_name, absf(hp.x - (world_min.x + 0.3)), absf(hp.y - (world_min.y + 0.5))])
	_cleanup(terrain, viewer)


func _cleanup(terrain: Node, viewer: Node) -> void:
	terrain.queue_free()
	viewer.queue_free()


func _check(group: String, ok: bool, label: String) -> bool:
	if ok:
		print("  通过  ", label)
	else:
		_failures[group] += 1
		printerr("  失败  ", label)
	return ok
