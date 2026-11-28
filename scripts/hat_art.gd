extends RefCounted
## Top-down cowboy hat artwork, shared by the player and the in-game hat picker.
## Hats are drawn in a local frame where +x is the front of the hat.
## Shading follows the props: dark base, mid tone, lit patch toward the upper-left, dark outline.

const STYLES := [
	{
		"name": "Trail Felt",
		"brim": Vector2(12.5, 15.0), "square": 0.0, "wave": 0.02,
		"base": Color("6a4524"), "mid": Color("7a5530"), "light": Color("8e6a40"), "dark": Color("5a3a1e"),
		"crown": Vector2(9.0, 6.2), "taper": 0.0, "top": "pinch",
		"crown_base": Color("4a2e18"), "crown_mid": Color("7a5530"), "crown_light": Color("a07a4a"),
		"band": Color("2b1d12"), "deco": "studs", "deco_col": Color("c8a24a"),
	},
	{
		"name": "Cattleman",
		"brim": Vector2(13.0, 16.0), "square": 0.3, "wave": 0.01,
		"base": Color("3a1d14"), "mid": Color("45241a"), "light": Color("5a3326"), "dark": Color("2a140e"),
		"crown": Vector2(8.8, 6.8), "taper": 0.3, "top": "teardrop",
		"crown_base": Color("2e170f"), "crown_mid": Color("5a2f1e"), "crown_light": Color("7a4630"),
		"band": Color("1a0f0a"), "deco": "braid", "deco_col": Color("a8743e"),
	},
	{
		"name": "Suede Drifter",
		"brim": Vector2(13.0, 16.5), "square": 0.25, "wave": 0.03,
		"base": Color("b07a40"), "mid": Color("c08a4c"), "light": Color("d6a466"), "dark": Color("946232"),
		"crown": Vector2(9.0, 7.0), "taper": 0.38, "top": "teardrop",
		"crown_base": Color("8e5f2e"), "crown_mid": Color("c08a4c"), "crown_light": Color("dcae72"),
		"band": Color("a87442"), "deco": "conchos", "deco_col": Color("6e6a64"),
	},
	{
		"name": "Outback",
		"brim": Vector2(12.0, 14.0), "square": 0.0, "wave": 0.0, "piping": Color("4a2418"),
		"base": Color("8a5530"), "mid": Color("9a643a"), "light": Color("b07a4a"), "dark": Color("6a3e22"),
		"crown": Vector2(8.5, 6.5), "taper": 0.05, "top": "flat",
		"crown_base": Color("6a3e22"), "crown_mid": Color("9a643a"), "crown_light": Color("b07e52"),
		"band": Color("5a3420"), "deco": "braid", "deco_col": Color("9a8a70"),
	},
	{
		"name": "Outlaw",
		"brim": Vector2(12.5, 15.5), "square": 0.15, "wave": 0.02,
		"base": Color("1f1d22"), "mid": Color("2a282e"), "light": Color("3e3b44"), "dark": Color("141317"),
		"crown": Vector2(9.0, 6.0), "taper": 0.1, "top": "pinch",
		"crown_base": Color("141317"), "crown_mid": Color("2e2c33"), "crown_light": Color("4a4752"),
		"band": Color("0c0c0e"), "deco": "conchos", "deco_col": Color("c0c4ca"),
	},
	# ---- Small-brim hats. Keep them after the originals: saved maps store hat indices.
	{
		"name": "Bowler",
		"brim": Vector2(9.5, 11.0), "square": 0.0, "wave": 0.0, "piping": Color("0e0e10"),
		"base": Color("26252a"), "mid": Color("323036"), "light": Color("46434d"), "dark": Color("18171b"),
		"crown": Vector2(8.5, 7.5), "taper": 0.0, "top": "dome",
		"crown_base": Color("1c1b1f"), "crown_mid": Color("2e2c32"), "crown_light": Color("5a5662"),
		"band": Color("0e0e10"), "deco": "none", "deco_col": Color("0e0e10"),
	},
	{
		"name": "Flat Cap",
		"brim": Vector2(13.0, 10.0), "square": 0.15, "wave": 0.0, "peak": true,
		"base": Color("4a4238"), "mid": Color("5c5246"), "light": Color("726758"), "dark": Color("362f27"),
		"crown": Vector2(9.5, 8.0), "taper": 0.4, "top": "flat",
		"crown_base": Color("3c352c"), "crown_mid": Color("6a5f50"), "crown_light": Color("8a7d6a"),
		"band": Color("2e2822"), "deco": "studs", "deco_col": Color("3a3a3a"),
	},
	{
		"name": "Snap Fedora",
		"brim": Vector2(10.5, 12.5), "square": 0.1, "wave": 0.01,
		"base": Color("8a7a5e"), "mid": Color("9a8a6c"), "light": Color("b0a07e"), "dark": Color("6e6048"),
		"crown": Vector2(9.0, 6.5), "taper": 0.15, "top": "pinch",
		"crown_base": Color("6e6048"), "crown_mid": Color("9a8a6c"), "crown_light": Color("bcac8a"),
		"band": Color("2e2218"), "deco": "braid", "deco_col": Color("4a3a28"),
	},
	{
		"name": "Porkpie",
		"brim": Vector2(10.0, 11.5), "square": 0.0, "wave": 0.0,
		"base": Color("c9b48a"), "mid": Color("d6c298"), "light": Color("e6d4ae"), "dark": Color("a8946c"),
		"crown": Vector2(8.5, 7.0), "taper": 0.0, "top": "flat",
		"crown_base": Color("a8946c"), "crown_mid": Color("d2be94"), "crown_light": Color("eadab6"),
		"band": Color("4a3626"), "deco": "none", "deco_col": Color("4a3626"),
	},
	{
		"name": "Homburg",
		"brim": Vector2(10.5, 12.0), "square": 0.05, "wave": 0.0, "piping": Color("101012"),
		"base": Color("3a3a40"), "mid": Color("46464d"), "light": Color("5a5a63"), "dark": Color("26262b"),
		"crown": Vector2(8.8, 6.8), "taper": 0.1, "top": "teardrop",
		"crown_base": Color("2a2a2f"), "crown_mid": Color("44444b"), "crown_light": Color("62626c"),
		"band": Color("141416"), "deco": "none", "deco_col": Color("141416"),
	},
	{
		"name": "Gambler",
		"brim": Vector2(11.0, 13.0), "square": 0.1, "wave": 0.0,
		"base": Color("17151a"), "mid": Color("221f26"), "light": Color("36323d"), "dark": Color("0e0d10"),
		"crown": Vector2(8.5, 7.2), "taper": 0.0, "top": "flat",
		"crown_base": Color("0e0d10"), "crown_mid": Color("221f26"), "crown_light": Color("3c3844"),
		"band": Color("7a1e1e"), "deco": "feather", "deco_col": Color("d8cdb0"),
	},
	{
		"name": "Sombrero Corto",
		"brim": Vector2(11.5, 13.5), "square": 0.0, "wave": 0.04,
		"base": Color("c8a458"), "mid": Color("d6b46a"), "light": Color("e6c880"), "dark": Color("a88640"),
		"crown": Vector2(7.5, 6.0), "taper": 0.2, "top": "teardrop",
		"crown_base": Color("a88640"), "crown_mid": Color("d2b062"), "crown_light": Color("eed08a"),
		"band": Color("8a2a24"), "deco": "braid", "deco_col": Color("f0e2b8"),
	},
	{
		"name": "Ranch Slouch",
		"brim": Vector2(10.5, 12.0), "square": 0.0, "wave": 0.04,
		"base": Color("6e6a48"), "mid": Color("7c7852"), "light": Color("928e66"), "dark": Color("56523a"),
		"crown": Vector2(9.5, 7.0), "taper": 0.1, "top": "pinch",
		"crown_base": Color("56523a"), "crown_mid": Color("7c7852"), "crown_light": Color("a09c72"),
		"band": Color("3a3624"), "deco": "none", "deco_col": Color("3a3624"),
	},
	{
		"name": "Bandit Bowler",
		"brim": Vector2(9.0, 10.5), "square": 0.0, "wave": 0.02,
		"base": Color("6a5a48"), "mid": Color("786654"), "light": Color("908068"), "dark": Color("4e4132"),
		"crown": Vector2(8.5, 7.0), "taper": 0.0, "top": "dome",
		"crown_base": Color("463a2c"), "crown_mid": Color("6e5d4a"), "crown_light": Color("94826a"),
		"band": Color("2a2018"), "deco": "studs", "deco_col": Color("a0a0a0"),
	},
]


