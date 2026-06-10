local mod = dmhub.GetModLoading()

-- A "Modify Companion" CharacterModifier sits on the beastheart and contributes
-- modifiers onto their summoned companion. Symmetric to "Modify Mount Riders"
-- (DSModifyMounts.lua / modrider) -- the dispatch is via FillCompanionModifiers
-- on CharacterModifier and is invoked from AnimalCompanion's
-- FillTemporalActiveModifiers override in DSCompanion.lua.

CharacterModifier.RegisterType("modcompanion", "Modify Companion")

CharacterModifier.TypeInfo.modcompanion = {
    init = function(modifier)
        modifier.feature = CharacterFeature.Create{
            name = "Companion",
            description = "Modify the beastheart's companion",
            source = "Beastheart",
        }
    end,

    modifyCompanion = function(modifier, creature, companion, targetModifiers)
        for _,childMod in ipairs(modifier.feature.modifiers) do
            targetModifiers[#targetModifiers+1] = {
                mod = childMod,
            }
        end
    end,

    createEditor = function(modifier, element)
        local children = {}

        children[#children+1] = modifier:FilterConditionEditor()

        children[#children+1] = gui.Button{
            classes = {"sizeM"},
            text = "Edit Modifiers",
            click = function(element)
                element.root:AddChild(modifier.feature:PopupEditor())
            end,
        }

        element.children = children
    end,
}

--- Dispatcher invoked from AnimalCompanion:FillTemporalActiveModifiers. Each
--- of the beastheart's active modifiers is asked, in turn, whether it
--- contributes anything to the companion's modifier list. Modifiers whose
--- behavior has no `modifyCompanion` callback are silent.
--- @param context table Modifier context (the entry from GetActiveModifiers).
--- @param creature creature The beastheart's properties.
--- @param companion creature The companion's properties.
--- @param modifiers table The companion's accumulating modifier list.
function CharacterModifier:FillCompanionModifiers(context, creature, companion, modifiers)
    local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.modifyCompanion ~= nil then
        self:InstallSymbolsFromContext(context)
        typeInfo.modifyCompanion(self, creature, companion, modifiers)
    end
end

-- Mirror of "Modify Companion" in the summon -> summoner direction. A
-- "Modify Summoner" CharacterModifier sits on a summoned creature's stat

CharacterModifier.RegisterType("modsummoner", "Modify Summoner")

-- The "Modify Summoner" modifier supports two directions, selected by the
-- `mode` field:
--   "summoner" (DEFAULT)
--   "summons": the modifier sits on a SUMMONER
CharacterModifier.modsummonerDefaultMode = "summoner"

CharacterModifier.TypeInfo.modsummoner = {
    init = function(modifier)
        modifier.mode = "summoner"
        modifier.feature = CharacterFeature.Create{
            name = "Summoner",
            description = "Modify the summoner's properties",
            source = "Summoner",
        }
    end,

    modifySummoner = function(modifier, creature, summoner, targetModifiers)
        for _,childMod in ipairs(modifier.feature.modifiers) do
            targetModifiers[#targetModifiers+1] = {
                mod = childMod,
            }
        end
    end,

    --pushes nested modifiers DOWN onto a single summon. Invoked once per summon
    --from the summon's own FillTemporalActiveModifiers (see Creature.lua).
    modifySummons = function(modifier, summoner, summon, targetModifiers)
        for _,childMod in ipairs(modifier.feature.modifiers) do
            targetModifiers[#targetModifiers+1] = {
                mod = childMod,
            }
        end
    end,

    createEditor = function(modifier, element)
        local children = {}

        children[#children+1] = modifier:FilterConditionEditor()

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Direction:",
            },
            gui.Dropdown{
                options = {
                    { id = "summoner", text = "Modify Summoner" },
                    { id = "summons", text = "Modify Summons" },
                },
                idChosen = modifier:try_get("mode", "summoner"),
                change = function(element)
                    modifier.mode = element.idChosen
                end,
            },
        }

        children[#children+1] = gui.Button{
            classes = {"sizeM"},
            text = "Edit Modifiers",
            click = function(element)
                element.root:AddChild(modifier.feature:PopupEditor())
            end,
        }

        element.children = children
    end,
}

--- Dispatcher invoked from character:FillTemporalActiveModifiers (override
--- in DSCompanion.lua). Each of the companion's active modifiers is asked,
--- in turn, whether it contributes anything to the summoner's modifier list.
--- @param context table Modifier context (the entry from GetActiveModifiers).
--- @param creature creature The companion's properties.
--- @param summoner creature The beastheart's properties.
--- @param modifiers table The summoner's accumulating modifier list.
function CharacterModifier:FillSummonerModifiers(context, creature, summoner, modifiers)
    local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.modifySummoner ~= nil then
        --only the summon->summoner direction. Modifiers explicitly set to the
        --summons direction must NOT push upward. A nil mode is treated as the
        --legacy "summoner" default for backward compatibility.
        if self:try_get("mode", "summoner") ~= "summoner" then
            return
        end
        self:InstallSymbolsFromContext(context)
        typeInfo.modifySummoner(self, creature, summoner, modifiers)
    end
end

--- Dispatcher invoked from a SUMMON's creature:FillTemporalActiveModifiers
--- (DMHub Game Rules/Creature.lua). Each of the summoner's active modifiers is
--- asked, in turn, whether it pushes modifiers DOWN onto this summon. Only
--- modsummoner modifiers whose mode == "summons" contribute.
--- @param context table Modifier context (the entry from GetActiveModifiers).
--- @param summoner creature The summoner's properties.
--- @param summon creature The summon's properties (the creature being modified).
--- @param modifiers table The summon's accumulating modifier list.
function CharacterModifier:FillSummonsModifiers(context, summoner, summon, modifiers)
    local typeInfo = CharacterModifier.TypeInfo[self.behavior] or {}
    if typeInfo.modifySummons ~= nil then
        if self:try_get("mode", "summoner") ~= "summons" then
            return
        end
        self:InstallSymbolsFromContext(context)
        typeInfo.modifySummons(self, summoner, summon, modifiers)
    end
end
