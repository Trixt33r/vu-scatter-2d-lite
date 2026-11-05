@tool
extends EditorPlugin
## Vu Scatter 2D: brush-paint props onto a ScatterLayer2D in the 2D viewport.

const Edition := preload("res://addons/vu_scatter_2d/edition.gd")
const Sampler := preload("res://addons/vu_scatter_2d/core/sampler.gd")
const Placer := preload("res://addons/vu_scatter_2d/core/placer.gd")
const Toolbar := preload("res://addons/vu_scatter_2d/editor/toolbar.gd")
const Dock := preload("res://addons/vu_scatter_2d/editor/dock.gd")
const ICON_PATH := "res://addons/vu_scatter_2d/icons/scatter_layer_2d.svg"

const Mode := Toolbar.Mode
enum Stroke { PAINT, ERASE, REROLL }

const PAINT_COLOR := Color(0.45, 0.85, 0.55)
const ERASE_COLOR := Color(1.0, 0.45, 0.4)
const REROLL_COLOR := Color(0.55, 0.7, 1.0)
const PANEL_MENU_ITEM := "Show Vu Scatter panel" # Project > Tools

var _toolbar: Toolbar
var _dock: Dock
var _dock_wrapper: Control # EditorDock on 4.6+, else null
var _layer: ScatterLayer2D
var _post_cache := {} # texture -> width of the post at its left end (0 = none)
var _icon: Texture2D
# Godot 4.7+ has its own Scene Paint tool (B) in the 2D toolbar. It reacts to
# the same clicks, so we switch it off while a Vu Scatter mode is on, and turn
# our mode off when the user picks it.
var _godot_paint_btn: Button
var _godot_select_btn: Button
var _mode: int = Mode.NONE

# Brush cursor
var _mouse_screen := Vector2.ZERO
var _mouse_in_view := false

# Current stroke
var _stroking := false
var _stroke_kind: int = Stroke.PAINT
var _stroke_layer: ScatterLayer2D
var _stroke_nodes: Array[Node2D] = [] # added (paint), removed (erase) or touched (re-roll)
var _stroke_old := {} # re-roll: node -> {scale, rotation, modulate} before the stroke
var _stroke_hash: Sampler
var _stroke_cell := Vector2.ZERO # snap cell for this stroke, ZERO = no snap
var _last_dab := Vector2.INF
var _rng := RandomNumberGenerator.new()
var _stroke_count := 0
var _name_counter := 0
var _line_start := Vector2.INF # Line tool: drag start in layer space, INF = not dragging
var _line_end := Vector2.ZERO
var _line_seed := 0
var _fill_points := PackedVector2Array() # Fill area: the outline drawn so far (layer space)
var _picking_tile := false # next click picks the tile type for "only on this tile"


func _enter_tree() -> void:
	# load(), not preload(): on a project's first open the SVG isn't imported yet.
	_icon = load(ICON_PATH) if ResourceLoader.exists(ICON_PATH) else null
	_toolbar = Toolbar.new()
	_toolbar.visible = false
	_toolbar.mode_changed.connect(_set_mode)
	_toolbar.hint_changed.connect(update_overlays)
	_toolbar.tool_key.connect(func(e: InputEventKey):
		if is_instance_valid(_layer) and _palette() != null and _tool_shortcut(e):
			_toolbar.get_viewport().set_input_as_handled())
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar)

	_hook_godot_scene_paint.call_deferred()

	_dock = Dock.new()
	_dock.undo_redo = get_undo_redo()
	_dock.plugin = self
	_dock.settings_changed.connect(_on_settings_changed)
	_dock.start_painting.connect(func(): _set_mode(Mode.PAINT))
	_add_dock()
	add_tool_menu_item(PANEL_MENU_ITEM, _focus_dock)
	# First time: show the dock (it can open behind the Inspector).
	_focus_dock_if_new.call_deferred()


func _focus_dock_if_new() -> void:
	if is_instance_valid(_dock) and _dock.is_new_user():
		_focus_dock()


func _exit_tree() -> void:
	_cancel_stroke()
	if is_instance_valid(_godot_paint_btn) and _godot_paint_btn.toggled.is_connected(_on_godot_paint_toggled):
		_godot_paint_btn.toggled.disconnect(_on_godot_paint_toggled)
	if is_instance_valid(_toolbar):
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar)
		_toolbar.queue_free()
	remove_tool_menu_item(PANEL_MENU_ITEM)
	_remove_dock()
	_toolbar = null
	_dock = null
	_layer = null


## 4.6+ uses the EditorDock API; 4.4-4.5 use add_control_to_dock.
func _add_dock() -> void:
	if ClassDB.class_exists(&"EditorDock") and has_method(&"add_dock"):
		_dock_wrapper = ClassDB.instantiate(&"EditorDock")
		_dock_wrapper.name = "VuScatter2D"
		_dock_wrapper.set(&"title", "Vu Scatter")
		_dock_wrapper.set(&"layout_key", "vu_scatter_2d")
		_dock_wrapper.set(&"dock_icon", _icon)
		_dock_wrapper.set(&"default_slot", ClassDB.class_get_integer_constant(&"EditorDock", &"DOCK_SLOT_RIGHT_UL"))
		_dock_wrapper.add_child(_dock)
		call(&"add_dock", _dock_wrapper)
	else:
		add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
		if _icon != null and has_method(&"set_dock_tab_icon"):
			call(&"set_dock_tab_icon", _dock, _icon)


func _remove_dock() -> void:
	if is_instance_valid(_dock_wrapper):
		call(&"remove_dock", _dock_wrapper)
		_dock_wrapper.queue_free()
	elif is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.queue_free()
	_dock_wrapper = null


func _get_plugin_name() -> String:
	return "Vu Scatter 2D"


func _get_plugin_icon() -> Texture2D:
	return _icon


func _handles(object: Object) -> bool:
	return object is ScatterLayer2D


func _edit(object: Object) -> void:
	if _stroking and object != _stroke_layer:
		_end_stroke()
	_layer = object as ScatterLayer2D
	if _layer != null and _layer.palette == null:
		# Fresh layer: give it a palette and Y-sort, like the spec's defaults.
		_layer.palette = ScatterPalette.new()
		_layer.y_sort_enabled = true
		EditorInterface.mark_scene_as_unsaved()
	# Selecting a layer (again) brings the panel forward, e.g. after a prop was
	# opened in the Inspector, which shares its tab group.
	var show := _layer != null and _dock != null and (_layer != _dock._layer or not _dock.is_visible_in_tree())
	if _dock != null:
		_dock.set_layer(_layer)
	if show:
		_focus_dock()
	_on_settings_changed()


## Brings the Vu Scatter dock tab to the front so the palette is visible.
## On 4.6+ the user can close the dock; this reopens it.
func _focus_dock() -> void:
	if is_instance_valid(_dock_wrapper) and _dock_wrapper.has_method(&"make_visible"):
		if _dock_wrapper.has_method(&"open") and not _dock.is_visible_in_tree():
			_dock_wrapper.call(&"open")
		_dock_wrapper.call(&"make_visible")
		return
	var child: Node = _dock
	var p := _dock.get_parent()
	while p != null and not p is TabContainer:
		child = p
		p = p.get_parent()
	if p is TabContainer:
		var idx: int = p.get_tab_idx_from_control(child)
		if idx >= 0:
			p.current_tab = idx


