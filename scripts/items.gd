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
	"glowcap": {"name": "Glowcap", "type": "resource", "stack": 30, "color": Color(0.6, 1.0, 0.4), "tag": "GLW",
		"desc": "A riverbank herb whose bulbs glow at dusk. Cooked down, the sap sets like resin: a field coagulant."},
	"medpack": {"name": "Pathfinder Med Pack", "type": "resource", "stack": 5, "color": Color(0.95, 0.5, 0.15), "tag": "MED",
		"desc": "Coalition pathfinder medical pack: sutures, dressings, antiseptic and a cracked rack of vials."},
	"tissue":  {"name": "Creature Tissue Sample", "type": "resource", "stack": 10, "color": Color(0.35, 0.8, 1.0), "tag": "TIS",
		"desc": "A sealed vial with a sliver of spine and muscle. It flinches from light, long after the creature is dead."},
	"crystal": {"name": "Spire Crystal", "type": "resource", "stack": 30, "color": Color(0.35, 0.85, 1.0), "tag": "CRY",
		"desc": "A shard of the glowing crystal that grows through the spires and the Vaari stones. Hums faintly. Mined from crystal clusters with a pick."},
	"tech":    {"name": "Tech Components", "type": "resource", "stack": 30, "color": Color(0.3, 0.7, 0.95), "tag": "TEC",
		"desc": "Circuit boards, wiring and power cells from supply crates."},
	# Consumables
	"bandage": {"name": "Bandage", "type": "consumable", "stack": 10, "color": Color(0.95, 0.95, 0.9), "tag": "BND",
		"heal": 30.0, "desc": "Restores 30 health. Quick use: H."},
	"stim":    {"name": "Medical Stim", "type": "consumable", "stack": 5, "color": Color(0.95, 0.3, 0.35), "tag": "STM",
		"heal": 80.0, "desc": "Restores 80 health instantly."},
	"coagulant": {"name": "Glowcap Coagulant", "type": "consumable", "stack": 10, "color": Color(0.55, 0.95, 0.5), "tag": "COA",
		"heal": 55.0, "desc": "Glowcap sap cooked down to a resin. Seals a wound fast. Restores 55 health."},
	"trauma_kit": {"name": "Trauma Kit", "type": "consumable", "stack": 5, "color": Color(0.95, 0.95, 0.95), "tag": "TRK",
		"heal": 120.0, "desc": "Coalition-pattern trauma kit: coagulant, sutures and a pressure dressing. Restores 120 health."},
	"antivenom": {"name": "Antivenom Shot", "type": "consumable", "stack": 5, "color": Color(0.4, 0.9, 0.85), "tag": "AVN",
		"heal": 45.0, "desc": "Her counter to the creatures' bite, made from what the tissue samples taught her. Restores 45 health."},
	"ration":  {"name": "Military Ration", "type": "consumable", "stack": 10, "color": Color(0.6, 0.6, 0.35), "tag": "RTN",
		"heal": 15.0, "desc": "Sealed field ration. Restores 15 health. Found in supply crates."},
	# Ammo
	"cartridge": {"name": "Blaster Cartridge", "type": "ammo", "stack": 20, "color": Color(1.0, 0.55, 0.2), "tag": "AMO",
		"shots": 30, "desc": "Power cartridge for blaster rifles: one full magazine (30 shots). Reload: R."},
	"heavy_cell": {"name": "Heavy Repeater Cell", "type": "ammo", "stack": 10, "color": Color(0.95, 0.25, 0.2), "tag": "HVC",
		"shots": 75, "desc": "Long drum cell for the Heavy Repeater: one full 75-round magazine. Reload: R."},
	"fuel":    {"name": "Fuel Canister", "type": "ammo", "stack": 10, "color": Color(1.0, 0.45, 0.1), "tag": "FUL",
		"shots": 100, "desc": "Pressurised canister of promethium gel for the flamethrower: one full tank. Found in wrecks, or made at the bench. Reload: R."},
	# Weapons
	"rifle":   {"name": "Blaster Rifle", "type": "weapon", "slot": "primary", "stack": 1, "color": Color(0.25, 0.25, 0.28), "tag": "RFL",
		"damage": 1.0, "rate": 0.16, "ammo": "cartridge", "mag": 30, "desc": "Standard-issue blaster rifle. 30-round magazine. Uses blaster cartridges."},
	"pistol":  {"name": "Blaster Pistol", "type": "weapon", "slot": "sidearm", "stack": 1, "color": Color(0.35, 0.3, 0.3), "tag": "PST",
		"damage": 0.6, "rate": 0.32, "desc": "Sidearm with a self-charging cell: never needs ammo, but weaker. Switch weapon: Q."},
	# New weapons (models/weapons/, Meshy). "model"/"len"/"grip"/"muzzle": see
	# player.gd _mount_weapons (grip and muzzle in model units, side view).
	"lmg":     {"name": "Heavy Repeater", "type": "weapon", "slot": "primary", "stack": 1, "color": Color(0.5, 0.15, 0.12), "tag": "LMG",
		"damage": 0.7, "rate": 0.085, "ammo": "heavy_cell", "mag": 75, "model": "res://models/weapons/lmg.glb", "len": 1.15,
		"grip": Vector2(0.6, -0.12), "muzzle": Vector2(-0.95, 0.07),
		"desc": "Twin-barrel light repeater. Heavy, loud, and it never stops. 75-round magazine. Uses heavy repeater cells."},
	"flamethrower": {"name": "Flamethrower", "type": "weapon", "slot": "primary", "stack": 1, "color": Color(0.9, 0.35, 0.1), "tag": "FLM",
		"damage": 0.3, "rate": 0.07, "flame": true, "ammo": "fuel", "mag": 100, "model": "res://models/weapons/flamethrower.glb", "len": 1.05,
		"grip": Vector2(0.62, -0.1), "muzzle": Vector2(-0.95, 0.02),
		"desc": "Throws burning gel about 20 m in an arc. Where it lands it keeps burning for a few seconds. The creatures hate fire. Uses fuel canisters (one tank = 100)."},
	"pistol_heavy": {"name": "Heavy Machine Pistol", "type": "weapon", "slot": "sidearm", "stack": 1, "color": Color(0.35, 0.33, 0.3), "tag": "HMP",
		"damage": 0.55, "rate": 0.2, "model": "res://models/weapons/pistol_heavy.glb", "len": 0.32,
		"grip": Vector2(0.8, -0.25), "muzzle": Vector2(-0.95, 0.27),
		"desc": "Chunky self-charging machine pistol. Fast, never needs ammo. Switch weapon: Q."},
	"pistol_long": {"name": "Long Blaster Pistol", "type": "weapon", "slot": "sidearm", "stack": 1, "color": Color(0.25, 0.25, 0.28), "tag": "LBP",
		"damage": 0.85, "rate": 0.38, "model": "res://models/weapons/pistol_long.glb", "len": 0.36,
		"grip": Vector2(0.78, -0.2), "muzzle": Vector2(-0.95, 0.3),
		"desc": "Long-barrelled, precise self-charging pistol. Slow and accurate. Switch weapon: Q."},
	# Strider droid parts (Spire Canyon side areas) and its arm attachments.
	"strider_legs_f": {"name": "Strider Front Legs", "type": "quest", "stack": 1, "color": Color(0.35, 0.6, 0.9), "tag": "LGF",
		"desc": "A Strider escort droid's front leg pair, servos still whole. Something dragged it a long way."},
	"strider_legs_b": {"name": "Strider Rear Legs", "type": "quest", "stack": 1, "color": Color(0.35, 0.6, 0.9), "tag": "LGB",
		"desc": "The droid's rear leg pair, frosted over but sound."},
	"strider_arm_l": {"name": "Strider Left Cannon", "type": "quest", "stack": 1, "color": Color(0.35, 0.6, 0.9), "tag": "CNL",
		"desc": "The droid's left weapon arm. Mud in the barrel; the coils test fine."},
	"strider_arm_r": {"name": "Strider Right Arm Mount", "type": "quest", "stack": 1, "color": Color(0.35, 0.6, 0.9), "tag": "CNR",
		"desc": "The droid's right weapon arm and its quick-change socket: it takes tool attachments as well as the cannon."},
	"saw_arm": {"name": "Plasma Saw Arm", "type": "droid_arm", "stack": 1, "color": Color(1.0, 0.45, 0.15), "tag": "SAW",
		"desc": "A heavy cutting arm for the Strider droid's right socket: a heated diamond-tooth blade that cuts hull plate. Fit it in the party menu. With it fitted, the droid fights up close."},
	"control_chip": {"name": "Drone Control Chip", "type": "resource", "stack": 1, "color": Color(0.9, 0.2, 0.2), "tag": "CHP",
		"desc": "A hand-built control chip to replace the burnt-out one in the drone from the freighter."},
	# Tools
	"hatchet": {"name": "Vibro-Hatchet", "type": "tool", "stack": 1, "color": Color(0.7, 0.45, 0.3), "tag": "HAT",
		"desc": "Lets you chop trees for wood (E at a tree)."},
	"pick":    {"name": "Mining Pick", "type": "tool", "stack": 1, "color": Color(0.5, 0.45, 0.5), "tag": "PCK",
		"desc": "Lets you mine glowing ore veins (E at a vein)."},
	# Utility
	"grenade": {"name": "Frag Grenade", "type": "utility", "slot": "utility", "stack": 5, "color": Color(0.35, 0.45, 0.3), "tag": "GRN",
		"damage": 70.0, "radius": 4.5, "desc": "Throw with G (uses the first utility slot)."},
	"flashbang": {"name": "Flashbang", "type": "utility", "slot": "utility", "stack": 5, "color": Color(0.9, 0.9, 0.95), "tag": "FLS",
		"effect": "flash", "damage": 0.0, "radius": 9.0, "desc": "Blinding flash and bang. Creatures caught in it stagger about, unable to attack, for 3 s. Throw with G."},
	"smoke_grenade": {"name": "Smoke Grenade", "type": "utility", "slot": "utility", "stack": 5, "color": Color(0.6, 0.62, 0.6), "tag": "SMK",
		"effect": "smoke", "damage": 0.0, "radius": 6.0, "desc": "Thick smoke for 8 s. Creatures inside it, or hunting someone inside it, lose track of their prey. Throw with G."},
	"stun_grenade": {"name": "Stun Grenade", "type": "utility", "slot": "utility", "stack": 5, "color": Color(0.35, 0.65, 1.0), "tag": "STN",
		"effect": "stun", "damage": 15.0, "radius": 6.0, "desc": "Electric burst: light damage and locks creatures in place for 2.5 s. Throw with G."},
	"thermal": {"name": "Thermal Detonator", "type": "utility", "slot": "utility", "stack": 3, "color": Color(0.85, 0.75, 0.6), "tag": "THD",
		"effect": "thermal", "damage": 190.0, "radius": 7.5, "desc": "Crystal-core thermal charge. A huge blast that leaves the ground burning. Throw with G."},
	# Enhancement modules
	"mod_plating":   {"name": "Plating Module", "type": "module", "slot": "module", "stack": 1, "color": Color(0.45, 0.5, 0.55), "tag": "M-PL",
		"bonus": {"health": 25.0}, "desc": "+25 max health while equipped."},
	"mod_targeting": {"name": "Targeting Module", "type": "module", "slot": "module", "stack": 1, "color": Color(0.9, 0.3, 0.25), "tag": "M-TG",
		"bonus": {"damage": 0.15}, "desc": "+15% weapon damage while equipped."},
	"mod_servo":     {"name": "Servo Module", "type": "module", "slot": "module", "stack": 1, "color": Color(0.3, 0.75, 0.6), "tag": "M-SV",
		"bonus": {"speed": 0.1}, "desc": "+10% movement speed while equipped."},
	"mod_capacitor": {"name": "Capacitor Module", "type": "module", "slot": "module", "stack": 1, "color": Color(0.95, 0.8, 0.3), "tag": "M-CP",
		"bonus": {"mag": 10}, "desc": "+10 shots per magazine while equipped."},
	"mod_nanite":    {"name": "Nanite Module", "type": "module", "slot": "module", "stack": 1, "color": Color(0.4, 0.95, 0.6), "tag": "M-NN",
		"bonus": {"regen": 1.5}, "desc": "+1.5 health/s regeneration (after 5 s without being hit) while equipped."},
	"mod_armor":     {"name": "Reactive Armour Module", "type": "module", "slot": "module", "stack": 1, "color": Color(0.55, 0.5, 0.45), "tag": "M-AR",
		"bonus": {"armor": 0.08}, "desc": "Take 8% less damage while equipped."},
	"mod_crit":      {"name": "Crystal Lens Module", "type": "module", "slot": "module", "stack": 1, "color": Color(0.35, 0.85, 1.0), "tag": "M-CL",
		"bonus": {"crit": 0.06, "damage": 0.08}, "desc": "+6% critical chance and +8% weapon damage while equipped. Needs spire crystal."},
	"mod_loader":    {"name": "Autoloader Module", "type": "module", "slot": "module", "stack": 1, "color": Color(0.9, 0.6, 0.25), "tag": "M-AL",
		"bonus": {"reload": 0.3}, "desc": "Reload 30% faster while equipped."},
	"mod_cooling":   {"name": "Cooling Module", "type": "module", "slot": "module", "stack": 1, "color": Color(0.5, 0.75, 0.95), "tag": "M-CO",
		"bonus": {"rate": 0.1}, "desc": "+10% fire rate while equipped."},
	# Only from Unrelenting Horde milestones (waves 5, 10, 15, 20).
	"mod_hordebreaker": {"name": "Hordebreaker Core", "type": "module", "slot": "module", "stack": 1, "color": Color(1.0, 0.35, 0.2), "tag": "M-HB",
		"bonus": {"damage": 0.15, "rate": 0.08}, "desc": "Horde exclusive. +15% weapon damage and +8% fire rate while equipped."},
	"mod_bulwark":     {"name": "Bulwark Matrix", "type": "module", "slot": "module", "stack": 1, "color": Color(0.85, 0.65, 0.3), "tag": "M-BW",
		"bonus": {"armor": 0.15, "regen": 2.0}, "desc": "Horde exclusive. Take 15% less damage and regenerate 2 health/s while equipped."},
	"mod_scavenger":   {"name": "Scavenger Lattice", "type": "module", "slot": "module", "stack": 1, "color": Color(0.6, 0.9, 0.4), "tag": "M-SV",
		"bonus": {"salvage": 0.25}, "desc": "Horde exclusive. +25% salvage from everything while equipped."},
	"mod_relentless":  {"name": "Relentless Heart", "type": "module", "slot": "module", "stack": 1, "color": Color(0.95, 0.2, 0.35), "tag": "M-RH",
		"bonus": {"damage": 0.12, "crit": 0.08, "reload": 0.2}, "desc": "Horde exclusive. +12% damage, +8% critical chance and 20% faster reloads while equipped."},
	# Placeable storage
	"crate_wood":  {"name": "Wooden Crate", "type": "placeable", "stack": 5, "slots": 10, "color": Color(0.5, 0.36, 0.22), "tag": "CRW",
		"desc": "Timber storage crate on a scrap-metal frame with a mag-lock. Holds 10 stacks. Use it from your backpack to place it at camp."},
	"crate_metal": {"name": "Metal Crate", "type": "placeable", "stack": 5, "slots": 20, "color": Color(0.32, 0.35, 0.4), "tag": "CRM",
		"desc": "Sealed alloy cargo container with a powered lock. Holds 20 stacks. Use it from your backpack to place it at camp."},
}

