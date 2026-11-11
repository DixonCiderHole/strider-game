STRIDER GAME - tutorial level (first playable)

How to play
  1. Open Godot 4.7, click "Import", pick this folder's project.godot, then "Import & Edit".
  2. Wait for Godot to finish importing the models (first time only).
  3. Press F5 (or the Play button, top right).

Controls
  WASD          walk / strafe
  Shift         run (forwards)
  Mouse         aim / look
  Left click    fire (works while walking)
  Right click   aim down sights
  Space         jump
  Esc           pause menu (resume, restart, settings, main menu, quit)

Droid companion (comes online after wave 1)
  1             follow me
  2             hold position
  3             go to the spot under the crosshair, or attack the creature under it
  4             weapons free / hold fire

What's in it
  - Your trooper (models/maincharacter.glb) with the blaster (models/blaster.glb)
  - A forest clearing with your crashed ship
  - 3 waves of native creatures (models/creature_rigged.glb: roar, run, blade slashes, cross slash, pounce, flinch, death)

Files
  scripts/main.gd    level, forest, crash site, wave system
  scripts/player.gd  movement, camera, shooting, health
  scripts/enemy.gd   creature behaviour and placeholder body
  scripts/hud.gd     health bar, wave counter, messages
  scripts/bolt.gd    blaster bolt effect
  scripts/util.gd    shared helpers

Quick tweaks (select nothing, just edit the numbers at the top of the script)
  player.gd  walk_speed, sprint_speed, damage, fire_interval
             model_yaw_offset_deg   -> if the trooper faces backwards
             blaster_yaw_offset_deg -> if the blaster points the wrong way
  main.gd    WAVES := [3, 5, 8]     -> creatures per wave
