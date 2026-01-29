local mod = dmhub.GetModLoading()

--This file implements parties, including both their core rules and the UI for editing them.


RegisterGameType("Party")

Party.name = "New Party"
Party.details = ""
Party.tableName = "parties"
Party.playerParty = false
Party.noncombatant = false
Party.color = "#ffffff"
Party.ord = 1

local defaultPlayerParty = nil

function Party.CreateNew()
	local id = dmhub.GenerateGuid()
	return Party.new{
		id = id,
	}
end

function Party:GetColor()
	return self.color
end

function Party:GetFrame()
	return self:try_get("defaultFrame")
end

function Party:GetName()
	return self.name
end

function Party:GetAllyParties()
	return self:get_or_add("allyParties", {})
end

function Party:AddAllyParty(partyid)
	self:GetAllyParties()[partyid] = true
end

function Party:RemoveAllyParty(partyid)
	self:GetAllyParties()[partyid] = nil
end


function Party.PlayerParty()
	local dataTable = dmhub.GetTable(Party.tableName)

	for k,party in pairs(dataTable) do
		if party.playerParty then
			return party
		end
	end

	for k,party in pairs(dataTable) do
		if party.name == "Players" then
			return party
		end
	end

	for k,party in pairs(dataTable) do
		return party
	end

	if defaultPlayerParty == nil then
		defaultPlayerParty = Party.CreateNew()
		defaultPlayerParty.id = "players"
	end

	return defaultPlayerParty
end

function GetDefaultPartyID()
	return Party.PlayerParty().id
end

function GetParty(id)
	if id == nil or id == "players" then
		id = GetDefaultPartyID()
	end

	local dataTable = dmhub.GetTable(Party.tableName)
	return dataTable[id]
end

--get a list of all party ids.
function GetAllParties()

	local result = {}
	local defaultParty = GetDefaultPartyID()

	result[#result+1] = defaultParty

	local dataTable = dmhub.GetTableVisible(Party.tableName)
	for k,party in pairs(dataTable) do
		if k ~= defaultParty then
			result[#result+1] = k
		end
	end

	return result
end

function GetFriendlyParties()
	local result = {}

	local allParties = GetAllParties()
	allParties[#allParties+1] = "MONSTER"

	for _,partyid in ipairs(allParties) do
		result[partyid] = {}
	end

	local dataTable = dmhub.GetTableVisible(Party.tableName)
	for k,party in pairs(dataTable) do
		local allies = party:GetAllyParties()
		for allyid,_ in pairs(allies) do
			result[k][allyid] = true
			if result[allyid] ~= nil then
				result[allyid][k] = true
			end
		end
	end

	return result
end


local SetData
SetData = function(tableName, partyPanel, partyid)
	local dataTable = dmhub.GetTable(tableName) or {}
	local party = dataTable[partyid]
	local UploadParty = function(partyItem)
		dmhub.SetAndUploadTableItem(tableName, partyItem or party)
	end

	local children = {}

	--the name of the party.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Name:',
			valign = 'center',
			minWidth = 240,
		},
		gui.Input{
			text = party.name,
			change = function(element)
				party.name = element.text
				UploadParty()
			end,
		},
	}

	--the display order of the party.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Display Order:',
			valign = 'center',
			minWidth = 240,
		},
		gui.Input{
			text = tostring(party.ord),
			change = function(element)
				local ord = tonumber(element.text)
				if ord ~= nil then
					party.ord = ord
				end

				element.text = tostring(party.ord)
				UploadParty()
			end,
		},
	}



	--the default frame for this party
	local frameEditor = gui.IconEditor{
		library = "AvatarFrame",
		bgcolor = "white",
		margin = 20,
		width = 64,
		height = 64,
		halign = "left",
		value = party:GetFrame(),
		change = function(element)
			party.defaultFrame = element.value
			UploadParty()
		end,
	}

	local colorPicker = gui.ColorPicker{
		value = party.color,
		hmargin = 8,
		width = 24,
		height = 24,
		valign = 'center',
		borderWidth = 2,
		borderColor = '#999999ff',

		confirm = function(element)
			party.color = element.value
			UploadParty()
		end,
	}

	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		height = 'auto',
		gui.Label{
			text = "Default Frame:",
			valign = "center",
			minWidth = 240,
		},
		frameEditor,
	}

	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		height = 'auto',
		gui.Label{
			text = "Color:",
			valign = "center",
			minWidth = 240,
		},
		colorPicker,
	}

	--party details.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		height = 'auto',
		gui.Label{
			text = "Details:",
			valign = "center",
			minWidth = 240,
		},
		gui.Input{
			text = party.details,
			multiline = true,
			minHeight = 50,
			height = 'auto',
			width = 400,
			textAlignment = "topleft",
			change = function(element)
				party.details = element.text
				UploadParty()
			end,
		}
	}

    children[#children+1] = gui.Check{
        text = "Non-Combatant",
        value = party.noncombatant,
		change = function(element)
			party.noncombatant = element.value
			UploadParty()
		end,
    }

	--party default.
	if party.playerParty then
		children[#children+1] = gui.Label{
			text = "This is the default player party",
			italics = true,
			minWidth = 250,
			textAlignment = "left",
			height = 40,
		}
	else
		children[#children+1] = gui.PrettyButton{
			text = "Make this the player party",
			height = 50,
			width = 300,
			fontSize = 20,
			click = function(element)
				for id,otherParty in pairs(dataTable) do
					if otherParty ~= party and otherParty.playerParty then
						otherParty.playerParty = nil
						UploadParty(otherParty)
					end
				end

				party.playerParty = true
				UploadParty()
				SetData(tableName, partyPanel, partyid)
			end,
		}
	end

	local relationshipValues = {"Friendly", "Hostile"}

	--relationships with other parties.
	local friendsIndex = GetFriendlyParties()
	for friendid,friends in pairs(friendsIndex) do
		if friendid ~= partyid then
			local desc = "monsters"
			local friendInfo = dataTable[friendid]
			if friendInfo ~= nil then
				desc = friendInfo.name
			elseif friendid == GetDefaultPartyID() then
				desc = "players"
			end

			children[#children+1] = gui.Panel{
				classes = {'formPanel'},
				height = 'auto',
				gui.Dropdown{
					options = relationshipValues,
					optionChosen = cond(friends[partyid], "Friendly", "Hostile"),
					width = 160,
					height = 30,
					fontSize = 18,
					change = function(element)
						if element.optionChosen == "Hostile" then
							party:RemoveAllyParty(friendid)
							UploadParty()

							if friendInfo ~= nil then
								friendInfo:RemoveAllyParty(partyid)
								UploadParty(friendInfo)
							end
						else
							party:AddAllyParty(friendid)
							UploadParty()

							if friendInfo ~= nil then
								friendInfo:AddAllyParty(partyid)
								UploadParty(friendInfo)
							end
						end
					end,
				},
				gui.Label{
					hmargin = 8,
					text = "toward " .. desc,
					valign = "left",
					minWidth = 240,
				},
			}
		end
	end

	partyPanel.children = children
