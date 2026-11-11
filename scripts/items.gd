extends RefCounted
## Game data: items, recipes, skills and quests. No logic here.

## type: resource | consumable | ammo | weapon | tool | utility | module
## slot (for equipment): primary | sidearm | utility | module
const ITEMS := {
	# Resources
	"scrap":   {"name": "Metal Scrap", "type": "resource", "stack": 50, "color": Color(0.55, 0.57, 0.6), "tag": "SCR",
		"desc": "Twisted hull plating and brackets. Found in wreckage crates and debris."},
	"wood":    {"name": "Wood", "type": "resource", "stack": 50, "color": Color(0.55, 0.38, 0.22), "tag": "WD",
		"desc": "Branches and logs. Picked up off the ground, or chopped from trees with a hatchet."},
	"plastic": {"name": "Plastic", "type": "resource", "stack": 50, "color": Color(0.85, 0.85, 0.8), "tag": "PL",
		"desc": "Panels and casings scattered around wrecks."},
	"fiber":   {"name": "Fiber", "type": "resource", "stack": 50, "color": Color(0.5, 0.7, 0.3), "tag": "FB",
		"desc": "Tough plant fibre, stripped from bushes and ferns."},
	"ore":     {"name": "Ore", "type": "resource", "stack": 50, "color": Color(0.6, 0.35, 0.25), "tag": "ORE",
		"desc": "Raw metal ore. Loose stones on the ground, or mined from veins with a pick."},
	"tech":    {"name": "Tech Components", "type": "resource", "stack": 30, "color": Color(0.3, 0.7, 0.95), "tag": "TEC",
		"desc": "Circuit boards, wiring and power cells from supply crates."},
	# Consumables
	"bandage": {"name": "Bandage", "type": "consumable", "stack": 10, "color": Color(0.95, 0.95, 0.9), "tag": "BND",
		"heal": 30.0, "desc": "Restores 30 health. Quick use: H."},
	"stim":    {"name": "Medical Stim", "type": "consumable", "stack": 5, "color": Color(0.95, 0.3, 0.35), "tag": "STM",
		"heal": 80.0, "desc": "Restores 80 health instantly."},
	"ration":  {"name": "Military Ration", "type": "consumable", "stack": 10, "color": Color(0.6, 0.6, 0.35), "tag": "RTN",
		"heal": 15.0, "desc": "Sealed field ration. Restores 15 health. Found in supply crates."},
	# Ammo
	"cartridge": {"name": "Blaster Cartridge", "type": "ammo", "stack": 20, "color": Color(1.0, 0.55, 0.2), "tag": "AMO",
		"shots": 30, "desc": "Power cartridge for the blaster rifle: one full magazine (30 shots). Reload: R."},
	# Weapons
	"rifle":   {"name": "Blaster Rifle", "type": "weapon", "slot": "primary", "stack": 1, "color": Color(0.25, 0.25, 0.28), "tag": "RFL",
		"damage": 1.0, "rate": 0.16, "desc": "Standard-issue blaster rifle. Uses blaster cartridges."},
	"pistol":  {"name": "Blaster Pistol", "type": "weapon", "slot": "sidearm", "stack": 1, "color": Color(0.35, 0.3, 0.3), "tag": "PST",
		"damage": 0.6, "rate": 0.32, "desc": "Sidearm with a self-charging cell: never needs ammo, but weaker. Switch weapon: Q."},
	# Tools
	"hatchet": {"name": "Vibro-Hatchet", "type": "tool", "stack": 1, "color": Color(0.7, 0.45, 0.3), "tag": "HAT",
		"desc": "Lets you chop trees for wood (E at a tree)."},
	"pick":    {"name": "Mining Pick", "type": "tool", "stack": 1, "color": Color(0.5, 0.45, 0.5), "tag": "PCK",
		"desc": "Lets you mine glowing ore veins (E at a vein)."},
	# Utility
	"grenade": {"name": "Frag Grenade", "type": "utility", "slot": "utility", "stack": 5, "color": Color(0.35, 0.45, 0.3), "tag": "GRN",
		"damage": 70.0, "radius": 4.5, "desc": "Throw with G (uses the first utility slot)."},
	# Enhancement modules
	"mod_plating":   {"name": "Plating Module", "type": "module", "slot": "module", "stack": 1, "color": Color(0.45, 0.5, 0.55), "tag": "M-PL",
		"bonus": {"health": 25.0}, "desc": "+25 max health while equipped."},
	"mod_targeting": {"name": "Targeting Module", "type": "module", "slot": "module", "stack": 1, "color": Color(0.9, 0.3, 0.25), "tag": "M-TG",
		"bonus": {"damage": 0.15}, "desc": "+15% weapon damage while equipped."},
	"mod_servo":     {"name": "Servo Module", "type": "module", "slot": "module", "stack": 1, "color": Color(0.3, 0.75, 0.6), "tag": "M-SV",
		"bonus": {"speed": 0.1}, "desc": "+10% movement speed while equipped."},
	"mod_capacitor": {"name": "Capacitor Module", "type": "module", "slot": "module", "stack": 1, "color": Color(0.95, 0.8, 0.3), "tag": "M-CP",
		"bonus": {"mag": 10}, "desc": "+10 shots per magazine while equipped."},
}

