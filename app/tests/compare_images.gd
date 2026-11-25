extends SceneTree
## 软件渲染截图检查：
##   godot --headless --path app -s res://tests/compare_images.gd -- \
##     --actual=<截图目录> --baseline=<基准图目录> --diff=<差异图输出目录>
## 两类检查，任一失败则退出码 1：
## 1. 语义检查：不依赖基准图，只看「该有的东西在不在」（天空、地面、白色原点方块、红色标尺）。
##    防止基准图本身就是坏的，或者整张图黑屏。
## 2. 基准图比对：逐像素比较，差异像素比例超过阈值即失败，并输出差异图。

## 某像素任一通道差值超过这个数（0–255）才算「不同」，吸收抗锯齿与浮点的细微差别。
const PIXEL_TOLERANCE := 24
## 「不同」像素占比的上限。
const MAX_DIFF_RATIO := 0.005

## 每个机位的语义检查：[检查名, 区域 Rect2i, 条件]。条件作用于区域内的平均颜色。
var SEMANTIC := {
	"start": [
		["顶部是天空", Rect2i(560, 20, 160, 60), "sky"],
		["底部是地面", Rect2i(200, 620, 880, 80), "ground"],
		["中间有白色原点方块", Rect2i(620, 430, 40, 40), "white"],
		["右侧有红色 10 m 标尺", Rect2i(1222, 425, 8, 40), "red"],
	],
	"overview": [
		["顶部是天空", Rect2i(560, 20, 160, 60), "sky"],
		["下半部是地面", Rect2i(200, 450, 880, 200), "ground"],
	],
	"pillar_1km": [
		["左上是天空", Rect2i(100, 40, 300, 100), "sky"],
		["底部是地面", Rect2i(100, 620, 300, 80), "ground"],
		["中间有红色 1 km 标尺", Rect2i(615, 150, 50, 400), "red"],
	],
}

var _failures := 0


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	for key in ["actual", "baseline", "diff"]:
		if not args.has(key):
			printerr("缺少参数 --%s=" % key)
			quit(2)
			return
	DirAccess.make_dir_recursive_absolute(args["diff"])

	for view in SEMANTIC:
		_check_view(view, args["actual"], args["baseline"], args["diff"])

	if _failures > 0:
		printerr("截图检查：%d 项失败" % _failures)
		quit(1)
	else:
		print("截图检查：全部通过")
		quit(0)


func _check_view(view: String, actual_dir: String, baseline_dir: String, diff_dir: String) -> void:
	var actual := Image.load_from_file(actual_dir.path_join(view + ".png"))
	if actual == null:
		_fail("%s：找不到截图" % view)
		return
	actual.convert(Image.FORMAT_RGB8)

	for c in SEMANTIC[view]:
		var avg := _average(actual, c[1])
		if _matches(avg, c[2]):
			print("  通过  %s：%s（平均色 %s）" % [view, c[0], avg.to_html(false)])
		else:
			_fail("%s：%s（平均色 %s）" % [view, c[0], avg.to_html(false)])

	var base_path := baseline_dir.path_join(view + ".png")
	if not FileAccess.file_exists(base_path):
		_fail("%s：没有基准图 %s" % [view, base_path])
		return
	var base := Image.load_from_file(base_path)
	base.convert(Image.FORMAT_RGB8)
	if base.get_size() != actual.get_size():
		_fail("%s：尺寸不同（截图 %s，基准 %s）" % [view, actual.get_size(), base.get_size()])
		return

	var w := actual.get_width()
	var h := actual.get_height()
	var a := actual.get_data()
	var b := base.get_data()
	var diff := Image.create(w, h, false, Image.FORMAT_RGB8)
	var diff_count := 0
	for i in w * h:
		var o := i * 3
		var d := maxi(absi(a[o] - b[o]), maxi(absi(a[o + 1] - b[o + 1]), absi(a[o + 2] - b[o + 2])))
		if d > PIXEL_TOLERANCE:
			diff_count += 1
			diff.set_pixel(i % w, i / w, Color.MAGENTA)
		else:
			var g := a[o] / 255.0 * 0.3
			diff.set_pixel(i % w, i / w, Color(g, g, g))
	var ratio := float(diff_count) / float(w * h)
	diff.save_png(diff_dir.path_join(view + "_diff.png"))
	var msg := "%s：与基准图差异 %.3f%%（上限 %.3f%%）" % [view, ratio * 100.0, MAX_DIFF_RATIO * 100.0]
	if ratio <= MAX_DIFF_RATIO:
		print("  通过  " + msg)
	else:
		_fail(msg)


func _average(img: Image, r: Rect2i) -> Color:
	var sum := Color(0, 0, 0)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			sum += img.get_pixel(x, y)
	return sum / float(r.get_area())


func _matches(c: Color, kind: String) -> bool:
	match kind:
		"sky":    # 偏蓝或偏灰的亮色
			return c.b >= c.r and c.b >= c.g - 0.02 and c.get_luminance() > 0.4
		"ground": # 绿色占优
			return c.g > c.r + 0.03 and c.g > c.b + 0.03
		"white":
			return c.r > 0.75 and c.g > 0.75 and c.b > 0.75
		"red":
			return c.r > c.g + 0.25 and c.r > c.b + 0.25
	return false


func _fail(msg: String) -> void:
	_failures += 1
	printerr("  失败  " + msg)
