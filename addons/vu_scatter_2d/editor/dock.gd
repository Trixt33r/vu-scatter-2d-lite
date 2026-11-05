@tool
extends ScrollContainer
## Side dock: palette list with drag-and-drop, brush, randomness and placement.
## Built in code (no .tscn) so it scales with the editor and stays easy to gate.

signal settings_changed

const Edition := preload("res://addons/vu_scatter_2d/edition.gd")

var undo_redo: EditorUndoRedoManager

var _layer: ScatterLayer2D
var _palette: ScatterPalette
var _es := 1.0
var _refreshing := false
var _rebuild_queued := false

var _root: VBoxContainer
var _hint: Label
var _content: VBoxContainer
var _palette_label: Label
var _items_box: VBoxContainer
var _drop_zone: Label
var _fields := {} # property name -> control
var _file_dialog: EditorFileDialog
var _guide_btn: Button

# Getting-started tutorial (steps tick off as the user does them).
const TUTORIAL_STEPS := [
	["layer", "Click \"+ Add scatter layer\"."],
	["props", "Click \"Use example props\", or drag your own images in below."],
	["painted", "Drag over your level to paint."],
	["erased", "Shift + drag erases. Ctrl+Z undoes."],
	["shape", "Straight rows (fences, walls): press U and drag. It snaps straight."], # Pro only
]
var _tut_panel: PanelContainer
var _tut_labels := {} # step key -> Label
var _tut_done_label: Label
var _tut_show_btn: Button
var _tut_restart_btn: Button
var _add_layer_btn: Button
var _creating_scene := false
var _example_btn: Button
var _new_layer_btn: Button
var _notice: Label
var plugin: EditorPlugin # set by plugin.gd: tile picking, lock, view centre
var _sections := {} # title -> header Button
var _tile_status: Label
var _tile_icon: TextureRect
var _tools_status: Label
var _stats: Label
var _stats_timer := 0.0
var _items_header: Label

## Asks the plugin to switch to Paint (after the first props are added).
signal start_painting

## Shipped inside the addon, so "Use example props" works in an empty project.
const EXAMPLES := "res://addons/vu_scatter_2d/examples/"
const EXAMPLE_PROPS := [
	EXAMPLES + "tree_round.svg", EXAMPLES + "bush.svg",
	EXAMPLES + "rock.svg", EXAMPLES + "tree_pine.svg",
]
## Where "+ Add scatter layer" saves a new scene when none is open.
const NEW_SCENE_PATH := "res://level.tscn"
var _progress := {} # step key -> true, saved per project


func _process(delta: float) -> void:
	_stats_timer -= delta
	if _stats_timer > 0.0 or _stats == null or not is_visible_in_tree():
		return
	_stats_timer = 0.5
	_refresh_hint()
	var n := _layer.get_painted_props().size() if is_instance_valid(_layer) else 0
	_stats.text = "Painted on this layer: %d props" % n
	_stats.visible = n > 0


func _init() -> void:
	name = "Vu Scatter"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _ready() -> void:
	_es = EditorInterface.get_editor_scale()
	custom_minimum_size = Vector2(180, 200) * _es
	_build_ui()
	set_layer(null)


# ---------------------------------------------------------------- binding

func set_layer(layer: ScatterLayer2D) -> void:
	if is_instance_valid(_layer) and _layer.palette_changed.is_connected(_on_layer_palette_changed):
		_layer.palette_changed.disconnect(_on_layer_palette_changed)
	_layer = layer
	if _layer != null:
		_layer.palette_changed.connect(_on_layer_palette_changed)
	_bind_palette(layer.palette if layer != null else null)
	if _hint == null:
		return
	_hint.visible = layer == null
	_refresh_hint()
	_add_layer_btn.visible = layer == null
	_new_layer_btn.visible = layer != null
	_content.visible = layer != null
	_refresh_tutorial()


func _on_layer_palette_changed() -> void:
	if is_instance_valid(_layer):
		_bind_palette(_layer.palette)
		settings_changed.emit()


func _bind_palette(p: ScatterPalette) -> void:
	if _palette == p:
		refresh()
		return
	if _palette != null and _palette.changed.is_connected(_queue_rebuild):
		_palette.changed.disconnect(_queue_rebuild)
	_palette = p
	if _palette != null:
		_palette.changed.connect(_queue_rebuild)
	refresh()


## Re-reads every field from the palette (call after outside changes, e.g. [ ]).
func refresh() -> void:
	if _content == null:
		return
	_refreshing = true
	for prop in _fields:
		var c: Control = _fields[prop]
		var v = _get_field(prop)
		if v == null:
			continue
		if c is EditorSpinSlider:
			c.value = v
		elif c is CheckBox:
			c.button_pressed = v
		elif c is ColorPickerButton:
			c.color = v
		elif c is OptionButton:
			c.selected = int(v)
	_refreshing = false
	if _palette == null:
		_palette_label.text = ""
	elif _palette.resource_path.is_empty() or _palette.resource_path.contains("::"):
		_palette_label.text = "Settings are saved in this scene (no preset file)."
	else:
		_palette_label.text = "Using preset: " + _palette.resource_path.get_file()
	_refresh_tile_status()
	_rebuild_items()
	var has_items := _palette != null and not _palette.items.is_empty()
	_example_btn.visible = not has_items and not _example_paths().is_empty()
	_items_header.visible = has_items
	_refresh_tutorial()
	settings_changed.emit() # keeps the toolbar's prop strip in sync