## Crafting menu categories, in tab order (recipes pick one with "cat").
const CRAFT_CATS := ["MEDICAL", "AMMO & GEAR", "GRENADES", "TOOLS", "MODULES", "STORAGE", "TEST WEAPONS"]

## Crafting bench recipes. bench = bench level needed; skill = skill node needed.
const RECIPES := [
	{"id": "bandage", "out": "bandage", "count": 1, "in": {"fiber": 3}, "bench": 1, "cat": "MEDICAL"},
	{"id": "coagulant", "out": "coagulant", "count": 1, "in": {"glowcap": 2, "fiber": 1}, "bench": 1, "cat": "MEDICAL"},
	{"id": "stim", "out": "stim", "count": 1, "in": {"bandage": 1, "tech": 1, "plastic": 2}, "bench": 2, "skill": "field_chem", "cat": "MEDICAL"},
	{"id": "cartridge", "out": "cartridge", "count": 1, "in": {"scrap": 2, "tech": 1}, "bench": 1, "cat": "AMMO & GEAR"},
	{"id": "trauma_kit", "out": "trauma_kit", "count": 1, "in": {"bandage": 2, "coagulant": 1, "plastic": 1}, "bench": 2, "skill": "pharmacology", "cat": "MEDICAL"},
	{"id": "antivenom", "out": "antivenom", "count": 2, "in": {"glowcap": 2, "tech": 1, "plastic": 1}, "bench": 2, "skill": "pharmacology", "cat": "MEDICAL"},
	{"id": "heavy_cell", "out": "heavy_cell", "count": 1, "in": {"scrap": 3, "tech": 1, "ore": 1}, "bench": 1, "cat": "AMMO & GEAR"},
	{"id": "fuel", "out": "fuel", "count": 1, "in": {"plastic": 2, "scrap": 1, "fiber": 2}, "bench": 1, "cat": "AMMO & GEAR"},
	{"id": "grenade", "out": "grenade", "count": 2, "in": {"scrap": 2, "ore": 1, "plastic": 1}, "bench": 2, "cat": "GRENADES"},
	{"id": "flashbang", "out": "flashbang", "count": 2, "in": {"scrap": 1, "plastic": 1, "tech": 1}, "bench": 2, "cat": "GRENADES"},
	{"id": "smoke_grenade", "out": "smoke_grenade", "count": 2, "in": {"fiber": 3, "plastic": 1, "scrap": 1}, "bench": 2, "cat": "GRENADES"},
	{"id": "stun_grenade", "out": "stun_grenade", "count": 2, "in": {"tech": 2, "scrap": 1, "ore": 1}, "bench": 2, "cat": "GRENADES"},
	{"id": "thermal", "out": "thermal", "count": 1, "in": {"ore": 2, "crystal": 1, "tech": 2, "scrap": 2}, "bench": 3, "cat": "GRENADES"},
	{"id": "pistol", "out": "pistol", "count": 1, "in": {"scrap": 4, "tech": 2, "plastic": 1}, "bench": 2, "cat": "AMMO & GEAR"},
	{"id": "hatchet", "out": "hatchet", "count": 1, "in": {"scrap": 3, "wood": 2, "tech": 1}, "bench": 1, "cat": "TOOLS"},
	{"id": "pick", "out": "pick", "count": 1, "in": {"scrap": 4, "wood": 2}, "bench": 1, "cat": "TOOLS"},
	{"id": "mod_plating", "out": "mod_plating", "count": 1, "in": {"ore": 3, "scrap": 3, "tech": 1}, "bench": 2, "cat": "MODULES"},
	{"id": "mod_targeting", "out": "mod_targeting", "count": 1, "in": {"tech": 3, "plastic": 2, "ore": 1}, "bench": 2, "skill": "modding", "cat": "MODULES"},
	{"id": "mod_servo", "out": "mod_servo", "count": 1, "in": {"tech": 2, "scrap": 3, "fiber": 2}, "bench": 2, "skill": "modding", "cat": "MODULES"},
	{"id": "mod_capacitor", "out": "mod_capacitor", "count": 1, "in": {"tech": 3, "ore": 2}, "bench": 2, "skill": "modding", "cat": "MODULES"},
	{"id": "mod_loader", "out": "mod_loader", "count": 1, "in": {"tech": 2, "scrap": 4, "ore": 1}, "bench": 2, "cat": "MODULES"},
	{"id": "mod_nanite", "out": "mod_nanite", "count": 1, "in": {"tech": 3, "glowcap": 2, "plastic": 2}, "bench": 3, "cat": "MODULES"},
	{"id": "mod_armor", "out": "mod_armor", "count": 1, "in": {"ore": 4, "scrap": 4, "tech": 2}, "bench": 3, "cat": "MODULES"},
	{"id": "mod_cooling", "out": "mod_cooling", "count": 1, "in": {"tech": 3, "plastic": 2, "crystal": 1}, "bench": 3, "skill": "modding", "cat": "MODULES"},
	{"id": "mod_crit", "out": "mod_crit", "count": 1, "in": {"crystal": 3, "tech": 2, "ore": 2}, "bench": 3, "skill": "modding", "cat": "MODULES"},
	{"id": "saw_arm", "out": "saw_arm", "count": 1, "in": {"scrap": 8, "ore": 4, "tech": 4, "crystal": 2}, "bench": 2, "needs": "droid_rebuilt", "cat": "TOOLS"},
	{"id": "control_chip", "out": "control_chip", "count": 1, "in": {"tech": 2, "scrap": 2, "plastic": 1}, "bench": 1, "cat": "AMMO & GEAR"},
	# Testing: every new weapon for 1 scrap.
	{"id": "lmg", "out": "lmg", "count": 1, "in": {"scrap": 1}, "bench": 1, "cat": "TEST WEAPONS"},
	{"id": "flamethrower", "out": "flamethrower", "count": 1, "in": {"scrap": 1}, "bench": 1, "cat": "TEST WEAPONS"},
	{"id": "pistol_heavy", "out": "pistol_heavy", "count": 1, "in": {"scrap": 1}, "bench": 1, "cat": "TEST WEAPONS"},
	{"id": "pistol_long", "out": "pistol_long", "count": 1, "in": {"scrap": 1}, "bench": 1, "cat": "TEST WEAPONS"},
	{"id": "crate_wood", "out": "crate_wood", "count": 1, "in": {"wood": 6, "scrap": 2}, "bench": 1, "cat": "STORAGE"},
	{"id": "crate_metal", "out": "crate_metal", "count": 1, "in": {"scrap": 8, "plastic": 2, "tech": 1}, "bench": 1, "cat": "STORAGE"},
]

