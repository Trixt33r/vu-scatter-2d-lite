@tool
extends RefCounted
## Lite/Pro feature gate. The build script flips EDITION to make the Lite zip.
## Every Pro-only behaviour asks `allows()`, so Lite data opens unchanged in Pro.

const EDITION := "lite" # "lite" or "pro"
const LITE_MAX_ITEMS := 3

const PRO_FEATURES: Array[StringName] = [
	&"weights", # weighted palette picks (Lite picks evenly)
	&"flip",
	&"tint",
	&"z_index",
	&"feet_anchor",
	&"presets", # save/load palettes as .tres from the dock
	&"reroll",
	&"grid_snap",
	&"line", # Shape tool
	&"mirror", # Mirror painting
	&"tile_mask", # Only on my TileMap
]


static func is_pro() -> bool:
	return EDITION == "pro"


static func allows(feature: StringName) -> bool:
	return is_pro() or not PRO_FEATURES.has(feature)


## Max palette items that get painted. -1 means unlimited.
static func max_items() -> int:
	return -1 if is_pro() else LITE_MAX_ITEMS


static func display_name() -> String:
	return "Vu Scatter 2D Pro" if is_pro() else "Vu Scatter 2D Lite"
