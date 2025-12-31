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
        width = "100%",
        flow = "horizontal",
        height = 20,
        bgimage = true,
        bgcolor = "black",
        borderColor = "white",
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
        styles = {
            {
                borderWidth = 1,
                borderColor = "#ffffff88",
            },
            {
                selectors = {"hover"},
                borderColor = "white",
                borderWidth = 2,
            },
            {
                selectors = {"focus"},
                borderColor = "yellow",
            }
        },
        flow = "vertical",
        width = 260,
        height = "auto",
        pad = 2,
        halign = "left",
        bgimage = true,

        spawn = function(element)
            print("FLOOR:: SPAWNING")
            local initiativeQueue = dmhub.initiativeQueue
            if initiativeQueue ~= nil and initiativeQueue.hidden then
                initiativeQueue = nil
            end
            self.spawns = {}
            for _,group in ipairs(self.encounter:CloneForNumberOfHeroes().groups) do
                local minionName = nil
                for monsterid,quantity in pairs(group.monsters) do
                    local monster = assets.monsters[monsterid]
                    if monster ~= nil and monster.properties:IsMonster() and monster.properties.minion then
                        minionName = monster.properties.monster_type
                        break
                    end
                end

                local squadName = nil

                if minionName ~= nil then
                    --find a name for the squad.
                    squadName = monster.FindFreshSquadName(minionName)
                end

                local groupid = dmhub.GenerateGuid()
                local index = 1
                for monsterid,quantity in pairs(group.monsters) do
                    print("SPAWN:: SPAWNING", monsterid, quantity)

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

                            print("SPAWN:: SPAWNED TOKEN:", token.name ~= nil, "invisible = ", invisibleToPlayers[i] or false, "has appearance =", appearanceInfo)
                            if invisibleToPlayers[i] then
                                token.invisibleToPlayers = true
                            end

                            if type(appearanceInfo) == "string" then
                                token:SerializeAppearanceFromString(appearanceInfo)
                            end

                            token.properties.minHeroes = group.minHeroes
                            token.properties.initiativeGrouping = groupid

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

                            if squadName ~= nil then
                                token.properties.minionSquad = squadName
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
                if group.minHeroes == nil or numHeroes >= group.minHeroes then
                    local spawnIndex = 1
                    for monsterid,quantity in pairs(group.monsters) do
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

            game.DeleteCharacters(charids)

            if self:has_key("_tmp_document") then
                print("SPAWN:: DOCUMENT UPLOAD")
                self._tmp_document:Upload()
            end
        end,

        reset = function(element)
            local charids = self:try_get("spawns", {})
            game.DeleteCharacters(charids)
            element:FireEvent("spawn")
        end,

        create = function(element)
            if element.data.monitorid == nil then
                element.data.monitorid = dmhub.RegisterEventHandler("spawnFromBestiary", function(charids)
                    print("SPAWN::", element:HasClass("focus"), charids)
                    if not element:HasClass("focus") then
                        return
                    end

                    gui.SetFocus(nil)

                    self.spawns = charids
                    if self:has_key("_tmp_document") then
                        self._tmp_document:Upload()
                    end

                    print("SPAWN:: QUEUE:", dmhub.initiativeQueue ~= nil and not dmhub.initiativeQueue.hidden)
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
        width = "100%",
        flow = "horizontal",
        height = 18,
        bgimage = true,
        bgcolor = "black",
        borderColor = "white",
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

        gui.SettingsButton{
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
        width = "100%",
        height = "100% available",
        fontSize = 12,
        minFontSize = 8,
        pad = 4,
        textAlignment = "topleft",
        bgimage = true,
        bgcolor = "clear",
        borderColor = "#ffffff88",
        borderWidth = 1,
        refreshEditor = function(element)
            element.text = self.encounter:Describe()
        end,
    }

    resultPanel = gui.Panel{
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