## Crafting bench levels: cost to build (level 1) or upgrade.
const BENCH_LEVELS := {
	1: {"in": {"wood": 4, "scrap": 3}},
	2: {"in": {"scrap": 6, "tech": 3, "ore": 2}},
	3: {"in": {"scrap": 10, "tech": 6, "ore": 5, "crystal": 2}},
}

## Skill tree. One point per player level. ranks = how many times it can be taken.
## Attributes: +2 points every level, spent freely (SWTOR-style stats).
## "per" is what one point gives; stat sheet maths is in game_state.gd.
const ATTRIBUTES := [
	{"id": "mastery", "name": "Mastery", "per": "+1.5% weapon damage", "icon": "◆"},
	{"id": "endurance", "name": "Endurance", "per": "+10 max health, +0.15 health/s regeneration", "icon": "♥"},
	{"id": "power", "name": "Power", "per": "+1% weapon damage, +4% grenade damage", "icon": "✦"},
	{"id": "critical", "name": "Critical", "per": "+1% critical chance, +2% critical damage", "icon": "✸"},
	{"id": "alacrity", "name": "Alacrity", "per": "+2% fire rate, +3% reload speed", "icon": "➤"},
	{"id": "defense", "name": "Defense", "per": "+0.8% chance to evade an attack", "icon": "◇"},
	{"id": "shield", "name": "Shield", "per": "+1% chance to block (blocked hits deal 40% less)", "icon": "⬡"},
	{"id": "presence", "name": "Presence", "per": "+4% droid and ally damage", "icon": "✚"},
]
const ATTR_CAP := 25
const ATTR_PER_LEVEL := 2

