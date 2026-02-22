local mod = dmhub.GetModLoading()

function creature:RemoveLoopingEmotes()
	local token = dmhub.LookupToken(self)
	if token == nil then
		return
	end


	token:BeginChanges()
	self.loopemotes = {}
	token:CompleteChanges('emote')
end

--calculates looping emotes currently playing on this creature. Returns a { (string id) -> {timestamp = number } }
function creature:CalculateLoopingEmotes()
	local loopemotes = self:try_get('loopemotes')
	local ongoingEffects = self:try_get('ongoingEffects')

	if loopemotes == nil then
		loopemotes = {}
	else
		loopemotes = DeepCopy(loopemotes)
	end

	local deletes = {}
	for k,emote in pairs(loopemotes) do
		if emote.ttl ~= nil and TimestampAgeInSeconds(emote.timestamp) > emote.ttl then
			deletes[#deletes+1] = k
		end
	end

	for _,k in ipairs(deletes) do
		loopemotes[k] = nil
	end

	if ongoingEffects ~= nil then
		for i,cond in ipairs(ongoingEffects) do
			if not cond:Expired() then
				local ongoingEffect = dmhub.GetTable("characterOngoingEffects")[cond.ongoingEffectid]
				if ongoingEffect ~= nil and ongoingEffect.emoji ~= nil and ongoingEffect.emoji ~= 'none' then
					loopemotes[ongoingEffect.emoji] = { timestamp = ServerTimestamp() }
				end
			end
		end
	end

	local gearTable = dmhub.GetTable('tbl_Gear')
	for slotid,equip in pairs(self:Equipment()) do
		local item = gearTable[equip]
		if item ~= nil and item:has_key("accessory") and self:IsUsingEquipmentSlot(slotid) then
			loopemotes[item.accessory] = { timestamp = ServerTimestamp() }
		end
	end

	local token = dmhub.LookupToken(self)
	if token ~= nil then
		local mount = token.mountObject
		if mount ~= nil and mount.emoteid ~= nil and mount.emoteid ~= "" then
			loopemotes[mount.emoteid] = { timestamp = ServerTimestamp() }
		end
	end

	return loopemotes
end

function creature:EmoteTransition(effect, transitionToEffect)
	
end

function creature:Emote(effect, options)

	options = options or {}

	local token = dmhub.LookupToken(self)
	if token == nil then
		return
	end

	local effectInfo = GetTokenEffects(effect)
	if not effectInfo or #effectInfo == 0 then
		dmhub.Debug('unknown effect: ' .. effect)
		return
	end

	token:BeginChanges()

	if effectInfo[1].looping then
		local loopemotes = self:get_or_add("loopemotes", {})

		--take the opportunity to wipe out any expired looping emotes.
		local deletes = {}
		for k,emote in pairs(loopemotes) do
			if (emote.ttl ~= nil and TimestampAgeInSeconds(emote.timestamp) > emote.ttl) or
			   (options.deleteOthers and k ~= effect) then
				deletes[#deletes+1] = k
			end
		end

		for _,k in ipairs(deletes) do
			loopemotes[k] = nil
		end

		local start = options.start
		if start == nil then
			if loopemotes[effect] then
				start = false
			else
				start = true
			end
		end

		if not start then
			loopemotes[effect] = nil
		else
			loopemotes[effect] = {
				timestamp = ServerTimestamp(),
				ttl = options.ttl,
			}
		end
	else

		local emotes = self:get_or_add("emotes", {})

		local removes = {}
		for k,emote in pairs(emotes) do
			if TimestampAgeInSeconds(emote.timestamp) > 180 then
				removes[#removes+1] = k
			end
		end

		for i,k in ipairs(removes) do
			emotes[k] = nil
		end

		local guid = dmhub.GenerateGuid()

		emotes[guid] = {
			timestamp = ServerTimestamp(),
			effect = effect,
		}
	end

	token:CompleteChanges('emote')

	if token.sheet ~= nil then
		token.sheet:FireEventTree('refresh')
	end
end

local NumFavorites = 6
function GetFavoriteEmoji()
	local favorites = dmhub.GetSettingValue("favoriteemoji")
	if favorites ~= nil then
		return favorites
	end

	local result = {}
	local dataTable = assets.emojiTable
	for k,emoji in pairs(dataTable) do
		if #result < NumFavorites and (not emoji.hidden) and emoji.emojiType == "Emoji" then
			result[#result+1] = k
		end
	end

	return result
end

function SetFavoriteEmoji(emoji)
	dmhub.SetSettingValue("favoriteemoji", emoji)
end


function GameHud:CreateEmojiEditorPanel(token)

	local search = ""
	local loopingEmotes = token.properties:try_get("loopemotes", {})

	local GetNumPages
	local pageNum = 1
	local SetPageNum = function(num)
		if num > GetNumPages() then
			num = GetNumPages()
		end
		if num < 1 then
			num = 1
		end

		pageNum = num
	end


	local visibleEmoji = {}
	local CalculateVisibleEmoji = function()
		local dataTable = assets.emojiTable
		visibleEmoji = {}
		for k,emoji in pairs(dataTable) do
			if emoji.emojiType == "Emoji" and (search == "" or string.find(string.lower(emoji.description), string.lower(search))) then
				visibleEmoji[#visibleEmoji+1] = k
			end
		end

		table.sort(visibleEmoji, function(a,b) return dataTable[a].description < dataTable[b].description end)

		SetPageNum(pageNum)
	end


	local resultPanel


	local emojiPanel = gui.Panel{
		width = "95%",
		height = "auto",
		halign = "center",
		
		flow = "horizontal",
		wrap = true,
		valign = "center",
	}

	local PageSize = 24
	GetNumPages = function()
		return math.ceil(#visibleEmoji / PageSize)
	end

	CalculateVisibleEmoji()

	local BaseIndex = function()
		return (pageNum-1)*GetNumPages()
	end

	local emojiChildren = {}
	for i=1,PageSize do
		local index = i

		emojiChildren[#emojiChildren+1] = gui.Panel{
			classes = {"emojiItem"},
			bgimage = "panels/square.png",
			draggable = true,
			canDragOnto = function(element, target)
				return target:HasClass("favoriteEmoji")
			end,

			drag = function(element, target)
				if target == nil then
					return
				end

				local favorites = GetFavoriteEmoji()
				favorites[target.data.index] = visibleEmoji[BaseIndex() + index]
				SetFavoriteEmoji(favorites)
				resultPanel:FireEventTree("refreshEmoji")
			end,

			click = function(element)
				token.properties:Emote(visibleEmoji[BaseIndex() + index], {deleteOthers = true})
				resultPanel:FireEvent("escape")
			end,

            rightClick = function(element)
                element.popup = gui.ContextMenu{
                    entries = {
                        {
                            text = "Set Keybind...",
                            click = function()
	                            local dataTable = assets.emojiTable
                                local emoteid = visibleEmoji[BaseIndex() + index]
                                local emote = dataTable[emoteid]
                                element.popup = Keybinds.ShowBindPopup{
                                    command = string.format("emote %s", emoteid),
                                    name = string.format("%s Emote", emote.description),
                                    destroy = function()
                                        print("DESTROY:: DESTROYED KEYBIND")
                                        element.root:FireEventTree("refreshEmoji")
                                    end,
                                }
                            end,
                        }
                    }
                }
            end,

			refreshEmoji = function(element)
				element:SetClass("hidden", visibleEmoji[BaseIndex() + index] == nil)
				element:SetClass("selected", visibleEmoji[BaseIndex() + index] ~= nil and loopingEmotes[visibleEmoji[BaseIndex() + index]])
			end,
			gui.CreateTokenImage(token, {
				width = 36,
				height = 36,
			}),
			gui.Panel{
				classes = {"emojiIcon"},
				refreshEmoji = function(element)
					if visibleEmoji[BaseIndex() + index] then
						element.bgimage = visibleEmoji[BaseIndex() + index]
					end
				end,
			},

            gui.Label{
                classes = {"emojiBindLabel"},
				refreshEmoji = function(element)
					local emoteid = visibleEmoji[BaseIndex() + index]
                    if emoteid == nil then
                        element:SetClass("collapsed", true)
                    else
                        local command = string.format("emote %s", emoteid)
                        local binding = dmhub.GetCommandBinding(command)
                        if binding == nil then
                            element:SetClass("collapsed", true)
                        else
                            element.text = binding
                            element:SetClass("collapsed", false)
                        end
                    end
                end,
            },

		}
	end

	emojiPanel.children = emojiChildren

	local favoritesPanel = gui.Panel{
		width = "95%",
		height = 160,
		halign = "center",
		
		flow = "none",
		valign = "center",
	}

	local favorites = GetFavoriteEmoji()
	local favoritePanels = {}

	for index,k in ipairs(favorites) do
		local p = gui.Panel{
			translate = core.Vector2(0,70):Rotate(index*45),

			data = {
				index = index,
			},

			dragTarget = true,
			classes = {"emojiItem", "favoriteEmoji"},
			halign = "center",
			valign = "center",
			bgimage = "panels/square.png",
			click = function(element)
				token.properties:Emote(favorites[index], {deleteOthers = true})
				resultPanel:FireEvent("escape")
			end,

            rightClick = function(element)
                element.popup = gui.ContextMenu{
                    entries = {
                        {
                            text = "Set Keybind...",
                            click = function()
	                            local dataTable = assets.emojiTable
                                local emoteid = favorites[index]
                                local emote = dataTable[emoteid]
                                element.popup = Keybinds.ShowBindPopup{
                                    command = string.format("emote %s", emoteid),
                                    name = string.format("%s Emote", emote.description),
                                    destroy = function()
                                        element.root:FireEventTree("refreshEmoji")
                                    end,
                                }
                            end,
                        }
                    }
                }
            end,


			refreshEmoji = function(element)
				favorites = GetFavoriteEmoji()
				element:SetClass("selected", loopingEmotes[favorites[index]])
			end,
			gui.CreateTokenImage(token, {
				width = 36,
				height = 36,
			}),
			gui.Panel{
				classes = {"emojiIcon"},
				refreshEmoji = function(element)
					element.bgimage = favorites[index]
				end,
			},

            gui.Label{
                classes = {"emojiBindLabel"},
				refreshEmoji = function(element)
					local emoteid = favorites[index]
                    if emoteid == nil then
                        element:SetClass("collapsed", true)
                    else
                        local command = string.format("emote %s", emoteid)
                        local binding = dmhub.GetCommandBinding(command)
                        if binding == nil then
                            element:SetClass("collapsed", true)
                        else
                            element.text = binding
                            element:SetClass("collapsed", false)
                        end
                    end
                end,
            },


		}
		favoritePanels[#favoritePanels+1] = p
	end

	favoritesPanel.children = favoritePanels



	resultPanel = gui.Panel{
		id = "emojiPanel",
		uiscale = 1.5,
		styles = {
			Styles.Default,
			Styles.Panel,
			{
				selectors = "emojiItem",
				flow = "none",
				width = 48,
				height = 48,
				bgcolor = "clear",
				pad = 2,
				halign = "center",
				cornerRadius = 12,
			},
			{
				selectors = {"emojiItem", "drag-target"},
				bgcolor = "#ffffff44",
			},
			{
				selectors = {"emojiItem", "drag-target-hover"},
				bgcolor = "#ffff8899",
			},
			{
				selectors = {"emojiItem", "selected"},
				borderWidth = 2,
				borderColor = "#888888ff",
			},
			{
				selectors = {"emojiItem", "hover"},
				borderWidth = 2,
				borderColor = "white",
			},
			{
				selectors = {"emojiItem", "press"},
				borderWidth = 2,
				borderColor = "#888888ff",
			},
			{
				selectors = "emojiIcon",
				width = 81,
				height = 81,
				halign = "center",
				valign = "center",
				bgcolor = "white",
			},
            {
                selectors = {"emojiBindLabel"},
                bgimage = "panels/square.png",
                bgcolor = "#000000fa",
                borderColor = "#000000fa",
                borderWidth = 5,
                pad = 2,
                borderFade = true,
                valign = "top",
                halign = "right",
                width = "auto",
                height = "auto",
                fontSize = 10,
                color = "white",
            },
			{
				selectors = {"create"},
				transitionTime = 0.2,
				opacity = 0,
				scale = 0.9,
			},
			{
				selectors = {"title"},
				fontSize = 20,
				vmargin = 8,
				color = "white",
				width = "auto",
				height = "auto",
				halign = "center",
				valign = "center",
			},
		},
		classes = {"framedPanel"},
		width = 340,
		height = 540,

		halign = "center",
		valign = "center",
		flow = "vertical",

		captureEscape = true,
		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,

		escape = function(element)
			element:DestroySelf()
		end,

		clickaway = function(element)
			element:FireEvent("escape")
		end,

		gui.Label{
			text = "Favorite Emotes",
			fontFace = "SupernaturalKnight",
			classes = {"title"},
		},

		favoritesPanel,

		gui.Label{
			text = "All Emotes",
			fontFace = "SupernaturalKnight",
			classes = {"title"},
		},


		gui.Input{
			placeholderText = "Search for Emotes...",
			halign = "center",
			valign = "center",
			hpad = 10,
			width = 180,
			height = 16,
			fontSize = 12,
			text = "",
			margin = 6,
			hasFocus = true,
			borderColor = "black",
			borderWidth = 7,
			borderFade = true,
			edit = function(element)
				search = element.text
				CalculateVisibleEmoji()
				resultPanel:FireEventTree("refreshEmoji")
			end,
		},

		emojiPanel,

		gui.Panel{
			flow = "horizontal",
			width = "30%",
			height = "auto",
			halign = "center",
			valign = "center",
			gui.Panel{
				bgimage = "panels/InventoryArrow.png",
				bgcolor = "white",
				width = 8,
				height = 16,
				halign = "left",
				click = function(element)
					SetPageNum(pageNum - 1)
					resultPanel:FireEventTree("refreshEmoji")
				end,
			},

			gui.Label{
				width = "auto",
				height = "auto",
				fontSize = 10,
				color = "white",
				halign = "center",
				valign = "center",
				vmargin = 8,
				text = "Page 1/1",
				refreshEmoji = function(element)
					element.text = string.format("Page %d/%d", pageNum, GetNumPages())
				end,
			},

			gui.Panel{
				bgimage = "panels/InventoryArrow.png",
				bgcolor = "white",
				scale = { x = -1, y = 1 },
				width = 8,
				height = 16,
				halign = "right",
				click = function(element)
					SetPageNum(pageNum + 1)
					resultPanel:FireEventTree("refreshEmoji")
				end,

			},
		},
	}

	resultPanel:FireEventTree("refreshEmoji")

	self.mainDialogPanel:AddChild(resultPanel)
end

local g_init = false
dmhub.RegisterEventHandler("refreshTables", function(keys)
    if g_init then
        return
    end

    Keybinds.RegisterSection{
        key = "emotes",
        name = tr("Emotes"),
        hideUnlessBound = true,
    }
    
    g_init = true

	local dataTable = assets.emojiTable
    for k,emoji in pairs(dataTable) do
        if not emoji.hidden then
            Keybinds.Register{
                name = string.format("%s emote", emoji.description),
                command = string.format("emote %s", k),
                section = "emotes",
            }
        end
    end

end)