## Field keys are property names, or "prop:x" / "prop:y" for a Vector2 component.
func _get_field(key: String) -> Variant:
	if _palette == null:
		return null
	var parts := key.split(":")
	var v = _palette.get(parts[0])
	if parts.size() > 1 and v is Vector2:
		return v.x if parts[1] == "x" else v.y
	return v


func _set_field(key: String, value: Variant) -> void:
	var parts := key.split(":")
	if parts.size() > 1:
		var v: Vector2 = _palette.get(parts[0])
		if parts[1] == "x":
			v.x = value
		else:
			v.y = value
		_palette.set(parts[0], v)
	elif key in ["random_seed", "z_index", "shape_count", "mirror_mode"]:
		_palette.set(key, int(value))
	else:
		_palette.set(key, value)


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	(func():
		_rebuild_queued = false
		if is_inside_tree():
			refresh()
	).call_deferred()


func _mark_dirty() -> void:
	EditorInterface.mark_scene_as_unsaved()
	settings_changed.emit()


# ---------------------------------------------------------------- UI build

func _build_ui() -> void:
	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_root)

	var title_row := HBoxContainer.new()
	var title := Label.new()
	title.text = Edition.display_name()
	title.add_theme_font_size_override(&"font_size", roundi(15 * _es))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_tut_show_btn = _make_button("Tutorial", "Show the getting-started steps again.", func(): _set_tutorial_hidden(false))
	_tut_show_btn.flat = true
	_guide_btn = _make_button("?", "User guide: opens the full guide (with pictures) in your web browser.", _open_guide)
	_guide_btn.flat = true
	_new_layer_btn = _make_button("+ New layer",
		"Adds another layer that draws behind this one, e.g. trees here, grass on the new layer. Drag layers in the Scene dock to change what draws on top.", _add_layer)
	_new_layer_btn.flat = true
	title_row.add_child(_new_layer_btn)
	title_row.add_child(_tut_show_btn)
	title_row.add_child(_guide_btn)
	_root.add_child(title_row)

	_build_tutorial()

	_hint = Label.new()
	_hint.text = "Props are painted into a scatter layer. Add one, or select one in the Scene dock."
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_hint)
	_add_layer_btn = _make_button("+ Add scatter layer",
		"Adds a ScatterLayer2D node to the open scene (under the selected node) and selects it.", _add_layer)
	_root.add_child(_add_layer_btn)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override(&"separation", roundi(4 * _es))
	_root.add_child(_content)

	# Props: what gets painted.
	var props := _add_section("What to paint")
	_drop_zone = Label.new()
	_drop_zone.text = "Drag images, .tscn scenes or a folder\nhere from the FileSystem dock"
	if Edition.max_items() >= 0:
		_drop_zone.text += "\n(Lite: up to %d)" % Edition.max_items()
	_drop_zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drop_zone.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_drop_zone.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_drop_zone.custom_minimum_size = Vector2(0, 56 * _es)
	_drop_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(maxi(1, roundi(_es)))
	sb.set_corner_radius_all(roundi(4 * _es))
	_drop_zone.add_theme_stylebox_override(&"normal", sb)
	props.add_child(_drop_zone)
	_notice = Label.new()
	_notice.add_theme_color_override(&"font_color", Color(1.0, 0.75, 0.4))
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.visible = false
	props.add_child(_notice)
	_example_btn = _make_button("Use example props",
		"No art yet? Adds a few trees, bushes and rocks that come with the plugin, so you can try painting right away.", _use_example_props)
	props.add_child(_example_btn)
	_items_header = Label.new()
	_items_header.text = "Tick = use it · number = how often it appears" if Edition.allows(&"weights") else "Tick = use it"
	_items_header.modulate = Color(1, 1, 1, 0.6)
	_items_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	props.add_child(_items_header)
	_items_box = VBoxContainer.new()
	props.add_child(_items_box)
	_stats = Label.new()
	_stats.modulate = Color(1, 1, 1, 0.6)
	_stats.tooltip_text = "How many props the brush has painted on the selected layer."
	_stats.mouse_filter = Control.MOUSE_FILTER_PASS
	props.add_child(_stats)
	# Drops anywhere on the dock add props.
	for c: Control in [self, _drop_zone, _items_box]:
		c.set_drag_forwarding(Callable(), _can_drop, _drop)

	# Brush: the everyday settings.
	var brush := _add_section("Brush")
	_add_number(brush, "Brush size", "radius", 4, 4096, 1, "Brush radius in pixels. Shortcut: [ and ].")
	_add_number(brush, "Amount", "density", 0.01, 100, 0.01, "How many props per 100 × 100 pixels. 1 = sparse, 5 = lush.")
	_add_number(brush, "Gap between props", "min_spacing", 0, 1024, 1, "Props never get closer than this (pixels). 0 lets them overlap.")

	# Variety: what makes it look natural.
	var rnd := _add_section("Variety")
	_add_number(rnd, "Smallest size", "scale_min", 0.05, 10, 0.01, "Each prop gets a random size between Smallest and Biggest. 1 = original size, 0.5 = half.")
	_add_number(rnd, "Biggest size", "scale_max", 0.05, 10, 0.01, "Each prop gets a random size between Smallest and Biggest. 1 = original size, 2 = double.")
	_add_number(rnd, "Tilt (± degrees)", "rotation_range_deg", 0, 180, 0.5, "Random rotation either way. Keep 0 for trees, use it for rocks and debris.")
	if Edition.allows(&"flip"):
		_add_number(rnd, "Mirror left/right", "flip_h_chance", 0, 1, 0.01, "Chance (0 to 1) to mirror a prop horizontally. 0.5 = half of them.")
		_add_number(rnd, "Mirror up/down", "flip_v_chance", 0, 1, 0.01, "Chance (0 to 1) to mirror a prop vertically.")
	if Edition.allows(&"tint"):
		_add_color(rnd, "Color", "tint")
		_add_number(rnd, "Color variation", "tint_jitter", 0, 1, 0.01, "Varies brightness and hue a little per prop. 0.2 to 0.3 looks natural.")

	# Placement: folded away until needed.
	if Edition.allows(&"z_index") or Edition.allows(&"feet_anchor") or Edition.allows(&"grid_snap"):
		var place := _add_section("Placement", true)
		if Edition.allows(&"feet_anchor"):
			_add_check(place, "Images stand on their bottom edge", "anchor_at_feet", "Each image stands where you click (its base), so rows line up and Y-sort draws the nearer prop in front. Turned on by itself when you add your first images.")
		if Edition.allows(&"grid_snap"):
			_add_check(place, "Snap to grid", "grid_snap", "One prop per grid cell, centred.")
			_add_check(place, "Use my TileMap's grid", "use_tileset_cell_size", "Takes the cell size from a TileMapLayer next to this layer (or the first one in the scene).")
			_add_number(place, "Grid width", "cell_size:x", 1, 1024, 1, "Used when not taking the TileMap's grid.")
			_add_number(place, "Grid height", "cell_size:y", 1, 1024, 1, "Used when not taking the TileMap's grid.")
		if Edition.allows(&"z_index"):
			_add_number(place, "Draw order", "z_index", -4096, 4096, 1, "Z index of painted props. Higher draws on top, e.g. -1 to draw behind the player.")
		if Edition.allows(&"tile_mask"):
			_add_check(place, "Only on my TileMap", "only_on_tiles", "Props only land where your TileMapLayer has a tile, e.g. grass on land but not in water. Uses the TileMapLayer next to this layer (or the first one in the scene).")
			var srow := HBoxContainer.new()
			_tile_icon = TextureRect.new()
			_tile_icon.custom_minimum_size = Vector2(24, 24) * _es
			_tile_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_tile_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_tile_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_tile_icon.tooltip_text = "The tile type props land on."
			srow.add_child(_tile_icon)
			_tile_status = Label.new()
			_tile_status.modulate = Color(1, 1, 1, 0.7)
			_tile_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_tile_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			srow.add_child(_tile_status)
			place.add_child(srow)
			var trow := HBoxContainer.new()
			trow.add_child(_make_button("Pick tile type…", "Then click a tile in the 2D view: props will only land on tiles of that type (e.g. only on grass).", _on_pick_tile))
			trow.add_child(_make_button("Any tile", "Props land on every tile, whatever its type.", _on_any_tile))
			place.add_child(trow)

	# Shape tool options (Pro).
	if Edition.allows(&"line"):
		var shp := _add_section("Shape options", true)
		var hint := Label.new()
		hint.text = "Pick the shape (Line, Rectangle…) in the top toolbar. These settings change how it's filled."
		hint.modulate = Color(1, 1, 1, 0.6)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		shp.add_child(hint)
		_add_number(shp, "Number of props", "shape_count", 0, 500, 1, "0 = automatic: props sit end to end (or further apart if Gap between props is bigger). Any other number spreads exactly that many evenly along the shape.")
		_add_check(shp, "Turn props along the shape", "shape_follow", "Each prop turns to follow the line, circle or spiral, like a fence going round a corner. Off = props stay upright, except long props like fences, which still turn along a Line or Rectangle. Tip: add a side piece (the fence drawn running up the screen) to the layer and Line and Rectangle use it for up-down runs instead of turning.")
		_add_number(shp, "Wobble", "shape_wobble", 0, 1, 0.01, "Small random offsets so rows look placed by hand. 0 = perfectly tidy, 0.2 = natural.")

	# Mirror painting (Pro).
	if Edition.allows(&"mirror"):
		var mir := _add_section("Mirror painting", true)
		_add_option(mir, "Mirror", "mirror_mode", ["Off", "Left ↔ right", "Up ↕ down", "Both"], "Everything you paint, erase or place also happens on the other side of the yellow mirror line(s). Great for symmetrical gardens, arenas and town squares.")
		mir.add_child(_make_button("Put mirror line in the middle of the view", "Moves the mirror line(s) to the centre of what you see in the 2D view.", _on_center_mirror))
		_add_number(mir, "Mirror line X", "mirror_center:x", -100000, 100000, 1, "Where the left/right mirror line is (in this layer's pixels).")
		_add_number(mir, "Mirror line Y", "mirror_center:y", -100000, 100000, 1, "Where the up/down mirror line is (in this layer's pixels).")

	# Erasing and repeatability: folded away.
	var adv := _add_section("Erasing & more", true)
	_add_number(adv, "Erase strength", "erase_strength", 0.05, 1, 0.01, "1 removes everything under the brush. Lower values thin props out.")
	_add_check(adv, "Erase only the props listed above", "erase_only_palette", "Erase only removes props that are ticked in the list above. Untick the trees to erase just the grass.")
	_add_number(adv, "Random seed", "random_seed", 0, 2147483647, 1, "0 = new randomness every stroke. Any other number repeats the same result.")
	var arow := HBoxContainer.new()
	arow.add_child(_make_button("Clear layer", "Removes every prop the brush painted on this layer. Ctrl+Z brings them back.", _on_clear_layer))
	arow.add_child(_make_button("Lock props", "Turns this layer's painted props into ordinary nodes: Erase and Clear layer won't remove them anymore. Use it when a patch is finished. Ctrl+Z undoes.", _on_lock_props))
	adv.add_child(arow)
	_tools_status = Label.new()
	_tools_status.modulate = Color(1, 1, 1, 0.7)
	_tools_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	adv.add_child(_tools_status)

	# Presets (Pro): folded away.
	if Edition.allows(&"presets"):
		var pre := _add_section("Presets", true)
		_palette_label = Label.new()
		_palette_label.clip_text = true
		_palette_label.modulate = Color(1, 1, 1, 0.6)
		pre.add_child(_palette_label)
		var brow := HBoxContainer.new()
		brow.add_child(_make_button("Save…", "Save the props and settings as a .tres preset to reuse on other layers.", _on_save_palette))
		brow.add_child(_make_button("Load…", "Use a saved preset on this layer.", _on_load_palette))
		brow.add_child(_make_button("Start over", "Empties the list and puts every setting back to default (painted props stay). Ctrl+Z undoes.", _on_new_palette))
		pre.add_child(brow)
		_file_dialog = EditorFileDialog.new()
		_file_dialog.add_filter("*.tres", "Vu Scatter preset")
		_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		add_child(_file_dialog)
	else:
		_palette_label = Label.new() # kept for refresh(), not shown
		_palette_label.visible = false
		_root.add_child(_palette_label) # in the tree, so it's freed with the panel


