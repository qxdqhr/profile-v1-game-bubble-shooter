class_name BubbleConfig
extends RefCounted

const ROWS := 12
const COLS := 8
const INITIAL_ROWS := 5
const RADIUS := 16.0
const TOP_OFFSET := 18.0
const LAUNCH_SPEED := 480.0
const MIN_MATCH := 3

static func row_step() -> float:
	return roundf(RADIUS * 1.73)

static func diameter() -> float:
	return RADIUS * 2.0

static func board_width() -> float:
	return diameter() * float(COLS) + RADIUS

static func board_height() -> float:
	return TOP_OFFSET + row_step() * float(ROWS + 1) + RADIUS

static func shooter_pos() -> Vector2:
	return Vector2(board_width() * 0.5, board_height() - RADIUS - 12.0)

const PALETTE: Array[Color] = [
	Color(0.984, 0.443, 0.522),
	Color(0.376, 0.647, 0.980),
	Color(0.204, 0.827, 0.600),
	Color(0.984, 0.749, 0.141),
	Color(0.655, 0.545, 0.980),
]

static func random_color_index(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(0, PALETTE.size() - 1)

static func bubble_pos(row: int, col: int) -> Vector2:
	var x := RADIUS + float(col) * diameter() + (float(row % 2) * RADIUS)
	var y := TOP_OFFSET + RADIUS + float(row) * row_step()
	return Vector2(x, y)

static func color_for(idx: int) -> Color:
	return PALETTE[clampi(idx, 0, PALETTE.size() - 1)]