func _make_visible(visible: bool) -> void:
	if _toolbar != null:
		_toolbar.visible = visible
	if not visible:
		_end_stroke()
		_set_mode(Mode.NONE)
		if _dock != null:
			_dock.set_layer(null)


## Finds the 2D editor's Select and Scene Paint buttons by their editor icons.
## Scene Paint only exists on 4.7+; on older versions this finds nothing.
func _hook_godot_scene_paint() -> void:
	var cie: Node = null
	for n in EditorInterface.get_editor_main_screen().get_children():
		if n.get_class() == "CanvasItemEditor":
			cie = n
			break
	if cie == null:
		return
	var theme := EditorInterface.get_editor_theme()
	if not theme.has_icon(&"Paint", &"EditorIcons"):
		return
	var paint_icon := theme.get_icon(&"Paint", &"EditorIcons")
	var select_icon := theme.get_icon(&"ToolSelect", &"EditorIcons")
	for b: Button in cie.find_children("*", "Button", true, false):
		if not b.toggle_mode:
			continue
		if b.icon == paint_icon and _godot_paint_btn == null:
			_godot_paint_btn = b
		elif b.icon == select_icon and _godot_select_btn == null:
			_godot_select_btn = b
	if _godot_paint_btn != null and _godot_select_btn != null:
		_godot_paint_btn.toggled.connect(_on_godot_paint_toggled)
	else:
		_godot_paint_btn = null
		_godot_select_btn = null


func _on_godot_paint_toggled(on: bool) -> void:
	if on and _mode != Mode.NONE:
		_end_stroke()
		_set_mode(Mode.NONE)


func _turn_off_godot_scene_paint() -> void:
	if is_instance_valid(_godot_paint_btn) and _godot_paint_btn.button_pressed and is_instance_valid(_godot_select_btn):
		_godot_select_btn.button_pressed = true
		_godot_select_btn.pressed.emit()


func _set_mode(mode: int) -> void:
	if mode == Mode.REROLL and not Edition.allows(&"reroll"):
		mode = Mode.NONE
	if mode == Mode.LINE and not Edition.allows(&"line"):
		mode = Mode.NONE
	if mode == Mode.LINE and _dock != null:
		_dock.open_section("Shape options")
	_line_start = Vector2.INF
	if mode != Mode.NONE:
		_turn_off_godot_scene_paint()
	_mode = mode
	if _toolbar != null:
		_toolbar.set_mode(mode)
	update_overlays()


func _on_settings_changed() -> void:
	if _toolbar != null and _palette() != null:
		_toolbar.set_radius(_palette().radius)
		_toolbar.set_props(_palette().get_active_items())
	update_overlays()


## The root of the scene the layer belongs to. Painted props are owned by it,
## whichever scene tab happens to be active.
static func _scene_root_of(layer: Node) -> Node:
	if layer.owner != null:
		return layer.owner
	return layer


func _palette() -> ScatterPalette:
	return _layer.palette if is_instance_valid(_layer) else null


# ---------------------------------------------------------------- input

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if _picking_tile and is_instance_valid(_layer) and _palette() != null:
		if event is InputEventMouseMotion:
			_mouse_screen = event.position
			_mouse_in_view = true
			update_overlays()
			return false
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_pick_tile(_to_local(event.position))
			return true
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_picking_tile = false
			_dock.tile_pick_done("")
			update_overlays()
			return true
	if is_instance_valid(_layer) and _palette() != null and _tool_shortcut(event):
		return true
	if not is_instance_valid(_layer) or _palette() == null or _mode == Mode.NONE:
		return false

	if event is InputEventMouseMotion:
		_mouse_screen = event.position
		_mouse_in_view = true
		update_overlays()
		if _line_start != Vector2.INF:
			if _shape() == Toolbar.Shape.FILL:
				var lp := _to_local(event.position)
				if _fill_points.is_empty() or _fill_points[-1].distance_to(lp) > 4.0 / absf(_canvas_xform().get_scale().x):
					_fill_points.append(lp)
				_line_end = lp
			else:
				_line_end = _constrain_line(_line_start, _line_snap(_to_local(event.position)), event.shift_pressed)
			return true
		if _stroking:
			_stroke_dab(_to_local(event.position), false)
			return true
		return false

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false # wheel / middle / right keep zoom, pan, context menu
		_mouse_screen = mb.position
		if mb.pressed:
			if mb.ctrl_pressed or mb.alt_pressed or mb.meta_pressed:
				return false
			if _mode == Mode.SINGLE:
				_place_single(_to_local(mb.position))
			elif _mode == Mode.LINE:
				_line_start = _line_snap(_to_local(mb.position))
				_line_end = _line_start
				_line_seed = randi()
				_fill_points = PackedVector2Array([_to_local(mb.position)])
				update_overlays()
			else:
				var kind := Stroke.PAINT
				if _mode == Mode.ERASE or (_mode == Mode.PAINT and mb.shift_pressed):
					kind = Stroke.ERASE
				elif _mode == Mode.REROLL:
					kind = Stroke.REROLL
				_begin_stroke(kind)
				_stroke_dab(_to_local(mb.position), true)
			return true
		if _line_start != Vector2.INF:
			if _shape() == Toolbar.Shape.FILL:
				_fill_points.append(_to_local(mb.position))
				_place_fill()
			else:
				_line_end = _constrain_line(_line_start, _line_snap(_to_local(mb.position)), mb.shift_pressed)
				_place_line()
			return true
		if _stroking:
			_end_stroke()
			return true
		return false

	if event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
			return false
		match k.keycode:
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				var p := _palette()
				var f := 1.0 / 1.15 if k.keycode == KEY_BRACKETLEFT else 1.15
				p.radius = clampf(p.radius * f, 4.0, 4096.0)
				EditorInterface.mark_scene_as_unsaved()
				_dock.refresh()
				_on_settings_changed()
				return true
			KEY_ESCAPE:
				if not k.echo and _line_start != Vector2.INF:
					_line_start = Vector2.INF # cancel the row, stay in Line mode
					update_overlays()
					return true
				if not k.echo:
					_end_stroke()
					_set_mode(Mode.NONE)
					return true
	return false


