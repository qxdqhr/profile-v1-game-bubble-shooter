extends Node2D
## Stage-C polish: aim guide, endgame bias, shots HUD, float score, pointer-up shoot.

enum Status { READY, SHOOTING, WON, LOST }

var _grid: Array = []
var _status: Status = Status.READY
var _score: int = 0
var _shots: int = 0
var _aim_angle: float = -PI * 0.5
var _current_color: int = 0
var _next_color: int = 0
var _projectile: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _float_scores: Array = [] # {pos, text, life, max_life}

@onready var _hud: Label = $UI/HUD
@onready var _overlay: ColorRect = $UI/Overlay
@onready var _over_msg: Label = $UI/Overlay/VBox/Msg
@onready var _retry: Button = $UI/Overlay/VBox/Retry
@onready var _restart_btn: Button = $UI/Restart

func _ready() -> void:
	_rng.randomize()
	_retry.pressed.connect(_restart)
	_restart_btn.pressed.connect(_restart)
	_overlay.visible = false
	_restart()

func _restart() -> void:
	_grid = BubbleGrid.create_initial(_rng)
	_status = Status.READY
	_score = 0
	_shots = 0
	_aim_angle = -PI * 0.5
	_current_color = BubbleGrid.random_playable_color(_grid, _rng)
	_next_color = BubbleGrid.pick_next_color(_grid, _current_color, _rng)
	_projectile.clear()
	_float_scores.clear()
	_overlay.visible = false
	_update_hud()
	queue_redraw()

func _update_hud() -> void:
	var st: String = "待发射"
	match _status:
		Status.SHOOTING:
			st = "发射中"
		Status.WON:
			st = "胜利"
		Status.LOST:
			st = "失败"
	_hud.text = "状态：%s   分数：%d   发射次数：%d" % [st, _score, _shots]

func _unhandled_input(event: InputEvent) -> void:
	if _status == Status.WON or _status == Status.LOST:
		return
	var shooter: Vector2 = BubbleConfig.shooter_pos()
	if event is InputEventMouseMotion:
		var e := event as InputEventMouseMotion
		_aim_angle = BubbleGrid.clamp_aim(atan2(e.position.y - shooter.y, e.position.x - shooter.x))
		queue_redraw()
	elif event is InputEventScreenDrag:
		var e2 := event as InputEventScreenDrag
		_aim_angle = BubbleGrid.clamp_aim(atan2(e2.position.y - shooter.y, e2.position.x - shooter.x))
		queue_redraw()
	# Original: pointerup to shoot
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _status == Status.READY:
			_shoot()
	if event is InputEventScreenTouch and not event.pressed:
		if _status == Status.READY:
			var e3 := event as InputEventScreenTouch
			_aim_angle = BubbleGrid.clamp_aim(atan2(e3.position.y - shooter.y, e3.position.x - shooter.x))
			_shoot()

func _shoot() -> void:
	if _status != Status.READY:
		return
	var colors: Array = BubbleGrid.collect_colors(_grid)
	if not colors.is_empty():
		if _current_color not in colors:
			_current_color = BubbleGrid.random_playable_color(_grid, _rng)
		if _next_color not in colors:
			_next_color = BubbleGrid.random_playable_color(_grid, _rng)
	var shooter2: Vector2 = BubbleConfig.shooter_pos()
	# Match original launch offset (slightly above shooter center)
	_projectile = {
		"x": shooter2.x,
		"y": shooter2.y - BubbleConfig.RADIUS,
		"vx": cos(_aim_angle) * BubbleConfig.LAUNCH_SPEED,
		"vy": sin(_aim_angle) * BubbleConfig.LAUNCH_SPEED,
		"color": _current_color,
	}
	_status = Status.SHOOTING
	_update_hud()

func _process(delta: float) -> void:
	var dirty := false
	if not _float_scores.is_empty():
		var kept: Array = []
		for item in _float_scores:
			var d: Dictionary = item
			d["life"] = float(d["life"]) - delta
			d["pos"] = Vector2(float((d["pos"] as Vector2).x), float((d["pos"] as Vector2).y) - 35.0 * delta)
			if float(d["life"]) > 0.0:
				kept.append(d)
		_float_scores = kept
		dirty = true

	if _status == Status.SHOOTING and not _projectile.is_empty():
		var dt := minf(delta, 0.05)
		var bw := BubbleConfig.board_width()
		var r := BubbleConfig.RADIUS
		var nx: float = float(_projectile["x"]) + float(_projectile["vx"]) * dt
		var ny: float = float(_projectile["y"]) + float(_projectile["vy"]) * dt
		var nvx: float = float(_projectile["vx"])

		if nx <= r:
			nx = r
			nvx = absf(nvx)
		elif nx >= bw - r:
			nx = bw - r
			nvx = -absf(nvx)

		if ny <= BubbleConfig.TOP_OFFSET + r:
			_settle(nx, BubbleConfig.TOP_OFFSET + r, BubbleGrid.nearest_slot(nx, ny))
		else:
			var hit: Variant = BubbleGrid.find_collision(nx, ny, _grid)
			if hit != null:
				_settle(nx, ny, hit)
			else:
				_projectile["x"] = nx
				_projectile["y"] = ny
				_projectile["vx"] = nvx
		dirty = true

	if dirty:
		queue_redraw()

