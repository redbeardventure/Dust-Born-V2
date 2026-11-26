class_name MapData
extends RefCounted
## Map data model, terrain/prop definitions, JSON save/load and a forest scatter helper.
##
## A map is a Dictionary:
##   size: Vector2, ambient: Color, background: String (terrain key), spawn: Vector2
##   polygons: [{type, points: PackedVector2Array}]   (drawn in array order, later = on top)
##   walls:    [{points, closed, width}]
##   props:    [{type, pos, scale, rot, seed, loot}]   (loot only matters for LOOT_PROPS)
##   lights:   [{pos, radius, color, energy, flicker}]
##   npcs:     [{name, pos, weapon, loot, disposition, patrol: PackedVector2Array, bounty?: bool}]
##             (bounty only on hostile NPCs: killing every bounty wins the play-test)
##             guard?: bool, guard_dir?: float degrees (0 = east, 90 = south): stands and faces that way
##   openings: [{kind: "door"|"window", pos, rot, width, thick}]   (sit in a wall; the wall is cut open there)
##   roofs:    [{type (key of ROOFS), points: PackedVector2Array}]   (drawn above everything)
## NOTE: packed arrays are never mutated in place, only replaced, so undo snapshots stay valid.

const MAP_DIR := "user://maps"
const DEFAULT_PATH := "user://maps/current.json"
const DEFAULT_SIZE := Vector2(2048, 1728)

## The map shared between the menu, editor and game screens.
static var working: Dictionary = {}
static var current_path: String = DEFAULT_PATH
static var _tex_cache: Dictionary = {}

## Multiplier for the automatic drop shadows (props, walls, roofs, doors, rails). 1.0 = default look.
static var shadow_strength: float = 1.0
const SHADOW_MAX := 2.5


## Black drop-shadow colour with the given base alpha, scaled by shadow_strength.
static func shadow_color(alpha: float) -> Color:
	return Color(0, 0, 0, clampf(alpha * shadow_strength, 0.0, 1.0))


