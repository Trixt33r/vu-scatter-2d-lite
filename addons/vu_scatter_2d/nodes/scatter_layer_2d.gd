@tool
@icon("res://addons/vu_scatter_2d/icons/scatter_layer_2d.svg")
class_name ScatterLayer2D
extends Node2D
## Container for painted props. Select it in the Scene dock to paint.
## Painted props are its direct children and are plain nodes, so nothing
## from this plugin runs while the game is playing.

## Meta key set on every prop the brush places. Erase only touches these.
const PAINTED_META := &"vu_scatter"

## Emitted when a different palette is assigned (the dock follows it).
signal palette_changed

## The props and settings this layer paints with. Edit them in the Vu Scatter panel.
@export var palette: ScatterPalette:
	set(v):
		if palette == v:
			return
		palette = v
		palette_changed.emit()


static func is_painted(node: Node) -> bool:
	return node is Node2D and node.has_meta(PAINTED_META)


func get_painted_props() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for child in get_children():
		if is_painted(child):
			out.append(child)
	return out
