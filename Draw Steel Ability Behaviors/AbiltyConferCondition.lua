local mod = dmhub.GetModLoading()

--------------------------------------------------------------------------------
-- Confer Conditions behavior.
--
-- Opens a modal (styled like the purge-effects modal) listing the LIVE
-- conditions currently on a SOURCE creature.  The player selects which
-- condition(s) to confer, and each selected condition is COPIED (NOT purged)
-- onto every recipient creature, preserving the condition's caster attribution,
-- riders, duration and stacks.
--------------------------------------------------------------------------------

--- @class ActivatedAbilityConferConditionsBehavior:ActivatedAbilityBehavior
--- @field conditions string[] Optional restrict list of condition ids; empty means offer all of the source's conditions.
ActivatedAbilityConferConditionsBehavior = RegisterGameType("ActivatedAbilityConferConditionsBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
    id = 'confer_conditions',
    text = 'Confer Conditions',
    createBehavior = function()
        return ActivatedAbilityConferConditionsBehavior.new{
            conditions = {},
        }
    end,
}

-- applyto is inherited from ActivatedAbilityBehavior (default 'targets') and is
-- the RECIPIENT set; it is intentionally NOT redeclared here.
ActivatedAbilityConferConditionsBehavior.summary = "Confer Conditions"
ActivatedAbilityConferConditionsBehavior.conditionSource = ""
ActivatedAbilityConferConditionsBehavior.conferType = "one"
ActivatedAbilityConferConditionsBehavior.chatMessage = ""
ActivatedAbilityConferConditionsBehavior.reminderText = ""

ActivatedAbilityConferConditionsBehavior.conferTypeOptions = {
    {
        id = "all",
        text = "All Conditions",
    },
    {
        id = "chosen",
        text = "Chosen Conditions",
    },
    {
        id = "one",
        text = "One Chosen Condition",
    },
}

-- Builds the candidate item list from the source creature's live conditions.
-- Each item carries enough metadata for both the modal chip and the apply step.
-- Returns a flat list (possibly empty).
function ActivatedAbilityConferConditionsBehavior:CollectConferItems(sourceToken)
    local items = {}
    if sourceToken == nil or sourceToken.properties == nil then
        return items
    end

    local sourceCreature = sourceToken.properties
    if not sourceCreature:has_key("inflictedConditions") then
        return items
    end

    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName) or {}

    for conditionId, entry in pairs(sourceCreature.inflictedConditions) do
        if #self.conditions == 0 or table.contains(self.conditions, conditionId) then
            local condDef = conditionsTable[conditionId]
            items[#items+1] = {
                conditionId = conditionId,
                displayName = condDef and condDef.name or conditionId,
                iconid = condDef and condDef.iconid or nil,
                display = condDef and condDef.display or nil,
                duration = entry.duration,
                stacks = entry.stacks,
                casterTokenId = entry.casterInfo and entry.casterInfo.tokenid or nil,
                riders = entry.riders,
                sourceDescription = entry.sourceDescription,
            }
        end
    end

    return items
end

function ActivatedAbilityConferConditionsBehavior:Cast(ability, casterToken, targets, options)
    -- Resolve the SOURCE creature whose live conditions populate the modal.
    -- Mirrors the conferTo resolution block in the purge behavior.
    local sourceToken = casterToken
    if self:try_get("conditionSource", "") ~= "" then
        if options.symbols == nil then
            options.symbols = {}
        end
        local obj = dmhub.EvalGoblinScriptToObject(self.conditionSource, casterToken.properties:LookupSymbol(options.symbols), "Determine condition source")
        if obj ~= nil and type(obj) == "table" and (obj.typeName == "creature" or obj.typeName == "character" or obj.typeName == "monster" or obj.typeName == "follower") then
            local resolved = dmhub.GetCharacterById(dmhub.LookupTokenId(obj))
            if resolved ~= nil then
                sourceToken = resolved
            end
        end
    end

    -- Collect candidate conditions from the source.
    local items = self:CollectConferItems(sourceToken)

    if #items == 0 then
        -- Nothing to confer: bail gracefully but still pay the ability cost.
        if self:try_get("chatMessage", "") ~= "" then
            chat.Send(self.chatMessage .. " (no conditions to confer)")
        end
        ability:CommitToPaying(casterToken, options)
        return
    end

    -- Selection.
    local selectedItems
    if self.conferType == "all" then
        selectedItems = items
    else
        local multiSelect = self.conferType ~= "one"
        local confirmed, selection = self:ShowConferDialog(sourceToken, items, ability, casterToken, multiSelect)
        if not confirmed then
            -- Cancelled: do not apply and do not pay.
            return
        end
        selectedItems = selection or {}
    end

    -- Pay for the ability now that the selection is confirmed.
    ability:CommitToPaying(casterToken, options)

    if #selectedItems == 0 then
        return
    end

    -- Apply: copy each selected condition onto every recipient.
    for _, target in ipairs(targets) do
        local token = target.token
        if token ~= nil then
            token:ModifyProperties{
                description = "Confer Condition",
                execute = function()
                    for _, item in ipairs(selectedItems) do
                        token.properties:InflictCondition(item.conditionId, {
                            duration = item.duration,
                            casterInfo = item.casterTokenId and {tokenid = item.casterTokenId} or nil,
                            riders = item.riders,
                            sourceDescription = item.sourceDescription,
                            stacks = item.stacks,
                        })
                    end
                end,
            }
        end
    end

    -- Optional chat note.
    if self:try_get("chatMessage", "") ~= "" then
        chat.Send(self.chatMessage)
    end