## Shortcuts familiar from drawing apps (Photoshop, Krita, Aseprite), only while
## a scatter layer is selected: B brush, E eraser (only with a tool on, so Godot's
## E = rotate still works otherwise), P place one, Shift+B shuffle, U shapes
## (Shift+U = next shape), L fill area.
func _tool_shortcut(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	var k := event as InputEventKey
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed or _stroking or _line_start != Vector2.INF:
		return false
	if k.shift_pressed and k.keycode != KEY_U and k.keycode != KEY_B:
		return false
	match k.keycode:
		KEY_B:
			if k.shift_pressed: # Shift+B: Shuffle (Pro), the brush's other job
				if not Edition.allows(&"reroll"):
					return false
				_set_mode(Mode.REROLL)
			else:
				_set_mode(Mode.PAINT)
			return true
		KEY_P:
			_set_mode(Mode.SINGLE)
			return true
		KEY_E:
			if _mode == Mode.NONE:
				return false
			_set_mode(Mode.ERASE)
			return true
		KEY_U:
			if not Edition.allows(&"line"):
				return false
			# U keeps the picked shape (pressing it twice must not change it);
			# Shift+U steps to the next outline shape, like Photoshop.
			if k.shift_pressed:
				_toolbar.set_shape((_toolbar.shape + 1) % Toolbar.Shape.FILL)
			elif _toolbar.shape == Toolbar.Shape.FILL:
				_toolbar.set_shape(Toolbar.Shape.LINE)
			_set_mode(Mode.LINE)
			return true
		KEY_L:
			if not Edition.allows(&"line"):
				return false
			_toolbar.set_shape(Toolbar.Shape.FILL)
			_set_mode(Mode.LINE)
			return true
	return false


func _canvas_xform() -> Transform2D:
	return EditorInterface.get_editor_viewport_2d().global_canvas_transform * _layer.global_transform


func _to_local(screen_pos: Vector2) -> Vector2:
	return _canvas_xform().affine_inverse() * screen_pos


# ---------------------------------------------------------------- overlay

## "What to do next" for the current tool, at the bottom of the 2D view while a
## scatter layer is selected (the toolbar has no room for long text).
func _draw_hint_bar(overlay: Control, es: float) -> void:
	if _toolbar == null:
		return
	var text: String = _toolbar.hint_text()
	if text.is_empty():
		return
	var font := overlay.get_theme_default_font()
	var fs := roundi(14 * es)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad := Vector2(10, 6) * es
	var h := font.get_height(fs)
	var box := Rect2(Vector2((overlay.size.x - w) * 0.5 - pad.x, overlay.size.y - h - pad.y * 2 - 22 * es), Vector2(w, h) + pad * 2)
	overlay.draw_rect(box, Color(0, 0, 0, 0.6))
	overlay.draw_string(font, box.position + Vector2(pad.x, pad.y + font.get_ascent(fs)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if not is_instance_valid(_layer) or _palette() == null:
		return
	var es := EditorInterface.get_editor_scale()
	if _picking_tile:
		overlay.draw_string(overlay.get_theme_default_font(), _mouse_screen + Vector2(14, -14) * es,
			"Click a tile to pick its type (Esc cancels)", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14 * es), PAINT_COLOR)
		return
	_draw_tool_overlay(overlay, es)
	_draw_hint_bar(overlay, es) # last, so mirror lines and brush circles never cross the text


func _draw_tool_overlay(overlay: Control, es: float) -> void:
	var p := _palette()
	if _mode == Mode.NONE:
		return
	_draw_mirror_lines(overlay, es)
	if not _mouse_in_view:
		return
	if _mode == Mode.LINE:
		_draw_line_overlay(overlay, es)
	elif _mode == Mode.SINGLE:
		var s := 8.0 * es
		var at := _mouse_screen
		var cell := _cell_size()
		if cell != Vector2.ZERO:
			at = _canvas_xform() * _snap(_to_local(_mouse_screen), cell)
		overlay.draw_line(at - Vector2(s, 0), at + Vector2(s, 0), PAINT_COLOR, 2 * es)
		overlay.draw_line(at - Vector2(0, s), at + Vector2(0, s), PAINT_COLOR, 2 * es)
	else:
		var col := PAINT_COLOR
		if _mode == Mode.REROLL:
			col = REROLL_COLOR
		elif _mode == Mode.ERASE or (_stroking and _stroke_kind == Stroke.ERASE) or Input.is_key_pressed(KEY_SHIFT):
			col = ERASE_COLOR
		var r := p.radius * absf(_canvas_xform().get_scale().x)
		overlay.draw_arc(_mouse_screen, r, 0.0, TAU, 64, col, 2.0 * es, true)
		overlay.draw_circle(_mouse_screen, 2.0 * es, col)
		for m in _mirrors(_to_local(_mouse_screen)):
			overlay.draw_arc(_canvas_xform() * m, r, 0.0, TAU, 64, Color(col, 0.45), 1.5 * es, true)
	if p.get_active_items().is_empty() and (_mode == Mode.PAINT or _mode == Mode.SINGLE or _mode == Mode.LINE):
		var font := overlay.get_theme_default_font()
		overlay.draw_string(font, _mouse_screen + Vector2(12, -12) * es,
			"Pick what to paint in the Vu Scatter panel first", HORIZONTAL_ALIGNMENT_LEFT, -1,
			roundi(14 * es), ERASE_COLOR)


# ---------------------------------------------------------------- grid snap

## Snap cell for the current layer, or Vector2.ZERO when snapping is off.
func _cell_size() -> Vector2:
	var p := _palette()
	if p == null or not p.grid_snap or not Edition.allows(&"grid_snap"):
		return Vector2.ZERO
	var cell := p.cell_size
	if p.use_tileset_cell_size:
		var tile := _find_tile_size(_layer)
		if tile != Vector2.ZERO:
			cell = tile
	if cell.x < 1.0 or cell.y < 1.0:
		return Vector2.ZERO
	return cell


## Tile size of a sibling TileMapLayer, else the first one in the edited scene.
static func _find_tile_size(layer: Node) -> Vector2:
	var parent := layer.get_parent()
	if parent != null:
		for sib in parent.get_children():
			var s := _tile_size_of(sib)
			if s != Vector2.ZERO:
				return s
	var root := _scene_root_of(layer)
	if root != null:
		for n in root.find_children("*", "TileMapLayer", true, false):
			var s := _tile_size_of(n)
			if s != Vector2.ZERO:
				return s
	return Vector2.ZERO


static func _tile_size_of(n: Node) -> Vector2:
	if n is TileMapLayer and n.tile_set != null:
		return Vector2(n.tile_set.tile_size)
	return Vector2.ZERO


static func _snap(p: Vector2, cell: Vector2) -> Vector2:
	return (Vector2(floorf(p.x / cell.x), floorf(p.y / cell.y)) + Vector2(0.5, 0.5)) * cell


# ---------------------------------------------------------------- strokes

func _seed_rng() -> void:
	_stroke_count += 1
	var p := _palette()
	if p.random_seed != 0:
		_rng.seed = hash([p.random_seed, _stroke_count])
	else:
		_rng.randomize()


func _build_hash(layer: ScatterLayer2D) -> Sampler:
	var p := layer.palette
	var h := Sampler.new(maxf(p.min_spacing, p.radius * 0.25))
	for n in layer.get_painted_props():
		h.insert(n)
	return h


func _begin_stroke(kind: int) -> void:
	_stroking = true
	_stroke_kind = kind
	_stroke_layer = _layer
	_stroke_nodes.clear()
	_stroke_old.clear()
	_stroke_hash = _build_hash(_layer)
	_stroke_cell = _cell_size()
	_last_dab = Vector2.INF
	_seed_rng()


func _stroke_dab(local: Vector2, force: bool) -> void:
	if not _stroking or not is_instance_valid(_stroke_layer):
		return
	var p := _stroke_layer.palette
	var step := maxf(p.radius * 0.35, 1.0)
	if not force and _last_dab.distance_to(local) < step:
		return
	_last_dab = local
	match _stroke_kind:
		Stroke.ERASE:
			for at in [local] + _mirrors(local):
				_erase_dab(at, p)
		Stroke.REROLL:
			for at in [local] + _mirrors(local):
				_reroll_dab(at, p)
		_:
			_paint_dab(local, p) # mirrored copies are made per prop, see _add_mirror_copies


func _paint_dab(center: Vector2, p: ScatterPalette) -> void:
	if p.get_active_items().is_empty():
		return
	var target := p.density * PI * p.radius * p.radius / 10000.0
	var existing := _stroke_hash.query_circle(center, p.radius).size()
	var need_f := target - existing
	if need_f <= 0.0:
		return
	var need := floori(need_f)
	if _rng.randf() < need_f - need:
		need += 1
	var points: PackedVector2Array
	if _stroke_cell != Vector2.ZERO:
		points = _snapped_points(center, p, need)
	else:
		points = _stroke_hash.sample(_rng, center, p.radius, need, p.min_spacing)
	for pos in points:
		var node := _spawn(pos, p)
		if node != null:
			_stroke_hash.insert(node)
			_stroke_nodes.append(node)
			for copy in _add_mirror_copies(node, _stroke_layer, _stroke_hash):
				_stroke_nodes.append(copy)


## Free cell centres inside the brush, picked at random, at most `need`.
## A cell is taken if a painted prop sits within half a cell of its centre.
func _snapped_points(center: Vector2, p: ScatterPalette, need: int) -> PackedVector2Array:
	var cell := _stroke_cell
	var half := minf(cell.x, cell.y) * 0.5
	var free := PackedVector2Array()
	var lo := Vector2i(floori((center.x - p.radius) / cell.x), floori((center.y - p.radius) / cell.y))
	var hi := Vector2i(floori((center.x + p.radius) / cell.x), floori((center.y + p.radius) / cell.y))
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var c := (Vector2(x, y) + Vector2(0.5, 0.5)) * cell
			if c.distance_to(center) > p.radius:
				continue
			if _stroke_hash.has_within(c, maxf(half - 0.01, 0.01)):
				continue
			free.append(c)
	# Partial Fisher-Yates so we take `need` random cells.
	var out := PackedVector2Array()
	var n := free.size()
	for i in mini(need, n):
		var j := _rng.randi_range(i, n - 1)
		var tmp := free[i]
		free[i] = free[j]
		free[j] = tmp
		out.append(free[i])
	return out


func _erase_filter(p: ScatterPalette) -> PackedStringArray:
	return p.get_active_source_paths() if p.erase_only_palette else PackedStringArray()


func _erase_dab(center: Vector2, p: ScatterPalette) -> void:
	var only := _erase_filter(p)
	for n in _stroke_hash.query_circle(center, p.radius):
		if p.erase_only_palette and not only.has(String(n.get_meta(ScatterLayer2D.PAINTED_META, ""))):
			continue
		if _rng.randf() > p.erase_strength:
			continue
		_stroke_hash.remove(n)
		_stroke_layer.remove_child(n)
		_stroke_nodes.append(n)


func _reroll_dab(center: Vector2, p: ScatterPalette) -> void:
	for n in _stroke_hash.query_circle(center, p.radius):
		if _stroke_old.has(n):
			continue
		_stroke_old[n] = {"scale": n.scale, "rotation": n.rotation, "modulate": n.modulate}
		var item := p.find_item_by_source(String(n.get_meta(ScatterLayer2D.PAINTED_META, "")))
		Placer.randomize_props(n, Placer.settings_for(item, p), _rng)
		_stroke_nodes.append(n)


func _spawn(pos: Vector2, p: ScatterPalette) -> Node2D:
	if not _tile_ok(pos, _stroke_layer if _stroking else _layer):
		return null
	var item := p.pick_item(_rng)
	if item == null:
		return null
	var node := Placer.build(item, p, _rng, pos)
	if node == null:
		return null
	var layer := _stroke_layer if _stroking else _layer
	node.name = _unique_name(layer, item.get_display_name())
	layer.add_child(node)
	node.owner = _scene_root_of(layer)
	return node


## Cheap readable names without add_child(force_readable_name), which is slow.
func _unique_name(layer: Node, base: String) -> String:
	base = base.validate_node_name()
	if base.is_empty():
		base = "Prop"
	var n := "%s_%d" % [base, _name_counter]
	while layer.has_node(NodePath(n)):
		_name_counter += 1
		n = "%s_%d" % [base, _name_counter]
	_name_counter += 1
	return n


func _place_single(local: Vector2) -> void:
	var p := _palette()
	var cell := _cell_size()
	if cell != Vector2.ZERO:
		local = _snap(local, cell)
		# One prop per cell.
		var h := _build_hash(_layer)
		if h.has_within(local, maxf(minf(cell.x, cell.y) * 0.5 - 0.01, 0.01)):
			return
	_seed_rng()
	var node := _spawn(local, p)
	if node == null:
		return
	var nodes: Array[Node2D] = [node]
	nodes.append_array(_add_mirror_copies(node, _layer, null))
	_record_add_remove(nodes, _layer, false)
	if _dock != null:
		_dock.mark_step("painted")


# ---------------------------------------------------------------- shape tool

func _shape() -> int:
	return _toolbar.shape if _toolbar != null else Toolbar.Shape.LINE


## Snaps a drag point to a grid cell centre when Snap to grid is on.
func _line_snap(local: Vector2) -> Vector2:
	var cell := _cell_size()
	return _snap(local, cell) if cell != Vector2.ZERO else local


## Line: horizontal / vertical / 45° unless Shift. Rectangle and Grid: Shift = square.
func _constrain_line(from: Vector2, to: Vector2, shift: bool) -> Vector2:
	var d := to - from
	match _shape():
		Toolbar.Shape.LINE:
			if shift or d.length() < 0.001:
				return to
			var dir := Vector2.from_angle(snappedf(d.angle(), PI / 4.0))
			return from + dir * d.dot(dir)
		Toolbar.Shape.RECT, Toolbar.Shape.GRID:
			if shift:
				var m := maxf(absf(d.x), absf(d.y))
				return from + Vector2(signf(d.x) if d.x != 0 else 1.0, signf(d.y) if d.y != 0 else 1.0) * m
	return to


## Size of a prop along `dir` (layer space), from its image.
static func _extent(item: ScatterItem, scale: float, dir: Vector2) -> float:
	var t := item.get_thumbnail()
	var size := t.get_size() if t != null else Vector2(32, 32)
	return (absf(dir.x) * size.x + absf(dir.y) * size.y) * scale


## Does this prop turn along the shape? Always when "Turn props along the shape"
## is on. On Line and Rectangle, long props (fences, walls: art at least 1.5x
## wider than tall) turn by themselves too, so a fence running up the screen
## stands the right way. Upright props like trees stay upright.
func _follows(item: ScatterItem, p: ScatterPalette) -> bool:
	if is_tall_prop(item) and _side_kit(p):
		return false # a side piece is already drawn running up the screen
	if p.shape_follow:
		return true
	var shp := _shape()
	if shp != Toolbar.Shape.LINE and shp != Toolbar.Shape.RECT:
		return false
	return is_long_prop(item)


## Side pieces: art at least 1.5x taller than wide, like a fence drawn running
## up the screen. When a layer has both long props and side pieces, Line and
## Rectangle use the side pieces on up-down runs and the long props elsewhere.
static func is_tall_prop(item: ScatterItem) -> bool:
	var t := item.get_thumbnail() if item != null else null
	if t == null:
		return false
	var size := t.get_size()
	return size.x > 0.0 and size.y >= size.x * 1.5


func _side_kit(p: ScatterPalette) -> bool:
	var shp := _shape()
	if shp != Toolbar.Shape.LINE and shp != Toolbar.Shape.RECT:
		return false
	var long := false
	var tall := false
	for it in p.get_active_items():
		long = long or is_long_prop(it)
		tall = tall or is_tall_prop(it)
	return long and tall


## Drawn size of the layer's biggest long prop (a fence piece). Side pieces
## step by its width, so both kinds join on the same spacing.
func _long_size(p: ScatterPalette) -> Vector2:
	var size := Vector2.ZERO
	for it in p.get_active_items():
		if is_long_prop(it):
			size = size.max(it.get_thumbnail().get_size() * _row_scale(Placer.settings_for(it, p)))
	return size


## Picks the next prop for a shape. With a side kit, up-down runs get side
## pieces and other runs get the rest (weights still count within each group).
func _pick_along(p: ScatterPalette, rng: RandomNumberGenerator, dir: Vector2) -> ScatterItem:
	var item := p.pick_item(rng)
	if item == null or not _side_kit(p):
		return item
	var up_down := absf(dir.y) > absf(dir.x) + 0.001
	for i in 50:
		if is_tall_prop(item) == up_down:
			return item
		item = p.pick_item(rng)
	return item


static func is_long_prop(item: ScatterItem) -> bool:
	var t := item.get_thumbnail() if item != null else null
	if t == null:
		return false
	var size := t.get_size()
	return size.y > 0.0 and size.x >= size.y * 1.5


## Every prop in a shape gets the same size: the middle of Smallest and Biggest.
static func _row_scale(s) -> float:
	return (s.scale_min + s.scale_max) * 0.5


## The shape's outline as a dense polyline (layer space), and whether it's closed.
func _shape_outline() -> Array:
	var a := _line_start
	var b := _line_end
	match _shape():
		Toolbar.Shape.RECT:
			return [PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y), a]), true]
		Toolbar.Shape.CIRCLE:
			var r := a.distance_to(b)
			var pts := PackedVector2Array()
			var start := (b - a).angle()
			for i in 129:
				pts.append(a + Vector2.from_angle(start + TAU * i / 128.0) * r)
			return [pts, true]
		Toolbar.Shape.SPIRAL:
			var r := a.distance_to(b)
			var turns := 3.0
			var pts := PackedVector2Array()
			var start := (b - a).angle()
			var n := 384
			for i in n + 1:
				var t := float(i) / n
				pts.append(a + Vector2.from_angle(start + TAU * turns * t - TAU * turns) * r * t)
			return [pts, false]
	return [PackedVector2Array([a, b]), false]