# ---------------------------------------------------------------- tutorial

func _build_tutorial() -> void:
	_progress = EditorInterface.get_editor_settings().get_project_metadata("vu_scatter_2d", "tutorial", {})
	_tut_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 0.55, 1.0, 0.12)
	sb.border_color = Color(0.4, 0.65, 1.0, 0.5)
	sb.set_border_width_all(maxi(1, roundi(_es)))
	sb.set_corner_radius_all(roundi(6 * _es))
	sb.set_content_margin_all(8 * _es)
	_tut_panel.add_theme_stylebox_override(&"panel", sb)
	var box := VBoxContainer.new()
	_tut_panel.add_child(box)
	var head := HBoxContainer.new()
	var hl := Label.new()
	hl.text = "Getting started"
	hl.add_theme_font_size_override(&"font_size", roundi(14 * _es))
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	var hide_btn := _make_button("Hide", "Hide the tutorial. Bring it back with the Tutorial button.", func(): _set_tutorial_hidden(true))
	hide_btn.flat = true
	_tut_restart_btn = _make_button("Restart", "Show the steps again from the start.", _restart_tutorial)
	_tut_restart_btn.flat = true
	head.add_child(_tut_restart_btn)
	head.add_child(hide_btn)
	box.add_child(head)
	var n := 1
	for step in TUTORIAL_STEPS:
		if step[0] == "shape" and not Edition.allows(&"line"):
			continue
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(180, 0) * _es
		l.set_meta(&"text", "%d. %s" % [n, step[1]])
		box.add_child(l)
		_tut_labels[step[0]] = l
		n += 1
	_tut_done_label = Label.new()
	_tut_done_label.text = "That's it! Ctrl+S saves the scene, F6 plays it. Brush and Variety below change size, amount and look. The ? button at the top opens the full guide."
	_tut_done_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tut_done_label.add_theme_color_override(&"font_color", Color(0.5, 0.9, 0.55))
	box.add_child(_tut_done_label)
	_root.add_child(_tut_panel)


