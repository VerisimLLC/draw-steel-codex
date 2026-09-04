---
name: build-character
description: |
  Create hero characters programmatically via the DMHub MCP server. Use when asked to
  "build a character", "create a hero", "make a PC", "set up a character token",
  "place a character on the map", or any request to instantiate a playable character
  with class, subclass, abilities, attributes, and other builder choices resolved.
---

# Build Character via MCP

You create fully-configured hero characters on the DMHub map using the MCP Lua execution
tools. This replicates what the in-app character builder does, but programmatically.

## Overview

Creating a character requires these steps:
1. **Create the token** via `game.CreateCharacter("character")`
2. **Set core properties** (name, class, `raceid`, attributes) via `ModifyProperties`
3. **Fill choices** -- set typed choices (subclass, skills, feats) explicitly, then run
   `AutofillFeatureChoices(token, requestedNames)` (see "Auto-Filling Choices") to
   auto-select every `CharacterFeatureChoice` across the class AND the ancestry,
   honoring any specifically-requested feature (e.g. "Dragon Breath").
4. **Place on map** via `token:ChangeLocation(core.Loc{x, y})`

The critical piece is `levelChoices` -- this is how the builder records every player
decision (subclass, abilities, skills, feats, kits, AND ancestry feature choices).
Without it, the engine won't resolve those features into actual abilities. A very common
miss: setting `raceid` but not the ancestry's own feature choices, so ancestry-granted
abilities (like Dragon Knight's Dragon Breath) never appear -- the auto-fill routine
exists specifically to prevent that.

## Step-by-Step Process

### Step 1: Resolve the build target (selected token FIRST, else create)

**CRITICAL:** If the user has already spawned/selected a token, build onto THAT token.
Do NOT unconditionally `game.CreateCharacter` -- if you do, the user's selected token
stays empty while a separate hidden character gets all the abilities, and the user
correctly reports "it didn't work." When a user says "build a X" while a blank hero
token is selected, they mean *that* token.

```lua
-- Prefer the currently-selected character token; only create a new one if none is selected.
local function ResolveBuildTarget()
    for _, tok in ipairs(dmhub.selectedTokens or {}) do
        if tok.properties and tok.properties.typeName == "character" then
            return tok.charid, false   -- build onto existing selected token
        end
    end
    return game.CreateCharacter("character"), true   -- nothing selected: create fresh
end

local charid, created = ResolveBuildTarget()
```

Either way the token may not be immediately available (especially a freshly created
one), so resolve it inside a coroutine:

```lua
dmhub.Coroutine(function()
    local token = nil
    for i = 1, 200 do
        coroutine.yield(0.05)
        token = dmhub.GetCharacterById(charid)
        if token ~= nil then break end
    end
    if token == nil then
        print("ERROR: Token not created")
        return
    end
    -- configure token here...
end)
```

`dmhub.selectedTokens` is the current selection (a `CharacterToken[]`); a character
token's `properties.typeName == "character"`. `dmhub.SelectToken(charid)` (note: takes
the charid STRING, not a token object) selects a token if you need to.

### Step 2: Set name and appearance

```lua
token.name = "Character Name"
token.partyId = GetDefaultPartyID()  -- adds to the party
token:UploadAppearance()
```

### Step 3: Set properties

```lua
token:ModifyProperties{
    description = "Initialize character",
    execute = function()
        local props = token.properties

        -- Attributes (characteristics)
        local attrs = props:get_or_add("attributes", {})
        attrs["mgt"] = { baseValue = 2 }   -- Might
        attrs["agl"] = { baseValue = 1 }   -- Agility
        attrs["rea"] = { baseValue = 0 }   -- Reason
        attrs["inu"] = { baseValue = -1 }  -- Intuition
        attrs["prs"] = { baseValue = 2 }   -- Presence

        -- Class assignment
        local classes = props:get_or_add("classes", {})
        classes[#classes + 1] = {
            classid = "<class-uuid>",
            level = 1
        }

        -- Builder choices (THE CRITICAL PART)
        local lc = props:get_or_add("levelChoices", {})

        -- Subclass choice
        lc["<subclass-choice-feature-guid>"] = { "<chosen-subclass-uuid>" }

        -- Skill choices
        lc["<skill-choice-feature-guid>"] = { "<skill-uuid-1>", "<skill-uuid-2>" }

        -- Feature choices (e.g. ability selection)
        lc["<feature-choice-guid>"] = { "<chosen-option-guid>" }

        -- Kit bonus choices (special key, map not array)
        lc["kitBonusChoices"] = {
            ["<bonus-item-guid>"] = "<kit-uuid>",
        }
    end,
}
```