## Roof coverings for the roof layer. Same fields as TERRAIN (get_texture reads either table),
## kept separate so they don't show up in the terrain dropdown.
static var ROOFS: Dictionary = {
	"roof_shingle": {"label": "Wood shingles", "a": Color("5e3f27"), "b": Color("84603c"), "freq": 0.06, "outline": Color(0.08, 0.05, 0.03, 0.9), "planks": false, "plank_w": 16, "vertical": false, "speckle": 0.02},
	"roof_shake_dark": {"label": "Dark shakes", "a": Color("33271d"), "b": Color("4d3b2b"), "freq": 0.07, "outline": Color(0.04, 0.03, 0.02, 0.9), "planks": false, "plank_w": 16, "vertical": false, "speckle": 0.03},
	"roof_tile_red": {"label": "Red clay tiles", "a": Color("9a4a33"), "b": Color("c26a47"), "freq": 0.05, "outline": Color(0.25, 0.08, 0.05, 0.9), "planks": false, "plank_w": 32, "vertical": true, "speckle": 0.02},
	# Barrel (Spanish) clay tiles: rows of half-round tiles, see get_texture's "barrel_tile" pattern.
	"roof_barrel_red": {"label": "Barrel tiles: crimson", "a": Color("7e1826"), "b": Color("a82838"), "freq": 0.05, "outline": Color(0.22, 0.03, 0.06, 0.95), "planks": false, "barrel_tile": 16, "course": 16, "speckle": 0.0},
	"roof_barrel_terracotta": {"label": "Barrel tiles: terracotta", "a": Color("a24c28"), "b": Color("cc723a"), "freq": 0.05, "outline": Color(0.28, 0.1, 0.04, 0.95), "planks": false, "barrel_tile": 16, "course": 16, "speckle": 0.0},
	"roof_slate": {"label": "Grey slate", "a": Color("4d535c"), "b": Color("737b86"), "freq": 0.06, "outline": Color(0.07, 0.08, 0.1, 0.9), "planks": false, "plank_w": 16, "vertical": false, "speckle": 0.03},
	"roof_thatch": {"label": "Thatch", "a": Color("8a7436"), "b": Color("b8a054"), "freq": 0.12, "outline": Color(0.2, 0.15, 0.05, 0.85), "planks": false, "speckle": 0.14},
	"roof_tin": {"label": "Corrugated tin", "a": Color("6f747a"), "b": Color("9aa0a8"), "freq": 0.04, "outline": Color(0.1, 0.11, 0.12, 0.9), "planks": false, "plank_w": 16, "vertical": true, "speckle": 0.02},
	"roof_train": {"label": "Train car roof (curved)", "shape": "round", "a": Color("3f444c"), "b": Color("5a606a"), "freq": 0.05, "outline": Color(0.05, 0.06, 0.07, 0.95), "planks": false, "plank_w": 32, "vertical": true, "speckle": 0.04},
	"roof_canvas": {"label": "Wagon canvas (ribbed)", "shape": "round", "a": Color("cdbf9c"), "b": Color("e6dbbd"), "freq": 0.08, "outline": Color(0.38, 0.3, 0.18, 0.9), "planks": false, "ribs": 2, "speckle": 0.0},
	"roof_canvas_dark": {"label": "Weathered canvas (ribbed)", "shape": "round", "a": Color("8d826a"), "b": Color("b0a587"), "freq": 0.09, "outline": Color(0.2, 0.17, 0.1, 0.9), "planks": false, "ribs": 2, "speckle": 0.04},
	"roof_canvas_blue": {"label": "Blue wagon tarp (curved)", "shape": "round", "a": Color("4c6b92"), "b": Color("7193bd"), "freq": 0.08, "outline": Color(0.12, 0.18, 0.3, 0.9), "planks": false, "ribs": 2, "speckle": 0.0},
	"roof_sod": {"label": "Sod / turf", "a": Color("4a6024"), "b": Color("74893a"), "freq": 0.05, "outline": Color(0.1, 0.15, 0.05, 0.85), "planks": false, "speckle": 0.08},
	# Chimney top: draw a small rectangle. "fit" stretches the texture over the roof's bounding box
	# (instead of tiling it in world space) so the border and dark opening always line up.
	"roof_chimney": {"label": "Chimney top", "shape": "flat", "fit": true, "chimney": 0.22, "a": Color("2e2e30"), "b": Color("4a4a4d"), "freq": 0.08, "outline": Color(0.05, 0.05, 0.06, 0.95), "planks": false, "speckle": 0.03},
	"roof_scale_orange": {"label": "Fish-scale tiles: orange", "a": Color("b8501f"), "b": Color("e88a45"), "freq": 0.05, "outline": Color(0.28, 0.1, 0.04, 0.95), "planks": false, "scale": 16, "speckle": 0.0},
	"roof_scale_slate": {"label": "Fish-scale slate: dark", "a": Color("2c2c2e"), "b": Color("4d4c4a"), "freq": 0.06, "outline": Color(0.04, 0.04, 0.04, 0.95), "planks": false, "scale": 32, "speckle": 0.02},
	"roof_scale_brown": {"label": "Fish-scale shingles: brown", "a": Color("4a3326"), "b": Color("7a5a40"), "freq": 0.06, "outline": Color(0.08, 0.05, 0.03, 0.95), "planks": false, "scale": 16, "speckle": 0.02},
	"roof_barrel_mossy": {"label": "Barrel tiles: mossy", "a": Color("a24c28"), "b": Color("cc723a"), "freq": 0.04, "outline": Color(0.2, 0.1, 0.05, 0.95), "planks": false, "barrel_tile": 16, "course": 16, "moss": Color("6f9a82"), "moss_t": 0.55, "speckle": 0.0},
	"roof_barrel_rustic": {"label": "Barrel tiles: rustic brown (small)", "a": Color("5a3b2a"), "b": Color("8e6a48"), "freq": 0.07, "outline": Color(0.1, 0.06, 0.04, 0.95), "planks": false, "barrel_tile": 8, "course": 16, "speckle": 0.03},
	"roof_barrel_large": {"label": "Barrel tiles: plum", "a": Color("7a3a3c"), "b": Color("b0705a"), "freq": 0.04, "outline": Color(0.2, 0.07, 0.08, 0.95), "planks": false, "barrel_tile": 16, "course": 16, "speckle": 0.0},
	"roof_tile_patched": {"label": "Red tiles: patched", "a": Color("8c3a2c"), "b": Color("b8604a"), "freq": 0.06, "outline": Color(0.22, 0.07, 0.05, 0.9), "planks": false, "plank_w": 16, "vertical": false, "patch": 0.14, "speckle": 0.03},
	"roof_shake_grey": {"label": "Weathered grey shakes", "a": Color("6a6d70"), "b": Color("a4a8aa"), "freq": 0.08, "outline": Color(0.1, 0.1, 0.11, 0.9), "planks": false, "plank_w": 8, "vertical": false, "speckle": 0.04},
	"roof_shake_tan": {"label": "Tan cedar shakes", "a": Color("8a7650"), "b": Color("c2ab78"), "freq": 0.08, "outline": Color(0.2, 0.15, 0.08, 0.9), "planks": false, "plank_w": 8, "vertical": false, "speckle": 0.03},
	"roof_shingle_fine_brown": {"label": "Fine brown shingles", "a": Color("3e2a1c"), "b": Color("6c4a30"), "freq": 0.08, "outline": Color(0.06, 0.04, 0.02, 0.9), "planks": false, "plank_w": 8, "vertical": false, "speckle": 0.03},
	"roof_snow_slate": {"label": "Snowy slate", "a": Color("5c626b"), "b": Color("a9b1bb"), "freq": 0.035, "outline": Color(0.08, 0.09, 0.11, 0.9), "planks": false, "plank_w": 16, "vertical": false, "speckle": 0.04},
	"roof_snow": {"label": "Snow-covered", "a": Color("c4ccd6"), "b": Color("f2f5f9"), "freq": 0.03, "outline": Color(0.35, 0.4, 0.48, 0.85), "planks": false, "plank_w": 32, "vertical": true, "speckle": 0.02},
	"roof_straw_gold": {"label": "Golden straw thatch", "a": Color("a8873c"), "b": Color("d9b95e"), "freq": 0.14, "outline": Color(0.28, 0.2, 0.06, 0.85), "planks": false, "speckle": 0.16},
	"roof_shingle_grey": {"label": "Weathered grey shingles", "a": Color("45423e"), "b": Color("6b675f"), "freq": 0.07, "outline": Color(0.05, 0.05, 0.04, 0.9), "planks": false, "plank_w": 16, "vertical": false, "speckle": 0.03},
	"roof_copper": {"label": "Weathered copper", "a": Color("3f7a68"), "b": Color("6fb09a"), "freq": 0.05, "outline": Color(0.08, 0.2, 0.17, 0.9), "planks": false, "plank_w": 32, "vertical": true, "speckle": 0.03},
	"roof_tile_brown": {"label": "Brown clay tiles", "a": Color("5b3a2a"), "b": Color("84563b"), "freq": 0.05, "outline": Color(0.12, 0.06, 0.04, 0.9), "planks": false, "plank_w": 32, "vertical": true, "speckle": 0.02},
}

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
	"dock_vertical": {"label": "Wood: weathered dock (vertical)", "a": Color("6b5638"), "b": Color("8f7852"), "freq": 0.05, "outline": Color(0.1, 0.08, 0.06, 0.8), "blocks_scatter": true, "planks": false, "plank_w": 16, "vertical": true, "cracks": true, "speckle": 0.01},
	"driftwood": {"label": "Wood: bleached driftwood", "a": Color("9a8f80"), "b": Color("c0b6a2"), "freq": 0.05, "outline": Color(0.2, 0.18, 0.15, 0.7), "blocks_scatter": true, "planks": false, "plank_w": 32, "vertical": true, "speckle": 0.01},
	# --- stone and plaster ---
	"stone_pebbles": {"label": "Stone: river pebbles", "a": Color("3c3b38"), "b": Color("a9a69e"), "freq": 0.06, "outline": Color(0, 0, 0, 0), "blocks_scatter": true, "planks": false, "speckle": 0.02, "stones": {"grid": 24, "ar": 1.15, "grout": 1.0, "round": 3.0}, "tones": [Color("8d8b86"), Color("a5a29a"), Color("75736e"), Color("b3aea3"), Color("6a6963"), Color("968f84")]},
	"stone_rough": {"label": "Stone: rough fieldstone", "a": Color("3a312c"), "b": Color("a58f80"), "freq": 0.07, "outline": Color(0, 0, 0, 0), "blocks_scatter": true, "planks": false, "speckle": 0.02, "stones": {"grid": 16, "ar": 1.0, "grout": 1.5, "round": 1.5}, "tones": [Color("8e8179"), Color("a4917f"), Color("7c716b"), Color("b09c8c"), Color("9a8a82"), Color("85796f")]},
	"stone_limestone": {"label": "Stone: pale limestone", "a": Color("55534c"), "b": Color("d8d5cb"), "freq": 0.07, "outline": Color(0, 0, 0, 0), "blocks_scatter": true, "planks": false, "speckle": 0.03, "stones": {"grid": 18, "ar": 1.2, "grout": 1.2, "round": 2.0}, "tones": [Color("c9c6bb"), Color("b8b5a9"), Color("d9d7cd"), Color("aaa79c"), Color("c2bfb2")]},
	"stone_fieldstone": {"label": "Stone: rounded fieldstone", "a": Color("2c2924"), "b": Color("8a7a5a"), "freq": 0.06, "outline": Color(0, 0, 0, 0), "blocks_scatter": true, "planks": false, "speckle": 0.02, "stones": {"grid": 16, "ar": 1.6, "grout": 1.5, "round": 4.0}, "tones": [Color("7d6c4f"), Color("5f5c54"), Color("8f7e5c"), Color("6b6e6e"), Color("98835e"), Color("746955")]},
	"stone_slate_stack": {"label": "Stone: stacked slate", "a": Color("2a2a2c"), "b": Color("b0a79a"), "freq": 0.08, "outline": Color(0, 0, 0, 0), "blocks_scatter": true, "planks": false, "speckle": 0.02, "courses": {"rows": [12, 8, 16, 10, 14, 8, 12, 10, 14, 8, 16, 12, 8, 16, 10, 14, 8, 12, 10, 14, 8, 16], "min": 20, "max": 48}, "tones": [Color("5c616a"), Color("8b6a4c"), Color("a07850"), Color("70757d"), Color("b0a79a"), Color("4a4f58"), Color("9a6f48")]},
	"stucco_red": {"label": "Plaster: red stucco", "a": Color("8a4a42"), "b": Color("b06a5e"), "freq": 0.22, "outline": Color(0, 0, 0, 0), "blocks_scatter": true, "planks": false, "speckle": 0.0, "stucco": 1.6},
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
	# --- covered wagon / trail theme ---
	"trail_dust": {"label": "Trail dust", "a": Color("847a6a"), "b": Color("a39883"), "freq": 0.025, "outline": Color(0, 0, 0, 0), "blocks_scatter": false, "planks": false, "speckle": 0.09},
	"wagon_ruts": {"label": "Wagon ruts (packed dirt)", "a": Color("6b5c45"), "b": Color("88785a"), "freq": 0.06, "outline": Color(0, 0, 0, 0), "blocks_scatter": true, "planks": false, "speckle": 0.1},
	"wagon_boards": {"label": "Wagon: floor boards", "a": Color("6e4727"), "b": Color("93673b"), "freq": 0.04, "outline": Color(0.09, 0.05, 0.02, 0.9), "blocks_scatter": true, "planks": false, "plank_w": 16, "vertical": true, "speckle": 0.01},
	"wagon_rug": {"label": "Wagon: green rug", "a": Color("2c5446"), "b": Color("3d6f5d"), "freq": 0.07, "outline": Color(0.8, 0.65, 0.3, 0.9), "blocks_scatter": true, "planks": false, "speckle": 0.0},
}

