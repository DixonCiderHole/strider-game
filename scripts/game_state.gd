extends RefCounted
## Progress that carries between areas: salvage and upgrades.
## Static, so it survives scene changes. Saved to user://save_<slot>.cfg
## (several save files; the last one used is remembered in user://profile.cfg).

const LEGACY_PATH := "user://save.cfg"
const PROFILE_PATH := "user://profile.cfg"
const SLOTS := 5
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
## Allies' own level and XP: id -> {"level": int, "xp": int}. Allies who are
## following you when you earn XP get the same amount.
static var party := {}
## Placed storage crates: Array of {"area", "type", "pos": Vector3, "yaw", "items": Array (null or {"id","n"})}.
static var storage: Array = []
## Which party member you are playing as (highlighted on the PARTY screen).
static var active_member := "trooper"   # who you're playing: "trooper" or "survivor"
## Progress of the members you're NOT currently playing (each character has
## their own level, XP, skills, attributes, backpack and gear). The active
## member's progress lives in the usual vars below.
static var profiles := {}
static var _loaded := false
static var slot := 0   # 0 = not picked yet (uses the last one played)

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
static var attr_points := 0
static var attributes := {}       # attribute id -> points spent
static var _last_stand_at := -1000.0
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
	if cf.load(save_path()) != OK:
		_fix_backpack()
		_starting_kit()
		return
	salvage = cf.get_value("progress", "salvage", 0)
	reached_base = cf.get_value("progress", "reached_base", false)
	last_area = cf.get_value("progress", "last_area", last_area)
	checkpoint = cf.get_value("progress", "checkpoint", "")
	horde_best_wave = cf.get_value("horde", "best_wave", 0)
	ally_joined = cf.get_value("progress", "ally_joined", false)
	party = cf.get_value("party", "stats", {})
	storage = cf.get_value("party", "storage", [])
	for k in levels:
		levels[k] = cf.get_value("upgrades", k, 0)
	backpack = cf.get_value("rpg", "backpack", [])
	equipment = cf.get_value("rpg", "equipment", equipment)
	mag = cf.get_value("rpg", "mag", MAG_SIZE)
	player_level = cf.get_value("rpg", "level", 1)
	xp = cf.get_value("rpg", "xp", 0)
	skill_points = cf.get_value("rpg", "skill_points", 0)
	skills = cf.get_value("rpg", "skills", {})
	attributes = cf.get_value("rpg", "attributes", {})
	# Saves from before attributes existed get the points they'd have earned.
	attr_points = cf.get_value("rpg", "attr_points", Items.ATTR_PER_LEVEL * maxi(0, player_level - 1))
	bench_level = cf.get_value("rpg", "bench_level", 0)
	quest_stage = cf.get_value("rpg", "quest_stage", 0)
	flags = cf.get_value("rpg", "flags", {})
	active_member = cf.get_value("party", "active_member", "trooper")
	profiles = cf.get_value("party", "profiles", {})
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path()))
	_clear()
	_fix_backpack()
	_starting_kit()
	save()


static func _clear() -> void:
	salvage = 0
	levels = {"blaster": 0, "armor": 0, "droid": 0}
	reached_base = false
	last_area = "res://main.tscn"
	checkpoint = ""
	horde_best_wave = 0
	ally_joined = false
	party = {}
	storage = []
	backpack = []
	equipment = {"primary": "rifle", "sidearm": "pistol", "utility1": "", "utility2": "", "module1": "", "module2": "", "module3": ""}
	mag = MAG_SIZE
	player_level = 1
	xp = 0
	skill_points = 0
	skills = {}
	attr_points = 0
	attributes = {}
	bench_level = 0
	quest_stage = 0
	flags = {}
	active_member = "trooper"
	profiles = {}


