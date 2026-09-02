local mod = dmhub.GetModLoading()

--- One hero at the table. Who is present decides the language patience bonus.
--- @class NEGParticipant
--- @field charid string
--- @field name string
--- @field included boolean
NEGParticipant = RegisterGameType("NEGParticipant")

NEGParticipant.name = ""
NEGParticipant.included = true

--- @param args nil|table
--- @return NEGParticipant
function NEGParticipant.CreateNew(args)
    return NEGParticipant.new(args or {})
end

--- A negotiation in play. Holds its own copy of the definition, so editing the
--- prepared version mid-run does not disturb it.
--- @class NEGLive
--- @field defid string what it was started from, for the library's play marker
--- @field def NEGDefinition a copy, never the library's object
--- @field interest number
--- @field patience number
--- @field showInterest boolean whether the table sees the interest scale
--- @field showPatience boolean whether the table sees the patience scale
--- @field languageBonus number patience granted for speaking their tongue
--- @field languageSpeakers string[] the heroes who earned it
--- @field revealedTraits table<string, boolean> trait rows the table has seen
--- @field status string
--- @field presented boolean whether the board is on the players' screens
NEGLive = RegisterGameType("NEGLive")

NEGLive.interest = 2
NEGLive.patience = 3
NEGLive.showInterest = false
NEGLive.showPatience = false
NEGLive.languageBonus = 0
NEGLive.status = NEGConstants.statusRunning
NEGLive.presented = false

--- Declared on the type so a document mutation can read them as plain fields
--- rather than through accessors that raise mid-transaction. Writers copy
--- before assigning, so these shared defaults are never written into.
NEGLive.revealedTraits = {}
NEGLive.participants = {}

--- Who is standing where, keyed by slot: argumentLead, argumentAssist, learn.
--- Each entry is {charid, attrId, skillId}.
NEGLive.slots = {}

--- A roll out with a player, or nil. {slot, track, actionId, actionFor}.
NEGLive.resolution = nil

--- What the assist's roll earned the lead, harvested when it comes back.
NEGLive.assistTier = 0

--- Completed rolls, keyed by slot.
NEGLive.rolls = {}

--- Whether the argument appeals to a motivation. Never sent to the roller;
--- decides which outcome ladder the returned tier is read against.
NEGLive.appealMotivation = false

--- Heroes who have taken a test since the floor last turned over. The set
--- clears once everyone is in it.
NEGLive.acted = {}

--- Whether the table can currently see the NPC's offer. Cleared whenever
--- interest moves, because the offer moved with it.
NEGLive.offerShared = false

--- Run the negotiation in the open: the table sees both scales, the offer, and
--- the real tier ladders on their roll dialogs. Motivations and pitfalls are
--- unaffected and stay behind their own eyes.
NEGLive.open = false

--- Set when the Director clears a read of the room, cleared when an argument
--- is made. The rules bar a second read until then.
NEGLive.learnLocked = false

--- The journal page that launched this, so ending it can tick that Run row.
NEGLive.launchedFromDocid = ""

--- Heroes on the map, and only those. The engine's prompt gate tests
--- `dmhub.GetTokenById(tokid) ~= nil` OUTSIDE its forceuserid disjunct
--- (Draw Steel UI/DSRequestRollsDialog.lua), and that call is loaded-map only,
--- so an off-map hero cannot be asked to roll by any means.
--- @return NEGParticipant[]
function NEGLive.EligibleParticipants()
    local placed = {}
    for _, token in ipairs(dmhub.allTokens) do
        if token ~= nil and token.valid then
            placed[token.charid] = true
        end
    end

    local result = {}
    for _, charid in ipairs(NEGRules.HeroRoster()) do
        if placed[charid] then
            local token = dmhub.GetCharacterById(charid)
            result[#result + 1] = NEGParticipant.CreateNew{
                charid = charid,
                name = token ~= nil and token.name or "",
                included = true,
            }
        end
    end
    return result
end

--- A negotiation ready to be set up. The language bonus is applied at Start,
--- once the roster is settled.
--- @param def NEGDefinition
--- @return NEGLive
function NEGLive.FromDefinition(def)
    return NEGLive.new{
        defid = def:GetID(),
        def = DeepCopy(def),
        revealedTraits = {},
        participants = NEGLive.EligibleParticipants(),
        interest = NEGConstants.Clamp(def:try_get("interest", NEGDefinition.interest),
            NEGConstants.scaleMin, NEGConstants.scaleMax),
        patience = NEGConstants.Clamp(def:try_get("patience", NEGDefinition.patience),
            NEGConstants.scaleMin, NEGConstants.scaleMax),
        languageBonus = 0,
        languageSpeakers = {},
        showInterest = def:try_get("showInterest", false),
        showPatience = def:try_get("showPatience", false),
        status = NEGConstants.statusSetup,
        presented = false,
    }