end

-- Shows the confer-conditions selection modal.  Modeled on ShowPurgeDialog, but
-- with a SINGLE source row (the source creature's condition chips).  Returns
-- confirmed (bool), selectedItems (list of item references).
function ActivatedAbilityConferConditionsBehavior:ShowConferDialog(sourceToken, items, ability, casterToken, multiSelect)
    local finished = false
    local canceled = false

    -- Selected item references.
    local selections = {}

    -- Build the chips for the single source row.
    local chipPanels = {}
    for _, item in ipairs(items) do
        local capturedItem = item

        local chipChildren = {}
        if item.iconid ~= nil then
            chipChildren[#chipChildren+1] = gui.Panel{
                classes = {"purge-chip-icon"},
                bgimage = item.iconid,
                selfStyle = item.display,
            }
        end
        chipChildren[#chipChildren+1] = gui.Label{
            classes = {"purge-chip-label"},
            text = item.displayName,
        }

        chipPanels[#chipPanels+1] = gui.Panel{
            classes = {"purge-chip"},
            flow = "horizontal",

            press = function(element)
                if multiSelect then
                    local isSelected = element:HasClass("purge-chip-selected")
                    if isSelected then
                        element:SetClass("purge-chip-selected", false)
                        for i, sel in ipairs(selections) do
                            if sel == capturedItem then
                                table.remove(selections, i)
                                break
                            end
                        end
                    else
                        element:SetClass("purge-chip-selected", true)
                        selections[#selections+1] = capturedItem
                    end
                else
                    -- Single-select: clear all sibling chips first.
                    for _, sibling in ipairs(element.parent.children) do
                        sibling:SetClass("purge-chip-selected", false)
                    end
                    element:SetClass("purge-chip-selected", true)
                    selections = {capturedItem}
                end
            end,

            children = chipChildren,
        }
    end

    local sourceRow = gui.Panel{
        classes = {"purge-token-row"},
        gui.Panel{
            classes = {"purge-token-header"},
            gui.CreateTokenImage(sourceToken, {
                classes = {"purge-token-image"},
                width = 40,
                height = 40,
                valign = "center",
            }),
            gui.Label{
                classes = {"purge-token-name"},
                text = sourceToken.name,
            },
        },
        gui.Panel{
            classes = {"purge-chips-wrap"},
            children = chipPanels,
        },
    }

    local mainChildren = {}

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"purge-title"},
        text = "CONFER CONDITIONS",
    }

    local reminderText = self:try_get("reminderText", "")
    if reminderText ~= "" then
        mainChildren[#mainChildren+1] = gui.Label{
            classes = {"purge-reminder"},
            text = reminderText,
        }
    end

    local instructionText
    if multiSelect then
        instructionText = "Select conditions to confer"
    else
        instructionText = "Select a condition to confer"
    end
    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"purge-count"},
        text = instructionText,
    }

    mainChildren[#mainChildren+1] = gui.Panel{ classes = {"purge-divider"} }

    mainChildren[#mainChildren+1] = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        maxHeight = 420,
        vscroll = true,
        children = { sourceRow },
    }

    mainChildren[#mainChildren+1] = gui.Panel{ classes = {"purge-divider"} }

    mainChildren[#mainChildren+1] = gui.Panel{
        classes = {"purge-button-row"},
        gui.Panel{
            classes = {"purge-submit"},
            press = function(element)
                finished = true
                gui.CloseModal()
            end,
            gui.Label{
                classes = {"purge-button-label"},
                text = "Submit",
            },
        },
        gui.Panel{
            classes = {"purge-cancel"},
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            press = function(element)
                finished = true
                canceled = true
                gui.CloseModal()
            end,
            gui.Label{
                classes = {"purge-button-label"},
                text = "Cancel",
            },
        },
    }

    local resultPanel = gui.Panel{
        flow = "vertical",
        bgimage = "panels/square.png",
        bgcolor = "#040807",
        border = 1,
        borderColor = "#5C3D10",
        cornerRadius = 6,
        width = 480,
        height = "auto",
        pad = 12,

        styles = {
            {
                selectors = {"label", "purge-title"},
                fontFace = "Berling",
                fontSize = 18,
                color = "#5C6860",
                width = "auto",
                height = "auto",
                halign = "left",
                bmargin = 2,
            },
            {
                selectors = {"label", "purge-count"},
                fontFace = "Berling",
                fontSize = 12,
                color = "#C49A5A",
                width = "100%",
                height = "auto",
                halign = "left",
                bmargin = 2,
            },
            {
                selectors = {"label", "purge-reminder"},
                fontFace = "Berling",
                fontSize = 12,
                color = "#5C6860",
                width = "100%",
                height = "auto",
                halign = "left",
                textWrap = true,
                bmargin = 4,
            },
            {
                selectors = {"panel", "purge-divider"},
                width = "100%",
                height = 1,
                bgimage = "panels/square.png",
                bgcolor = "#5C3D10",
                vmargin = 8,
            },
            {
                selectors = {"panel", "purge-token-row"},
                width = "100%",
                height = "auto",
                flow = "vertical",
                vmargin = 4,
            },
            {
                selectors = {"panel", "purge-token-header"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                bmargin = 6,
                halign = "left",
            },
            {
                selectors = {"panel", "purge-token-image"},
                halign = "left",
                valign = "center",
                rmargin = 8,
            },
            {
                selectors = {"label", "purge-token-name"},
                fontFace = "Berling",
                fontSize = 14,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
            },
            {
                selectors = {"panel", "purge-chips-wrap"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                lmargin = 48,
                bmargin = 2,
            },
            {
                selectors = {"panel", "purge-chip"},
                height = "auto",
                minHeight = 22,
                width = "auto",
                halign = "left",
                valign = "top",
                hpad = 8,
                vpad = 4,
                margin = 3,
                flow = "horizontal",
                bgimage = "panels/square.png",
                border = 1,
                borderColor = "#5C6860",
                bgcolor = "clear",
                cornerRadius = 4,
            },
            {
                selectors = {"panel", "purge-chip", "hover"},
                brightness = 1.3,
                transitionTime = 0.15,
            },
            {
                selectors = {"panel", "purge-chip", "purge-chip-selected"},
                borderColor = "#966D4B",
                bgcolor = "#5C3D10",
            },
            {
                selectors = {"panel", "purge-chip-icon"},
                width = 16,
                height = 16,
                valign = "center",
                halign = "left",
                rmargin = 4,
            },
            {
                selectors = {"label", "purge-chip-label"},
                fontFace = "Berling",
                fontSize = 13,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                valign = "center",
            },
            {
                selectors = {"panel", "purge-button-row"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                tmargin = 4,
            },
            {
                selectors = {"panel", "purge-submit"},
                width = 130,
                height = 30,
                halign = "right",
                rmargin = 8,
                bgimage = "panels/square.png",
                bgcolor = "#040807",
                border = 1,
                borderColor = "#966D4B",
                cornerRadius = 4,
            },
            {
                selectors = {"panel", "purge-submit", "hover"},
                brightness = 1.25,
                transitionTime = 0.1,
            },
            {
                selectors = {"panel", "purge-cancel"},
                width = 130,
                height = 30,
                halign = "right",
                bgimage = "panels/square.png",
                bgcolor = "#040807",
                border = 1,
                borderColor = "#5C6860",
                cornerRadius = 4,
            },
            {
                selectors = {"panel", "purge-cancel", "hover"},
                brightness = 1.25,
                transitionTime = 0.1,
            },
            {
                selectors = {"label", "purge-button-label"},
                fontFace = "Berling",
                fontSize = 13,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
            },
        },

        children = mainChildren,
    }

    gui.ShowModal(resultPanel)

    while not finished do
        coroutine.yield(0.1)
    end

    if canceled then
        return false, nil
    end
    return true, selections
end

function ActivatedAbilityConferConditionsBehavior:EditorItems(parentPanel)
    local result = {}
    self:ApplyToEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Confer Type:",
        },
        gui.Dropdown{
            idChosen = self.conferType,
            options = ActivatedAbilityConferConditionsBehavior.conferTypeOptions,
            change = function(element)
                self.conferType = element.idChosen
                parentPanel:FireEvent("refreshBehavior")
            end,
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Condition Source:",
        },
        gui.GoblinScriptInput{
            value = self:try_get("conditionSource", ""),
            events = {
                change = function(element)
                    self.conditionSource = element.value
                end,
            },

            documentation = {
                help = string.format("Creature whose current conditions can be conferred. Defaults to the caster if blank."),
                output = "creature",
                subject = creature.helpSymbols,
                subjectDescription = "The creature that is casting the spell.",
                examples = {
                    {
                        script = "Caster",
                        text = "The caster's current conditions can be conferred.",
                    },
                    {
                        script = "Target",
                        text = "The target's current conditions can be conferred.",
                    },
                },
                symbols = ActivatedAbility.CatHelpSymbols(ActivatedAbility.helpCasting, {
                    caster = {
                        name = "Caster",
                        type = "creature",
                        desc = "The creature that is casting the ability.",
                    },
                    target = {
                        name = "Target",
                        type = "creature",
                        desc = "The target creature of the ability.",
                    },
                    subject = {
                        name = "Subject",
                        type = "creature",
                        desc = "The subject of the triggered ability. Only valid within a triggered ability.",
                    },
                })
            },
        }
    }

    local conditionOptions = {}
    local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
    for k,v in unhidden_pairs(conditionsTable) do
        conditionOptions[#conditionOptions+1] = {
            id = k,
            text = v.name,
        }
    end

    table.sort(conditionOptions, function(a,b) return a.text < b.text end)
    table.insert(conditionOptions, 1, {
        id = "none",
        text = "All Conditions",
    })

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Conditions:",
        },

        gui.Panel{
            flow = "vertical",
            width = 300,
            height = "auto",
            halign = "left",

            gui.Panel{
                flow = "vertical",
                width = "100%",
                height = "auto",
                create = function(element)
                    element:FireEvent("refreshConfer")
                end,
                refreshConfer = function(element)

                    local children = {}
                    for i,cond in ipairs(self.conditions) do
                        children[#children+1] = gui.Label{
                            width = 240,
                            height = "auto",
                            fontSize = 14,
                            color = "white",
                            text = conditionsTable[cond].name,
                            vmargin = 4,

                            gui.Button{
                                classes = {"deleteButton", "sizeS"},
                                floating = true,
                                halign = 'right',
                                valign = 'center',
                                click = function(element)
                                    table.remove(self.conditions, i)
                                    parentPanel:FireEventTree("refreshConfer")
                                end,
                            },
                        }
                    end

                    element.children = children
                end,
            },

            gui.Dropdown{
                options = conditionOptions,
                idChosen = "none",
                halign = "left",
                create = function(element)
                    element:FireEvent("refreshConfer")
                end,
                refreshConfer = function(element)
                    if #self.conditions == 0 then
                        conditionOptions[1].text = "All Conditions"
                    else
                        conditionOptions[1].text = "Add Condition..."
                    end
                    element.options = conditionOptions
                    element.idChosen = "none"
                end,
                change = function(element)
                    if element.idChosen ~= "none" then
                        self.conditions[#self.conditions+1] = element.idChosen
                    end
                    parentPanel:FireEventTree("refreshConfer")
                end,
            },
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Log Message:",
        },
        gui.Input{
            classes = {"formInput"},
            text = self.chatMessage,
            events = {
                change = function(element)
                    self.chatMessage = element.text
                end
            }
        },
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Reminder Text:",
        },
        gui.Input{
            classes = {"formInput"},
            placeholderText = "Enter text...",
            text = self:try_get("reminderText", ""),
            change = function(element)
                self.reminderText = element.text
            end,
        },
    }

    return result
end