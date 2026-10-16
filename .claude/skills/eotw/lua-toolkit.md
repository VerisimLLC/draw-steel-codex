# /eotw Lua toolkit

Run these through `mcp__dmhub__execute_lua` (load it with ToolSearch
`select:mcp__dmhub__execute_lua,mcp__dmhub__check_connection` if it is
deferred). They inspect the author's CURRENT game and map; `print` output comes
back to you. Check `mcp__dmhub__check_connection` first and confirm the game id
is the author's authoring game before running anything that writes.

The EotW globals (`EncounterMontage`, `EncounterScript`, `EncounterZones`,
`EncounterOfTheWeekGame`) exist only in a game with `codex-eotwauthor` (or the official module)
installed. Read them with `rawget(_G, "...")` when unsure: Lua globals here are
strict, and reading an undefined one raises.

## Preflight

```lua
local function has(name) return rawget(_G, name) ~= nil end
print("EotW code loaded:", has("EncounterMontage") and has("EncounterScript") and has("EncounterZones"))
print("director:", dmhub.isDM, "game:", dmhub.gameid)
print("dev:encounteroftheweek =", dmhub.GetSettingValue("dev:encounteroftheweek"))
if has("EncounterZones") then
  local id, kw = EncounterZones.FindKeyword("Start")
  print("Start keyword:", id, kw and kw.name)
end
```

- EotW code not loaded -> install `codex-eotwauthor` in this game and
  restart (the author does it).
- `dev:encounteroftheweek` false -> the author types `/toggle dev:encounteroftheweek`.

## Current map

```lua
local m = game.currentMap
print("map:", m and m.description, "id:", game.currentMapId)
for _, map in pairs(game.maps or {}) do
  local n = map.description or ""
  local ok = n == "Encounter" or n:sub(1, 11) == "Encounter: "
  print(ok and "ENCOUNTER MAP" or "", n, map.id)
end
```

A valid encounter map name is `Encounter` or `Encounter: <Title>`, at most 80
characters, none of `. $ # [ ] / |`, unique among the module's maps.

## Zones (Start, traps)

```lua
for _, kind in ipairs({"Start", "Trap"}) do
  local recs = EncounterZones.ZoneRecords(kind)
  local tiles = 0
  for _, z in ipairs(recs) do
    tiles = tiles + #(z.record.locs or {})
    print(kind, z.zoneid, "floor", z.floorIndex, #(z.record.locs or {}), "tiles; playerVisible =", z.record.playerVisible)
  end
  print(kind, "zones:", #recs, "total tiles:", tiles)
end
for _, e in ipairs(MapMarkup.GetZoneTypesOnMap()) do print("zone type on map:", e.name, e.keywordid) end
```

- Start: at least one zone, 12+ tiles, on walkable ground.
- Trap zones: `playerVisible` should be false/nil (hidden until revealed), and
  there should be more tiles than traps placed.
- Replace `"Trap"` with whatever zone type the script's setup line names
  (`FindKeyword` also accepts the plural).

Painting zones is the author's job in Map Markup -> Zones. Only if asked, a zone
can be made in Lua on the current floor: `MapMarkupImpl.CreateZone(keywordid,
locs)` -- inspect an existing record's `locs` first to copy its exact shape, and
note it does not add the type to the panel's palette.

## Encounter (monsters)

```lua
local e = EncounterOfTheWeekGame.FindMapEncounter()
if e == nil then print("NO ENCOUNTER ISLAND FOUND on this map") return end
print("found in doc:", e.docid, "bubble:", e.bubbleid)
local enc = e.encounter
for gi, g in ipairs(enc.groups or {}) do
  local parts = {}
  for mid, q in pairs(g.monsters or {}) do
    local a = assets.monsters[mid]
    parts[#parts+1] = (a and a.name or mid) .. " x" .. tostring(q)
  end
  local counts = {}
  for n = 4, 6 do counts[#counts+1] = n .. " heroes: " .. tostring(Encounter.AdjustedGroupCount(g, n)) end
  print(string.format("group %d: %s | wave=%s minHeroes=%s | banked positions=%d on map %s (this map %s) | %s",
    gi, table.concat(parts, ", "), tostring(g.wave), tostring(g.minHeroes),
    #(g.spawnlocs or {}), tostring(g.stagemapid), tostring(game.currentMapId), table.concat(counts, ", ")))
end
print("EV:", enc:CountEDS())
```

- `found in doc` should be the script document. A `bubble` id means an info
  bubble's encounter is winning -- remove it or the script's island is ignored.