### Step 4: Place on map

```lua
token:ChangeLocation(core.Loc{x = 5, y = 10})
```

## The levelChoices System (CRITICAL)

`levelChoices` is a map stored on `character.properties` that records every choice the
player makes during character creation. The engine reads this map when resolving which
class features, subclass features, abilities, skills, and feats are active.

### How it works

When the engine calls `character:GetClassFeatures()` or `character:GetClassesAndSubClasses()`,
it passes `self:GetLevelChoices()` to every `FillChoice()` / `FillFeaturesForLevel()` /
`GetSubclasses()` call. Each choice type looks up its own GUID in the map to find what
was selected.

### Data format

```lua
levelChoices = {
    -- Key: the GUID of the choice feature (CharacterSubclassChoice, CharacterFeatureChoice, etc.)
    -- Value: an ARRAY of selected option GUIDs

    ["<CharacterSubclassChoice-guid>"] = { "<subclass-uuid>" },
    ["<CharacterFeatureChoice-guid>"]  = { "<option-1-guid>", "<option-2-guid>" },
    ["<CharacterSkillChoice-guid>"]    = { "<skill-uuid-1>", "<skill-uuid-2>" },
    ["<CharacterFeatChoice-guid>"]     = { "<feat-uuid>" },

    -- Special: kit bonus choices use a MAP, not an array
    ["kitBonusChoices"] = {
        ["<bonus-item-id>"] = "<kit-id>",
    },
}
```

**IMPORTANT:** `raceid` (the ancestry ID itself) is NOT stored in levelChoices. It's
stored as a top-level field on the character (`props.raceid = "<ancestry-uuid>"`). The
engine injects it temporarily when `GetLevelChoices()` is called.