## Skill trees (disciplines). Each tier opens at a player level and once
## enough points are spent in that tree: [level, points in tree].
const TIERS := [[1, 0], [4, 3], [8, 6], [12, 9]]
const BRANCHES := ["MARKSMAN", "VANGUARD", "MEDIC", "ENGINEER", "COMMAND", "SCAVENGER"]
const BRANCH_BLURB := {
	"MARKSMAN": "Blaster mastery: damage, criticals and rate of fire.",
	"VANGUARD": "Staying alive: health, armour, evasion and recovery.",
	"MEDIC": "Field medicine: stronger healing, regeneration and remedies.",
	"ENGINEER": "Tech and crafting: grenades, modules and the bench.",
	"COMMAND": "Leading the squad: the droid and your allies.",
	"SCAVENGER": "Living off the land: salvage, loot and experience.",
}
const SKILLS := [
	# Marksman
	{"id": "steady_aim", "branch": "MARKSMAN", "tier": 0, "name": "Steady Aim", "ranks": 3, "desc": "+10% weapon damage per rank."},
	{"id": "quick_hands", "branch": "MARKSMAN", "tier": 0, "name": "Quick Hands", "ranks": 1, "desc": "Reload 40% faster."},
	{"id": "extended_mag", "branch": "MARKSMAN", "tier": 1, "name": "Extended Cells", "ranks": 2, "desc": "+5 shots per magazine per rank."},
	{"id": "deadeye", "branch": "MARKSMAN", "tier": 1, "name": "Deadeye", "ranks": 3, "desc": "+3% critical chance per rank."},
	{"id": "rapid_fire", "branch": "MARKSMAN", "tier": 2, "name": "Rapid Fire", "ranks": 2, "desc": "+8% fire rate per rank."},
	{"id": "overcharged_bolts", "branch": "MARKSMAN", "tier": 2, "name": "Overcharged Bolts", "ranks": 2, "desc": "Critical hits deal +20% damage per rank."},
	{"id": "executioner", "branch": "MARKSMAN", "tier": 3, "name": "Executioner", "ranks": 1, "desc": "+40% damage to creatures below 30% health."},
	# Vanguard
	{"id": "tough", "branch": "VANGUARD", "tier": 0, "name": "Tough", "ranks": 3, "desc": "+15 max health per rank."},
	{"id": "field_medic", "branch": "VANGUARD", "tier": 0, "name": "Field Medic", "ranks": 1, "desc": "Healing items restore 50% more."},
	{"id": "field_chem", "branch": "VANGUARD", "tier": 1, "name": "Field Chemistry", "ranks": 1, "desc": "Unlocks the Medical Stim recipe."},
	{"id": "thick_skin", "branch": "VANGUARD", "tier": 1, "name": "Thick Skin", "ranks": 3, "desc": "Take 5% less damage per rank."},
	{"id": "second_wind", "branch": "VANGUARD", "tier": 2, "name": "Second Wind", "ranks": 2, "desc": "Regenerate 1.5 health/s per rank after 5 s without being hit."},
	{"id": "evasive", "branch": "VANGUARD", "tier": 2, "name": "Evasive", "ranks": 2, "desc": "+4% chance to evade an attack per rank."},
	{"id": "last_stand", "branch": "VANGUARD", "tier": 3, "name": "Last Stand", "ranks": 1, "desc": "A killing blow leaves you at 1 health and invulnerable for 3 s instead. Once every 2 minutes."},
	# Medic
	{"id": "triage", "branch": "MEDIC", "tier": 0, "name": "Triage", "ranks": 3, "desc": "Healing items restore 15% more per rank."},
	{"id": "pharmacist", "branch": "MEDIC", "tier": 0, "name": "Pharmacist", "ranks": 1, "desc": "Crafting medical supplies makes one extra."},
	{"id": "regenerative", "branch": "MEDIC", "tier": 1, "name": "Regenerative Care", "ranks": 2, "desc": "+0.75 health/s regeneration per rank (after 5 s without being hit)."},
	{"id": "pharmacology", "branch": "MEDIC", "tier": 1, "name": "Pharmacology", "ranks": 1, "desc": "Unlocks the Trauma Kit and Antivenom Shot recipes."},
	{"id": "anatomy", "branch": "MEDIC", "tier": 2, "name": "Creature Anatomy", "ranks": 2, "desc": "+8% damage to creatures per rank: you know where it hurts."},
	{"id": "auto_injector", "branch": "MEDIC", "tier": 2, "name": "Auto-Injector", "ranks": 1, "desc": "Below 25% health, your best healing item is used automatically. Once every 45 s."},
	{"id": "second_chance", "branch": "MEDIC", "tier": 3, "name": "Second Chance", "ranks": 1, "desc": "A killing blow uses up a healing item instead and leaves you at 40% health. Once every 3 minutes."},
	# Engineer
	{"id": "tinkerer", "branch": "ENGINEER", "tier": 0, "name": "Tinkerer", "ranks": 1, "desc": "Bench crafting gives double XP."},
	{"id": "demolitions", "branch": "ENGINEER", "tier": 0, "name": "Demolitions", "ranks": 2, "desc": "+25% grenade damage and +0.75 m blast radius per rank."},
	{"id": "efficient", "branch": "ENGINEER", "tier": 1, "name": "Efficient Crafting", "ranks": 2, "desc": "15% chance per rank to craft a bonus item."},
	{"id": "modding", "branch": "ENGINEER", "tier": 1, "name": "Modding", "ranks": 1, "desc": "Unlocks Targeting, Servo and Capacitor modules."},
	{"id": "overclock", "branch": "ENGINEER", "tier": 2, "name": "Overclock", "ranks": 2, "desc": "Equipped module bonuses +25% per rank."},
	{"id": "master_crafter", "branch": "ENGINEER", "tier": 3, "name": "Master Crafter", "ranks": 1, "desc": "Crafting ammo, grenades and medical supplies makes one extra."},
	# Command
	{"id": "droid_link", "branch": "COMMAND", "tier": 0, "name": "Droid Link", "ranks": 3, "droid": true, "desc": "+10% droid damage per rank."},
	{"id": "squad_leader", "branch": "COMMAND", "tier": 0, "name": "Squad Leader", "ranks": 2, "desc": "+12% ally damage per rank."},
	{"id": "adrenaline", "branch": "COMMAND", "tier": 1, "name": "Adrenaline", "ranks": 2, "desc": "Each kill restores 6 health per rank."},
	{"id": "commander", "branch": "COMMAND", "tier": 2, "name": "Commanding Presence", "ranks": 2, "desc": "+5 Presence per rank."},
	{"id": "coordinated_fire", "branch": "COMMAND", "tier": 3, "name": "Coordinated Fire", "ranks": 1, "desc": "Droid and allies deal +25% damage."},
	# Scavenger
	{"id": "scavenger", "branch": "SCAVENGER", "tier": 0, "name": "Scavenger", "ranks": 2, "desc": "+1 resource from every pickup per rank."},
	{"id": "lumberjack", "branch": "SCAVENGER", "tier": 0, "name": "Lumberjack", "ranks": 1, "desc": "Chopping and mining give double."},
	{"id": "lucky", "branch": "SCAVENGER", "tier": 1, "name": "Lucky Find", "ranks": 1, "desc": "Crates contain an extra item."},
	{"id": "salvager", "branch": "SCAVENGER", "tier": 1, "name": "Salvager", "ranks": 2, "desc": "+20% salvage per rank."},
	{"id": "quick_study", "branch": "SCAVENGER", "tier": 2, "name": "Quick Study", "ranks": 2, "desc": "+10% experience per rank."},
	{"id": "fortune", "branch": "SCAVENGER", "tier": 3, "name": "Fortune", "ranks": 1, "desc": "Crates have a 25% chance to hold an enhancement module."},
]

