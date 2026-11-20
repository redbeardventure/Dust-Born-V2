extends RefCounted
## One list of "head" choices for the player: the hats first, then the hair styles.

const HatArt := preload("res://scripts/hat_art.gd")
const HairArt := preload("res://scripts/hair_art.gd")


static func count() -> int:
	return HatArt.count() + HairArt.count()


static func is_hat(idx: int) -> bool:
	return idx < HatArt.count()


static func style_name(idx: int) -> String:
	if is_hat(idx):
		return "Hat: %s" % HatArt.style_name(idx)
	return "Hair: %s" % HairArt.style_name(idx - HatArt.count())


## How far the head reaches toward the front; the face dot is drawn just inside this.
static func front(idx: int) -> float:
	if is_hat(idx):
		return HatArt.brim_front(idx)
	return HairArt.FRONT


static func draw(ci: CanvasItem, idx: int, pos: Vector2, angle: float, s: float = 1.0) -> void:
	if is_hat(idx):
		HatArt.draw(ci, idx, pos, angle, s)
	else:
		HairArt.draw(ci, idx - HatArt.count(), pos, angle, s)
