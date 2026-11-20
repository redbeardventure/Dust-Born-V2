class_name MapData
extends RefCounted
## Map data model, terrain/prop definitions, JSON save/load and a forest scatter helper.
##
## A map is a Dictionary:
##   size: Vector2, ambient: Color, background: String (terrain key), spawn: Vector2
##   polygons: [{type, points: PackedVector2Array}]   (drawn in array order, later = on top)
##   walls:    [{points, closed, width}]
##   props:    [{type, pos, scale, rot, seed}]
##   lights:   [{pos, radius, color, energy, flicker}]
## NOTE: packed arrays are never mutated in place, only replaced, so undo snapshots stay valid.

const MAP_DIR := "user://maps"
const DEFAULT_PATH := "user://maps/current.json"
const DEFAULT_SIZE := Vector2(2048, 1728)

## The map shared between the menu, editor and game screens.
static var working: Dictionary = {}
static var current_path: String = DEFAULT_PATH
static var _tex_cache: Dictionary = {}

static var TERRAIN: Dictionary = {
	"grass": {"label": "Grass", "a": Color("5a7026"), "b": Color("8b9d3b"), "freq": 0.018, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.0},
	"grass_dark": {"label": "Grass (dark patch)", "a": Color("465a1d"), "b": Color("66792b"), "freq": 0.025, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.0},
	"dirt": {"label": "Dirt path", "a": Color("6a5638"), "b": Color("8f7a52"), "freq": 0.05, "outline": Color(0, 0, 0, 0), "blocks_scatter": true, "planks": false, "speckle": 0.08},
	"stone": {"label": "Stone floor", "a": Color("6e6b64"), "b": Color("8f8b82"), "freq": 0.05, "outline": Color(0.15, 0.13, 0.12, 0.8), "blocks_scatter": true, "planks": false, "speckle": 0.06},
	"wood": {"label": "Wood floor", "a": Color("55371f"), "b": Color("7b5230"), "freq": 0.04, "outline": Color(0.1, 0.07, 0.04, 0.6), "blocks_scatter": true, "planks": false, "plank_w": 16, "vertical": false, "speckle": 0.0},
	"wood_planks_dark": {"label": "Wood: dark boards", "a": Color("2b1d12"), "b": Color("43301d"), "freq": 0.04, "outline": Color(0.05, 0.03, 0.02, 0.8), "blocks_scatter": true, "planks": false, "plank_w": 16, "vertical": true, "speckle": 0.02},
	"wood_worn": {"label": "Wood: worn, cracked", "a": Color("3a2a1b"), "b": Color("57402a"), "freq": 0.03, "outline": Color(0.06, 0.04, 0.02, 0.8), "blocks_scatter": true, "planks": false, "plank_w": 16, "vertical": true, "cracks": true, "speckle": 0.01},
	"wood_planks_light": {"label": "Wood: light planks", "a": Color("8a6a43"), "b": Color("b08c5a"), "freq": 0.04, "outline": Color(0.15, 0.1, 0.05, 0.6), "blocks_scatter": true, "planks": false, "plank_w": 16, "vertical": false, "speckle": 0.0},
	"wood_deck": {"label": "Wood: wide deck", "a": Color("5c3b21"), "b": Color("84582f"), "freq": 0.03, "outline": Color(0.1, 0.06, 0.03, 0.8), "blocks_scatter": true, "planks": false, "plank_w": 32, "vertical": false, "cracks": true, "speckle": 0.0},
	"wood_braced": {"label": "Wood: braced beams", "a": Color("3a2818"), "b": Color("523a22"), "freq": 0.05, "outline": Color(0.05, 0.03, 0.02, 0.9), "blocks_scatter": true, "planks": false, "cross": 64, "speckle": 0.02},
	"dark": {"label": "Dark floor", "a": Color("3a342e"), "b": Color("524a41"), "freq": 0.04, "outline": Color(0.08, 0.07, 0.06, 0.7), "blocks_scatter": true, "planks": false, "speckle": 0.04},
	"carpet": {"label": "Carpet", "a": Color("2a6f35"), "b": Color("3d9448"), "freq": 0.08, "outline": Color(0.85, 0.7, 0.3, 0.9), "blocks_scatter": true, "planks": false, "speckle": 0.0},
	"water": {"label": "Water", "a": Color("2a5f70"), "b": Color("3f8696"), "freq": 0.03, "outline": Color(0.1, 0.2, 0.25, 0.8), "blocks_scatter": true, "planks": false, "speckle": 0.0},
	"shadow": {"label": "Overlay: shadow", "a": Color(0, 0, 0, 0.25), "b": Color(0, 0, 0, 0.45), "freq": 0.01, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.0},
	"moss": {"label": "Overlay: moss", "a": Color(0.25, 0.45, 0.1, 0.3), "b": Color(0.45, 0.65, 0.2, 0.5), "freq": 0.04, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.0},
	"blood": {"label": "Overlay: blood", "a": Color(0.4, 0.03, 0.03, 0.45), "b": Color(0.6, 0.05, 0.05, 0.65), "freq": 0.06, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.0},
	# --- wood / deck options (vertical = boards run top-to-bottom, plank = board width in px, varied = per-board shade) ---
	"wood_vertical": {"label": "Wood: mid boards (vertical)", "a": Color("6b4526"), "b": Color("8f6338"), "freq": 0.04, "outline": Color(0.1, 0.07, 0.04, 0.7), "blocks_scatter": true, "planks": false, "plank_w": 32, "vertical": true, "speckle": 0.0},
	"deck_ship": {"label": "Wood: ship deck (lengthwise)", "a": Color("5b3a20"), "b": Color("7d5632"), "freq": 0.05, "outline": Color(0.07, 0.04, 0.02, 0.9), "blocks_scatter": true, "planks": false, "plank_w": 16, "vertical": true, "speckle": 0.0},
	"dock_weathered": {"label": "Wood: weathered dock", "a": Color("6b5638"), "b": Color("8f7852"), "freq": 0.05, "outline": Color(0.1, 0.08, 0.06, 0.8), "blocks_scatter": true, "planks": false, "plank_w": 32, "vertical": false, "cracks": true, "speckle": 0.01},
	"dock_vertical": {"label": "Wood: weathered dock (vertical)", "a": Color("6b5638"), "b": Color("8f7852"), "freq": 0.05, "outline": Color(0.1, 0.08, 0.06, 0.8), "blocks_scatter": true, "planks": false, "plank_w": 32, "vertical": true, "cracks": true, "speckle": 0.01},
	"driftwood": {"label": "Wood: bleached driftwood", "a": Color("9a8f80"), "b": Color("c0b6a2"), "freq": 0.05, "outline": Color(0.2, 0.18, 0.15, 0.7), "blocks_scatter": true, "planks": false, "plank_w": 32, "vertical": true, "speckle": 0.01},
	"canvas_red": {"label": "Red canvas / tarp", "a": Color("b2402e"), "b": Color("d4583e"), "freq": 0.07, "outline": Color(0.3, 0.08, 0.05, 0.85), "blocks_scatter": true, "planks": false, "speckle": 0.0},
	# --- train theme ---
	"rail_dirt": {"label": "Yard dirt", "a": Color("5f5430"), "b": Color("7d6e3c"), "freq": 0.03, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.05},
	"gravel": {"label": "Gravel ballast", "a": Color("6b655a"), "b": Color("918a7b"), "freq": 0.08, "outline": Color(0, 0, 0, 0), "blocks_scatter": true, "planks": false, "speckle": 0.18},
	"cliff": {"label": "Rocky ground", "a": Color("5f584a"), "b": Color("857b69"), "freq": 0.04, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.12},
	"river": {"label": "River", "a": Color("6d7e8e"), "b": Color("9fb0bd"), "freq": 0.02, "outline": Color(0.2, 0.25, 0.3, 0.6), "blocks_scatter": true, "planks": false, "speckle": 0.0},
	"train_wood": {"label": "Train: wood floor", "a": Color("7a5430"), "b": Color("a07a48"), "freq": 0.03, "outline": Color(0.1, 0.07, 0.04, 0.8), "blocks_scatter": true, "planks": true, "speckle": 0.0},
	"train_black": {"label": "Train: dark floor", "a": Color("1a1715"), "b": Color("2b2724"), "freq": 0.05, "outline": Color(0, 0, 0, 0.9), "blocks_scatter": true, "planks": false, "speckle": 0.0},
	"train_blue": {"label": "Train: blue carpet", "a": Color("2f5f9a"), "b": Color("4a82c0"), "freq": 0.03, "outline": Color(0.1, 0.12, 0.2, 0.9), "blocks_scatter": true, "planks": false, "speckle": 0.0},
	"train_red": {"label": "Train: red upholstery", "a": Color("a8283a"), "b": Color("cc3d4c"), "freq": 0.06, "outline": Color(0.25, 0.04, 0.06, 0.9), "blocks_scatter": true, "planks": false, "speckle": 0.0},
	"steel": {"label": "Train: steel deck", "a": Color("59606b"), "b": Color("7d8590"), "freq": 0.05, "outline": Color(0.1, 0.11, 0.13, 0.9), "blocks_scatter": true, "planks": false, "speckle": 0.05},
	# --- desert ruins theme ---
	"sand": {"label": "Sand", "a": Color("c9a468"), "b": Color("e0c58a"), "freq": 0.02, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.05},
	"sand_dune": {"label": "Dune shade", "a": Color("b88f52"), "b": Color("d4ad6c"), "freq": 0.03, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.04},
	"sandstone": {"label": "Sandstone rock", "a": Color("a8845a"), "b": Color("c9a477"), "freq": 0.05, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.1},
	"ruin_tile": {"label": "Ruin tiles", "a": Color("9a8a6c"), "b": Color("bcab8a"), "freq": 0.05, "outline": Color(0.25, 0.2, 0.12, 0.8), "blocks_scatter": true, "planks": false, "speckle": 0.08},
	"oasis": {"label": "Oasis water", "a": Color("2b7f86"), "b": Color("4fb3a8"), "freq": 0.03, "outline": Color(0.1, 0.3, 0.25, 0.8), "blocks_scatter": true, "planks": false, "speckle": 0.0},
	# --- snow theme ---
	"snow": {"label": "Snow", "a": Color("dfe8f2"), "b": Color("f6fafe"), "freq": 0.02, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.03},
	"snow_deep": {"label": "Deep snow", "a": Color("c4d4e6"), "b": Color("e4eef8"), "freq": 0.03, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.0},
	"ice": {"label": "Ice", "a": Color("8fc4de"), "b": Color("c4e6f4"), "freq": 0.02, "outline": Color(0.3, 0.5, 0.65, 0.8), "blocks_scatter": true, "planks": false, "speckle": 0.0},
	"frozen_dirt": {"label": "Frozen path", "a": Color("7a6e62"), "b": Color("a09384"), "freq": 0.05, "outline": Color(0, 0, 0, 0), "blocks_scatter": true, "planks": false, "speckle": 0.06},
	"icy_water": {"label": "Icy water", "a": Color("2d5878"), "b": Color("4a86a8"), "freq": 0.03, "outline": Color(0.1, 0.2, 0.3, 0.8), "blocks_scatter": true, "planks": false, "speckle": 0.0},
	# --- coast theme ---
	"ocean": {"label": "Ocean (rough sea)", "a": Color("0b3f6e"), "b": Color("2a8ac4"), "freq": 0.02, "outline": Color(0, 0, 0, 0), "blocks_scatter": true, "planks": false, "speckle": 0.0},
	"lagoon": {"label": "Lagoon (tropical)", "a": Color("1a9aa8"), "b": Color("5fe0d0"), "freq": 0.025, "outline": Color(0.05, 0.3, 0.3, 0.6), "blocks_scatter": true, "planks": false, "speckle": 0.0},
	"sewer": {"label": "Sewer water", "a": Color("2c3a24"), "b": Color("4c6034"), "freq": 0.035, "outline": Color(0.08, 0.1, 0.06, 0.8), "blocks_scatter": true, "planks": false, "speckle": 0.0},
	# --- town theme ---
	"cobble": {"label": "Cobblestone", "a": Color("76736d"), "b": Color("9a968d"), "freq": 0.09, "outline": Color(0, 0, 0, 0), "blocks_scatter": true, "planks": false, "speckle": 0.14},
	"plaza": {"label": "Plaza paving", "a": Color("a29a88"), "b": Color("c4bba5"), "freq": 0.06, "outline": Color(0.2, 0.18, 0.14, 0.6), "blocks_scatter": true, "planks": false, "speckle": 0.08},
	# --- swamp theme ---
	"bog": {"label": "Bog water", "a": Color("2f3d2a"), "b": Color("47592f"), "freq": 0.03, "outline": Color(0.08, 0.12, 0.06, 0.8), "blocks_scatter": true, "planks": false, "speckle": 0.0},
	"mud": {"label": "Mud", "a": Color("4e3f2b"), "b": Color("6b5a3c"), "freq": 0.04, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.08},
	"swamp_grass": {"label": "Swamp grass", "a": Color("4a5a28"), "b": Color("6d7a37"), "freq": 0.03, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.0},
	"algae": {"label": "Overlay: algae", "a": Color(0.3, 0.55, 0.15, 0.45), "b": Color(0.5, 0.75, 0.25, 0.65), "freq": 0.05, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.0},
	"mist": {"label": "Overlay: mist", "a": Color(0.8, 0.9, 0.85, 0.18), "b": Color(0.9, 0.95, 0.9, 0.35), "freq": 0.01, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.0},
}

