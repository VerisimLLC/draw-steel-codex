local mod = dmhub.GetModLoading()

RegisterGameType("ActivatedAbilityReplenishBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'replenish_resources',
	text = 'Replenish Resources',
	createBehavior = function()
        local options = CharacterResource.GetDropdownOptions()
		return ActivatedAbilityReplenishBehavior.new{
            resourceid = options[1].id,
		}
	end
}

--- @class ResourceChatMessage
--- @field tokenid string
--- @field resourceid string
--- @field quantity number
--- @field mode string
--- @field reason string
--- @field undone boolean
ResourceChatMessage = RegisterGameType("ResourceChatMessage")

ResourceChatMessage.tokenid = ""
ResourceChatMessage.resourceid = ""
ResourceChatMessage.quantity = 0
ResourceChatMessage.mode = "replenish"
ResourceChatMessage.reason = ""
ResourceChatMessage.undone = false

--- Gets the token for this message.
--- @return nil|CharacterToken
function ResourceChatMessage:GetToken()
    return dmhub.GetCharacterById(self.tokenid)
end

--- Gets the resource for this message.
--- @return nil|CharacterResource
function ResourceChatMessage:GetResource()
    local resourceTable = dmhub.GetTable("characterResources") or {}
    return resourceTable[self.resourceid]
end

function ResourceChatMessage.Render(selfInput, message)
    return gui.Panel{
        width = 0, height = 0,
    }
end

function ResourceChatMessage:Undo(message)
    local token = self:GetToken()
    if token == nil then
        return
    end

    token:ModifyProperties{
        description = "Undo Resource",
        combine = true,
        execute = function()
            local replenish = self.mode == "replenish"
            if not self.undone then
                replenish = not replenish
            end

            local message = cond(self.undone, "Redo", "Undo")

            if replenish then
                token.properties:RefreshResource(self.resourceid, self:GetResource().usageLimit, self.quantity, message)
            else
                token.properties:ConsumeResource(self.resourceid, self:GetResource().usageLimit, self.quantity, message)
            end

            local record = token.properties:get_or_add("heroicResourceRecord", {})
            for key,value in pairs(self:try_get("checklistBefore", {})) do
                record[key] = value[cond(self.undone, 2, 1)]
            end
        end,
    }

    self.undone = not self.undone
    message:UploadProperties(self)
end

ActivatedAbilityReplenishBehavior.summary = 'Replenish Resources'
ActivatedAbilityReplenishBehavior.mode = 'replenish'
ActivatedAbilityReplenishBehavior.quantity = '1'
ActivatedAbilityReplenishBehavior.allowSubstitution = false
ActivatedAbilityReplenishBehavior.chooseResourceFromList = false

