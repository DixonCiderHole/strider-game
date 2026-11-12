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
	},
}


static func entry(id: String) -> Dictionary:
	return ENTRIES.get(id, {})
