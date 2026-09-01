class_name BubbleGrid
extends RefCounted

## Grid helpers ported from PhaserBubbleShooter.tsx (color index -1 = empty).

static func create_empty() -> Array:
	var g: Array = []
	for _r in BubbleConfig.ROWS:
		var row: Array = []
		row.resize(BubbleConfig.COLS)
		for c in BubbleConfig.COLS:
			row[c] = -1
		g.append(row)
	return g

static func create_initial(rng: RandomNumberGenerator) -> Array:
	var g := create_empty()
	for row in BubbleConfig.INITIAL_ROWS:
		for col in BubbleConfig.COLS:
			g[row][col] = BubbleConfig.random_color_index(rng)
	return g

static func slot_key(row: int, col: int) -> String:
	return "%d:%d" % [row, col]

static func is_valid(row: int, col: int) -> bool:
	return row >= 0 and row < BubbleConfig.ROWS and col >= 0 and col < BubbleConfig.COLS

static func neighbors(row: int, col: int) -> Array:
	var dirs: Array
	if row % 2 == 0:
		dirs = [[-1, -1], [-1, 0], [0, -1], [0, 1], [1, -1], [1, 0]]
	else:
		dirs = [[-1, 0], [-1, 1], [0, -1], [0, 1], [1, 0], [1, 1]]
	var out: Array = []
	for d in dirs:
		var nr: int = row + int(d[0])
		var nc: int = col + int(d[1])
		if is_valid(nr, nc):
			out.append({"row": nr, "col": nc})
	return out

static func nearest_slot(x: float, y: float) -> Dictionary:
	var row := clampi(
		roundi((y - BubbleConfig.TOP_OFFSET - BubbleConfig.RADIUS) / BubbleConfig.row_step()),
		0,
		BubbleConfig.ROWS - 1
	)
	var row_offset := BubbleConfig.RADIUS if row % 2 == 1 else 0.0
	var col := clampi(
		roundi((x - BubbleConfig.RADIUS - row_offset) / BubbleConfig.diameter()),
		0,
		BubbleConfig.COLS - 1
	)
	return {"row": row, "col": col}

static func has_adjacent(row: int, col: int, grid: Array) -> bool:
	if row == 0:
		return true
	for n in neighbors(row, col):
		if grid[n.row][n.col] >= 0:
			return true
	return false

static func find_attach_slot(x: float, y: float, grid: Array, preferred: Variant = null) -> Variant:
	var candidates: Array = []
	if preferred != null:
		var p: Dictionary = preferred
		if is_valid(p.row, p.col):
			candidates.append(p)
			for n in neighbors(p.row, p.col):
				candidates.append(n)
	var near: Dictionary = nearest_slot(x, y)
	candidates.append(near)
	for n in neighbors(near.row, near.col):
		candidates.append(n)

	var seen := {}
	var unique: Array = []
	for s in candidates:
		var d: Dictionary = s
		var k := slot_key(d.row, d.col)
		if seen.has(k):
			continue
		seen[k] = true
		unique.append(d)

	var best: Variant = null
	var best_dist := INF
	for s in unique:
		var slot: Dictionary = s
		if grid[slot.row][slot.col] >= 0:
			continue
		if not has_adjacent(slot.row, slot.col, grid):
			continue
		var pos := BubbleConfig.bubble_pos(slot.row, slot.col)
		var dx := pos.x - x
		var dy := pos.y - y
		var dist := dx * dx + dy * dy
		if dist < best_dist:
			best_dist = dist
			best = slot
	return best

static func find_collision(x: float, y: float, grid: Array) -> Variant:
	var threshold := pow(BubbleConfig.RADIUS * 2.0 - 1.0, 2.0)
	for row in BubbleConfig.ROWS:
		for col in BubbleConfig.COLS:
			if grid[row][col] < 0:
				continue
			var pos := BubbleConfig.bubble_pos(row, col)
			var dx := pos.x - x
			var dy := pos.y - y
			if dx * dx + dy * dy <= threshold:
				return {"row": row, "col": col}
	return null

