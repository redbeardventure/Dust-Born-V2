class_name RailNode
extends Node2D
## Draws a railway track along a polyline: gravel bed shadow, wooden sleepers and two steel rails.
## `width` is the gauge width (sleeper length).

var points := PackedVector2Array()
var closed := false
var width := 70.0

const TIE_SPACING := 22.0


func _path() -> PackedVector2Array:
	var p := PackedVector2Array(points)
	if closed and p.size() > 2:
		p.append(p[0])
	return p


## Offsets the polyline sideways using averaged vertex normals.
func _offset(p: PackedVector2Array, dist: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in p.size():
		var n := Vector2.ZERO
		if i > 0:
			n += (p[i] - p[i - 1]).normalized().orthogonal()
		if i < p.size() - 1:
			n += (p[i + 1] - p[i]).normalized().orthogonal()
		n = n.normalized() if n.length() > 0.001 else Vector2.DOWN
		out.append(p[i] + n * dist)
	return out


func _draw() -> void:
	var p := _path()
	if p.size() < 2:
		return
	# soft bed shadow
	draw_polyline(p, MapData.shadow_color(0.22), width * 1.25, true)
	# sleepers
	var carry := 0.0
	for i in p.size() - 1:
		var a := p[i]
		var b := p[i + 1]
		var seg := (b - a)
		var seg_len := seg.length()
		if seg_len < 0.01:
			continue
		var dir := seg / seg_len
		var nrm := dir.orthogonal()
		var t := carry
		while t <= seg_len:
			var c := a + dir * t
			var h := nrm * (width * 0.5)
			draw_line(c - h, c + h, Color("2b1a0b"), 9.0)
			draw_line(c - h * 0.96, c + h * 0.96, Color("73502c"), 6.0)
			t += TIE_SPACING
		carry = t - seg_len
	# rails
	var gauge := width * 0.32
	for side in [-1.0, 1.0]:
		var r := _offset(p, gauge * side)
		draw_polyline(r, Color("1c1f23"), 8.0, true)
		draw_polyline(r, Color("9aa2aa"), 4.0, true)
		draw_polyline(r, Color("d3d9de"), 1.2, true)