function ActivatedAbilityReplenishBehavior:Cast(ability, casterToken, targets, options)
    if #targets == 0 then
        return
    end

	local resourceTable = dmhub.GetTable("characterResources") or {}

    local resourceName = "Resource"

    if self.chooseResourceFromList then
        local resourceNames = {}
        for _,resourceid in ipairs(self:try_get("resourceOptions", {})) do
            local resourceInfo = resourceTable[self.resourceid]
            if resourceInfo ~= nil then
                resourceNames[#resourceNames+1] = resourceInfo.name
            end
        end

        resourceName = table.concat(resourceNames, ", ")
    else
        local resourceInfo = resourceTable[self.resourceid]
        if resourceInfo ~= nil then
            resourceName = resourceInfo.name
        end
    end

    local quantity = nil
    local rollComplete = false

    local roll = dmhub.EvalGoblinScript(self.quantity, casterToken.properties:LookupSymbol(options.symbols), string.format("Resource roll for %s", ability.name))
    print("QUANTITY::", self.quantity, "symbols =", table.keys(options.symbols), "RESULT =", roll)

    local rollResults = {}

    if safe_toint(roll) ~= nil then
        rollComplete = true

        for _,target in ipairs(targets) do
            rollResults[target.token.charid] = { result = safe_toint(roll) }
        end
        quantity = safe_toint(roll)
    else
        local dcaction = ability:RequireSavingThrowsCo(self, casterToken, ActivatedAbility.GetTokenIds(targets), {
            rollType = "custom",
            id = "",
            text = ability.name,
            explanation = "Roll for " .. resourceName,
            roll = roll,
            targets = targets,
        })

        if dcaction == nil then
            return
        end

        rollResults = dcaction.info.tokens
    end

    for _,target in ipairs(targets) do
        if target.token ~= nil and rollResults[target.token.charid] ~= nil then
            local quantity = rollResults[target.token.charid].result

            --check if the checklistid has already been set for this item, in which case it doesn't trigger.
            if self:try_get("checklistid", "none") ~= "none" then
                local items = target.token.properties:GetHeroicResourceChecklist()
                for i,item in ipairs(items or {}) do
                    if item.guid == self.checklistid then
                        if item.mode == "recurring" then
                            break
                        end

                        local updateid = target.token.properties:GetResourceRefreshId(item.mode or "encounter")
                        local record = target.token.properties:get_or_add("heroicResourceRecord", {})

                        if updateid == record[self.checklistid] then
                            --cancel this resource since the checklistid has already been triggered.
                            quantity = 0
                        end
                        break
                    end
                end
            end

            local resourceidToQuantity = {}

            if quantity <= 0 then
                --pass

            elseif self.chooseResourceFromList then

                local finished = false
                local canceled = false

                local m_pinnedResource = nil

                local RecalculateResources = function()
                    if #self:try_get("resourceOptions", {}) == 0 or (m_pinnedResource ~= nil and self.resourceOptions == 1) then
                        return
                    end

                    local assigned = 0
                    for i,resourceid in ipairs(self.resourceOptions) do
                        resourceidToQuantity[resourceid] = resourceidToQuantity[resourceid] or 0
                        assigned = assigned + resourceidToQuantity[resourceid]
                    end


                    while assigned > quantity do
                        local startingAssigned = assigned
                        for i,resourceid in ipairs(self.resourceOptions) do
                            if assigned > quantity and m_pinnedResource ~= i and resourceidToQuantity[resourceid] > 0 then
                                resourceidToQuantity[resourceid] = resourceidToQuantity[resourceid] - 1
                                assigned = assigned - 1
                            end
                        end
                        if startingAssigned == assigned then
                            break
                        end
                    end

                    while assigned < quantity do
                        local startingAssigned = assigned
                        for i,resourceid in ipairs(self.resourceOptions) do
                            if assigned < quantity and m_pinnedResource ~= i then
                                resourceidToQuantity[resourceid] = resourceidToQuantity[resourceid] + 1
                                assigned = assigned + 1
                            end
                        end
                        if startingAssigned == assigned then
                            break
                        end
                    end
                end


                local dialogPanel

                local items = {}

                for i,resourceid in ipairs(self:try_get("resourceOptions", {})) do
                    local resourceInfo = resourceTable[resourceid]

                    local iconid = resourceInfo.iconid
                    if resourceInfo.hasLargeDisplay then
                        iconid = resourceInfo.largeIconid
                    end

                    items[#items+1] = gui.Label{
                        fontSize = 24,
                        width = "auto",
                        height = "auto",
                        text = resourceInfo.name,
                        bmargin = -16,
                    }

                    items[#items+1] = gui.Panel{
                        flow = "horizontal",
                        halign = "center",
                        valign = "center",
                        width = "auto",
                        height = 160,

                        gui.PagingArrow{
                            facing = -1,
                            height = "30%",
                            refreshResources = function(element)
                                element:SetClass("hidden", resourceidToQuantity[resourceid] <= 0)
                            end,
                            click = function(element)
                                resourceidToQuantity[resourceid] = resourceidToQuantity[resourceid] - 1
                                m_pinnedResource = i
                                dialogPanel:FireEventTree("refreshResources")
                            end,
                        },

                        gui.Panel{
                            bgimage = iconid,
                            bgimageMask = mod.images.resourceMask,
                            bgcolor = "white",
                            width = 160,
                            height = 160,
                            hmargin = 10,
                            cornerRadius = 80,

                            gui.Panel{
                                bgimage = "panels/square.png",
                                width = 130,
                                height = 130,
                                cornerRadius = 65,
                                borderWidth = 2,
                                borderColor = Styles.textColor,
                            },

                            gui.Label{
                                refreshResources = function(element)
                                    element.text = string.format("%d", resourceidToQuantity[resourceid])
                                end,
                                change = function(element)
                                    local n = safe_toint(element.text)
                                    if n ~= nil and n <= quantity then
                                        resourceidToQuantity[resourceid] = n
                                        m_pinnedResource = i
                                        dialogPanel:FireEventTree("refreshResources")
                                    else
                                        element.text = tostring(resourceidToQuantity[resourceid])
                                    end
                                end,
                                textAlignment = "center",
                                editable = true,
                                halign = "center",
                                valign = "center",
                                width = "auto",
                                height = "auto",
                                hpad = 16,
                                vpad = 16,
                                fontSize = 48,
                                bold = true,
                            }
                        },

                        gui.PagingArrow{
                            facing = 1,
                            height = "30%",
                            refreshResources = function(element)
                                element:SetClass("hidden", resourceidToQuantity[resourceid] >= quantity)
                            end,
                            click = function(element)
                                resourceidToQuantity[resourceid] = resourceidToQuantity[resourceid] + 1
                                m_pinnedResource = i
                                dialogPanel:FireEventTree("refreshResources")
                            end,
                        },
                    }
                end

                dialogPanel = gui.Panel{
                    height = "auto",
                    width = 600,
                    classes = {"framedPanel"},
                    styles = {
                        Styles.Panel,
                        Styles.Default,
                    },

                    refreshResources = function(element)
                        RecalculateResources()
                    end,

                    gui.CloseButton{
                        floating = true,
                        halign = "right",
                        valign = "top",
                        click = function(element)
                            finished = true
                            canceled = true
                        end,
                    },

                    gui.Panel{
                        flow = "vertical",
                        width = "80%",
                        height = "auto",
                        maxHeight = 800,
                        vscroll = true,

                        gui.Label{
                            classes = {"dialogTitle"},
                            text = "Choose Resources",
                        },

                        gui.Divider{
                        },

                        gui.Panel{
                            flow = "vertical",
                            width = "auto",
                            height = "auto",
                            children = items,
                        },

                        gui.Panel{
                            flow = "horizontal",
                            width = "auto",
                            height = "auto",

                            gui.Label{
                                fontSize = 32,
                                width = "auto",
                                height = "auto",
                                halign = "left",
                                text = "Total:",
                            },

                            gui.Label{
                                fontSize = 32,
                                width = 80,
                                height = "auto",
                                textAlignment = "right",
                                characterLimit = 2,
                                halign = "right",
                                text = string.format("%d", quantity),
                                editable = true,
                                change = function(element)
                                    local n = safe_toint(element.text)
                                    if n ~= nil  then
                                        quantity = n
                                        m_pinnedResource = nil
                                        dialogPanel:FireEventTree("refreshResources")
                                    else
                                        element.text = tostring(quantity)
                                    end
                                end,
                            },

                        },

                        gui.Divider{
                        },

                        gui.PrettyButton{
                            text = "Confirm",
                            click = function()
                                finished = true
                            end,
                        },
                    },
                }

                dialogPanel:FireEventTree("refreshResources")

                gui.ShowModal(dialogPanel)

                while not finished do
                    print("WAITING...")
                    coroutine.yield(0.1)
                end

                gui.CloseModal()

                if canceled then
                    resourceidToQuantity = {}
                end

            else
                resourceidToQuantity[self.resourceid] = quantity
            end

            local hasSomeResources = false
            for id ,quantity in pairs(resourceidToQuantity) do
                --If resource is heroic resource, allow attribute modification
                if id == CharacterResource.heroicResourceId then
                    resourceidToQuantity[id] = quantity + target.token.properties:CalculateNamedCustomAttribute("Heroic Resource Gain Modification")
                end
                if quantity > 0 then
                    hasSomeResources = true
                    break
                end
            end

            if hasSomeResources then
                options.resourcesToRefundOnAbort = options.resourcesToRefundOnAbort or {}
                options.payIfNotAborted = true
                local chatMessageOverride = nil
                local checklistBefore = {}
                target.token:ModifyProperties{
                    description = cond(self.mode == "replenish", "Replenish Resource", "Consume Resource"),
                    execute = function()

                        if self:try_get("checklistid", "none") ~= "none" then
                            local items = target.token.properties:GetHeroicResourceChecklist()
                            for i,item in ipairs(items or {}) do
                                if item.guid == self.checklistid then
                                    local updateid
                                    local record = target.token.properties:get_or_add("heroicResourceRecord", {})
                                    if item.mode == "recurring" then
                                        updateid = dmhub.GenerateGuid()
                                    else
                                        updateid = target.token.properties:GetResourceRefreshId(item.mode or "encounter")
                                    end

                                    checklistBefore[self.checklistid] = {record[self.checklistid], updateid}
                                    record[self.checklistid] = updateid

                                    chatMessageOverride = item.name
                                    break
                                end
                            end
                        end


                        for resourceid,quantity in pairs(resourceidToQuantity) do
                            local resourceInfo = resourceTable[resourceid]
                            if self.mode == "replenish" then

                                if not self:try_get("chatonly", false) then
                                    local amount = target.token.properties:RefreshResource(resourceid, resourceInfo.usageLimit, quantity, ability.name)
                                    if amount ~= nil and amount ~= 0 and target.token.charid == casterToken.charid then
                                        options.resourcesToRefundOnAbort[resourceid] = (options.resourcesToRefundOnAbort[resourceid] or 0) - amount
                                    end

                                    if amount ~= nil and resourceid == CharacterResource.heroicResourceId then
                                        options.symbols.cast.heroicresourcesgained = options.symbols.cast.heroicresourcesgained + amount
                                    end
                                end

                            else
                                if not self:try_get("chatonly", false) then
                                    local amount = target.token.properties:ConsumeResource(resourceid, resourceInfo.usageLimit, quantity, ability.name)
                                    if amount ~= nil and amount ~= 0 and target.token.charid == casterToken.charid then
                                        options.resourcesToRefundOnAbort[resourceid] = (options.resourcesToRefundOnAbort[resourceid] or 0) + amount
                                    end
                                end

                            end
                        end

                    end,
                }

                if chatMessageOverride ~= nil or self:has_key("chatMessage") then
                    chat.SendCustom(
                        ResourceChatMessage.new{
                            tokenid = target.token.charid,
                            resourceid = self.resourceid,
                            quantity = resourceidToQuantity[self.resourceid] or quantity,
                            mode = self.mode,
                            checklistBefore = checklistBefore,
                            reason = chatMessageOverride or self.chatMessage,
                        }
                    )
                end
            end

        end
    end



end


function ActivatedAbilityReplenishBehavior:EditorItems(parentPanel)
	local result = {}

	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

    local options = CharacterResource.GetDropdownOptions()

    result[#result+1] = gui.Check{
        text = "Choose Resource from List",
        value = self.chooseResourceFromList,
        change = function(element)
            self.chooseResourceFromList = element.value
            parentPanel:FireEvent("refreshBehavior")
        end,
    }

    if self.chooseResourceFromList then
        local resourceTable = dmhub.GetTable("characterResources") or {}
        for index,resourceid in ipairs(self:try_get("resourceOptions", {})) do
            local resourceInfo = resourceTable[resourceid]
            if resourceInfo ~= nil then
                result[#result+1] = gui.Panel{
                    classes = "formPanel",
                    gui.Label{
                        classes = "formLabel",
                        text = resourceInfo.name,
                    },

                    gui.DeleteItemButton{
                        width = 12,
                        height = 12,
                        click = function(element)
                            local options = self:try_get("resourceOptions", {})
                            table.remove(options, index)
                            parentPanel:FireEvent("refreshBehavior")
                        end,
                    },
                }
            end
        end

        result[#result+1] = gui.Panel{
            classes = "formPanel",
            gui.Label{
                classes = "formLabel",
                text = "Add Resource:",
            },

            gui.Dropdown{
                idChosen = self.resourceid,
                options = options,
                textOverride = "Choose...",
                change = function(element)
                    self.resourceid = element.idChosen
                    local options = self:get_or_add("resourceOptions", {})
                    options[#options+1] = element.idChosen
                    parentPanel:FireEvent("refreshBehavior")
                end,
            },
        }
    else
        result[#result+1] = gui.Panel{
            classes = "formPanel",
            gui.Label{
                classes = "formLabel",
                text = "Resource:",
            },

            gui.Dropdown{
                idChosen = self.resourceid,
                options = options,
                change = function(element)
                    self.resourceid = element.idChosen
                    parentPanel:FireEvent("refreshBehavior")
                end,

            },
        }
    end

    local checklistOptions = Class.GatherHeroicResourceCheckListItems()
    table.insert(checklistOptions, 1, {
        id = "none",
        text = "None",
    })

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        refreshBehavior = function(element)
            element:SetClass("collapsed", self.resourceid ~= CharacterResource.heroicResourceId)
        end,
        gui.Label{
            classes = {"formLabel"},
            text = "Resource Checklist:",
        },
        gui.Dropdown{
            options = checklistOptions,
            idChosen = self:try_get("checklistid", "none"),
            hasSearch = true,
            change = function(element)
                self.checklistid = element.idChosen
                parentPanel:FireEvent("refreshBehavior")
            end,
        }
    }

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Mode:",
        },

        gui.Dropdown{
            idChosen = self.mode,
            options = {
                {
                    id = "replenish",
                    text = "Replenish Resources"
                },
                {
                    id = "expend",
                    text = "Expend Resources"
                },
            },
            change = function(element)
                self.mode = element.idChosen
                parentPanel:FireEvent("refreshBehavior")
            end,

        },
    }

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Quantity:",
        },

        gui.GoblinScriptInput{
            value = self.quantity,
            change = function(element)
                self.quantity = element.value
                parentPanel:FireEvent("refreshBehavior")
            end,


			documentation = {
				help = string.format("This GoblinScript determines the number of resources to replenish."),
				output = "roll",
				examples = {
					{
						script = "1",
						text = "1 resource is replenished.",
					},
					{
						script = "-1",
						text = "1 resource is expended",
					},
					{
						script = "2d6",
						text = "2d6 resources are replenished.",
					},
				},
				subject = creature.helpSymbols,
				subjectDescription = "The creature that is casting the spell",
				symbols = ActivatedAbility.helpCasting,
			},
        },

    }

    result[#result+1] = gui.Panel{
        classes = "formPanel",
        gui.Label{
            classes = "formLabel",
            text = "Chat Message:",
        },

        gui.Input{
            classes = {"formInput"},
            text = self:try_get("chatMessage"),
            change = function(element)
                self.chatMessage = element.text
                parentPanel:FireEvent("refreshBehavior")
            end,
        },
    }

    result[#result+1] = gui.Check{
        value = self:try_get("chatonly", false),
        text = "Show Chat Only",
        hover = gui.Tooltip("Choose to make this behavior not give resources. It will only show the chat message. This is useful if the resources are given in some other way."),
        change = function(element)
            self.chatonly = element.value
            parentPanel:FireEvent("refreshBehavior")
        end,
    }

    return result
end