## Called by the plugin (and the dock) when the user completes a step.
## True until the user has painted once in this project.
func is_new_user() -> bool:
	return not _progress.has("painted")


func mark_step(key: String) -> void:
	if _progress.get(key, false):
		return
	_progress[key] = true
	EditorInterface.get_editor_settings().set_project_metadata("vu_scatter_2d", "tutorial", _progress)
	_refresh_tutorial()


func _restart_tutorial() -> void:
	_progress = {}
	EditorInterface.get_editor_settings().set_project_metadata("vu_scatter_2d", "tutorial", _progress)
	_refresh_tutorial()


func _set_tutorial_hidden(hidden: bool) -> void:
	_progress["hidden"] = hidden
	EditorInterface.get_editor_settings().set_project_metadata("vu_scatter_2d", "tutorial", _progress)
	_refresh_tutorial()


func _refresh_tutorial() -> void:
	if _tut_panel == null:
		return
	var hidden: bool = _progress.get("hidden", false)
	_tut_panel.visible = not hidden
	_tut_show_btn.visible = hidden
	var current_found := false
	# Steps 1-2 follow what's selected right now; steps 3-4 are remembered once done.
	var live := {
		"layer": is_instance_valid(_layer),
		"props": is_instance_valid(_layer) and _palette != null and not _palette.get_active_items().is_empty(),
	}
	for step in TUTORIAL_STEPS:
		if not _tut_labels.has(step[0]):
			continue
		var l: Label = _tut_labels[step[0]]
		var done: bool = live.get(step[0], _progress.get(step[0], false))
		l.text = ("✓ " if done else "") + String(l.get_meta(&"text"))
		if done:
			l.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.45))
		elif not current_found:
			current_found = true
			l.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.35)) # the step to do now
		else:
			l.remove_theme_color_override(&"font_color")
	_tut_done_label.visible = not current_found
	_tut_restart_btn.visible = not current_found


