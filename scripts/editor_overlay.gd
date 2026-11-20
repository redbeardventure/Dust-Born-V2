extends Node2D
## Thin node that lets the map editor draw handles, grid and previews above the (lit) map.

var editor: Node


func _draw() -> void:
	if editor != null:
		editor.draw_overlay(self)
