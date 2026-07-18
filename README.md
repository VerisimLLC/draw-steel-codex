# Draw Steel Codex

This repository is the Lua source code for the **Draw Steel Codex** -- the implementation of
MCDM's **Draw Steel** RPG that runs inside the Codex virtual tabletop (the DMHub engine). You can [get the Codex on Steam](https://store.steampowered.com/app/2902740/Draw_Steel/).
Everything in this repo runs as a set of Lua "code mods" loaded by the Codex desktop app;
there is no standalone build, test runner, or interpreter to invoke from the command line.

The engine itself (C#/Unity) is closed source. This repo is the game system that runs on top
of it: character creation, classes, abilities, combat rules, initiative, monster AI, the
compendium, and nearly all of the UI you see in the app.

## Running the Codex From This Repo

The Codex normally runs the Lua code that ships with the app (synced from the cloud). To
develop against this repo, you point the app's **modding folder** at your clone. Once linked,
the Codex reads every module's `.lua` files directly from your working copy and watches them
for changes, so edits in your editor show up in the running app.

### 1. Clone the repo

Clone this repository anywhere you like, e.g.:

```
git clone <this-repo-url> D:/dev/draw-steel-codex
```

### 2. Turn on Developer Mode

In the Codex, open **Settings** and enable the **Developer Mode** checkbox. You can also
type this into the in-game chat:

```
/dev true
```

Developer Mode unlocks the modding tools and dev-only UI throughout the app.

### 3. Open Compendium -> Code Mods -> Dev Settings

1. Open (or create) a game where you are the Director.
2. Open the **Compendium**.
3. In the sidebar, scroll to the **Modding** section and click **Code Mods**.
4. Select any mod to open the code mod editor, then click the **Dev Settings** button.

**Dev Settings** creates (if needed) and opens the modding configuration file in your
system text editor. The file lives at:

| Platform | Path |
|---|---|
| Windows | `%USERPROFILE%\AppData\LocalLow\MCDM\Codex\mods\settings.json` |
| Mac | `~/Library/Application Support/MCDM/Codex/mods/settings.json` |

### 4. Set `gitfolder` to your clone

Edit the `gitfolder` field to point at the repository you cloned in step 1. Use forward
slashes (or doubled backslashes) -- this is JSON:

```json
{
    "gitfolder": "D:/dev/draw-steel-codex",
    "diffFilesExe": "",
    "diffFilesArgs": "--diff %FILE1% %FILE2%",
    "editFilesExe": "",
    "editFilesArgs": ""
}
```

The other fields are optional: `diffFilesExe`/`diffFilesArgs` let you configure an external
diff tool for comparing code revisions, and `editFilesExe`/`editFilesArgs` an external editor
for opening mod files. `%FILE1%` and `%FILE2%` are substituted with the file paths.

### 5. Restart the Codex

The modding folder is read once at startup, so save `settings.json` and restart the app.

### 6. Verify the link

Each top-level directory in this repo (`Draw Steel Core Rules`, `DMHub Game Rules`, and so
on) matches a module by name. When the app finds a matching directory inside `gitfolder`, it
marks that module **Managed by Git**: it loads the module's Lua from your clone instead of
the cloud copy and watches the files for changes.

To confirm, open **Compendium -> Code Mods**, select a mod (e.g. *Draw Steel Core Rules*),
and check that the editor shows **Managed by Git**. You can also search the player log
(`%USERPROFILE%\AppData\LocalLow\MCDM\Codex\Player.log` on Windows) for
`MOD:: READ CONTENTS FOR MOD` lines to see exactly which files the app loaded from disk.

## Development Workflow

- **Edit files in your clone with any editor.** The Codex watches the linked module folders.
  With the **Auto Reload Lua Changes** setting on (the default, `/autoreloadlua true`),
  saving a file hot-reloads the affected module and its dependents in the running app. If
  auto-reload is off, a notification appears when changes are pending; press **F4** to
  reload.
- **Turn debugging on.** Inside the Codex, type this into the chat:

  ```
  /debug true
  ```

  This enables the Debugging preference, which unlocks debug traces, the debug log tooling,
  and other diagnostics gated behind it (most require Developer Mode to be on as well).
  `/debug false` turns it off, and `/debug` on its own prints the current value. This
  pattern works for any setting: `/<settingid> <value>` sets it, `/<settingid>` shows it.
- **Do not create new Lua files on disk.** Modules and files are registered through the
  Codex's mod system; a file dropped into a module folder will not auto-load, and adding a
  `require` in `main.lua` for an unregistered file breaks loading. Add code to an existing
  file, or create the new file through the in-app Code Mods editor first.
- **ASCII only.** The Lua runtime does not handle non-ASCII characters in source files --
  no em dashes, curly quotes, or other Unicode punctuation, including in comments.
- **Editor tooling.** `Definitions/` contains LuaLS type stubs for the entire engine API
  (`dmhub`, `gui`, `game`, `chat`, and friends), so an editor running the Lua language
  server (e.g. VS Code with the Lua extension) gets completions and type checking against
  the engine surface.

## How This Implements Draw Steel

The engine provides the generic VTT infrastructure: maps, tokens, vision, dice, networking, a
declarative `gui` framework, and a serialization system, and exposes it to Lua. This repo
builds the Draw Steel game system on top of that in layers, loaded in dependency order by
`main.lua` (each `require` line names a module directory and file):

1. **`DMHub Utils/` and `DMHub Core UI/`** -- shared utility code and the UI framework
   (`gui.Panel` wrappers, dockable panels, styles, the theme engine).
2. **`DMHub Game Rules/`** -- a system-agnostic rules framework. Game objects are declared
   with `RegisterGameType` ("creature", "character", classes, conditions, equipment,
   activated abilities) and persist through the engine's serialization system. This layer
   knows nothing about Draw Steel specifically.
3. **`Draw Steel Core Rules/`** -- the Draw Steel system itself. `MCDMRules.lua` resets the
   generic rules (`GameSystem.ClearRules()`) and installs Draw Steel's concepts: Stamina,
   the five characteristics, power rolls (2d10 with edges/banes and three tiers), heroic
   resources, victories, recoveries, respite activities, and so on. The other `MCDM*.lua`
   and `DS*.lua` files extend the base game types with Draw Steel behavior -- e.g. `creature`
   gains minion rules, `character` gains class/kit/ancestry handling.
4. **`Draw Steel Ability Behaviors/` and `Draw Steel Modifiers/`** -- abilities are data
   objects composed of reusable behaviors (deal damage, force movement, apply an ongoing
   effect, summon, ...), and modifiers implement the passive/triggered effects that classes,
   kits, conditions, and items grant. Numeric formulas throughout (damage, distances,
   prerequisites) are written in **GoblinScript**, the expression language evaluated against
   creatures and abilities (`GoblinScript_Guide.md`).
5. **Content data** -- the actual game content (classes, abilities, monsters, items, tables)
   lives as structured data in the compendium; `data/` holds the YAML object tables and
   assets that ship with the codex.
6. **UI and play aids** -- `Draw Steel UI/`, `Draw Steel V/`, `DrawSteelActionBar/` (ability
   casting), `Timeline/` (roll dialog and sidebar), `Draw Steel Character Builder/`, the
   initiative tracker, negotiations, downtime, and montages. `Monster AI/` automates monster
   turns using the same ability objects players use.

The result is that "the rules" are not a monolith: a Draw Steel ability is a data record
composed of behaviors, its numbers are GoblinScript formulas, its presentation is a gui
panel, and the engine only ever sees generic typed objects to store, sync, and render.

## AI Policy

We do allow contributions to this repository that are written using AI tooling, however all contributions must be read, and understood by a human engineer who can take responsibility for them. When making pull requests, please disclose if any substantial part of the code was written using AI.

We are wary about the prospect of being flooded with pull requests that contain large amounts of generated code, so we may decline to accept substantial sized PR's, especially if they use AI generation since accepting PR's means that the maintainers have to take full responsibility for them. If you want to make extensive modifications, consider using your own mod to do so.

## Further Reading

- `CLAUDE.md` -- deeper architecture notes: module structure, core patterns
  (`RegisterGameType`, data tables, `ModifyProperties`, shared documents), and Lua
  constraints.
- `UI_BEST_PRACTICES.md`, `ThemeEngine.md`, `DefaultStyles.md` -- building UI.
- `GoblinScript_Guide.md` -- the formula language.
- `data/DATA_REFERENCE.md` -- the content data format.

## License

See [LICENSE](LICENSE).
