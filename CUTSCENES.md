# Strider cutscene style (SWTOR-inspired)

Matt wants story cutscenes done in the style of Star Wars: The Old Republic's
conversation cinematics. Nothing is built yet: Matt says when a cutscene is
needed. Use this as the base for every one.

## Matt's decisions (Nov 2026)

- **Line pacing:** a setting in Options. Default auto-advance (each line holds
  for its reading time); toggle for "press to continue".
- **No dialogue choices.** Scenes play out as written; no dialogue wheel.
- **Subtitles:** one line, `NAME: text`, with the name in the speaker's colour.
- **His name:** shows as `YOU` until the story reveals it (she asks at the fire).
- **Helmet stays on** in cutscenes for now (a face reveal could be a later trust moment).
- **Old text-card scenes** (crash, ambush, rescue, escape) stay as they are
  until Matt asks for each one to be redone in this style.
- **Skipping:** a scene can only be skipped once you've seen it (replays).
- **Name colours (faction):** YOU in Ascendancy red, SURVIVOR/ILSA in
  Coalition orange-white, STRIDER in droid blue, Vaari in crystal cyan.
- **"Seen" for skipping** counts across all saves (kept outside the save slots).
- **World during a scene:** safe. Creatures hold off/freeze and nobody can be hurt.
- **Audio:** Matt may do voice acting; he'll say what each scene needs.
  Don't decide music or ambience for a scene on your own.

## Look and feel

- **Cinematic mode:** gameplay HUD hidden. Black letterbox bars slide in at the
  top and bottom (about 10-12% of the screen each) as the scene starts and slide
  out at the end.
- **Opening shot:** a wide two-shot (or establishing shot of the place),
  usually with a slow push-in, so the player sees where everyone stands.
- **Shot / reverse shot:** cut to whoever is speaking. Default framing is a
  medium close-up over the listener's shoulder, the speaker slightly off
  centre, background softly out of focus (depth of field).
- **Camera motion:** gentle. A slow drift or push-in during a line; clean cut
  on a speaker change. No shaky cam.
- **Acting:** characters face each other; idle gestures on key lines
  (crossed arms, hand gesture, head tilt, glance away).
- **Lighting:** a warm key light on faces where possible (campfire, lamps),
  rim light to separate them from the background.
- **Pacing:** each line holds for its reading length plus a beat. Scenes end
  with a short fade back to gameplay.

## Subtitles (required)

- Text appears on screen whenever someone speaks, **with the speaker's name**.
- Bottom centre, just above the lower letterbox bar.
- One line: `NAME: text`. Name in the character's colour, dialogue in white,
  on a soft dark backing for readability.
- Names follow LORE.md (e.g. SURVIVOR until she introduces herself, then ILSA;
  STRIDER for the droid; YOU for the player).

## Controls

- Space / click: next line (or advances early in auto mode).
- Esc: skip the scene, only if you've seen it before.
- No player choices.

## Current state (for reference)

- `scripts/cutscene.gd`: story cutscenes are white text cards on black
  (leave_crash, ambushed, rescued, escaped).
- `scripts/base.gd` TALK: the fireside talk is a text box over gameplay.
- `scripts/dialogue_box.gd`: banter text box.