- `wave` groups are reinforcements and are not spawned at the start.
- Banked positions should be on THIS map; unpositioned monsters fall into a
  grid near the group's first saved position.

Staging for the largest party: `dmhub.SetSettingValue("numheroes", 6)` (range
3-7; the real game sets it from the party). Read with
`dmhub.GetSettingValue("numheroes")`. Tell the author before changing it.

## Writing documents

Ask the author first, and never write a document they have open in the editor
(the editor's own save would overwrite yours, or yours theirs).

Create a document in the current map's Map Documents folder:

```lua
local doc = MarkdownDocument.new{
  id = dmhub.GenerateGuid(),
  parentFolder = game.currentMapId,   -- the map's journal folder
  description = "The Tolling",        -- the name sub-document links use
  annotations = {},
}
doc:SetTextContent(text)              -- LF line endings
doc:Upload()
print("created", doc.id)
```

Edit an existing one -- **read first**, change only what you mean to, keep
every `[[tag]]` line verbatim and in the same order (the tags' objects are keyed
by their text and order):

```lua
local docs = dmhub.GetTable("documents")
for id, d in unhidden_pairs(docs) do
  if d.parentFolder == game.currentMapId then print(id, d.description, #d:GetTextContent()) end
end
-- local d = docs["<docid>"]; print(d:GetTextContent())
-- d:SetTextContent(newText); d:Upload()
```

Then re-read the table to confirm the write landed, and re-run the Full check.
To show the author a document: `docs["<docid>"]:ShowDocument{ edit = true }`.

## Rich tags: the objects behind `[[encounter]]` and `[[scene]]`

A `[[tag]]` line in the text is only half of it. The other half is an object in
the document's `annotations` table, which Lua can build directly. This is
exactly what the journal editor does when it meets a new tag
(`MarkdownDocument.lua` `editDocument`), so the editor is not needed.

**Keys.** The key is the tag's full text: `[[encounter]]` -> `"encounter"`,
`[[scene:marsh]]` -> `"scene:marsh"`. A repeat of the same text in one document
gets `-1`, `-2`, ... in text order (`"scene"`, `"scene-1"`). Keys may not
contain `. $ # [ ] /`. Prefer `[[scene:<name>]]` for every scene after the first
in a document. The editor's autocomplete may insert `[[scene2]]`, which is not
a registered tag.

**`identifier`** is the part after the colon (`"marsh"`), or `false` for a bare
tag. It is not a declared field, so read it with `a:try_get("identifier")`.

```lua
local docs = dmhub.GetTable("documents")
local doc = docs["<docid>"]
-- copy before changing: the annotations table may be shared or cached
local ann = DeepCopy(doc:try_get("annotations") or {})

-- [[scene:marsh]]
local scene = RichScene.Create()
scene.identifier = "marsh"            -- false for a bare [[scene]]
scene.image = "<image asset id>"      -- see "Scene images" below
ann["scene:marsh"] = scene

-- [[encounter]] (the start-of-combat fight)
local re = RichEncounter.Create()     -- re.encounter is a fresh Encounter
re.identifier = false
re.encounter.name = "The Drowned Bell"
re.encounter.groups = { }             -- ALWAYS assign a fresh table, see below
ann["encounter"] = re

doc.annotations = ann
doc:Upload()
```

The text must contain the matching tag lines (`[[scene:marsh]]`,
`[[encounter]]`) on their own lines. An annotation with no tag in the text is
ignored, and a tag with no annotation is an empty widget. Re-read
`docs["<docid>"].annotations[...]` afterwards to confirm.

### Encounter groups and positions

The data model, confirmed against encounters built in the app:

```lua
group = {
  monsters = { [monsterid] = count, ... },   -- bestiary ids (assets.monsters keys)
  spawnlocs = { Loc, Loc, ... },             -- saved positions, one per spawned monster
  spawnmonsters = { monsterid, ... },        -- optional: which monster type each slot is for
                                             -- (dense list; use false for "any"); without it
                                             -- slots are handed out in order
  stagemapid = "<map id>",                   -- the map the positions belong to
  invisibleToPlayers = { false, ... },       -- optional, per slot
  appearances = { false, ... },              -- optional, per slot
  -- optional, party-size scaling:
  minHeroes = 5,                             -- the whole group only appears with 5+ heroes
  monsterMinHeroes = { [monsterid] = 6 },    -- one monster type only with 6+ heroes
  balancing = { [4] = { monsters = { [monsterid] = -1 } } },   -- per party size: count deltas
  wave = nil,                                -- nil = arrives at the start (wave groups are
                                             -- reinforcements, not spawned by EotW at start)
}
```

- A position is `core.Loc{ x = x, y = y, floorIndex = f }` (tile coordinates;
  `floorIndex` as the map's tokens report it in `token.loc.floor`). Read a token's
  spot with `token.loc` and copy it as-is.
- Save positions for the LARGEST party (6 heroes): a slot with no saved position
  spawns in a grid near the group's first position.
- Groups act together in initiative (Draw Steel squads), so group monsters the
  way they should take turns: a minion squad and its captain, a solo, a pair of
  elites.
- Every table you assign must be fresh: the class defaults (`Encounter.groups`)
  are shared between instances.

**Building from tokens the author placed** (the friendliest way to position
monsters: the author drags monsters from the Bestiary onto the map exactly where
they want them, then you convert them):

```lua
-- 1. find the placed monster tokens on this map and match each to its bestiary entry.
--    A placed token keeps its bestiary entry's monster_type (renaming the token
--    does not change it); match on that.
local byType = {}
for id, m in pairs(assets.monsters) do
  local t; pcall(function() t = m.properties:try_get("monster_type") end)
  if t ~= nil and t ~= "" then
    byType[t] = byType[t] or {}
    table.insert(byType[t], { id = id, hidden = m.hidden == true, name = m.name })
  end
end
for _, tok in ipairs(dmhub.allTokens) do
  local props = tok.properties
  local t = props ~= nil and not props:IsHero() and props:try_get("monster_type") or nil
  if t ~= nil and t ~= "" then           -- tokens with no monster_type are not monsters (objects etc.)
    local matches = byType[t] or {}
    local ids = {}
    for _, mm in ipairs(matches) do ids[#ids+1] = mm.name .. (mm.hidden and " (hidden)" or "") .. " " .. mm.id end
    print(tok.charid, tok.name, "type:", t, "at", tok.loc.x, tok.loc.y, tok.loc.floor, "->", table.concat(ids, " | "))
  end
end
```

2. Agree the grouping with the author, and resolve any token whose type matches
   more than one bestiary entry (prefer the visible one; ask if unsure).
3. Build the groups: `monsters[id] = count`, and append each token's `token.loc`
   to `spawnlocs` (and its id to `spawnmonsters`); `stagemapid =
   game.currentMapId`. Upload the document as above.
4. **Remove the placed tokens**, after the author confirms:
   `game.DeleteCharacters({ charid, ... })`. They must not stay. The encounter
   spawns its own copies at game time, and a published map ships every
   non-hero token standing on it, so leftovers would mean a second set of
   monsters.
5. Run the Encounter check above: banked positions = monster count for 6 heroes,
   on this map.

Alternatively, positions can be computed from coordinates (e.g. spread over the
tiles of a helper zone the author painted, then delete the helper zone), or the
author can use the builder's Stage on Map / Save Positions & Remove.

### Scene images

Use an image already in the game (`image` = its asset id; any image the author
picked elsewhere works), or upload one from a file on this machine:

```lua
local imageid
imageid = assets:UploadImageAsset{
  path = [[C:\path\to\marsh.jpg]],
  description = "Marsh",
  error = function(text) print("upload failed:", text) end,
  upload = function(id) dmhub.AddAndUploadImageToLibrary("coverart", id) end,
}
print("image id", imageid)
-- usable once it appears in assets.imagesTable[imageid]; then set scene.image = imageid
```

This is what the journal's scene image picker does (library `coverart`).

## Full check (run after every substantial edit)

```lua
local s = EncounterMontage.FindMapScript(true)
print("script doc:", s.docid, s.doc and s.doc.description)
for id, inc in pairs(s.parse.included or {}) do print("  includes:", inc.name or id) end
print(EncounterScript.Describe(s.parse))
local hasEnc = false
for _, b in ipairs(s.parse.beats) do if b.kind == "encounter" then hasEnc = true end end
print("has # Encounter beat:", hasEnc)
for _, w in ipairs(s.parse.warnings or {}) do print("WARN", w) end

local items, monsters = EncounterScript.ReferencedNames(s.parse)
for n in pairs(items) do print("item", n, EncounterMontage.FindGear(n) or "NOT FOUND") end
for n in pairs(monsters) do print("ally monster", n, EncounterMontage.FindMonster(n) or "NOT FOUND") end

for _, b in ipairs(s.parse.beats) do
  for _, ins in ipairs(b.setup or {}) do
    print("setup", ins.kind, ins.object, EncounterZones.FindObjectAsset(ins.object or "") or "NO OBJECT ASSET",
      ins.zone, EncounterZones.FindKeyword(ins.zone or "") or "NO ZONE TYPE", "zones:", #EncounterZones.ZoneRecords(ins.zone or ""))
  end
  if b.kind == "montage" then
    for _, e in ipairs(EncounterScript.MontageEntries(b)) do
      for _, o in ipairs(e.options or {}) do
        if o.roll then
          local c = EncounterScript.ParseAttr(o.roll.attr, creature.attributesInfo, Skill.skillsDropdownOptions)
          if next(c) == nil then print("NO CHARACTERISTIC:", e.name, "/", o.name, "/", o.roll.attr) end
        end
      end
    end
  end
end
local town = s.parse.story and s.parse.story.towngate
print("Town Gate text:", town and town.text and #town.text or "NONE")
print("Conclusion:", s.parse.story and s.parse.story.conclusion ~= nil, "Defeat:", s.parse.story and s.parse.story.defeat ~= nil)
```

Reading the results:
- `unrecognized effect ...` warnings on pure flavour lines are fine; anything
  meant to be mechanical must be reworded to a recognized clause.
- Warnings about rolls without a `###` heading, fewer than 3 tiers, unknown
  rider requirements, `PC chose` naming no option, delves with no `# Delve:`
  section, threats without a consequence, and skill names must all be fixed.
- Scene cast monsters (`Witch (Wode Hag) enters`) are NOT in this check: look
  each one up with `EncounterMontage.FindMonster("Wode Hag")`.
- `/eotwscript` prints the same parse to chat; with the `dev` setting on,
  `/eotwvalidate` opens the visual validator.

For a map other than the current one: `EncounterMontage.ScriptForMap(mapid)`
returns `{script, documents}` (no info-bubble fallback).

## Lookups

```lua
for _, o in ipairs(Skill.skillsDropdownOptions) do print("skill:", o.text) end
for id, info in pairs(creature.attributesInfo) do print("characteristic:", info.description) end
for _, l in unhidden_pairs(dmhub.GetTable("languages") or {}) do print("language:", l.name) end

local q = "hag"   -- monster search
for id, a in pairs(assets.monsters) do
  if not a.hidden and string.find(string.lower(a.name or ""), q, 1, true) then print("monster:", a.name, id) end
end
q = "potion"      -- item search
for id, it in unhidden_pairs(dmhub.GetTable("tbl_Gear") or {}) do
  if string.find(string.lower(it.name or ""), q, 1, true) then print("item:", it.name, id) end
end
q = "trap"        -- object assets (for setup lines)
for id, n in pairs(assets.allObjects) do
  local d; pcall(function() d = n.description end)
  if type(d) == "string" and string.find(string.lower(d), q, 1, true) then print("object:", d, id) end
end
```

## Playtest drivers

Chat commands (or `Commands.eotwmontage("state")` etc. over MCP):
`/eotwnarrative start|stop|state|force|reset`, `/eotwmontage start|stop|state|reset`,
`/eotwprep start|stop|state|force|reset|unlock|intelligence <n>`,
`/eotwzones setup|reveal <zone>|apply|state|reset`,
`/eotwencounter start|stop|state`. `reset` refuses during combat. These drive
the FIRST beat of their kind; the Director plays the party-owned heroes.

Driving montage turns without the UI (what the stage itself sends):
`EncounterMontage.SendRequest("approach", {heroid, entryId})` (status
`gathering`: `("accompany", {heroid})` sends another hero along,
`("setOff", {})` continues), then `("choose", {optionIndex})` (status
`assist`: `("assist", {heroid, skillid})` claims an assist,
`("proceedTest", {})` rolls without more help), then `("rolled", {rollSeq =
m.turn.rollSeq, tier, total, natural})`. Skip a
scene with `doc.data.montageScene = { id = m.turn.scene.id, index =
#m.turn.scene.steps + 1 }` inside a change on `EncounterMontage.GetDoc()`.
Each step lands on the dev driver's next host tick (~0.5s), so poll
`EncounterMontage.GetState().turn.status` between them.

## Publishing

- Open the publish dialog for the author: `Commands.sharecontent()`.
- After publishing, confirm the record:

```lua
module.DownloadModuleInfo{ moduleid = "<author>-<module>", success = function(info)
  print("type:", info.moduleType, "public:", info.published)
  for name, e in pairs(info.publishingProperties.eotwEncounters or {}) do
    print("encounter:", name, "town gate chars:", e.townGate and #e.townGate or 0)
  end
end, failure = function(m) print("FAILED", m) end }
```

`moduleType` must be `eotw` and `published` true for the encounters to join the
pool. Then check in the town: the Danger Rooms list the encounter under
"Encounters to Try" (the Town Gate shows only the Encounter of the Week).