## Each theme is a palette for the editor plus default ground/ambient for new maps.
## Theme "all" is only a palette filter in the editor (shows everything).
static var THEMES: Dictionary = {
	"fantasy": {
		"label": "Forest / Manor",
		"background": "grass",
		"ambient": Color(0.62, 0.64, 0.72),
		"terrain": ["grass", "grass_dark", "dirt", "stone", "wood", "wood_planks_dark", "wood_worn", "wood_planks_light", "wood_deck", "wood_braced", "wood_vertical", "canvas_red", "dark", "carpet", "water", "shadow", "moss", "blood"],
		"props": ["tree", "bush", "rock", "barrel", "crate", "table", "well", "torch"],
	},
	"train": {
		"label": "Train / Rail yard",
		"background": "rail_dirt",
		"ambient": Color(0.84, 0.82, 0.82),
		"terrain": ["rail_dirt", "gravel", "grass", "grass_dark", "cliff", "river", "train_wood", "wood_planks_dark", "wood_deck", "wood_braced", "train_black", "train_blue", "train_red", "steel", "shadow", "blood"],
		"props": ["locomotive", "coal_car", "smoke", "bench", "window", "crate", "barrel", "torch", "tree", "bush", "rock"],
	},
	"desert": {
		"label": "Desert ruins",
		"background": "sand",
		"ambient": Color(0.95, 0.88, 0.76),
		"terrain": ["sand", "sand_dune", "sandstone", "ruin_tile", "oasis", "stone", "dark", "wood_planks_light", "driftwood", "canvas_red", "shadow"],
		"props": ["cactus", "palm", "pillar", "broken_pillar", "rubble", "rock", "crate", "barrel", "table", "torch"],
		"scatter": ["cactus", "rock", "rubble"],
	},
	"snow": {
		"label": "Snow / Winter",
		"background": "snow",
		"ambient": Color(0.72, 0.8, 0.95),
		"terrain": ["snow", "snow_deep", "ice", "frozen_dirt", "icy_water", "wood", "wood_planks_dark", "wood_worn", "wood_planks_light", "wood_deck", "stone", "shadow"],
		"props": ["pine", "snowdrift", "snowman", "campfire", "stump", "rock", "crate", "barrel", "table", "torch"],
		"scatter": ["pine", "rock", "snowdrift"],
	},
	"town": {
		"label": "Town / Village",
		"background": "grass",
		"ambient": Color(0.86, 0.86, 0.9),
		"terrain": ["grass", "grass_dark", "dirt", "cobble", "plaza", "wood", "wood_planks_dark", "wood_worn", "wood_planks_light", "wood_deck", "wood_braced", "wood_vertical", "dock_weathered", "dock_vertical", "canvas_red", "stone", "carpet", "water", "shadow"],
		"props": ["stall", "fountain", "lamppost", "cart", "haybale", "well", "tree", "bush", "barrel", "crate", "table", "torch", "rock"],
		"scatter": ["tree", "rock", "bush"],
	},
	"coast": {
		"label": "Coast / Harbor",
		"background": "ocean",
		"ambient": Color(0.82, 0.86, 0.95),
		"terrain": ["ocean", "lagoon", "sand", "cliff", "stone", "plaza", "wood", "dark", "sewer", "deck_ship", "dock_weathered", "dock_vertical", "driftwood", "wood_vertical", "canvas_red", "shadow"],
		"props": ["palm", "rock", "crate", "barrel", "table", "lamppost", "torch", "bush"],
		"scatter": ["rock", "palm"],
	},
	"swamp": {
		"label": "Swamp",
		"background": "mud",
		"ambient": Color(0.56, 0.68, 0.62),
		"terrain": ["mud", "swamp_grass", "bog", "algae", "mist", "moss", "wood", "wood_planks_dark", "wood_worn", "wood_deck", "dock_weathered", "dock_vertical", "driftwood", "dirt", "shadow", "blood"],
		"props": ["dead_tree", "reeds", "lilypad", "mushroom", "stump", "wisp", "rock", "bush", "crate", "barrel", "torch"],
		"scatter": ["dead_tree", "stump", "reeds"],
	},
}