func _settle(x: float, y: float, preferred: Variant) -> void:
	if _projectile.is_empty():
		return
	var attach: Variant = BubbleGrid.find_attach_slot(x, y, _grid, preferred)
	if attach == null:
		_fail("Game Over")
		return
	var slot: Dictionary = attach
	if _grid[slot.row][slot.col] >= 0:
		_fail("Game Over")
		return

	_grid[slot.row][slot.col] = int(_projectile["color"])
	var resolved: Dictionary = BubbleGrid.resolve_matches(_grid, slot)
	_grid = resolved["grid"] as Array
	_shots += 1
	var gain := int(resolved["matched"]) * 10 + int(resolved["dropped"]) * 15
	if int(resolved["removed"]) > 0:
		_score += gain
		var attach_pos := BubbleConfig.bubble_pos(slot.row, slot.col)
		_spawn_float(attach_pos + Vector2(0, -14), "+%d" % gain)

	if not BubbleGrid.has_any(_grid):
		_projectile.clear()
		_status = Status.WON
		_over_msg.text = "You Win!\n分数 %d" % _score
		_overlay.visible = true
	elif BubbleGrid.reached_danger(_grid):
		_fail("Game Over")
		return
	else:
		_status = Status.READY

	_projectile.clear()
	_current_color = _next_color
	_next_color = BubbleGrid.pick_next_color(_grid, _current_color, _rng)
	_update_hud()
	queue_redraw()

func _fail(title: String) -> void:
	_projectile.clear()
	_status = Status.LOST
	_over_msg.text = "%s\n分数 %d" % [title, _score]
	_overlay.visible = true
	_update_hud()
	queue_redraw()

func _spawn_float(pos: Vector2, text: String) -> void:
	_float_scores.append({
		"pos": pos,
		"text": text,
		"life": 0.7,
		"max_life": 0.7,
	})

func _draw() -> void:
	var bw := BubbleConfig.board_width()
	var bh := BubbleConfig.board_height()
	draw_rect(Rect2(0, 0, bw, bh), Color(0.973, 0.98, 0.988))
	draw_rect(Rect2(0, BubbleConfig.TOP_OFFSET, bw, bh - BubbleConfig.TOP_OFFSET - 40), Color(0.886, 0.910, 0.941))

	var shooter := BubbleConfig.shooter_pos()
	# Shooter reference line (original)
	draw_rect(Rect2(0, shooter.y - BubbleConfig.RADIUS * 1.3, bw, 2.0), Color(0.58, 0.64, 0.72, 0.2))

	for row in BubbleConfig.ROWS:
		for col in BubbleConfig.COLS:
			var idx: int = _grid[row][col]
			if idx < 0:
				continue
			_draw_bubble(BubbleConfig.bubble_pos(row, col), BubbleConfig.color_for(idx))

	if _status == Status.READY:
		_draw_aim_guide(shooter)
		var pulse := sin(Time.get_ticks_msec() / 220.0) * 0.6
		_draw_bubble(shooter, BubbleConfig.color_for(_current_color), BubbleConfig.RADIUS - 0.5 + pulse)
		_draw_bubble(
			Vector2(bw - BubbleConfig.RADIUS * 1.6, shooter.y),
			BubbleConfig.color_for(_next_color),
			BubbleConfig.RADIUS * 0.72
		)
		draw_circle(Vector2(bw - BubbleConfig.RADIUS * 1.6, shooter.y), 2.0, Color(0.2, 0.25, 0.33, 0.7))

	if not _projectile.is_empty():
		_draw_bubble(
			Vector2(float(_projectile["x"]), float(_projectile["y"])),
			BubbleConfig.color_for(int(_projectile["color"]))
		)

	for item in _float_scores:
		var d: Dictionary = item
		var life: float = float(d["life"])
		var max_life: float = float(d["max_life"])
		var a := clampf(life / max_life, 0.0, 1.0)
		var p: Vector2 = d["pos"]
		draw_string(
			ThemeDB.fallback_font,
			p + Vector2(-10, 0),
			str(d["text"]),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			Color(0.086, 0.639, 0.290, a)
		)

func _draw_aim_guide(shooter: Vector2) -> void:
	var bw := BubbleConfig.board_width()
	var r := BubbleConfig.RADIUS
	var px := shooter.x
	var py := shooter.y
	var vx := cos(_aim_angle)
	var vy := sin(_aim_angle)
	var step_len := r * 0.9
	for i in range(1, 27):
		px += vx * step_len
		py += vy * step_len
		if px <= r or px >= bw - r:
			vx *= -1.0
			px = clampf(px, r, bw - r)
		if py <= BubbleConfig.TOP_OFFSET + r:
			break
		var alpha := maxf(0.12, 0.55 - float(i) * 0.018)
		var rad := maxf(1.4, 2.8 - float(i) * 0.07)
		draw_circle(Vector2(px, py), rad, Color(0.2, 0.25, 0.33, alpha))

func _draw_bubble(center: Vector2, color: Color, radius: float = BubbleConfig.RADIUS) -> void:
	draw_circle(center, radius, color)
	draw_circle(center + Vector2(-radius * 0.32, -radius * 0.36), radius * 0.35, Color(1, 1, 1, 0.22))
	draw_arc(center, radius, 0, TAU, 24, Color(0.2, 0.25, 0.33, 0.22), 1.0)
