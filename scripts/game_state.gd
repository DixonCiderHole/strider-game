extends RefCounted
## Progress that carries between areas: salvage and upgrades.
## Static, so it survives scene changes. Saved to user://save.cfg.

const PATH := "user://save.cfg"
const Items = preload("res://scripts/items.gd")
const BACKPACK_SLOTS := 24
const MAG_SIZE := 30

## Upgrade tracks. Each level costs base_cost + level * cost_step salvage.
const TRACKS := {
	"blaster": {
		"crate": "ARMORY",
		"title": "Blaster",
		"blurb": "Overcharge the blaster's power cell.",
		"stat": "Damage per bolt",
		"max": 5, "base_cost": 30, "cost_step": 20,
	},
	"armor": {
		"crate": "MED-SUPPLY",
		"title": "Armor",
		"blurb": "Patch your armor with plating from the wreck.",
		"stat": "Max health",
		"max": 5, "base_cost": 30, "cost_step": 20,
	},
	"droid": {
		"crate": "DROID PARTS",
		"title": "Strider droid",
		"blurb": "Bolt salvaged parts onto the droid's weapon arms.",
		"stat": "Droid damage per bolt",
		"max": 5, "base_cost": 40, "cost_step": 25,
	},
}

## Salvage per creature killed in the crash-site waves, plus a bonus for clearing them.
const SALVAGE_PER_KILL := 6
const CLEAR_BONUS := 30

static var salvage := 0
static var levels := {"blaster": 0, "armor": 0, "droid": 0}
static var reached_base := false
## Unrelenting Horde: endless waves at the crash site (set by the main menu).
static var horde_mode := false
static var horde_best_wave := 0
## Which placeholder cutscene cutscene.tscn should play next.
static var cutscene_id := ""
## Scene the player was last in (the title screen shows it at night).
static var last_area := "res://main.tscn"
## True while an area scene is being built as the title-screen backdrop.
static var menu_preview := false
## Story checkpoint: the story area you last entered ("" = none yet).
## CONTINUE on the title screen starts here.
static var checkpoint := ""
## Set when the story brings you to the camp: you wake up on the bedroll.
static var wake_at_camp := false
## She has joined you (after the campfire talk): she follows and fights.
static var ally_joined := false
static var _loaded := false

# ---- Survival / RPG state (saved) ----
## Backpack: BACKPACK_SLOTS entries, each null or {"id": String, "n": int}.
static var backpack: Array = []
## Equipment slots -> item id ("" = empty).
static var equipment := {"primary": "rifle", "sidearm": "pistol", "utility1": "", "utility2": "", "module1": "", "module2": "", "module3": ""}
## Shots left in the rifle magazine.
static var mag := MAG_SIZE
static var player_level := 1
static var xp := 0
static var skill_points := 0
static var skills := {}           # skill id -> rank
static var bench_level := 0
static var quest_stage := 0
static var flags := {}            # crafted:<id>, chopped, spent_point, equipped_module, talk
## Things that want to know when the inventory/quests/xp change (UI). Callables.
static var listeners: Array = []
## Short messages for the on-screen feed ("+2 Wood", "LEVEL UP").
static var toasts: Array = []


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		_fix_backpack()
		_starting_kit()
		return
	salvage = cf.get_value("progress", "salvage", 0)
	reached_base = cf.get_value("progress", "reached_base", false)
	last_area = cf.get_value("progress", "last_area", last_area)
	checkpoint = cf.get_value("progress", "checkpoint", "")
	horde_best_wave = cf.get_value("horde", "best_wave", 0)
	ally_joined = cf.get_value("progress", "ally_joined", false)
	for k in levels:
		levels[k] = cf.get_value("upgrades", k, 0)
	backpack = cf.get_value("rpg", "backpack", [])
	equipment = cf.get_value("rpg", "equipment", equipment)
	mag = cf.get_value("rpg", "mag", MAG_SIZE)
	player_level = cf.get_value("rpg", "level", 1)
	xp = cf.get_value("rpg", "xp", 0)
	skill_points = cf.get_value("rpg", "skill_points", 0)
	skills = cf.get_value("rpg", "skills", {})
	bench_level = cf.get_value("rpg", "bench_level", 0)
	quest_stage = cf.get_value("rpg", "quest_stage", 0)
	flags = cf.get_value("rpg", "flags", {})
	_fix_backpack()
	if not cf.has_section("rpg"):
		_starting_kit()


