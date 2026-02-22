local mod = dmhub.GetModLoading()


local SetRace = function(tableName, racePanel, raceid)
	local raceTable = dmhub.GetTable(tableName) or {}
	local race = raceTable[raceid]
	local UploadRace = function()
		dmhub.SetAndUploadTableItem(tableName, race)
	end

	local children = {}

	children[#children+1] = gui.Panel{
		flow = "vertical",
		width = 196,
		height = "auto",
		floating = true,
		halign = "right",
		valign = "top",
		gui.IconEditor{
		value = race.portraitid,
		library = "Avatar",
		width = 196,
		height = "150% width",
		autosizeimage = true,
		allowPaste = true,
		borderColor = Styles.textColor,
		borderWidth = 2,
		change = function(element)
			race.portraitid = element.value
			UploadRace()
		end,
		},
		gui.Label{
			text = "1000x1500 image",
			width = "auto",
			height = "auto",
			halign = "center",
			color = Styles.textColor,
			fontSize = 12,
		},
	}

	--the name of the race.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Name:',
			valign = 'center',
			minWidth = 240,
		},
		gui.Input{
			text = race.name,
			change = function(element)
				race.name = element.text
				UploadRace()
			end,
		},
	}

	if tableName == "subraces" then
		local parentRaceTable = dmhub.GetTable("races") or {}
		local options = {}

		if parentRaceTable[race:try_get("parentRace", "none")] == nil then
			options[#options+1] = {
				id = "none",
				text = "Choose main race...",
			}
		end

		for k,parentRace in pairs(parentRaceTable) do
			options[#options+1] = {
				id = k,
				text = parentRace.name,
			}
		end

		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Subrace of:',
				valign = 'center',
				minWidth = 240,
			},
			gui.Dropdown{
				width = 200,
				height = 40,
				fontSize = 20,
				options = options,
				idChosen = race:try_get("parentRace", "none"),
				change = function(element)
					local val = element.idChosen
					if val == "none" then
						val = nil
					end

					race.parentRace = val
					UploadRace()
				end,
			}
		}
	end

	--race details.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		height = 'auto',
		gui.Label{
			text = "Description:",
			valign = "center",
			minWidth = 240,
		},
		gui.Input{
			text = race.details,
			multiline = true,
			minHeight = 50,
			maxHeight = 300,
			vscroll = true,
			height = 'auto',
			width = 400,
			textAlignment = "topleft",
			change = function(element)
				race.details = element.text
				UploadRace()
			end,
		}
	}

    --race lore.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		height = 'auto',
		gui.Label{
			text = "Lore:",
			valign = "center",
			minWidth = 240,
		},
		gui.Input{
			text = race.lore,
			multiline = true,
			minHeight = 50,
			maxHeight = 300,
			vscroll = true,
			height = 'auto',
			width = 700,
			textAlignment = "topleft",
			change = function(element)
				race.lore = element.text
				UploadRace()
			end,
		}
	}

	local sizeOptions = {}
	for i,size in ipairs(creature.sizes) do
		sizeOptions[#sizeOptions+1] = {
			id = size,
			text = size,
		}
	end

	if tableName ~= 'subraces' then
		--the name generation table to use for this race.
		local nameGeneratorOptions = {
			{
				id = "none",
				text = "(None)",
			},
		}
		local nameDataTable = dmhub.GetTable("nameGenerators") or {}
		for k,rolltableTable in pairs(nameDataTable) do
			nameGeneratorOptions[#nameGeneratorOptions+1] = {
				id = k,
				text = rolltableTable.name,
			}
		end

		table.sort(nameGeneratorOptions, function(a,b) return a.text < b.text end)

		children[#children+1] = gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				text = 'Name Generator:',
				valign = 'center',
				minWidth = 240,
			},
			gui.Dropdown{
				idChosen = race:try_get("nameGenerator", "none"),
				options = nameGeneratorOptions,
				width = 200,
				height = 40,
				fontSize = 20,
				change = function(element)
					race.nameGenerator = element.idChosen
					UploadRace()
				end,
			},
		}

		printf("ZZZ: Race: idChosen = %s ; options = %s", json(race.size), json(sizeOptions))
		--size of creatures in the race.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Creature Size:',
				valign = 'center',
				minWidth = 240,
			},
			gui.Dropdown{
				idChosen = race.size,
				options = sizeOptions,
				width = 200,
				height = 40,
				fontSize = 20,
				change = function(element)
					race.size = element.idChosen
					UploadRace()
				end,
			},
		}

		--height.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Height',
				valign = 'center',
				minWidth = 240,
			},
			gui.Input{
				text = tostring(race.height),
				change = function(element)
					race.height = element.text
					UploadRace()
				end,
			},
		}

		--weight.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Weight',
				valign = 'center',
				minWidth = 240,
			},
			gui.Input{
				text = tostring(race.weight),
				change = function(element)
					race.weight = element.text
					UploadRace()
				end,
			},
		}

		--lifespan
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Life Expectancy',
				valign = 'center',
				minWidth = 240,
			},
			gui.Input{
				text = tostring(race.lifeSpan),
				change = function(element)
					race.lifeSpan = element.text
					UploadRace()
				end,
			},
		}

		--walking speed.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Walking Speed:',
				valign = 'center',
				minWidth = 240,
			},
			gui.Input{
				text = tostring(race.moveSpeeds.walk),
				change = function(element)
					race.moveSpeeds = DeepCopy(race.moveSpeeds) --in case this isn't init yet.
					race.moveSpeeds.walk = tonumber(element.text) or race.moveSpeeds.walk
					element.text = tostring(race.moveSpeeds.walk)
					UploadRace()
				end,
			},
		}

	end --end main race only data.

	children[#children+1] = gui.Panel{
		width = "60%",
		height = "auto",
		race:GetClassLevel():CreateEditor(race, 0, {
			change = function(element)
				racePanel:FireEvent("change")
				UploadRace()
			end,
		})
	}

	if GameSystem.racesHaveLeveling then
		Class.CreateLevelEditor(children, race, UploadRace, 1, GameSystem.numLevels)
	end

	racePanel.children = children
end

function Race.CreateEditor()

	local racePanel
	racePanel = gui.Panel{
		data = {
			SetRace = function(tableName, raceid)
				SetRace(tableName, racePanel, raceid)
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

	return racePanel
end