## Quest chain started at the camp. Objectives are checked by GameState.
## Camp quest chain. Each quest: title, desc (the story behind it) and goals.
## A goal is [id, short text, hint]: the hint says how and where to do it
## (shown in the mission log).
const QUESTS := [
	{"title": "A Familiar Face",
		"desc": "You came to in a cave you don't remember reaching. The Coalition medic who dragged you here is sitting by the fire. Enemy colours or not, she saved your life. Find out why.",
		"goals": [["talk", "Talk to the survivor by the fire",
			"She's sitting at the campfire inside the cave. Walk up to her and press E."]]},
	{"title": "Make Camp",
		"desc": "The cave is dry, but it isn't a camp yet. You need wood for the fire and metal scrap to build anything worth having. The escape pod that came down east of camp should have plenty to strip.",
		"goals": [["have:wood:4", "Gather wood",
			"Fallen branches lie around the camp clearing. Walk over one and press E. The gold marker points to the nearest."],
			["have:scrap:3", "Find metal scrap (crashed pod east of camp)",
			"Head east out of the cave to the crashed escape pod. Scrap piles lie around the wreck: press E to collect."]]},
	{"title": "Workbench",
		"desc": "With wood and scrap you can put together a proper workbench. Everything else you make, from bandages to ammo, starts here.",
		"goals": [["bench:1", "Build a crafting bench in the cave",
			"The bench spot is inside the cave, on the left (west) side. Walk up to it and press E to build."]]},
	{"title": "Patch Yourself Up",
		"desc": "Out here a bandage is the difference between a bad day and your last one. Plant fibre makes a decent field dressing.",
		"goals": [["have:fiber:3", "Collect fiber from plants",
			"Look for tall leafy plants around the clearing and the meadow to the south-west. Press E to harvest."],
			["crafted:bandage", "Craft a bandage",
			"At the workbench, pick Bandage and craft it. Use bandages from the inventory (Tab) or press H to heal."]]},
	{"title": "Ammo Supply",
		"desc": "The blaster's power cells won't last forever. Supply crates thrown clear of the wreckage still hold tech parts you can turn into cartridges.",
		"goals": [["have:tech:1", "Find tech components in supply crates",
			"Open supply crates (press E) around camp and by the escape pod. The marker points to the nearest."],
			["crafted:cartridge", "Craft a blaster cartridge",
			"Craft a cartridge at the workbench. Each one refills a magazine: press R to reload."]]},
	{"title": "Tools of the Trade",
		"desc": "Picking up branches one at a time won't keep a fire going. A vibro-hatchet will make short work of the trees around camp.",
		"goals": [["crafted:hatchet", "Craft a vibro-hatchet",
			"Craft it at the workbench."],
			["chopped", "Chop a tree",
			"Walk up to a tree and press E with the hatchet in your kit. The marker points to the nearest one."]]},
	{"title": "Level Up",
		"desc": "Every fight on Kethra teaches you something. Put what you've learned to use.",
		"goals": [["spent_point", "Spend a skill point (Esc → SKILLS)",
			"Press Esc and open SKILLS (or press K). Spend a point on any skill, or an attribute point on any attribute."]]},
	{"title": "Strike the Vein",
		"desc": "A better bench needs ore, and loose stones won't cover it. The crystal spires west of camp have ore veins at their feet, and so do the cliffs beside the cave. You'll need a pick. While you're there, the crystal itself might be worth chipping off.",
		"goals": [["crafted:pick", "Craft a mining pick",
			"Craft a Mining Pick at the workbench (TOOLS)."],
			["mined", "Mine an ore vein",
			"Ore veins glow orange. Two are at the foot of the cliffs either side of the cave mouth, two at the Crystal Spires to the west (marked on the map). Press E with the pick in your kit."],
			["have:ore:3", "Collect 3 ore",
			"Each vein gives ore a few times before it's spent. Loose ore stones also lie around the valley."]]},
	{"title": "Upgrades",
		"desc": "The basics are covered. Now make them better: a stronger bench, and gear that gives you an edge.",
		"goals": [["bench:2", "Upgrade the crafting bench",
			"Use the workbench and choose Upgrade. It needs salvage and materials."],
			["equipped_module", "Craft and equip an enhancement module",
			"Craft a module at the upgraded bench, then open the inventory (Tab) and equip it in a module slot."]]},
	{"title": "Check On Him",
		"desc": "The camp is running and the bench is better than it's ever been. But he still hasn't woken up, and the dressings on those bites are soaked through again. Go and look at him properly.",
		"goals": [["checked_on_him", "Check on the trooper",
			"Go into the cave and press E at his cot."]]},
]
const QUEST_XP := 40

