local mod = dmhub.GetModLoading()


---@class RichEncounter
RichEncounter = RegisterGameType("RichEncounter", "RichTag")
RichEncounter.tag = "encounter"


function RichEncounter.Create()
    return RichEncounter.new{
        encounter = Encounter.new(),
    }
end

function RichEncounter.CreateDisplay(self)

    local resultPanel

    local m_balancedEncounter = self.encounter:CloneForNumberOfHeroes()
    local m_open = false

    --party strength for the difficulty pill and EV/budget readout. This must
    --agree with the encounter builder: the hero COUNT comes from the numheroes
    --setting (the same count the roster is balanced for via
    --CloneForNumberOfHeroes), while level and victories are averaged from the
    --hero tokens on the current map. Summing raw map tokens instead would
    --disagree with the builder whenever the map holds more or fewer hero
    --tokens than the party size setting.
    local function CurrentPartyStrength()
        local totalLevel = 0
        local totalVictories = 0
        local count = 0
        for _, tok in ipairs(dmhub.allTokens) do
            local props = tok.properties
            if props ~= nil and props:IsHero() then
                count = count + 1
                totalLevel = totalLevel + props:CharacterLevel()
                totalVictories = totalVictories + props:GetVictories()
            end
        end

        local level = 1
        local victories = 0
        if count > 0 then
            level = math.max(1, round(totalLevel / count))
            victories = math.max(0, round(totalVictories / count))
        end

        return Encounter.PartyStrength{
            level = level,
            victories = victories,
        }
    end

    --EV contributed by one group of the balanced encounter, using the same
    --minion math as Encounter.CountEDS.
    local function GroupEV(group)
        local ev = 0
        for monsterid, quantity in pairs(group.monsters) do
            local monsterAsset = assets.monsters[monsterid]
            if monsterAsset ~= nil then
                local entryEV = monsterAsset.properties:EV() * quantity
                if monsterAsset.properties.minion then
                    entryEV = round(entryEV / 4)
                end
                ev = ev + entryEV
            end
        end
        return ev
    end

    local function TotalCounts()
        local creatures = 0
        local ev = 0
        for _, group in ipairs(m_balancedEncounter.groups) do
            ev = ev + GroupEV(group)
            for _, quantity in pairs(group.monsters) do
                creatures = creatures + quantity
            end
        end
        return creatures, ev
    end

    local function VictoryConditionText()
        local chosen = self.encounter:try_get("victoryCondition", "all_defeated")
        for _, option in ipairs(Encounter.GetVictoryConditions(self.encounter)) do
            if option.id == chosen then
                return option.text
            end
        end
        return "All Monsters Defeated"
    end

    local tierClasses = {
        Trivial = "tierTrivial",
        Easy = "tierEasy",
        Standard = "tierStandard",
        Hard = "tierHard",
        Extreme = "tierExtreme",
    }
    local function SetTierClass(element, tier)
        for _, cls in pairs(tierClasses) do
            element:SetClass(cls, cls == tierClasses[tier])
        end
    end

    -- ============== header ==============

    local titleLabel = gui.Label{
        width = "100%",
        height = "auto",
        halign = "left",
        bold = true,
        fontSize = 16,
        minFontSize = 8,
        refreshTag = function(element)
            element.text = self.encounter:try_get("name", "Encounter")
        end,
    }

    local metaLabel = gui.Label{
        classes = {"encounterWidgetCaption"},
        width = "100%",
        height = "auto",
        halign = "left",
        fontSize = 11,
        refreshTag = function(element)
            local creatures = TotalCounts()
            element.text = string.format("%d creatures - %d groups - %s", creatures, #m_balancedEncounter.groups, VictoryConditionText())
        end,
    }

    local diffPill = gui.Label{
        classes = {"encounterWidgetPill"},
        width = "auto",
        height = "auto",
        hpad = 8,
        vpad = 3,
        valign = "center",
        fontSize = 11,
        bold = true,
        bgimage = true,
        refreshTag = function(element)
            local _, ev = TotalCounts()
            local tier = Encounter.DifficultyTier(ev, CurrentPartyStrength())
            element.text = tier
            SetTierClass(element, tier)
        end,
    }

    local evLabel = gui.Label{
        classes = {"encounterWidgetEV"},
        width = "auto",
        height = "auto",
        halign = "right",
        fontSize = 16,
        bold = true,
        refreshTag = function(element)
            local _, ev = TotalCounts()
            local strength = CurrentPartyStrength()
            element.text = string.format("%d / %d", ev, strength.total)
        end,
    }

    local chevronLabel = gui.Label{
        width = "auto",
        height = "auto",
        valign = "center",
        lmargin = 10,
        fontSize = 13,
        text = ">",
    }

    local headerPanel
    local bodyPanel

    local function SetOpen(open)
        m_open = open
        bodyPanel:SetClass("collapsed", not open)
        headerPanel:SetClass("open", open)
        chevronLabel.selfStyle.rotate = cond(open, -90, 0)
    end

    headerPanel = gui.Panel{
        classes = {"encounterWidgetHead"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        hpad = 12,
        vpad = 10,
        borderBox = true,
        bgimage = true,

        press = function(element)
            SetOpen(not m_open)
            gui.SetFocus(resultPanel)
        end,

        gui.Panel{
            classes = {"image"},
            bgimage = "icons/standard/Icon_App_EncounterCreator.png",
            width = 20,
            height = 20,
            valign = "center",
            rmargin = 10,
        },

        gui.Panel{
            flow = "vertical",
            width = "100%-200",
            height = "auto",
            valign = "center",
            titleLabel,
            metaLabel,
        },

        diffPill,

        gui.Panel{
            flow = "vertical",
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 10,

            evLabel,

            gui.Label{
                classes = {"encounterWidgetCaption"},
                width = "auto",
                height = "auto",
                halign = "right",
                fontSize = 9,
                text = "EV / budget",
            },
        },

        chevronLabel,
    }

    -- ============== expanded body ==============

    local bodyGroupsPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        refreshTag = function(element)
            local wavesById = {}
            for _, wave in ipairs(self.encounter:try_get("waves", {})) do
                wavesById[wave.id] = wave
            end

            local children = {}
            for gi, group in ipairs(m_balancedEncounter.groups) do
                local groupEV = GroupEV(group)

                local wave = nil
                if group.wave ~= nil then
                    wave = wavesById[group.wave]
                end

                --the DM-given group name when set; otherwise wave groups
                --default to their wave's name and start groups to the
                --positional default ("Group A").
                local caption = group.name
                if caption == nil or caption == "" then
                    if wave ~= nil then
                        caption = wave.name or "Reinforcements"
                    elseif gi <= 26 then
                        caption = string.format("Group %s", string.char(64 + gi))
                    else
                        caption = string.format("Group %d", gi)
                    end
                end
                if wave ~= nil then
                    if caption == wave.name then
                        caption = string.format("%s (%s)", caption, Encounter.WaveRoundText(wave))
                    else
                        caption = string.format("%s (%s, %s)", caption, wave.name, Encounter.WaveRoundText(wave))
                    end
                end

                children[#children + 1] = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    tmargin = cond(gi == 1, 0, 12),
                    bmargin = 6,

                    gui.Label{
                        classes = {"encounterWidgetCaption"},
                        width = "auto",
                        height = "auto",
                        valign = "center",
                        bold = true,
                        fontSize = 11,
                        text = caption,
                    },

                    gui.Label{
                        classes = {"encounterWidgetEV"},
                        width = "auto",
                        height = "auto",
                        valign = "center",
                        halign = "right",
                        fontSize = 11,
                        text = string.format("%d EV", groupEV),
                    },
                }

                --one chip per monster type in the group.
                local entryList = {}
                for monsterid, quantity in pairs(group.monsters) do
                    local monsterAsset = assets.monsters[monsterid]
                    if monsterAsset ~= nil then
                        entryList[#entryList + 1] = {
                            quantity = quantity,
                            asset = monsterAsset,
                            name = creature.GetTokenDescription(monsterAsset),
                        }
                    end
                end
                table.sort(entryList, function(a, b)
                    return a.name < b.name
                end)

                local chips = {}
                for _, entry in ipairs(entryList) do
                    local props = entry.asset.properties
                    local level = 0
                    if props ~= nil and props:IsMonster() then
                        level = props:Level()
                    end

                    local kind = string.format("Lvl %d", level)
                    if props ~= nil and props.minion then
                        kind = string.format("Minions - Lvl %d", level)
                    elseif props ~= nil then
                        local m = regex.MatchGroups(props:try_get("role", ""), "^(?<org>[a-zA-Z]+).*$")
                        if m ~= nil then
                            local org = string.lower(m.org)
                            if org == "leader" then
                                kind = string.format("Leader - Lvl %d", level)
                            elseif org == "solo" then
                                kind = string.format("Solo - Lvl %d", level)
                            end
                        end
                    end

                    local chipChildren = {}
                    if entry.asset.info ~= nil then
                        chipChildren[#chipChildren + 1] = gui.CreateTokenImage(entry.asset.info, {
                            width = 18,
                            height = 18,
                            valign = "center",
                            rmargin = 6,
                        })
                    end
                    chipChildren[#chipChildren + 1] = gui.Label{
                        width = "auto",
                        height = "auto",
                        valign = "center",
                        fontSize = 13,
                        text = string.format("%dx %s", entry.quantity, entry.name),
                    }
                    chipChildren[#chipChildren + 1] = gui.Label{
                        classes = {"encounterWidgetCaption"},
                        width = "auto",
                        height = "auto",
                        valign = "center",
                        lmargin = 6,
                        fontSize = 9,
                        text = kind,
                    }

                    chips[#chips + 1] = gui.Panel{
                        classes = {"encounterWidgetChip"},
                        flow = "horizontal",
                        width = "auto",
                        height = "auto",
                        hpad = 8,
                        vpad = 4,
                        borderBox = true,
                        rmargin = 6,
                        bmargin = 6,
                        bgimage = true,
                        children = chipChildren,
                    }
                end

                children[#children + 1] = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    wrap = true,
                    children = chips,
                }
            end

            element.children = children
        end,
    }

    -- ============== actions ==============

    --"Run Encounter" shows when this encounter's monsters are placed on the
    --map and combat has not started yet. Pressing it starts combat.
    local drawSteelButton = gui.Button{
        classes = {"collapsed"},
        width = 140,
        height = 30,
        fontSize = 13,
        bold = true,
        text = "Run Encounter",
        halign = "left",
        valign = "center",
        swallowPress = true,

        thinkTime = 1,
        think = function(element)
            element:FireEvent("refreshTag")
        end,
        refreshTag = function(element)
            local show = false
            local q = dmhub.initiativeQueue
            local inCombat = q ~= nil and not q.hidden
            if dmhub.isDM and not inCombat then
                --only show once we have monsters from this encounter on the map.
                for _,spawn in ipairs(self:try_get("spawns", {})) do
                    if dmhub.GetTokenById(spawn) ~= nil then
                        show = true
                        break
                    end
                end
            end
            element:SetClass("collapsed", not show)
        end,

        press = function(element)
            Encounter.DrawSteelWithEncounter(self.encounter, self:try_get("spawns", {}))
        end,
        hover = function(element)
            gui.Tooltip("Start combat with this encounter.")(element)
        end,
    }

    local footerPanel = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        valign = "center",

        thinkTime = 1,
        think = function(element)
            element:FireEvent("refreshTag")
        end,
        refreshTag = function(element)
            --check we have spawn locations for all monsters.
            local canspawn = true
            for _,group in ipairs(self.encounter:CloneForNumberOfHeroes().groups) do
                --reinforcement groups arrive later and are not placed up front, so
                --they do not need spawn locations to enable "Place on Map".
                if group.wave == nil then
                    local nmonsters = 0
                    for monsterid,quantity in pairs(group.monsters) do
                        nmonsters = nmonsters + quantity
                    end

                    if nmonsters > 0 and (group.spawnlocs == nil or #group.spawnlocs < nmonsters) then
                        canspawn = false
                    end
                end
            end

            local children = element.children

            for _,spawn in ipairs(self:try_get("spawns", {})) do
                local token = dmhub.GetTokenById(spawn)
                if token ~= nil then
                    --we have some spawns on the map, so offer to despawn.
                    children[1]:SetClass("collapsed", true)
                    children[2]:SetClass("collapsed", false)
                    children[3]:SetClass("collapsed", not canspawn)
                    return
                end
            end

            if canspawn then
                children[1]:SetClass("collapsed", false)
                children[2]:SetClass("collapsed", true)
                children[3]:SetClass("collapsed", true)
                return
            end

            children[1]:SetClass("collapsed", true)
            children[2]:SetClass("collapsed", true)
            children[3]:SetClass("collapsed", true)
        end,

        gui.Button{
            width = 130,
            height = 30,
            fontSize = 13,
            text = "Place on Map",
            valign = "center",
            lmargin = 8,
            swallowPress = true,

            press = function(element)
                resultPanel:FireEventTree("spawn")
            end,
        },
        gui.Button{
            width = 150,
            height = 30,
            fontSize = 13,
            text = "Save and Remove",
            valign = "center",
            lmargin = 8,
            swallowPress = true,

            press = function(element)
                resultPanel:FireEventTree("despawn")
            end,
            hover = function(element)
                gui.Tooltip("Saves the current positions of the monsters in the encounter, then removes them from the map.")(element)
            end,
        },
        gui.Button{
            width = 90,
            height = 30,
            fontSize = 13,
            text = "Reset",
            valign = "center",
            lmargin = 8,
            swallowPress = true,

            press = function(element)
                resultPanel:FireEventTree("reset")
            end,
            hover = function(element)
                gui.Tooltip("Resets the monsters to their original positions and status.")(element)
            end,
        },
    }

    local editLink = gui.Label{
        classes = {"encounterWidgetLink"},
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        fontSize = 12,
        text = "Edit in builder",
        press = function(element)
            self.encounter:CreateEditorDialog{
                mode = "Save",
                journal = true,
                save = function()
                    if resultPanel ~= nil and resultPanel.valid then
                        resultPanel:FireEventTree("refreshTag")
                    end
                end,
            }
        end,
    }

    bodyPanel = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        hpad = 12,
        vpad = 10,
        borderBox = true,

        bodyGroupsPanel,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 12,

            drawSteelButton,
            footerPanel,
            editLink,
        },
    }

    resultPanel = gui.Panel{
        classes = {"encounterWidget"},
        styles = ThemeEngine.MergeTokens({
            {
                selectors = {"encounterWidget"},
                bgcolor = "@bg",
                borderColor = "@border",
                borderWidth = 1,
                cornerRadius = 8,
            },
            {
                selectors = {"encounterWidget", "focus"},
                borderColor = "@accent",
            },
            {
                selectors = {"encounterWidgetHead"},
                bgcolor = "clear",
            },
            {
                selectors = {"encounterWidgetHead", "hover"},
                bgcolor = "@bgAlt",
            },
            {
                selectors = {"encounterWidgetHead", "open"},
                bgcolor = "@bgAlt",
            },
            {
                selectors = {"encounterWidgetDivider"},
                bgcolor = "@border",
            },
            {
                selectors = {"encounterWidgetCaption"},
                color = "@fgMuted",
            },
            {
                selectors = {"encounterWidgetEV"},
                color = "@accent",
            },
            {
                selectors = {"encounterWidgetLink"},
                color = "@accent",
            },
            {
                selectors = {"encounterWidgetLink", "hover"},
                color = "@accentHover",
            },
            {
                selectors = {"encounterWidgetPill"},
                borderWidth = 1,
                cornerRadius = 6,
                borderColor = "@border",
                color = "@fg",
            },
            {
                selectors = {"encounterWidgetPill", "tierTrivial"},
                color = "@fgMuted",
                borderColor = "@fgMuted",
            },
            {
                selectors = {"encounterWidgetPill", "tierEasy"},
                color = "@success",
                borderColor = "@success",
            },
            {
                selectors = {"encounterWidgetPill", "tierStandard"},
                color = "@info",
                borderColor = "@info",
            },
            {
                selectors = {"encounterWidgetPill", "tierHard"},
                color = "@warning",
                borderColor = "@warning",
            },
            {
                selectors = {"encounterWidgetPill", "tierExtreme"},
                color = "@danger",
                borderColor = "@danger",
            },
            {
                selectors = {"encounterWidgetChip"},
                bgcolor = "@bgAlt",
                borderColor = "@border",
                borderWidth = 1,
                --must stay under half the chip's ~26px height: larger radii
                --make the engine's rounded-rect pinch the pill ends into
                --points (the radius exceeds the geometry's semicircle cap).
                cornerRadius = 10,
            },
        }),
        flow = "vertical",
        width = "98%",
        maxWidth = 720,
        height = "auto",
        halign = "left",
        bgimage = true,

        spawn = function(element)
            print("FLOOR:: SPAWNING")
            --Remember this as the readied encounter so the combat-setup dialog can
            --default its dropdown to it. Cleared when combat actually starts.
            Encounter.SetReadiedEncounter(self.encounter)
            local initiativeQueue = dmhub.initiativeQueue
            if initiativeQueue ~= nil and initiativeQueue.hidden then
                initiativeQueue = nil
            end
            self.spawns = {}
            for _,group in ipairs(self.encounter:CloneForNumberOfHeroes().groups) do
                --Reinforcement groups (assigned to a wave) are not placed up front;
                --they arrive when their wave triggers, so skip them here.
                if group.wave ~= nil then
                    goto continue
                end

                local minionName = nil
                local nsquads = 1
                for monsterid,quantity in pairs(group.monsters) do
                    local monster = assets.monsters[monsterid]
                    if monster ~= nil and monster.properties:IsMonster() and monster.properties.minion then
                        minionName = monster.properties.monster_type
                        if quantity >= 8 then
                            nsquads = math.ceil(quantity / (group.squadSize or 4))
                        end
                        break
                    end
                end

                local squadNames = nil
                local nminions = 0

                if minionName ~= nil then
                    --find a name for the squad.
                    squadNames = {}
                    for i=1,nsquads do
                        squadNames[#squadNames+1] = monster.FindFreshSquadName(minionName)
                    end
                end

                local groupid = dmhub.GenerateGuid()
                local index = 1
                local nsquad = 1
                for monsterid,quantity in pairs(group.monsters) do

                    for i=1,quantity do
                        local loc = (group.spawnlocs or {})[index] or (group.spawnlocs or {})[1]
                        local appearanceInfo = (group.appearances or {})[index]
                        local invisibleToPlayers = group.invisibleToPlayers or {}
                        index = index+1

                        if loc ~= nil then
                            print("SPAWN:: ", loc.floor, loc.isValidFloor)
                            if not loc.isValidFloor then
                                loc = loc.withCurrentFloor
                                print("SPAWN:: adjusted to", loc.floor, loc.isValidFloor)
                            end
                            local token = game.SpawnTokenFromBestiaryLocally(monsterid, loc, {
                                fitLocation = true
                            })

                            token.properties.initiativeGrouping = groupid
                            token.properties:OnCreateFromBestiary(token, groupid)


                            print("SPAWN:: SPAWNED TOKEN:", token.name ~= nil, "invisible = ", invisibleToPlayers[i] or false, "has appearance =", appearanceInfo)
                            if invisibleToPlayers[i] then
                                token.invisibleToPlayers = true
                            end

                            if type(appearanceInfo) == "string" then
                                token:SerializeAppearanceFromString(appearanceInfo)
                            end

                            token.properties.minHeroes = (group.monsterMinHeroes or {})[monsterid] or group.minHeroes

                            local balancing = group.balancing
                            if balancing ~= nil then
                                local numHeroes = dmhub.GetSettingValue("numheroes")
                                local info = balancing[numHeroes]
                                if info ~= nil then
                                    if type(info.stamina) == "number" then
                                        token.properties.max_hitpoints = info.stamina
                                    end
                                end
                            end

                            if squadNames~= nil then

                                token.properties.minionSquad = squadNames[nsquad]
                                nsquad = nsquad + 1
                                if nsquad > #squadNames then
                                    nsquad = 1
                                end
                            end

                            token:UploadToken()
                            game.UpdateCharacterTokens()

                            self.spawns[#self.spawns+1] = token.charid
                        end
                    end

                    if initiativeQueue ~= nil then
                        initiativeQueue:SetInitiative(groupid, 0, 0)
                    end
                end

                ::continue::
            end

            self:UploadDocument()
            if initiativeQueue ~= nil then
			    dmhub:UploadInitiativeQueue()
            end
        end,

        despawn = function(element)
            local charids = self:try_get("spawns", {})
            self.spawns = nil
            local index = 1
            local numHeroes = dmhub.GetSettingValue("numheroes")
            print("SPAWN:: DESPAWNING MONSTERS:", #self.encounter.groups)
            for _,group in ipairs(self.encounter.groups) do
                group.appearances = {}
                group.invisibleToPlayers = {}
                --reinforcement (wave) groups are not placed up front, so they have no
                --tokens to despawn; skip them to keep the charid index aligned with spawn.
                if group.wave == nil and (group.minHeroes == nil or numHeroes >= group.minHeroes) then
                    local spawnIndex = 1
                    for monsterid,quantity in pairs(group.monsters) do
                        --match the adjusted count used at spawn time so token ids stay aligned.
                        quantity = Encounter.AdjustedMonsterQuantity(group, monsterid, quantity, numHeroes)
            print("SPAWN:: DESPAWNING monsterid =", monsterid, quantity)
                        for i=1,quantity do
                            local tokenid = charids[index]
                            local token = dmhub.GetTokenById(tokenid or "")
                            index = index + 1
                            if token ~= nil then
                                group.spawnlocs = group.spawnlocs or {}
                                group.spawnlocs[spawnIndex] = token.loc
                                group.invisibleToPlayers[spawnIndex] = token.invisibleToPlayers or false
                                print("SPAWN:: INVISIBLE", spawnIndex, " =", group.invisibleToPlayers[spawnIndex])
                                if self.encounter.saveAppearances and token.appearanceChangedFromBestiary then
                                    group.appearances[#group.appearances+1] = token:SerializeAppearanceToString()
                                else
                                    group.appearances[#group.appearances+1] = false
                                end

                                spawnIndex = spawnIndex + 1
                            end
                        end
                    end
                end
            end

            --Also save the positions of any deployed reinforcements (wave groups).
            --These were not placed by the start-of-encounter spawn above; they were
            --spawned at runtime by LiveEncounter:DeployWave, which TAGGED each token
            --with its wave id, group index, and flat spawn slot. We scan the map for
            --those tags and bank each token's current position into the matching
            --authored wave group's spawnlocs. Scanning the map (rather than reading the
            --live encounter) means this works whether or not combat is still active and
            --regardless of which live encounter is current. Banking into the authored
            --encounter means the next time the wave deploys it comes up where the DM
            --left them.
            local waveCharids = {}
            local myWaveIds = {}
            for _,wave in ipairs(self.encounter:try_get("waves", {})) do
                myWaveIds[wave.id] = true
            end

            local groupsReset = {}
            for _,token in ipairs(dmhub.allTokens) do
                local waveid = token.properties:try_get("encounterWaveId")
                local gidx = token.properties:try_get("encounterGroupIndex")
                local slot = token.properties:try_get("encounterSpawnSlot")
                if waveid ~= nil and gidx ~= nil and slot ~= nil and myWaveIds[waveid] then
                    local group = self.encounter.groups[gidx]
                    if group ~= nil and group.wave == waveid then
                        --clear the group's slots once, the first time we touch it, so
                        --stale entries from a previous save don't linger.
                        if not groupsReset[gidx] then
                            groupsReset[gidx] = true
                            group.spawnlocs = {}
                            group.appearances = {}
                            group.invisibleToPlayers = {}
                        end
                        group.spawnlocs[slot] = token.loc
                        group.invisibleToPlayers[slot] = token.invisibleToPlayers or false
                        if self.encounter.saveAppearances and token.appearanceChangedFromBestiary then
                            group.appearances[slot] = token:SerializeAppearanceToString()
                        else
                            group.appearances[slot] = false
                        end
                        waveCharids[#waveCharids+1] = token.charid
                    end
                end
            end

            game.DeleteCharacters(charids)
            if #waveCharids > 0 then
                game.DeleteCharacters(waveCharids)
            end

            if self:has_key("_tmp_document") then
                self._tmp_document:Upload()
            end
        end,

        reset = function(element)
            local charids = self:try_get("spawns", {})
            game.DeleteCharacters(charids)
            game.Refresh{}
            element:ScheduleEvent("spawn", 0.1)
        end,

        create = function(element)
            if element.data.monitorid == nil then
                element.data.monitorid = dmhub.RegisterEventHandler("spawnFromBestiary", function(charids)
                    if not element:HasClass("focus") then
                        return
                    end

                    gui.SetFocus(nil)

                    self.spawns = charids

                    --The engine places ALL of the encounter's monsters here, including
                    --reinforcement (wave) groups, as plain tokens. Tag the wave-group
                    --tokens so "Save and Remove" can bank their positions (mirrors the
                    --tags LiveEncounter:DeployWave applies for the in-combat path).
                    --The tokens are not always queryable the instant this fires, so
                    --(like the initiative-queue spawnFromBestiary handler) wait until
                    --they resolve before tagging.
                    local attempts = 20
                    local function tagWhenReady()
                        if mod.unloaded then return end
                        local allReady = true
                        for _,cid in ipairs(charids) do
                            if dmhub.GetTokenById(cid or "") == nil then
                                allReady = false
                                break
                            end
                        end
                        if not allReady and attempts > 0 then
                            attempts = attempts - 1
                            dmhub.Schedule(0.1, tagWhenReady)
                            return
                        end
                        self.encounter:TagWaveTokensFromSpawn(charids)
                        if self:has_key("_tmp_document") then
                            self._tmp_document:Upload()
                        end
                    end
                    tagWhenReady()

                end)

            end
        end,
        destroy = function(element)
            if element.data.monitorid ~= nil then
                dmhub.DeregisterEventHandler(element.data.monitorid)
            end
        end,
        press = function(element)
            gui.SetFocus(element)
        end,
        refreshTag = function(element, tag)
            self = tag or self
            element.data.encounter = self.encounter
            m_balancedEncounter = self.encounter:CloneForNumberOfHeroes()
        end,

        multimonitor = {"numheroes"},
        monitor = function(element)
            element:FireEventTree("refreshTag")
        end,

        headerPanel,

        gui.Panel{
            classes = {"encounterWidgetDivider"},
            width = "100%",
            height = 1,
            bgimage = true,
        },

        bodyPanel,
    }

    return resultPanel
end

function RichEncounter.CreateEditor(self)
    local resultPanel

    local titleLabel = gui.Label{
        width = "100%-54",
        height = 18,
        lmargin = 2,
        halign = "left",
        bold = true,
        fontSize = 14,
        minFontSize = 8,
        refreshEditor = function(element)
            element.text = self.encounter.name
        end,
    }

    local headerPanel = gui.Panel{
        classes = {"encounterEditorHeader"},
        width = "100%",
        flow = "horizontal",
        height = 18,
        bgimage = true,
        borderWidth = 1,

        titleLabel,

        gui.Label{
            width = 40,
            height = "auto",
            fontSize = 12,
            minFontSize = 8,
            halign = "right",
            valign = "center",
            refreshEditor = function(element)
                local ev = self.encounter:CountEDS()
                element.text = string.format("EV: %d", ev)
            end,
        },

        gui.Button{
            classes = {"settingsButton"},
            width = 12,
            height = 12,
            valign = "center",
            halign = "right",
            click = function(element)
                self.encounter:CreateEditorDialog{
                    mode = "Save",
                    journal = true,
                    save = function()
                        resultPanel:FireEventTree("refreshEditor")
                    end
                }
            end,
        },
    }

    local textPanel = gui.Label{
        classes = {"encounterEditorText"},
        width = "100%",
        height = "100% available",
        fontSize = 12,
        minFontSize = 8,
        pad = 4,
        textAlignment = "topleft",
        bgimage = true,
        bgcolor = "clear",
        borderWidth = 1,
        refreshEditor = function(element)
            element.text = self.encounter:Describe()
        end,
    }

    resultPanel = gui.Panel{
        styles = ThemeEngine.MergeTokens({
            {
                selectors = {"encounterEditorHeader"},
                bgcolor = "@bg",
                borderColor = "@fgStrong",
            },
            {
                selectors = {"encounterEditorText"},
                borderColor = "@border",
            },
        }),
        flow = "vertical",
        width = 160,
        height = "100%",
        refreshEditor = function(element, tag)
            self = tag or self
        end,
        headerPanel,
        textPanel,
    }

    return resultPanel
end


MarkdownDocument.RegisterRichTag(RichEncounter)