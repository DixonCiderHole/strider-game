extends RefCounted
## Party banter: walk up to a companion, look at them and press E to talk.
##
## Each companion has TOPICS (one-off conversations, played in order once
## they unlock) and IDLE lines (short one-liners for when there's nothing new
## to say). Topics unlock by trust stage (see GS.trust_stage), and can also
## need an area, a story flag, or the player to be hurt. A new topic only comes
## up every NEW_TOPIC_GAP seconds, so conversations stay occasional.
##
## Lines are [speaker, text]. "YOU" is the player; "ILSA" and "STRIDER" are
## the companions. Story writing rules are in LORE.md.

const GS = preload("res://scripts/game_state.gd")

const NEW_TOPIC_GAP := 150.0
static var _last_topic_at := -1000.0

## Display names for the speaker tags.
static func speaker_name(tag: String) -> String:
	if tag == "ILSA" and not GS.flags.get("knows_ilsa", false):
		return "SURVIVOR"
	return tag


const TOPICS := {
	"survivor": [
		# ---- stage 0: wary. Short, guarded.
		{"id": "s0_name", "stage": 0, "sets": "knows_ilsa", "lines": [
			["SURVIVOR", "If we're going to keep not shooting each other, you may as well know my name."],
			["SURVIVOR", "Ilsa Renn. Corpsman, Coalition Pathfinders. What's left of them."],
			["YOU", "I'm not giving you my unit."],
			["ILSA", "Didn't ask for it. Just tell me if you start bleeding again."],
		]},
		{"id": "s0_why", "stage": 0, "lines": [
			["YOU", "Why did you pull me out of there?"],
			["ILSA", "You were breathing. That's the only qualification I care about."],
			["YOU", "My squad would have left you on that tree."],
			["ILSA", "I believe you. That's the difference between us."],
		]},
		{"id": "s0_armour", "stage": 0, "lines": [
			["ILSA", "Do you ever take that helmet off?"],
			["YOU", "Not around Coalition."],
			["ILSA", "Fair. Every time I look at that black and red I see the ridge where we went down. Don't take it personally."],
		]},
		{"id": "s0_ambush", "stage": 0, "lines": [
			["ILSA", "Your squad was in that clearing before mine. Convenient."],
			["YOU", "We were dying in it before you arrived. Convenient for who?"],
			["ILSA", "...Then answer me this. When I went back for our packs, half my people weren't where they fell."],
			["ILSA", "Something dragged them into the trees. Yours too."],
		]},
		{"id": "s0_blaster", "stage": 0, "lines": [
			["YOU", "This rifle is a toy. I carried a flame projector into three campaigns."],
			["ILSA", "And where is it now?"],
			["YOU", "Somewhere in that wreck. In pieces."],
			["ILSA", "Then the toy will have to do. Aim for the eyes."],
		]},
		{"id": "s0_hurt", "stage": 0, "hurt": true, "lines": [
			["ILSA", "You're bleeding through the seals again. Sit down before you fall down."],
			["YOU", "I'm fine."],
			["ILSA", "You're Ascendancy. You'd say that with your arm off. Bandage. Now."],
		]},
		{"id": "s0_crash", "stage": 0, "area": "res://main.tscn", "lines": [
			["ILSA", "So this was your ship."],
			["YOU", "Assault lander. Twelve of us aboard."],
			["ILSA", "The same thing hit us. No warning on the scopes, no missile. The drives just... died."],
		]},
		# ---- stage 1: grudging respect. Small personal details slip out.
		{"id": "s1_patch", "stage": 1, "lines": [
			["ILSA", "Hold still. You took that last hit on the shoulder plate and didn't even flinch."],
			["YOU", "Training."],
			["ILSA", "Training doesn't stop it hurting. It just teaches you to lie about it. Ours does the same."],
		]},
		{"id": "s1_propaganda", "stage": 1, "lines": [
			["YOU", "They told us the Coalition couldn't hold a line. That you'd scatter at the first shot."],
			["ILSA", "They told us you shoot your own wounded to save rations."],
			["YOU", "...We don't."],
			["ILSA", "I know. I've watched you share yours with the droid. It doesn't even eat."],
		]},
		{"id": "s1_home", "stage": 1, "lines": [
			["YOU", "Where are you from? Before the Coalition."],
			["ILSA", "A farming moon you've never heard of. Wheat to the horizon and a sky the colour of rust."],
			["ILSA", "Your fleet passed over it once. Didn't stop. I suppose we weren't worth the fuel."],
			["ILSA", "That's the first time I've been glad to be ignored."],
		]},
		{"id": "s1_flamer", "stage": 1, "lines": [
			["ILSA", "You talk in your sleep, you know. Mostly about fuel pressure and nozzle widths."],
			["YOU", "It's a flame projector. It's a precision instrument."],
			["ILSA", "If we find a working fuel cell, I'll help you build one. If only so you'll stop mourning it."],
		]},
		{"id": "s1_spines", "stage": 1, "lines": [
			["ILSA", "I cut one of those creatures open last night. The crystal along the spine isn't a growth."],
			["ILSA", "It's set. Placed. The way you'd set a bone."],
			["YOU", "Something did that to them?"],
			["ILSA", "Something's doing it to everything out here. I'd rather not find out what."],
		]},
		{"id": "s1_tag", "stage": 1, "lines": [
			["ILSA", "Found this in the brush by the stream. A Coalition tag. Not one of mine."],
			["YOU", "The first team? The ones who built the beacon?"],
			["ILSA", "It's a long way from K-7. And there was no body. There never is."],
		]},
		{"id": "s1_beacon", "stage": 1, "lines": [
			["YOU", "When we reach the beacon, only one of us gets to call a fleet."],
			["ILSA", "I know."],
			["YOU", "That's it? 'I know'?"],
			["ILSA", "Get us there alive first. Then we can go back to being enemies."],
		]},
		# ---- stage 2: trust (after the beacon). Unlocked by story flags later.
		{"id": "s2_nobody", "stage": 2, "lines": [
			["ILSA", "Nobody's coming. Not for you, not for me."],
			["YOU", "Then we stop waiting for them."],
			["ILSA", "...That's the most Coalition thing I've ever heard you say."],
		]},
		{"id": "s2_name", "stage": 2, "lines": [
			["ILSA", "You still haven't told me your name."],
			["YOU", "...You've earned it. Ask me again tonight, by the fire."],
		]},
		{"id": "s2_after", "stage": 2, "lines": [
			["ILSA", "If a ship ever does come, whose colours do you think it'll be flying?"],
			["YOU", "Doesn't matter. Whoever lands, you're coming with me."],
			["ILSA", "Careful. That almost sounded like trust."],
		]},
	],
	"droid": [
		{"id": "d_status", "stage": 0, "lines": [
			["STRIDER", "[chirp] Status report. Chassis integrity 71%. Optical sensor 64%. Operator survival probability: improving."],
			["YOU", "Good to have you, tin can."],
			["STRIDER", "[two-tone beep] Designation noted: 'Tin Can'. Filing under affectionate."],
		]},
		{"id": "d_medic", "stage": 0, "lines": [
			["STRIDER", "[low whirr] Query. The Coalition medic has had seventeen clear firing solutions on the operator."],
			["STRIDER", "She has taken none of them. Threat assessment downgraded from 'hostile' to 'useful'."],
		]},
		{"id": "d_blackbox", "stage": 0, "lines": [
			["YOU", "What brought the lander down? You were plugged into the flight systems."],
			["STRIDER", "[static] Black-box log partly corrupted. Final readings: all drives lost power at the same instant."],
			["STRIDER", "Cause: an energy pulse from the ground below. Origin: west. Source matches the crystal formations."],
		]},
		{"id": "d_loyal", "stage": 1, "lines": [
			["STRIDER", "[soft chirp] Note. Unit's assigned squad: all signals lost. Unit reassigned to the last operator standing."],
			["STRIDER", "Reassignment is not a protocol. Unit chose it."],
		]},
		{"id": "d_tracks", "stage": 1, "lines": [
			["STRIDER", "[scanning tone] Ground scan: drag marks along the stream bank. Weight consistent with an armoured human."],
			["STRIDER", "Direction: away from every human structure on this planet. Recommend not following. Yet."],
		]},
		{"id": "d_after", "stage": 2, "lines": [
			["STRIDER", "[warm two-tone] Beacon offline. Fleet contact: impossible. Mission: void."],
			["STRIDER", "New mission, self-assigned: keep both of you alive. Acceptance not required."],
		]},
	],
}