static func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("progress", "salvage", salvage)
	cf.set_value("progress", "reached_base", reached_base)
	cf.set_value("progress", "last_area", last_area)
	cf.set_value("progress", "checkpoint", checkpoint)
	cf.set_value("horde", "best_wave", horde_best_wave)
	cf.set_value("progress", "ally_joined", ally_joined)
	cf.set_value("party", "stats", party)
	cf.set_value("party", "storage", storage)
	for k in levels:
		cf.set_value("upgrades", k, levels[k])
	cf.set_value("rpg", "backpack", backpack)
	cf.set_value("rpg", "equipment", equipment)
	cf.set_value("rpg", "mag", mag)
	cf.set_value("rpg", "level", player_level)
	cf.set_value("rpg", "xp", xp)
	cf.set_value("rpg", "skill_points", skill_points)
	cf.set_value("rpg", "skills", skills)
	cf.set_value("rpg", "attributes", attributes)
	cf.set_value("rpg", "attr_points", attr_points)
	cf.set_value("rpg", "bench_level", bench_level)
	cf.set_value("rpg", "quest_stage", quest_stage)
	cf.set_value("rpg", "flags", flags)
	cf.set_value("party", "active_member", active_member)
	cf.set_value("party", "profiles", profiles)
	if active_member == "survivor":
		party_stats("survivor")["level"] = player_level
	cf.set_value("meta", "saved_at", int(Time.get_unix_time_from_system()))
	cf.save(save_path())


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
	salvage += int(round(amount * salvage_mult()))
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
	return stat_at("blaster", level("blaster")) * (1.0 + 0.1 * rank("steady_aim") + 0.015 * attr("mastery")
		+ 0.01 * attr("power") + module_bonus("damage"))


static func player_max_health() -> float:
	return stat_at("armor", level("armor")) + 15.0 * rank("tough") + 10.0 * attr("endurance") + module_bonus("health")


static func droid_damage() -> float:
	return stat_at("droid", level("droid")) * (1.0 + 0.1 * rank("droid_link") + 0.04 * attr("presence")
		+ 0.25 * rank("coordinated_fire"))


## Allies' outgoing damage multiplier.
static func ally_damage_mult() -> float:
	return 1.0 + 0.12 * rank("squad_leader") + 0.04 * attr("presence") + 0.25 * rank("coordinated_fire")


# ---------------------------------------------------------------- combat stats

static func crit_chance() -> float:
	return minf(0.05 + 0.01 * attr("critical") + 0.03 * rank("deadeye"), 0.75)


static func crit_mult() -> float:
	return 1.5 + 0.02 * attr("critical") + 0.2 * rank("overcharged_bolts")


static func fire_rate_mult() -> float:
	return 1.0 + 0.02 * attr("alacrity") + 0.08 * rank("rapid_fire")


static func reload_time_mult() -> float:
	return (0.6 if rank("quick_hands") > 0 else 1.0) / (1.0 + 0.03 * attr("alacrity"))


static func evade_chance() -> float:
	return minf(0.008 * attr("defense") + 0.04 * rank("evasive"), 0.35)


static func block_chance() -> float:
	return minf(0.01 * attr("shield"), 0.3)


const BLOCK_ABSORB := 0.4


static func damage_taken_mult() -> float:
	return 1.0 - 0.05 * rank("thick_skin")


## Health/s regenerated once you've gone 5 s without being hit.
static func regen_rate() -> float:
	return 0.15 * attr("endurance") + 1.5 * rank("second_wind")


static func grenade_mult() -> float:
	return 1.0 + 0.04 * attr("power") + 0.25 * rank("demolitions")


static func grenade_radius_bonus() -> float:
	return 0.75 * rank("demolitions")


static func xp_mult() -> float:
	return 1.0 + 0.1 * rank("quick_study")


static func salvage_mult() -> float:
	return 1.0 + 0.2 * rank("salvager")


## Last Stand: true (and starts the 2 minute cooldown) if it can save you now.
static func try_last_stand() -> bool:
	if rank("last_stand") <= 0:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_stand_at < 120.0:
		return false
	_last_stand_at = now
	return true



# ================================================================ inventory

static func _fix_backpack() -> void:
	while backpack.size() < BACKPACK_SLOTS:
		backpack.append(null)
	for k in ["primary", "sidearm", "utility1", "utility2", "module1", "module2", "module3"]:
		if not equipment.has(k):
			equipment[k] = ""