## The text above "+ Add scatter layer" says what the button will do in the
## current situation (no scene yet, a 3D scene, or a normal 2D scene).
func _refresh_hint() -> void:
	if _hint == null or not _hint.visible:
		return
	var root := EditorInterface.get_edited_scene_root()
	var text := "Props are painted into a scatter layer. Add one, or select one in the Scene dock."
	var can_add := true
	if root == null:
		text = "No scene is open yet. Click below and we'll make a 2D scene for you (saved as %s) with a scatter layer in it." % _new_scene_path().get_file()
	elif root is Node3D:
		text = "This is a 3D scene. Vu Scatter paints in 2D: open a 2D scene, or close this tab and click below to make one."
		can_add = false
	if _hint.text != text:
		_hint.text = text
	_add_layer_btn.disabled = not can_add


## res://level.tscn, or level_2.tscn … if that name is taken.
func _new_scene_path() -> String:
	var path := NEW_SCENE_PATH
	var n := 2
	while ResourceLoader.exists(path) or FileAccess.file_exists(path):
		path = NEW_SCENE_PATH.get_basename() + "_%d.tscn" % n
		n += 1
	return path


## No scene open: saves a new 2D scene with a Node2D root and opens it.
func _create_2d_scene() -> Node:
	var root := Node2D.new()
	root.name = "Level"
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	var path := _new_scene_path()
	if ResourceSaver.save(ps, path) != OK:
		push_warning("Vu Scatter 2D: couldn't save %s. Make a scene with Scene > New Scene > 2D Scene instead." % path)
		return null
	EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.open_scene_from_path(path)
	# Godot 4.4 opens the tab a few frames later; 4.7 right away.
	for i in 60:
		var r := EditorInterface.get_edited_scene_root()
		if r != null and r.scene_file_path == path:
			return r
		await get_tree().process_frame
	push_warning("Vu Scatter 2D: made %s but couldn't open it. Double-click it in the FileSystem dock, then click + Add scatter layer again." % path)
	return null


## Adds a ScatterLayer2D under the selected node (or the scene root), with undo, and selects it.
## With no scene open, makes a 2D scene first. Always shows the 2D view.
func _add_layer() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		if _creating_scene:
			return # one click, one scene
		_creating_scene = true
		_add_layer_btn.disabled = true
		root = await _create_2d_scene()
		_add_layer_btn.disabled = false
		_creating_scene = false
		if root == null:
			return
	if root is Node3D:
		push_warning("Vu Scatter 2D: this is a 3D scene. Open a 2D scene to paint.")
		return
	EditorInterface.set_main_screen_editor("2D")
	var parent: Node = root
	var behind: Node = null # with a layer selected, the new one goes right behind it
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.size() == 1 and (sel[0] == root or root.is_ancestor_of(sel[0])):
		if sel[0] is ScatterLayer2D and sel[0] != root:
			behind = sel[0]
			parent = behind.get_parent()
		else:
			parent = sel[0]
	var layer := ScatterLayer2D.new()
	layer.name = "ScatterLayer2D"
	layer.palette = ScatterPalette.new()
	layer.y_sort_enabled = true
	undo_redo.create_action("Add ScatterLayer2D", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_method(parent, &"add_child", layer, true)
	if behind != null:
		undo_redo.add_do_method(parent, &"move_child", layer, behind.get_index())
	undo_redo.add_do_method(layer, &"set_owner", root)
	undo_redo.add_do_reference(layer)
	undo_redo.add_undo_method(parent, &"remove_child", layer)
	undo_redo.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(layer)
	EditorInterface.edit_node(layer)


## The guide ships next to the plugin in the store zips; the repository keeps it in docs/.
func _guide_path() -> String:
	for p in ["res://addons/vu_scatter_2d/USER_GUIDE.html", "res://docs/USER_GUIDE.html"]:
		if FileAccess.file_exists(p):
			return p
	return ""


func _open_guide() -> void:
	var p := _guide_path()
	if p.is_empty():
		push_warning("Vu Scatter 2D: USER_GUIDE.html is missing. Download the plugin again to get the guide.")
		return
	OS.shell_open(ProjectSettings.globalize_path(p))


func _make_button(text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


## Collapsible section; returns the box to fill.
func _add_section(title: String, collapsed := false) -> VBoxContainer:
	var header := Button.new()
	header.text = "▾ " + title
	header.tooltip_text = "Click to show or hide these settings."
	header.flat = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.toggle_mode = true
	var box := VBoxContainer.new()
	header.toggled.connect(func(collapsed: bool):
		box.visible = not collapsed
		header.text = ("▸ " if collapsed else "▾ ") + title)
	_content.add_child(HSeparator.new())
	_content.add_child(header)
	_content.add_child(box)
	_sections[title] = header
	if collapsed:
		header.button_pressed = true # toggled handler hides the box
	return box


func _add_number(parent: Control, label: String, prop: String, mn: float, mx: float, step: float, tip := "") -> void:
	var s := EditorSpinSlider.new()
	s.tooltip_text = tip
	s.label = label
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.allow_greater = true
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v: float):
		if _refreshing or _palette == null:
			return
		_set_field(prop, v)
		_mark_dirty())
	parent.add_child(s)
	_fields[prop] = s