const THEME_ORDER := ["fantasy", "train", "desert", "snow", "town", "swamp", "coast", "all"]

## style -> [label, default width]
const WALL_STYLES := {
	"wall": ["Stone wall", 12.0],
	"hull": ["Train hull", 16.0],
	"rail": ["Rail track", 70.0],
}
const WALL_STYLE_ORDER := ["wall", "hull", "rail"]

## radius = selection/footprint size, solid = collision radius (0 = walk-through)
static var PROPS: Dictionary = {
	"tree": {"label": "Tree", "radius": 56.0, "solid": 8.0, "fade": true},
	"bush": {"label": "Bush", "radius": 26.0, "solid": 0.0},
	# rect = rectangular collision/shadow footprint (local, before rotation); fade = drawn above the player and fades when covering them
	"locomotive": {"label": "Locomotive", "radius": 220.0, "solid": 0.0, "rect": Vector2(150, 430)},
	"coal_car": {"label": "Coal tender", "radius": 100.0, "solid": 0.0, "rect": Vector2(190, 190)},
	"smoke": {"label": "Smoke (overhead)", "radius": 90.0, "solid": 0.0, "fade": true},
	"bench": {"label": "Train bench", "radius": 38.0, "solid": 0.0, "rect": Vector2(70, 28)},
	"window": {"label": "Window", "radius": 24.0, "solid": 0.0},
	"rock": {"label": "Rock", "radius": 34.0, "solid": 28.0},
	"barrel": {"label": "Barrel", "radius": 14.0, "solid": 12.0},
	"crate": {"label": "Crate", "radius": 18.0, "solid": 16.0},
	"table": {"label": "Table", "radius": 40.0, "solid": 30.0},
	"well": {"label": "Well", "radius": 36.0, "solid": 34.0},
	# light = {r: radius, c: color, e: energy}; props with it emit a flickering light
	"torch": {"label": "Torch (light)", "radius": 10.0, "solid": 0.0, "light": {"r": 240.0, "c": Color(1.0, 0.62, 0.3), "e": 1.1}},
	# desert
	"cactus": {"label": "Cactus", "radius": 24.0, "solid": 10.0},
	"palm": {"label": "Palm tree", "radius": 64.0, "solid": 8.0, "fade": true},
	"pillar": {"label": "Stone pillar", "radius": 26.0, "solid": 21.0},
	"broken_pillar": {"label": "Broken pillar", "radius": 24.0, "solid": 18.0},
	"rubble": {"label": "Rubble", "radius": 28.0, "solid": 0.0},
	# snow
	"pine": {"label": "Pine tree", "radius": 52.0, "solid": 8.0, "fade": true},
	"snowdrift": {"label": "Snowdrift", "radius": 34.0, "solid": 0.0},
	"snowman": {"label": "Snowman", "radius": 20.0, "solid": 14.0},
	"campfire": {"label": "Campfire (light)", "radius": 24.0, "solid": 0.0, "light": {"r": 300.0, "c": Color(1.0, 0.55, 0.2), "e": 1.2}},
	"stump": {"label": "Tree stump", "radius": 18.0, "solid": 14.0},
	# town
	"stall": {"label": "Market stall", "radius": 52.0, "solid": 0.0, "rect": Vector2(96, 64)},
	"fountain": {"label": "Fountain", "radius": 52.0, "solid": 46.0},
	"lamppost": {"label": "Lamppost (light)", "radius": 12.0, "solid": 6.0, "light": {"r": 300.0, "c": Color(1.0, 0.85, 0.5), "e": 1.0}},
	"cart": {"label": "Cart", "radius": 46.0, "solid": 0.0, "rect": Vector2(84, 52)},
	"haybale": {"label": "Hay bale", "radius": 24.0, "solid": 18.0},
	# swamp
	"dead_tree": {"label": "Dead tree", "radius": 48.0, "solid": 7.0, "fade": true},
	"reeds": {"label": "Reeds", "radius": 28.0, "solid": 0.0},
	"lilypad": {"label": "Lily pads", "radius": 24.0, "solid": 0.0},
	"mushroom": {"label": "Mushrooms", "radius": 16.0, "solid": 0.0},
	"wisp": {"label": "Will-o-wisp (light)", "radius": 14.0, "solid": 0.0, "light": {"r": 220.0, "c": Color(0.5, 1.0, 0.8), "e": 1.0}},
}