static func count() -> int:
	return STYLES.size()


static func style_name(idx: int) -> String:
	return str(STYLES[clampi(idx, 0, STYLES.size() - 1)]["name"])


static func brim_front(idx: int) -> float:
	var bs: Vector2 = STYLES[clampi(idx, 0, STYLES.size() - 1)]["brim"]
	return bs.x


## Draws hat `idx` on `ci` centred at `pos`, front pointing along `angle`, scaled by `s`.
static func draw(ci: CanvasItem, idx: int, pos: Vector2, angle: float, s: float = 1.0) -> void:
	var st: Dictionary = STYLES[clampi(idx, 0, STYLES.size() - 1)]
	ci.draw_set_transform(pos, angle, Vector2(s, s))
	var ol := Color(0.1, 0.07, 0.04, 0.9)
	var bs: Vector2 = st["brim"]
	var sq: float = st["square"]
	var peak: bool = st.get("peak", false)  # cap: the brim is only a peak at the front
	var brim := _peak(bs, sq) if peak else _brim(bs, sq, st["wave"])

	# Brim: shadow (fixed world direction), base, mid tone, lit and dark felt patches
	ci.draw_colored_polygon(_shift(brim, _u(Vector2(2, 3), angle)), Color(0, 0, 0, 0.3))
	ci.draw_colored_polygon(brim, st["base"])
	if peak:
		ci.draw_colored_polygon(_peak(bs * 0.86, sq, _u(Vector2(-0.6, -0.6), angle)), st["mid"])
		ci.draw_colored_polygon(_ellipse(bs.x * 0.2, bs.y * 0.22, 10, Vector2(bs.x * 0.7, 0.0)), st["light"])
	else:
		ci.draw_colored_polygon(_brim(bs * 0.86, sq, 0.0, _u(Vector2(-0.6, -0.6), angle)), st["mid"])
		ci.draw_colored_polygon(_ellipse(bs.x * 0.42, bs.y * 0.28, 12, _u(Vector2(-0.55, -0.55), angle) * bs.y), st["light"])
		ci.draw_colored_polygon(_ellipse(bs.x * 0.32, bs.y * 0.22, 10, _u(Vector2(0.5, 0.55), angle) * bs.y), st["dark"])
		ci.draw_colored_polygon(_ellipse(bs.x * 0.22, bs.y * 0.16, 8, _u(Vector2(-0.6, 0.45), angle) * bs.y), st["light"])
	if st.has("piping"):
		ci.draw_polyline(_close(brim), st["piping"], 2.4)
		ci.draw_polyline(_close(brim), ol, 0.8)
	else:
		ci.draw_polyline(_close(brim), ol, 1.5)

	# Crown and the shadow it casts on the brim
	var cs: Vector2 = st["crown"]
	var tp: float = st["taper"]
	ci.draw_colored_polygon(_crown(cs + Vector2(1.6, 2.0), tp, _u(Vector2(1.0, 1.5), angle)), Color(0.08, 0.05, 0.03, 0.45))
	var crown := _crown(cs, tp, Vector2(-0.5, 0))
	ci.draw_colored_polygon(crown, st["crown_base"])
	ci.draw_colored_polygon(_crown(cs * 0.88, tp, Vector2(-0.9, -0.4)), st["crown_mid"])
	var c_mid: Color = st["crown_mid"]
	var c_light: Color = st["crown_light"]
	var c_base: Color = st["crown_base"]
	match st["top"]:
		"pinch":
			# Two lit lobes with a dent running front to back
			ci.draw_colored_polygon(_ellipse(cs.x * 0.66, cs.y * 0.29, 12, Vector2(-1.2, -cs.y * 0.39)), c_light)
			ci.draw_colored_polygon(_ellipse(cs.x * 0.66, cs.y * 0.26, 12, Vector2(-1.2, cs.y * 0.4)), c_mid.lerp(c_light, 0.4))
			ci.draw_colored_polygon(_ellipse(cs.x * 0.75, cs.y * 0.21, 12, Vector2(-0.5, 0)), c_base)
			ci.draw_line(Vector2(-cs.x * 0.66, 0), Vector2(cs.x * 0.66, 0), Color(0.08, 0.05, 0.03, 0.7), 1.0)
		"teardrop":
			# Deep teardrop dent narrowing to the front, with a lit ridge along one side
			ci.draw_colored_polygon(_crown(cs * Vector2(0.64, 0.6), tp * 1.2, Vector2(-1.4, 0)), c_mid.darkened(0.35))
			ci.draw_colored_polygon(_crown(cs * Vector2(0.4, 0.34), tp * 1.2, Vector2(-1.8, 0.3)), c_mid.darkened(0.5))
			var ridge := _crown(cs * 0.8, tp, Vector2(-0.8, 0))
			ci.draw_polyline(ridge.slice(13, 24), c_light, 1.2)
		"dome":
			# Round, unbroken crown with a soft highlight (bowler)
			ci.draw_colored_polygon(_ellipse(cs.x * 0.7, cs.y * 0.7, 16, Vector2(-1.0, -0.6)), c_mid.lerp(c_light, 0.35))
			ci.draw_colored_polygon(_ellipse(cs.x * 0.36, cs.y * 0.3, 10, Vector2(-2.6, -2.2)), c_light)
		"flat":
			# Raised rim around a flatter top panel
			var panel := _crown(cs * 0.7, tp, Vector2(-0.8, -0.3))
			ci.draw_colored_polygon(panel, c_light.darkened(0.08))
			ci.draw_colored_polygon(_ellipse(cs.x * 0.3, cs.y * 0.22, 10, Vector2(-2.0, -1.4)), c_light)
			ci.draw_polyline(_close(panel), Color(c_base, 0.7), 1.0)

	# Band and decoration
	var band := _close(crown)
	ci.draw_polyline(band, st["band"], 1.8)
	var deco_col: Color = st["deco_col"]
	match st["deco"]:
		"studs":
			for sy in [-1.0, 1.0]:
				ci.draw_circle(Vector2(0.5, sy * cs.y * 0.97), 0.9, deco_col)
		"braid":
			for i in range(0, crown.size(), 2):
				ci.draw_line(crown[i], crown[(i + 1) % crown.size()], deco_col, 1.2)
		"conchos":
			for i in 5:
				var p := crown[(i * crown.size() / 5 + 2) % crown.size()]
				ci.draw_circle(p, 1.15, deco_col)
				ci.draw_arc(p, 1.15, 0.0, TAU, 8, Color(0.1, 0.1, 0.1, 0.8), 0.5)
		"feather":
			# A feather tucked into the band at the back-left, sweeping out past the crown
			var root := Vector2(-cs.x * 0.2, -cs.y * 0.95)
			var tip := Vector2(-cs.x * 1.05, -cs.y * 1.55)
			ci.draw_line(root, tip, Color(deco_col, 0.9), 2.2)
			ci.draw_line(root, tip, Color(0.1, 0.07, 0.04, 0.7), 0.6)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- shape helpers