func _add_check(parent: Control, label: String, prop: String, tip := "") -> void:
	var c := CheckBox.new()
	c.tooltip_text = tip
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.text = label
	c.toggled.connect(func(v: bool):
		if _refreshing or _palette == null:
			return
		_set_field(prop, v)
		_mark_dirty())
	parent.add_child(c)
	_fields[prop] = c


func _add_option(parent: Control, label: String, prop: String, options: Array, tip := "") -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(l)
	var o := OptionButton.new()
	o.tooltip_text = tip
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in options.size():
		o.add_item(options[i], i)
	o.item_selected.connect(func(i: int):
		if _refreshing or _palette == null:
			return
		if prop == "mirror_mode" and _palette.mirror_mode == 0 and i != 0 and _palette.mirror_center == Vector2.ZERO and plugin != null:
			_palette.mirror_center = plugin.view_center_local() # first time: line where you're looking
		_set_field(prop, i)
		_mark_dirty()
		refresh()
		if plugin != null:
			plugin.update_overlays())
	row.add_child(o)
	parent.add_child(row)
	_fields[prop] = o


## Opens a folded section (e.g. "Shape options" when the Shape tool is picked).
func open_section(title: String) -> void:
	var h: Button = _sections.get(title)
	if h != null and h.button_pressed:
		h.button_pressed = false


func _refresh_tile_status() -> void:
	if _tile_status == null or _palette == null or plugin == null:
		return
	_tile_icon.texture = plugin.tile_texture(_palette)
	_tile_icon.visible = _tile_icon.texture != null
	if not plugin.has_tilemap():
		_tile_status.text = "No TileMapLayer found in this scene, so this setting does nothing yet."
	else:
		_tile_status.text = "Lands on: " + plugin.tile_label(_palette)


func _on_pick_tile() -> void:
	if plugin == null or _palette == null:
		return
	if not plugin.has_tilemap():
		_tile_status.text = "Add a TileMapLayer with tiles to this scene first."
		return
	_tile_status.text = "Now click a tile in the 2D view… (Esc cancels)"
	plugin.start_tile_pick()


## Called by the plugin after a tile pick ("" = cancelled or no tile there).
func tile_pick_done(label: String) -> void:
	if label.is_empty():
		_refresh_tile_status()
		_tile_status.text += "\n(No tile picked.)"
	else:
		refresh()


func _on_any_tile() -> void:
	if _palette == null:
		return
	_palette.only_tile_source = -1
	_palette.only_tile_coords = Vector2i(-1, -1)
	_mark_dirty()
	refresh()


func _on_center_mirror() -> void:
	if _palette == null or plugin == null:
		return
	var c: Vector2 = plugin.view_center_local()
	undo_redo.create_action("Move mirror line", UndoRedo.MERGE_DISABLE, _palette)
	undo_redo.add_do_property(_palette, &"mirror_center", c.round())
	undo_redo.add_undo_property(_palette, &"mirror_center", _palette.mirror_center)
	undo_redo.add_do_method(self, &"refresh")
	undo_redo.add_undo_method(self, &"refresh")
	undo_redo.commit_action()
	plugin.update_overlays()


func _on_clear_layer() -> void:
	if _layer == null:
		return
	var props := _layer.get_painted_props()
	if props.is_empty():
		_tools_status.text = "Nothing to clear: this layer has no painted props."
		return
	var root := _layer.owner if _layer.owner != null else _layer
	undo_redo.create_action("Clear scatter layer", UndoRedo.MERGE_DISABLE, root)
	for n in props:
		undo_redo.add_do_method(_layer, &"remove_child", n)
		undo_redo.add_undo_method(_layer, &"add_child", n)
		undo_redo.add_undo_method(n, &"set_owner", root)
		undo_redo.add_undo_reference(n)
	undo_redo.commit_action()
	_tools_status.text = "Removed %d props. Ctrl+Z brings them back." % props.size()


func _on_lock_props() -> void:
	if plugin == null:
		return
	var n: int = plugin.lock_painted_props()
	_tools_status.text = ("Locked %d props: Erase and Clear layer leave them alone now." % n) if n > 0 else "Nothing to lock: this layer has no painted props."


func _add_color(parent: Control, label: String, prop: String) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var c := ColorPickerButton.new()
	c.custom_minimum_size = Vector2(64, 0) * _es
	c.tooltip_text = "Color mixed into every prop. White = the art's own colors."
	l.tooltip_text = c.tooltip_text
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	c.color_changed.connect(func(v: Color):
		if _refreshing or _palette == null:
			return
		_set_field(prop, v)
		_mark_dirty())
	row.add_child(c)
	parent.add_child(row)
	_fields[prop] = c