## Crafting bench recipes. bench = bench level needed; skill = skill node needed.
const RECIPES := [
	{"id": "bandage", "out": "bandage", "count": 1, "in": {"fiber": 3}, "bench": 1},
	{"id": "cartridge", "out": "cartridge", "count": 1, "in": {"scrap": 2, "tech": 1}, "bench": 1},
	{"id": "hatchet", "out": "hatchet", "count": 1, "in": {"scrap": 3, "wood": 2, "tech": 1}, "bench": 1},
	{"id": "pick", "out": "pick", "count": 1, "in": {"scrap": 4, "wood": 2}, "bench": 1},
	{"id": "grenade", "out": "grenade", "count": 2, "in": {"scrap": 2, "ore": 1, "plastic": 1}, "bench": 2},
	{"id": "stim", "out": "stim", "count": 1, "in": {"bandage": 1, "tech": 1, "plastic": 2}, "bench": 2, "skill": "field_chem"},
	{"id": "pistol", "out": "pistol", "count": 1, "in": {"scrap": 4, "tech": 2, "plastic": 1}, "bench": 2},
	{"id": "mod_plating", "out": "mod_plating", "count": 1, "in": {"ore": 3, "scrap": 3, "tech": 1}, "bench": 2},
	{"id": "mod_targeting", "out": "mod_targeting", "count": 1, "in": {"tech": 3, "plastic": 2, "ore": 1}, "bench": 2, "skill": "modding"},
	{"id": "mod_servo", "out": "mod_servo", "count": 1, "in": {"tech": 2, "scrap": 3, "fiber": 2}, "bench": 2, "skill": "modding"},
	{"id": "mod_capacitor", "out": "mod_capacitor", "count": 1, "in": {"tech": 3, "ore": 2}, "bench": 2, "skill": "modding"},
]

## Crafting bench levels: cost to build (level 1) or upgrade.
const BENCH_LEVELS := {
	1: {"in": {"wood": 4, "scrap": 3}},
	2: {"in": {"scrap": 6, "tech": 3, "ore": 2}},
}

## Skill tree. One point per player level. ranks = how many times it can be taken.
const SKILLS := [
	# Combat
	{"id": "steady_aim", "branch": "COMBAT", "name": "Steady Aim", "ranks": 3, "desc": "+10% weapon damage per rank."},
	{"id": "quick_hands", "branch": "COMBAT", "name": "Quick Hands", "ranks": 1, "req": "steady_aim", "desc": "Reload 40% faster."},
	{"id": "extended_mag", "branch": "COMBAT", "name": "Extended Cells", "ranks": 2, "req": "quick_hands", "desc": "+5 shots per magazine per rank."},
	# Survival
	{"id": "tough", "branch": "SURVIVAL", "name": "Tough", "ranks": 3, "desc": "+15 max health per rank."},
	{"id": "field_medic", "branch": "SURVIVAL", "name": "Field Medic", "ranks": 1, "req": "tough", "desc": "Healing items restore 50% more."},
	{"id": "field_chem", "branch": "SURVIVAL", "name": "Field Chemistry", "ranks": 1, "req": "field_medic", "desc": "Unlocks the Medical Stim recipe."},
	# Crafting
	{"id": "tinkerer", "branch": "CRAFTING", "name": "Tinkerer", "ranks": 1, "desc": "Bench crafting gives double XP."},
	{"id": "efficient", "branch": "CRAFTING", "name": "Efficient Crafting", "ranks": 2, "req": "tinkerer", "desc": "15% chance per rank to craft a bonus item."},
	{"id": "modding", "branch": "CRAFTING", "name": "Modding", "ranks": 1, "req": "tinkerer", "desc": "Unlocks Targeting, Servo and Capacitor modules."},
	# Scavenging
	{"id": "scavenger", "branch": "SCAVENGING", "name": "Scavenger", "ranks": 2, "desc": "+1 resource from every pickup per rank."},
	{"id": "lucky", "branch": "SCAVENGING", "name": "Lucky Find", "ranks": 1, "req": "scavenger", "desc": "Crates contain an extra item."},
	{"id": "lumberjack", "branch": "SCAVENGING", "name": "Lumberjack", "ranks": 1, "req": "scavenger", "desc": "Chopping and mining give double."},
]
const BRANCHES := ["COMBAT", "SURVIVAL", "CRAFTING", "SCAVENGING"]

## Quest chain started at the camp. Objectives are checked by GameState.
const QUESTS := [
	{"title": "A Familiar Face", "goals": [["talk", "Talk to the survivor by the fire"]]},
	{"title": "Make Camp", "goals": [["have:wood:4", "Gather wood"], ["have:scrap:3", "Find metal scrap (crashed pod east of camp)"]]},
	{"title": "Workbench", "goals": [["bench:1", "Build a crafting bench in the cave"]]},
	{"title": "Patch Yourself Up", "goals": [["have:fiber:3", "Collect fiber from plants"], ["crafted:bandage", "Craft a bandage"]]},
	{"title": "Ammo Supply", "goals": [["have:tech:1", "Find tech components in supply crates"], ["crafted:cartridge", "Craft a blaster cartridge"]]},
	{"title": "Tools of the Trade", "goals": [["crafted:hatchet", "Craft a vibro-hatchet"], ["chopped", "Chop a tree"]]},
	{"title": "Level Up", "goals": [["spent_point", "Spend a skill point (Esc → SKILLS)"]]},
	{"title": "Upgrades", "goals": [["bench:2", "Upgrade the crafting bench"], ["equipped_module", "Craft and equip an enhancement module"]]},
]
const QUEST_XP := 40

## XP needed to reach the next level from `level`.
static func xp_for(level: int) -> int:
	return 60 + level * 40


## Supply crate loot: [item, min, max, chance]
const CRATE_LOOT := [
	["scrap", 2, 4, 0.9],
	["tech", 1, 2, 0.6],
	["plastic", 1, 3, 0.5],
	["ration", 1, 1, 0.45],
	["cartridge", 1, 2, 0.55],
	["ore", 1, 2, 0.25],
]