**BUT the ancestry's own feature choices ARE stored in levelChoices**, keyed by the
race's `CharacterFeatureChoice` GUIDs -- exactly like class choices. Setting `raceid`
alone only grants the ancestry's fixed features; any ability or trait the ancestry
gates behind a choice (a signature-trait pick, or a points-buy "spend N ancestry
points" list) will NOT appear until you record that choice in levelChoices. This is
the #1 cause of "the ancestry built but its granted ability is missing" (e.g. Dragon
Knight's Dragon Breath, which lives in the "Purchased Dragon Knight Traits" points-buy).
See "Race Feature Choices" below.

### Choice types in detail

#### CharacterSubclassChoice
- **Key:** The GUID of the `CharacterSubclassChoice` feature in the class definition
- **Value:** `{ "<subclass-table-uuid>" }` -- array with ONE element
- **How to find the key:** Look at the class's level features for `typeName == "CharacterSubclassChoice"` and use its `guid`
- **How to find the value:** The UUID/ID of the subclass entry in the `subclasses` table

```lua
-- Example: choosing the Dominion subclass for Acolyte
lc["ac017e00-2005-4000-8000-000000000001"] = { "ac017e00-0002-4000-8000-000000000001" }
```

#### CharacterFeatureChoice
- **Key:** The GUID of the `CharacterFeatureChoice` feature
- **Value:** Array of selected option GUIDs. Length must match `numChoices` on the feature
- **How to find the key:** Look at the class/subclass level features for `typeName == "CharacterFeatureChoice"` and use its `guid`
- **How to find values:** Each option inside the choice has a `guid` -- use those

```lua
-- Example: choosing 2 heroic abilities from a list of options
lc["ability-choice-guid"] = { "elder-visage-guid", "glamorous-rush-guid" }
```

#### CharacterSkillChoice
- **Key:** The GUID of the `CharacterSkillChoice` feature
- **Value:** Array of skill UUIDs. Length must match `numChoices` on the feature
- **How to find skill UUIDs:** Look up the `Skills` table

```lua
-- Example: choosing Intimidate and Religion
lc["skill-choice-guid"] = { "intimidate-skill-uuid", "religion-skill-uuid" }
```

#### CharacterFeatChoice
- **Key:** The GUID of the `CharacterFeatChoice` feature
- **Value:** Array of feat UUIDs from the `feats` table

#### Race Feature Choices (including points-buy)

Ancestries expose their choices as `CharacterFeatureChoice` features too, keyed into
the SAME `levelChoices` map. There are two shapes:

- **Simple pick** (e.g. Dragon Knight "Signature Trait: Wyrmplate", `numChoices: 1`):
  value is an array of chosen option GUIDs, length == `numChoices`.
- **Points-buy** (e.g. Dragon Knight "Purchased Dragon Knight Traits"): `numChoices`
  is the POINT BUDGET, not a count, and each option carries a `pointsCost`. Pick any
  set of options whose `pointsCost` sum is `<= budget`; value is the array of their
  GUIDs. **Watch for whitespace** -- the budget can be stored as a string with a
  trailing tab (e.g. `"3\t"`), so always `tonumber(...)` it before comparing.

```lua
-- Dragon Knight ancestry: pick Fire Immunity (Wyrmplate) + spend 3 ancestry points
-- on Dragon Breath (2 pts) and Draconian Guard (1 pt).
lc["cbe77035-1c50-42c6-ad6b-9ce5754d4895"] = { "efb897ff-9c79-4aab-9e40-fc8321b9dc85" }
lc["a13b9b12-95d5-4a75-ad09-14c48aeb5e09"] = {
    "1ba77d3b-3f14-4151-b6e7-8dde7ceca1f1",  -- Dragon Breath  (2 pts)
    "e1e98137-88d1-4451-9c43-4fd9ef6577a9",  -- Draconian Guard (1 pt)
}
```

**Enumerating race choices is different from classes** -- a `Race` has NO
`FillLevelsUpTo`. Use `GetClassLevel(level)` and read `.features`:

```lua
local race = dmhub.GetTable("races")["<race-uuid>"]
local lvl = race:GetClassLevel(1)
for _, feat in ipairs(lvl:try_get("features") or {}) do
    if feat.typeName == "CharacterFeatureChoice" then
        local budget = tonumber(tostring(feat:try_get("numChoices", 1))) or 1
        print(feat:try_get("name", "?"), "guid=" .. feat:try_get("guid", "?"),
              "budget/count=" .. budget)
        for _, opt in ipairs(feat:try_get("options") or {}) do
            print("   opt", opt:try_get("name", "?"), "guid=" .. opt:try_get("guid", "?"),
                  "pointsCost=" .. tostring(opt:try_get("pointsCost")))
        end
    end
end
```

## How to discover what choices a class needs

Use this Lua code to enumerate all choices that must be filled:

```lua
local classTable = dmhub.GetTable("classes")
local myClass = classTable["<class-uuid>"]

-- Get class-level features
local classFill = {}
myClass:FillLevelsUpTo(targetLevel, false, "nonprimary", classFill)

for i, levelEntry in ipairs(classFill) do
    local features = levelEntry:try_get("features") or {}
    for j, feat in ipairs(features) do
        local tn = feat.typeName
        local nm = feat:try_get("name", "unnamed")
        local guid = feat:try_get("guid", "no-guid")
        print(string.format("[%d] %s: '%s' guid=%s", j, tn, nm, guid))

        if tn == "CharacterFeatureChoice" then
            local opts = feat:try_get("options") or {}
            local nc = feat:try_get("numChoices", 1)
            print(string.format("    CHOOSE %s:", tostring(nc)))
            for k, opt in ipairs(opts) do
                print(string.format("    - '%s' guid=%s", opt:try_get("name","?"), opt:try_get("guid","?")))
            end
        elseif tn == "CharacterSubclassChoice" then
            print("    SUBCLASS CHOICE -- set to subclass UUID")
        elseif tn == "CharacterSkillChoice" then
            print(string.format("    SKILL CHOICE -- choose %s", tostring(feat:try_get("numChoices",1))))
        end
    end
end

-- Then do the same for the subclass
local subclassTable = dmhub.GetTable("subclasses")
local mySubclass = subclassTable["<subclass-uuid>"]
local subFill = {}
mySubclass:FillLevelsUpTo(targetLevel, false, "nonprimary", subFill)
-- ... same enumeration loop
```

**Don't forget the ancestry.** If the character has a `raceid`, enumerate the race's
choices too and fill them -- otherwise ancestry-granted abilities go missing. Races
use a different accessor (`GetClassLevel`, not `FillLevelsUpTo`); see the enumeration
snippet under "Race Feature Choices (including points-buy)".

## Auto-Filling Choices (class + subclass + race)

Rather than hand-picking every choice GUID, run this generic routine AFTER setting
`classes` and `raceid`. It walks every level of the class(es) and the ancestry,
auto-selects all `CharacterFeatureChoice` nodes (both simple `numChoices` picks and
`pointsCost` points-buy), and honors any feature names you request (e.g. the user asked
for "Dragon Breath"). It deliberately does NOT touch subclass / skill / feat choices --
those need typed values -- but it REPORTS them so the build never silently misses one.

Selection policy:
- **Requested names win.** Any option whose name matches `requestedNames`
  (case-insensitive) is chosen first, in whatever choice contains it.
- **Points-buy** (options carry `pointsCost`; `numChoices` is the point BUDGET): after
  the requested picks, greedily add the most expensive still-affordable option until the
  budget is spent.
- **Simple pick** (`numChoices` is a count): after requested picks, fill remaining slots
  with the first options.
- **Already-set choices are left alone** -- set any choice explicitly before calling this
  and it won't be overwritten.

```lua
-- Returns (featureChoices, otherChoices). featureChoices are auto-fillable
-- CharacterFeatureChoice nodes; otherChoices are typed choices (subclass/skill/feat)
-- that must be set explicitly.
local function CollectChoices(token)
    local props = token.properties
    local featureChoices, otherChoices, seen = {}, {}, {}
    local function add(feature)
        local tn = feature.typeName
        if tn == "CharacterFeature" then return end
        local guid = feature:try_get("guid"); if guid == nil or seen[guid] then return end
        seen[guid] = true
        if tn == "CharacterFeatureChoice" then
            local opts = feature:try_get("options") or {}
            if #opts == 0 then return end
            local pb, list = false, {}
            for _, o in ipairs(opts) do
                local cost = o:try_get("pointsCost"); if cost ~= nil then pb = true end
                list[#list+1] = { guid = o:try_get("guid"), name = o:try_get("name", "?"), cost = tonumber(cost) or 1 }
            end
            featureChoices[#featureChoices+1] = {
                guid = guid, name = feature:try_get("name", "?"), options = list,
                budget = tonumber(tostring(feature:try_get("numChoices", 1))) or 1, pointsBuy = pb }
        else
            otherChoices[#otherChoices+1] = { guid = guid, typeName = tn,
                name = feature:try_get("name", tn),
                numChoices = tonumber(tostring(feature:try_get("numChoices", 1))) or 1 }
        end
    end
    local function walk(feats) for _, f in ipairs(feats or {}) do add(f) end end
    -- class + subclass levels (races have NO FillLevelsUpTo)
    for _, entry in ipairs(props:try_get("classes") or {}) do
        local c = dmhub.GetTable("classes")[entry.classid]
        if c then
            local fill = {}; c:FillLevelsUpTo(entry.level or 1, false, "nonprimary", fill)
            for _, lvl in ipairs(fill) do walk(lvl:try_get("features")) end
        end
    end
    -- ancestry: GetClassLevel().features + per-level features
    local raceid = props:try_get("raceid")
    if raceid then
        local race = dmhub.GetTable("races")[raceid]
        if race then
            walk(race:GetClassLevel().features)
            for _, lvl in ipairs(race:try_get("levels") or {}) do walk(lvl:try_get("features")) end
        end
    end
    return featureChoices, otherChoices
end

-- Auto-fills every CharacterFeatureChoice. Returns (filled[], warnings[]).
local function AutofillFeatureChoices(token, requestedNames)
    local wanted = {}
    for _, nm in ipairs(requestedNames or {}) do wanted[string.lower(nm)] = true end
    local props = token.properties
    local filled, warnings = {}, {}
    local featureChoices, otherChoices = CollectChoices(token)
    token:ModifyProperties{ description = "Auto-fill feature choices", execute = function()
        local lc = props:get_or_add("levelChoices", {})
        for _, node in ipairs(featureChoices) do
            if lc[node.guid] ~= nil then
                filled[#filled+1] = node.name .. " -> (already set)"
            else
                local chosen, inSet = {}, {}
                for _, o in ipairs(node.options) do
                    if wanted[string.lower(o.name)] then chosen[#chosen+1] = o; inSet[o.guid] = true end
                end
                local function spent() local s = 0 for _, o in ipairs(chosen) do s = s + o.cost end return s end
                if node.pointsBuy then
                    local more = true
                    while more do
                        more = false; local best = nil
                        for _, o in ipairs(node.options) do
                            if not inSet[o.guid] and spent() + o.cost <= node.budget then
                                if best == nil or o.cost > best.cost then best = o end
                            end
                        end
                        if best then chosen[#chosen+1] = best; inSet[best.guid] = true; more = true end
                    end
                else
                    for _, o in ipairs(node.options) do
                        if #chosen >= node.budget then break end
                        if not inSet[o.guid] then chosen[#chosen+1] = o; inSet[o.guid] = true end
                    end
                end
                local guids, names = {}, {}
                for _, o in ipairs(chosen) do guids[#guids+1] = o.guid; names[#names+1] = o.name end
                lc[node.guid] = guids
                filled[#filled+1] = string.format("%s [%s] -> %s", node.name,
                    node.pointsBuy and "points" or "pick", table.concat(names, ", "))
            end
        end
    end}
    props:Invalidate()  -- force feature/ability cache to recompute from the new choices
    for _, o in ipairs(otherChoices) do
        warnings[#warnings+1] = string.format(
            "%s '%s' (guid=%s, numChoices=%d) NOT auto-filled -- set explicitly",
            o.typeName, o.name, o.guid, o.numChoices)
    end
    return filled, warnings
end

-- Usage inside the build coroutine, after classes + raceid are set:
local filled, warnings = AutofillFeatureChoices(token, { "Dragon Breath" })
for _, l in ipairs(filled) do print("FILLED:", l) end
for _, l in ipairs(warnings) do print("TODO:", l) end
```

**After running it, act on the warnings.** Each warning is a subclass/skill/feat choice
you must set explicitly (see "Choice types in detail"): resolve the subclass UUID, pick
skills from the `Skills` table, etc., then set them in `levelChoices` and (optionally)
call `token.properties:Invalidate()` again. Then verify with `GetActivatedAbilities()`.

## Attribute IDs

| Display Name | ID    |
|-------------|-------|
| Might       | `mgt` |
| Agility     | `agl` |
| Reason      | `rea` |
| Intuition   | `inu` |
| Presence    | `prs` |

## Complete Working Example

```lua
-- Create a level 1 Shadow/Assassin character named "Shade"
local charid = game.CreateCharacter("character")

dmhub.Coroutine(function()
    local token = nil
    for i = 1, 200 do
        coroutine.yield(0.05)
        token = dmhub.GetCharacterById(charid)
        if token ~= nil then break end
    end

    if token == nil then
        print("ERROR: Token creation timed out")
        return
    end

    -- Name and party
    token.name = "Shade"
    token.partyId = GetDefaultPartyID()
    token:UploadAppearance()

    -- Properties
    token:ModifyProperties{
        description = "Build Shade",
        execute = function()
            local props = token.properties

            -- Characteristics
            local attrs = props:get_or_add("attributes", {})
            attrs["mgt"] = { baseValue = 0 }
            attrs["agl"] = { baseValue = 2 }
            attrs["rea"] = { baseValue = 2 }
            attrs["inu"] = { baseValue = -1 }
            attrs["prs"] = { baseValue = -1 }

            -- Class
            local classes = props:get_or_add("classes", {})
            classes[#classes + 1] = {
                classid = "<shadow-class-uuid>",
                level = 1
            }

            -- Ancestry (optional)
            -- props.raceid = "<ancestry-uuid>"

            -- Typed choices set explicitly (subclass / skills / feats)
            local lc = props:get_or_add("levelChoices", {})
            -- Subclass: Assassin
            lc["<subclass-choice-guid>"] = { "<assassin-subclass-uuid>" }
            -- Skills: Sneak + Hide
            lc["<skill-choice-guid>"] = { "<sneak-uuid>", "<hide-uuid>" }
        end,
    }

    -- Auto-fill every CharacterFeatureChoice (class ability picks + all ancestry
    -- feature choices, including points-buy). Pass the names the user asked for.
    local filled, warnings = AutofillFeatureChoices(token, { "<requested-feature-name>" })
    for _, l in ipairs(filled) do print("FILLED:", l) end
    for _, l in ipairs(warnings) do print("TODO (set explicitly):", l) end

    -- Place on map
    token:ChangeLocation(core.Loc{x = 5, y = 5})
    print("Created " .. token.name .. " successfully!")
end)
```

## Verification (MANDATORY -- assert requested features are present)

Every build MUST end by verifying that each feature/ability the user asked for by name
actually resolved. Do this INSIDE the build coroutine, after the auto-fill, and treat a
miss as a hard failure -- never report success without this check passing. Silent
"it built but the ability is missing" is the exact failure this skill guards against.

```lua
-- requestedNames: the same names you passed to AutofillFeatureChoices, e.g. {"Dragon Breath"}
local function VerifyBuild(token, requestedNames)
    token.properties:Invalidate()
    local present = {}
    for _, a in ipairs(token.properties:GetActivatedAbilities()) do present[a.name] = true end
    local missing = {}
    for _, nm in ipairs(requestedNames or {}) do
        if not present[nm] then missing[#missing + 1] = nm end
    end
    print("Abilities on " .. tostring(token.name) .. ":")
    for _, a in ipairs(token.properties:GetActivatedAbilities()) do
        local cat = a:try_get("categorization", "?")
        if cat ~= "Common Ability" and cat ~= "Basic Attack" and cat ~= "Hidden" and cat ~= "Move" then
            print("  " .. a.name .. " | " .. cat)
        end
    end
    if #missing > 0 then
        print("BUILD FAILED -- requested but MISSING: " .. table.concat(missing, ", "))
        return false
    end
    print("BUILD OK -- all requested features present.")
    return true
end

-- at the end of the coroutine:
VerifyBuild(token, { "Dragon Breath" })
```

If `VerifyBuild` returns false, do NOT tell the user it worked. Diagnose: dump
`token.properties:try_get("levelChoices")` and re-run `CollectChoices(token)` to see
which choice the requested option lives in and whether its GUID got set.

## Tips

- **Always use coroutines** when creating characters -- `game.CreateCharacter` is async
- **Call `UploadAppearance()`** after setting name/partyId
- **Wrap property changes in `ModifyProperties{}`** -- never mutate properties directly outside it
- **Enumerate choices first** if you don't know the GUIDs -- use `FillLevelsUpTo` to discover them
- **Ancestry is optional** for basic testing -- characters work without one
- **Kit selection** is handled through class features with `behavior: kitaccess` -- the kit choice
  appears as a CharacterFeatureChoice in the class level features
- **Fill ancestry choices, not just `raceid`** -- setting `raceid` alone omits any ability
  the ancestry gates behind a choice or points-buy (see "Race Feature Choices")
- **If a granted ability seems missing after a build, call `token.properties:Invalidate()`**
  and re-check `GetActivatedAbilities()` -- this forces the feature/ability cache to recompute
  from the current `levelChoices`. A fresh `ModifyProperties` build recomputes on its own, but
  `Invalidate()` is a cheap guarantee when you've mutated `levelChoices` after already reading
  abilities in the same session.