static func theme_terrain(theme: String) -> Array:
	if THEMES.has(theme):
		return THEMES[theme]["terrain"]
	return TERRAIN.keys()


static func theme_props(theme: String) -> Array:
	if THEMES.has(theme):
		return THEMES[theme]["props"]
	return PROPS.keys()


static func empty(theme: String = "fantasy") -> Dictionary:
	if not THEMES.has(theme):
		theme = "fantasy"
	return {
		"theme": theme,
		"size": DEFAULT_SIZE,
		"ambient": THEMES[theme]["ambient"],
		"background": THEMES[theme]["background"],
		"spawn": DEFAULT_SIZE * 0.5,
		"polygons": [],
		"walls": [],
		"props": [],
		"lights": [],
	}


static func new_poly(type: String, pts: PackedVector2Array) -> Dictionary:
	return {"type": type, "points": pts}


static func new_wall(pts: PackedVector2Array, closed: bool, width: float = 12.0, style: String = "wall") -> Dictionary:
	return {"points": pts, "closed": closed, "width": width, "style": style}


static func new_prop(type: String, pos: Vector2, scale: float = 1.0, rot: float = 0.0, seed_v: int = -1) -> Dictionary:
	if seed_v < 0:
		seed_v = randi()
	return {"type": type, "pos": pos, "scale": scale, "rot": rot, "seed": seed_v}


