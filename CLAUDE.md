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
- **Banter system:** built (`scripts/banter.gd`). Add new lines there, following `LORE.md`.
- **Quests:** future quests may start by talking to someone or by interacting
  with an object.
- **Git:**
  - Matt decides when to push to GitHub. Never push unprompted.
  - Push through GitHub Desktop on his PC.
