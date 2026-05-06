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
			classes = {"portraitImage"},
			value = race.portraitid,
			library = "Avatar",
			autosizeimage = true,
			allowPaste = true,
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
			fontSize = 12,
		},
	}

	--the name of the race.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Name:",
		},
		gui.Input{
			classes = {"formStacked"},
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
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Subrace of:",
			},
			gui.Dropdown{
				classes = {"formStacked"},
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
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Description:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = race.details,
			multiline = true,
			minHeight = 50,
			maxHeight = 300,
            characterLimit = 8096,
			vscroll = true,
			height = "auto",
			textAlignment = "topleft",
			change = function(element)
				race.details = element.text
				UploadRace()
			end,
		}
	}

    --race lore.
	children[#children+1] = gui.Panel{
		classes = {"formStackedRow"},
		gui.Label{
			classes = {"formStacked"},
			text = "Lore:",
		},
		gui.Input{
			classes = {"formStacked"},
			text = race.lore,
			multiline = true,
			minHeight = 50,
			maxHeight = 300,
			vscroll = true,
			height = "auto",
            characterLimit = 8192,
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

	if tableName ~= "subraces" then
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
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Name Generator:",
			},
			gui.Dropdown{
				classes = {"formStacked"},
				fontFace = "Inter",  -- THC:: test: force sans font inline on the dropdown panel
				idChosen = race:try_get("nameGenerator", "none"),
				options = nameGeneratorOptions,
				change = function(element)
					race.nameGenerator = element.idChosen
					UploadRace()
				end,
			},
		}

		printf("ZZZ: Race: idChosen = %s ; options = %s", json(race.size), json(sizeOptions))
		--size of creatures in the race.
		children[#children+1] = gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Creature Size:",
			},
			gui.Dropdown{
				classes = {"formStacked"},
				idChosen = race.size,
				options = sizeOptions,
				change = function(element)
					race.size = element.idChosen
					UploadRace()
				end,
			},
		}

		--height.
		children[#children+1] = gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Height:",
			},
			gui.Input{
				classes = {"formStacked"},
				text = tostring(race.height),
				change = function(element)
					race.height = element.text
					UploadRace()
				end,
			},
		}

		--weight.
		children[#children+1] = gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Weight:",
			},
			gui.Input{
				classes = {"formStacked"},
				text = tostring(race.weight),
				change = function(element)
					race.weight = element.text
					UploadRace()
				end,
			},
		}

		--lifespan
		children[#children+1] = gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Life Expectancy:",
			},
			gui.Input{
				classes = {"formStacked"},
				text = tostring(race.lifeSpan),
				change = function(element)
					race.lifeSpan = element.text
					UploadRace()
				end,
			},
		}

		--walking speed.
		children[#children+1] = gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Walking Speed:",
			},
			gui.Input{
				classes = {"formStacked"},
				text = tostring(race.moveSpeeds.walk),
				change = function(element)
					race.moveSpeeds = DeepCopy(race.moveSpeeds) --in case this isn"t init yet.
					race.moveSpeeds.walk = tonumber(element.text) or race.moveSpeeds.walk
					element.text = tostring(race.moveSpeeds.walk)
					UploadRace()
				end,
			},
		}

	end --end main race only data.

	children[#children+1] = gui.Panel{
		width = "100%",
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
		classes = "class-panel",
		-- Theme provides label/input vocabulary (fontSize, color, font) via the
		-- default theme. Local extras here are layout-only — the surface size
		-- of the editor, form-row layout, and an explicit input size that"s
		-- specific to this editor"s column geometry. Per-class label/input
		-- *theme overrides* (fontSize 22, color white) intentionally dropped
		-- so this editor uses default theme styling.
		styles = ThemeEngine.MergeStyles({
			{
				halign = "left",
			},
			{
				classes = {"class-panel"},
				width = 1200,
				height = "90%",
				halign = "left",
				flow = "vertical",
				pad = 20,
			},
		}),
	}

	return racePanel
end
