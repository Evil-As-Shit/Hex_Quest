# HexQuest: handoff to Claude Code

This summarises the working sessions so far so a fresh Claude Code session can continue without re-deriving anything.
The project was built on Godot 4.2.2 and has since been **upgraded to Godot 4.7** (the user's editor is 4.7.2 from
Steam). Everything below was verified by running Godot unless marked **(unverified)**; the 4.2-era notes in section 5
were found on 4.2 and may or may not still apply on 4.7.



## 1. Quick start for the new session

**Paste this as your first message in Claude Code:**

> Read `HANDOFF.md` in the repo root, then run the three test suites (commands in section 7) to confirm the
> project is healthy. Don't change anything yet. Tell me what passed and what you'd suggest tackling first
> from section 9. Delegate easier tasks to agents with an appropriate model and effor to save on usage. Limit
> the number of agents running at one time to an appropriate level (less than 5).

## 2. The project

* **HexQuest**: a 2D pixel-art game in **Godot 4.7** (`config/features` in `project.godot`; scene files use the
  4.6+ format with `unique_id=`, so don't open them in an older editor), GDScript, **GL Compatibility** renderer, 1080x720 viewport
  stretch, nearest texture filtering. Repo: `github.com/Evil-As-Shit/Hex_Quest`.
* Player character is **Hexy** (pronouns unknown: **use neutral wording** in comments and docs).
* Startup scene: `The Game/0 - Main Menu/Main_Menu.tscn` (project main scene). New Game starts
  `The Game/1 - TheSat/Scenes/the_satellite.tscn`; the other level is `The Game/2 - The Apartments/The Apartments.tscn`.
* Indentation is **tabs only** in every `.gd` file. Mixed tabs/spaces is a parse error. Check with
  `grep -rnP "^ +\S" Scripts addons`.

### Folder layout (reorganised in session 2; put new files where they belong)
```
Assets/
  Data/dialogue.txt            dialogue database (the tool edits it)
  Shaders/                     pixel_reveal.gdshader
  Source/                      .aseprite source files
  Sprites/Characters/          Hexy, NPC sprites
  Sprites/Objects/             Objects_Spritesheet (+ _Old: older sheet, the Lamp still uses 3 frames from it)
  Sprites/Environments/        room/level spritesheets
  UI/Dialogue/  UI/Phone/      UI art
  UI/Portraits/                one .png per dialogue expression (Sheets/ = source sheets, ignored by the game)
Scenes/Characters/  Scenes/Objects/  Scenes/Rooms/  Scenes/UI/
Scripts/Autoload/              SignalController, GameData, SaveManager
Scripts/Core/                  GameController, InputController, DialogueController, DialogueParser
Scripts/Characters/  Scripts/World/ (Room.gd)  Scripts/Objects/  Scripts/UI/
Tests/                         smoke_test.gd (_tmp/ is created and removed by core_test)
The Game/<n> - <Name>/         one folder per level (its own scene, level-only scripts and art)
addons/hexquest_tools/         the editor plugin; its paths are all in hq_config.gd
```
Moving files: close the editor (or move them inside the editor, which updates references). From outside, use `git mv`
(with the `.import` / `.uid` sidecars) and rewrite `res://` paths in .tscn/.gd/.godot/.import files; then run
`godot --headless --import` twice (the first scan may log stale autoload errors) and the test suites. Watch out for
case-only renames on Windows (git has `ignorecase` on): go through a temporary name.

## 3. Architecture (as it is now)

### Autoloads (order matters, set in `project.godot`)
`SignalController` (event bus) -> `GameData` (shared state, loads dialogue) -> `SaveManager`.

* `GameData` loads `res://Assets/Data/dialogue.txt` itself in `_ready()` via a **`preload`** of `DialogueParser.gd`
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
* Data: `Assets/Data/dialogue.txt`, valid JSON `{"dialogue": [ {...}, ... ]}`.
* Entry keys, always in this order: `id`, `tagRequired`, `text`, `expression`, `tagAdd`, then **one of**
  `isEnd: true` / `divert: "<id>"` / `choices: [a, b]` + `choice_0: [ids]` + `choice_1: [ids]`.
  `expression` is a portrait filename without `.png` in `Assets/UI/Portraits/`, or `null`.
* **Rule:** wherever a *list* of ids appears (an object's `dialogue_ids`, a `choice_N`), the game shows the **first**
  id whose `tagRequired` is met (an entry with no `tagRequired` always passes). Anything after an unconditional entry
  can never show.
* Tags are a `Dictionary` used as a set (`GameData.add_tag / has_tag`). Typewriter text is a tween
  (`Scripts/UI/DialogueBox.gd`). The dialogue box has exactly **2** choice buttons.

### Tags as signals, and the phone battery
* `GameData.add_tag(tag)` ignores duplicates and emits `SignalController.tag_added(tag)`; `remove_tag(tag)` emits
  `tag_removed`. `load_state()` and `reset()` emit `tags_loaded` (all tags replaced at once). Systems that react to a
  tag listen to these signals; don't special-case tags inside `GameData`.
* **Dialogue hold:** `GameData.hold_dialogue()` keeps the current (non-choice) line on screen: interact can't skip it.
  `GameData.release_dialogue()` emits `SignalController.dialogue_released` and `DialogueBox` moves the line on (to its
  divert, or closes it). Closing dialogue or `reset()` clears a hold. Use it for any line that waits on something.
* **Phone battery** (`Scripts/UI/Phone.gd`). Nodes under `UI/PhoneControl`: `Battery` (level), `Battery_Charging`
  (the "Charging" animation drawn on top, only while charging) and `Phone_Bool` (covers the screen while the phone
  is off or turning on).
  * Levels in `charge`: 0 = "Ded", 1 = "Dying" (loops), 2..`max_charge` = "Charges" frames 0..8, so `max_charge` = 1 +
    the "Charges" frame count = 10. States are `Battery.DEAD / CHARGING / CHARGED / FULL` (0..3).
  * `add_charge(amount)` changes the level (negative drains). No gameplay drains it yet; for testing, **F6**
    (input action `debug_drain_battery`, debug builds only) drains one level.
  * Tags mirror the level for dialogue: `PHONE_CHARGE_ZERO` while dead (NPC002 needs it), `PHONE_CHARGE_FULL` only
    while full (so after draining, the charger offers to charge again). `PHONE_CHARGE` only while charging.
  * Charger flow: Charger `dialogue_ids` = `["ITM014", "ITM010"]`, so a full phone gets "already charged". ITM010 Yes
    -> ITM011 "Charging phone..." adds `PHONE_CHARGE`. The phone holds that line and shows `Battery_Charging`. Each
    loop raises `Battery` one level (Dying, then each Charges frame). The rise happens on sweep frame
    `charge_step_frame` (an export on PhoneControl, default 10, the frame whose sweep covers the whole battery), so
    the change is hidden. At max, once that loop ends, it hides the overlay, clears `PHONE_CHARGE` and releases
    the line, so ITM012 "Phone is Charged!!!" shows by itself. A full charge is 10 loops of 21 frames at 25 fps
    (about 8.4 s); tune the "Charging" speed in `Battery_Charging`'s SpriteFrames. If the sweep art is redrawn,
    re-check `charge_step_frame`.
  * Power: reaching 0 plays `Phone_Bool` "Turn_Phone_Off" once (`ANIM_OFF`) and leaves its black last frame up. Buttons are disabled with focus mode NONE; Q still opens and closes the phone. A charged phone
    stays off until it's next opened. Opening it plays "Turn_Phone_On" once, then `Phone_Bool` is hidden, the buttons
    are re-enabled and Home gets focus.
  * Saving: the phone is in the "persist" group (`get_save_id` "phone", saves `{"charge": n}`). Older saves without it
    fall back to the tags (full or dead). A save from mid-charge loads as dead and clears `PHONE_CHARGE` so charging
    can start again. On load the phone is simply on if it has charge, with no animation.

### Room reveal (hidden until entered, permanent)
* `Scripts/World/Room.gd` (`class_name Room`) sits on the room's `Area2D`. `reveal_nodes: Array[NodePath]` lists the room
  sprite plus every object inside it. Hexy tells the room directly (`area.on_player_entered`) when its position
  moves into that area (point query, only when moving).
* Hidden state = a **per-room** `ShaderMaterial` using `Assets/Shaders/pixel_reveal.gdshader` (uniforms `reveal`
  0..1, `block_size`). After the fade the material is removed, so there is no ongoing cost.
* Objects stay in the `YSort` node (needed for depth sorting), so the `reveal_nodes` list is what ties them to a room.
* Rooms in The Apartments: `Room1` is built in the scene; `Room2` is an instanced scene (`Scenes/Rooms/Room2.tscn`)
  with "Editable Children" on, which is what lets its `reveal_nodes` override (Lamp2, Chair2) be saved.

### Save/load (`Scripts/Autoload/SaveManager.gd`)
* One file: `user://savegame.json` (atomic write via temp file + rename). F5 save, F9 load, F6 drain the phone battery one level (debug builds only), F10 delete + new game
  (debug builds only). Autosave on room reveal and on quit. The last save loads automatically on start, **only if it
  belongs to the running scene**.
* Contract: a node joins group `SaveManager.GROUP` ("persist") and provides `get_save_id()`, `save_state()`,
  `load_state(dict)`. Currently: Hexy, every `Room`, `Lamp`, the phone; plus `GameData.dialogue_tags`.
* Saving is **off** unless the scene contains a `GameController` node (which calls `SaveManager.register_scene()`).
  This keeps test scenes from overwriting the real save. The main menu calls `unregister_scene()` to turn it off
  again (otherwise quitting from the menu would save "the menu" as the place to continue).
* **Main menu** (`Scenes/UI/MainMenuBox.tscn` + `Scripts/UI/MainMenu.gd`, instanced under `MenuLayer` in
  Main_Menu.tscn): title, New Game, Load Game, styled like the dialogue box (blankballoon 9-slice, flat buttons:
  white text, yellow when focused/hovered; placeholder art/fonts).
  * New Game -> `SaveManager.start_new_game(scene)` (`new_game_scene` export, default TheSat): resets GameData and
    skips the automatic load once. If a save exists it asks first ("overwritten"; No is focused). The old save is
    only replaced when the new game first saves.
  * Load Game -> `SaveManager.continue_game()`: opens the scene the save belongs to; its GameController restores the
    save as usual. Greyed out with no save. E (interact) presses the focused button too; Esc backs out of the question.
  * Running a level directly (F6 in the editor) still auto-loads that level's save, for testing.
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
4. **Session 2 (Claude Code, Windows, Godot 4.7.2)**, three commits:
   * Phone battery driven by tags (section 3).
   * Tests brought up to date with the current data: the scene path had a double space; the smoke test now has a
     watchdog and null-checked lookups so it can't hang; counts and node lookups derive from the data (NPC is found by
     script, it's now called `Charater_Test`); battery checks added.
   * HexQuest Tools: room assignment to an instanced room was silently dropped on save (now turns on Editable
     Children, undoably, via `SceneTools.add_make_editable`); the Scene & Rooms tab's room dropdown reset to Room1
     every time the tab was shown again (now kept), and Assign always reports what it did. Regression tests for both.
   * Later: phone battery levels / power off-on / charging sweep (section 3), then the folder reorganisation
     (section 2). Removed: a committed Visual Studio cache (`Scripts/.vs`), `*.png~` backups, an unused old
     `Scenes/Objects/Lamp.gd`, and old manual test scenes (`Tests/test.tscn`, `TestDialogue.*`).

## 5. Gotchas learned the hard way (please don't relearn these)

**GDScript / Godot 4.2** (found on 4.2; most likely still true on 4.7)
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
* A button press that changes scene takes the pressing node out of the tree immediately: in an input handler, call
  `set_input_as_handled()` (and anything else needing `get_viewport()`) BEFORE emitting `pressed`. Tests should
  press buttons with real input events (`root.push_input`), not `pressed.emit()`, to catch this.
* `AnimatedSprite2D.play(name)` on the animation it's already on carries on from the current frame; parked on the
  last frame of a non-looping animation, it "plays" nothing. Rewind first (`set_frame_and_progress(0, 0.0)`); see
  `Phone._play_from_start`. Tests of an animation should check it starts at frame 0, not just `is_playing()`.
* `AnimatedSprite2D.stop()` resets the frame. Lamp uses `pause()` after setting the frame to hold an end state.

**Headless `-s` test scripts**
* The main script of `godot -s x.gd` compiles **before autoloads exist**: fetch them with
  `root.get_node("SaveManager")`, and do not reference game `class_name`s or autoload identifiers in that file.
* `Input.parse_input_event` is not delivered in headless mode. Use `root.push_input(event)`.
* A scene added manually needs `current_scene = scene`, or `SaveManager.save_game()` returns false.
* `--check-only` on a single script can't see autoloads. Judge parse errors by running the scene instead.

**Tests that touch real files**
* Renaming a dialogue id in the Dialogue tab also rewrites matching ids in the **real** `.tscn` files (the tests only
  use a temp copy of the dialogue). `ui_test` renames `ITM011` and checks first that no scene uses it; pick another id
  if that ever changes. An earlier version renamed `ITM014`, which silently rewrote the Charger scene.
* After a test run, check `git status` for unexpected changes.

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
* **User's Windows machine:** Godot is `C:\Program Files\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`
  (4.7.2). It's a GUI build: it prints nothing to the console and `&` returns immediately, so run it with
  `Start-Process ... -PassThru`, `--log-file <path>`, and a timeout (`WaitForExit(180000)`, then stop **only that PID**:
  the user may have the editor open). `git` isn't on PATH; Sourcetree's bundled one is at
  `%LOCALAPPDATA%\Atlassian\SourceTree\git_local\cmd\git.exe`. The user commits via Sourcetree; local commits from
  Claude are fine, never push.
* The first session had a Linux sandbox with Godot 4.2.2 (downloaded from the official GitHub release) and
  `xvfb` + Mesa software GL, which allowed real rendering/screenshots and running the real editor.
  On the user's machine use their installed Godot 4.7 (see above).
* Rendering test pattern: `xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --windowed --resolution 1080x720 -s <script>`, where the script saves
  `root.get_viewport().get_texture().get_image()` to PNG after some frames.
* Editor test pattern: copy the project to a temp dir, add a throw-away `@tool` EditorPlugin (not shipped) that waits a
  few seconds, then drives the HexQuest panels, takes screenshots, writes a log and calls `get_tree().quit()`;
  launch with `godot --editor --path <tmp>` under `xvfb-run`. Never run this against the real project.

## 7. How to run the tests
From the project root (replace `godot` with your Godot 4.7 executable; on Windows see section 6 for how to capture
output). First open the project in the editor once, or run `godot --headless --import`.

```
godot --headless -s res://Tests/smoke_test.gd                              # reveal, interactions, dialogue, save/load
godot --headless -s res://addons/hexquest_tools/tests/core_test.gd         # DialogueDB, validator, factory, scene tools
godot --headless -s res://addons/hexquest_tools/tests/ui_test.gd           # drives the tool panels
godot --headless -s res://Tests/menu_test.gd                               # main menu: New Game / Load Game
```
Each prints PASS/FAIL lines and exits non-zero on failure. All three pass on Godot 4.7.2 as of session 2
(smoke 93, core 80, ui 71, menu 23 checks). `menu_test` registers an `OS.add_logger()` Logger and fails on any
engine/script error printed during the run (script errors don't stop a test on their own); worth copying into the
other suites. The smoke test's battery flow waits on real animation time (sped up 40x), so it's a few seconds slower. One `ERROR: SaveManager: save file is corrupt` line in the smoke test is **expected** (it
deliberately writes a corrupt save). Tests use their own save/dialogue files and clean up after themselves.

## 8. Known issues and data problems
* ~~`NPC005 -> NPC006`~~ fixed in the data (the Problems tab shows 0 errors).
* `FIRST_SOUL_COMPLETED` (ITM021, NPC010) is required but never set, so those lines never show.
  `PHONE_CHARGE_ZERO` is set by `Phone.gd` (the Problems tab still warns about it; that warning is expected).
* The tests reference current node names (`Charater_Test`, `Table`, `Room2`); renaming those means updating tests.
* Two Godot-generated `.import` files are untracked in the repo (`hexy stand.png.import`,
  `witch_confused.png.import`). Commit them or ignore them, the user hasn't decided.
* Dialogue-tab edits (delete, duplicate, text) are **not undoable**; Reload from disk or git is the escape hatch.
* Creating a conversation saves `dialogue.txt` immediately, including other pending edits (by design).
* Only 2 choices per question (the dialogue box has 2 buttons).
* **(unverified)** macOS behaviour, exported builds (needs `*.txt` in the export filter so
  `dialogue.txt` ships), and 2D movement smoothness on >60 Hz displays (Hexy moves in `_physics_process` at 60 Hz;
  Godot 4.2 had no 2D physics interpolation, but 4.7 has it under Project Settings > Physics > Common, which may
  fix this).

## 9. Suggested next steps (pick with the user)
1. Decide what sets `FIRST_SOUL_COMPLETED`. Battery follow-up: decide what drains it (call
   `Phone.add_charge(-n)`; levels, tags, power-off and saving are already handled).
2. Main menu follow-ups: real art/font for the menu box, a Quit button, a way back to the menu from the game
   (call `SaveManager.save_game()` first, then change scene), and showing the save's "saved at" time on Load Game.
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
# HexQuest (Godot 4.7, GDScript, GL Compatibility)

## Rules
- Tabs only in .gd files. Use typed signals: `SignalController.x.emit(...)`, never `emit_signal("x")`.
- Use input actions (`interact`, `phone`, `move_*`), never hard-coded keys.
- Neutral wording for Hexy (pronouns unknown).
- Autoload scripts must not depend on global `class_name`s (use `preload`).
- Addon scripts (`addons/hexquest_tools`) are `@tool`, never use `class_name`, and use `preload`.
- Don't name methods `_set` / `_get`. Annotate types when `:=` can't infer.
- React to dialogue tags via `SignalController.tag_added` / `tags_loaded`, not by special-casing in GameData.
- Tool code that edits nodes inside an instanced scene must turn on Editable Children (`SceneTools.add_make_editable`).

## Architecture in one paragraph
Autoloads: SignalController -> GameData -> SaveManager. E key -> `interaction_check` -> `Hexy.interact_nearby()` finds an
`Object_Id` Area2D (physics layer 4) and calls `.interact()` on its parent (all extend `Interactable`). Dialogue lives in
`Assets/Data/dialogue.txt` (first entry in an id list whose `tagRequired` is met wins). Rooms (`Room.gd` on an Area2D, layer 2)
hide `reveal_nodes` behind a per-room pixel-dissolve shader until Hexy enters, and stay revealed. Saving is one JSON
file via `SaveManager`; saveable nodes join group "persist" and implement `get_save_id/save_state/load_state`; a scene
only saves if it contains a `GameController`.

## Verify before finishing any change
    godot --headless -s res://Tests/smoke_test.gd
    godot --headless -s res://addons/hexquest_tools/tests/core_test.gd
    godot --headless -s res://addons/hexquest_tools/tests/ui_test.gd
    godot --headless -s res://Tests/menu_test.gd
(One "save file is corrupt" error line in smoke_test is expected. On Windows, see HANDOFF.md section 6 for running
the GUI Godot build with --log-file and a timeout.) In `-s` test scripts, fetch autoloads via
`root.get_node(...)`, use `root.push_input()` for input, and set `current_scene`.

## Update HANDOFF.md with any relevent information needed for future use.
````