## Wipes all progress (inventory, level, quests, upgrades) for a fresh start.
## Called by each area when it starts, so the title screen can show it.
static func enter_area(scene: String) -> void:
	ensure_loaded()
	last_area = scene
	if not horde_mode:
		checkpoint = scene
	save()


static func reset() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	salvage = 0
	levels = {"blaster": 0, "armor": 0, "droid": 0}
	reached_base = false
	last_area = "res://main.tscn"
	checkpoint = ""
	horde_best_wave = 0
	ally_joined = false
	backpack = []
	equipment = {"primary": "rifle", "sidearm": "pistol", "utility1": "", "utility2": "", "module1": "", "module2": "", "module3": ""}
	mag = MAG_SIZE
	player_level = 1
	xp = 0
	skill_points = 0
	skills = {}
	bench_level = 0
	quest_stage = 0
	flags = {}
	_fix_backpack()
	_starting_kit()
	save()


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("progress", "salvage", salvage)
	cf.set_value("progress", "reached_base", reached_base)
	cf.set_value("progress", "last_area", last_area)
	cf.set_value("progress", "checkpoint", checkpoint)
	cf.set_value("horde", "best_wave", horde_best_wave)
	cf.set_value("progress", "ally_joined", ally_joined)
	for k in levels:
		cf.set_value("upgrades", k, levels[k])
	cf.set_value("rpg", "backpack", backpack)
	cf.set_value("rpg", "equipment", equipment)
	cf.set_value("rpg", "mag", mag)
	cf.set_value("rpg", "level", player_level)
	cf.set_value("rpg", "xp", xp)
	cf.set_value("rpg", "skill_points", skill_points)
	cf.set_value("rpg", "skills", skills)
	cf.set_value("rpg", "bench_level", bench_level)
	cf.set_value("rpg", "quest_stage", quest_stage)
	cf.set_value("rpg", "flags", flags)
	cf.save(PATH)


static func level(track: String) -> int:
	ensure_loaded()
	return levels.get(track, 0)


static func is_maxed(track: String) -> bool:
	return level(track) >= int(TRACKS[track]["max"])


static func cost(track: String) -> int:
	var t: Dictionary = TRACKS[track]
	return int(t["base_cost"]) + level(track) * int(t["cost_step"])


static func can_upgrade(track: String) -> bool:
	return not is_maxed(track) and salvage >= cost(track)


static func upgrade(track: String) -> bool:
	if not can_upgrade(track):
		return false
	salvage -= cost(track)
	levels[track] = level(track) + 1
	save()
	return true


static func add_salvage(amount: int) -> void:
	ensure_loaded()
	salvage += amount
	save()


## The stat value for a track at a given level (shown in the upgrade panel).
static func stat_at(track: String, lvl: int) -> float:
	match track:
		"blaster":
			return 20.0 + 5.0 * lvl
		"armor":
			return 100.0 + 20.0 * lvl
		"droid":
			return 14.0 + 4.0 * lvl
	return 0.0


static func player_damage() -> float:
	return stat_at("blaster", level("blaster")) * (1.0 + 0.1 * rank("steady_aim") + module_bonus("damage"))


static func player_max_health() -> float:
	return stat_at("armor", level("armor")) + 15.0 * rank("tough") + module_bonus("health")


static func droid_damage() -> float:
	return stat_at("droid", level("droid"))



# ================================================================ inventory