static func new_light(pos: Vector2, radius: float = 300.0, color: Color = Color(1, 0.75, 0.45), energy: float = 1.0, flicker: bool = true) -> Dictionary:
	return {"pos": pos, "radius": radius, "color": color, "energy": energy, "flicker": flicker}


# ---------------------------------------------------------------- textures

static func get_texture(type: String) -> Texture2D:
	if _tex_cache.has(type):
		return _tex_cache[type]
	var def: Dictionary = TERRAIN.get(type, TERRAIN["grass"])
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = def["freq"]
	noise.fractal_octaves = 4
	noise.seed = type.hash()
	var src: Image = noise.get_seamless_image(256, 256)
	var img := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = type.hash()
	var col_a: Color = def["a"]
	var col_b: Color = def["b"]
	var planks: bool = def["planks"]
	var speckle: float = def["speckle"]
	for y in 256:
		for x in 256:
			var v: float = clampf(src.get_pixel(x, y).r, 0.0, 1.0)
			var c: Color = col_a.lerp(col_b, v)
			var g := rng.randf_range(-0.035, 0.035)
			c = Color(clampf(c.r + g, 0.0, 1.0), clampf(c.g + g, 0.0, 1.0), clampf(c.b + g, 0.0, 1.0), c.a)
			if def.has("plank_w"):
				# Styled boards: plank_w = board width px (divides 256), vertical = boards run up/down.
				var pw: int = def["plank_w"]
				var vertical: bool = def.get("vertical", false)
				var u := x if vertical else y   # across the boards
				var w := y if vertical else x   # along the boards
				var board := u / pw
				var tone := float((board * 7919 + int(type.hash() % 97)) % 13) / 13.0 - 0.5
				c = c.lightened(tone * 0.14) if tone > 0.0 else c.darkened(-tone * 0.2)
				if u % pw < 2:
					c = c.darkened(0.5)
				elif ((w + board * 97) % 128) < 2:
					c = c.darkened(0.4)
				if def.get("cracks", false) and absf(v - 0.5) < 0.012:
					c = c.darkened(0.55)
			elif def.has("cross"):
				# Braced beams: square panels with an X, like a plank corridor.
				var cs: int = def["cross"]
				var lx := x % cs
				var ly := y % cs
				if lx < 3 or ly < 3:
					c = c.darkened(0.5)
				elif absi(lx - ly) < 2 or absi(lx + ly - (cs - 1)) < 2:
					c = c.darkened(0.4)
			elif planks:
				if y % 32 < 2:
					c = c.darkened(0.45)
				elif ((x + (y / 32) * 97) % 128) < 2:
					c = c.darkened(0.35)
			if speckle > 0.0 and rng.randf() < speckle:
				c = c.darkened(0.3) if rng.randf() < 0.5 else c.lightened(0.25)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[type] = tex
	return tex


