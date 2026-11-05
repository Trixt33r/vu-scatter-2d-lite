@tool
extends HBoxContainer
## Paint / Erase / Place one buttons in the 2D editor's top menu bar.

signal mode_changed(mode: int)
## B / E / U / L / P pressed anywhere in the editor while this toolbar shows
## (i.e. a scatter layer is selected), not only with the 2D view focused.
signal tool_key(event: InputEventKey)
signal hint_changed

const Edition := preload("res://addons/vu_scatter_2d/edition.gd")

enum Mode { NONE, PAINT, ERASE, SINGLE, REROLL, LINE }
enum Shape { LINE, RECT, CIRCLE, SPIRAL, GRID, FILL }
const SHAPE_NAMES := ["Line", "Rectangle", "Circle", "Spiral", "Grid (rows)", "Fill area"]
const SHAPE_HINTS := [
	"Drag from start to end · Shift = any angle",
	"Drag corner to corner · Shift = square",
	"Drag from the centre outward",
	"Drag from the centre outward",
	"Drag corner to corner to fill in rows · Shift = square",
	"Draw around an area to fill it with props",
]

## The shape the Shape tool places.
var shape: int = Shape.LINE
var _shape_pick: OptionButton

var _group := ButtonGroup.new()
var _buttons := {} # Mode -> Button
var _radius_label: Label
var _props_strip: HBoxContainer
var _hint_label: Label
var _syncing := false
var _mode: int = Mode.NONE
var _has_props := false

const HINTS := {
	Mode.NONE: "Click Paint (or press B) to start",
	Mode.PAINT: "Drag to paint · Shift+drag erases · [ ] brush size · Esc stops",
	Mode.ERASE: "Drag to erase painted props · Esc stops",
	Mode.SINGLE: "Click to place one prop · Esc stops",
	Mode.REROLL: "Drag over props to shuffle their look · Esc stops",
	Mode.LINE: "",
}


func _init() -> void:
	_group.allow_unpress = true
	add_child(VSeparator.new())
	_add_button(Mode.PAINT, "Paint", "Paint props with the brush (left drag). Shortcut: B\nShift + drag erases. [ and ] resize. Esc stops.")
	_add_button(Mode.ERASE, "Erase", "Erase painted props under the brush (left drag). Only removes props the brush made.\nShortcut: E (while a Vu Scatter tool is on). Esc stops.")
	_add_button(Mode.SINGLE, "Place one", "Place exactly one prop where you click, e.g. a sign or a torch.\nShortcut: P. Esc stops.")
	if Edition.allows(&"line"):
		_add_button(Mode.LINE, "Shape", "Place props along a shape, end to end: a line of fence, a fenced yard, a ring of stones, a spiral or an orchard in rows.\nPick the shape next to this button, then drag.\nShortcuts: U = Shape, Shift+U = next shape, L = Fill area.")
		_shape_pick = OptionButton.new()
		const TIPS := [
			"A straight row: fences, walls, torches. Snaps to straight lines; hold Shift for any angle.",
			"Props around the edge of a rectangle: a fenced yard or garden border.",
			"Props around a circle: a stone circle or a ring of trees.",
			"Props along a spiral, from the centre outward.",
			"A rectangle filled in neat rows: an orchard, crops, a graveyard.",
			"Draw freely around an area; it fills with props like the Paint brush. Shortcut: L",
		]
		for i in SHAPE_NAMES.size():
			_shape_pick.add_item(SHAPE_NAMES[i], i)
			_shape_pick.set_item_tooltip(i, TIPS[i])
		_shape_pick.tooltip_text = "Which shape the Shape tool makes. Shift+U picks the next one.\nMore options: \"Shape options\" in the Vu Scatter panel."
		_shape_pick.focus_mode = Control.FOCUS_NONE
		_shape_pick.item_selected.connect(func(i: int):
			shape = i
			if _mode != Mode.LINE:
				mode_changed.emit(Mode.LINE) # picking a shape turns the tool on
			_update_hint())
		add_child(_shape_pick)
	if Edition.allows(&"reroll"):
		_add_button(Mode.REROLL, "Shuffle", "Drag over painted props to give them a new random size, tilt, mirror and color. They stay where they are.\nShortcut: Shift+B. Esc stops.")
	_radius_label = Label.new()
	_radius_label.tooltip_text = "Brush size. Change it with the [ and ] keys."
	_radius_label.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_radius_label)
	add_child(VSeparator.new())
	var painting := Label.new()
	painting.text = "Painting:"
	painting.tooltip_text = "The props this layer paints: the ticked ones in the Vu Scatter panel. Hover a picture for its name."
	painting.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(painting)
	_props_strip = HBoxContainer.new()
	_props_strip.add_theme_constant_override(&"separation", 2)
	add_child(_props_strip)
	add_child(VSeparator.new())
	_hint_label = Label.new()
	_hint_label.modulate = Color(1, 1, 1, 0.65)
	# The hint may be cut short on narrow screens instead of widening the editor.
	_hint_label.clip_text = true
	_hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.custom_minimum_size = Vector2(80, 0)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_hint_label.visible = false # shown in full at the bottom of the 2D view instead (plugin.gd)
	add_child(_hint_label)
	_update_hint()


