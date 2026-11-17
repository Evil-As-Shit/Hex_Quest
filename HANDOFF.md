# HexQuest: handoff to Claude Code

This summarises a long working session so a fresh Claude Code session can continue without re-deriving anything.
Everything below was verified by actually running Godot 4.2.2 unless marked **(unverified)**.



## 1. Quick start for the new session

**Paste this as your first message in Claude Code:**

> Read `HANDOFF.md` in the repo root, then run the three test suites (commands in section 7) to confirm the
> project is healthy. Don't change anything yet. Tell me what passed and what you'd suggest tackling first
> from section 9. Delegate easier tasks to agents with an appropriate model and effor to save on usage. Limit
> the number of agents running at one time to an appropriate level (less than 5).

## 2. The project

* **HexQuest**: a 2D pixel-art game in **Godot 4.2.2**, GDScript, **GL Compatibility** renderer, 1080x720 viewport
  stretch, nearest texture filtering. Repo: `github.com/Evil-As-Shit/Hex_Quest`.
* Player character is **Hexy** (pronouns unknown: **use neutral wording** in comments and docs).
* Playable scenes: `The Game/2 - The Apartments/The Apartments.tscn` and `The Game/1 - TheSat/Scenes/the_satellite.tscn`.
* Indentation is **tabs only** in every `.gd` file. Mixed tabs/spaces is a parse error. Check with
  `grep -rnP "^ +\S" Scripts addons`.

## 3. Architecture (as it is now)

### Autoloads (order matters, set in `project.godot`)
`SignalController` (event bus) -> `GameData` (shared state, loads dialogue) -> `SaveManager`.

* `GameData` loads `res://Assets/dialogue.txt` itself in `_ready()` via a **`preload`** of `DialogueParser.gd`
  (not the global class name, so a fresh clone works before Godot builds its class cache).
* All signals in `SignalController` are declared with parameters and fired with `.emit()`. Never `emit_signal("...")`.

### Input and interaction flow
`InputController` (uses input *actions*: `interact` = E, `phone` = Q, `move_*`, `ui_cancel` quits via
`SaveManager.quit_game()`) -> `SignalController.interaction_check` -> `Hexy.interact_nearby()` does a point query on
physics layer "objects" -> finds the `Object_Id` **Area2D** -> calls `.interact(player)` on its **parent**.
Everything interactable extends `Scripts/Objects/Interactable.gd` (`NPC.gd`, `Chair.gd`, `Lamp.gd`) and overrides
`_interact(player)`. There is no instance-id matching any more.

### Physics layers (bit values, as used in code and scenes)
`2` = areas (rooms), `4` = objects (and `Object_Id` areas), `8` = walls.

### Dialogue
* Data: `Assets/dialogue.txt`, valid JSON `{"dialogue": [ {...}, ... ]}`.
* Entry keys, always in this order: `id`, `tagRequired`, `text`, `expression`, `tagAdd`, then **one of**
  `isEnd: true` / `divert: "<id>"` / `choices: [a, b]` + `choice_0: [ids]` + `choice_1: [ids]`.
  `expression` is a portrait filename without `.png` in `Assets/ui/Avatars/`, or `null`.