## Where the shape's props go: [[position, item, angle], ...]. Props sit end to
## end along the outline (further apart if Gap between props is bigger), or an
## exact number spread evenly. angle = the shape's direction at that point.
## Uses its own seeded RNG so the preview matches what gets placed.
func _line_points(p: ScatterPalette) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _line_seed if p.random_seed == 0 else hash([p.random_seed, _line_start])
	var out: Array
	if _shape() == Toolbar.Shape.GRID:
		out = _grid_points(p, rng)
	else:
		out = _outline_points(p, rng)
	if p.shape_wobble > 0.0:
		for e in out:
			var size := _extent(e[1], _row_scale(Placer.settings_for(e[1], p)), Vector2.RIGHT)
			e[0] += Vector2.from_angle(rng.randf() * TAU) * rng.randf() * p.shape_wobble * size * 0.5
	return out


func _outline_points(p: ScatterPalette, rng: RandomNumberGenerator) -> Array:
	var ol: Array = _shape_outline()
	if _shape() == Toolbar.Shape.RECT and p.shape_count == 0:
		# Each side starts at its corner, so rows meet neatly at the corners.
		var corners: PackedVector2Array = ol[0]
		var out := []
		for i in 4:
			out.append_array(_walk(p, rng, PackedVector2Array([corners[i], corners[i + 1]]), false))
		return out
	return _walk(p, rng, ol[0], ol[1])