## Converts a world-space offset into the hat's rotated frame, so light/shadow stay put as it turns.
static func _u(v: Vector2, angle: float) -> Vector2:
	return v.rotated(-angle)


## Brim outline: superellipse (`sq` > 0 squares off the sides) with an optional wavy edge.
static func _brim(size: Vector2, sq: float, wave: float, off: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * float(i) / 32.0
		var c := cos(a)
		var sn := sin(a)
		var w := 1.0 + wave * (sin(a * 5.0 + 1.0) + 0.8 * sin(a * 3.0))
		pts.append(off + Vector2(signf(c) * pow(absf(c), 1.0 - sq) * size.x, signf(sn) * pow(absf(sn), 1.0 - sq) * size.y) * w)
	return pts


## Front half of the brim shape only (a cap's peak). The flat back edge hides under the crown.
static func _peak(size: Vector2, sq: float, off: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var full := _brim(size, sq, 0.0, off)
	var pts := full.slice(24)  # points 24..31: back edge to the front on the -y side
	pts.append_array(full.slice(0, 9))  # points 0..8: front to the back edge on the +y side
	return pts


## Crown outline: oval that narrows toward the front (+x) by `taper` (0 = plain oval).
static func _crown(size: Vector2, taper: float, off: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		var c := cos(a)
		var k := 1.0 - taper * (c + 1.0) * 0.5
		pts.append(off + Vector2(c * size.x, sin(a) * size.y * k))
	return pts


static func _ellipse(rx: float, ry: float, n: int, off: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(off + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func _close(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	out.append(pts[0])
	return out


static func _shift(pts: PackedVector2Array, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + off)
	return out