## Switches who you're playing. Stores the current character's progress and
## loads the other's (a fresh one the first time: the survivor starts at her
## party level with a rifle and a medic's kit).
static func switch_member(id: String) -> void:
	ensure_loaded()
	if id == active_member:
		return
	profiles[active_member] = {
		"backpack": backpack.duplicate(true), "equipment": equipment.duplicate(true), "mag": mag,
		"player_level": player_level, "xp": xp, "skill_points": skill_points, "skills": skills.duplicate(true),
		"attr_points": attr_points, "attributes": attributes.duplicate(true),
	}
	if profiles.has(id):
		var p: Dictionary = profiles[id]
		backpack = (p.get("backpack", []) as Array).duplicate(true)
		equipment = (p.get("equipment", {}) as Dictionary).duplicate(true)
		mag = int(p.get("mag", MAG_SIZE))
		player_level = int(p.get("player_level", 1))
		xp = int(p.get("xp", 0))
		skill_points = int(p.get("skill_points", 0))
		skills = (p.get("skills", {}) as Dictionary).duplicate(true)
		attr_points = int(p.get("attr_points", 0))
		attributes = (p.get("attributes", {}) as Dictionary).duplicate(true)
		profiles.erase(id)
	else:
		var lv := maxi(1, int(party_stats(id).get("level", 1)))
		backpack = []
		equipment = {"primary": "rifle", "sidearm": "", "utility1": "", "utility2": "", "module1": "", "module2": "", "module3": ""}
		mag = MAG_SIZE
		player_level = lv
		xp = 0
		skill_points = lv - 1
		skills = {}
		attr_points = Items.ATTR_PER_LEVEL * (lv - 1)
		attributes = {}
		_fix_backpack()
		add_item("cartridge", 3, false)
		add_item("bandage", 4, false)
		add_item("ration", 2, false)
	active_member = id
	_fix_backpack()
	changed()
	save()


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
	return total * (1.0 + 0.25 * rank("overclock"))


static func mag_size() -> int:
	return MAG_SIZE + 5 * rank("extended_mag") + int(module_bonus("mag"))


static func heal_amount(id: String) -> float:
	return float(item(id).get("heal", 0.0)) * (1.5 if rank("field_medic") > 0 else 1.0)


# ================================================================ xp & skills

static func add_xp(n: int) -> void:
	ensure_loaded()
	xp += int(round(n * xp_mult()))
	while xp >= Items.xp_for(player_level):
		xp -= Items.xp_for(player_level)
		player_level += 1
		skill_points += 1
		attr_points += Items.ATTR_PER_LEVEL
		toast("LEVEL UP!  Level %d  ·  +1 skill point  ·  +%d attribute points" % [player_level, Items.ATTR_PER_LEVEL])
	# Allies following you learn alongside you.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for m in tree.get_nodes_in_group("party_member"):
			var st := party_stats(m.party_id)
			st["xp"] = int(st["xp"]) + n
			while int(st["xp"]) >= Items.xp_for(int(st["level"])):
				st["xp"] = int(st["xp"]) - Items.xp_for(int(st["level"]))
				st["level"] = int(st["level"]) + 1
				toast("%s reached level %d" % [String(m.party_name).capitalize(), int(st["level"])])
	changed()


static func party_stats(id: String) -> Dictionary:
	ensure_loaded()
	if not party.has(id):
		party[id] = {"level": 1, "xp": 0}
	return party[id]


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
	return tier_open(String(d["branch"]), int(d.get("tier", 0)))


## How far the two survivors trust each other (drives banter):
## 0 wary, 1 grudging respect, 2 trust (after the beacon). Story scripts can
## force a stage with flags["trust"].
static func trust_stage() -> int:
	ensure_loaded()
	if flags.has("trust"):
		return int(flags["trust"])
	if flags.get("beacon_wrecked", false):
		return 2
	if quest_stage >= 6 or player_level >= 6:
		return 1
	return 0


## Points spent in one skill tree.
static func branch_points(branch: String) -> int:
	var n := 0
	for s in Items.SKILLS:
		if s["branch"] == branch:
			n += rank(s["id"])
	return n


static func tier_open(branch: String, tier: int) -> bool:
	var req: Array = Items.TIERS[tier]
	return player_level >= int(req[0]) and branch_points(branch) >= int(req[1])