static func _fix_backpack() -> void:
	while backpack.size() < BACKPACK_SLOTS:
		backpack.append(null)
	for k in ["primary", "sidearm", "utility1", "utility2", "module1", "module2", "module3"]:
		if not equipment.has(k):
			equipment[k] = ""


static func _starting_kit() -> void:
	add_item("cartridge", 3, false)
	add_item("bandage", 2, false)
	add_item("ration", 1, false)


static func item(id: String) -> Dictionary:
	return Items.ITEMS.get(id, {})


static func count(id: String) -> int:
	ensure_loaded()
	var n := 0
	for s in backpack:
		if s != null and s["id"] == id:
			n += int(s["n"])
	return n


## Adds to the backpack; returns how many didn't fit.
static func add_item(id: String, n: int, announce := true) -> int:
	ensure_loaded()
	if n <= 0 or item(id).is_empty():
		return n
	var stack: int = item(id).get("stack", 1)
	var left := n
	for s in backpack:
		if left <= 0:
			break
		if s != null and s["id"] == id and int(s["n"]) < stack:
			var add := mini(stack - int(s["n"]), left)
			s["n"] = int(s["n"]) + add
			left -= add
	for i in backpack.size():
		if left <= 0:
			break
		if backpack[i] == null:
			var add := mini(stack, left)
			backpack[i] = {"id": id, "n": add}
			left -= add
	if announce and n - left > 0:
		toast("+%d %s" % [n - left, item(id)["name"]])
	if left > 0 and announce:
		toast("Backpack full!")
	changed()
	return left


static func remove_item(id: String, n: int) -> bool:
	if count(id) < n:
		return false
	var left := n
	for i in range(backpack.size() - 1, -1, -1):
		var s = backpack[i]
		if left <= 0:
			break
		if s != null and s["id"] == id:
			var take := mini(int(s["n"]), left)
			s["n"] = int(s["n"]) - take
			left -= take
			if int(s["n"]) <= 0:
				backpack[i] = null
	changed()
	return true


static func has_all(costs: Dictionary) -> bool:
	for k in costs:
		if count(k) < int(costs[k]):
			return false
	return true


static func pay(costs: Dictionary) -> bool:
	if not has_all(costs):
		return false
	for k in costs:
		remove_item(k, int(costs[k]))
	return true


# ================================================================ equipment

static func equip_from_slot(index: int) -> String:
	var s = backpack[index]
	if s == null:
		return "Empty slot."
	var it := item(s["id"])
	var slot: String = it.get("slot", "")
	if slot == "":
		return "%s can't be equipped." % it["name"]
	var target := slot
	if slot == "utility" or slot == "module":
		target = ""
		var n := 2 if slot == "utility" else 3
		for i in range(1, n + 1):
			if equipment[slot + str(i)] == "":
				target = slot + str(i)
				break
		if target == "":
			target = slot + "1"
	var old: String = equipment[target]
	# Utility items stack (grenades): equip the whole stack id; count stays in the backpack.
	if slot == "utility":
		equipment[target] = s["id"]
		changed()
		return "Equipped %s." % it["name"]
	backpack[index] = null
	equipment[target] = s["id"]
	if old != "":
		add_item(old, 1, false)
	if slot == "module":
		flags["equipped_module"] = true
	changed()
	return "Equipped %s." % it["name"]


static func unequip(slot: String) -> void:
	var id: String = equipment.get(slot, "")
	if id == "":
		return
	equipment[slot] = ""
	if item(id).get("type") != "utility":
		add_item(id, 1, false)
	changed()


static func module_bonus(key: String) -> float:
	var total := 0.0
	for k in ["module1", "module2", "module3"]:
		var id: String = equipment.get(k, "")
		if id != "":
			total += float(item(id).get("bonus", {}).get(key, 0.0))
	return total


static func mag_size() -> int:
	return MAG_SIZE + 5 * rank("extended_mag") + int(module_bonus("mag"))


static func heal_amount(id: String) -> float:
	return float(item(id).get("heal", 0.0)) * (1.5 if rank("field_medic") > 0 else 1.0)


