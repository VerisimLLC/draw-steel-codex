local mod = dmhub.GetModLoading()

---@class RichParty
RichParty = RegisterGameType("RichParty", "RichTag")
RichParty.tag = "party"
RichParty.hasEdit = "hidden"
RichParty.partyid = false

function RichParty.Create()
    return RichParty.new {
        partyid = GetDefaultPartyID(),
        tokensAdded = {},
        tokensRemoved = {},
    }
end

function RichParty.CreateDisplay(self)
    local resultPanel
    print("PARTY:: CREATE")

    local m_token = {}

    local nameLabel = gui.Label {
        text = "Party Members",
        textAlignment = "center",
        halign = "center",
        valign = "bottom",
        fontSize = 18,
        minFontSize = 12,
        bold = true,
        width = 300,
        height = 24,
        refreshTag = function(element, tag, match)
            if match ~= nil then
                element.text = match.name
            end
        end,

        gui.AddButton {
            halign = "right",
            valign = "center",
            width = 16,
            height = 16,
            refreshTag = function(element, richTag, patternMatch, token)
                token = token or m_token
                element:SetClass("collapsed", token.player)
            end,
            press = function(element)
                local entries = {}

                for _, partyid in ipairs(GetAllParties()) do
                    local party = GetParty(partyid)
                    local charsInParty = dmhub.GetCharacterIdsInParty(partyid) or {}
                    if #charsInParty > 0 and party ~= nil then
                        local submenu = {}
                        for _, charid in ipairs(charsInParty) do
                            if not self.tokensAdded[charid] then
                                local character = dmhub.GetCharacterById(charid)
                                if character ~= nil then
                                    submenu[#submenu + 1] = {
                                        text = character.name or "(Unnamed)",
                                        click = function()
                                            element.popup = nil
                                            self.tokensAdded[charid] = true
                                            self.tokensRemoved[charid] = nil
                                            self:UploadDocument()
                                        end,
                                    }
                                end
                            end
                        end

                        if #submenu > 0 then
                            table.sort(submenu, function(a, b) return a.text < b.text end)
                            if #submenu > 1 then
                                local entry = {
                                    text = "Entire Party",
                                    click = function()
                                        element.popup = nil
                                        for _, charid in ipairs(charsInParty) do
                                            self.tokensAdded[charid] = true
                                            self.tokensRemoved[charid] = nil
                                        end
                                        self:UploadDocument()
                                    end
                                }
                                submenu[#submenu + 1] = entry
                            end
                            entries[#entries + 1] = {
                                text = party.name,
                                submenu = submenu,
                            }
                        end
                    end
                end

                element.popup = gui.ContextMenu {
                    entries = entries,
                }
            end,
        },
    }

    local m_tokenPanels = {}


    local m_tokenContainer

    m_tokenContainer = gui.Panel {
        width = "auto",
        height = 180,
        flow = "horizontal",
        halign = "center",
        valign = "top",

        refreshTag = function(element, tag, match, token)
            m_token = token or m_token
            local ordering = self:try_get("ord", {})

            local firstTime = element.aliveTime < 0.5

            self = tag or self

            local characters = {}
            if self.partyid then
                local charsInParty = dmhub.GetCharacterIdsInParty(self.partyid) or {}
                for _, charid in ipairs(charsInParty) do
                    if not self.tokensRemoved[charid] then
                        --only add party members on the map.
                        characters[charid] = dmhub.GetTokenById(charid)
                    end
                end
            end

            for charid, _ in pairs(self.tokensAdded) do
                if characters[charid] == nil then
                    --if a token is explicitly added, it doesn't need to be on the map.
                    characters[charid] = dmhub.GetCharacterById(charid)
                end
            end

            local newTokenPanels = {}
            local children = {}

            local state = self:get_or_add("state", {})
            for charid, character in pairs(characters) do
                local tokenPanel = m_tokenPanels[charid] or gui.Panel {
                    data = {
                        charid = charid,
                    },
                    classes = { "tokenPanel" },

                    dragTarget = true,
                    dragTargetPriority = 10,
                    bgimage = true,
                    bgcolor = "clear",

                    flow = "vertical",
                    width = 100,
                    height = 140,
                    pad = 1,
                    click = function(element)
                        local state = self:get_or_add("state", {})
                        local currentState = state[charid]
                        if currentState == nil then
                            currentState = "highlight"
                        elseif currentState == "highlight" then
                            currentState = "disabled"
                        else
                            currentState = nil
                        end

                        state[charid] = currentState
                        self:UploadDocument()
                        resultPanel:FireEventTree("refreshTag")
                    end,
                    draggable = dmhub.isDM,
                    refreshTag = function(element, richTag, patternMatch, token)
                        token = token or m_token
                        element:SetClass("playerview", token.player)
                        element.draggable = not token.player
                    end,
                    beginDrag = function(element)
                    end,
                    canDragOnto = function(element, target)
                        if not dmhub.isDM then
                            return false
                        end
                        if target:HasClass("richParty") and element.parent ~= target then
                            return true
                        end

                        if element ~= target and element.parent == target.parent and target:HasClass("tokenPanel") and target.data.charid ~= charid then
                            return true
                        end

                        return false
                    end,
                    drag = function(element, target)
                        if target ~= nil and target ~= element.parent and target:HasClass("richParty") then
                            local source = self
                            local dest = target.data.GetInfo()

                            if source ~= dest then
                                source.tokensAdded[charid] = nil
                                source.tokensRemoved[charid] = true
                                dest.tokensAdded[charid] = true
                                dest.tokensRemoved[charid] = nil
                                source:UploadDocument()

                                if target.data.GetDocument() ~= source:try_get("_tmp_document") then
                                    dest:UploadDocument()
                                end
                            end
                        elseif target ~= nil and target:HasClass("tokenPanel") then
                            local ord = self:get_or_add("ord", {})
                            ord[charid] = target.siblingIndex
                            ord[target.data.charid] = element.siblingIndex
                            self:UploadDocument()
                            resultPanel:FireEventTree("refreshTag")
                        end
                    end,
                    gui.Panel {
                        classes = "tokenImage",
                        width = "78% height",
                        height = 120,
                        halign = "center",
                        valign = "top",
                        bgimage = true,
                        bgcolor = "white",
                        token = function(element, token)
                            local portrait = token.offTokenPortrait
                            element.bgimage = portrait
                            element.selfStyle.imageRect = token:GetPortraitRectForAspect(78 * 0.01, portrait)
                        end,

                        gui.CloseButton {
                            styles = {
                                {
                                    hidden = 1,
                                },
                                {
                                    selectors = { "parent:hover", "dm" },
                                    hidden = 0,
                                },
                            },
                            refreshTag = function(element, richTag, patternMatch, token)
                                token = token or m_token
                                element:SetClass("collapsed", token.player)
                            end,
                            escapeActivates = false,
                            halign = "right",
                            valign = "top",
                            width = 12,
                            height = 12,
                            hmargin = 2,
                            vmargin = 2,
                            press = function(element)
                                self.tokensAdded[charid] = nil
                                self.tokensRemoved[charid] = true
                                local state = self:get_or_add("state", {})
                                state[charid] = nil
                                self:UploadDocument()
                            end,
                        }
                    },
                    gui.Label {
                        fontSize = 12,
                        width = 100,
                        height = 20,
                        textAlignment = "center",
                        token = function(element, token)
                            element.text = token.name
                        end,
                    }
                }

                if (not firstTime) and m_tokenPanels[charid] == nil then
                    tokenPanel:PulseClassTree("new")
                end

                tokenPanel:FireEventTree("token", character)

                local panelState = state ~= nil and state[charid]
                tokenPanel:SetClassTree("highlight", panelState == "highlight")
                tokenPanel:SetClassTree("disabled", panelState == "disabled")

                newTokenPanels[charid] = tokenPanel
                children[#children + 1] = tokenPanel
            end

            table.sort(children, function(a, b) return a.data.charid < b.data.charid end)

            local ordClaimed = {}

            --first pass: put children in exact spots they can go.
            for _, child in ipairs(children) do
                local ord = ordering[child.data.charid]
                if ord ~= nil and ord <= #children and ordClaimed[ord] == nil then
                    ordClaimed[ord] = child
                    child.data.claimed = true
                else
                    child.data.claimed = false
                end
            end

            --second pass: put children who have a preferred ord in the closest spot.
            for _, child in ipairs(children) do
                local ord = ordering[child.data.charid]
                if ord ~= nil and (not child.data.claimed) then
                    local bestDist = nil
                    local bestSpot = nil
                    for i = 1, #children do
                        if ordClaimed[i] == nil then
                            local dist = math.abs(i - ord)
                            if bestDist == nil or dist < bestDist then
                                bestDist = dist
                                bestSpot = i
                            end
                        end
                    end

                    ordClaimed[bestSpot] = child
                    child.data.claimed = true
                end
            end

            --third pass: put remaining children in the first open spot.
            for _, child in ipairs(children) do
                if not child.data.claimed then
                    for i = 1, #children do
                        if ordClaimed[i] == nil then
                            ordClaimed[i] = child
                            child.data.claimed = true
                            break
                        end
                    end
                end
            end

            local currentChildren = element.children or {}
            if #currentChildren > #ordClaimed then
                local noadds = true
                --see if we are just deleting items, in which case we can animate it nicely.
                for _,child in ipairs(ordClaimed) do
                    local alreadyExists = false
                    for _,currentChild in ipairs(currentChildren) do
                        if currentChild == child then
                            alreadyExists = true
                            break
                        end
                    end

                    if not alreadyExists then
                        noadds = false
                        break
                    end
                end

                if noadds then
                    for _,currentChild in ipairs(currentChildren) do
                        local found = false
                        for _,child in ipairs(ordClaimed) do
                            if currentChild == child then
                                found = true
                                break
                            end
                        end

                        if not found then
                            currentChild:SetClass("remove", true)
                            currentChild:ScheduleEvent("die", 0.2)
                        end
                    end

                    ordClaimed = currentChildren
                end
            end

            element.children = ordClaimed
            m_tokenPanels = newTokenPanels
        end,

        die = function(element)
            element:DestroySelf()
        end,
    }

    resultPanel = gui.Panel {
        classes = "richParty",
        data = {
            GetDocument = function()
                return self:try_get("_tmp_document")
            end,
            GetInfo = function()
                return self
            end,

        },

        styles = {
            {
                selectors = { "richParty" },
                borderColor = "#FFFFFF66",
                borderWidth = 1,
            },
            {
                selectors = { "richParty", "drag-target" },
                borderColor = "white",
            },
            {
                selectors = { "richParty", "drag-target-hover" },
                borderColor = "yellow",
            },
            {
                selectors = { "tokenPanel", "hover", "~playerview" },
                borderWidth = 1,
                borderColor = "#ffffff88",
            },
            {
                selectors = {"tokenPanel", "highlight"},
                borderWidth = 2,
                borderColor = "white",
                y = -8,
                transitionTime = 0.2,
            },
            {
                selectors = {"tokenImage", "highlight"},
                transitionTime = 0.2,
                brightness = 1.2,
            },
            {
                selectors = {"tokenImage", "disabled"},
                transitionTime = 0.2,
                brightness = 0.7,
                saturation = 0.2,
            },
            {
                selectors = { "tokenPanel", "drag-target" },
                borderWidth = 1,
                borderColor = "white",
            },
            {
                selectors = { "tokenPanel", "drag-target-hover" },
                borderWidth = 1,
                borderColor = "yellow",
            },
            {
                selectors = { "tokenPanel", "new" },
                uiscale = { x = 0, y = 1 },
                transitionTime = 0.2,
                brightness = 3,
            },
            {
                selectors = { "tokenPanel", "remove" },
                uiscale = { x = 0, y = 1 },
                transitionTime = 0.2,
            },
        },

        dragTarget = true,

        minWidth = 300,
        width = "auto",
        height = 200,
        flow = "vertical",
        bgimage = true,
        bgcolor = "clear",

        press = function(element)
            if element.popup ~= nil then
                element.popup = nil
            end
        end,

        rightClick = function(element)
            local doc = self:GetDocument()
            if doc == nil or doc:IsPlayerView(element) then
                return
            end
            local entries = {
                {
                    text = "Clear",
                    click = function()
                        element.popup = nil
                        self.partyid = false
                        self.tokensAdded = {}
                        self.tokensRemoved = {}
                        self:UploadDocument()
                    end,
                }
            }

            element.popup = gui.ContextMenu {
                entries = entries,
            }
        end,

        m_tokenContainer,
        nameLabel,
    }


    return resultPanel
end

MarkdownDocument.RegisterRichTag(RichParty)