# ---------------------------------------------------------------- save / load

static func _pack(pts: PackedVector2Array) -> Array:
	var out: Array = []
	for p in pts:
		out.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
	return out


static func _unpack(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


static func _v2(arr: Variant, fallback: Vector2) -> Vector2:
	if arr is Array and arr.size() >= 2:
		return Vector2(float(arr[0]), float(arr[1]))
	return fallback


static func to_dict(d: Dictionary) -> Dictionary:
	var size: Vector2 = d["size"]
	var ambient: Color = d["ambient"]
	var spawn: Vector2 = d["spawn"]
	var out := {
		"version": 2,
		"theme": d.get("theme", "fantasy"),
		"size": [size.x, size.y],
		"ambient": ambient.to_html(false),
		"background": d["background"],
		"spawn": [spawn.x, spawn.y],
		"polygons": [],
		"walls": [],
		"props": [],
		"lights": [],
	}
	for p in d["polygons"]:
		out["polygons"].append({"type": p["type"], "points": _pack(p["points"])})
	for w in d["walls"]:
		out["walls"].append({"points": _pack(w["points"]), "closed": w["closed"], "width": w["width"], "style": w.get("style", "wall")})
	for pr in d["props"]:
		var pos: Vector2 = pr["pos"]
		out["props"].append({"type": pr["type"], "pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)], "scale": pr["scale"], "rot": pr["rot"], "seed": pr["seed"]})
	for l in d["lights"]:
		var lp: Vector2 = l["pos"]
		var lc: Color = l["color"]
		out["lights"].append({"pos": [lp.x, lp.y], "radius": l["radius"], "color": lc.to_html(false), "energy": l["energy"], "flicker": l["flicker"]})
	return out


static func from_dict(j: Dictionary) -> Dictionary:
	var d := empty(str(j.get("theme", "fantasy")))
	d["size"] = _v2(j.get("size"), DEFAULT_SIZE)
	d["ambient"] = Color(str(j.get("ambient", "9fa3b8")))
	d["background"] = str(j.get("background", "grass"))
	d["spawn"] = _v2(j.get("spawn"), d["size"] * 0.5)
	for p in j.get("polygons", []):
		d["polygons"].append(new_poly(str(p.get("type", "grass")), _unpack(p.get("points", []))))
	for w in j.get("walls", []):
		d["walls"].append(new_wall(_unpack(w.get("points", [])), bool(w.get("closed", false)), float(w.get("width", 12.0)), str(w.get("style", "wall"))))
	for pr in j.get("props", []):
		d["props"].append(new_prop(str(pr.get("type", "tree")), _v2(pr.get("pos"), Vector2.ZERO), float(pr.get("scale", 1.0)), float(pr.get("rot", 0.0)), int(pr.get("seed", 0))))
	for l in j.get("lights", []):
		d["lights"].append(new_light(_v2(l.get("pos"), Vector2.ZERO), float(l.get("radius", 300.0)), Color(str(l.get("color", "ffbf73"))), float(l.get("energy", 1.0)), bool(l.get("flicker", false))))
	return d


static func save_map(d: Dictionary, path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Could not write map: %s" % path)
		return false
	f.store_string(JSON.stringify(to_dict(d), "\t"))
	f.close()
	return true


static func load_map(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return from_dict(parsed)
	return {}


## Makes sure `working` holds a map: last saved map, otherwise the sample manor.
static func ensure_loaded() -> void:
	if not working.is_empty():
		return
	working = load_map(current_path)
	if working.is_empty():
		working = SampleMap.create()


# ---------------------------------------------------------------- geometry helpers

static func dist_to_path(p: Vector2, pts: PackedVector2Array, closed: bool) -> float:
	var best := INF
	var n := pts.size()
	var segs := n if closed else n - 1
	for i in segs:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


static func _scatter_ok(d: Dictionary, blockers: Array, pos: Vector2, r: float) -> bool:
	for poly in blockers:
		if Geometry2D.is_point_in_polygon(pos, poly):
			return false
		if dist_to_path(pos, poly, true) < r * 0.8:
			return false
	for w in d["walls"]:
		if dist_to_path(pos, w["points"], w["closed"]) < r + 10.0:
			return false
	for pr in d["props"]:
		var orad: float = PROPS.get(pr["type"], PROPS["tree"])["radius"] * float(pr["scale"])
		if pos.distance_to(pr["pos"]) < (r + orad) * 0.55:
			return false
	return true


## Randomly adds big/medium/small props while avoiding floors, paths, water and walls.
## `kinds` = [big, medium, small]; defaults to tree/rock/bush, or the map theme's "scatter" list.
static func scatter_props(d: Dictionary, trees: int, rocks: int, bushes: int, seed_v: int = 0, kinds: Array = []) -> int:
	if kinds.is_empty():
		kinds = THEMES.get(str(d.get("theme", "fantasy")), {}).get("scatter", ["tree", "rock", "bush"])
	var rng := RandomNumberGenerator.new()
	if seed_v == 0:
		rng.randomize()
	else:
		rng.seed = seed_v
	var blockers: Array = []
	for p in d["polygons"]:
		var def: Dictionary = TERRAIN.get(p["type"], {})
		var pts: PackedVector2Array = p["points"]
		if def.get("blocks_scatter", false) and pts.size() >= 3:
			blockers.append(pts)
	var plan: Array = []
	for i in trees:
		plan.append(kinds[0])
	for i in rocks:
		plan.append(kinds[1])
	for i in bushes:
		plan.append(kinds[2])
	var size: Vector2 = d["size"]
	var added := 0
	for kind in plan:
		var def: Dictionary = PROPS[kind]
		for attempt in 30:
			var pos := Vector2(rng.randf_range(-20.0, size.x + 20.0), rng.randf_range(-20.0, size.y + 20.0))
			var sc := rng.randf_range(0.8, 1.4) if kind == kinds[0] else rng.randf_range(0.7, 1.3)
			var r: float = def["radius"] * sc
			if not _scatter_ok(d, blockers, pos, r):
				continue
			d["props"].append(new_prop(kind, pos, sc, rng.randf() * TAU, rng.randi()))
			added += 1
			break
	return added