end

function Party.CreateEditor()
	local partyPanel
	partyPanel = gui.Panel{
		data = {
			SetData = function(tableName, partyid)
				SetData(tableName, partyPanel, partyid)
			end,
		},
		vscroll = true,
		classes = 'class-panel',
		styles = {
			{
				halign = "left",
			},
			{
				classes = {'class-panel'},
				width = 1200,
				height = '90%',
				halign = 'left',
				flow = 'vertical',
				pad = 20,
			},
			{
				classes = {'label'},
				color = 'white',
				fontSize = 22,
				width = 'auto',
				height = 'auto',
			},
			{
				classes = {'input'},
				width = 200,
				height = 26,
				fontSize = 18,
				color = 'white',
			},
			{
				classes = {'formPanel'},
				flow = 'horizontal',
				width = 'auto',
				height = 'auto',
				halign = 'left',
				vmargin = 2,
			},

		},
	}

	return partyPanel
end

--PartyInfo is the per-game info about a party, such as party inventory, etc.
RegisterGameType("PartyInfo", "loot")

function CreatePartyInfo(partyid)
	return PartyInfo.new{
		partyid = partyid,
	}
end

--- @return table<string, CharacterToken>
function Party.GetPlayerCharacters()
    local charids = {}

    for _,token in ipairs(dmhub.GetTokens{playerControlled = true}) do
        if token.name ~= "" then
            charids[token.charid] = true
        end
    end

    local partyid = GetDefaultPartyID()
    local partyids = dmhub.GetCharacterIdsInParty(partyid)

    for _,charid in ipairs(partyids) do
        charids[charid] = true
    end

    for charid,_ in pairs(charids) do
        charids[charid] = dmhub.GetCharacterById(charid)
        if charids[charid].name == "" or charids[charid].name == nil then
            charids[charid] = nil
        end
    end


    return charids
end