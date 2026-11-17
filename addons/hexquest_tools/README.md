# HexQuest Tools

An editor plugin with a **HexQuest** tab (next to 2D / 3D / Script) and a nicer `dialogue_ids` editor in the Inspector.
It's enabled already (Project > Project Settings > Plugins). Everything the tools need to know about your folders and
scripts is in `hq_config.gd`.

## Dialogue tab
Edit every line in `dialogue.txt` without touching JSON.

* **List + search** (id, text or tag). Lines with errors are red.
* **Form**: text, portrait (with thumbnail), "only shown if tag", "sets tag", and what happens next:
  *end*, *continue to another line*, or *ask a question* (2 buttons, each with its own list of lines).
* **Live preview** of the dialogue box, and a warning if the text is too long to fit it (uses your real box size and font).
* **＋ New next line** creates the next line and links to it, so you can write a conversation by just clicking through.
* **Quick conversation…** paste what's said, one dialogue box per line, and the whole linked chain is created.
  `[witch_happy] Hello!` picks a portrait for that line, `#` starts a comment.
* **Rename** (type a new id, press Enter) updates every line *and every scene file* that points at it.
* **Used by**: jump to the lines and scene objects that use the selected line.
* Ids are generated for you: the next free number for the prefix (NPC012, SAT012…).

The file is written in the same format the game already uses. **Save dialogue** (or Ctrl+S in the editor) writes it.
There's no undo inside this tab: use **Reload from disk** to throw away unsaved changes (or git).

## Objects tab
Create new things with the right structure (`Object_Id` area, collision layers, scripts) in a few clicks.

* Types: **NPC**, **Seat**, **Lamp / toggle** (pick an off and an on look), **Prop**, **Room** (hidden until entered).
* **Drag on the spritesheet** to choose the art (grid-snapped; set Grid to 1 for pixel-exact).
* **Preview** shows the position (red +), the solid box (blue) and the press-E area (green) so you can tune them.
* NPCs take their dialogue here: add existing lines or write a new conversation.
* **Also place it in the open scene** drops it under `YSort` (undoable), and **Reveal with room** adds it to that
  room's hidden-until-entered list. New scenes are saved in `Scenes/Objects/` (rooms: `Scenes/Rooms/`).

## Scene & Rooms tab
Shows each room with the objects hidden inside it, what each NPC says, and what's visible from the start.
**Assign** the selected scene nodes to a room, **Auto-assign by position** (finds objects standing inside a room's
floor area, you confirm), or **Remove from room**. Everything is undoable. Double-click a row to select it in the scene.

## Problems tab
Checks the dialogue file and every scene: lines that continue to nothing, dead ends, loops, missing ids/portraits,
choices that lead nowhere, text too long for the box, tags that are required but never set, objects pointing at missing
lines, and entries in a list that can never show (an earlier line with no tag requirement always wins).
Double-click a row to jump to it. The tag table shows which lines set and which need each tag.

## Inspector
On any node with a `dialogue_ids` property (like NPCs) the plain array is replaced by a list that shows what each line
says, with Edit / reorder / remove, "＋ Existing line…" and "＋ New conversation…".

## Tests
Headless, no editor needed (run from the project folder):

    godot --headless -s res://addons/hexquest_tools/tests/core_test.gd
    godot --headless -s res://addons/hexquest_tools/tests/ui_test.gd
    godot --headless -s res://Tests/smoke_test.gd

## Notes
* Exports: add `*.txt` to the export filter (Resources tab) so `dialogue.txt` is included in builds.
* Not handled: deleting/duplicating lines isn't undoable, and conversations with more than 2 choices (the game's box has 2 buttons).
