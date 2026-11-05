@tool
class_name ScatterPalette
extends Resource
## A set of props plus brush settings. Save it as a .tres to reuse it as a preset.

const Edition := preload("res://addons/vu_scatter_2d/edition.gd")

## The props to paint. Easiest to edit in the Vu Scatter panel.
@export var items: Array[ScatterItem] = []

@export_group("Brush")
## Brush radius in pixels. Shortcut in the 2D view: [ and ].
@export_range(4.0, 4096.0, 1.0, "or_greater") var radius := 96.0
## How many props per 100 x 100 pixels. 1 = sparse, 5 = lush.
@export_range(0.01, 100.0, 0.01, "or_greater") var density := 3.0
## No two painted props get closer than this (pixels). 0 lets them overlap.
@export_range(0.0, 1024.0, 1.0, "or_greater") var min_spacing := 24.0
## 1 removes everything under the brush. Lower values thin props out.
@export_range(0.05, 1.0, 0.01) var erase_strength := 1.0
## Erase only removes props that are ticked in this list (e.g. untick the trees to erase just the grass).
@export var erase_only_palette := false
## 0 = new randomness every stroke. Any other number repeats the same result.
@export var random_seed := 0

@export_group("Randomness")
## Each prop gets a random size between Smallest and Biggest. 1 = original size.
@export_range(0.05, 10.0, 0.01, "or_greater") var scale_min := 0.8
## Each prop gets a random size between Smallest and Biggest. 1 = original size.
@export_range(0.05, 10.0, 0.01, "or_greater") var scale_max := 1.2
## Random tilt either way, in degrees. Keep 0 for trees, use it for rocks and debris.
@export_range(0.0, 180.0, 0.5) var rotation_range_deg := 0.0
## Chance (0 to 1) to mirror a prop left/right. 0.5 = half of them (Pro).
@export_range(0.0, 1.0, 0.01) var flip_h_chance := 0.0
## Chance (0 to 1) to mirror a prop upside down (Pro).
@export_range(0.0, 1.0, 0.01) var flip_v_chance := 0.0
## Color mixed into every prop. White = the art's own colors (Pro).
@export var tint := Color.WHITE
## Varies brightness (up to ±25%) and hue a little per prop. 0.2 to 0.3 looks natural (Pro).
@export_range(0.0, 1.0, 0.01) var tint_jitter := 0.0

@export_group("Placement")
## Draw order of painted props. Higher draws on top (Pro).
@export_range(-4096, 4096) var z_index := 0
## Images stand on their bottom edge, so Y-sort uses their base (Pro).
@export var anchor_at_feet := false
## One prop per grid cell, centred (Pro).
@export var grid_snap := false
## Grid cell size in pixels, when not using the TileMap's grid (Pro).
@export var cell_size := Vector2(32, 32)
## Take the grid size from a TileMapLayer next to this layer, else the first one in the scene (Pro).
@export var use_tileset_cell_size := false
## Props only land where your TileMapLayer has a tile (Pro).
@export var only_on_tiles := false
## Set by "Pick tile type…" in the panel. -1 = any tile.
@export var only_tile_source := -1
## Set by "Pick tile type…" in the panel.
@export var only_tile_coords := Vector2i(-1, -1)

@export_group("Shape options")
## Shape tool: 0 = props sit end to end. Any other number spreads exactly that many evenly (Pro).
@export_range(0, 500) var shape_count := 0
## Shape tool: each prop turns to follow the line, circle or spiral (Pro).
## Long props (fences) turn on Line and Rectangle even when this is off.
@export var shape_follow := false
## Shape tool: small random offsets so rows look placed by hand. 0 = perfectly tidy (Pro).
@export_range(0.0, 1.0, 0.01) var shape_wobble := 0.0

@export_group("Mirror")
## Mirror painting: 0 = off, 1 = left/right, 2 = up/down, 3 = both (Pro).
@export_range(0, 3) var mirror_mode := 0
## Where the mirror line(s) cross, in this layer's pixels (Pro).
@export var mirror_center := Vector2.ZERO


## Items the brush may paint: enabled, valid, and within the edition's item limit.
func get_active_items() -> Array[ScatterItem]:
	var out: Array[ScatterItem] = []
	var limit := Edition.max_items()
	for i in items.size():
		if limit >= 0 and i >= limit:
			break
		var item := items[i]
		if item != null and item.enabled and item.is_valid():
			out.append(item)
	return out


## The item whose scene/texture has this resource path, or null.
func find_item_by_source(path: String) -> ScatterItem:
	if path.is_empty():
		return null
	for item in items:
		if item != null and item.get_source() != null and item.get_source().resource_path == path:
			return item
	return null


## Resource paths of the active items (used by the erase filter).
func get_active_source_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for item in get_active_items():
		out.append(item.get_source().resource_path)
	return out


## Picks one active item. Pro uses weights; Lite picks evenly.
func pick_item(rng: RandomNumberGenerator) -> ScatterItem:
	var active := get_active_items()
	if active.is_empty():
		return null
	if not Edition.allows(&"weights"):
		return active[rng.randi_range(0, active.size() - 1)]
	var total := 0.0
	for item in active:
		total += maxf(item.weight, 0.0)
	if total <= 0.0:
		return active[rng.randi_range(0, active.size() - 1)]
	var roll := rng.randf() * total
	for item in active:
		roll -= maxf(item.weight, 0.0)
		if roll <= 0.0:
			return item
	return active[active.size() - 1]