## Each theme is a palette for the editor plus default ground/ambient for new maps.
## Theme "all" is only a palette filter in the editor (shows everything).
static var THEMES: Dictionary = {
	"fantasy": {
		"label": "Forest / Manor",
		"background": "grass",
		"ambient": Color(0.62, 0.64, 0.72),
		"terrain": ["grass", "grass_dark", "dirt", "stone", "wood", "wood_planks_dark", "wood_worn", "wood_planks_light", "wood_deck", "wood_braced", "wood_vertical", "canvas_red", "dark", "carpet", "water", "shadow", "moss", "blood"],
		"props": ["weapon", "tree", "bush", "rock", "barrel", "crate", "table", "well", "torch", "fireplace"],
	},
	"train": {
		"label": "Train / Rail yard",
		"background": "rail_dirt",
		"ambient": Color(0.84, 0.82, 0.82),
		"terrain": ["rail_dirt", "gravel", "grass", "grass_dark", "cliff", "river", "train_wood", "wood_planks_dark", "wood_deck", "wood_braced", "train_black", "train_blue", "train_red", "steel", "shadow", "blood"],
		"props": ["weapon", "locomotive", "coal_car", "smoke", "bench", "window", "crate", "barrel", "torch", "tree", "bush", "rock"],
	},
	"desert": {
		"label": "Desert ruins",
		"background": "sand",
		"ambient": Color(0.95, 0.88, 0.76),
		"terrain": ["sand", "sand_dune", "sandstone", "ruin_tile", "oasis", "stone", "dark", "wood_planks_light", "driftwood", "canvas_red", "shadow"],
		"props": ["weapon", "cactus", "palm", "pillar", "broken_pillar", "rubble", "rock", "crate", "barrel", "table", "torch"],
		"scatter": ["cactus", "rock", "rubble"],
	},
	"snow": {
		"label": "Snow / Winter",
		"background": "snow",
		"ambient": Color(0.72, 0.8, 0.95),
		"terrain": ["snow", "snow_deep", "ice", "frozen_dirt", "icy_water", "wood", "wood_planks_dark", "wood_worn", "wood_planks_light", "wood_deck", "stone", "shadow"],
		"props": ["weapon", "pine", "snowdrift", "snowman", "campfire", "stump", "rock", "crate", "barrel", "table", "torch"],
		"scatter": ["pine", "rock", "snowdrift"],
	},
	"town": {
		"label": "Town / Village",
		"background": "grass",
		"ambient": Color(0.86, 0.86, 0.9),
		"terrain": ["grass", "grass_dark", "dirt", "cobble", "plaza", "wood", "wood_planks_dark", "wood_worn", "wood_planks_light", "wood_deck", "wood_braced", "wood_vertical", "dock_weathered", "dock_vertical", "canvas_red", "stone", "carpet", "water", "shadow"],
		"props": ["weapon", "stall", "fountain", "lamppost", "cart", "haybale", "well", "tree", "bush", "barrel", "crate", "table", "torch", "fireplace", "rock"],
		"scatter": ["tree", "rock", "bush"],
	},
	"coast": {
		"label": "Coast / Harbor",
		"background": "ocean",
		"ambient": Color(0.82, 0.86, 0.95),
		"terrain": ["ocean", "lagoon", "sand", "cliff", "stone", "plaza", "wood", "dark", "sewer", "deck_ship", "dock_weathered", "dock_vertical", "driftwood", "wood_vertical", "canvas_red", "shadow"],
		"props": ["weapon", "palm", "rock", "crate", "barrel", "table", "lamppost", "torch", "bush"],
		"scatter": ["rock", "palm"],
	},
	"swamp": {
		"label": "Swamp",
		"background": "mud",
		"ambient": Color(0.56, 0.68, 0.62),
		"terrain": ["mud", "swamp_grass", "bog", "algae", "mist", "moss", "wood", "wood_planks_dark", "wood_worn", "wood_deck", "dock_weathered", "dock_vertical", "driftwood", "dirt", "shadow", "blood"],
		"props": ["weapon", "dead_tree", "reeds", "lilypad", "mushroom", "stump", "rock", "bush", "crate", "barrel", "torch"],
		"scatter": ["dead_tree", "stump", "reeds"],
	},
	# A wagon is built from parts: a "Wagon: floor boards" polygon for the bed, "Wagon side boards"
	# walls round it, wheel props on both sides, a hitch at the front and a curved canvas roof.
	"wagon": {
		"label": "Covered wagon / Trail",
		"background": "trail_dust",
		"ambient": Color(0.9, 0.86, 0.8),
		"terrain": ["trail_dust", "wagon_ruts", "grass", "grass_dark", "dirt", "mud", "wagon_boards", "wood_planks_dark", "wood_worn", "wagon_rug", "carpet", "canvas_red", "water", "shadow"],
		"props": ["weapon", "wagon_wheel", "wagon_hitch", "wagon_seat", "trunk", "bedroll", "sacks", "wagon_lantern", "barrel", "crate", "campfire", "haybale", "stump", "rock", "bush", "tree"],
		"scatter": ["tree", "rock", "bush"],
	},
}

const THEME_ORDER := ["fantasy", "train", "desert", "snow", "town", "swamp", "coast", "wagon", "all"]

## style -> [label, default width]
const WALL_STYLES := {
	"wall": ["Stone wall", 12.0],
	"hull": ["Train hull", 16.0],
	"rail": ["Rail track", 70.0],
	"wagon": ["Wagon side boards", 6.0],
}
const WALL_STYLE_ORDER := ["wall", "hull", "rail", "wagon"]