const IDLE := {
	"survivor": [
		["Keep your eyes on the treeline, not on me.", "We need more fibre for bandages. You go through them like rations.", "Don't thank me. Just don't die.", "I'm fine. Ask me again and I'll stop being fine."],
		["You fight better when you're angry. Stay a little angry.", "My hands stop shaking when I'm working. Find me something to fix.", "That's the third time you've watched my back today. I noticed.", "Get some rest. You're no use to me asleep on your feet."],
		["Still here. Still breathing. Both of us.", "If you tell anyone I laughed at your joke, I'll deny it.", "Whatever's out there, we face it together. That's the deal."],
	],
	"droid": [
		["[chirp] Awaiting orders.", "[beep] Perimeter clear. For now.", "[whirr] Ambient creature activity: elevated.", "[two-tone] Ammunition reserves: adequate. Recommend fewer misses."],
		["[chirp] The medic hums when she works. Unit has recorded it. For morale.", "[beep] Operator heart rate elevated near the treeline. Understandable.", "[whirr] Unit is still functional. Thank you for the repairs."],
		["[warm chirp] Both humans: accounted for. Unit is... content.", "[beep] Standing by. As always."],
	],
}


## Picks what to say: the next unlocked topic not yet heard (rate-limited),
## otherwise one idle line. Returns an Array of [speaker, text].
static func pick(who: String, area: String, player_hurt: bool) -> Array:
	var stage := GS.trust_stage()
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_topic_at >= NEW_TOPIC_GAP:
		for t in TOPICS.get(who, []):
			if GS.flags.get("banter:" + t["id"], false) or int(t["stage"]) > stage:
				continue
			if t.has("area") and t["area"] != area:
				continue
			if t.get("hurt", false) and not player_hurt:
				continue
			if t.has("needs") and not GS.flags.get(t["needs"], false):
				continue
			GS.flags["banter:" + t["id"]] = true
			if t.has("sets"):
				GS.flags[t["sets"]] = true
			_last_topic_at = now
			GS.save()
			return t["lines"]
	var pool: Array = IDLE[who][mini(stage, IDLE[who].size() - 1)]
	var tag := "ILSA" if who == "survivor" else "STRIDER"
	return [[tag, pool[randi() % pool.size()]]]
