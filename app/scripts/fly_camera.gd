extends Camera3D
## 自由飞行相机。
## 点击窗口捕获鼠标环视，Esc 释放；WASD 平移（沿视线方向），空格/E 上升，Ctrl/Q 下降；
## Shift 加速；滚轮调基础速度；R 回到起点。
## 移动逻辑放在 step() / apply_look() 里，便于无头测试直接调用。

@export var base_speed := 10.0          ## 米/秒
@export var boost_multiplier := 5.0
@export var mouse_sensitivity := 0.0025 ## 弧度/像素

const MIN_SPEED := 0.1
const MAX_SPEED := 10000.0
const PITCH_LIMIT := deg_to_rad(89.0)

var speed := 10.0
var _yaw := 0.0
var _pitch := 0.0
var _start := Transform3D.IDENTITY


func _ready() -> void:
	speed = base_speed
	_start = transform
	_yaw = rotation.y
	_pitch = rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			MOUSE_BUTTON_WHEEL_UP:
				adjust_speed(1.25)
			MOUSE_BUTTON_WHEEL_DOWN:
				adjust_speed(0.8)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look(event.relative)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_R:
				reset()


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S): dir.z += 1.0
	if Input.is_physical_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_E): dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_Q): dir.y -= 1.0
	step(dir, delta, Input.is_physical_key_pressed(KEY_SHIFT))


## 按输入方向移动一帧。local_dir：x 右、y 上（世界竖直）、z 后（相机朝向的反方向）。
func step(local_dir: Vector3, delta: float, boost: bool) -> void:
	if local_dir == Vector3.ZERO:
		return
	var move := transform.basis * Vector3(local_dir.x, 0.0, local_dir.z)
	move.y += local_dir.y
	if move.length_squared() == 0.0:
		return
	var s := speed * (boost_multiplier if boost else 1.0)
	position += move.normalized() * s * delta


## 鼠标环视；俯仰角限制在 ±89°，不会翻转。
func apply_look(relative: Vector2) -> void:
	_yaw -= relative.x * mouse_sensitivity
	_pitch = clampf(_pitch - relative.y * mouse_sensitivity, -PITCH_LIMIT, PITCH_LIMIT)
	rotation = Vector3(_pitch, _yaw, 0.0)


func adjust_speed(factor: float) -> void:
	speed = clampf(speed * factor, MIN_SPEED, MAX_SPEED)


func reset() -> void:
	transform = _start
	_yaw = rotation.y
	_pitch = rotation.x
	speed = base_speed