* **Rule:** wherever a *list* of ids appears (an object's `dialogue_ids`, a `choice_N`), the game shows the **first**
  id whose `tagRequired` is met (an entry with no `tagRequired` always passes). Anything after an unconditional entry
  can never show.
* Tags are a `Dictionary` used as a set (`GameData.add_tag / has_tag`). Typewriter text is a tween
  (`Scripts/UI/DialogueBox.gd`). The dialogue box has exactly **2** choice buttons.

### Room reveal (hidden until entered, permanent)
* `Scripts/Room.gd` (`class_name Room`) sits on the room's `Area2D`. `reveal_nodes: Array[NodePath]` lists the room
  sprite plus every object inside it. Hexy tells the room directly (`area.on_player_entered`) when its position
  moves into that area (point query, only when moving).
* Hidden state = a **per-room** `ShaderMaterial` using `Assets/Shaders/pixel_reveal.gdshader` (uniforms `reveal`
  0..1, `block_size`). After the fade the material is removed, so there is no ongoing cost.
* Objects stay in the `YSort` node (needed for depth sorting), so the `reveal_nodes` list is what ties them to a room.

### Save/load (`Scripts/SaveManager.gd`)
* One file: `user://savegame.json` (atomic write via temp file + rename). F5 save, F9 load, F10 delete + new game
  (debug builds only). Autosave on room reveal and on quit. The last save loads automatically on start, **only if it
  belongs to the running scene**.
* Contract: a node joins group `SaveManager.GROUP` ("persist") and provides `get_save_id()`, `save_state()`,
  `load_state(dict)`. Currently: Hexy, every `Room`, `Lamp`; plus `GameData.dialogue_tags`.
* Saving is **off** unless the scene contains a `GameController` node (which calls `SaveManager.register_scene()`).
  This keeps test scenes from overwriting the real save.
* `SaveManager.save_path` is a var so tests can redirect it.

### Editor plugin: `addons/hexquest_tools/`
A "HexQuest" main-screen tab (Dialogue / Objects / Scene & Rooms / Problems) plus an Inspector editor for
`dialogue_ids`. Layout:

```
hq_config.gd      every project-specific path / script name (edit here if folders move)
hq_context.gd     static shared state: the one DialogueDB, editor access, scene_root_override for tests
core/             engine-independent logic, tested headless:
  dialogue_db.gd, validator.gd, dialogue_metrics.gd, scene_scanner.gd, object_factory.gd, scene_tools.gd
ui/               all UI built in code (no .tscn): main_screen, dialogue_tab, object_tab, scene_tab,
                  problems_tab, region_picker, object_preview, id_list_editor, dialogue_picker,
                  conversation_dialog, dialogue_ids_property, inspector_plugin
tests/            core_test.gd, ui_test.gd
```
Design decisions worth keeping: every addon script is `@tool`; the addon **never uses `class_name`** and refers to
other addon scripts with `preload`; `DialogueDB.save_file()` round-trips the real file **byte-for-byte**;
rename-id edits `.tscn` files as text and the editor then prompts to reload.

## 4. What was done, in order

1. **Optimisations pass:** fixed `object_interacted` (missing `break`, so every untagged line fired); tags became a
   set (they were duplicated on every re-read); tween typewriter; Hexy only queries location when moving, caches
   facing, derives `is_sitting` from state; Phone uses a tween; input uses actions + `Input.get_vector`;
   dialogue loaded once; portraits preloaded; `dialogue.txt` made valid JSON (real booleans / `null`);
   Compatibility renderer; vsync on; `.gitignore` updated; stray `.kra` autosave removed; `NPC.gd` and `Chair.gd`
   moved to `Scripts/Objects/` (and the path fixed in `the_satellite.tscn`).
2. **Room reveal + save/load** (sections 3).
3. **HexQuest Tools plugin** (section 3), including a project-wide validator.

## 5. Gotchas learned the hard way (please don't relearn these)

**GDScript / Godot 4.2**
* `_set` and `_get` are reserved Object virtuals. Do not name your own methods that.
* `:=` fails to infer from a dynamically typed value (e.g. `var x := some_untyped_call()`). Annotate the type.
* `JSON.stringify(data, "\t", false)`: the third argument must be `false` or keys get alphabetised.
* `Label.get_line_count()` is only right a frame after the label is in the tree. For synchronous text measurement
  use `font.get_multiline_string_size(...)` (see `dialogue_metrics.gd`).
* Changing a `CollisionShape2D.disabled` should use `set_deferred` (can't change during physics flush).
* `get_children()` has no recursion flag in 4.2. Write a recursive helper. `find_children(..., owned=false)` is needed
  to see inside instanced scenes.
* New `class_name` scripts are only registered in `.godot/global_script_class_cache.cfg` after an editor/import scan.
  Autoload scripts must not depend on that cache (hence the `preload` in `GameData`).
* `AnimatedSprite2D.stop()` resets the frame. Lamp uses `pause()` after setting the frame to hold an end state.

**Headless `-s` test scripts**
* The main script of `godot -s x.gd` compiles **before autoloads exist**: fetch them with
  `root.get_node("SaveManager")`, and do not reference game `class_name`s or autoload identifiers in that file.
* `Input.parse_input_event` is not delivered in headless mode. Use `root.push_input(event)`.
* A scene added manually needs `current_scene = scene`, or `SaveManager.save_game()` returns false.
* `--check-only` on a single script can't see autoloads. Judge parse errors by running the scene instead.

**Editor plugins**
* Selecting a `Node2D` (for example after placing one) makes Godot switch to the 2D view. Screenshots/tests must
  switch back with `set_main_screen_editor("HexQuest")`.
* Popup dialogs are separate OS windows, so they do not appear in viewport screenshots.
* Load spritesheets lazily (when the tab is first shown): on a fresh clone plugins start before imports finish.
* Property changes on a node **inside an instanced scene** (e.g. Room2's `reveal_nodes`, Room2 being
  `Scenes/Rooms/Room2.tscn` placed in The Apartments) are silently dropped on save unless "Editable Children" is on
  for that instance. The plugin's room-assign paths call `SceneTools.add_make_editable()` to turn it on (undoably).
  Anything new that edits instanced children must do the same.

## 6. Environment notes for verification
* The session had a Linux sandbox with Godot 4.2.2 (downloaded from the official GitHub release) and
  `xvfb` + Mesa software GL, which allowed real rendering/screenshots and running the real editor.
  On the user's machine just use their installed Godot 4.2.x.
* Rendering test pattern: `xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --windowed --resolution 1080x720 -s <script>`, where the script saves
  `root.get_viewport().get_texture().get_image()` to PNG after some frames.
* Editor test pattern: copy the project to a temp dir, add a throw-away `@tool` EditorPlugin (not shipped) that waits a
  few seconds, then drives the HexQuest panels, takes screenshots, writes a log and calls `get_tree().quit()`;
  launch with `godot --editor --path <tmp>` under `xvfb-run`. Never run this against the real project.

## 7. How to run the tests
From the project root (replace `godot` with your Godot 4.2 executable). First open the project in the editor once,
or run `godot --headless --import`.

```
godot --headless -s res://Tests/smoke_test.gd                              # reveal, interactions, dialogue, save/load
godot --headless -s res://addons/hexquest_tools/tests/core_test.gd         # DialogueDB, validator, factory, scene tools
godot --headless -s res://addons/hexquest_tools/tests/ui_test.gd           # drives the tool panels
```
Each prints PASS/FAIL lines and exits non-zero on failure. All three passed at the end of the session, also from a
wiped `.godot/` cache. One `ERROR: SaveManager: save file is corrupt` line in the smoke test is **expected** (it
deliberately writes a corrupt save). Tests use their own save/dialogue files and clean up after themselves.

## 8. Known issues and data problems
* **Broken dialogue data:** `NPC005` has `divert: "NPC006"` but `NPC006` doesn't exist (the Problems tab reports it).
* Tags required but never set by any line: `FIRST_SOUL_COMPLETED` (ITM021, NPC010) and `PHONE_CHARGE_ZERO` (NPC002).
  Fine if code sets them, otherwise those lines never show.
* Two Godot-generated `.import` files are untracked in the repo (`hexy stand.png.import`,
  `witch_confused.png.import`). Commit them or ignore them, the user hasn't decided.
* Dialogue-tab edits (delete, duplicate, text) are **not undoable**; Reload from disk or git is the escape hatch.
* Creating a conversation saves `dialogue.txt` immediately, including other pending edits (by design).
* Only 2 choices per question (the dialogue box has 2 buttons).
* **(unverified)** Windows/macOS behaviour, exported builds (needs `*.txt` in the export filter so
  `dialogue.txt` ships), and 2D movement smoothness on >60 Hz displays (Godot 4.2 has no 2D physics interpolation;
  Hexy moves in `_physics_process` at 60 Hz).

## 9. Suggested next steps (pick with the user)
1. Fix `NPC005 -> NPC006` and decide what to do about the unset tags.
2. Main menu / Continue button using `SaveManager.has_save()` and `load_game()` (scene-change loading is
   implemented but only lightly exercised).
3. More rooms and objects using the Objects tab; wire `TheSat` into the same flow if it should share the save.
4. Save slots, and showing the "saved at" timestamp (already stored in the save file).
5. Plugin ideas: undo for the dialogue tab, a dialogue graph view, >2 choices (needs a DialogueBox change),
   tag usage warnings that understand code-set tags.
6. Export testing, and 2D smoothness on high-refresh monitors.

## 10. How the user likes to work
* Wants things done and **verified**, with plain-English explanations of what changed and why.
* Asks for broad improvements ("anything else useful") and then expects them built, not just suggested.
* Deliverables so far were a `.patch` plus a zip of changed files. In Claude Code, prefer small commits instead.
* Repo conventions to match: tabs, short explanatory comments, `snake_case` files in `Scripts/`, existing
  mixed-case names left alone, `The Game/<n> - <Name>/` folders for levels.

---

## Appendix: ready-to-paste `CLAUDE.md`
Save the block below as `CLAUDE.md` in the repo root. Claude Code reads it automatically at the start of every session.

````markdown
# HexQuest (Godot 4.2.2, GDScript, GL Compatibility)

## Rules
- Tabs only in .gd files. Use typed signals: `SignalController.x.emit(...)`, never `emit_signal("x")`.
- Use input actions (`interact`, `phone`, `move_*`), never hard-coded keys.
- Neutral wording for Hexy (pronouns unknown).
- Autoload scripts must not depend on global `class_name`s (use `preload`).
- Addon scripts (`addons/hexquest_tools`) are `@tool`, never use `class_name`, and use `preload`.
- Don't name methods `_set` / `_get`. Annotate types when `:=` can't infer.

## Architecture in one paragraph
Autoloads: SignalController -> GameData -> SaveManager. E key -> `interaction_check` -> `Hexy.interact_nearby()` finds an
`Object_Id` Area2D (physics layer 4) and calls `.interact()` on its parent (all extend `Interactable`). Dialogue lives in
`Assets/dialogue.txt` (first entry in an id list whose `tagRequired` is met wins). Rooms (`Room.gd` on an Area2D, layer 2)
hide `reveal_nodes` behind a per-room pixel-dissolve shader until Hexy enters, and stay revealed. Saving is one JSON
file via `SaveManager`; saveable nodes join group "persist" and implement `get_save_id/save_state/load_state`; a scene
only saves if it contains a `GameController`.

## Verify before finishing any change
    godot --headless -s res://Tests/smoke_test.gd
    godot --headless -s res://addons/hexquest_tools/tests/core_test.gd
    godot --headless -s res://addons/hexquest_tools/tests/ui_test.gd
(One "save file is corrupt" error line in smoke_test is expected.) In `-s` test scripts, fetch autoloads via
`root.get_node(...)`, use `root.push_input()` for input, and set `current_scene`.

## Update HANDOFF.md with any relevent information needed for future use.
````