# ---------------------------------------------------------------- items

func _rebuild_items() -> void:
	for c in _items_box.get_children():
		_items_box.remove_child(c)
		c.queue_free()
	if _palette == null:
		return
	var limit := Edition.max_items()
	for i in _palette.items.size():
		var item := _palette.items[i]
		if item == null:
			continue
		_items_box.add_child(_make_item_row(item, i, limit >= 0 and i >= limit))


func _make_item_row(item: ScatterItem, index: int, locked: bool) -> Control:
	var row := HBoxContainer.new()
	row.set_drag_forwarding(Callable(), _can_drop, _drop)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(32, 32) * _es
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if item.texture != null:
		thumb.texture = item.texture
	elif item.scene != null and item.scene.resource_path != "":
		# Show the scene's first texture right away; the editor preview replaces it when ready.
		thumb.texture = item.get_thumbnail()
		EditorInterface.get_resource_previewer().queue_resource_preview(
			item.scene.resource_path, self, &"_on_preview", thumb)
	row.add_child(thumb)

	var on := CheckBox.new()
	on.button_pressed = item.enabled
	on.tooltip_text = "Ticked = this prop gets painted. Untick to skip it without removing it."
	on.toggled.connect(func(v: bool):
		item.enabled = v
		_mark_dirty())
	row.add_child(on)

	var name_btn := Button.new()
	name_btn.text = item.get_display_name()
	name_btn.flat = true
	name_btn.clip_text = true
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.tooltip_text = "Click to open this prop in the Inspector. There, open Per-prop overrides and turn on Override Settings to give it its own size, tilt, color…\nSelect the scatter layer in the Scene dock to come back here."
	name_btn.pressed.connect(func():
		EditorInterface.edit_resource(item)
		_show_inspector())
	row.add_child(name_btn)

	if locked:
		on.disabled = true
		name_btn.tooltip_text = "Lite paints the first %d props only." % Edition.max_items()
		name_btn.modulate.a = 0.5
	elif Edition.allows(&"weights"):
		var w := EditorSpinSlider.new()
		w.min_value = 0
		w.max_value = 100
		w.step = 0.1
		w.value = item.weight
		w.hide_slider = true
		w.tooltip_text = "How often this prop appears compared with the others. 2 = twice as often as a prop set to 1."
		w.custom_minimum_size = Vector2(56, 0) * _es
		w.value_changed.connect(func(v: float):
			item.weight = v
			_mark_dirty())
		row.add_child(w)

	var rm := Button.new()
	rm.icon = get_theme_icon(&"Remove", &"EditorIcons")
	rm.flat = true
	rm.tooltip_text = "Remove this prop from the list (Ctrl+Z brings it back)."
	rm.pressed.connect(_remove_item.bind(index))
	row.add_child(rm)
	return row


## The Inspector often shares a tab group with this panel; bring it to the
## front so clicking a prop's name visibly opens it.
func _show_inspector() -> void:
	var child: Node = EditorInterface.get_inspector()
	var p := child.get_parent() if child != null else null
	while p != null:
		if p.is_class("EditorDock") and p.has_method(&"make_visible"):
			p.call(&"make_visible")
			return
		if p is TabContainer:
			var idx: int = p.get_tab_idx_from_control(child)
			if idx >= 0:
				p.current_tab = idx
			return
		child = p
		p = p.get_parent()


func _on_preview(_path: String, preview: Texture2D, _thumb: Texture2D, rect: Variant) -> void:
	if is_instance_valid(rect) and preview != null:
		rect.texture = preview


func _set_items(new_items: Array[ScatterItem], action: String, also := {}) -> void:
	var old_items: Array[ScatterItem] = _palette.items.duplicate()
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, EditorInterface.get_edited_scene_root())
	for prop: String in also:
		undo_redo.add_do_property(_palette, prop, also[prop])
		undo_redo.add_undo_property(_palette, prop, _palette.get(prop))
	undo_redo.add_do_property(_palette, &"items", new_items)
	undo_redo.add_do_method(_palette, &"emit_changed")
	undo_redo.add_undo_property(_palette, &"items", old_items)
	undo_redo.add_undo_method(_palette, &"emit_changed")
	undo_redo.commit_action()


func _remove_item(index: int) -> void:
	if _palette == null or index >= _palette.items.size():
		return
	var items: Array[ScatterItem] = _palette.items.duplicate()
	items.remove_at(index)
	_set_items(items, "Remove scatter prop")


# ---------------------------------------------------------------- drag and drop

