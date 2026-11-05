@tool
extends RefCounted
## Builds a prop node from a ScatterItem and applies randomness.

const Edition := preload("res://addons/vu_scatter_2d/edition.gd")
const PAINTED_META := &"vu_scatter"


## The object holding the randomness/placement values for this item:
## the item itself when it overrides, else the palette (same field names).
static func settings_for(item: ScatterItem, palette: ScatterPalette) -> Resource:
	return item if item != null and item.override_settings else palette


## Returns a new Node2D (not yet in the tree), or null if the item can't make one.
static func build(item: ScatterItem, palette: ScatterPalette, rng: RandomNumberGenerator, position: Vector2) -> Node2D:
	var node: Node2D = null
	var s = settings_for(item, palette)

	if item.scene != null:
		var inst := item.scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		if not inst is Node2D:
			push_warning("Vu Scatter 2D: '%s' root is not a Node2D, skipped." % item.scene.resource_path)
			if inst != null:
				inst.free()
			return null
		node = inst
		node.scene_file_path = item.scene.resource_path
	elif item.texture != null:
		var sprite := Sprite2D.new()
		sprite.texture = item.texture
		if s.anchor_at_feet and Edition.allows(&"feet_anchor"):
			var size := item.texture.get_size()
			sprite.centered = false
			sprite.offset = Vector2(-size.x * 0.5, -size.y)
		node = sprite
	else:
		return null

	node.position = position
	randomize_props(node, s, rng)
	if Edition.allows(&"z_index") and s.z_index != 0:
		node.z_index = s.z_index

	var src := item.get_source()
	node.set_meta(PAINTED_META, src.resource_path if src != null else "")
	return node


## Computes scale, rotation and modulate for a prop. Used by paint and Re-roll.
static func roll(s, rng: RandomNumberGenerator) -> Dictionary:
	var lo := minf(s.scale_min, s.scale_max)
	var hi := maxf(s.scale_min, s.scale_max)
	var sc := rng.randf_range(lo, hi)
	var scale := Vector2(sc, sc)
	if Edition.allows(&"flip"):
		if rng.randf() < s.flip_h_chance:
			scale.x = -scale.x
		if rng.randf() < s.flip_v_chance:
			scale.y = -scale.y
	var rot := 0.0
	if s.rotation_range_deg > 0.0:
		rot = deg_to_rad(rng.randf_range(-s.rotation_range_deg, s.rotation_range_deg))
	var mod := Color.WHITE
	if Edition.allows(&"tint"):
		mod = jitter_color(s.tint, s.tint_jitter, rng)
	return {"scale": scale, "rotation": rot, "modulate": mod}


static func randomize_props(node: Node2D, s, rng: RandomNumberGenerator) -> void:
	var r := roll(s, rng)
	node.scale = r.scale
	node.rotation = r.rotation
	node.modulate = r.modulate


static func jitter_color(base: Color, jitter: float, rng: RandomNumberGenerator) -> Color:
	if jitter <= 0.0:
		return base
	var c := base
	var v := clampf(c.v * (1.0 + rng.randf_range(-0.25, 0.25) * jitter), 0.0, 1.0)
	var h := fposmod(c.h + rng.randf_range(-0.08, 0.08) * jitter, 1.0)
	c = Color.from_hsv(h, c.s, v, c.a)
	return c