end

--- The charids of the heroes actually taking part.
--- @return string[]
function NEGLive:IncludedCharids()
    local result = {}
    for _, p in ipairs(self:try_get("participants", {})) do
        if p:try_get("included", true) then
            result[#result + 1] = p.charid
        end
    end
    return result
end

--- @return NEGDefinition|nil
function NEGLive:Definition()
    return self:try_get("def")
end

--- @return string
function NEGLive:Name()
    local def = self:Definition()
    return def ~= nil and def:try_get("name", "") or ""
end

--- @return string
function NEGLive:NpcName()
    local def = self:Definition()
    return def ~= nil and def:try_get("npcName", "") or ""
end

--- What the NPC is offering right now, in the Director's own words. Falls back
--- to the rulebook's shape of answer when nothing was written for this score.
--- @return string
function NEGLive:OfferText()
    local def = self:Definition()
    local written = def ~= nil and def:GetOffer(self.interest) or ""
    if trim(written) ~= "" then
        return written
    end
    return NEGRules.OfferDetail(self.interest)
end

--- A negotiation ends of its own accord at either end of the interest scale or
--- when patience runs out. The Director is told, and closes it themself.
--- @return boolean
function NEGLive:AtTerminal()
    return self.interest <= NEGConstants.scaleMin
        or self.interest >= NEGConstants.scaleMax
        or self.patience <= NEGConstants.scaleMin
end

--- Why it is over, or an empty string while it is not.
--- @return string
function NEGLive:TerminalReason()
    if self.interest >= NEGConstants.scaleMax then
        return "Interest is full. This is their final offer."
    end
    if self.interest <= NEGConstants.scaleMin then
        return "Interest is gone. They will not deal."
    end
    if self.patience <= NEGConstants.scaleMin then
        return "Patience is spent. This is their final offer."
    end
    return ""
end

--- The one negotiation in play, and everything that moves it.
NEGRun = RegisterGameType("NEGRun")

mod:RegisterDocumentForCheckpointBackups(NEGConstants.activeRunDoc)

--- @return LuaCodeModDocumentSnapshot
function NEGRun.Doc()
    return mod:GetDocumentSnapshot(NEGConstants.activeRunDoc)
end

--- @return string monitorGame path for the live negotiation
function NEGRun.DocPath()
    return mod:GetDocumentPath(NEGConstants.activeRunDoc)
end

--- Whether this hero can be asked to roll. Checked live, not from setup.
--- @param charid string
--- @return boolean
function NEGRun.CanBePrompted(charid)
    return dmhub.GetTokenById(charid) ~= nil
end

--- @param description string
--- @param fn fun(doc: table)
function NEGRun.Mutate(description, fn)
    local doc = NEGRun.Doc()
    doc:BeginChange()
    fn(doc.data)
    doc:CompleteChange(description)
end

--- @return NEGLive|nil
function NEGRun.Active()
    local doc = NEGRun.Doc()
    if doc == nil or doc.data == nil then
        return nil
    end
    return doc.data.live
end

--- The live negotiation, if it came from this prepared one.
--- @param defid string
--- @return NEGLive|nil
function NEGRun.ActiveFor(defid)
    local live = NEGRun.Active()
    if live ~= nil and live:try_get("defid") == defid then
        return live
    end
    return nil
end

--- Open a prepared negotiation's setup step. One negotiation at a time.
--- @param defid string
--- @param docid nil|string the journal page that launched it
--- @return boolean whether it opened
function NEGRun.BeginSetup(defid, docid)
    if NEGRun.Active() ~= nil then
        return false
    end

    local def = NEGDefinition.GetByID(defid)
    if def == nil then
        return false
    end

    local live = NEGLive.FromDefinition(def)
    live.launchedFromDocid = docid or ""

    NEGRun.Mutate("Begin negotiation setup", function(data)
        data.live = live
    end)
    return true
end

--- Tick the Run row for the page that launched this negotiation, if it came
--- from one. RunAgenda loads late, hence the rawget.
--- @param docid string
local function MarkRunItemDone(docid)
    local agenda = rawget(_G, "RunAgenda")
    if agenda == nil or docid == nil or docid == "" then
        return
    end

    local items = agenda.GetItems()
    local touched = false

    for _, item in ipairs(items) do
        if item.docid == docid and item.done ~= true then
            item.done = true
            touched = true
        end
    end

    if touched then
        agenda.SetItems(items, "Negotiation complete")
    end
end

--- @param charid string
--- @param included boolean
function NEGRun.SetParticipantIncluded(charid, included)
    NEGRun.Mutate("Change negotiation roster", function(data)
        local live = data.live
        if live == nil then
            return
        end
        for _, p in ipairs(live.participants) do
            if p.charid == charid then
                p.included = included
                return
            end
        end
    end)
end

--- What the current roster would open on.
--- @param live NEGLive
--- @return number patience
--- @return number bonus
--- @return string[] speakers
function NEGRun.PreviewOpening(live)
    local def = live:Definition()
    return NEGRules.OpeningPatience(
        live.patience,
        def ~= nil and def:try_get("languageId", "") or "",
        live:IncludedCharids())
end

--- Open the negotiation, banking the language patience bonus.
function NEGRun.Start()
    local live = NEGRun.Active()
    if live == nil then
        return
    end

    local patience, bonus, speakers = NEGRun.PreviewOpening(live)

    NEGRun.Mutate("Start negotiation", function(data)
        local target = data.live
        if target == nil then
            return
        end
        target.status = NEGConstants.statusRunning
        target.patience = patience
        target.languageBonus = bonus
        target.languageSpeakers = speakers
    end)
end

--- Back to setup, scales restored to what the negotiation was prepared with.
function NEGRun.Reset()
    local live = NEGRun.Active()
    if live == nil then
        return
    end

    local def = live:Definition()
    local interest = def ~= nil
        and def:try_get("interest", NEGDefinition.interest)
        or NEGDefinition.interest
    local patience = def ~= nil
        and def:try_get("patience", NEGDefinition.patience)
        or NEGDefinition.patience

    NEGRun.Mutate("Reset negotiation", function(data)
        local target = data.live
        if target == nil then
            return
        end
        target.status = NEGConstants.statusSetup
        target.interest = interest
        target.patience = patience
        target.languageBonus = 0
        target.languageSpeakers = {}
        target.revealedTraits = {}
        target.presented = false
    end)

    GameHud.HidePresentedDialog()
end

--- Abandon a negotiation that has not started.
function NEGRun.Discard()
    NEGRun.Mutate("Cancel negotiation", function(data)
        data.live = nil
    end)
    GameHud.HidePresentedDialog()
end

--- @param which string NEGConstants.scaleInterest or scalePatience
--- @param value number
function NEGRun.SetScale(which, value)
    NEGRun.Mutate("Set negotiation scale", function(data)
        local live = data.live
        if live == nil then
            return
        end
        live[which] = NEGConstants.Clamp(value,
            NEGConstants.scaleMin, NEGConstants.scaleMax)

        --Interest moved, so the shared offer is now the wrong one.
        if which == NEGConstants.scaleInterest then
            live.offerShared = false
        end
    end)
end

--- @param shared boolean
function NEGRun.SetOfferShared(shared)
    NEGRun.Mutate("Share negotiation offer", function(data)
        local live = data.live
        if live ~= nil then
            live.offerShared = shared
        end
    end)
end

--- @return boolean
function NEGRun.IsOfferShared()
    local live = NEGRun.Active()
    return live ~= nil and live:try_get("offerShared", false)
end

--- What is standing in one slot, or nil.
--- @param live NEGLive
--- @param slot string
--- @return table|nil
function NEGRun.Slot(live, slot)
    if live == nil then
        return nil
    end
    return live:try_get("slots", {})[slot]
end

--- Every hero at the table who is not already standing in a slot, each
--- carrying whether they have already taken a test this time around.
--- @param live NEGLive
--- @return {charid: string, name: string, acted: boolean}[]
function NEGRun.FreeHeroes(live)
    local taken = {}
    for _, entry in pairs(live:try_get("slots", {})) do
        if entry.charid ~= nil then
            taken[entry.charid] = true
        end
    end

    local acted = live:try_get("acted", {})

    local result = {}
    for _, p in ipairs(live:try_get("participants", {})) do
        local charid = p.charid
        if p:try_get("included", true) and taken[charid] ~= true then
            result[#result + 1] = {
                charid = charid,
                name = p:try_get("name", ""),
                acted = acted[charid] == true,
            }
        end
    end
    return result
end

--- Clear one track: its heroes go back to the tray marked spent and its roll
--- is forgotten. Once everyone is spent the set clears, turning the round over.
--- @param track string
--- @param slotKeys string[]
function NEGRun.ResetTrack(track, slotKeys)
    NEGRun.Mutate("Reset negotiation track", function(data)
        local live = data.live
        if live == nil then
            return
        end

        local acted = {}
        for key, value in pairs(live.acted) do
            acted[key] = value
        end

        local slots = {}
        for key, entry in pairs(live.slots) do
            slots[key] = entry
        end

        local rolls = {}
        for key, value in pairs(live.rolls) do
            rolls[key] = value
        end

        for _, slotKey in ipairs(slotKeys) do
            local entry = slots[slotKey]
            if entry ~= nil and entry.charid ~= nil then
                acted[entry.charid] = true
            end
            slots[slotKey] = nil
            rolls[slotKey] = nil
        end

        --Everyone spent means nobody is.
        local anyFresh = false
        for _, p in ipairs(live.participants) do
            if p.included ~= false and acted[p.charid] ~= true then
                anyFresh = true
            end
        end
        if not anyFresh then
            acted = {}
        end

        live.acted = acted
        live.slots = slots
        live.rolls = rolls

        --Clearing a read locks it; clearing an argument is what frees it again.
        if track == NEGConstants.trackArgument then
            live.assistTier = 0
            live.appealMotivation = false
            live.learnLocked = false
        else
            live.learnLocked = true
        end
    end)
end

--- Copy, change, put back. Never writes into the type's shared default table.
--- @param slot string
--- @param apply fun(entry: table|nil): table|nil
--- @param description string
local function MutateSlot(slot, apply, description)
    NEGRun.Mutate(description, function(data)
        local live = data.live
        if live == nil then
            return
        end

        local slots = {}
        for key, entry in pairs(live.slots) do
            slots[key] = entry
        end
        slots[slot] = apply(slots[slot])
        live.slots = slots
    end)
end

--- Stand a hero in a slot, taking them off any other: one hero cannot both
--- lead an argument and read the room.
--- @param slot string
--- @param charid string
function NEGRun.Stage(slot, charid)
    NEGRun.Mutate("Place negotiator", function(data)
        local live = data.live
        if live == nil then
            return
        end

        local slots = {}
        for key, entry in pairs(live.slots) do
            if entry.charid ~= charid then
                slots[key] = entry
            end
        end

        local existing = slots[slot]
        slots[slot] = {
            charid = charid,
            attrId = existing ~= nil and existing.attrId or NEGConstants.argumentAttributes[1],
            skillId = existing ~= nil and existing.skillId or "",
        }

        live.slots = slots
    end)
end

--- @param slot string
function NEGRun.Unstage(slot)
    MutateSlot(slot, function()
        return nil
    end, "Remove negotiator")
end

--- @param value boolean
function NEGRun.SetOpen(value)
    NEGRun.Mutate("Set negotiation openness", function(data)
        if data.live ~= nil then
            data.live.open = value
        end
    end)
end

--- @return boolean
function NEGRun.IsOpen()
    local live = NEGRun.Active()
    return live ~= nil and live:try_get("open", false)
end

--- @param value boolean
function NEGRun.SetAppealMotivation(value)
    NEGRun.Mutate("Set negotiation appeal", function(data)
        if data.live ~= nil then
            data.live.appealMotivation = value
        end
    end)
end

--- The roll a slot has already made, or nil.
--- @param live NEGLive
--- @param slot string
--- @return table|nil
function NEGRun.RollFor(live, slot)
    if live == nil then
        return nil
    end
    return live:try_get("rolls", {})[slot]
end

--- Clear the floor for the next argument: slots emptied, rolls forgotten, the
--- assist's grant spent.
function NEGRun.ClearFloor()
    NEGRun.Mutate("Clear negotiation floor", function(data)
        local live = data.live
        if live == nil then
            return
        end
        live.slots = {}
        live.rolls = {}
        live.assistTier = 0
        live.appealMotivation = false
    end)
end

--- @param slot string
--- @param key string "attrId" or "skillId"
--- @param value string
function NEGRun.SetSlotField(slot, key, value)
    MutateSlot(slot, function(entry)
        if entry == nil then
            return nil
        end
        local updated = {
            charid = entry.charid,
            attrId = entry.attrId,
            skillId = entry.skillId,
        }
        updated[key] = value
        return updated
    end, "Set negotiation test")
end

--- @param which string
--- @param delta number
function NEGRun.AdjustScale(which, delta)
    local live = NEGRun.Active()
    if live == nil then
        return
    end
    NEGRun.SetScale(which, live[which] + delta)
end

--- Show or hide one scale to the table.
--- @param which string
--- @param shown boolean
function NEGRun.SetRevealed(which, shown)
    local key = cond(which == NEGConstants.scaleInterest, "showInterest", "showPatience")
    NEGRun.Mutate("Reveal negotiation scale", function(data)
        local live = data.live
        if live ~= nil then
            live[key] = shown
        end
    end)
end

--- @param which string
--- @return boolean
function NEGRun.IsRevealed(which)
    local live = NEGRun.Active()
    if live == nil then
        return false
    end
    if which == NEGConstants.scaleInterest then
        return live:try_get("showInterest", false)
    end
    return live:try_get("showPatience", false)
end

--- Motivations or pitfalls, alphabetical, each with its revealed state.
--- @param live NEGLive
--- @param kind string "motivations" or "pitfalls"
--- @return {id: string, trait: string, name: string, note: string, revealed: boolean}[]
function NEGRun.Traits(live, kind)
    local def = live ~= nil and live:Definition() or nil
    if def == nil then
        return {}
    end

    local revealed = live:try_get("revealedTraits", {})
    local result = {}

    for _, row in ipairs(def:try_get(kind, {})) do
        local trait = row:try_get("trait", "")
        result[#result + 1] = {
            id = row.id,
            trait = trait,
            name = NEGRules.TraitName(trait),
            note = row:try_get("note", ""),
            revealed = revealed[row.id] == true,
        }
    end

    table.sort(result, function(a, b)
        return string.lower(a.name) < string.lower(b.name)
    end)

    return result
end

--- Show or hide one motivation or pitfall to the table.
--- @param rowId string
--- @param shown boolean
function NEGRun.SetTraitRevealed(rowId, shown)
    NEGRun.Mutate("Reveal negotiation trait", function(data)
        local live = data.live
        if live == nil then
            return
        end
        --Copied before write: a live that never got its own table would
        --otherwise mutate the type's shared default.
        local revealed = {}
        for key, value in pairs(live.revealedTraits) do
            revealed[key] = value
        end
        revealed[rowId] = cond(shown, true, nil)
        live.revealedTraits = revealed
    end)
end

--- @return boolean
function NEGRun.IsPresented()
    local live = NEGRun.Active()
    return live ~= nil and live:try_get("presented", false)
end

--- @param hostPanel Panel the Director's window, which owns the presentation
function NEGRun.PresentToPlayers(hostPanel)
    NEGRun.Mutate("Show negotiation", function(data)
        if data.live ~= nil then
            data.live.presented = true
        end
    end)
    GameHud.PresentDialogToUsers(hostPanel, NEGConstants.dialogId, {})
end

function NEGRun.HideFromPlayers()
    NEGRun.Mutate("Hide negotiation", function(data)
        if data.live ~= nil then
            data.live.presented = false
        end
    end)
    GameHud.HidePresentedDialog()
end

--- Close the negotiation but leave it on screen, so the Director can read the
--- final offer out before clearing it away.
function NEGRun.End()
    local live = NEGRun.Active()
    local res = live ~= nil and live:try_get("resolution") or nil
    if res ~= nil and res.actionId ~= nil then
        dmhub.CancelActionRequest(res.actionId)
    end

    --The board stays up: the table reads the final offer off it. Clear takes
    --it down.
    NEGRun.Mutate("End negotiation", function(data)
        if data.live ~= nil then
            data.live.status = NEGConstants.statusEnded
            data.live.resolution = nil
        end
    end)

    if live ~= nil then
        MarkRunItemDone(live:try_get("launchedFromDocid", ""))
    end
end

--==============================================================================
-- ASKING A PLAYER TO ROLL
--==============================================================================

--- The player-facing roll. Two independent axes meet here: `rollType` picks
--- the dialog, while GetModifiers passes a type from the modifier pipeline's
--- own closed vocabulary. A private id on that second axis silently drops
--- every Tests-scoped modifier, Skilled included.
RollCheck.RegisterCustom{
    id = NEGConstants.rollCheckId,
    rollType = "power_roll_custom",

    Describe = function(check, isplayer)
        return check.info.explanation
    end,

    GetRoll = function(check, creature)
        return "2d10 + " .. creature:AttributeMod(check.info.attrid)
    end,

    GetModifiers = function(check, creature)
        local result = creature:GetModifiersForPowerRoll(
            check:GetRoll(creature),
            NEGConstants.modifierRollType,
            { attribute = check.info.attrid, skills = check.skills })

        --Skilled is offered rather than applied: the pipeline cannot know the
        --skill was chosen for this test, so proficiency is confirmed here.
        local skillsTable = GetTableCached("Skills")
        for _, skillid in ipairs(check.skills or {}) do
            local skill = skillsTable[skillid]
            if skill ~= nil and creature:ProficientInSkill(skill) then
                for _, entry in ipairs(result) do
                    if entry.modifier.name == "Skilled" then
                        entry.hint.result = true
                    end
                end
            end
        end

        --The grant crosses the wire as a plain id and becomes a modifier here,
        --where the lead's creature is in hand. Appending it raw would raise:
        --the dialog reads `.modifier` off each entry, so it goes through the
        --same wrapper sequence the engine uses.
        local grant = check.info.assistGrant
        if grant ~= nil and grant ~= "" then
            local options = { attribute = check.info.attrid, skills = check.skills }
            local m = CharacterModifier.new{
                behavior = "power",
                rollType = NEGConstants.modifierRollType,
                modtype = grant,
                activationCondition = true,
                guid = dmhub.GenerateGuid(),
                name = check.info.assistName or "Assisted",
                description = check.info.assistDescription or "An ally assisted this test.",
                keywords = {},
            }

            local entry = { mod = m }
            local described = m:DescribeModifyPowerRoll(entry, creature,
                NEGConstants.modifierRollType, options)
            if described ~= nil then
                described.hint = described.modifier:HintModifyPowerRolls(entry, creature,
                    NEGConstants.modifierRollType, options)
                if described.hint ~= nil then
                    result[#result + 1] = described
                end
            end
        end

        for _, entry in pairs(check:try_get("modifiers", {})) do
            result[#result + 1] = entry
        end

        return result
    end,

    ShowDialog = function(check, dialogOptions)
        --A negotiation roll is read, not admired: the tier table has to be
        --legible over whatever the map is showing. The frame's blur is what
        --makes it see-through, so opacity alone would not do it.
        dialogOptions.solidDialog = true

        local tiers = check:try_get("options", {}).tiers

        if tiers ~= nil then
            dialogOptions.rollProperties = RollPropertiesPowerTable.new{
                tiers = DeepCopy(tiers),
            }
            dialogOptions.PopulateCustom =
                ActivatedAbilityPowerRollBehavior.GetPowerTablePopulateCustom(
                    dialogOptions.rollProperties, dialogOptions.creature)
        end

        return GameHud.instance.rollDialog.data.ShowDialog(dialogOptions)
    end,
}

--- What an assist's tier hands the lead. The montage's ladder.
--- @param tier number
--- @return string modtype
function NEGRun.AssistGrant(tier)
    if tier >= 3 then
        return "double_edge"
    end
    if tier >= 2 then
        return "edge"
    end
    return "bane"
end

--- What a roller is shown before they roll. An assist always gets its real
--- ladder, which gives nothing away. The rest get vague bands unless the
--- negotiation is open, because the real ladder leaks the NPC's motivations.
--- @param live NEGLive
--- @param slot string
--- @param track string
--- @return string[]
local function TiersFor(live, slot, track)
    if slot == NEGConstants.slotAssist then
        local tiers = {}
        for tier = 1, 3 do
            local grant = NEGRun.AssistGrant(tier)
            tiers[tier] = string.format("The Lead rolls with %s %s",
                cond(grant == "edge", "an", "a"),
                string.gsub(grant, "_", " "))
        end
        return tiers
    end

    if live:try_get("open", false) then
        return NEGRules.TierText(track, live:try_get("appealMotivation", false))
    end

    return DeepCopy(NEGConstants.tierBands)
end

--- Ask a hero's player for a test.
--- @param live NEGLive
--- @param slot string
--- @param track string
--- @param grant string|nil
--- @param grantFrom string|nil
--- @return string|nil actionId
local function SendRequest(live, slot, track, grant, grantFrom)
    local entry = NEGRun.Slot(live, slot)
    if entry == nil then
        return nil
    end

    local attrName = NEGRules.CharacteristicName(entry.attrId)

    local skills = {}
    if entry.skillId ~= nil and entry.skillId ~= "" then
        skills[1] = entry.skillId
    end

    local title = cond(track == NEGConstants.trackLearn,
        "Read the room", "Make an argument")
    if slot == NEGConstants.slotAssist then
        title = "Assist: Make an argument"
    end

    local explanation = string.format("%s (%s)", title, attrName)

    local check = RollCheck.new{
        type = NEGConstants.rollCheckId,
        id = NEGConstants.rollCheckId,
        text = title,
        explanation = explanation,
        skills = skills,
        modifiers = {},
        options = { tiers = TiersFor(live, slot, track) },
        info = {
            attrid = entry.attrId,
            explanation = explanation,
            assistGrant = grant,
            assistName = grant ~= nil
                and string.format("Assisted by %s", grantFrom or "an ally") or nil,
            assistDescription = grant ~= nil
                and string.format("%s's assist gave you a %s.",
                    grantFrom or "An ally", string.gsub(grant, "_", " ")) or nil,
        },
    }

    return dmhub.SendActionRequest(RollRequest.new{
        title = title,
        checks = { check },
        tokens = { [entry.charid] = {} },
    })
end

--- Whether this client may move this hero. The Director may move anyone; a
--- player may move only the characters they control.
--- @param charid string
--- @return boolean
function NEGRun.CanManage(charid)
    if dmhub.isDM then
        return true
    end
    local token = dmhub.GetCharacterById(charid)
    return token ~= nil and token.canControl == true
end

--- @param live NEGLive
--- @param charid string
--- @return string
function NEGRun.ParticipantName(live, charid)
    for _, p in ipairs(live:try_get("participants", {})) do
        if p.charid == charid then
            return p:try_get("name", "")
        end
    end
    return ""
end

--- Ask for the next roll this track needs. On an argument the assist goes
--- first, because what it earns rides on the lead's roll.
--- @param track string
function NEGRun.TriggerRoll(track)
    local live = NEGRun.Active()
    if live == nil then
        printf("NEG:: TriggerRoll(%s) refused - no live negotiation", tostring(track))
        return
    end

    --A resolution outlives its request, and lives in the shared document, so a
    --stale one survives reloads. Refusing on its mere presence makes every
    --later roll a silent no-op; check whether it is still live first.
    local res = live:try_get("resolution")
    if res ~= nil then
        local req = res.actionId ~= nil
            and dmhub.GetPlayerActionRequest(res.actionId) or nil
        local info = req ~= nil and req.info.tokens[res.actionFor] or nil
        local status = info ~= nil and info.status or nil

        if req == nil or status == "cancel" or status == "complete" then
            printf("NEG:: TriggerRoll(%s) clearing stale resolution slot=%s status=%s",
                tostring(track), tostring(res.slot), tostring(status))
            NEGRun.Mutate("Clear stale negotiation roll", function(data)
                if data.live ~= nil then
                    data.live.resolution = nil
                end
            end)
            live = NEGRun.Active()
        else
            printf("NEG:: TriggerRoll(%s) refused - roll still out on track=%s slot=%s",
                tostring(track), tostring(res.track), tostring(res.slot))
            return
        end
    end

    local slot = NEGConstants.slotLearn
    local grant, grantFrom = nil, nil

    if track == NEGConstants.trackArgument then
        local assist = NEGRun.Slot(live, NEGConstants.slotAssist)
        if assist ~= nil and live:try_get("assistTier", 0) == 0 then
            slot = NEGConstants.slotAssist
        else
            slot = NEGConstants.slotLead
            local tier = live:try_get("assistTier", 0)
            if assist ~= nil and tier > 0 then
                grant = NEGRun.AssistGrant(tier)
                grantFrom = NEGRun.ParticipantName(live, assist.charid)
            end
        end
    end

    local entry = NEGRun.Slot(live, slot)
    if entry == nil then
        printf("NEG:: TriggerRoll(%s) refused - nothing standing in slot %s",
            tostring(track), tostring(slot))
        return
    end

    --A request for an off-map character goes out and is never answered.
    if not NEGRun.CanBePrompted(entry.charid) then
        printf("NEG:: TriggerRoll(%s) refused - %s is not on the map, so cannot be prompted",
            tostring(track), tostring(NEGRun.ParticipantName(live, entry.charid)))
        gui.ModalMessage{
            title = "Not on the map",
            message = string.format(
                "%s is not on the current map, and the roll prompt cannot reach a character who is not. Place them on the map and try again.",
                NEGRun.ParticipantName(live, entry.charid)),
        }
        return
    end

    local actionId = SendRequest(live, slot, track, grant, grantFrom)
    if actionId == nil then
        printf("NEG:: TriggerRoll(%s) SendActionRequest returned nil for slot=%s charid=%s",
            tostring(track), tostring(slot), tostring(entry.charid))
        return
    end

    printf("NEG:: TriggerRoll(%s) sent slot=%s charid=%s actionId=%s",
        tostring(track), tostring(slot), tostring(entry.charid), tostring(actionId))

    NEGRun.Mutate("Request negotiation roll", function(data)
        if data.live ~= nil then
            data.live.resolution = {
                slot = slot,
                track = track,
                actionId = actionId,
                actionFor = entry.charid,
            }
        end
    end)
end

--- Drop an outstanding request and take the track out of resolution.
function NEGRun.CancelRoll()
    local live = NEGRun.Active()
    local res = live ~= nil and live:try_get("resolution") or nil
    if res ~= nil and res.actionId ~= nil then
        dmhub.CancelActionRequest(res.actionId)
    end

    NEGRun.Mutate("Cancel negotiation roll", function(data)
        if data.live ~= nil then
            data.live.resolution = nil
        end
    end)
end

--- Move a finished roll onto the negotiation. Stateless and idempotent: every
--- input is cloud state, so a reload picks up wherever the document says it is.
function NEGRun.PumpRolls()
    if not dmhub.isDM then
        return
    end

    local live = NEGRun.Active()
    if live == nil or live:try_get("status") ~= NEGConstants.statusRunning then
        return
    end

    local res = live:try_get("resolution")
    if res == nil or res.actionId == nil then
        return
    end

    local req = dmhub.GetPlayerActionRequest(res.actionId)

    --A request cleared out from under us takes its roll with it. Treat that as
    --never having asked: the Director presses the die again.
    if req == nil then
        NEGRun.Mutate("Clear negotiation roll", function(data)
            if data.live ~= nil then
                data.live.resolution = nil
            end
        end)
        return
    end

    local info = req.info.tokens[res.actionFor]
    local status = info ~= nil and info.status or nil

    if status == "cancel" then
        NEGRun.CancelRoll()
        return
    end

    if status ~= "complete" then
        return
    end

    --Tier comes from the numbers the request carries, not from the total
    --alone: two edges bump the tier without moving it.
    local rollInfo = {
        total = info.result,
        naturalRoll = info.naturalRoll,
        boons = info.boons,
        banes = info.banes,
    }
    local tier = RollUtils.DiceResultToTier(rollInfo)

    dmhub.CancelActionRequest(res.actionId)

    local wasAssist = res.slot == NEGConstants.slotAssist
    local track = res.track
    local entry = NEGRun.Slot(live, res.slot)

    --Read once here and stored, so both windows show the same sentence.
    local outcome = nil
    if not wasAssist then
        if track == NEGConstants.trackLearn then
            outcome = NEGRules.LearnOutcome(tier)
        else
            outcome = NEGRules.ArgumentOutcome(tier,
                live:try_get("appealMotivation", false), rollInfo.naturalRoll)
        end
    end

    local record = {
        tier = tier,
        total = rollInfo.total,
        naturalRoll = rollInfo.naturalRoll,
        boons = rollInfo.boons,
        banes = rollInfo.banes,
        charid = res.actionFor,
        attrId = entry ~= nil and entry.attrId or "",
        skillId = entry ~= nil and entry.skillId or "",
        outcomeText = outcome ~= nil and outcome.text or nil,
        interestDelta = outcome ~= nil and outcome.interest or 0,
        patienceDelta = outcome ~= nil and outcome.patience or 0,
    }

    NEGRun.Mutate("Record negotiation roll", function(data)
        local target = data.live
        if target == nil then
            return
        end
        target.resolution = nil

        local rolls = {}
        for key, value in pairs(target.rolls) do
            rolls[key] = value
        end
        rolls[res.slot] = record
        target.rolls = rolls

        if wasAssist then
            target.assistTier = tier
        end

        --The ladder is unambiguous once the appeal is known. The scales stay
        --clickable for what the rules leave to judgment: a caught lie, a
        --well-roleplayed argument taken as a tier 3.
        if outcome ~= nil then
            if outcome.interest ~= 0 then
                target.interest = NEGConstants.Clamp(
                    target.interest + outcome.interest,
                    NEGConstants.scaleMin, NEGConstants.scaleMax)

                --Interest moved, so the offer moved with it.
                target.offerShared = false
            end

            if outcome.patience ~= 0 then
                target.patience = NEGConstants.Clamp(
                    target.patience + outcome.patience,
                    NEGConstants.scaleMin, NEGConstants.scaleMax)
            end
        end
    end)

    if outcome ~= nil then
        printf("NEG:: roll applied track=%s tier=%d interest%+d patience%+d - %s",
            tostring(track), tier, outcome.interest, outcome.patience, outcome.text)
    end

    --The assist only ever set up the lead's roll, so it rolls straight on.
    if wasAssist then
        NEGRun.TriggerRoll(track)
    end
end

--- Ticked rather than driven from the panel: closing the window destroys the
--- panel, and the harvest has to survive that.
local function Tick()
    if mod.unloaded then
        return
    end
    if dmhub.isDM then
        NEGRun.PumpRolls()
    end
    dmhub.Schedule(0.5, Tick)
end

dmhub.Schedule(0.5, Tick)

--- Discard the whole run and go back to the library. Cancels any outstanding
--- request, so nothing survives to block the next negotiation.
function NEGRun.Clear()
    local live = NEGRun.Active()
    local res = live ~= nil and live:try_get("resolution") or nil
    if res ~= nil and res.actionId ~= nil then
        dmhub.CancelActionRequest(res.actionId)
    end

    NEGRun.Mutate("Clear negotiation", function(data)
        data.live = nil
    end)

    GameHud.HidePresentedDialog()
    printf("NEG:: negotiation cleared")
end
