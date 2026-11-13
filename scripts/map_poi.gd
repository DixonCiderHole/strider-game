extends Node3D
## A place shown on the pause-menu MAP: an icon, a name and a line of info.
## Add with MapPoi.add(parent, position, "Name", "kind", "What it's for").
##
## Kinds (colour and icon on the map):
##   camp       your shelter and its stations
##   exit       a way to another area
##   objective  where the story wants you to go
##   landmark   a named place worth knowing
##   resource   salvage, scrap and materials
##   danger     somewhere to be careful

var label := ""
var kind := "landmark"
var info := ""


static func add(parent: Node, pos: Vector3, label_text: String, kind_id: String, info_text: String) -> Node3D:
	var p := new()
	p.label = label_text
	p.kind = kind_id
	p.info = info_text
	p.position = pos
	parent.add_child(p)
	return p


func _ready() -> void:
	add_to_group("map_poi")


static func colour(kind_id: String) -> Color:
	match kind_id:
		"camp":
			return Color(0.95, 0.55, 0.2)
		"exit":
			return Color(0.45, 0.85, 1.0)
		"objective":
			return Color(1.0, 0.8, 0.25)
		"resource":
			return Color(0.6, 0.9, 0.5)
		"danger":
			return Color(1.0, 0.3, 0.25)
	return Color(0.85, 0.85, 0.9)