# ================================================================ xp & skills

static func add_xp(n: int) -> void:
	ensure_loaded()
	xp += n
	while xp >= Items.xp_for(player_level):
		xp -= Items.xp_for(player_level)
		player_level += 1
		skill_points += 1
		toast("LEVEL UP!  Level %d  ·  +1 skill point" % player_level)
	changed()


static func rank(id: String) -> int:
	ensure_loaded()
	return int(skills.get(id, 0))


static func skill_def(id: String) -> Dictionary:
	for s in Items.SKILLS:
		if s["id"] == id:
			return s
	return {}


static func can_learn(id: String) -> bool:
	var d := skill_def(id)
	if d.is_empty() or skill_points <= 0 or rank(id) >= int(d["ranks"]):
		return false
	var req: String = d.get("req", "")
	return req == "" or rank(req) > 0


static func learn(id: String) -> bool:
	if not can_learn(id):
		return false
	skills[id] = rank(id) + 1
	skill_points -= 1
	flags["spent_point"] = true
	changed()
	return true


# ================================================================ crafting

static func recipe_unlocked(r: Dictionary) -> bool:
	if bench_level < int(r.get("bench", 1)):
		return false
	var sk: String = r.get("skill", "")
	return sk == "" or rank(sk) > 0


static func craft(r: Dictionary) -> bool:
	if not recipe_unlocked(r) or not pay(r["in"]):
		return false
	var n: int = r["count"]
	if randf() < 0.15 * rank("efficient"):
		n += 1
	add_item(r["out"], n)
	flags["crafted:" + String(r["id"])] = true
	add_xp(12 if rank("tinkerer") > 0 else 6)
	changed()
	return true


static func upgrade_bench() -> bool:
	var next := bench_level + 1
	if not Items.BENCH_LEVELS.has(next):
		return false
	if not pay(Items.BENCH_LEVELS[next]["in"]):
		return false
	bench_level = next
	add_xp(20)
	toast("Crafting bench level %d" % bench_level)
	changed()
	return true


# ================================================================ quests

static func current_quest() -> Dictionary:
	ensure_loaded()
	if quest_stage < Items.QUESTS.size():
		return Items.QUESTS[quest_stage]
	return {}


static func goal_done(g: String) -> bool:
	# Once reached, a goal stays done (crafting uses up the materials you gathered).
	if flags.get("done:" + g, false):
		return true
	var parts := g.split(":")
	match parts[0]:
		"talk":
			return ally_joined
		"have":
			return count(parts[1]) >= int(parts[2])
		"bench":
			return bench_level >= int(parts[1])
		"crafted":
			return flags.get(g, false)
		_:
			return flags.get(g, false)


static func goal_progress(g: String) -> String:
	var parts := g.split(":")
	if parts[0] == "have":
		return " (%d/%d)" % [mini(count(parts[1]), int(parts[2])), int(parts[2])]
	return ""


## Advances the quest chain when every goal of the current quest is done.
static func check_quests() -> void:
	var q := current_quest()
	if q.is_empty():
		return
	var all := true
	for g in q["goals"]:
		if goal_done(g[0]):
			flags["done:" + String(g[0])] = true
		else:
			all = false
	if not all:
		return
	quest_stage += 1
	toast("QUEST COMPLETE: %s  ·  +%d XP" % [q["title"], Items.QUEST_XP])
	add_xp(Items.QUEST_XP)
	var nq := current_quest()
	if not nq.is_empty():
		toast("New quest: %s" % nq["title"])
	save()


# ================================================================ notifications

static func toast(text: String) -> void:
	toasts.append(text)


static func changed() -> void:
	check_quests_deferred()
	save()
	for cb in listeners.duplicate():
		if (cb as Callable).is_valid():
			(cb as Callable).call()
		else:
			listeners.erase(cb)


static var _checking := false

static func check_quests_deferred() -> void:
	if _checking:
		return
	_checking = true
	check_quests()
	_checking = false
