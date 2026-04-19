local mod = dmhub.GetModLoading()

--- @class SpellcastingFeature
--- @field id string Unique identifier (default "Custom").
--- @field name string Display name.
--- @field attr string Spellcasting ability score id (e.g. "int", "wis", "cha").
--- @field level number Minimum character level to access this feature.
--- @field refreshType string How spells refresh: "prepared" or "known".
--- @field spellbook boolean If true, this class uses a spellbook.
--- @field spellbookSize number|string|table Number of spells the spellbook can hold.
--- @field spellbookSpells table[] List of spells in the spellbook.
--- @field spellLists table[] Spell lists available to this feature.
--- @field dc number Spell save DC base value.
--- @field attackBonus number Spell attack bonus base value.
--- @field maxSpellLevel number Maximum spell slot level available.
--- @field numKnownCantrips number|string|table Number of cantrips known.
--- @field numKnownSpells number|string|table Number of spells known.
--- @field knownCantrips string[] Ids of known cantrips.
--- @field knownSpells string[] Ids of known spells.
--- @field memorizedSpells string[] Ids of memorized (prepared) spells.
--- @field grantedSpells string[] Ids of spells automatically granted by this feature.
--- @field upcastingType string When upcasting is allowed: "cast", "prepared", or "none".
--- @field canUseSpellSlots boolean If true, the caster can spend spell slots.
--- @field ritualCasting boolean If true, the caster can cast rituals without expending a slot.
SpellcastingFeature = RegisterGameType("SpellcastingFeature")

SpellcastingFeature.id = "Custom"
SpellcastingFeature.name = "Spellcasting"
SpellcastingFeature.attr = "int"
SpellcastingFeature.level = 1
SpellcastingFeature.refreshType = "prepared" --known or prepared.
SpellcastingFeature.spellbook = false
SpellcastingFeature.spellbookSize = 0
SpellcastingFeature.spellbookSpells = {}
SpellcastingFeature.spellLists = {}
SpellcastingFeature.dc = 10
SpellcastingFeature.attackBonus = 2
SpellcastingFeature.maxSpellLevel = 1
SpellcastingFeature.numKnownCantrips = 0
SpellcastingFeature.numKnownSpells = 0
SpellcastingFeature.knownCantrips = {}
SpellcastingFeature.knownSpells = {}
SpellcastingFeature.memorizedSpells = {}
SpellcastingFeature.grantedSpells = {} --list of spellid's granted to this feature.
SpellcastingFeature.upcastingType = "cast" --none, cast, prepared
SpellcastingFeature.canUseSpellSlots = true

SpellcastingFeature.ritualCasting = false


SpellcastingFeature.RefreshTypeOptions = {
    {
        id = "prepared",
        text = "Prepared",
    },
    {
        id = "known",
        text = "Known",
    },
}

SpellcastingFeature.UpcastingOptions = {
    {
        id = "cast",
        text = "When casting",
    },
    {
        id = "prepared",
        text = "When preparing",
    },
    {
        id = "none",
        text = "None",
    },
}


--some utils for encoding/decoding spellcasting spellids with levels included.

function SpellcastingFeature.EncodeSpellId(spellid, level)
    if level == nil then
        return spellid
    end
    return string.format("level:%s:%s", tostring(level), spellid)
end

function SpellcastingFeature.DecodeSpellId(spellid)
    if string.starts_with(spellid, "level:") == false then
        return spellid, nil
    end

    local level, id = string.match(spellid, "level:(%d+):(.+)")
    if level == nil then
        return spellid, nil
    end
    return id, tonumber(level)
end