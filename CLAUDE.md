# Strider: notes for Claude

- **Story/lore:** read `LORE.md` before writing any dialogue, datapad, banter or quest text.
- **Asset quality bar:**
  - Every asset must match or exceed the environment and character models.
  - Sci-fi and futuristic.
  - No primitive "cube" models.
- **Asset generators:**
  - `tools/assetgen/*.py` write the `.glb` models.
  - After changing a model, open the Godot editor so it re-imports before
    running with F5.
- **Cutscenes:** follow `CUTSCENES.md` (SWTOR-style: letterbox, speaker shots,
  subtitles with the speaker's name). Only build one when Matt asks for it.
- **Banter system:** built (`scripts/banter.gd`). Add new lines there, following `LORE.md`.
- **Quests:** future quests may start by talking to someone or by interacting
  with an object.
- **World map / areas:**
  - Keep one world map where no two areas overlap.
  - Areas are separate sections. Where section A's exit path leads to
    section B, B's spawn entrance path must line up with it (same direction
    and position on the world map). Players move between areas through an
    interact prompt ("go to next area").
  - This is groundwork for a teleport system later.
- **Git:**
  - Matt decides when to push to GitHub. Never push unprompted.
  - Push through GitHub Desktop on his PC.