## Her own missions while he recovers (Shipfall Reach). They start when you
## check on him at camp as her, and run ahead of the camp missions until done
## (GS.flags["med_stage"]). Text follows LORE.md.
const MED_QUESTS := [
	{"title": "Pathfinder Cache",
		"desc": "He's lost too much blood for field dressings, and the bites won't close. On the march in from the HALCYON, your unit cached its heavy med packs in the wreck field east of camp so it could move faster. You marked every cache with a pathfinder beacon and swore you'd be back for them in two days. Go and get them.",
		"goals": [["reach_waypoint", "Find your unit's waypoint camp in Shipfall Reach",
			"Take the trail east out of Base Camp (it leaves the camp path by the escape pod), then press E at the end of it. The camp is a short walk along the trail."],
			["have:medpack:3", "Recover the med packs from your unit's caches",
			"Look for the blinking orange pathfinder beacons: one inside the broken freighter, one on the old stone ruins east of the river, one by the survey lander across the southern stream."]]},
	{"title": "Field Remedies",
		"desc": "The packs survived. The coagulant didn't: every vial is cracked or spoiled. The pathfinder survival brief swore by glowcap sap as a clotting agent. You hate waste, and the riverbanks are full of the stuff.",
		"goals": [["have:glowcap:4", "Gather glowcaps along the riverbanks",
			"Glowcaps grow on the damp banks of both rivers: broad dark leaves and glowing bulbs. Press E to pick them."],
			["crafted:coagulant", "Cook coagulant at the field med kit",
			"Use the field med kit at your unit's waypoint camp. Spare coagulant is a strong heal, and you can make more at the workbench later."]]},
	{"title": "Tissue Samples",
		"desc": "Coagulant will close the wounds, but something in the creatures' bite keeps blood from clotting at all. You won't counter it without knowing what it is. You need tissue from the creatures themselves.",
		"goals": [["have:tissue:3", "Take tissue samples from slain creatures",
			"Kill creatures in Shipfall Reach, then press E at a body to take a sample (look for the blue vial marker)."],
			["analysed_tissue", "Study the samples at the field med kit",
			"Use the field med kit at the waypoint camp with three samples."]]},
	{"title": "Bring It Home",
		"desc": "You have what he needs: sutures, coagulant, and some idea of what you're fighting. Get the supplies back to the trooper before the fever takes hold.",
		"goals": [["treated_trooper", "Bring the med supplies to the trooper and treat him",
			"Head back west to Base Camp, go into the cave and press E at his cot."]]},
]