## radius = selection/footprint size, solid = collision radius (0 = walk-through)
static var PROPS: Dictionary = {
	"tree": {"defence": 0.30, "label": "Tree", "radius": 56.0, "solid": 8.0, "fade": true},
	"bush": {"defence": 0.25, "low": true, "label": "Bush", "radius": 26.0, "solid": 0.0},
	# rect = rectangular collision/shadow footprint (local, before rotation); fade = drawn above the player and fades when covering them
	"locomotive": {"defence": 0.90, "label": "Locomotive", "radius": 220.0, "solid": 0.0, "rect": Vector2(150, 430)},
	"coal_car": {"defence": 0.80, "label": "Coal tender", "radius": 100.0, "solid": 0.0, "rect": Vector2(190, 190)},
	"smoke": {"label": "Smoke (overhead)", "radius": 90.0, "solid": 0.0, "fade": true},
	"bench": {"defence": 0.30, "low": true, "label": "Train bench", "radius": 38.0, "solid": 0.0, "rect": Vector2(70, 28)},
	"window": {"label": "Window", "radius": 24.0, "solid": 0.0},
	"rock": {"defence": 0.60, "label": "Rock", "radius": 34.0, "solid": 28.0},
	"barrel": {"defence": 0.35, "low": true, "label": "Barrel", "radius": 14.0, "solid": 12.0},
	"crate": {"defence": 0.50, "low": true, "label": "Crate", "radius": 18.0, "solid": 16.0},
	"table": {"defence": 0.40, "low": true, "label": "Table", "radius": 40.0, "solid": 30.0},
	"well": {"defence": 0.70, "label": "Well", "radius": 36.0, "solid": 34.0},
	# light = {r: radius, c: color, e: energy}; props with it emit a flickering light
	"torch": {"label": "Torch (light)", "radius": 10.0, "solid": 0.0, "light": {"r": 240.0, "c": Color(1.0, 0.62, 0.3), "e": 1.1}},
	# A gun lying on the ground. Which one is the prop's "loot" value (a key in Weapons.PLAYER_CHOICES).
	# In play-test it glows and bobs; walking over it picks it up.
	"weapon": {"label": "Weapon pickup", "radius": 16.0, "solid": 0.0},
	# desert
	"cactus": {"label": "Cactus", "radius": 24.0, "solid": 10.0},
	"palm": {"defence": 0.25, "label": "Palm tree", "radius": 64.0, "solid": 8.0, "fade": true},
	"pillar": {"defence": 0.70, "label": "Stone pillar", "radius": 26.0, "solid": 21.0},
	"broken_pillar": {"defence": 0.50, "label": "Broken pillar", "radius": 24.0, "solid": 18.0},
	"rubble": {"defence": 0.35, "low": true, "label": "Rubble", "radius": 28.0, "solid": 0.0},
	# snow
	"pine": {"defence": 0.30, "label": "Pine tree", "radius": 52.0, "solid": 8.0, "fade": true},
	"snowdrift": {"defence": 0.30, "low": true, "label": "Snowdrift", "radius": 34.0, "solid": 0.0},
	"snowman": {"defence": 0.20, "label": "Snowman", "radius": 20.0, "solid": 14.0},
	"campfire": {"label": "Campfire (light)", "radius": 24.0, "solid": 0.0, "light": {"r": 300.0, "c": Color(1.0, 0.55, 0.2), "e": 1.2}},
	"stump": {"defence": 0.30, "low": true, "label": "Tree stump", "radius": 18.0, "solid": 14.0, "no_shadow": true},
	# Square stone hearth with a burning fire, as in the tavern floor plans. Low, so it gives some cover.
	"fireplace": {"defence": 0.40, "low": true, "label": "Fireplace (light)", "radius": 40.0, "solid": 0.0, "rect": Vector2(60, 60), "light": {"r": 340.0, "c": Color(1.0, 0.58, 0.24), "e": 1.3}},
	# town
	"stall": {"defence": 0.30, "label": "Market stall", "radius": 52.0, "solid": 0.0, "rect": Vector2(96, 64)},
	"fountain": {"defence": 0.70, "label": "Fountain", "radius": 52.0, "solid": 46.0},
	"lamppost": {"label": "Lamppost (light)", "radius": 12.0, "solid": 6.0, "light": {"r": 300.0, "c": Color(1.0, 0.85, 0.5), "e": 1.0}},
	"cart": {"defence": 0.40, "low": true, "label": "Cart", "radius": 46.0, "solid": 0.0, "rect": Vector2(84, 52)},
	"haybale": {"defence": 0.45, "low": true, "label": "Hay bale", "radius": 24.0, "solid": 18.0},
	# swamp
	"dead_tree": {"defence": 0.25, "label": "Dead tree", "radius": 48.0, "solid": 7.0, "fade": true},
	"reeds": {"label": "Reeds", "radius": 28.0, "solid": 0.0},
	"lilypad": {"label": "Lily pads", "radius": 24.0, "solid": 0.0},
	"mushroom": {"label": "Mushrooms", "radius": 16.0, "solid": 0.0},
	# covered wagon (parts are drawn with the wagon's length running along local y; hitch points to -y)
	"wagon_wheel": {"defence": 0.30, "label": "Wagon wheel (hub faces +x)", "radius": 24.0, "solid": 0.0, "rect": Vector2(10, 46)},
	"wagon_hitch": {"label": "Wagon hitch (tongue + crossbars)", "radius": 60.0, "solid": 0.0},
	"wagon_seat": {"label": "Wagon driver's seat", "radius": 34.0, "solid": 0.0},
	"trunk": {"defence": 0.45, "low": true, "label": "Travel trunk", "radius": 18.0, "solid": 0.0, "rect": Vector2(32, 22)},
	"bedroll": {"label": "Bedroll", "radius": 26.0, "solid": 0.0},
	"sacks": {"defence": 0.40, "low": true, "label": "Grain sacks", "radius": 18.0, "solid": 12.0},
	"wagon_lantern": {"label": "Wagon lantern (light)", "radius": 10.0, "solid": 0.0, "light": {"r": 230.0, "c": Color(1.0, 0.78, 0.45), "e": 1.0}},
}


## Defence score of a prop type: the chance (0..1) that a shot at someone crouching behind it
## is soaked up by the prop. 0 = no cover. Set with the "defence" key in PROPS.
static func prop_defence(kind: String) -> float:
	return float(PROPS.get(kind, {}).get("defence", 0.0))


## Radius (px, unscaled) of a round prop's body: how far from its centre cover starts.
## Rectangular props use PropNode.edge_distance() instead.
static func prop_body_radius(kind: String) -> float:
	var def: Dictionary = PROPS.get(kind, {})
	var solid := float(def.get("solid", 0.0))
	return solid if solid > 0.0 else float(def.get("radius", 20.0)) * 0.6


## NPC option lists (key -> label). Order is the dropdown order.
const NPC_WEAPONS := {
	"none": "Unarmed",
	"dagger": "Dagger",
	"sword": "Sword",
	"axe": "Axe",
	"spear": "Spear",
	"pistol": "Pistol",
	"shotgun": "Shotgun",
	"rifle": "Rifle",
	"flintlock": "Flintlock Rifle",
}
const NPC_LOOT := {
	"none": "Nothing",
	"gold": "Gold coins",
	"potion": "Potion",
	"food": "Food",
	"water": "Water",
	"gems": "Gems",
	"key": "Key",
	"dagger": "Dagger",
	"pistol": "Pistol",
	"shotgun": "Shotgun",
	"rifle": "Rifle",
	"flintlock": "Flintlock Rifle",
}
## Loot kinds from older maps that no longer exist -> what they become.
const LOOT_MIGRATE := {"ammo": "none", "weapon": "none"}


static func clean_loot(k: String) -> String:
	k = str(LOOT_MIGRATE.get(k, k))
	return k if NPC_LOOT.has(k) else "none"
const DEFAULT_NPC_HP := 40  # matches NpcNode.MAX_HP
const DEFAULT_NPC_SPEED := 4  # tiles an NPC can move in one action (matches the old 140 px)
const MAX_SPEED := 20
const MAX_ACTIONS := 5  # most actions an NPC / animal can take per combat turn (editor field)
const DEFAULT_NPC_XP := 10  # XP the player earns for killing an NPC (editor field)
const NPC_DISPOSITIONS := {
	"friendly": "Friendly",
	"hostile": "Hostile",
}