func _walk(p: ScatterPalette, rng: RandomNumberGenerator, poly: PackedVector2Array, closed: bool) -> Array:
	var out := []
	var lengths := PackedFloat32Array()
	var total := 0.0
	for i in poly.size() - 1:
		lengths.append(poly[i].distance_to(poly[i + 1]))
		total += lengths[i]
	# Distances along the outline where props go.
	var at := PackedFloat32Array()
	var items: Array[ScatterItem] = []
	var cell := _cell_size()
	if p.shape_count > 0:
		var n := p.shape_count
		for i in n:
			if n == 1:
				at.append(0.0)
			else:
				at.append(total * i / (n if closed else n - 1))
			var item := _pick_along(p, rng, _dir_at(poly, lengths, at[i]))
			if item == null:
				return out
			items.append(item)
	else:
		# Open shapes (no grid): props fill the line from its start to its end,
		# the first one starting at the start point. A centre-to-centre walk
		# otherwise (closed shapes, grid cells).
		var fill := not closed and cell == Vector2.ZERO
		var walked := 0.0 # fill: end of the previous prop; else: last centre
		var prev_half := -1.0
		while at.size() < 2000:
			var dir := _dir_at(poly, lengths, walked)
			var item := _pick_along(p, rng, dir)
			if item == null:
				break
			var step: float
			if cell != Vector2.ZERO and _shape() == Toolbar.Shape.LINE:
				step = minf(cell.x / maxf(absf(dir.x), 0.0001), cell.y / maxf(absf(dir.y), 0.0001))
			else:
				# A prop turned along the shape always lies lengthways.
				var along := Vector2.RIGHT if _follows(item, p) else dir
				var size := _extent(item, _row_scale(Placer.settings_for(item, p)), along)
				if is_tall_prop(item) and _side_kit(p):
					size = _long_size(p).x # side pieces join on the fence's spacing
				step = maxf(size, p.min_spacing)
			var half := maxf(step, 1.0) * 0.5
			if fill:
				# Allow the last prop to stick out at most half its size.
				if walked + half > total + 0.01:
					break
				at.append(walked + half)
				walked += half * 2.0
			else:
				var advance := 0.0 if prev_half < 0.0 else prev_half + half
				# The last prop of a closed shape must not overlap the first.
				if walked + advance > (total - half if closed else total + 0.01):
					break
				walked += advance
				at.append(walked)
				prev_half = half
			items.append(item)
			if total < 0.001:
				break
		if fill and walked > 0.001 and total > 0.001:
			# Spread the row so it ends exactly where the drag ended (props keep
			# their size; spacing changes by at most half a prop over the row).
			var f := total / walked
			for i in at.size():
				at[i] *= f
	for i in at.size():
		var d := at[i]
		var seg := 0
		while seg < lengths.size() - 1 and d > lengths[seg]:
			d -= lengths[seg]
			seg += 1
		var pos := poly[0] if lengths.is_empty() else poly[seg] + (poly[seg + 1] - poly[seg]).normalized() * minf(d, lengths[seg])
		out.append([pos, items[i], _dir_at(poly, lengths, at[i]).angle()])
	return out


