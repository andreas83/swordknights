class_name Weight
extends RefCounted
## Who is standing on a surface, and who is in the way of one: the questions a
## plate and a lift both ask, answered once.
##
## A mechanism sees the prince through the Contact it is met with, and the
## foes through the tree's foe group, because a plate a Bastion stands on is
## pressed by him exactly as by the prince (docs/campaign.md, "Counterweights").
## Only a foe that `has_weight()` counts as standing, so a cat on a plate is a
## cat on a floor. A foe that is down is scenery, and stands on nothing.
##
## "Standing on" is feet on the surface's top edge, give or take
## `TOLERANCE`, with some of the body over it -- or, asked `centred`, with the
## middle of the feet over it. A plate is pressed by any foot on it; a lift
## counts as its rider only a body whose weight is over it, or a prince
## walking off its edge onto the landing would still be riding it with his
## heel. The tolerance is wider than a stone plate needs because a lift's
## surface moves two thirds of a pixel a frame, and the body it carries
## catches up with it a frame late.

## How far feet may be from the surface and still stand on it, in pixels.
const TOLERANCE := 2.0


## The prince stands on the surface `[x0, x1)` at height `top`.
static func prince_on(contact: Contact, top: float, x0: float, x1: float,
		centred := false) -> bool:
	if contact == null or not contact.alive or not contact.grounded:
		return false
	if absf(contact.feet.y - top) > TOLERANCE:
		return false
	return _over(contact.body, x0, x1, centred)


## A live foe with weight stands on the surface `[x0, x1)` at height `top`.
static func foe_on(foe: Foe, top: float, x0: float, x1: float, centred := false) -> bool:
	if foe == null or not foe.is_alive() or not foe.has_weight():
		return false
	var body := foe.bounds()
	if absf(body.end.y - top) > TOLERANCE:
		return false
	return _over(body, x0, x1, centred)


static func _over(body: Rect2, x0: float, x1: float, centred: bool) -> bool:
	if centred:
		var middle := body.get_center().x
		return middle >= x0 and middle < x1
	return body.position.x < x1 and body.end.x > x0


## Every foe in `node`'s tree that is alive: the bodies a mechanism must not
## crush and may be weighed down by.
static func foes(node: Node) -> Array[Foe]:
	var out: Array[Foe] = []
	if node == null or not node.is_inside_tree():
		return out
	for member: Node in node.get_tree().get_nodes_in_group(Foe.GROUP):
		var foe := member as Foe
		if foe != null and foe.is_alive() and not foe.is_queued_for_deletion():
			out.append(foe)
	return out


## Anyone -- the prince or a live foe with weight -- stands on the surface.
static func anyone_on(node: Node, contact: Contact, top: float, x0: float,
		x1: float, centred := false) -> bool:
	if prince_on(contact, top, x0, x1, centred):
		return true
	for foe: Foe in foes(node):
		if foe_on(foe, top, x0, x1, centred):
			return true
	return false


## Every body a moving thing must not close on: the prince's (while he is
## alive) and every live foe's, whatever it weighs.
static func bodies(node: Node, contact: Contact) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if contact != null and contact.alive and contact.body.size != Vector2.ZERO:
		out.append(contact.body)
	for foe: Foe in foes(node):
		out.append(foe.bounds())
	return out