func _accepted_paths(data: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if not (data is Dictionary and data.get("type") in ["files", "files_and_dirs"]):
		return out
	for path: String in data.get("files", []):
		if path.ends_with("/"):
			_collect_dir(path, out)
		elif _is_prop_file(path):
			out.append(path)
	return out


## A dropped folder adds every image and scene inside it (and its subfolders).
func _collect_dir(dir: String, out: PackedStringArray) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	for f in da.get_files():
		var path := dir.path_join(f)
		if not f.ends_with(".import") and not f.ends_with(".uid") and _is_prop_file(path):
			out.append(path)
	for sub in da.get_directories():
		if not sub.begins_with("."):
			_collect_dir(dir.path_join(sub) + "/", out)


func _is_prop_file(path: String) -> bool:
	var t := EditorInterface.get_resource_filesystem().get_file_type(path)
	if t.is_empty() and ResourceLoader.exists(path):
		# File cache not updated yet (e.g. right after an import): ask the loader.
		var res := load(path)
		t = res.get_class() if res != null else ""
	return t == "PackedScene" or ClassDB.is_parent_class(t, "Texture2D")


func _can_drop(_pos: Vector2, data: Variant) -> bool:
	if _palette == null or not data is Dictionary:
		return false
	# Folders are scanned on drop, not on every hover.
	for path: String in data.get("files", []):
		if path.ends_with("/") and data.get("type") == "files_and_dirs":
			return true
	return not _accepted_paths(data).is_empty()


func _drop(_pos: Vector2, data: Variant) -> void:
	_add_paths(_accepted_paths(data), "Add scatter props")


## Adds props from file paths (scenes or images), with undo. Turns Paint on
## when these are the first props, so the user can start right away.
func _add_paths(paths: PackedStringArray, action: String) -> void:
	if _palette == null:
		return
	var items: Array[ScatterItem] = _palette.items.duplicate()
	var was_empty := items.is_empty()
	var limit := Edition.max_items()
	var skipped := 0
	for path in paths:
		if limit >= 0 and items.size() >= limit:
			skipped += 1
			continue
		var res := load(path)
		var item := ScatterItem.new()
		if res is PackedScene:
			item.scene = res
		elif res is Texture2D:
			item.texture = res
		else:
			continue
		items.append(item)
	_notice.visible = skipped > 0 or paths.is_empty()
	if paths.is_empty():
		_notice.text = "Nothing to add there: drop images or .tscn scenes (or a folder of them)."
	elif skipped > 0:
		_notice.text = "Lite holds up to %d props, so %d %s not added. Pro has no limit." % [limit, skipped, "was" if skipped == 1 else "were"]
	if items.size() != _palette.items.size():
		var fit := _fit_to_props(items) if was_empty else {}
		_set_items(items, action, fit)
		if was_empty:
			start_painting.emit()


## Big art with the default Gap paints an overlapping blob, so when the first
## props come in, Gap and Brush size grow to fit them (never shrink), and images
## stand on their bottom edge (Pro). Undoable.
func _fit_to_props(items: Array[ScatterItem]) -> Dictionary:
	var total := 0.0
	var n := 0
	var images := false
	for item in items:
		images = images or item.texture != null
		var t := item.get_thumbnail()
		if t != null:
			total += maxf(t.get_width(), t.get_height())
			n += 1
	var out := {}
	# Images stand where you click (their base), so tall trees and small bushes
	# line up in a row and Y-sort draws the nearer one in front.
	if images and not _palette.anchor_at_feet and Edition.allows(&"feet_anchor"):
		out["anchor_at_feet"] = true
	if n == 0:
		return out
	var size := total / n * (_palette.scale_min + _palette.scale_max) * 0.5
	var gap := roundf(size * 0.6)
	if gap > _palette.min_spacing:
		out["min_spacing"] = gap
	var radius := roundf(gap * 1.5)
	if radius > _palette.radius:
		out["radius"] = radius
	return out


func _example_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for path: String in EXAMPLE_PROPS:
		if ResourceLoader.exists(path):
			out.append(path)
	return out


func _use_example_props() -> void:
	var paths := _example_paths()
	if Edition.max_items() >= 0 and paths.size() > Edition.max_items():
		paths = paths.slice(0, Edition.max_items()) # Lite: no "limit" warning for the examples
	_add_paths(paths, "Use example scatter props")


# ---------------------------------------------------------------- presets (Pro)

func _assign_palette(p: ScatterPalette, action: String) -> void:
	if _layer == null:
		return
	undo_redo.create_action(action, UndoRedo.MERGE_DISABLE, _layer)
	undo_redo.add_do_property(_layer, &"palette", p)
	undo_redo.add_undo_property(_layer, &"palette", _layer.palette)
	undo_redo.commit_action()
	_bind_palette(p)
	settings_changed.emit()


func _on_new_palette() -> void:
	_assign_palette(ScatterPalette.new(), "New scatter palette")


func _on_load_palette() -> void:
	_open_dialog(EditorFileDialog.FILE_MODE_OPEN_FILE, func(path: String):
		var res := load(path)
		if res is ScatterPalette:
			_assign_palette(res, "Load scatter palette")
		else:
			push_warning("Vu Scatter 2D: %s is not a ScatterPalette." % path))


func _on_save_palette() -> void:
	if _palette == null:
		return
	_open_dialog(EditorFileDialog.FILE_MODE_SAVE_FILE, func(path: String):
		var err := ResourceSaver.save(_palette, path)
		if err != OK:
			push_error("Vu Scatter 2D: could not save the preset (%s)." % error_string(err))
			return
		_palette.take_over_path(path)
		EditorInterface.get_resource_filesystem().update_file(path)
		_mark_dirty()
		refresh())


func _open_dialog(mode: EditorFileDialog.FileMode, cb: Callable) -> void:
	for c in _file_dialog.file_selected.get_connections():
		_file_dialog.file_selected.disconnect(c.callable)
	_file_dialog.file_mode = mode
	_file_dialog.file_selected.connect(cb, CONNECT_ONE_SHOT)
	_file_dialog.popup_file_dialog()