## Attribute total: points spent plus skill bonuses.
static func attr(id: String) -> int:
	ensure_loaded()
	var v := int(attributes.get(id, 0))
	if id == "presence":
		v += 5 * rank("commander")
	return v


static func can_raise(id: String) -> bool:
	return attr_points > 0 and int(attributes.get(id, 0)) < Items.ATTR_CAP


static func raise_attr(id: String) -> bool:
	if not can_raise(id):
		return false
	attributes[id] = int(attributes.get(id, 0)) + 1
	attr_points -= 1
	flags["spent_point"] = true
	changed()
	return true


## Refunds every skill and attribute point so they can be spent again.
static func respec() -> void:
	for id in skills:
		skill_points += int(skills[id])
	for id in attributes:
		attr_points += int(attributes[id])
	skills = {}
	attributes = {}
	changed()
	save()


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
	if rank("master_crafter") > 0 and item(r["out"]).get("type", "") in ["consumable", "ammo", "utility"]:
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


# ---------------------------------------------------------------- storage

## Moves the whole stack in backpack slot `i` into crate `c` (merging first).
## Returns true if anything moved.
static func store(c: Dictionary, i: int) -> bool:
	var s = backpack[i]
	if s == null:
		return false
	var left := _put(c["items"], s["id"], int(s["n"]))
	if left == int(s["n"]):
		return false
	if left <= 0:
		backpack[i] = null
	else:
		s["n"] = left
	changed()
	return true


## Moves the whole stack in crate slot `i` back into the backpack.
static func take(c: Dictionary, i: int) -> bool:
	var s = c["items"][i]
	if s == null:
		return false
	var left := add_item(s["id"], int(s["n"]), false)
	if left == int(s["n"]):
		return false
	if left <= 0:
		c["items"][i] = null
	else:
		s["n"] = left
	changed()
	return true


static func _put(slots: Array, id: String, n: int) -> int:
	var stack: int = item(id).get("stack", 1)
	var left := n
	for s in slots:
		if left <= 0:
			break
		if s != null and s["id"] == id and int(s["n"]) < stack:
			var add := mini(stack - int(s["n"]), left)
			s["n"] = int(s["n"]) + add
			left -= add
	for i in slots.size():
		if left <= 0:
			break
		if slots[i] == null:
			var add2 := mini(stack, left)
			slots[i] = {"id": id, "n": add2}
			left -= add2
	return left


# ---------------------------------------------------------------- save files

static func current_slot() -> int:
	if slot < 1:
		var pf := ConfigFile.new()
		slot = clampi(int(pf.get_value("profile", "last_slot", 1)) if pf.load(PROFILE_PATH) == OK else 1, 1, SLOTS)
		# Older builds kept one save at user://save.cfg: it becomes save file 1.
		if FileAccess.file_exists(LEGACY_PATH) and not FileAccess.file_exists("user://save_1.cfg"):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(LEGACY_PATH), ProjectSettings.globalize_path("user://save_1.cfg"))
	return slot


static func save_path(n := 0) -> String:
	return "user://save_%d.cfg" % (n if n > 0 else current_slot())


## Switches to save file `n` and loads it (an empty one starts fresh).
static func use_slot(n: int) -> void:
	slot = clampi(n, 1, SLOTS)
	var pf := ConfigFile.new()
	pf.set_value("profile", "last_slot", slot)
	pf.save(PROFILE_PATH)
	_clear()
	_loaded = false
	ensure_loaded()


## Summary of save file `n` for the save-file list.
static func slot_info(n: int) -> Dictionary:
	current_slot()
	var cf := ConfigFile.new()
	if cf.load(save_path(n)) != OK:
		return {"used": false}
	return {
		"used": true,
		"area": String(cf.get_value("progress", "checkpoint", "")),
		"level": int(cf.get_value("rpg", "level", 1)),
		"salvage": int(cf.get_value("progress", "salvage", 0)),
		"saved_at": int(cf.get_value("meta", "saved_at", 0)),
	}


static func delete_slot(n: int) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path(n)))
	if n == current_slot():
		_clear()
		_loaded = false
		ensure_loaded()
