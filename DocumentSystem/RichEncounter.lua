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

    local titleLabel = gui.Label{
        width = "100%-54",
        height = 20,
        lmargin = 2,
        hpad = 2,
        halign = "left",
        bold = true,
        fontSize = 14,
        refreshTag = function(element)
            element.text = self.encounter.name
        end,
    }

    local headerPanel = gui.Panel{
        classes = {"encounterHeader"},
        width = "100%",
        flow = "horizontal",
        height = 20,
        bgimage = true,
        border = {x1 = 0, y1 = 1, x2 = 0, y2 = 0},

        titleLabel,

        gui.Label{
            width = 50,
            height = 18,
            fontSize = 12,
            halign = "right",
            valign = "center",
            refreshTag = function(element)
                local ev = m_balancedEncounter:CountEDS()
                element.text = string.format("EV: %d", ev)
            end,
        },
    }

    local textPanel = gui.Label{
        width = "100%",
        height = "auto",
        fontSize = 12,
        minFontSize = 8,
        pad = 4,
        textAlignment = "topleft",
        borderWidth = 1,
        refreshTag = function(element)
            element.text = m_balancedEncounter:Describe()
        end,
    }

    local footerPanel = gui.Panel{
        width = "100%",
        height = 18,

        flow = "horizontal",

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
                    print("SPAWN:: CANNOT SPAWN")
                    canspawn = false
                    --break
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
            width = 180,
            height = 18,
            fontSize = 12,
            text = "Place on Map",
            halign = "center",
            swallowPress = true,

            press = function(element)
                resultPanel:FireEventTree("spawn")
            end,
        },
        gui.Button{
            width = 110,
            height = 18,
            fontSize = 12,
            text = "Save and Remove",
            halign = "center",
            swallowPress = true,

            press = function(element)
                resultPanel:FireEventTree("despawn")
            end,
            hover = function(element)
                gui.Tooltip("Saves the current positions of the monsters in the encounter, then removes them from the map.")(element)
            end,
        },
        gui.Button{
            width = 110,
            height = 18,
            fontSize = 12,
            text = "Reset",
            halign = "center",
            swallowPress = true,

            press = function(element)
                resultPanel:FireEventTree("reset")
            end,
            hover = function(element)
                gui.Tooltip("Resets the monsters to their original positions and status.")(element)
            end,
        },

    }

    resultPanel = gui.Panel{
        styles = ThemeEngine.MergeTokens({
            {
                selectors = {"encounterHeader"},
                bgcolor = "@bg",
                borderColor = "@fgStrong",
            },
            {
                borderWidth = 1,
                borderColor = "@border",
            },
            {
                selectors = {"hover"},
                borderColor = "@fgStrong",
                borderWidth = 2,
            },
            {
                selectors = {"focus"},
                borderColor = "@accent",
            },
        }),
        flow = "vertical",
        width = 260,
        height = "auto",
        pad = 2,
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

                            token.properties.minHeroes = group.minHeroes

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
            print("HAVE TAG::", json(tag))
        end,

        multimonitor = {"numheroes"},
        monitor = function(element)
            element:FireEventTree("refreshTag")
        end,

        headerPanel,
        textPanel,
        footerPanel,
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