static func resolve_matches(grid_in: Array, placed: Dictionary) -> Dictionary:
	var grid := _copy_grid(grid_in)
	var color_idx: int = grid[placed.row][placed.col]
	if color_idx < 0:
		return {
			"grid": grid,
			"matched": 0,
			"dropped": 0,
			"removed": 0,
		}

	var queue: Array = [placed]
	var visited := {}
	var group: Array = []
	while not queue.is_empty():
		var cur: Dictionary = queue.pop_front()
		var key := slot_key(cur.row, cur.col)
		if visited.has(key):
			continue
		visited[key] = true
		if grid[cur.row][cur.col] != color_idx:
			continue
		group.append(cur)
		for n in neighbors(cur.row, cur.col):
			var nk := slot_key(n.row, n.col)
			if not visited.has(nk):
				queue.append(n)

	var matched := 0
	if group.size() >= BubbleConfig.MIN_MATCH:
		for s in group:
			var slot: Dictionary = s
			if grid[slot.row][slot.col] >= 0:
				grid[slot.row][slot.col] = -1
				matched += 1

	var dropped := 0
	if matched > 0:
		var connected := {}
		var top_queue: Array = []
		for col in BubbleConfig.COLS:
			if grid[0][col] >= 0:
				top_queue.append({"row": 0, "col": col})
		while not top_queue.is_empty():
			var cur2: Dictionary = top_queue.pop_front()
			var key2 := slot_key(cur2.row, cur2.col)
			if connected.has(key2) or grid[cur2.row][cur2.col] < 0:
				continue
			connected[key2] = true
			for n in neighbors(cur2.row, cur2.col):
				var nk2 := slot_key(n.row, n.col)
				if not connected.has(nk2):
					top_queue.append(n)
		for row in BubbleConfig.ROWS:
			for col in BubbleConfig.COLS:
				if grid[row][col] >= 0 and not connected.has(slot_key(row, col)):
					grid[row][col] = -1
					dropped += 1

	return {
		"grid": grid,
		"matched": matched,
		"dropped": dropped,
		"removed": matched + dropped,
	}

static func has_any(grid: Array) -> bool:
	for row in BubbleConfig.ROWS:
		for col in BubbleConfig.COLS:
			if grid[row][col] >= 0:
				return true
	return false

static func reached_danger(grid: Array) -> bool:
	var from := maxi(0, BubbleConfig.ROWS - 2)
	for row in range(from, BubbleConfig.ROWS):
		for col in BubbleConfig.COLS:
			if grid[row][col] >= 0:
				return true
	return false

static func collect_colors(grid: Array) -> Array:
	var set := {}
	for row in BubbleConfig.ROWS:
		for col in BubbleConfig.COLS:
			var idx: int = grid[row][col]
			if idx >= 0:
				set[idx] = true
	var out: Array = set.keys()
	out.sort()
	return out

static func random_playable_color(grid: Array, rng: RandomNumberGenerator) -> int:
	var colors := collect_colors(grid)
	if colors.is_empty():
		return BubbleConfig.random_color_index(rng)
	return colors[rng.randi_range(0, colors.size() - 1)]

static func pick_next_color(grid: Array, current: int, rng: RandomNumberGenerator) -> int:
	var colors := collect_colors(grid)
	if colors.is_empty():
		return BubbleConfig.random_color_index(rng)
	# Endgame bias: when ≤2 colors left, 78% chance to chain same color (original).
	if colors.size() <= 2 and current in colors and rng.randf() < 0.78:
		return current
	return colors[rng.randi_range(0, colors.size() - 1)]

static func _copy_grid(grid: Array) -> Array:
	var out: Array = []
	for row in grid:
		out.append(row.duplicate())
	return out

static func clamp_aim(angle: float) -> float:
	var min_a := -PI + 0.15
	var max_a := -0.15
	return clampf(angle, min_a, max_a)