## Direction of the outline `dist` along it.
static func _dir_at(poly: PackedVector2Array, lengths: PackedFloat32Array, dist: float) -> Vector2:
	if lengths.is_empty():
		return Vector2.RIGHT
	var seg := 0
	while seg < lengths.size() - 1 and dist > lengths[seg]:
		dist -= lengths[seg]
		seg += 1
	var d := poly[seg + 1] - poly[seg]
	return d / lengths[seg] if lengths[seg] > 0.001 else Vector2.RIGHT


## Grid: the dragged rectangle filled in even rows, one prop per spot.
func _grid_points(p: ScatterPalette, rng: RandomNumberGenerator) -> Array:
	var out := []
	var cell := _cell_size()
	var step := cell
	if step == Vector2.ZERO:
		for item in p.get_active_items():
			var t := item.get_thumbnail()
			var size := (t.get_size() if t != null else Vector2(32, 32)) * _row_scale(Placer.settings_for(item, p))
			step = step.max(size)
		step = step.max(Vector2(p.min_spacing, p.min_spacing)).max(Vector2.ONE)
	var lo := _line_start.min(_line_end)
	var hi := _line_start.max(_line_end)
	var cols := floori((hi.x - lo.x) / step.x + 0.01) + 1
	var rows := floori((hi.y - lo.y) / step.y + 0.01) + 1
	if cols * rows > 2000:
		return out
	for y in rows:
		for x in cols:
			var item := p.pick_item(rng)
			if item == null:
				return out
			out.append([lo + Vector2(x, y) * step, item, 0.0])
	return out