## Animal types (Animal tool). Each entry holds the defaults a new animal of that type starts with:
## hp, damage range (dmg_min..dmg_max per bite), aggro = how close (in tiles) the player can get
## before a hostile animal attacks, plus speed (px/s), size multiplier and body colour for drawing.
const ANIMALS := {
	"rat": {"move": 4, "xp": 2, "label": "Rat", "hp": 6, "dmg_min": 1, "dmg_max": 3, "aggro": 3.0, "speed": 85.0, "size": 0.6, "color": Color("6b4430")},
	"snake": {"move": 3, "xp": 4, "label": "Snake", "hp": 8, "dmg_min": 4, "dmg_max": 8, "aggro": 2.0, "speed": 70.0, "size": 0.8, "color": Color("c4622d")},
	"dog": {"move": 5, "xp": 5, "label": "Dog", "hp": 15, "dmg_min": 2, "dmg_max": 5, "aggro": 5.0, "speed": 105.0, "size": 0.8, "color": Color("a5764a")},
	"coyote": {"move": 5, "xp": 8, "label": "Coyote", "hp": 18, "dmg_min": 3, "dmg_max": 6, "aggro": 6.0, "speed": 115.0, "size": 0.85, "color": Color("b09060")},
	"wolf": {"move": 5, "xp": 15, "label": "Wolf", "hp": 30, "dmg_min": 5, "dmg_max": 10, "aggro": 8.0, "speed": 120.0, "size": 1.0, "color": Color("7d8189")},
	"bear": {"move": 4, "xp": 40, "label": "Bear", "hp": 80, "dmg_min": 10, "dmg_max": 20, "aggro": 5.0, "speed": 85.0, "size": 1.6, "color": Color("5a3d2b")},
}
## Body colour choices for snakes (key -> [label, colour]). The default is the original orange.
const SNAKE_COLORS := {
	"red": ["Red", Color("b02a22")],
	"orange": ["Orange", Color("c4622d")],
	"blue": ["Blue", Color("2f5fa8")],
	"green": ["Green", Color("4a8c3a")],
	"brown": ["Brown", Color("6b4a2b")],
	"black": ["Black", Color("26262a")],
}
const SNAKE_COLOR_DEFAULT := "orange"
const ANIMAL_DEFAULT := "wolf"
const ANIMAL_DISPOSITIONS := {
	"friendly": "Friendly",
	"hostile": "Hostile",
}


static func new_animal(species: String = ANIMAL_DEFAULT, pos: Vector2 = Vector2.ZERO, disposition: String = "hostile") -> Dictionary:
	if not ANIMALS.has(species):
		species = ANIMAL_DEFAULT
	var def: Dictionary = ANIMALS[species]
	return {"species": species, "pos": pos, "disposition": disposition, "hp": int(def["hp"]),
			"dmg_min": int(def["dmg_min"]), "dmg_max": int(def["dmg_max"]), "aggro": float(def["aggro"]), "xp": int(def["xp"]), "actions": 1, "speed": int(def["move"]),
			"color": SNAKE_COLOR_DEFAULT, "patrol": PackedVector2Array()}


## Wall openings: key -> [label, default width]
const OPENING_KINDS := {
	"door": ["Door", 48.0],
	"window": ["Window", 64.0],
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
		"npcs": [],
		"animals": [],
		"openings": [],
		"roofs": [],
	}


## A roof drawn above everything (see MapData.ROOFS). Hidden when the player is under it, and
## cut open along the line of sight through windows and open doors.
static func new_roof(type: String, pts: PackedVector2Array) -> Dictionary:
	return {"type": type, "points": pts}


static func new_poly(type: String, pts: PackedVector2Array) -> Dictionary:
	return {"type": type, "points": pts}


static func new_wall(pts: PackedVector2Array, closed: bool, width: float = 12.0, style: String = "wall") -> Dictionary:
	return {"points": pts, "closed": closed, "width": width, "style": style}


## Walls share the draw order of the terrain polygons. A wall's optional "under" key is how many
## polygons are drawn beneath it (0 = under all of them). Without it the wall is above every polygon.
static func wall_under(d: Dictionary, w: Dictionary) -> int:
	var n: int = d["polygons"].size()
	return clampi(int(w["under"]), 0, n) if w.has("under") else n


## The shared draw order, bottom first: [["polygon", index] or ["wall", index], ...].
static func terrain_sequence(d: Dictionary) -> Array:
	var seq: Array = []
	var n: int = d["polygons"].size()
	for i in n:
		for k in d["walls"].size():
			if wall_under(d, d["walls"][k]) == i:
				seq.append(["wall", k])
		seq.append(["polygon", i])
	for k in d["walls"].size():
		if wall_under(d, d["walls"][k]) >= n:
			seq.append(["wall", k])
	return seq


## Rewrites the polygon and wall lists (and each wall's "under") so they follow `seq`,
## a list in the same format terrain_sequence returns. Returns {"polygon": {old: new}, "wall": {old: new}}.
static func apply_terrain_sequence(d: Dictionary, seq: Array) -> Dictionary:
	var polys: Array = []
	var walls: Array = []
	var remap := {"polygon": {}, "wall": {}}
	var total: int = d["polygons"].size()
	for e in seq:
		if e[0] == "polygon":
			remap["polygon"][e[1]] = polys.size()
			polys.append(d["polygons"][e[1]])
		else:
			remap["wall"][e[1]] = walls.size()
			var w: Dictionary = d["walls"][e[1]]
			if polys.size() >= total:
				w.erase("under")  # above every polygon: the default
			else:
				w["under"] = polys.size()
			walls.append(w)
	d["polygons"] = polys
	d["walls"] = walls
	return remap


## A polygon was removed at `idx`: walls that sat above it keep their place in the draw order.
static func polygon_removed(d: Dictionary, idx: int) -> void:
	for w in d["walls"]:
		if w.has("under") and int(w["under"]) > idx:
			w["under"] = int(w["under"]) - 1


## Props that can hold loot (a key in NPC_LOOT). In play-test the player can select them;
## barrels can be shot apart and crates opened with E, which drops the loot.
const LOOT_PROPS := ["barrel", "crate", "trunk"]
## The weapon pickup prop keeps the gun it shows in its "loot" field.
const WEAPON_PROP := "weapon"


static func new_prop(type: String, pos: Vector2, scale: float = 1.0, rot: float = 0.0, seed_v: int = -1, loot: String = "none", locked: bool = false) -> Dictionary:
	if seed_v < 0:
		seed_v = randi()
	return {"type": type, "pos": pos, "scale": scale, "rot": rot, "seed": seed_v, "loot": loot, "locked": locked}


## Light settings of a "(light)" prop as {radius, color, energy, flicker}, or {} if it emits none.
## Starts from the type's defaults (radius scaled by the prop's scale); a "light" dictionary on the
## prop itself (set in the editor) overrides any of the four values.
static func prop_light(pr: Dictionary) -> Dictionary:
	var lt: Dictionary = PROPS.get(pr["type"], {}).get("light", {})
	if lt.is_empty():
		return {}
	var out := {"radius": float(lt["r"]) * float(pr["scale"]), "color": lt["c"], "energy": float(lt["e"]), "flicker": true, "npc_shadow": false}
	var ov: Dictionary = pr.get("light", {})
	for k in ov:
		out[k] = ov[k]
	return out


static func new_light(pos: Vector2, radius: float = 300.0, color: Color = Color(1, 0.75, 0.45), energy: float = 1.0, flicker: bool = true, npc_shadow: bool = false) -> Dictionary:
	return {"pos": pos, "radius": radius, "color": color, "energy": energy, "flicker": flicker, "npc_shadow": npc_shadow}


