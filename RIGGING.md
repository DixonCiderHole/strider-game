# Rigging notes (playable characters)

Analysis of the current models (Nov 15, 2026). **Nothing here has been changed
in the game yet.** It's a record of why the current rigs misbehave, so the new
rigs (mainman / mainlady) go in cleanly.

## 1. "Randomly stretches, fixed only by reloading": cause found in code

`scripts/player.gd` edits bones every frame with `skeleton.set_bone_global_pose()`:
- `_twist_spine()`: upper body follows the camera (aiming / looking around)
- `_seat_legs()`: legs forward when sitting
- the sleeping/cot pose path

`set_bone_global_pose` writes the bone's *whole* transform (rotation, position
and scale) into its stored pose. The animations only overwrite rotations: in
`_fit_to_body()` every scale track, and every position track except the hips,
is deliberately removed. So position and scale on those bones are never
reset. Tiny floating-point errors from the world/skeleton conversions (worse on
skeletons with unit scaling, e.g. her FBX imported at 107x) build up frame after
frame. Eventually a limb visibly stretches, and only rebuilding the skeleton
(a reload) puts it right. Arms stretch too because they hang off the twisted
spine bones.

**Fix for the new rigs (when approved):** apply these tweaks as rotation only,
e.g. `set_bone_pose_rotation()`, or a SkeletonModifier3D, which is re-applied
fresh each frame and never stored. Alternatively reset each bone's position and
scale to its rest every frame before the tweak. Also keep (or rebuild from rest)
position/scale tracks so the pose is fully defined each frame.

## 2. Arms bending / deforming: causes