func _draw_line_overlay(overlay: Control, es: float) -> void:
	var xf := _canvas_xform()
	if _line_start == Vector2.INF:
		var at := xf * _line_snap(_to_local(_mouse_screen))
		overlay.draw_circle(at, 4.0 * es, PAINT_COLOR)
		return
	var font := overlay.get_theme_default_font()
	if _shape() == Toolbar.Shape.FILL:
		if _fill_points.size() > 1:
			var closed := _fill_points.duplicate()
			closed.append(_fill_points[0])
			overlay.draw_polyline(xf * closed, PAINT_COLOR, 2.0 * es, true)
			for m in _mirror_polys(_fill_points):
				m.append(m[0])
				overlay.draw_polyline(xf * m, Color(PAINT_COLOR, 0.45), 1.5 * es, true)
		overlay.draw_string(font, _mouse_screen + Vector2(12, -12) * es, "Release to fill",
			HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14 * es), PAINT_COLOR)
		return
	if _shape() == Toolbar.Shape.GRID:
		var r := Rect2(_line_start.min(_line_end), (_line_end - _line_start).abs())
		overlay.draw_rect(Rect2(xf * r.position, xf.basis_xform(r.size)).abs(), PAINT_COLOR, false, 2.0 * es)
	else:
		var poly: PackedVector2Array = _shape_outline()[0]
		overlay.draw_polyline(xf * poly, PAINT_COLOR, 2.0 * es, true)
	var pts := _line_points(_palette())
	var n := 0
	for e in pts:
		for at in [e[0]] + _mirrors(e[0]):
			var ok := _tile_ok(at, _layer)
			overlay.draw_arc(xf * at, 6.0 * es, 0.0, TAU, 16, PAINT_COLOR if ok else Color(ERASE_COLOR, 0.6), 2.0 * es, true)
			n += 1 if ok else 0
	overlay.draw_string(font, xf * _line_end + Vector2(12, -12) * es, "%d prop%s" % [n, "" if n == 1 else "s"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(14 * es), PAINT_COLOR)


## Builds one shape/fill prop, or null if it can't go there.
func _shape_prop(item: ScatterItem, pos: Vector2, angle: float, p: ScatterPalette, rng: RandomNumberGenerator, tidy: bool) -> Node2D:
	if not _tile_ok(pos, _layer):
		return null
	var node := Placer.build(item, p, rng, pos)
	if node == null:
		return null
	if tidy:
		var sc := _row_scale(Placer.settings_for(item, p))
		node.scale = Vector2(sc * signf(node.scale.x), sc * signf(node.scale.y)) # keep mirroring, drop size jitter
		var a := angle if _follows(item, p) else 0.0 # shapes stay tidy
		if is_long_prop(item):
			# Never upside down: a fence drawn right to left still stands up.
			if a > PI / 2.0 + 0.001:
				a -= PI
			elif a < -PI / 2.0 - 0.001:
				a += PI
			if absf(a) < 0.0001:
				a = 0.0
		node.rotation = a
		if node is Sprite2D and is_tall_prop(item) and _side_kit(p):
			# Line the side piece up with the long pieces: it covers its run
			# from the bottom edge of the top row to the bottom edge of the
			# bottom row, so the corners meet.
			# Its bottom edge goes where the run ends (one long-piece width on).
			var long := _long_size(p)
			var y := long.x * 0.5
			if node.centered:
				y += long.y * 0.5 - node.texture.get_size().y * sc * 0.5
			node.position.y += y
	node.name = _unique_name(_layer, item.get_display_name())
	_layer.add_child(node)
	node.owner = _scene_root_of(_layer)
	return node


func _place_line() -> void:
	var p := _palette()
	var pts := _line_points(p)
	_line_start = Vector2.INF
	update_overlays()
	if pts.is_empty():
		return
	var h := _build_hash(_layer)
	var rng := RandomNumberGenerator.new()
	rng.seed = _line_seed
	var nodes: Array[Node2D] = []
	for e in pts:
		# Drawing over an existing shape doesn't double it up.
		if h.has_within(e[0], 1.0):
			continue
		var node := _shape_prop(e[1], e[0], e[2], p, rng, true)
		if node != null:
			h.insert(node)
			nodes.append(node)
			nodes.append_array(_add_mirror_copies(node, _layer, h))
	if _shape() == Toolbar.Shape.LINE or _shape() == Toolbar.Shape.RECT:
		nodes.append_array(_end_posts(nodes))
	_commit_shape(nodes)


## Fence art usually has its post at one end only, so a row stops on bare
## rails. Where a fence piece's post-less end meets no other piece's post, add
## an end post: a copy of the piece showing only its post.
func _end_posts(nodes: Array[Node2D]) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var starts := [] # where each fence piece's post stands
	var ends := [] # [point, piece] at each piece's post-less end
	for n in nodes:
		if not n is Sprite2D or n.region_enabled or n.texture == null:
			continue
		var size: Vector2 = n.texture.get_size()
		if size.x < size.y * 1.5 or _post_width(n.texture) == 0:
			continue
		var half := Vector2(size.x * 0.5 * n.scale.x, 0.0).rotated(n.rotation)
		starts.append(n.position - half)
		ends.append([n.position + half, n])
	for e in ends:
		var covered := false
		for st: Vector2 in starts:
			if st.distance_to(e[0]) < 2.0:
				covered = true
				break
		if covered:
			continue
		var piece: Sprite2D = e[1]
		var size: Vector2 = piece.texture.get_size()
		var cap: Sprite2D = piece.duplicate()
		cap.region_enabled = true
		cap.region_rect = Rect2(0, 0, _post_width(piece.texture), size.y)
		if cap.centered:
			cap.centered = false
			cap.offset = -size * 0.5
		cap.position = piece.position + Vector2(size.x * piece.scale.x, 0.0).rotated(piece.rotation)
		cap.name = _unique_name(_layer, String(piece.name).rstrip("0123456789_") + "_end")
		_layer.add_child(cap)
		cap.owner = _scene_root_of(_layer)
		starts.append(e[0]) # two pieces ending at the same spot get one post
		out.append(cap)
	return out


## Width of the post at the left end of fence art (the opaque columns that are
## clearly taller than the rails), or 0 when the art has no such post there or
## also has one at its right end.
func _post_width(tex: Texture2D) -> int:
	if _post_cache.has(tex):
		return _post_cache[tex]
	var w := 0
	var img := tex.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		var cols := PackedInt32Array()
		var top := 0
		for x in img.get_width():
			var c := 0
			for y in img.get_height():
				if img.get_pixel(x, y).a > 0.5:
					c += 1
			cols.append(c)
			top = maxi(top, c)
		var tall := func(x: int) -> bool: return cols[x] >= top * 0.75
		var quarter := img.get_width() / 4
		var x := 0
		while x < quarter and not tall.call(x):
			x += 1
		var end := x
		while end < quarter and tall.call(end):
			end += 1
		var right_post: bool = tall.call(img.get_width() - 1) or tall.call(img.get_width() - 2)
		if x < quarter and end < quarter and not right_post:
			w = end
	_post_cache[tex] = w
	return w


## Fill area: scatter inside the drawn outline using Amount and Gap, like Paint.
func _place_fill() -> void:
	var p := _palette()
	var outline := _fill_points
	_line_start = Vector2.INF
	_fill_points = PackedVector2Array()
	update_overlays()
	if outline.size() < 3 or p.get_active_items().is_empty():
		return
	var h := _build_hash(_layer)
	var rng := RandomNumberGenerator.new()
	rng.seed = _line_seed if p.random_seed == 0 else hash([p.random_seed, outline[0]])
	var nodes: Array[Node2D] = []
	for poly in [outline]:
		var box := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			box = box.expand(q)
		var area := absf(_poly_area(poly))
		var want := mini(roundi(p.density * area / 10000.0), 5000)
		var tries := want * 30
		var placed := 0
		while placed < want and tries > 0:
			tries -= 1
			var q := box.position + Vector2(rng.randf(), rng.randf()) * box.size
			if not Geometry2D.is_point_in_polygon(q, poly):
				continue
			if p.min_spacing > 0.0 and h.has_within(q, p.min_spacing):
				continue
			var item := p.pick_item(rng)
			if item == null:
				break
			var node := _shape_prop(item, q, 0.0, p, rng, false)
			if node != null:
				h.insert(node)
				nodes.append(node)
				nodes.append_array(_add_mirror_copies(node, _layer, h))
				placed += 1
	_commit_shape(nodes)


static func _poly_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var j := (i + 1) % poly.size()
		a += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	return a * 0.5


func _commit_shape(nodes: Array[Node2D]) -> void:
	if nodes.is_empty():
		return
	_record_add_remove(nodes, _layer, false)
	if _dock != null:
		_dock.mark_step("painted")
		_dock.mark_step("shape")


# ---------------------------------------------------------------- mirror painting

## Mirrored copies of a point (layer space) for Mirror painting; empty when off.
## Points on a mirror line don't get a duplicate.
func _mirrors(pos: Vector2) -> Array:
	var p := _palette()
	if p == null or p.mirror_mode == 0 or not Edition.allows(&"mirror"):
		return []
	var c := p.mirror_center
	var out := []
	var lr := p.mirror_mode == 1 or p.mirror_mode == 3
	var ud := p.mirror_mode == 2 or p.mirror_mode == 3
	var mx := Vector2(2.0 * c.x - pos.x, pos.y)
	var my := Vector2(pos.x, 2.0 * c.y - pos.y)
	if lr and absf(pos.x - c.x) > 0.5:
		out.append(mx)
	if ud and absf(pos.y - c.y) > 0.5:
		out.append(my)
	if lr and ud and absf(pos.x - c.x) > 0.5 and absf(pos.y - c.y) > 0.5:
		out.append(Vector2(mx.x, my.y))
	return out


## Exact mirror images of a just-placed prop (same prop, same size and color,
## flipped), so Mirror painting gives a truly symmetrical result.
func _add_mirror_copies(node: Node2D, layer: ScatterLayer2D, h: Sampler) -> Array[Node2D]:
	var out: Array[Node2D] = []
	var spots := _mirrors(node.position)
	if spots.is_empty():
		return out
	var p := layer.palette
	var item := p.find_item_by_source(String(node.get_meta(ScatterLayer2D.PAINTED_META, "")))
	if item == null:
		return out
	for at: Vector2 in spots:
		if not _tile_ok(at, layer) or (h != null and h.has_within(at, 0.5)):
			continue
		var copy := Placer.build(item, p, _rng, at)
		if copy == null:
			continue
		var fx := not is_equal_approx(at.x, node.position.x)
		var fy := not is_equal_approx(at.y, node.position.y)
		# Left/right copies are flipped like a mirror image. Up/down copies keep
		# standing upright (an upside-down tree is never what you want).
		copy.scale = node.scale * Vector2(-1.0 if fx else 1.0, 1.0)
		copy.rotation = -node.rotation if fx != fy else node.rotation
		copy.modulate = node.modulate
		copy.name = _unique_name(layer, item.get_display_name())
		layer.add_child(copy)
		copy.owner = _scene_root_of(layer)
		if h != null:
			h.insert(copy)
		out.append(copy)
	return out


func _mirror_polys(poly: PackedVector2Array) -> Array:
	var p := _palette()
	if p == null or p.mirror_mode == 0 or not Edition.allows(&"mirror"):
		return []
	var c := p.mirror_center
	var out := []
	var flips := []
	if p.mirror_mode == 1 or p.mirror_mode == 3:
		flips.append(Vector2(-1, 1))
	if p.mirror_mode == 2 or p.mirror_mode == 3:
		flips.append(Vector2(1, -1))
	if p.mirror_mode == 3:
		flips.append(Vector2(-1, -1))
	for f in flips:
		var m := PackedVector2Array()
		for q in poly:
			m.append(c + (q - c) * f)
		out.append(m)
	return out


func _draw_mirror_lines(overlay: Control, es: float) -> void:
	var p := _palette()
	if p.mirror_mode == 0 or not Edition.allows(&"mirror"):
		return
	var xf := _canvas_xform()
	var c := xf * p.mirror_center
	var size := overlay.size
	var col := Color(1.0, 0.85, 0.3, 0.8)
	if p.mirror_mode == 1 or p.mirror_mode == 3:
		overlay.draw_dashed_line(Vector2(c.x, 0), Vector2(c.x, size.y), col, 2.0 * es, 10.0 * es)
	if p.mirror_mode == 2 or p.mirror_mode == 3:
		overlay.draw_dashed_line(Vector2(0, c.y), Vector2(size.x, c.y), col, 2.0 * es, 10.0 * es)
	overlay.draw_string(overlay.get_theme_default_font(), c + Vector2(6, -6) * es, "Mirror",
		HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(12 * es), col)


## Centre of the visible 2D view, in the layer's space (where the mirror line goes).
func view_center_local() -> Vector2:
	if not is_instance_valid(_layer):
		return Vector2.ZERO
	var vp := EditorInterface.get_editor_viewport_2d()
	return _canvas_xform().affine_inverse() * (Vector2(vp.size) * 0.5)


# ---------------------------------------------------------------- only on tiles

## The TileMapLayer used by "Only on my TileMap": a sibling first, else the first in the scene.
static func _find_tilemap(layer: Node) -> TileMapLayer:
	var parent := layer.get_parent()
	if parent != null:
		for sib in parent.get_children():
			if sib is TileMapLayer and sib.tile_set != null:
				return sib
	var root := _scene_root_of(layer)
	if root != null:
		for n in root.find_children("*", "TileMapLayer", true, false):
			if n.tile_set != null:
				return n
	return null


static func _tile_at(layer: Node2D, tm: TileMapLayer, pos: Vector2) -> Vector2i:
	return tm.local_to_map(tm.to_local(layer.to_global(pos)))


## True if a prop may go at `pos` (layer space) under the "Only on my TileMap" setting.
func _tile_ok(pos: Vector2, layer: ScatterLayer2D) -> bool:
	if not is_instance_valid(layer):
		return true
	var p := layer.palette
	if p == null or not p.only_on_tiles or not Edition.allows(&"tile_mask"):
		return true
	var tm := _find_tilemap(layer)
	if tm == null:
		return true # nothing to test against; the panel says so
	var cell := _tile_at(layer, tm, pos)
	var src := tm.get_cell_source_id(cell)
	if src == -1:
		return false
	if p.only_tile_source == -1:
		return true
	return src == p.only_tile_source and tm.get_cell_atlas_coords(cell) == p.only_tile_coords


## Dock asks: the next click in the 2D view picks a tile type.
func start_tile_pick() -> void:
	_picking_tile = true
	update_overlays()


func _pick_tile(local: Vector2) -> void:
	_picking_tile = false
	update_overlays()
	var tm := _find_tilemap(_layer)
	if tm == null:
		_dock.tile_pick_done("")
		return
	var cell := _tile_at(_layer, tm, local)
	var src := tm.get_cell_source_id(cell)
	if src == -1:
		_dock.tile_pick_done("")
		return
	var p := _palette()
	var ur := get_undo_redo()
	ur.create_action("Pick scatter tile", UndoRedo.MERGE_DISABLE, p)
	for prop in [["only_tile_source", src], ["only_tile_coords", tm.get_cell_atlas_coords(cell)], ["only_on_tiles", true]]:
		ur.add_do_property(p, prop[0], prop[1])
		ur.add_undo_property(p, prop[0], p.get(prop[0]))
	ur.add_do_method(_dock, &"refresh")
	ur.add_undo_method(_dock, &"refresh")
	ur.commit_action()
	_dock.tile_pick_done(tile_label(p))


## Plain words for the picked tile type, for the panel (its picture is shown next to it).
func tile_label(p: ScatterPalette) -> String:
	if p.only_tile_source == -1:
		return "any tile"
	return "only this tile type (tile %d,%d)" % [p.only_tile_coords.x, p.only_tile_coords.y]


## A picture of the picked tile type, or null (any tile, or not an atlas tile).
func tile_texture(p: ScatterPalette) -> Texture2D:
	if p == null or p.only_tile_source == -1 or not is_instance_valid(_layer):
		return null
	var tm := _find_tilemap(_layer)
	if tm == null or not tm.tile_set.has_source(p.only_tile_source):
		return null
	var src := tm.tile_set.get_source(p.only_tile_source) as TileSetAtlasSource
	if src == null or src.texture == null or not src.has_tile(p.only_tile_coords):
		return null
	var at := AtlasTexture.new()
	at.atlas = src.texture
	at.region = src.get_tile_texture_region(p.only_tile_coords)
	return at


func has_tilemap() -> bool:
	return is_instance_valid(_layer) and _find_tilemap(_layer) != null


# ---------------------------------------------------------------- lock

## Turns the layer's painted props into ordinary nodes the brushes leave alone.
func lock_painted_props() -> int:
	if not is_instance_valid(_layer):
		return 0
	var props := _layer.get_painted_props()
	if props.is_empty():
		return 0
	var ur := get_undo_redo()
	ur.create_action("Lock scatter props", UndoRedo.MERGE_DISABLE, _scene_root_of(_layer))
	for n in props:
		ur.add_do_method(n, &"remove_meta", ScatterLayer2D.PAINTED_META)
		ur.add_undo_method(n, &"set_meta", ScatterLayer2D.PAINTED_META, n.get_meta(ScatterLayer2D.PAINTED_META))
	ur.commit_action()
	return props.size()


func _end_stroke() -> void:
	if not _stroking:
		return
	_stroking = false
	if is_instance_valid(_stroke_layer) and not _stroke_nodes.is_empty():
		match _stroke_kind:
			Stroke.REROLL:
				_record_reroll(_stroke_nodes.duplicate())
			_:
				_record_add_remove(_stroke_nodes.duplicate(), _stroke_layer, _stroke_kind == Stroke.ERASE)
		if _dock != null:
			_dock.mark_step("erased" if _stroke_kind == Stroke.ERASE else "painted")
	_stroke_nodes.clear()
	_stroke_old.clear()
	_stroke_hash = null
	_stroke_layer = null
	update_overlays()


## Throws away a stroke in progress (used when the plugin is disabled mid-drag).
func _cancel_stroke() -> void:
	if not _stroking:
		return
	_stroking = false
	if is_instance_valid(_stroke_layer):
		for n in _stroke_nodes:
			match _stroke_kind:
				Stroke.ERASE:
					_stroke_layer.add_child(n)
					n.owner = _scene_root_of(_stroke_layer)
				Stroke.REROLL:
					for prop in _stroke_old[n]:
						n.set(prop, _stroke_old[n][prop])
				_:
					_stroke_layer.remove_child(n)
					n.free()
	_stroke_nodes.clear()
	_stroke_old.clear()
	_stroke_layer = null


## One undo step for everything a stroke did. The changes already happened
## live, so commit_action(false) records without re-running them.
func _record_add_remove(nodes: Array[Node2D], layer: ScatterLayer2D, erase: bool) -> void:
	var root := _scene_root_of(layer)
	var ur := get_undo_redo()
	ur.create_action("Scatter erase" if erase else "Scatter paint", UndoRedo.MERGE_DISABLE, root)
	for n in nodes:
		if erase:
			ur.add_do_method(layer, &"remove_child", n)
			ur.add_undo_method(layer, &"add_child", n)
			ur.add_undo_method(n, &"set_owner", root)
			ur.add_undo_reference(n)
		else:
			ur.add_do_method(layer, &"add_child", n)
			ur.add_do_method(n, &"set_owner", root)
			ur.add_do_reference(n)
			ur.add_undo_method(layer, &"remove_child", n)
	ur.commit_action(false)


func _record_reroll(nodes: Array[Node2D]) -> void:
	var ur := get_undo_redo()
	ur.create_action("Scatter re-roll", UndoRedo.MERGE_DISABLE, _scene_root_of(nodes[0].get_parent()))
	for n in nodes:
		var old: Dictionary = _stroke_old[n]
		for prop in old:
			ur.add_do_property(n, prop, n.get(prop))
			ur.add_undo_property(n, prop, old[prop])
	ur.commit_action(false)