## patrol = closed area (3+ points) the NPC wanders inside; empty = stands still.
## A door or window set into a wall. rot = direction of the wall (radians), thick = wall width.
static func new_opening(kind: String, pos: Vector2, rot: float = 0.0, width: float = 48.0, thick: float = 12.0) -> Dictionary:
	return {"kind": kind, "pos": pos, "rot": rot, "width": width, "thick": thick}


## head = index into head_art.gd (hats, then hair styles); -1 = none.
static func new_npc(npc_name: String, pos: Vector2, weapon: String = "none", loot: String = "none", disposition: String = "friendly", patrol: PackedVector2Array = PackedVector2Array(), head: int = -1) -> Dictionary:
	return {"name": npc_name, "pos": pos, "weapon": weapon, "loot": loot, "disposition": disposition, "patrol": patrol, "head": head, "hp": DEFAULT_NPC_HP, "xp": DEFAULT_NPC_XP, "actions": 1, "speed": DEFAULT_NPC_SPEED}


# ---------------------------------------------------------------- textures

static func get_texture(type: String) -> Texture2D:
	if _tex_cache.has(type):
		return _tex_cache[type]
	var def: Dictionary = TERRAIN.get(type, ROOFS.get(type, TERRAIN["grass"]))
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
	var th := absi(type.hash()) % 10007
	# "stones": jittered-grid Voronoi cells (wrapping, so it tiles) drawn as separate stones with grout.
	var st: Dictionary = def.get("stones", {})
	var tones: Array = def.get("tones", [])
	var gn := 0
	var cell := 1.0
	var gpts := PackedVector2Array()
	if not st.is_empty():
		var prng := RandomNumberGenerator.new()
		prng.seed = type.hash()
		gn = int(st["grid"])
		cell = 256.0 / float(gn)
		for gy in gn:
			for gx in gn:
				gpts.append(Vector2((float(gx) + 0.5 + prng.randf_range(-0.38, 0.38)) * cell, (float(gy) + 0.5 + prng.randf_range(-0.38, 0.38)) * cell))
	# "courses": horizontal rows of blocks of random length (stacked slate / ledgestone).
	var crs: Dictionary = def.get("courses", {})
	var row_of := PackedInt32Array()
	var row_start := PackedInt32Array()
	var row_cuts: Array = []
	if not crs.is_empty():
		var prng2 := RandomNumberGenerator.new()
		prng2.seed = type.hash() + 1
		var yy := 0
		for ri in (crs["rows"] as Array).size():
			var rh: int = crs["rows"][ri]
			row_start.append(yy)
			for k in rh:
				row_of.append(ri)
			yy += rh
			var cuts := PackedInt32Array([0])
			var xx := 0
			while true:
				var bw := prng2.randi_range(int(crs["min"]), int(crs["max"]))
				if 256 - xx - bw < int(crs["min"]):
					cuts.append(256)
					break
				xx += bw
				cuts.append(xx)
			row_cuts.append(cuts)
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
			elif def.has("chimney"):
				# Chimney top: dark grey masonry rim around a black flue opening.
				var rim := int(256.0 * float(def["chimney"]))
				var edge_d := mini(mini(x, 255 - x), mini(y, 255 - y))  # distance to the nearest side
				if edge_d >= rim:
					c = Color(0.02, 0.02, 0.025, 1.0)
					if edge_d < rim + 6:
						c = Color(0.07, 0.07, 0.08, 1.0)  # soot-lit inner lip
				elif edge_d >= rim - 4:
					c = c.darkened(0.45)  # shadowed inner edge of the rim
				elif edge_d < 4:
					c = c.lightened(0.12)  # lit outer edge
			elif def.has("scale"):
				# Fish-scale shingles: rows of round-ended tiles, each row offset by half a tile.
				# Upper rows overlap the ones below, so a pixel belongs to its own row's scale if inside
				# that scale's circle, otherwise to the row beneath. scale = tile width (divides 128).
				var sw: int = def["scale"]
				var hh: int = sw / 2
				var rr := float(sw) * 0.5
				var row0: int = y / hh
				var found := false
				var dist := 0.0
				var s_col := 0
				var s_row := 0
				for k in 2:
					var rw: int = row0 + k
					var off: int = (rw % 2) * hh
					var ccx: int = int(roundf(float(x - off) / float(sw))) * sw + off
					var ddx := float(x - ccx)
					var ddy := float(y - rw * hh)
					var dd := sqrt(ddx * ddx + ddy * ddy)
					if dd <= rr:
						found = true
						dist = dd
						s_col = posmod(ccx / sw, 256 / sw)
						s_row = posmod(rw, 256 / hh)
						break
				if found:
					var stone := float(absi(s_col * 7919 + s_row * 104729 + type.hash()) % 17) / 17.0 - 0.5
					c = c.lightened(stone * 0.18) if stone > 0.0 else c.darkened(-stone * 0.25)
					c = c.darkened(0.35 * pow(dist / rr, 3.0))
					if dist > rr - 1.5:
						c = c.darkened(0.55)
				else:
					c = c.darkened(0.7)
			elif def.has("barrel_tile"):
				# Barrel (Spanish) clay tiles. Roofs map texture x along the eave and +y up the slope,
				# so tiles form columns up the texture; each course's rounded end bulges down-slope (-y)
				# over the course below and casts a shadow onto it. barrel_tile = tile width, course = length.
				var tw: int = def["barrel_tile"]
				var ch: int = def.get("course", tw)
				var tcol := x / tw
				var lx := x % tw
				var ly := y % ch
				var s := (float(lx) + 0.5) / float(tw) * 2.0 - 1.0  # -1..1 across the tile
				var edge := 1.0 + float(ch) * 0.32 * s * s  # rounded lower end of this course's tile
				var shaded := float(ly) < edge  # still on the tile below, under this one's overhang
				var course := posmod(y / ch - (1 if shaded else 0), 256 / ch)  # wraps so the texture tiles seamlessly
				var tone := float(absi(tcol * 7919 + course * 104729 + type.hash()) % 17) / 17.0 - 0.5
				c = c.lightened(tone * 0.16) if tone > 0.0 else c.darkened(-tone * 0.22)
				var k := sqrt(maxf(0.0, 1.0 - s * s))
				c = c.darkened(0.42 * (1.0 - k))  # half-round tile: sides curve away into shade
				if s > -0.6 and s < -0.2:
					c = c.lightened(0.2 * k)  # glint along the curve (light from the left)
				if shaded:
					c = c.darkened(0.55 - 0.25 * float(ly) / edge)  # shadow under the overlapping tile end
				elif float(ly) < edge + 1.5:
					c = c.darkened(0.3)  # dark lip of the tile end
				if lx == 0:
					c = c.darkened(0.6)  # gap between tile columns
			elif not st.is_empty():
				# Nearest and second-nearest stone centre (3x3 cells around, wrapping at the tile edge).
				var ar: float = st.get("ar", 1.0)
				var gx0 := int(float(x) / cell)
				var gy0 := int(float(y) / cell)
				var d1 := 1e9
				var d2 := 1e9
				var p1 := Vector2.ZERO
				var id1 := 0
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var cx := gx0 + ox
						var cy := gy0 + oy
						var wx := posmod(cx, gn)
						var wy := posmod(cy, gn)
						var p := gpts[wy * gn + wx] + Vector2(float(cx - wx), float(cy - wy)) * cell
						var dx := float(x) - p.x
						var dy := (float(y) - p.y) * ar
						var d := sqrt(dx * dx + dy * dy)
						if d < d1:
							d2 = d1
							d1 = d
							p1 = p
							id1 = wy * gn + wx
						elif d < d2:
							d2 = d
				var sh := float((id1 * 7919 + th) % 1013) / 1013.0  # per-stone random 0..1
				var base: Color = col_a.lerp(col_b, sh)
				if not tones.is_empty():
					base = (tones[(id1 * 31 + th) % tones.size()] as Color).lightened((sh - 0.5) * 0.2)
				c = base.lightened((v - 0.5) * 0.3)
				var edge := d2 - d1
				var gw: float = st["grout"]
				if edge < gw:
					c = col_a.darkened(0.7)  # grout between stones
				else:
					var k := clampf((edge - gw) / float(st["round"]), 0.0, 1.0)
					c = c.darkened(0.4 * (1.0 - k))  # rounded stone: sides fall away into shade
					var lit := clampf(Vector2(float(x) - p1.x, float(y) - p1.y).normalized().dot(Vector2(-0.7, -0.7)), 0.0, 1.0)
					c = c.lightened(0.14 * lit * k)  # light from the upper left
			elif not crs.is_empty():
				var ri2 := row_of[y]
				var ly := y - row_start[ri2]
				var rh2: int = crs["rows"][ri2]
				var cuts2: PackedInt32Array = row_cuts[ri2]
				var bk := 0
				while cuts2[bk + 1] <= x:
					bk += 1
				var lx := x - cuts2[bk]
				var tone2: Color = tones[(ri2 * 131 + bk * 17 + th) % tones.size()] if not tones.is_empty() else col_a
				c = tone2.lightened((v - 0.5) * 0.25)
				if ly < 1 or lx < 1:
					c = col_a.darkened(0.6)  # mortar line
				elif ly == 1:
					c = c.lightened(0.15)  # lit top edge of the block
				elif ly >= rh2 - 2:
					c = c.darkened(0.25)  # shaded lower edge
			elif def.has("stucco"):
				# Rough render: relief from the noise slope, lit from the upper left.
				var vn := clampf(src.get_pixel((x + 1) % 256, (y + 1) % 256).r, 0.0, 1.0)
				var slope := (v - vn) * float(def["stucco"])
				c = c.lightened(slope) if slope > 0.0 else c.darkened(-slope)
			elif planks:
				if y % 32 < 2:
					c = c.darkened(0.45)
				elif ((x + (y / 32) * 97) % 128) < 2:
					c = c.darkened(0.35)
			if def.has("patch"):
				# Dark repair patches / missing tiles: a random share of 32x16 cells (offset every other row).
				var prow := y / 16
				var pcol := (x + (prow % 2) * 16) / 32
				var ph := absi((pcol % 8) * 7919 + (prow % 16) * 104729 + type.hash()) % 100
				if float(ph) < float(def["patch"]) * 100.0:
					c = c.lerp(Color(0.1, 0.09, 0.08), 0.85)
			if def.has("moss"):
				# Patches of green moss / lichen, from the noise shifted so it differs from the base tone.
				var mv: float = src.get_pixel((x + 101) % 256, (y + 67) % 256).r
				if mv > float(def.get("moss_t", 0.58)):
					c = c.lerp(def["moss"], 0.7)
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
		"npcs": [],
		"animals": [],
		"openings": [],
		"roofs": [],
	}
	for r in d.get("roofs", []):
		out["roofs"].append({"type": r["type"], "points": _pack(r["points"])})
	for p in d["polygons"]:
		out["polygons"].append({"type": p["type"], "points": _pack(p["points"])})
	for w in d["walls"]:
		var wo := {"points": _pack(w["points"]), "closed": w["closed"], "width": w["width"], "style": w.get("style", "wall")}
		if w.has("under"):
			wo["under"] = int(w["under"])  # only written for walls placed below some polygon
		out["walls"].append(wo)
	for pr in d["props"]:
		var pos: Vector2 = pr["pos"]
		var po := {"type": pr["type"], "pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)], "scale": pr["scale"], "rot": pr["rot"], "seed": pr["seed"]}
		if str(pr.get("loot", "none")) != "none":
			po["loot"] = pr["loot"]  # only written when set, so ordinary props stay compact
		if bool(pr.get("locked", false)):
			po["locked"] = true
		if not is_equal_approx(float(pr.get("opacity", 1.0)), 1.0):
			po["opacity"] = snappedf(float(pr["opacity"]), 0.01)  # only written when changed
		if pr.has("light"):  # per-prop light override, only written when edited
			var pl: Dictionary = pr["light"]
			po["light"] = {"radius": pl["radius"], "color": (pl["color"] as Color).to_html(false), "energy": pl["energy"], "flicker": pl["flicker"], "npc_shadow": bool(pl.get("npc_shadow", false))}
		out["props"].append(po)
	for l in d["lights"]:
		var lp: Vector2 = l["pos"]
		var lc: Color = l["color"]
		var lo := {"pos": [lp.x, lp.y], "radius": l["radius"], "color": lc.to_html(false), "energy": l["energy"], "flicker": l["flicker"]}
		if bool(l.get("npc_shadow", false)):
			lo["npc_shadow"] = true  # only written when on
		out["lights"].append(lo)
	for n in d.get("npcs", []):
		var np: Vector2 = n["pos"]
		var no := {"name": n["name"], "pos": [snappedf(np.x, 0.01), snappedf(np.y, 0.01)], "weapon": n["weapon"], "loot": n["loot"], "disposition": n["disposition"], "patrol": _pack(n["patrol"]), "head": n.get("head", -1)}
		if int(n.get("hp", DEFAULT_NPC_HP)) != DEFAULT_NPC_HP:
			no["hp"] = int(n["hp"])  # only written when changed from the default
		if int(n.get("speed", DEFAULT_NPC_SPEED)) != DEFAULT_NPC_SPEED:
			no["speed"] = int(n["speed"])  # only written when changed from the default
		if int(n.get("actions", 1)) != 1:
			no["actions"] = int(n["actions"])  # only written when changed from the default
		if int(n.get("xp", DEFAULT_NPC_XP)) != DEFAULT_NPC_XP:
			no["xp"] = int(n["xp"])  # only written when changed from the default
		if bool(n.get("bounty", false)):
			no["bounty"] = true  # only written when set
		if bool(n.get("call_help", false)):
			no["call_help"] = true  # only written when set
		if bool(n.get("guard", false)):
			no["guard"] = true  # only written when set
			no["guard_dir"] = snappedf(float(n.get("guard_dir", 90.0)), 0.1)
		out["npcs"].append(no)
	for a in d.get("animals", []):
		var ap: Vector2 = a["pos"]
		out["animals"].append({"species": a["species"], "pos": [snappedf(ap.x, 0.01), snappedf(ap.y, 0.01)], "disposition": a["disposition"],
				"hp": int(a["hp"]), "xp": int(a.get("xp", 0)), "actions": int(a.get("actions", 1)), "speed": int(a.get("speed", ANIMALS.get(str(a["species"]), ANIMALS[ANIMAL_DEFAULT])["move"])), "dmg_min": int(a["dmg_min"]), "dmg_max": int(a["dmg_max"]), "aggro": snappedf(float(a["aggro"]), 0.1),
				"color": str(a.get("color", SNAKE_COLOR_DEFAULT)),
				"patrol": _pack(a.get("patrol", PackedVector2Array()))})
	for o in d.get("openings", []):
		var op: Vector2 = o["pos"]
		out["openings"].append({"kind": o["kind"], "pos": [snappedf(op.x, 0.01), snappedf(op.y, 0.01)], "rot": snappedf(float(o["rot"]), 0.0001), "width": o["width"], "thick": o["thick"]})
	# Editor groups: "group" id (> 0) on any object, only written when set.
	for key in GROUPABLE:
		var src: Array = d.get(key, [])
		var dst: Array = out[key]
		for i in mini(src.size(), dst.size()):
			var g := int(src[i].get("group", 0))
			if g > 0:
				dst[i]["group"] = g
	return out


## Object lists that can be grouped in the editor (each object may carry "group": int > 0).
const GROUPABLE := ["polygons", "roofs", "walls", "props", "lights", "npcs", "animals", "openings"]


## Reads "group" ids back onto loaded objects. `src` and `dst` must line up one to one.
static func _load_groups(src: Array, dst: Array) -> void:
	for i in mini(src.size(), dst.size()):
		var g := int(src[i].get("group", 0)) if src[i] is Dictionary else 0
		if g > 0:
			dst[i]["group"] = g


static func from_dict(j: Dictionary) -> Dictionary:
	var d := empty(str(j.get("theme", "fantasy")))
	d["size"] = _v2(j.get("size"), DEFAULT_SIZE)
	d["ambient"] = Color(str(j.get("ambient", "9fa3b8")))
	d["background"] = str(j.get("background", "grass"))
	d["spawn"] = _v2(j.get("spawn"), d["size"] * 0.5)
	for p in j.get("polygons", []):
		d["polygons"].append(new_poly(str(p.get("type", "grass")), _unpack(p.get("points", []))))
	for r in j.get("roofs", []):
		var rtype := str(r.get("type", "roof_shingle"))
		d["roofs"].append(new_roof(rtype if ROOFS.has(rtype) else "roof_shingle", _unpack(r.get("points", []))))
	for w in j.get("walls", []):
		d["walls"].append(new_wall(_unpack(w.get("points", [])), bool(w.get("closed", false)), float(w.get("width", 12.0)), str(w.get("style", "wall"))))
		if w.has("under"):
			d["walls"][d["walls"].size() - 1]["under"] = int(w["under"])
	for pr in j.get("props", []):
		if not PROPS.has(str(pr.get("type", "tree"))):
			continue  # prop type no longer exists (e.g. removed horses / cattle): drop it
		var ploot := str(pr.get("loot", "none"))
		d["props"].append(new_prop(str(pr.get("type", "tree")), _v2(pr.get("pos"), Vector2.ZERO), float(pr.get("scale", 1.0)), float(pr.get("rot", 0.0)), int(pr.get("seed", 0)),
				clean_loot(ploot), bool(pr.get("locked", false))))
		if pr.get("light") is Dictionary:
			var pl: Dictionary = pr["light"]
			d["props"][d["props"].size() - 1]["light"] = {"radius": float(pl.get("radius", 300.0)), "color": Color(str(pl.get("color", "ffbf73"))), "energy": float(pl.get("energy", 1.0)), "flicker": bool(pl.get("flicker", true)), "npc_shadow": bool(pl.get("npc_shadow", false))}
		if pr.has("opacity"):
			d["props"][d["props"].size() - 1]["opacity"] = clampf(float(pr["opacity"]), 0.0, 1.0)
		if int(pr.get("group", 0)) > 0:  # read here: skipped props would break a by-index match
			d["props"][d["props"].size() - 1]["group"] = int(pr["group"])
	for l in j.get("lights", []):
		d["lights"].append(new_light(_v2(l.get("pos"), Vector2.ZERO), float(l.get("radius", 300.0)), Color(str(l.get("color", "ffbf73"))), float(l.get("energy", 1.0)), bool(l.get("flicker", false)), bool(l.get("npc_shadow", false))))
	for n in j.get("npcs", []):
		var weapon := str(n.get("weapon", "none"))
		var loot := str(n.get("loot", "none"))
		var disp := str(n.get("disposition", "friendly"))
		d["npcs"].append(new_npc(str(n.get("name", "NPC")), _v2(n.get("pos"), Vector2.ZERO),
				weapon if NPC_WEAPONS.has(weapon) else "none",
				clean_loot(loot),
				disp if NPC_DISPOSITIONS.has(disp) else "friendly",
				_unpack(n.get("patrol", [])), int(n.get("head", -1))))
		d["npcs"][d["npcs"].size() - 1]["hp"] = clampi(int(n.get("hp", DEFAULT_NPC_HP)), 1, 9999)
		d["npcs"][d["npcs"].size() - 1]["xp"] = clampi(int(n.get("xp", DEFAULT_NPC_XP)), 0, 99999)
		d["npcs"][d["npcs"].size() - 1]["actions"] = clampi(int(n.get("actions", 1)), 1, MAX_ACTIONS)
		d["npcs"][d["npcs"].size() - 1]["speed"] = clampi(int(n.get("speed", DEFAULT_NPC_SPEED)), 0, MAX_SPEED)
		if bool(n.get("bounty", false)) and disp == "hostile":
			d["npcs"][d["npcs"].size() - 1]["bounty"] = true
		if bool(n.get("call_help", false)):
			d["npcs"][d["npcs"].size() - 1]["call_help"] = true
		if bool(n.get("guard", false)):
			d["npcs"][d["npcs"].size() - 1]["guard"] = true
			d["npcs"][d["npcs"].size() - 1]["guard_dir"] = fposmod(float(n.get("guard_dir", 90.0)), 360.0)
	for a in j.get("animals", []):
		var species := str(a.get("species", ANIMAL_DEFAULT))
		if not ANIMALS.has(species):
			species = ANIMAL_DEFAULT
		var adisp := str(a.get("disposition", "hostile"))
		var an := new_animal(species, _v2(a.get("pos"), Vector2.ZERO), adisp if ANIMAL_DISPOSITIONS.has(adisp) else "hostile")
		an["hp"] = clampi(int(a.get("hp", an["hp"])), 1, 9999)
		an["dmg_min"] = clampi(int(a.get("dmg_min", an["dmg_min"])), 0, 999)
		an["dmg_max"] = clampi(int(a.get("dmg_max", an["dmg_max"])), int(an["dmg_min"]), 999)
		an["xp"] = clampi(int(a.get("xp", an["xp"])), 0, 99999)
		an["actions"] = clampi(int(a.get("actions", 1)), 1, MAX_ACTIONS)
		an["speed"] = clampi(int(a.get("speed", an["speed"])), 0, MAX_SPEED)
		an["aggro"] = clampf(float(a.get("aggro", an["aggro"])), 0.0, 30.0)
		var acol := str(a.get("color", SNAKE_COLOR_DEFAULT))
		an["color"] = acol if SNAKE_COLORS.has(acol) else SNAKE_COLOR_DEFAULT
		an["patrol"] = _unpack(a.get("patrol", []))
		d["animals"].append(an)
	for o in j.get("openings", []):
		var kind := str(o.get("kind", "door"))
		if not OPENING_KINDS.has(kind):
			kind = "door"
		d["openings"].append(new_opening(kind, _v2(o.get("pos"), Vector2.ZERO), float(o.get("rot", 0.0)), float(o.get("width", OPENING_KINDS[kind][1])), float(o.get("thick", 12.0))))
	for key in GROUPABLE:
		if key != "props":
			_load_groups(j.get(key, []), d[key])
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
	var latest := _latest_map_path()
	if latest != "":
		current_path = latest
	working = load_map(current_path)
	if working.is_empty():
		working = SampleMap.create()


## The .json map in MAP_DIR that was modified most recently, or "" when there is none.
static func _latest_map_path() -> String:
	var best := ""
	var best_time := 0
	for file in DirAccess.get_files_at(MAP_DIR):
		if not file.ends_with(".json"):
			continue
		var path := MAP_DIR.path_join(file)
		var t := FileAccess.get_modified_time(path)
		if t > best_time:
			best_time = t
			best = path
	return best


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