## The mini combat drone (starts when the camp missions or her medical
## missions are done, whichever is first; either of you can do it). GS.flags["drone_stage"].
## Droid attachments you can fit to the Strider's right arm socket
## (party menu). Each opens a kind of obstacle.
const DROID_ARMS := {
	"saw_arm": {"name": "Plasma Saw", "does": "Cuts through hull plate and bulkheads. Fights up close."},
}

## The Strider droid, rebuilt from parts in the Spire Canyon. Starts the
## first time you reach the canyon. GS.flags["strider_stage"].
const STRIDER_QUESTS := [
	{"title": "Scattered Steel",
		"desc": "An Ascendancy supply drop came down in the canyon. In its cradle lies the frame of a Strider escort droid, stripped of its legs and arms. Strider units imprint on whoever brings them back online.",
		"goals": [["found_cradle", "Find the droid frame in the supply drop",
			"Spire Canyon: the crashed supply drop sits on the middle shelf on the canyon's north side. Follow the cave up from the canyon floor."]]},
	{"title": "Parts Hunt",
		"desc": "The limbs were torn off and carried away, into each of the four places the canyon branches into. Something has made a nest of each one.",
		"goals": [["have:strider_legs_f:1", "Recover the front legs (Glowmire Caverns, north-west)",
			"Take the north-west path out of the canyon into the caverns."],
			["have:strider_legs_b:1", "Recover the rear legs (Rimefall Plateau, north-east)",
			"Take the north-east path up onto the frozen plateau."],
			["have:strider_arm_l:1", "Recover the left cannon (Sunken Mire, south-west)",
			"Take the south-west path down into the swamp."],
			["have:strider_arm_r:1", "Recover the right arm mount (the wreck of the VIGILANT, south-east)",
			"Take the south-east path into the crashed capital ship."]]},
	{"title": "Wake the Strider",
		"desc": "All four limbs. Bolt them back onto the frame in the cradle and give it power.",
		"goals": [["droid_rebuilt", "Rebuild the droid at the supply drop cradle",
			"Back in Spire Canyon: press E at the cradle with all four parts."]]},
	{"title": "Cut a Way Through",
		"desc": "A whole bulkhead from some broken warship is jammed across the canyon's east fork. Nothing gets past it, but the Strider's right socket takes tool arms. A plasma saw would do it.",
		"goals": [["crafted:saw_arm", "Craft a Plasma Saw Arm at the workbench",
			"At the Base Camp workbench (TOOLS). Needs scrap, ore, tech and crystal."],
			["fitted:saw_arm", "Fit the saw arm to the droid",
			"Open the party menu (P) and pick the Plasma Saw under the droid's ARM."],
			["bulkhead_cut", "Cut through the bulkhead in the canyon's east fork",
			"Spire Canyon, east fork: walk up to the bulkhead with the droid and press E."]]},
]

