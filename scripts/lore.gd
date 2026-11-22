extends RefCounted
## Readable logs, datapads and transmissions found around the world.
## Reading one for the first time gives a little XP (GS.flags["read:<id>"]).

const ENTRIES := {
	"survivor_journal": {
		"title": "Survivor's Journal",
		"source": "Leather notebook, water-stained",
		"text": "Day 3. The cave is dry and the mouth faces away from the wind. Whoever stocked it left in a hurry. There are bedrolls, a locker that still takes my old clearance code, and a med bench with half its drawers empty.\n\nDay 6. Something circles the lake after dark. It doesn't come up the slope. Not yet.\n\nDay 9. Found the survey outpost to the north-east, K-7. The doors still slide if you hit the panel hard enough. The roof is half gone and the vines are pulling the rest down. I took what tech I could carry.\n\nDay 11. Keep the fire lit. They hate the light.",
	},
	"med_log": {
		"title": "Medic's Log - Entry 14",
		"source": "Datapad, med bench",
		"text": "Third bite this week. The wounds won't close on their own; the saliva carries an anticoagulant I can't name. Standard stims keep the patient upright, but only resting by a heat source brings the count back up.\n\nNote to whoever finds this station: the blue vials are coagulant, the red are painkiller, the green ones I still don't trust. Armor plating from the wreck can be bolted onto our suits. It's crude, but it stops teeth.",
	},
	"droid_manual": {
		"title": "Strider Unit - Field Maintenance",
		"source": "Datapad, droid workbench",
		"text": "STRIDER-class escort units are rated for hostile survey work. In the field:\n\n- Recalibrate weapon arms with salvaged emitter parts to raise bolt output.\n- Unit follows its operator by default. Give HOLD and MOVE orders for overwatch.\n- Optical sensor damage is common after hard landings. Replace the visor lens before the motivator.\n\nAll units carry a black-box recorder. If your unit is ever lost, its last position is logged to the nearest survey beacon.",
	},
	"quartermaster": {
		"title": "Quartermaster's Note",
		"source": "Taped inside the armory locker",
		"text": "Three rifles, one with a cracked emitter. Two cans of cells. Do NOT overcharge the cells past the yellow line unless you want to lose your eyebrows. If you have to, take them to the bench first.\n\nLocker code is the outpost designation. Change it if you've got the time. Nobody ever has the time.",
	},
	"radio": {
		"title": "Intercepted Transmission",
		"source": "Field radio, looping",
		"text": "...this is survey dropship HALCYON, any station on this band... we are going down over the eastern ridge... hull breach on decks two and three...\n\n[static]\n\n...if anyone reaches K-7, the beacon there is still live. Tell them the survey team found something under the crystal spires. Tell them not to... \n\n[the message repeats]",
	},
	"survey_map": {
		"title": "Survey Map - Valley Sector 4",
		"source": "Holo-map table",
		"text": "BASE CAMP: the cave in the southern cliffs. Shelter, water, fire.\n\nSTILLWATER: the lake to the east. Shallow at the edge, deep and cold past the reeds. An old jetty on the west shore.\n\nCRYSTAL SPIRES: rock towers to the west, threaded with glowing crystal. Ore veins at their base.\n\nSURVEY OUTPOST K-7: two prefab buildings to the north-east. Abandoned. Partly collapsed. Salvage likely.\n\nTHE MEADOW: flower fields and old trees to the south-west. Quiet. Too quiet, some say.",
	},
	"k7_roster": {
		"title": "K-7 Crew Roster",
		"source": "Datapad, habitat module",
		"text": "Survey Outpost K-7, crew of six.\n\nEvacuation order received 0400. Habitat sealed, lab samples to remain in containment.\n\nPersonal note, bottom of the file: 'We left the lights on. Someone said it would keep them away. The generator will run out long before they do.'",
	},
	"specimen_log": {
		"title": "Specimen Log - Containment",
		"source": "Datapad, survey lab",
		"text": "Specimen 7 shows the same crystalline growth along the spine as the formations at the spires. Its tissue responds to light: it recoils from the work lamps and calms in darkness.\n\nContainment breached at 0312 during the power cut. Tank glass failed from the INSIDE.\n\nRecommend all teams keep a light source burning after dark.",
	},	# ---- Shipfall Reach
	"pathfinder_log": {
		"title": "Pathfinder Team Log",
		"source": "Datapad, waypoint camp",
		"text": "Day 2 out from the HALCYON. Six of us walking, nobody carried. Sergeant's orders: we drop the heavy med packs here and move light through the wrecks.\n\nDoc didn't like it. Doc never likes leaving kit behind. She marked every cache with a beacon herself and made each of us repeat where they were. 'Two days,' she said. 'Then we come back for them.'\n\nRiver water's clean if you boil it. Something follows us at night, out past the firelight. Lights in the trees. Doc says it's just the crystal. Doc doesn't believe that either.",
	},
	"hauler_recorder": {
		"title": "Hauler Flight Recorder",
		"source": "Bridge console, broken freighter",
		"text": "BULK HAULER ORLA'S PROMISE. Independent charter, Meridian Run, first week the lane opened.\n\n04:12 Dropped out of hyperspace on schedule. Descending to pick up the survey crates.\n04:19 Crystal fields below are lit up like a city.\n04:20 Everything's dead. Drives, lights, the panel. Like someone threw a switch.\n04:20 Brace, brace, brace.\n\n[recording ends]",
	},
	"lander_log": {
		"title": "Lander K7-2 Flight Log",
		"source": "Survey lander, cockpit",
		"text": "Survey lander K7-2, out of Outpost K-7. Run to the eastern ridge to sample the spire field.\n\nReadings spike every time the crystals pulse. The pilot says the panel lights dim with it, a beat behind, like they're listening.\n\nTurning back. Logging the coordinates of the stone platform by the river: somebody built that. Somebody cut those blocks.\n\nLast entry: 'Lights in the trees again. Keep the engine warm.'",
	},
	"dog_tag": {
		"title": "Coalition ID Tag",
		"source": "Foot of the stone platform",
		"text": "A Coalition ID tag in the dust at the foot of the platform, a long way from any wreck. Pathfinder issue.\n\nThe name's been scraped off. The chain wasn't snapped. It was cut clean.\n\nThere are marks in the dirt beside it, two long grooves heading into the trees, as if something heavy was dragged.",
	},
	# ---- Spire Canyon
	"drop_manifest": {
		"title": "Supply Drop Manifest",
		"source": "Datapad, clipped inside the drop pod",
		"text": "ASCENDANCY FLEET LOGISTICS. Drop pod 14 of 20, from the cruiser VIGILANT.\n\nConsigned to: advance team, Outpost K-7.\nContents: 1 x STRIDER escort unit (cradled, powered down). Ration crates. Field cells.\n\nNote from the loadmaster: 'Strider imprints on the first operator to bring it online. Make sure that's one of ours.'\n\nThe pod's guidance log ends three seconds after release. Every drop in this batch shows the same thing.",
	},
	"canyon_pathfinder": {
		"title": "Waypoint Note",
		"source": "Scratched on a slate, weighted with a stone",
		"text": "Coalition pathfinders, second team. Water's good above the falls, not below.\n\nWe saw the big drop pod come down on the north wall and went up for it. Ascendancy kit. Somebody had already been at it. Not with tools: the limbs of the droid in the cradle were pulled off, and the marks go four different ways out of the canyon.\n\nWe're not following. Moving east at first light.",
	},
	"canyon_bulkhead": {
		"title": "Hull Plate Stencil",
		"source": "Stencilled on the bulkhead",
		"text": "ASC VIGILANT. FRAME 212. BLAST BULKHEAD. DO NOT CUT.\n\nThe plate came down kilometres from the rest of the ship and stuck upright between the walls like a door somebody shut. Under the stencil, in chalk, newer: 'CUTTER CREW: WE NEED A SAW, NOT A TORCH.'",
	},
	"canyon_rim_carving": {
		"title": "Carving on the Rim",
		"source": "Cut into a slab of the north rim",
		"text": "A row of carved figures along the edge of the slab, worn but clear. Tall, thin shapes holding up a crystal between them. Below them, smaller figures in a line, each one with its arms bound behind it.\n\nThe line of small figures leads east, along the rim, towards the gorge.",
	},
	# ---- Glowmire Caverns
	"caverns_survey": {
		"title": "Cave Survey Recorder",
		"source": "Helmet recorder, caught on a root",
		"text": "K-7 survey, cave team. The fungi light up when you talk. Loud voices, brighter caps. Elan thinks they're feeding off the sound. I think they're passing it on.\n\nIf they're passing it on, who's listening?\n\n[the recorder picks up a long, slow clicking from deeper in, then nothing]",
	},
	"caverns_cocoons": {
		"title": "Field Notes, Torn",
		"source": "Half a datapad, wedged between rocks",
		"text": "...husks hanging from the ceiling in the big chamber. Big enough to hold a person. All of them open, all of them empty.\n\nThe threads aren't silk. They're crystal, grown in neat, even rows. Nothing grows like that on its own.",
	},
	# ---- Rimefall Plateau
	"plateau_relay": {
		"title": "Coalition Relay Buffer",
		"source": "Frozen comm relay",
		"text": "AUTO-RELAY 9. Buffer holds one message, repeated.\n\n'All Coalition units on Kethra, this is fleet command. The HALCYON is overdue. The K-7 beacon is dark. Do not attempt a landing in force until the beacon is restored. Repeat, do not...'\n\nThe relay's antenna is iced solid. It has been sending this to nobody for weeks.",
	},
	"plateau_sledge": {
		"title": "Sledge Driver's Log",
		"source": "Datapad, frozen survey sledge",
		"text": "Day 4 on the plateau. The cold isn't natural. The crystals up here frost over from the inside, then crack.\n\nThe big one by the ridge stands up when it hears the engine. I've started walking the last kilometre.\n\nPicked up a droid leg in the snow this morning. Ascendancy make. Something had chewed the joints. Left it where it was.",
	},
	# ---- Sunken Mire
	"swamp_pod": {
		"title": "Escape Pod Beacon",
		"source": "Half-sunk escape pod",
		"text": "ORLA'S PROMISE, POD 2. Two aboard.\n\n'Day 1. Landed soft, for once. Water to the knees. Jory's leg is bad.\nDay 3. Lights out on the water at night. Jory says they're fireflies.\nDay 4. Jory's gone. The pod hatch was opened from outside. I never heard a thing.'\n\n[no further entries]",
	},
	"swamp_cages": {
		"title": "Root Cages",
		"source": "Your own notes",
		"text": "Cages, woven from living root and lashed with crystal thread, half under the water. Big enough for a person to sit in, not stand.\n\nThe doors are tied open. There are scratch marks on the inside of the bars.",
	},
	# ---- The VIGILANT
	"vigilant_bridge": {
		"title": "VIGILANT Bridge Recorder",
		"source": "Bridge console, still on emergency power",
		"text": "ASC CRUISER VIGILANT. Escort for the K-7 advance teams.\n\n'Low orbit, deploying supply pods to K-7. The spire field below us is pulsing in sequence, west to east, like a wave coming our way.\nHelm, take us up. Take us UP.\nAll decks, brace. Main drive is gone. Secondary is gone. Everything is...'\n\nThe recorder loops back to the start.",
	},
	"vigilant_quarters": {
		"title": "Crew Locker Note",
		"source": "Note in a crew locker",
		"text": "If you're reading this, you're Ascendancy, or you're a looter. Either way, the armoury on deck two is sealed, and the code died with the quartermaster.\n\nThe ones who made it out walked south. We heard them for a day on the comms. Then we heard clicking on the channel instead.",
	},
	"vigilant_hangar": {
		"title": "Hangar Deck Log",
		"source": "Deck officer's datapad",
		"text": "Hangar two. Drop pods 1 to 20 away before the power died. The Strider in pod 14 was the last one we had.\n\nSince we came down, things come in through the torn bow at night and take what's left. They don't take weapons. They take people, and they take machines.",
	},
	# ---- The Vaari temple
	"temple_mural": {
		"title": "The Great Wall Carving",
		"source": "Carved along the temple's great hall",
		"text": "The carving runs the length of the hall. Crystal spires rising out of a forest, with lines of light running between them. Ships falling out of the sky above them, drawn as broken birds.\n\nAt the end: tall figures leading smaller ones down into the earth, under the spires. The small ones are drawn with helmets.\n\nThe carving looks old. The helmets look new.",
	},
	"temple_cradles": {
		"title": "The Holding Room",
		"source": "Your own notes",
		"text": "A row of stone cradles, tilted back, each with cuffs grown out of crystal. Wide enough for a human. The cuffs are open.\n\nScratched into the side of the nearest one, small and careful, in standard script: K-7. 6. Then five marks crossed through.",
	},
	"temple_k7": {
		"title": "K-7 Survey Tablet",
		"source": "Datapad, hidden behind a brazier",
		"text": "If anyone from K-7 finds this. They brought us here first. Not to hurt us. They measured us. Held our hands up to the crystal and watched it light.\n\nThen they took Tomas somewhere deeper, under the big spires. They do the real work there, I think.\n\nThe crystal hums when they talk. I'm hiding this behind the fire. They don't come near the fire.",
	},
	"temple_sanctum": {
		"title": "The Crystal Heart",
		"source": "The temple's inner sanctum",
		"text": "A heart of spire crystal as tall as a man, set on a stepped dais under the temple. It pulses, slow and even. Every few seconds the lines in the walls answer it.\n\nYour helmet comm clicks once each time it pulses. Whatever this is, it's part of the network that brought the ships down. And something is still listening at the other end.",
	},
}


static func entry(id: String) -> Dictionary:
	return ENTRIES.get(id, {})
