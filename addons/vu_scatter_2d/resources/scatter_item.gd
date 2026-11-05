@tool
class_name ScatterItem
extends Resource
## One prop in a palette: a scene or a texture, plus optional per-prop settings.

## The scene to paint (its root must be a Node2D). Leave empty when using an image.
@export var scene: PackedScene:
	set(v):
		scene = v
		emit_changed()
## The image to paint. Leave empty when using a scene.
@export var texture: Texture2D:
	set(v):
		texture = v
		emit_changed()
## Ticked = this prop gets painted. Untick to skip it without removing it.
@export var enabled := true:
	set(v):
		enabled = v
		emit_changed()
## How often this prop appears compared with the others. 2 = twice as often as a prop set to 1 (Pro).
@export_range(0.0, 100.0, 0.1) var weight := 1.0:
	set(v):
		weight = v
		emit_changed()

@export_group("Per-prop overrides")
## Turn on to give this prop its own size, tilt, mirror, color and draw order. The settings below then replace the panel's settings for this prop only.
@export var override_settings := false
## Smallest random size for this prop. 1 = original size.
@export_range(0.05, 10.0, 0.01, "or_greater") var scale_min := 0.8
## Biggest random size for this prop. 1 = original size.
@export_range(0.05, 10.0, 0.01, "or_greater") var scale_max := 1.2
## Random tilt either way, in degrees. 0 = always upright.
@export_range(0.0, 180.0, 0.5) var rotation_range_deg := 0.0
## Chance (0 to 1) to mirror this prop left/right (Pro).
@export_range(0.0, 1.0, 0.01) var flip_h_chance := 0.0
## Chance (0 to 1) to mirror this prop upside down (Pro).
@export_range(0.0, 1.0, 0.01) var flip_v_chance := 0.0
## Color mixed into this prop. White = the art's own colors (Pro).
@export var tint := Color.WHITE
## Varies brightness and hue a little per copy. 0.2 to 0.3 looks natural (Pro).
@export_range(0.0, 1.0, 0.01) var tint_jitter := 0.0
## Draw order of this prop. Higher draws on top (Pro).
@export_range(-4096, 4096) var z_index := 0
## Images only: the prop stands on its bottom edge, so Y-sort uses its base (Pro).
@export var anchor_at_feet := false


func is_valid() -> bool:
	return scene != null or texture != null


func get_source() -> Resource:
	return scene if scene != null else texture


## A texture to show for this prop: the texture itself, or the first texture
## used inside the scene (read from the packed data, no instancing).
func get_thumbnail() -> Texture2D:
	if texture != null:
		return texture
	if scene == null:
		return null
	var st := scene.get_state()
	for i in st.get_node_count():
		for j in st.get_node_property_count(i):
			var v = st.get_node_property_value(i, j)
			if v is Texture2D:
				return v
	return null


func get_display_name() -> String:
	var res := get_source()
	if res == null:
		return "(empty)"
	if res.resource_path != "":
		return res.resource_path.get_file().get_basename()
	return res.resource_name if res.resource_name != "" else res.get_class()