1. **Animations from a different body than the mesh.** The animations were
   downloaded from other Mixamo characters (the crouch files even carry a
   whole other character's mesh; the code comments say "animations made on
   another body"). Mixamo rotations are relative to the skeleton they were
   made on. Played on a skeleton whose bones point or twist slightly
   differently, the arms (the longest chain, with the most twist) bend and
   twist wrong. Her rig even had to borrow his idle because her file only had
   a one-frame T-pose.
2. **Accumulating bone edits** (section 1) stack on top while aiming.
3. **Mixed units:** her FBX is in centimetres (scaled 107x in game), his in
   metres. Mismatched scales make hip-height corrections necessary and amplify
   drift.

## 3. Rules for the new rigs (mainman.glb / mainlady.glb)

- Rig each model once in Mixamo, then download **every** animation from **that
  same character** (T-pose "With Skin" once; animations "Without Skin", FBX
  Binary, 30 fps, In Place for locomotion). Never mix animations from another
  character.
- Same units for both (Mixamo exports in centimetres; handle it the same way
  for both).
- Fix the bone-edit code (section 1) at the same time the new rigs go in.
- Mixamo marker placement and model prep: see the research section below.

## 4. Research: Mixamo auto-rig best practice

Sources: Adobe Mixamo help (helpx.adobe.com/creative-cloud/help/mixamo-rigging-animation.html),
Tripo3D "rig an AI-generated character for Mixamo" guide, Adobe community threads.

**Upload**
- Formats: FBX (with embedded media), OBJ, or a ZIP of .obj + .mtl + textures
  (an OBJ alone shows up grey).
- One clean mesh: no duplicate vertices, no loose bits or hidden inner faces.
  Facing forward (+Z), feet on the ground, about 1.7-2 m tall.
- Lighter is better (about 50k vertices or less); Meshy output is ~60-70k, which is OK.
- T-pose, arms horizontal. If limbs stretch after rigging, the pose is usually to blame.

**Markers (front view, zoom in: ~1 cm errors show up in animation)**
- CHIN: tip/centre of the jaw, not on the neck.
- WRISTS: centre of the wrist joint, where the hand meets the forearm.
- ELBOWS: centre of the elbow bend (middle of the arm's thickness).
- KNEES: centre of the knee joint (front view: middle of the leg).
- GROIN: centre of the crotch / hip joint line, between the legs.
- Keep "Use Symmetry" on for a symmetrical model (place one side, it mirrors).
- If a result is poor, nudge the markers 2-3 cm and re-rig.

**Skeleton LOD**
- Standard (65 bones, full fingers) only if the fingers are separate in the mesh.
- Fused or mitten-like fingers: 2-chain or 1-chain fingers to stop hands crumpling.
- The game finds the palm from the wrist and the middle-finger knuckle, so keep at
  least the first finger joint (any option except "No Fingers").

**Check before accepting (Mixamo preview)**
- Idle, a walk, a rifle aim, and something with the arms raised.
- Look for: elbows bending the right way, no stretching at the armpits or
  shoulders, wrists not twisting, no clothing/armour tearing, hands closing cleanly.

**Download**
- Character: FBX Binary, T-pose, With Skin.
- Animations: FBX Binary, Without Skin, 30 fps, keyframe reduction none,
  In Place for locomotion. All from the same rigged character.

## 5. New rig results (Nov 15, 2026)

**mainman** (files in `Downloads\rig_v2\mainman\`):
- Markers (metres): chin 1.547 (Matt's spot), wrists ±0.555 @1.487, elbows ±0.375 @1.473,
  knees ±0.108 @0.62, groin 0.92 on the groin piece (Matt's spot).
- Skeleton: 2 Chain Fingers selected, but Mixamo dropped the thumb (it can't see a
  separate thumb on his gauntlets): 33 bones, finger chain = `*HandIndex1-4`.
  Palm detection must use `HandIndex1` (no `Middle1`, no thumb).
- Mixamo snaps the neck/head joints itself; moving the chin marker 3 cm changed nothing
  (Neck 1.553 m, Head 1.577 m every time).
- All 13 animations downloaded from this same rig; each checked: 0 bone offset
  differences vs the model, no mesh inside.
- **Helmet fix:** Mixamo weighted the bottom ~5 cm of the helmet (1.55-1.60 m) to the
  upper spine, so it smeared when the head turned (his rifle idle turns the head ~43 deg).
  `mainman_helmetfix.fbx` cuts the helmet off the body along its rim (339 seam vertices
  duplicated), locks every helmet vertex 100% to `mixamorig:Head`, and closes both
  openings with dark caps (helmet cap rides the head, body cap rides Spine2), so a turn
  shows a dark neck under the rim instead of stretched faces. Body weights are
  Mixamo's own minus the head. Use this file, not `mainman.fbx`, when integrating.
  Tested to 55 deg turn + 20 deg tilt: no stretching; at extreme tilt the chin piece
  dips into the chest top, as rigid armour would.

**mainlady** (files in `Downloads\rig_v2\mainlady\`): chin 1.679, groin 0.976, wrists
±0.661 @1.508, elbows ±0.45 @1.512, knees ±0.144 @0.63. 41 bones incl. thumbs.
13 animations from her own rig, all checked against her skeleton.

## 6. In the game (Nov 16, 2026)

- `models/player_v2/`: `mainman.fbx` (helmet fix), `mainlady.fbx`, and each one's
  13 animations in `mainman_anims/` and `mainlady_anims/`.
- `player.gd` `V2_RIGS`: trooper -> mainman, survivor -> mainlady. Loaded by
  `_load_rigged_v2()`; every track of their own clips is kept (no `_fit_to_body`).
  Scaled by exactly 100 (Mixamo labels metres as cm), so both keep real heights
  (1.82 m / 1.90 m). If a v2 file is missing, the old rig loads instead.
- Bone tweaks (spine twist, seated legs) now go through `_rotate_bone()`, which
  sets rotation only: the stretching bug can't build up any more.
- Palm knuckle: `*HandMiddle1`, falling back to `*HandIndex1`.
- Not changed: the ally NPC (`ally.gd`) still uses `femalelead_rigged.glb`.
- Prone (Nov 16): 6 clips per character from their own rigs (`prone_idle`,
  `prone_forward`, `prone_back`, `prone_turn_left/right`, `prone_fire`). Mixamo has
  no sideways crawl, so left/right turn on the spot. Z toggles prone; Space or
  sprint gets up; C goes to crouch. His were downloaded by uploading
  `mainman_helmetfix.fbx` itself to Mixamo (rigged FBX = no auto-rig, exact skeleton).