func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_B, KEY_E, KEY_U, KEY_L, KEY_P]:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return # typing a name or a script: not a shortcut
		tool_key.emit(event)


func _add_button(mode: Mode, text: String, tip: String) -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.toggle_mode = true
	b.button_group = _group
	b.theme_type_variation = &"FlatButton"
	b.focus_mode = Control.FOCUS_NONE
	# Make the active mode obvious: accent background + text when pressed.
	var accent := EditorInterface.get_editor_settings().get_setting("interface/theme/accent_color") as Color
	var on := StyleBoxFlat.new()
	on.bg_color = Color(accent, 0.35)
	on.border_color = accent
	on.set_border_width_all(1)
	on.set_corner_radius_all(3)
	on.set_content_margin_all(4)
	b.add_theme_stylebox_override(&"pressed", on)
	b.add_theme_stylebox_override(&"hover_pressed", on)
	b.add_theme_color_override(&"font_pressed_color", Color.WHITE)
	b.add_theme_color_override(&"font_hover_pressed_color", Color.WHITE)
	b.toggled.connect(_on_toggled.bind(mode))
	_buttons[mode] = b
	add_child(b)


func _on_toggled(pressed: bool, mode: Mode) -> void:
	if _syncing:
		return
	if pressed:
		mode_changed.emit(mode)
	elif _group.get_pressed_button() == null:
		mode_changed.emit(Mode.NONE)


## Updates the buttons without emitting mode_changed.
func set_mode(mode: int) -> void:
	_syncing = true
	for m in _buttons:
		_buttons[m].button_pressed = (m == mode)
	_syncing = false
	_mode = mode
	_update_hint()


## Shows a thumbnail per prop the brush will paint, so it's clear what you're painting.
func set_props(items: Array) -> void:
	for c in _props_strip.get_children():
		_props_strip.remove_child(c)
		c.queue_free()
	_has_props = not items.is_empty()
	var es := EditorInterface.get_editor_scale()
	var shown := 0
	for item in items:
		if shown == 8:
			var more := Label.new()
			more.text = "+%d" % (items.size() - 8)
			more.tooltip_text = "%d more props are ticked. See the full list in the Vu Scatter panel." % (items.size() - 8)
			more.mouse_filter = Control.MOUSE_FILTER_PASS
			_props_strip.add_child(more)
			break
		var t := TextureRect.new()
		t.texture = item.get_thumbnail()
		t.custom_minimum_size = Vector2(22, 22) * es
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.tooltip_text = item.get_display_name()
		_props_strip.add_child(t)
		shown += 1
	if items.is_empty():
		var none := Label.new()
		none.text = "none yet"
		none.add_theme_color_override(&"font_color", Color(1.0, 0.55, 0.45))
		none.tooltip_text = "Click \"Use example props\" in the Vu Scatter panel, or drag images or .tscn scenes into it."
		none.mouse_filter = Control.MOUSE_FILTER_PASS
		_props_strip.add_child(none)
	_update_hint()


func _update_hint() -> void:
	if _hint_label == null:
		return
	if not _has_props and (_mode == Mode.PAINT or _mode == Mode.SINGLE or _mode == Mode.LINE or _mode == Mode.NONE):
		_hint_label.text = "First pick what to paint in the Vu Scatter panel (right)"
	elif _mode == Mode.LINE:
		_hint_label.text = SHAPE_HINTS[shape] + " · Esc stops"
	else:
		_hint_label.text = HINTS.get(_mode, "")
	_hint_label.tooltip_text = _hint_label.text
	hint_changed.emit()


## The current "what to do next" text, also drawn at the bottom of the 2D view.
func hint_text() -> String:
	return _hint_label.text if _hint_label != null else ""


## Picks a shape without emitting signals (keyboard shortcuts).
func set_shape(i: int) -> void:
	shape = i
	if _shape_pick != null:
		_shape_pick.select(i)
	_update_hint()


func set_radius(r: float) -> void:
	_radius_label.text = " Size %d" % roundi(r)