const DRONE_QUESTS := [
	{"title": "Signal in the Wreck",
		"desc": "For days now your helmet comm has been picking up a weak transponder from Shipfall Reach, east over the hills. It's coming from the broken freighter: something small, still holding a charge.",
		"goals": [["found_drone", "Find the source of the signal in the freighter's nose",
			"Take the trail east out of Base Camp (it leaves the camp path by the escape pod) and press E at its end to reach Shipfall Reach. Then find the nose half of the broken freighter, west of the river. Walk in through the torn end and look along the cargo racks."]]},
	{"title": "Control Chip",
		"desc": "A mini combat drone, folded up in its cradle. The frame's fine, the guns are fine. The control chip's a melted lump. Build a new one at the workbench.",
		"goals": [["crafted:control_chip", "Craft a drone control chip at the workbench",
			"At the Base Camp workbench, craft a Drone Control Chip (AMMO & GEAR). It needs tech components, scrap and plastic."]]},
	{"title": "Wake It Up",
		"desc": "Fit the new chip and see if the drone still remembers how to fight.",
		"goals": [["drone_installed", "Install the chip in the drone in the freighter",
			"Go back to the freighter's nose in Shipfall Reach and press E at the drone."]]},
]

## Inventory icon for an item (res://icons/items/<id>.png), or null.
static func icon(id: String) -> Texture2D:
	var path := "res://icons/items/%s.png" % id
	return load(path) if ResourceLoader.exists(path) else null

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
	["heavy_cell", 1, 1, 0.25],
	["fuel", 1, 1, 0.25],
	["ore", 1, 2, 0.25],
]
