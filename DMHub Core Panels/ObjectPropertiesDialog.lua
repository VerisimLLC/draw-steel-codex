local mod = dmhub.GetModLoading()

mod.shared.objectDragAcceptors = {}

--Execute a component command (e.g. "Open Door") on a specific map object,
--addressed by floor id + object id. This is the executable form recorded by
--the command builder's lightning icons on the property dialog's command
--buttons, so journal macro buttons can drive specific objects.
Commands.RegisterMacro{
    name = "objectcommand",
    summary = "execute a command on a map object",
    doc = "Usage: /objectcommand <floorid> <objectid> <command>. Executes the named component command (e.g. Open Door) on the given object. The command builder's lightning icons on object command buttons record this for you.",
    command = function(str)
        local floorid, objid, cmdName = string.match(str or "", "^%s*(%S+)%s+(%S+)%s+(.-)%s*$")
        if floorid == nil or cmdName == nil or cmdName == "" then
            dmhub.Log("objectcommand: usage: /objectcommand <floorid> <objectid> <command>")
            return
        end

        local obj = game.LookupObject(floorid, objid)
        if obj == nil or not obj.valid then
            dmhub.Log(string.format("objectcommand: object not found: %s on floor %s", objid, floorid))
            return
        end

        --components is keyed by component id; find every component offering
        --this command and execute it on each, matching what pressing the
        --dialog's button does.
        local executed = false
        for _,component in pairs(obj.components) do
            for _,cmd in ipairs(component.commands) do
                if cmd == cmdName then
                    component:Execute(cmd)
                    executed = true
                    break
                end
            end
        end

        if not executed then
            dmhub.Log(string.format("objectcommand: object %s has no command named '%s'", objid, cmdName))
        end
    end,
}

--Activate/deactivate/toggle a specific map object, addressed by floor id +
--object id. Same semantics as /activateobjects (Codex Macros), but targeting
--one object by identity rather than by keyword -- the form the command
--builder records from the bolt next to the object's name.
Commands.RegisterMacro{
    name = "objectactivate",
    summary = "activate or deactivate a map object",
    doc = "Usage: /objectactivate <floorid> <objectid> <on|off|toggle>. Activates (on), deactivates (off), or toggles the given object.",
    command = function(str)
        local floorid, objid, mode = string.match(str or "", "^%s*(%S+)%s+(%S+)%s+(%S+)%s*$")
        if mode ~= "on" and mode ~= "off" and mode ~= "toggle" then
            dmhub.Log("objectactivate: usage: /objectactivate <floorid> <objectid> <on|off|toggle>")
            return
        end

        local obj = game.LookupObject(floorid, objid)
        if obj == nil or not obj.valid then
            dmhub.Log(string.format("objectactivate: object not found: %s on floor %s", objid, floorid))
            return
        end

        local newInactive
        if mode == "on" then
            newInactive = false
        elseif mode == "off" then
            newInactive = true
        else
            newInactive = not obj.inactive
        end

        if newInactive ~= obj.inactive then
            obj.inactive = newInactive
            obj:Upload()
        end
    end,
}

--Enable/disable/toggle a property (component) on a specific map object,
--matched by the property's display name (e.g. Solid). Recorded by the bolt
--on the property-header entries in the object properties dialog. Setting
--component.disabled persists by itself (same as the dialog's right-click
--Enable/Disable Property menu and /activateobjects).
Commands.RegisterMacro{
    name = "objectproperty",
    summary = "enable or disable a property on a map object",
    doc = "Usage: /objectproperty <floorid> <objectid> <on|off|toggle> <property name>. Enables (on), disables (off), or toggles the named property on the given object, e.g. /objectproperty <floorid> <objectid> off Solid.",
    command = function(str)
        local floorid, objid, mode, propName = string.match(str or "", "^%s*(%S+)%s+(%S+)%s+(%S+)%s+(.-)%s*$")
        if propName == nil or propName == "" or (mode ~= "on" and mode ~= "off" and mode ~= "toggle") then
            dmhub.Log("objectproperty: usage: /objectproperty <floorid> <objectid> <on|off|toggle> <property name>")
            return
        end

        local obj = game.LookupObject(floorid, objid)
        if obj == nil or not obj.valid then
            dmhub.Log(string.format("objectproperty: object not found: %s on floor %s", objid, floorid))
            return
        end

        local found = false
        for _,component in pairs(obj.components) do
            if component.name == propName then
                found = true
                local newDisabled
                if mode == "on" then
                    newDisabled = false
                elseif mode == "off" then
                    newDisabled = true
                else
                    newDisabled = not component.disabled
                end
                component.disabled = newDisabled
            end
        end

        if not found then
            dmhub.Log(string.format("objectproperty: object %s has no property named '%s'", objid, propName))
        end
    end,
}

--Set a field of a property on a specific map object. The property name,
--field id, and value are '::'-delimited since the property name and value
--may contain spaces. Boolean fields accept on/off/toggle; numeric fields a
--number; everything else takes the raw string (e.g. an enum id).
Commands.RegisterMacro{
    name = "objectfield",
    summary = "set a property field on a map object",
    doc = "Usage: /objectfield <floorid> <objectid> <property name>::<field id>::<value>. Sets the field on the named property of the given object. Boolean fields accept on, off, or toggle.",
    command = function(str)
        local floorid, objid, rest = string.match(str or "", "^%s*(%S+)%s+(%S+)%s+(.-)%s*$")
        local propName, fieldid, value
        if rest ~= nil then
            propName, fieldid, value = string.match(rest, "^(.-)::(.-)::(.*)$")
        end
        if propName == nil or propName == "" or fieldid == nil or fieldid == "" then
            dmhub.Log("objectfield: usage: /objectfield <floorid> <objectid> <property name>::<field id>::<value>")
            return
        end

        local obj = game.LookupObject(floorid, objid)
        if obj == nil or not obj.valid then
            dmhub.Log(string.format("objectfield: object not found: %s on floor %s", objid, floorid))
            return
        end

        local applied = false
        local groupid = dmhub.GenerateGuid()
        for _,component in pairs(obj.components) do
            if component.name == propName then
                for _,field in ipairs(component.fields) do
                    if field.id == fieldid then
                        local v = nil
                        if field.fieldType == "bool" then
                            if value == "toggle" then
                                v = not field:GetValue(1)
                            else
                                v = (value == "on" or value == "true")
                            end
                        elseif field.fieldType == "int" then
                            v = tonumber(value)
                            if v ~= nil then
                                v = math.floor(v)
                            end
                        elseif field.fieldType == "float" then
                            v = tonumber(value)
                        else
                            v = value
                        end

                        if v ~= nil then
                            field:SetValue(v, 1)
                            field:Upload(groupid)
                            applied = true
                        end
                    end
                end
            end
        end

        if not applied then
            dmhub.Log(string.format("objectfield: could not set field '%s' on property '%s' of object %s", fieldid, propName, objid))
        end
    end,
}

--Executes a "macro" field's recorded command. The engine fires this global
--event on the pressing client when a Button property with a non-empty Command
--field is pressed (ObjectComponentButton in LevelObject.cs). The stored
--command keeps its {name} step annotations; strip them before execution, the
--same way journal and rail command buttons run theirs.
dmhub.RegisterEventHandler("objectButtonCommand", function(command)
    if type(command) ~= "string" or command == "" then
        return
    end
    dmhub.Execute(CommandBuilder.StripAnnotations(command))
end)

-- External-text-editor watchers tied to object lifetime (not panel lifetime).
-- Keyed by "objid/componentid/fieldName". Each entry holds the watcher plus
-- the floorid/objid needed to detect deletion. Survives property-sheet close;
-- a periodic poll (below) cleans up entries whose object no longer exists.
local g_externalEditorWatchers = {}
local g_externalEditorPollScheduled = false

local function externalEditorPoll()
    if mod.unloaded then
        g_externalEditorPollScheduled = false
        return
    end

    local toRemove = nil
    for key, entry in pairs(g_externalEditorWatchers) do
        local floor = game.GetFloor(entry.floorid)
        local alive = floor ~= nil and floor:HasObject(entry.objid)
        if not alive then
            entry.watcher:Destroy()
            toRemove = toRemove or {}
            toRemove[#toRemove + 1] = key
        end
    end

    if toRemove ~= nil then
        for _, k in ipairs(toRemove) do
            g_externalEditorWatchers[k] = nil
        end
    end

    if next(g_externalEditorWatchers) == nil then
        g_externalEditorPollScheduled = false
        return
    end

    dmhub.Schedule(2, externalEditorPoll)
end

local function startExternalEditorPoll()
    if g_externalEditorPollScheduled then return end
    g_externalEditorPollScheduled = true
    dmhub.Schedule(2, externalEditorPoll)
end

local CreateEditorPanel = function(fieldInfo, displayInfo, options, valueIndex, resultOptions)

    print("EDITOR::", fieldInfo.type)
    if fieldInfo.type == "externaltexteditor" then
        local objid = tostring(fieldInfo.component.objid or "obj")
        local componentid = tostring(fieldInfo.component.componentid or "comp")
        local floorid = fieldInfo.component.floorid
        local watcherKey = string.format("%s/%s/%s", objid, componentid, fieldInfo.id)

        local labelIdle = "Edit Externally"
        local labelActive = "Editing... (click to close)"

        editorPanel = gui.Button{
            width = 160,
            height = 24,
            fontSize = 14,
            text = (g_externalEditorWatchers[watcherKey] ~= nil) and labelActive or labelIdle,
            halign = "right",
            valign = "center",

            click = function(element)
                local existing = g_externalEditorWatchers[watcherKey]
                if existing ~= nil then
                    existing.watcher:Destroy()
                    g_externalEditorWatchers[watcherKey] = nil
                    element.text = labelIdle
                    return
                end

                local currentValue = tostring(fieldInfo.fieldList[1]:GetValue(valueIndex) or "")

                local watcher = dmhub.OpenTextFileInConnectedEditor(currentValue,
                    function(contents)
                        -- If the object went away (deleted) and the poll
                        -- hasn't caught it yet, drop the watcher and bail
                        -- rather than re-creating the deleted component.
                        local liveFloor = game.GetFloor(floorid)
                        if liveFloor == nil or liveFloor:HasObject(objid) == false then
                            local entry = g_externalEditorWatchers[watcherKey]
                            if entry ~= nil then
                                entry.watcher:Destroy()
                                g_externalEditorWatchers[watcherKey] = nil
                            end
                            return
                        end

                        local groupid = dmhub.GenerateGuid()
                        for i, fieldInstance in ipairs(fieldInfo.fieldList) do
                            fieldInstance:SetValue(contents, valueIndex)
                            if options.objectInstances then
                                fieldInstance:Upload(groupid)
                            end
                        end
                        if options.onchange ~= nil then
                            options.onchange()
                        end
                    end)

                if watcher == nil then
                    gui.ModalMessage{
                        title = "Could not open editor",
                        message = "Could not spawn an external text editor for this field.",
                    }
                else
                    g_externalEditorWatchers[watcherKey] = {
                        watcher = watcher,
                        objid = objid,
                        floorid = floorid,
                    }
                    startExternalEditorPoll()
                    element.text = labelActive
                end
            end,
        }
    elseif fieldInfo.type == "macro" then
        --a recorded command macro (C# ObjectFieldMacro): a ';'-separated
        --command pipe built with the command builder, stored with {name} step
        --annotations. Mirrors the Record Command flow script buttons use
        --(DocumentSystem.lua): the button starts a recording session out in
        --the app and the completed pipe is written back into the field.
        local statusLabel = gui.Label{
            classes = {"sizeS"},
            width = "100%",
            height = "auto",
            halign = "left",
            tmargin = 4,
            text = "",
        }

        local function RefreshMacroStatus()
            if not statusLabel.valid then
                return
            end
            local command = tostring(fieldInfo.fieldList[1]:GetValue(valueIndex) or "")
            if command == "" then
                statusLabel.text = "No command recorded."
            else
                local parts = {}
                for part in string.gmatch(command, "[^;]+") do
                    local cmd, stepName = CommandBuilder.ParseStep(part)
                    if cmd ~= "" then
                        parts[#parts+1] = "- " .. (stepName or ("/" .. cmd))
                    end
                end
                statusLabel.text = string.format("%d step(s):\n%s", #parts, table.concat(parts, "\n"))
            end
        end

        editorPanel = gui.Panel{
            flow = "vertical",
            width = 220,
            height = "auto",
            halign = "left",
            valign = "center",

            create = function(element)
                RefreshMacroStatus()
            end,
            refreshObjects = function(element)
                RefreshMacroStatus()
            end,

            gui.Button{
                text = "Record Command...",
                width = 160,
                height = 24,
                fontSize = 14,
                halign = "left",
                click = function(element)
                    local floorid = fieldInfo.component.floorid
                    local objid = fieldInfo.component.objid
                    CommandBuilder.Begin{
                        seedCommand = tostring(fieldInfo.fieldList[1]:GetValue(valueIndex) or ""),
                        complete = function(cmd)
                            --recording happens out in the app; the object may
                            --have been deleted in the meantime.
                            if floorid ~= nil and floorid ~= "" then
                                local liveFloor = game.GetFloor(floorid)
                                if liveFloor == nil or liveFloor:HasObject(objid) == false then
                                    return
                                end
                            end

                            local groupid = dmhub.GenerateGuid()
                            for i,fieldInstance in ipairs(fieldInfo.fieldList) do
                                fieldInstance:SetValue(cmd, valueIndex)
                                if options.objectInstances then
                                    fieldInstance:Upload(groupid)
                                end
                            end

                            RefreshMacroStatus()

                            if options.onchange ~= nil then
                                options.onchange()
                            end
                        end,
                    }
                end,
            },
            statusLabel,
        }
    elseif fieldInfo.type == "document" then
        editorPanel = gui.Button{
            width = 96,
            height = 24,
            fontSize = 14,
            text = "Document",
			halign = "right",
			valign = "center",
            click = function(element)
                local changes =false
                local groupid = dmhub.GenerateGuid()
                local docid = nil
                local documentTable = dmhub.GetTable(MarkdownDocument.tableName or {})
                for i,fieldInstance in ipairs(fieldInfo.fieldList) do
                    local val = fieldInfo.fieldList[1]:GetValue(valueIndex)
                    if val == nil or val == '' or documentTable[val] == nil then
                        docid = dmhub.GenerateGuid()
                        local doc = MarkdownDocument.new{
                            id = docid,
                            description = "Sign",
                            parentFolder = game.currentMapId,
                            content = "# Sign Title\nDesign this sign.",
                            annotations = {},
                        }

                        dmhub.SetAndUploadTableItem(MarkdownDocument.tableName, doc)

					    fieldInstance:SetValue(docid, valueIndex)
						fieldInstance:Upload(groupid)
                        changes = true
                    elseif docid == nil then
                        docid = val
                    end
                end

                if changes then
				    options.onchange()
                end

                if docid ~= nil then
                    local documentTable = dmhub.GetTable(MarkdownDocument.tableName or {})
                    local doc = documentTable[docid]
                    doc:ShowDocument{edit = true}
                end
            end,
        }
	elseif fieldInfo.type == 'audio' then
		editorPanel = gui.AudioEditor{
			width = 64,
			height = 64,
			halign = "right",
			valign = "center",
			value = fieldInfo.fieldList[1]:GetValue(valueIndex),

			change = function(element)
				local groupid = dmhub.GenerateGuid()
				for i,fieldInstance in ipairs(fieldInfo.fieldList) do
					fieldInstance:SetValue(element.value, valueIndex)
					if options.objectInstances then
						fieldInstance:Upload(groupid)
					end
				end

				options.onchange()
			end,
			refreshObjects = function(element)
				element.value = fieldInfo.fieldList[1]:GetValue(valueIndex)
			end,
		}
	elseif fieldInfo.type == 'assetid' then
		local dataType = fieldInfo.fieldList[1].arguments[1]
		local dataTable = nil
		if dataType == "emote" then
			dataTable = assets.emojiTable
		end

		local choices = {}

		if dataTable ~= nil then
			for k,v in pairs(dataTable) do
				choices[#choices+1] = {
					id = k,
					text = v.description,
				}
			end
		end

		table.sort(choices, function(a,b)
			return a.text < b.text
		end)

		table.insert(choices, 1, {
			id = "",
			text = "(No Asset)",
		})

		
		editorPanel = gui.Dropdown{
			hasSearch = true,
			x = -10,
			width = 100,
			height = 24,
			halign = 'right',
			valign = 'center',
			fontSize = 12,
			idChosen = fieldInfo.fieldList[1]:GetValue(valueIndex) or "",

			options = choices,
		
			events = {
				change = function(element)
					local groupid = dmhub.GenerateGuid()
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						fieldInstance:SetValue(element.idChosen, valueIndex)
						if options.objectInstances then
							fieldInstance:Upload(groupid)
						end
					end
					options.onchange()
				end,
				refreshObjects = function(element)
					element.idChosen = fieldInfo.fieldList[1]:GetValue(valueIndex) or ""
				end,
			},

		}
	elseif fieldInfo.type == 'image' then
		editorPanel = gui.IconEditor{
			library = fieldInfo.fieldList[1].arguments[1],
			categoriesHidden = true,
			searchHidden = true,
			bgcolor = "white",
			width = 64,
			height = 64,
			halign = "right",
			valign = "center",
			hideButton = true,
            allowNone = true,
			value = fieldInfo.fieldList[1]:GetValue(valueIndex),

			change = function(element)
				local groupid = dmhub.GenerateGuid()
				for i,fieldInstance in ipairs(fieldInfo.fieldList) do
					fieldInstance:SetValue(element.value, valueIndex)
					if options.objectInstances then
						fieldInstance:Upload(groupid)
					end
				end

				options.onchange()
			end,
			refreshObjects = function(element)
				element.value = fieldInfo.fieldList[1]:GetValue(valueIndex)
			end,
		}
	elseif fieldInfo.type == 'imageswap' then
		editorPanel = gui.Panel{
			classes = {"accept-objects", "bordered"},
			width = 64,
			height = 64,
			halign = "center",
			valign = "center",
			dragTarget = true,
			dragTargetPriority = 0,
			flow = "none",

			bgimage = true,

			dragObject = function(element, nodeid)
				dmhub.Debug(string.format("DRAG ONTO: %s", nodeid))
				local groupid = dmhub.GenerateGuid()
				for i,fieldInstance in ipairs(fieldInfo.fieldList) do
					fieldInstance:SetValue(nodeid, valueIndex)
					if options.objectInstances then
						fieldInstance:Upload(groupid)
					end
				end

				element:FireEvent("create")
			end,

			destroy = function(element)
				mod.shared.objectDragAcceptors[element.id] = nil
			end,

			create = function(element)
				mod.shared.objectDragAcceptors[element.id] = element

				local val = fieldInfo.fieldList[1]:GetValue(valueIndex)
				if val == nil or val == '' then
					element.children = {
						gui.Label{
							textAlignment = "center",
							halign = "center",
							valign = "center",
							fontSize = 12,
							width = "100%",
							height = "auto",
							text = "Drag Object Here",
						}
					}
				else
					element.children = {
						gui.Panel{
							classes = {"image"},
							bgimage = val,
							halign = 'center',
							valign = 'center',
							width = '100%',
							height = '100%',
							imageLoaded = function(element)
								local maxDim = max(element.bgsprite.dimensions.x, element.bgsprite.dimensions.y)
								if maxDim > 0 then
									local xratio = element.bgsprite.dimensions.x/maxDim
									local yratio = element.bgsprite.dimensions.y/maxDim
									element.selfStyle.width = tostring(xratio*100) .. '%'
									element.selfStyle.height = tostring(yratio*100) .. '%'
								end
							end,
						}
					}
				end
			end,
		}
	elseif fieldInfo.type == "curve" then
		resultOptions.showLabel = false
		local ignoreCurveRefresh = 0
		local currentValue = fieldInfo.fieldList[1]:GetValue(valueIndex)

		local RecalculateEndpointGradients = function(element)
			local run = 1
			local rise = currentValue.points[#currentValue.points].y - currentValue.points[1].y

			currentValue.points[1].z = rise/run
			currentValue.points[#currentValue.points].z = rise/run
		end

		editorPanel = gui.Panel{
			bgimage = 'panels/square.png',
			bgcolor = 'black',
			height = "auto",
			width = "auto",
			flow = "vertical",
			swallowPress = true,
			refreshObjects = function(element)
				currentValue = fieldInfo.fieldList[1]:GetValue(valueIndex)
			end,
			styles = {
					{
						cornerRadius = 0,
					},
					{
						selectors = {"input"},
						priority = 20,
						width = 30,
						height = 14,
						hmargin = 6,
						pad = 2,
						fontSize = 12,
						borderWidth = 1,
						valign = "center",
					},
					{
						selectors = {"label"},
						width = "auto",
						height = "auto",
						fontSize = 16,
						valign = "center",
					},
					{
						selectors = {"curveSettings"},
						width = "100%",
						vmargin = 2,
						height = 16,
					},
			},
			gui.Panel{
				flow = "none",
				halign = "center",
				valign = "top",
				width = 200,
				height = 200,
				gui.Curve{
					halign = "left",
					valign = "top",
					width = 180,
					height = 180,
					value = currentValue,

					--this will draw lines on the chart showing where the value is currently being sampled.
					showEditorInfo = function(element)
						local info = fieldInfo.fieldList[1]:GetEditingInfo()
						if info ~= nil then
							element:FireEvent("updateEditorInfo", { x = info.x, y = info.y })
						end
					end,

					refreshObjects = function(element)
						if ignoreCurveRefresh > 0 then
							ignoreCurveRefresh = ignoreCurveRefresh-1
							return
						end
						element.value = currentValue
					end,


					confirm = function(element)
						local groupid = dmhub.GenerateGuid()
						ignoreCurveRefresh = ignoreCurveRefresh+1
						local value = element.value
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							fieldInstance:SetValue(value, valueIndex)
							if options.objectInstances then
								fieldInstance:Upload(groupid)
							end
						end
					end,
				},

				gui.Panel{
					floating = true,
					width = 180,
					height = 18,
					halign = "left",
					valign = "bottom",
					flow = "horizontal",
					gui.Label{
						fontSize = 12,
						width = "auto",
						height = "auto",
						halign = "left",
						valign = "center",
						text = currentValue.xmapping.x,
						refreshObjects = function(element)
							element.text = currentValue.xmapping.x
						end,
					},
					gui.Label{
						fontSize = 14,
							width = "auto",
						height = "auto",
						halign = "center",
						valign = "center",
						text = displayInfo.xlabel,
						refreshObjects = function(element)
							element.text = displayInfo.xlabel
						end,
					},
					gui.Label{
						fontSize = 12,
						width = "auto",
						height = "auto",
						halign = "right",
						valign = "center",
						text = string.format("%.1f", currentValue.xmapping.y),
						refreshObjects = function(element)
							element.text = string.format("%.1f", fieldInfo.fieldList[1]:GetValue(valueIndex).xmapping.y)
						end,
					},
				},

				--labels along the right side.
				gui.Panel{
					width = 20,
					height = 180,
					halign = "right",
					valign = "top",
					flow = "vertical",


					gui.Label{
						fontSize = 10,
						width = "auto",
						height = "auto",
						halign = "center",
						valign = "top",
						text = string.format("%.1f", currentValue.displayRange.y),
						refreshObjects = function(element)
							element.text = string.format("%.1f", currentValue.displayRange.y)
						end,
					},

					gui.Label{
						fontSize = 10,
						width = "auto",
						height = "auto",
						halign = "center",
						valign = "bottom",
						text = string.format("%.1f", currentValue.displayRange.x),
						refreshObjects = function(element)
							element.text = string.format("%.1f", currentValue.displayRange.x)
						end,
					},

				},

				gui.Panel{
					width = 20,
					height = 20,
					halign = "right",
					valign = "center",
					gui.Label{
						floating = true,
						fontSize = 14,
						rotate = 270,
						halign = "center",
						valign = "center",
							width = "auto",
						height = "100% width",
						text = displayInfo.ylabel,
						refreshObjects = function(element)
							element.text = displayInfo.ylabel
						end,
					},
				}


			},

			gui.Panel{
				classes = {"curveSettings"},
				gui.Label{
					text = "Period:",
					fontSize = 12,
					width = "auto",
					height = "auto",
				},
				gui.Input{
					text = currentValue.xmapping.y,
					refreshObjects = function(element)
						element.text = currentValue.xmapping.y
					end,

					change = function(element)
						local groupid = dmhub.GenerateGuid()
						local value = currentValue
						value.xmapping = { x = value.xmapping.x, y = tonumber(element.text) or 0 }
						if value.xmapping.y < value.xmapping.x+0.1 then
							value.xmapping.y = value.xmapping.x+0.1
						end
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							fieldInstance:SetValue(value, valueIndex)
							if options.objectInstances then
								fieldInstance:Upload(groupid)
							end
						end
					end,

				},
			},

			gui.Panel{
				classes = {"curveSettings"},

				gui.Label{
					text = "Range:",
					fontSize = 12,
					width = "auto",
					height = "auto",
				},
				gui.Input{
					text = currentValue.displayRange.x,
					refreshObjects = function(element)
						element.text = currentValue.displayRange.x
					end,

					change = function(element)
						local groupid = dmhub.GenerateGuid()
						local value = currentValue
						value.displayRange = { x = tonumber(element.text) or 0, y = value.displayRange.y }
						if value.displayRange.y < value.displayRange.x+1 then
							value.displayRange.y = value.displayRange.x+1
						end
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							fieldInstance:SetValue(value, valueIndex)
							if options.objectInstances then
								fieldInstance:Upload(groupid)
							end
						end
					end,

				},
				gui.Label{
					text = " to ",
					fontSize = 12,
					width = "auto",
					height = "auto",
				},
				gui.Input{
					text = currentValue.displayRange.y,
					refreshObjects = function(element)
						element.text = currentValue.displayRange.y
					end,

					change = function(element)
						local groupid = dmhub.GenerateGuid()
						local value = currentValue
						value.displayRange = { x = value.displayRange.x, y = tonumber(element.text) or 0}
						if value.displayRange.y < value.displayRange.x+1 then
							value.displayRange.y = value.displayRange.x+1
						end
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							fieldInstance:SetValue(value, valueIndex)
							if options.objectInstances then
								fieldInstance:Upload(groupid)
							end
						end
					end,
				},
			},

			gui.Panel{
				classes = {"curveSettings"},

				gui.Label{
					text = "Value:",
					fontSize = 12,
					width = "auto",
					height = "auto",
				},

				gui.Input{
					text = currentValue.points[1].y,
					refreshObjects = function(element)
						element.text = currentValue.points[1].y
					end,

					change = function(element)
						local groupid = dmhub.GenerateGuid()
						local num = tonumber(element.text) or 0
						currentValue.points[1] = { x = currentValue.points[1].x, y = num, z = currentValue.points[1].z }
						RecalculateEndpointGradients()
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							fieldInstance:SetValue(currentValue, valueIndex)
							if options.objectInstances then
								fieldInstance:Upload(groupid)
							end
						end
					end,
				},

				gui.Label{
					text = " to ",
					fontSize = 12,
					width = "auto",
					height = "auto",
				},
				gui.Input{
					text = currentValue.points[#currentValue.points].y,
					refreshObjects = function(element)
						element.text = currentValue.points[#currentValue.points].y
					end,

					change = function(element)
						local groupid = dmhub.GenerateGuid()
						local num = tonumber(element.text) or 0
						currentValue.points[#currentValue.points] = { x = currentValue.points[#currentValue.points].x, y = num, z = currentValue.points[#currentValue.points].z }
						RecalculateEndpointGradients()
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							fieldInstance:SetValue(currentValue, valueIndex)
							if options.objectInstances then
								fieldInstance:Upload(groupid)
							end
						end
					end,
				},

			},

		}
	elseif fieldInfo.type == 'path' then
		editorPanel = gui.Panel{
			valign = "center",
			width = "auto",
			height = "auto",
			flow = "vertical",
			styles = {
				{
					wrap = false,
				},
			},

			create = function(element)

				local text = "(no path)"
				local val = fieldInfo.fieldList[1]:GetValue(valueIndex)
				if val ~= nil then
					local len = val.length
					if len > 0 then
						text = string.format("%d foot path", round(len*5))
					end
				end
				element.children = {
					gui.Button{
						classes = {"sizeM"},
						text = "Set Path",
						click = function(button)
							element:FireEvent("setpath")
						end,
					},
					gui.Button{
						classes = {"sizeM"},
						text = "Edit Path",
						click = function(button)
							element:FireEvent("editpath")
						end,
					},
					gui.Button{
						classes = {"sizeM"},
						text = "Clear Path",
						click = function(button)
							element:FireEvent("clearpath")
						end,
					},

					gui.Label{
						classes = {"sizeM"},
						text = text,
						hmargin = 4,
						width = "auto",
						height = "auto",
					},
				}
			end,

            clearpath = function(element)
				local groupid = dmhub.GenerateGuid()
				for i,fieldInstance in ipairs(fieldInfo.fieldList) do
					fieldInstance:SetValue(nil, valueIndex)
					if options.objectInstances then
						fieldInstance:Upload(groupid) --upload if possible.
					end
                end
				element:FireEvent("create")
            end,

			setpath = function(element)
				element.children = {
					gui.Label{
						classes = {"sizeS"},
						halign = "left",
						width = "auto",
						height = "auto",
						text = "Draw path...",

						think = function(label)
							local eventSource = editor:SetMapTool{
								tool = "free",
								expires = 1,
								closed = false,
								stabilization = label:Get("objectSmoothingSlider").value,
							}

							eventSource:Listen(label)
						end,
						thinkTime = 0.5,

						tool = function(label, path)
							local groupid = dmhub.GenerateGuid()
							for i,fieldInstance in ipairs(fieldInfo.fieldList) do
								fieldInstance:SetValue(path, valueIndex)
								if options.objectInstances then
									fieldInstance:Upload(groupid) --upload if possible.
								end
							end

							element:FireEvent("create")
						end,

					},

					gui.Panel{
						width = "auto",
						height = "auto",
						flow = "vertical",
						gui.Label{
							classes = {"sizeS"},
							width = "auto",
							height = "auto",
							halign = "left",
							text = "Smooth:",
						},
						gui.Slider{
							id = "objectSmoothingSlider",
							value = 2,
							minValue = 0,
							maxValue = 5,
							sliderWidth = 180,
							labelWidth = 20,
							labelFormat = "%d",
							styles = ThemeEngine.MergeTokens({
								{
									selectors = {"sliderNotch"},
									bgimage = true,
									bgcolor = "@fgMuted",
									width = "100%",
									halign = "center",
									borderWidth = 0,
								},
							}),
							style = {
								height = 20,
								fontSize = 12,
								flow = "none",
								width = 90,
								valign = "center",
							},
							events = {
								confirm = function(element)
									
								end,
							},

						},
					},

					gui.Button{
						halign = "right",
						text = "Cancel",
						click = function(button)
							element:FireEvent("create")
						end,
					},
				}
			end,

			editpath = function(element)
				element.children = {
					gui.Label{
						halign = "left",
						fontSize = 10,
							width = "auto",
						height = "auto",
						text = "Edit path...",

						think = function(label)
							local val = fieldInfo.fieldList[1]:GetValue(valueIndex)
							local eventSource = editor:SetMapTool{
								tool = "objectpoints",
								expires = 0.5,
								path = val,
							}

							eventSource:Listen(label)
						end,
						thinkTime = 0.2,

						tool = function(label, path)
							local groupid = dmhub.GenerateGuid()
							for i,fieldInstance in ipairs(fieldInfo.fieldList) do
								fieldInstance:SetValue(path, valueIndex)
								if options.objectInstances then
									fieldInstance:Upload(groupid) --upload if possible.
								end
							end
						end,
					},

					gui.Button{
						halign = "right",
						text = "Finish",
						click = function(button)
							element:FireEvent("create")
						end,
					},
				}
			end,



		}

	elseif fieldInfo.type == 'color' then
		editorPanel = gui.ColorPicker{
			value = fieldInfo.fieldList[1]:GetValue(valueIndex),
			popupAlignment = 'left',
			hasAlpha = true,
			x = -10,
			events = {
				change = function(element)
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						fieldInstance:SetValue(element.value, valueIndex)
					end
				end,
				confirm = function(element)
					local groupid = dmhub.GenerateGuid()
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						fieldInstance:SetValue(element.value, valueIndex)
						if options.objectInstances then
							fieldInstance:Upload(groupid)
						end
					end
				end,
				refreshObjects = function(element)
					element.value = fieldInfo.fieldList[1]:GetValue(valueIndex)
				end,
			},
			styles = ThemeEngine.MergeTokens({
				{
					halign = 'right',
					valign = 'center',
					height = 24,
					width = 24,
					borderWidth = 2,
					borderColor = '@border',
					fontSize = '30%',
					cornerRadius = 0,
				},
				{
					selectors = 'hover',
					borderColor = '@accent',
				},
				{
					selectors = 'press',
					borderColor = '@accentHover',
				},
			}),
		}
	elseif fieldInfo.type == 'float' then

		local minValue = fieldInfo.fieldList[1].arguments[1] or 0
		local maxValue = fieldInfo.fieldList[1].arguments[2] or 1
		local labelFormat = "%.2f"

		if maxValue >= 100 then
			labelFormat = "%d"
		end

		local fieldOptions = fieldInfo.fieldList[1].options

		local sliderWidth = options.sliderWidth or 220
		local labelWidth = options.labelWidth or 60
		editorPanel = gui.Slider{
			value = fieldInfo.fieldList[1]:GetValue(valueIndex),
			minValue = minValue,
			maxValue = maxValue,
			unclamped = true,
			sliderWidth = sliderWidth,
			labelWidth = labelWidth,
			labelFormat = labelFormat,
			wrap = fieldOptions.rotateControls,
			styles = ThemeEngine.MergeTokens({
				{
					selectors = {"sliderNotch"},
					bgimage = true,
					bgcolor = "@fgMuted",
					width = "100%",
					halign = "center",
					borderWidth = 0,
				},
			}),
			data = {
				randomSpread = {},

			},
			style = {
				halign = 'center',
				valign = 'center',
				bgcolor = 'white',
				fontSize = '30%',
				height = 24,
				width = math.floor((sliderWidth + labelWidth)*1.05),
				flow = 'none',
			},
			events = {
				change = function(element)
					dmhub.Debug("SLIDER:: CHANGE")
					if dmhub.modKeys.ctrl and #element.data.randomSpread == 0 then
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							element.data.randomSpread[#element.data.randomSpread+1] = {
								r = math.random(),
								startValue = element.value, --should this be for each element?
							}
						end
					end

					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						local val = element.value
						if i ~= 1 and dmhub.modKeys.ctrl then
							--when control is held we do a random value spread.
							val = lerp(element.data.randomSpread[i].startValue, val, element.data.randomSpread[i].r)
						end
						fieldInstance:SetValue(val, valueIndex)
					end
					options.onchange()
				end,
				confirm = function(element)
					local groupid = dmhub.GenerateGuid()
					printf("SLIDER:: CONFIRM: %s", groupid)
					element.data.randomSpread = {}
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						if options.objectInstances then
							fieldInstance:Upload(groupid) --upload if possible.
						end
					end
					options.onchange()
				end,
				refreshObjects = function(element)
					element.data.setValueNoEvent(fieldInfo.fieldList[1]:GetValue(valueIndex))
				end,
			},
		}

		if fieldOptions.rotateControls then
			local slider = editorPanel
			editorPanel = gui.Panel{
				halign = 'right',
				valign = 'center',
				width = "auto",
				height = "auto",
				slider,
				gui.Panel{
					width = "auto",
					height = "auto",
					flow = "horizontal",
					halign = "right",
                    rmargin = 8,
                    y = -20,
                    floating = true,

					gui.Panel{
						classes = {"image"},
						bgimage = "panels/hud/anticlockwise-rotation.png",
						width = 16,
						height = 16,
						press = function()
							local val = slider.value
							val = val + 90
							if val >= 360 then
								val = val - 360
							end

							--data.setValue fires change (which applies the value
							--to the field); plain .value assignment is silent.
							slider.data.setValue(val)
							slider:FireEvent("confirm")
						end,
					},

					gui.Panel{
						classes = {"image"},
						bgimage = "panels/hud/clockwise-rotation.png",
						width = 16,
						height = 16,
						press = function()
							local val = slider.value
							val = val - 90
							if val < 0 then
								val = val + 360
							end

							slider.data.setValue(val)
							slider:FireEvent("confirm")
						end,
					},

				}
			}
		end
	elseif fieldInfo.type == 'vector' then
		editorPanel = gui.Panel{
			width = 140,
			height = 24,
			halign = "right",
			valign = "center",
			wrap = false,
			create = function(element)
				local fields = {"x", "y", "z"}
				local children = {}

				for _,field in ipairs(fields) do
					children[#children+1] = gui.FloatInput{
						hmargin = 3,
						opacity = 0.5,
						width = 40,
						valign = "center",
						halign = "center",
						allowNegative = true,
						value = fieldInfo.fieldList[1]:GetValue(valueIndex)[field],
						refreshObjects = function(element)
							element.value = fieldInfo.fieldList[1]:GetValue(valueIndex)[field]
						end,
						change = function(element)
							local val = fieldInfo.fieldList[1]:GetValue(valueIndex)
							val[field] = element.value
							for i,fieldInstance in ipairs(fieldInfo.fieldList) do
								fieldInstance:SetValue(val, valueIndex)
							end
							options.onchange()
						end,
						confirm = function(element)
							local groupid = dmhub.GenerateGuid()
							local val = fieldInfo.fieldList[1]:GetValue(valueIndex)
							val[field] = element.value

							for i,fieldInstance in ipairs(fieldInfo.fieldList) do
								fieldInstance:SetValue(val, valueIndex)
								if options.objectInstances then
									fieldInstance:Upload(groupid)
								end
							end
							options.onchange()
						end,
					}
				end

				element.children = children
			end,

		}
	elseif fieldInfo.type == 'int' then

		editorPanel = gui.Input{
			text = tostring(fieldInfo.fieldList[1]:GetValue(valueIndex)),
			halign = 'right',
			valign = 'center',
			hmargin = 8,
			height = 20,
			width = 60,
			fontSize = 14,
			events = {
				change = function(element)
					local num = tonumber(element.text)
					if num ~= nil then
						local groupid = dmhub.GenerateGuid()
						num = math.floor(num)
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							fieldInstance:SetValue(num, valueIndex)
							if options.objectInstances then
								fieldInstance:Upload(groupid)
							end
						end
					end
				end,
				refreshObjects = function(element)
					element.text = tostring(fieldInfo.fieldList[1]:GetValue(valueIndex))
				end,
			},
		}

	elseif fieldInfo.type == 'string' then
		local multiline = fieldInfo.fieldList[1].arguments[1] or false
		editorPanel = gui.Input{
			text = tostring(fieldInfo.fieldList[1]:GetValue(valueIndex)),
			halign = "left",
			multiline = multiline,
			hmargin = 4,
			height = cond(multiline, "auto", 24),
			minHeight = 24,
			width = 180,
			events = {
				change = function(element)
					local groupid = dmhub.GenerateGuid()
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						fieldInstance:SetValue(element.text, valueIndex)
						if options.objectInstances then
							fieldInstance:Upload(groupid)
						end
					end
				end,
				refreshObjects = function(element)
					element.text = tostring(fieldInfo.fieldList[1]:GetValue(valueIndex))
				end,
			},
		}
	elseif fieldInfo.type == 'goblinscript' then
		editorPanel = gui.GoblinScriptInput{
			value = tostring(fieldInfo.fieldList[1]:GetValue(valueIndex)),
			width = 160,
			halign = "right",
			displayTypes = "none",

			documentation = {
				help = "This GoblinScript is used to determine if a creature passes the filter.",
				output = "boolean",
				subject = creature.helpSymbols,
				subjectDescription = "The creature being examined.",
				symbols = {},
				examples = {},
			},

			change = function(element)
				local groupid = dmhub.GenerateGuid()
				for i,fieldInstance in ipairs(fieldInfo.fieldList) do
					fieldInstance:SetValue(element.value, valueIndex)
					if options.objectInstances then
						fieldInstance:Upload(groupid)
					end
				end
			end,
			refreshObjects = function(element)
				element.value = tostring(fieldInfo.fieldList[1]:GetValue(valueIndex))
			end,
		}

	elseif fieldInfo.type == "enum" then
		editorPanel = gui.Dropdown{
			id = 'EnumDropdown',
			options = displayInfo.enum,
			idChosen = fieldInfo.fieldList[1]:GetValue(valueIndex),
			width = 180,
			height = 24,
			halign = 'left',
			valign = 'center',
			fontSize = 12,

			events = {
				change = function(element)
					local groupid = dmhub.GenerateGuid()
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						fieldInstance:SetValue(element.idChosen, valueIndex)
						if options.objectInstances then
							fieldInstance:Upload(groupid)
						end
					end
				end,
				refreshObjects = function(element)
					element.options = displayInfo.enum
					element.idChosen = fieldInfo.fieldList[1]:GetValue(valueIndex)
				end,
			},

		}
	elseif fieldInfo.type == 'bool' then
		editorPanel = gui.Dropdown{
			id = 'BoolDropdown',
			options = {'Yes', 'No'},
			optionChosen = cond(fieldInfo.fieldList[1]:GetValue(valueIndex), 'Yes', 'No'),
			width = 180,
			height = 24,
            fontSize = 12,
			halign = 'left',
			valign = 'center',
			events = {
				change = function(element)
					local groupid = dmhub.GenerateGuid()
					local newValue = element.optionChosen == 'Yes'
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						fieldInstance:SetValue(newValue, valueIndex)
						if options.objectInstances then
							fieldInstance:Upload(groupid)
						end
					end
				end,
				refreshObjects = function(element)
					element.optionChosen = cond(fieldInfo.fieldList[1]:GetValue(valueIndex), 'Yes', 'No')
				end,
			},
		}
	elseif fieldInfo.type == 'particle' then
		local val = fieldInfo.fieldList[1]:GetValue(valueIndex)
		local fieldOptions = fieldInfo.fieldList[1].options
		editorPanel = gui.ParticleValue{
			halign = "right",
			valign = "center",
			width = 140,
			value = val,
			allowNegative = fieldOptions.allowNegative,

			events = {
				change = function(element)
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						fieldInstance:SetValue(element.value, valueIndex)
					end
					options.onchange()
				end,
				confirm = function(element)
					local groupid = dmhub.GenerateGuid()
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						if options.objectInstances then
							fieldInstance:Upload(groupid) --upload if possible.
						end
					end
					options.onchange()
				end,
				refreshObjects = function(element)
					element.data.setValueNoEvent(fieldInfo.fieldList[1]:GetValue(valueIndex))
				end,
			}
		}
	end

	return editorPanel
end


local CreateFieldEditor = function(fieldInfo, options)

	local displayInfo = fieldInfo.component:GetFieldDisplayInfo(fieldInfo.object, fieldInfo.id)

	local editorPanel = nil
	local resultOptions = {
		showLabel = true
	}

	local editorPanel

	if fieldInfo.array then
		editorPanel = gui.Panel{
			classes = {"bordered"},
			pad = 8,
			width = "100%",
			height = "auto",
			halign = "left",
			flow = "vertical",

			create = function(element)
				local children = {}

				for i = 1,fieldInfo.fieldList[1].count do
					local index = i
					children[#children+1] = gui.Panel{
						flow = "horizontal",

						--TODO: work out why 'auto' causes jumping problems with these.
						width = "100%",
						height = "auto",
						wrap = false,

						CreateEditorPanel(fieldInfo, displayInfo, options, i, resultOptions),
						gui.Button{
							classes = {"closeButton"},
							floating = true,
							halign = "right",
							valign = "center",
                            rmargin = 16,
							escapeActivates = false,
							click = function(element)
								local groupid = dmhub.GenerateGuid()
								for i,fieldInstance in ipairs(fieldInfo.fieldList) do
									fieldInstance:Remove(index)
									if options.objectInstances then
										element.parent:DestroySelf()
										fieldInstance:Upload(groupid)
									end
								end
							end,
						},
					}
				end

                local emptyLabel = nil
                if fieldInfo.fieldList[1].count == 0 then
                    emptyLabel = gui.Label{
                        classes = {"sizeS"},
                        valign = "center",
                        hmargin = 4,
                        text = string.format("%s empty", fieldInfo.prettyName),
                        width = "auto",
                        height = "auto",
                    }
                end

				children[#children+1] =
                gui.Panel{
                    flow = "horizontal",
                    width = "auto",
                    height = "auto",
                    gui.Button{
                        classes = {"addButton"},
                        click = function(element)
                            local groupid = dmhub.GenerateGuid()
                            for i,fieldInstance in ipairs(fieldInfo.fieldList) do
                                fieldInstance:Append()
                                if options.objectInstances then
                                    fieldInstance:Upload(groupid)
                                end
                            end

                            element:FireEventOnParents("refreshObjects")
                        end,
                    },
                    emptyLabel,
                }

				element.children = children
			end,

			refreshObjects = function(element)
				element:FireEvent("create")
			end,
		}
	else
		editorPanel = CreateEditorPanel(fieldInfo, displayInfo, options, 1, resultOptions)
	end

	--command-builder affordance: bolts on field rows recording
	--"/objectfield <floorid> <objid> <property>::<field id>::<value>" steps,
	--mirroring the settings editors: bool -> on/off/toggle menu, enum ->
	--set-to-each-option menu, float -> slider popup, int -> input popup.
	--Arrays and rich field types (images, curves, paths, ...) have no
	--command form and get no bolt.
	local fieldLightning = nil
	if not fieldInfo.array then
		local comp = fieldInfo.component
		local recordable = comp.floorid ~= nil and comp.floorid ~= ""
			and comp.objid ~= nil and comp.objid ~= ""
		if recordable then
			local prettyName = fieldInfo.prettyName
			local MakeCommand = function(value)
				return string.format("objectfield %s %s %s::%s::%s", comp.floorid, comp.objid, comp.name, fieldInfo.id, tostring(value))
			end

			if fieldInfo.type == "bool" then
				fieldLightning = {
					entries = function()
						return {
							{
								text = string.format("Turn %s on", prettyName),
								command = MakeCommand("on"),
								stepText = string.format("%s on", prettyName),
							},
							{
								text = string.format("Turn %s off", prettyName),
								command = MakeCommand("off"),
								stepText = string.format("%s off", prettyName),
							},
							{
								text = string.format("Toggle %s", prettyName),
								command = MakeCommand("toggle"),
								stepText = string.format("Toggle %s", prettyName),
							},
						}
					end,
				}
			elseif fieldInfo.type == "enum" then
				fieldLightning = {
					entries = function()
						local entries = {}
						local enumOptions = (displayInfo ~= nil and displayInfo.enum) or {}
						for _,opt in ipairs(enumOptions) do
							local id, text
							if type(opt) == "table" then
								id = opt.id
								text = tostring(opt.text or opt.id)
							else
								id = opt
								text = tostring(opt)
							end
							entries[#entries+1] = {
								text = string.format("Set %s to %s", prettyName, text),
								command = MakeCommand(id),
								stepText = string.format("%s = %s", prettyName, text),
							}
						end
						return entries
					end,
				}
			elseif fieldInfo.type == "float" then
				fieldLightning = {
					createPopup = function(iconElement)
						local minValue = fieldInfo.fieldList[1].arguments[1] or 0
						local maxValue = fieldInfo.fieldList[1].arguments[2] or 1
						local labelFormat = cond(maxValue >= 100, "%d", "%.2f")
						local m_value = fieldInfo.fieldList[1]:GetValue(1)
						local slider = gui.Slider{
							minValue = minValue,
							maxValue = maxValue,
							value = m_value,
							labelFormat = labelFormat,
							sliderWidth = 140,
							labelWidth = 48,
							events = {
								change = function(element)
									m_value = element.data.getValue()
								end,
								confirm = function(element)
									m_value = element.data.getValue()
								end,
							},
							style = {
								width = 220,
								height = 28,
								fontSize = 12,
							},
						}
						return gui.Panel{
							classes = {"bordered", "bg"},
							width = "auto",
							height = "auto",
							flow = "vertical",
							pad = 8,
							gui.Label{
								text = string.format("Set %s to:", prettyName),
								fontSize = 12,
								width = "auto",
								height = "auto",
							},
							slider,
							gui.Button{
								text = "Add Step",
								fontSize = 12,
								width = "auto",
								height = 24,
								hpad = 10,
								borderBox = true,
								halign = "right",
								vmargin = 4,
								click = function(element)
									CommandBuilder.RecordStep{
										command = MakeCommand(string.format("%g", m_value)),
										text = string.format("%s = " .. labelFormat, prettyName, m_value),
									}
									iconElement.popup = nil
								end,
							},
						}
					end,
				}
			elseif fieldInfo.type == "int" then
				fieldLightning = {
					createPopup = function(iconElement)
						local input = gui.Input{
							text = tostring(fieldInfo.fieldList[1]:GetValue(1)),
							width = 80,
							height = 22,
							fontSize = 12,
							halign = "left",
						}
						return gui.Panel{
							classes = {"bordered", "bg"},
							width = "auto",
							height = "auto",
							flow = "vertical",
							pad = 8,
							gui.Label{
								text = string.format("Set %s to:", prettyName),
								fontSize = 12,
								width = "auto",
								height = "auto",
							},
							input,
							gui.Button{
								text = "Add Step",
								fontSize = 12,
								width = "auto",
								height = 24,
								hpad = 10,
								borderBox = true,
								halign = "right",
								vmargin = 4,
								click = function(element)
									local num = tonumber(input.text)
									if num == nil then
										return
									end
									num = math.floor(num)
									CommandBuilder.RecordStep{
										command = MakeCommand(num),
										text = string.format("%s = %d", prettyName, num),
									}
									iconElement.popup = nil
								end,
							},
						}
					end,
				}
			end

			if fieldLightning ~= nil then
				fieldLightning.floating = true
				fieldLightning.halign = "right"
				fieldLightning.valign = "top"
				fieldLightning.rmargin = 2
				fieldLightning.width = 16
				fieldLightning.height = 16
			end
		end
	end

	local attachFieldLightning = nil
	if fieldLightning ~= nil then
		attachFieldLightning = function(element)
			CommandBuilder.EnsureLightningIcon(element, fieldLightning)
		end
	end

	local resultPanel = gui.Panel{
		bgimage = true,
		classes = {'field-editor-panel', cond(displayInfo ~= nil and displayInfo.hidden, 'collapsed')},
        flow = "vertical",
        height = "auto",
		multimonitor = fieldLightning ~= nil and {"commandcreationmode"} or nil,
		create = attachFieldLightning,
		monitor = attachFieldLightning,
		refreshObjects = function(element)
			displayInfo = fieldInfo.component:GetFieldDisplayInfo(fieldInfo.object, fieldInfo.id)
			element:SetClass('collapsed', displayInfo ~= nil and displayInfo.hidden)
		end,
		children = {
			gui.Label{
				text = fieldInfo.prettyName,
				classes = {'field-description-label', cond(resultOptions.showLabel, nil, 'collapsed')},
				selfStyle = {
                    bmargin = 4,
				},
			},

            gui.Panel{
			    editorPanel,
                width = "auto",
                height = "auto",
                halign = "left",
            },
		},
	}

	return resultPanel
end

local CreateArtistAndKeywordsPanel = function(nodes, options)

	local node = nodes[1]

	local keywordsProperty = nil
	
	if options.blueprint then
		keywordsProperty = node.keywords or ''
	end

	local artistProperty = node.artist
	for i,node in ipairs(nodes) do
		if keywordsProperty ~= nil and keywordsProperty ~= node.keywords then
			keywordsProperty = nil
		end
		if artistProperty ~= node.artist then
			artistProperty = 'multi'
		end
	end

	local artistInfo = nil
	local artistOptions = { { id = 'null', text = '(None)' } }
	for key,option in pairs(assets.artists) do
		artistOptions[#artistOptions+1] = { id = key, text = option.name }
		if key == artistProperty then
			artistInfo = option
		end
	end

	if artistProperty == nil then
		artistProperty = 'null'
	elseif artistProperty == 'multi' then
		artistOptions[#artistOptions+1] = { id = 'multi', text = '(Multiple values)' }
	end

	local artistPanel = nil
	
	if (dmhub.isAdminAccount and options.blueprint) then

		local fieldPanel = gui.Dropdown{
			id = "artist-dropdown",
			classes = {"formStacked"},
			options = artistOptions,
			idChosen = artistProperty,
			thinkTime = 0.2,
			think = function(element)
				element.thinkTime = nil
				element.options = element.options
				element:FireEventTree("refreshDropdown")
			end,
			events = {
				change = function(element)
					for i,n in ipairs(nodes) do
						n.artist = element.idChosen
					end
				end,
			},
		}

		artistPanel = gui.Panel{
			classes = {"formStackedRow"},
			children = {
				gui.Label{
					classes = {"formStacked"},
					text = "Artist:",
				},
				fieldPanel,
			},
		}
	end

	return gui.Panel{
		id = "ArtistsAndKeywords",
		style = {
			vmargin = 2,
		},
		children = {
			artistPanel,
		},
	}
end

local CreateObjectEditor = function(nodes, options)

	local mainPanel

	local previewFloor = nil

	local previewType
	
	if not options.objectInstances then
		previewType = nodes[1].previewType
		previewFloor = game.currentMap:CreatePreviewFloor("ObjectPreview")

	end

	local objectLocked = false
	
	if options.objectInstances then
		objectLocked = nodes[1].locked
	end

	local previewTimeOfDayIndex = 1

	options = options or {}

	local previewTokenId = nil
	local previewObjects = nil

	local selectedComponentName = nil

	options.onchange = function() end

	if options.objectInstances then
		for i,node in ipairs(nodes) do
			node:MarkUndo()
			if selectedComponentName == nil and node.editingInfo ~= nil then
				selectedComponentName = node.editingInfo.selectedComponentName
			end
		end

	end

	if not options.objectInstances then
		options.onchange = function()

			if previewTokenId ~= nil then
				local token = dmhub.GetTokenById(previewTokenId)
				if token ~= nil then
					token:InvalidateObjects()
				end
			end
		end
	end


	local components
	
	local CalculateComponents = function()
		components = {}

		local startingComponentName = nil
		local startingComponentPriority = nil
		for i,node in ipairs(nodes) do
			local ordinals = {} --mapping of name -> number of components of this name we have.
			for k,component in pairs(node.components) do
				local name = component.name
				local ordinal = ordinals[name] or 0
				ordinals[name] = ordinal+1

				component.ordinal = ordinal

				if ordinal > 0 then
					name = string.format("%s-%d", name, ordinal)
				end

				if startingComponentPriority == nil or component.displayPriority < startingComponentPriority then
					startingComponentName = name
					startingComponentPriority = component.displayPriority
				end

				components[name] = components[name] or {
					componentsList = {},
					name = name,
				}
				local componentsList = components[name].componentsList
				componentsList[#componentsList+1] = {
					object = node,
					componentid = k,
					component = component,
				}
			end
		end

		if selectedComponentName == nil then
			selectedComponentName = startingComponentName
		end

		--fill up the components and previews lists to include preview elements.
		for k,component in pairs(components) do
			local componentsAndPreviews = {}
			for i,element in ipairs(component.componentsList) do
				componentsAndPreviews[#componentsAndPreviews+1] = element
			end
			component.componentsAndPreviews = componentsAndPreviews
		end

		if not options.objectInstances then
			if previewObjects ~= nil then
				for _,obj in ipairs(previewObjects) do
					obj:Destroy()
				end
			end

			--create preview object instances. These are objects in the preview scene.
			previewObjects = {}
			for i,node in ipairs(nodes) do
				local previews = {}

				if previewType == "wield" then
					if previewTokenId == nil then
						previewTokenId = previewFloor:CreateToken(-20, 0)

						dmhub.ScheduleWhen(function() return dmhub.GetTokenById(previewTokenId) ~= nil end,
						function()

							local token = dmhub.GetTokenById(previewTokenId)

							previewFloor.cameraPos = {x = -20, y = 0}
							previewFloor.cameraSize = 1


							local itemid = nil
							local gearTable = dmhub.GetTable("tbl_Gear")
							for k,v in pairs(gearTable) do
								if v:try_get("itemObjectId") == node.id then
									itemid = k
								end
							end

							if itemid ~= nil then
								token.wieldedObjectsOverride = {
									mainhand = itemid,
								}
							end
							game.Refresh()
						end)

					else
						local token = dmhub.GetTokenById(previewTokenId)
						if token ~= nil then
							token:InvalidateObjects()
						end

					end
				else


					local objects = {}
					local newObj = previewFloor:CreateObjectCopy(node)
					newObj.x = 1
					newObj.y = -2
					previewObjects[#previewObjects+1] = newObj

					local newObj = previewFloor:CreateObjectCopy(node)
					newObj.x = 1
					newObj.y = 3
					previewObjects[#previewObjects+1] = newObj

					for i,obj in ipairs(previewObjects) do
						previews[#previews+1] = obj
						for k,component in pairs(obj.components) do
							local name = component.name
							local componentsAndPreviews = components[name].componentsAndPreviews
							componentsAndPreviews[#componentsAndPreviews+1] = {
								object = obj,
								componentid = k,
								component = component,
							}
						end
					end

				end

			end
			game.Refresh()
		end
	end

	CalculateComponents()

	local propertiesLabel = gui.Label{
		classes = {"label-text"},
		text = "Properties",
	}

	local leftPanel

	local addText = options.addPropertyText or "Add Property..."

	local multiComponents = {
		["Path Animation"] = true,
		["Animation Curve"] = true,
		["Mount"] = true,
		["Light"] = true,
		["Darkness"] = true,
	}

	local addPropertiesOptions = assets.objectComponentOptions
	addPropertiesOptions[#addPropertiesOptions+1] = addText

	local artistAndKeywordsPanel = CreateArtistAndKeywordsPanel(nodes, options)

	local editorPanel

	leftPanel = gui.Panel{
		bgimage = true,
		classes = {"left-panel", cond(options.objectInstances, "objectInstances"), cond(options.blueprint, "big")},
		vscroll = true,
		selfStyle = {
			cornerRadius = 8,
		},
		children = {
			propertiesLabel,
		},

		events = {
			create = function(element)
				local children = {}
				for k,componentInfo in pairs(components) do
					local componentName = k
					local completeClass = cond(#componentInfo.componentsList == #nodes, 'complete', 'incomplete')

					--command-builder affordance: a bolt on the property header
					--recording enable/disable/toggle of this property on the
					--specific object(s). Gated the same way as the right-click
					--Enable/Disable Property menu (deletable; CORE cannot be
					--disabled) plus a real placed-object identity.
					local headerComponent = componentInfo.componentsList[1].component
					local headerRecordable = headerComponent.deletable
						and headerComponent.floorid ~= nil and headerComponent.floorid ~= ""
						and headerComponent.objid ~= nil and headerComponent.objid ~= ""
					local propertyName = componentInfo.name

					local attachHeaderLightning = nil
					if headerRecordable then
						attachHeaderLightning = function(element)
							CommandBuilder.EnsureLightningIcon(element, {
								floating = true,
								halign = "right",
								valign = "center",
								rmargin = 2,
								width = 14,
								height = 14,
								entries = function()
									local entries = {}
									local info = components[componentName]
									if info == nil then
										return entries
									end
									local seen = {}
									for _,entry in ipairs(info.componentsList) do
										local comp = entry.component
										if comp.floorid ~= nil and comp.floorid ~= ""
												and comp.objid ~= nil and comp.objid ~= ""
												and not seen[comp.objid] then
											seen[comp.objid] = true
											local objName = nil
											pcall(function()
												local inst = comp.objectInstance
												if inst ~= nil and inst.name ~= nil and inst.name ~= "" then
													objName = tostring(inst.name)
												end
											end)
											local objLabel = objName or "this object"
											local chipPrefix = objName or "Object"
											local target = string.format("%s %s", comp.floorid, comp.objid)
											entries[#entries+1] = {
												text = string.format("Turn %s on for %s", propertyName, objLabel),
												command = string.format("objectproperty %s on %s", target, propertyName),
												stepText = string.format("%s: %s on", chipPrefix, propertyName),
											}
											entries[#entries+1] = {
												text = string.format("Turn %s off for %s", propertyName, objLabel),
												command = string.format("objectproperty %s off %s", target, propertyName),
												stepText = string.format("%s: %s off", chipPrefix, propertyName),
											}
											entries[#entries+1] = {
												text = string.format("Toggle %s for %s", propertyName, objLabel),
												command = string.format("objectproperty %s toggle %s", target, propertyName),
												stepText = string.format("%s: Toggle %s", chipPrefix, propertyName),
											}
										end
									end
									return entries
								end,
							})
						end
					end

					componentInfo.panel = componentInfo.panel or gui.Label{
						bgimage = true,
						text = componentInfo.name,
						classes = {"component-header", "bordered", cond(componentInfo.componentsList[1].component.disabled, "disabled"), completeClass},
						multimonitor = headerRecordable and {"commandcreationmode"} or nil,
						data = {
							ord = componentInfo.componentsList[1].component.displayPriority,
						},
						events = {
							create = attachHeaderLightning,
							monitor = attachHeaderLightning,
							hover = gui.Tooltip(componentInfo.componentsList[1].component.tooltip),
							click = function(element)
								if components[selectedComponentName] ~= nil and components[selectedComponentName].panel ~= nil then
									components[selectedComponentName].panel:SetClass('selected', false)
								end
								selectedComponentName = componentName
								element:SetClass('selected', true)

								--mark our selected component so we can restore it when this object is re-selected.
								if options.objectInstances then
									for i,node in ipairs(nodes) do
										if node.editingInfo == nil then
											node.editingInfo = {}
										end

										node.editingInfo.selectedComponentName = selectedComponentName
									end
								end

								editorPanel:FireEventTree('refresh')
							end,
							rightClick = function(element)

								local menuItems = {}

								local obj = components[componentName].componentsList[1].object

								if componentInfo.componentsList[1].component.deletable then

									local disable = not componentInfo.componentsList[1].component.disabled

									menuItems[#menuItems+1] = {
										text = cond(componentInfo.componentsList[1].component.disabled, 'Enable Property', 'Disable Property'),
										click = function()
											for i,entry in ipairs(components[componentName].componentsList) do
												entry.component.disabled = disable
												break
											end
											componentInfo.panel:SetClass("disabled", disable)
											element.popup = nil
										end,
									}
								end

								if obj ~= nil and obj:IsValidComponentJson(dmhub.GetInternalClipboard()) then
									menuItems[#menuItems+1] = {
										text = "Paste Property",
										click = function()
											local groupid = dmhub.GenerateGuid()
											for i,entry in ipairs(components[componentName].componentsList) do
												entry.object:ConstructComponent(dmhub.GetInternalClipboard())
												entry.object:Upload(groupid)
											end
											element.popup = nil
											CalculateComponents()
											leftPanel:FireEvent('create') --refresh list of properties available for this object.
										end,
									}
								end

								menuItems[#menuItems+1] = {
									text = 'Copy Property',
									click = function()
										for i,entry in ipairs(components[componentName].componentsList) do
                                            print("JSON:: COPY PROPERTY...")
											dmhub.CopyToInternalClipboard(entry.object:ComponentToJson(entry.componentid))
											break
										end
										element.popup = nil
									end,
								}

								if (not objectLocked) and components[componentName].componentsList[1].component.deletable then
									menuItems[#menuItems+1] = {
										text = 'Delete Property',
										click = function()
											local groupid = dmhub.GenerateGuid()
											for i,entry in ipairs(components[componentName].componentsList) do
												entry.object:RemoveComponent(entry.componentid)
												entry.object:Upload(groupid)
											end

											element.popup = nil
											components[componentName] = nil
											if selectedComponentName == componentName then
												selectedComponentName = 'Core'
												editorPanel:FireEventTree('refresh')
											end
											leftPanel:FireEventTree('create')

											CalculateComponents()
										end,
									}
								end

								if #menuItems > 0 then
									element.popup = gui.ContextMenu{
										entries = menuItems
									}
								end
							end,
						},
					}

					componentInfo.panel:SetClass('selected', selectedComponentName == k)

					children[#children+1] = componentInfo.panel
				end

				table.sort(children, function(a,b)
					return a.data.ord < b.data.ord
				end)

				--now we have sorted, put the properties label first.
				table.insert(children, 1, propertiesLabel)

				local addPropertiesDropdown = gui.Dropdown{
					options = addPropertiesOptions,
					idChosen = "none",
					textOverride = addText,
					menuWidth = 200,
					classes = {'add-property-dropdown'},
					events = {
						create = function(element)
							local options = {}
							local availableOptions = assets.objectComponentOptions
							for i,optionInfo in ipairs(availableOptions) do
								if optionInfo.submenu ~= nil then
									local submenuOptions = {}
									for i,subOptionInfo in ipairs(optionInfo.submenu) do
										if components[subOptionInfo.id] == nil or #components[subOptionInfo.id].componentsList < #nodes or multiComponents[subOptionInfo.id] then
											submenuOptions[#submenuOptions+1] = subOptionInfo
										end
									end

									if #submenuOptions > 0 then
										options[#options+1] = {
											text = optionInfo.text,
											submenu = submenuOptions,
										}
									end
								else
									if components[optionInfo.id] == nil or #components[optionInfo.id].componentsList < #nodes or multiComponents[optionInfo.id] then
										options[#options+1] = optionInfo
									end
								end
							end
							element.options = options
						end,
						change = function(element)
							local groupid = dmhub.GenerateGuid()
							local componentName = element.optionChosen
							for i,node in ipairs(nodes) do
								local hasComponent = false
								for k,component in pairs(node.components) do
									local name = component.name
									if name == componentName then
										hasComponent = true
									end
								end

								if hasComponent == false or multiComponents[element.optionChosen] then
									node:AddComponent(componentName)
									if options.objectInstances then
										node:Upload(groupid)
									end
								end
							end

							CalculateComponents()
							element:FireEvent('create') --refresh this dropdown to only have properties not available.
							element.idChosen = "none"
							leftPanel:FireEvent('create') --refresh list of properties available for this object.

							--wait a moment, then select the new component.
							dmhub.Schedule(0.05, function()
								if element == nil or not element.valid then
									return
								end
								for k,component in pairs(components) do
									if component.name == componentName then
										component.panel:FireEvent('click')
									end
								end
							end)
						end,

						lock = function(element, lock)
							element:SetClass("hidden", lock)
						end,
					},
				}

				children[#children+1] = addPropertiesDropdown
				children[#children+1] = artistAndKeywordsPanel

				element.children = children
			end,
		},
	}

	local lockPanel = gui.Panel{
		classes = {"lockOverlay", "hidden"},
		floating = true,
		width = "100%",
		height = "100%-60",
		valign = "bottom",
		lock = function(element, lock)
			element:SetClass("hidden", not lock)
		end,

		gui.Panel{
			classes = {"lockOverlayIcon"},
			bgimage = "icons/icon_tool/icon_tool_30.png",
			halign = "center",
			valign = "center",
			width = 128,
			height = 128,
		},
	}

	local fieldsPanel
	fieldsPanel = gui.Panel{
		classes = {"fieldsPanel", cond(options.blueprint, "big")},
		vscroll = true,
		thinkTime = 0.1,
		styles = {
			{
				flow = "horizontal",
				valign = "top",
				width = "100%",
				height = "100% available",
				borderWidth = 0,
				wrap = true,
			}
		},
		children = {
		},
		events = {
			create = function(element)
				element:FireEventTree('refresh')
			end,
			think = function(element)
				local componentInfo = components[selectedComponentName]
				if componentInfo == nil then
					return
				end
				for i,componentInfo in ipairs(componentInfo.componentsAndPreviews) do
					componentInfo.component:ThinkEdit()
				end

			end,
			refresh = function(element)
				local componentInfo = components[selectedComponentName]
				if componentInfo == nil then
					for k,component in pairs(components) do
						if componentInfo == nil then
							selectedComponentName = k
							componentInfo = component
						end
					end

					if componentInfo == nil then
						return
					end
				end
				local children = {}
				local fieldInfo = {}
				local fieldKeysOrdered = {}
				for i,component in ipairs(componentInfo.componentsAndPreviews) do
					if component.component then
						local fields = component.component.fields
						for i,field in ipairs(fields) do
							if fieldInfo[field.id] == nil then
								fieldKeysOrdered[#fieldKeysOrdered+1] = field.id
							end
							fieldInfo[field.id] = fieldInfo[field.id] or { type = field.fieldType, array = field.array, id = field.id, prettyName = field.prettyName, fieldList = {}, object = component.component.objectInstance, component = component.component }
							local fieldList = fieldInfo[field.id].fieldList
							fieldList[#fieldList+1] = field
						end
					end
				end

				local groupedPanels = {}
				local groupedPanelsChildren = {}
				local ungroupedPanel
				local ungroupedInner
				local ungroupedChildren = {}

				for _,fieldName in ipairs(fieldKeysOrdered) do
					local fieldEntry = fieldInfo[fieldName]
					local fieldOptions = fieldEntry.fieldList[1].options
					local editor = CreateFieldEditor(fieldEntry, options)

					if type(fieldOptions.group) == "string" then
						local group = groupedPanels[fieldOptions.group]

						if group == nil then
							local childrenPanel = gui.Panel{
								classes = {"groupingPanel"},
								flow = "vertical",
								width = "100%",
								height = "auto",
								vpad = 5,
							}
							group = gui.Panel{
								classes = {"sectionPanel", "bordered", cond(options.blueprint, "big")},
								bgimage = true,
								height = "auto",
								flow = "vertical",
								vmargin = 4,

								styles = {
									{
										wrap = false,
									},
								},

								gui.Panel{
									flow = "horizontal",
									width = "90%",
									height = "auto",
									halign = "left",
                                    hpad = 2,
									vpad = 0,
                                    tmargin = 4,
									gui.ExpandoArrow{
										classes = {"expanded"},
										press = function(element)
											element:SetClass("expanded", not element:HasClass("expanded"))
											childrenPanel:SetClass("collapsed", not element:HasClass("expanded"))
										end,
									},
									gui.Label{
										classes = {"sizeL"},
										width = "auto",
										height = "auto",
										halign = "left",
										text = fieldOptions.group,
									},
								},

								childrenPanel,
							}
							groupedPanels[fieldOptions.group] = group
							groupedPanelsChildren[fieldOptions.group] = {}
							children[#children+1] = group
						end

						local childList = groupedPanelsChildren[fieldOptions.group]
						childList[#childList+1] = editor
					else
						if ungroupedPanel == nil then
							ungroupedInner = gui.Panel{
								classes = {"groupingPanel"},
								flow = "vertical",
								width = "100%",
								height = "auto",
								vpad = 5,
							}
							ungroupedPanel = gui.Panel{
								classes = {"sectionPanel", "bordered", cond(options.blueprint, "big")},
								bgimage = true,
								height = "auto",
								flow = "vertical",
								vmargin = 4,

								styles = {
									{
										wrap = false,
									},
								},

								ungroupedInner,
							}
							children[#children+1] = ungroupedPanel
						end
						ungroupedChildren[#ungroupedChildren+1] = editor
					end
				end

				--assign the children to the grouped panels.
				for k,v in pairs(groupedPanels) do
					local panelChildren = groupedPanelsChildren[k]
					v.children[2].children = panelChildren
				end

				if ungroupedInner ~= nil then
					ungroupedInner.children = ungroupedChildren
				end

                local customEditor
				if #componentInfo.componentsAndPreviews == 1 then
					local component = componentInfo.componentsAndPreviews[1].component
					customEditor = component:CreateCustomEditor()

                elseif #componentInfo.componentsAndPreviews > 1 then
                    local components = {}
                    for i,componentInfo in ipairs(componentInfo.componentsAndPreviews) do
                        local component = componentInfo.component
                        components[#components+1] = component
                    end

					local component = componentInfo.componentsAndPreviews[1].component
					customEditor = component:CreateMultiCustomEditor(components)
				end

				if customEditor ~= nil then

					local containerPanel = gui.Panel{
						classes = {"field-editor-panel", "sectionPanel", "bordered", cond(options.blueprint, "big")},
						bgimage = true,
						refreshObjects = function(element)
						end,

						customEditor,
					}

					children[#children+1] = containerPanel
				end




				--add command buttons.
				local commandsAdded = {}
				--command-builder targets per command name: {floorid, objid,
				--name} for each real placed object offering the command, so
				--the lightning menu can record "/objectcommand <floorid>
				--<objid> <cmd>" steps addressing these specific objects.
				local commandTargets = {}
				local cmdButtonClass = cond(options.objectInstances, "sizeS", "sizeM")
				for i,componentInfo in ipairs(componentInfo.componentsAndPreviews) do
					for j,cmd in ipairs(componentInfo.component.commands) do
						local component = componentInfo.component
						local capturedCmd = cmd

						--only real placed objects are recordable; blueprint
						--previews have no floor/object identity to address.
						local recordable = component.floorid ~= nil and component.floorid ~= ""
							and component.objid ~= nil and component.objid ~= ""
						if recordable then
							local objName = nil
							pcall(function()
								local inst = component.objectInstance
								if inst ~= nil and inst.name ~= nil and inst.name ~= "" then
									objName = tostring(inst.name)
								end
							end)
							commandTargets[capturedCmd] = commandTargets[capturedCmd] or {}
							local targets = commandTargets[capturedCmd]
							local seen = false
							for _,t in ipairs(targets) do
								if t.objid == component.objid then
									seen = true
									break
								end
							end
							if not seen then
								targets[#targets+1] = {
									floorid = component.floorid,
									objid = component.objid,
									name = objName,
								}
							end
						end

						local attachLightning = nil
						if recordable then
							attachLightning = function(element)
								CommandBuilder.EnsureLightningIcon(element, {
									floating = true,
									halign = "right",
									valign = "center",
									--just outside the button's right edge;
									--the buttons are centered at 70% width,
									--so this lands inside the dialog.
									rmargin = -22,
									width = 16,
									height = 16,
									entries = function(element)
										local entries = {}
										for _,target in ipairs(commandTargets[capturedCmd] or {}) do
											local objLabel = target.name or "this object"
											entries[#entries+1] = {
												text = string.format("%s on %s", capturedCmd, objLabel),
												command = string.format("objectcommand %s %s %s", target.floorid, target.objid, capturedCmd),
												stepText = string.format("%s: %s", target.name or "Object", capturedCmd),
											}
										end
										return entries
									end,
								})
							end
						end

						children[#children+1] = gui.Button{
							classes = {cmdButtonClass, "cmdButton"},
							text = cmd,
							multimonitor = recordable and {"commandcreationmode"} or nil,
							create = attachLightning,
							monitor = attachLightning,
							click = function(element)
								local commands = commandsAdded[cmd]
								for _,fn in ipairs(commands) do
									fn()
								end
								fieldsPanel:FireEvent("refresh")
							end,
						}

						commandsAdded[cmd] = commandsAdded[cmd] or {}
						commandsAdded[cmd][#commandsAdded[cmd]+1] = function()
							componentInfo.component:Execute(cmd)
						end
					end
				end

				if selectedComponentName == "Core" and options.objectInstances then

					children[#children+1] = gui.Button{
						classes = {cmdButtonClass, "cmdButton"},
						text = "Save to Blueprint",
						click = function(element)

							for i,componentInfo in ipairs(componentInfo.componentsAndPreviews) do
								componentInfo.component:UpdateBlueprint(false)
							end
						end,
					}

					children[#children+1] = gui.Button{
						classes = {cmdButtonClass, "cmdButton"},
						text = "Save to New Blueprint",
						click = function(element)
							for i,componentInfo in ipairs(componentInfo.componentsAndPreviews) do
								componentInfo.component:UpdateBlueprint(true)
							end
						end,
					}

				end

				element.children = children
			end,
		},
	}

	local lockIcon = nil

	if options.objectInstances then
		lockIcon = gui.Panel{
			classes = {"lockIcon", cond(objectLocked, "locked", "unlocked")},
			bgimage = cond(objectLocked, "icons/icon_tool/icon_tool_30.png", "icons/icon_tool/icon_tool_30_unlocked.png"),
			width = 16,
			height = 16,
			halign = "right",
			valign = "right",
			vmargin = 12,
			hmargin = 8,
			press = function(element)
				objectLocked = not objectLocked
				element.bgimage = cond(objectLocked, "icons/icon_tool/icon_tool_30.png", "icons/icon_tool/icon_tool_30_unlocked.png")
				element:SetClass("locked", objectLocked)
				element:SetClass("unlocked", not objectLocked)
				local groupid = dmhub.GenerateGuid()
				for i,currentNode in ipairs(nodes) do
					currentNode.locked = objectLocked
					currentNode:Upload(groupid)
				end

				mainPanel:FireEventTree("lock", objectLocked)
			end,
		}
	end

	local idPanel

	if dmhub.GetSettingValue("dev") then
		idPanel = gui.Panel{
			classes = {"sectionPanel", "bordered", cond(options.blueprint, "big")},
			bgimage = true,

			styles = {
				{
					height = 40,
					flow = "none",
					valign = "top",
				}
			},

			click = function(element)
				dmhub.CopyToClipboard(nodes[1].id)
				gui.Tooltip("copied to clipboard")(element)
			end,

			gui.Label{
				classes = {"field-description-label", "field-name-label", cond(options.objectInstances, "sizeS", "sizeM")},
				selfStyle = {
					halign = "center",
					valign = "center",
					textAlignment = "center",
					width = cond(options.objectInstances, nil, "96%"),
				},

				text = nodes[1].id,
			}
		}
	end

	local childObjectsPanel = nil

	if options.objectInstances and #nodes == 1 then
		local childids = nodes[1].childids
		if childids ~= nil and #childids > 0 then
			local m_childrenLocked = false
			for _,childid in ipairs(childids) do
				local childNode = game.currentFloor:GetObject(childid)
				if childNode ~= nil and childNode.locked then
					m_childrenLocked = true
					break
				end
			end
			childObjectsPanel = gui.Panel{
				classes = {"sectionPanel", "bordered", cond(options.blueprint, "big")},
				-- bgimage = "panels/square.png",
				height = 40,
				flow = "horizontal",
				valign = "top",

				gui.Label{
					text = string.format("Child Objects: %d", #childids),
					classes = {"field-description-label", "field-name-label", "sizeXl"},
					halign = "left",
					valign = "center",
				},

				gui.Panel{
					classes = {"lockIcon", cond(m_childrenLocked, "locked", "unlocked")},
					bgimage = cond(m_childrenLocked, "icons/icon_tool/icon_tool_30.png", "icons/icon_tool/icon_tool_30_unlocked.png"),
					width = 16,
					height = 16,
					halign = "right",
					valign = "right",
					vmargin = 12,
					press = function(element)
						m_childrenLocked = not m_childrenLocked
						element.bgimage = cond(m_childrenLocked, "icons/icon_tool/icon_tool_30.png", "icons/icon_tool/icon_tool_30_unlocked.png")
						element:SetClass("locked", m_childrenLocked)
						element:SetClass("unlocked", not m_childrenLocked)

						local cmdgroup = dmhub.GenerateGuid()

						for _,childid in ipairs(childids) do
							local childNode = game.currentFloor:GetObject(childid)
							if childNode ~= nil then
								childNode.locked = m_childrenLocked
								childNode:Upload(cmdgroup)
							end
						end
					end,
				},
			}
		end
	end

	local multiselectPanel = nil

	local needMultiselect = false
	if options.objectInstances and #nodes > 1 then
		local assetid = nodes[1].assetid
		for _,node in ipairs(nodes) do
			if node.assetid ~= assetid then
				needMultiselect = true
				break
			end
		end
	end

	if needMultiselect then

		local children = {}

		local assetidToIndex = {}

		for _,node in ipairs(nodes) do
			local imageid = node.imageid
			local index = assetidToIndex[imageid] or (#children+1)
			if index > 32 then
				break
			end

			children[index] = children[index] or gui.Panel{
				classes = {"multiPanel"},
				flow = "none",
				data = {
					nodes = {},
				},

				gui.Panel{
					classes = {"image"},
					autosizeimage = true,
					maxWidth = 32,
					maxHeight = 32,
					halign = "center",
					valign = "center",
					bgimage = imageid,
				},

				gui.Label{
					classes = {"sizeXs", "bordered"},
					halign = "right",
					valign = "bottom",
					borderFade = true,
					pad = 2,
					width = "auto",
					height = "auto",

					quantity = function(element, quantity)
						element:SetClass("hidden", quantity <= 1)
						element.text = "x" .. tostring(quantity)
					end,

				},

				gui.Button{
					classes = {"deleteButton", "sizeXs"},
					halign = "right",
					valign = "top",
					click = function(element)
						if options.recreate ~= nil then
							local newNodes = {}
							for i,node in ipairs(nodes) do
								if node.imageid ~= imageid then
									newNodes[#newNodes+1] = node
								end
							end
							options.recreate(mainPanel, newNodes)
						end
					end,

				}
			}

			assetidToIndex[imageid] = index

			local child = children[index]
			child.data.nodes[#child.data.nodes+1] = node
			child:FireEventTree("quantity", #child.data.nodes)
		end

		multiselectPanel = gui.Panel{
			classes = {"sectionPanel", "bordered", cond(options.blueprint, "big")},
			bgimage = true,

			height = "auto",
			flow = "horizontal",
			wrap = true,
			valign = "top",

			styles = {
				{
					selectors = {"multiPanel"},
					width = 32,
					height = 32,
				},
				{
					selectors = {"deleteItemButton"},
					opacity = 0,
				},
				{
					selectors = {"deleteItemButton", "parent:hover"},
					opacity = 1,
				},
			},

			children = children,
		}
	end



	--command-builder affordance: a bolt beside the object's name recording
	--enable/disable/toggle of the object(s) themselves (/objectactivate).
	--Only for placed instances -- blueprints have no object identity.
	local attachObjectLightning = nil
	if options.objectInstances then
		attachObjectLightning = function(element)
			CommandBuilder.EnsureLightningIcon(element, {
				halign = "right",
				valign = "center",
				--to the left of the lock icon at the panel's right edge.
				rmargin = 32,
				width = 16,
				height = 16,
				entries = function()
					local entries = {}
					for _,node in ipairs(nodes) do
						if node.valid and node.floorid ~= nil and node.floorid ~= ""
								and node.objid ~= nil and node.objid ~= "" then
							local objName = nil
							pcall(function()
								if node.name ~= nil and node.name ~= "" then
									objName = tostring(node.name)
								end
							end)
							local objLabel = objName or "this object"
							local chipPrefix = objName or "Object"
							local target = string.format("%s %s", node.floorid, node.objid)
							entries[#entries+1] = {
								text = string.format("Enable %s", objLabel),
								command = string.format("objectactivate %s on", target),
								stepText = string.format("Enable %s", chipPrefix),
							}
							entries[#entries+1] = {
								text = string.format("Disable %s", objLabel),
								command = string.format("objectactivate %s off", target),
								stepText = string.format("Disable %s", chipPrefix),
							}
							entries[#entries+1] = {
								text = string.format("Toggle %s", objLabel),
								command = string.format("objectactivate %s toggle", target),
								stepText = string.format("Toggle %s", chipPrefix),
							}
						end
					end
					return entries
				end,
			})
		end
	end

	local namePanel = gui.Panel{
		classes = {"sectionPanel", "bordered", cond(options.blueprint, "big")},
		bgimage = true,
		tmargin = cond(options.blueprint, 0, 20),

		styles = {
			{
				height = 40,
				flow = "none",
				valign = "top",
			}
		},

		multimonitor = attachObjectLightning ~= nil and {"commandcreationmode"} or nil,
		events = {
			create = attachObjectLightning,
			monitor = attachObjectLightning,
		},

		children = {
			gui.Panel{
				flow = "vertical",
				width = "auto",
				height = "auto",
				halign = "left",
				valign = "center",
				gui.Label{
					text = "Name:",
					classes = {"field-description-label", "sizeS"},
					styles = {
						{
							hmargin = 4,
							halign = "left",
							valign = "center",
						}
					}
				},

				gui.Label{
					--for blueprints this edits the asset's shared description; for placed
					--instances it edits the per-instance name (falls back to the asset
					--description when unset). The instance name field is capped at 32 chars
					--by the engine setter.
					text = cond(options.objectInstances, nodes[1].name, nodes[1].description),
					editable = true,
					classes = {"field-description-label", "field-name-label"},
					selfStyle = {
						halign = "left",
						valign = "center",
						hmargin = 4,
						fontSize = 14,
						bold = true,
					},
					events = {
						change = function(element)
							if options.objectInstances then
								--instance edits must be uploaded to persist + be undoable.
								local groupid = dmhub.GenerateGuid()
								for i,node in ipairs(nodes) do
									node.name = element.text
									node:Upload(groupid)
								end
							else
								for i,node in ipairs(nodes) do
									node.description = element.text
								end
							end
						end,
					},
				},
			},

			lockIcon,
		}
	}

	local keywordsPanel = nil
	
	if not options.objectInstances then
		keywordsPanel = gui.Panel{
			classes = {"sectionPanel", "bordered", cond(options.blueprint, "big")},
			bgimage = true,

			styles = {
				{
					height = 40,
					flow = "none",
					valign = "top",
				}
			},
			children = {
				gui.Label{
					text = "Keywords:",
					classes = {"field-description-label", "sizeXl"},
					styles = {
						{
							hmargin = 4,
							halign = "left",
							valign = "center",
						}
					}
				},

				gui.Input{
					text = nodes[1].keywords,
					placeholderText = "Enter Keywords...",
					editable = not options.objectInstances,
					classes = {'field-description-label', 'field-name-label'},
					bgimage = true,
					selfStyle = {
						width = 400,
						halign = 'center',
						valign = 'center',
						textAlignment = 'left',
					},
					events = {
						change = function(element)
							for i,node in ipairs(nodes) do
								node.keywords = element.text
							end
						end,
					},
				},

				lockIcon,
			}
		}
	end



	local previewImage
	local previewSelector

	if not options.objectInstances then

		previewImage = gui.Panel{
			id = "MapPreviewImage",
			classes = {"image"},
			bgimage = "#MapPreview" .. previewFloor.floorid,
			halign = 'center',
			width = 960/2,
			height = 540/2,

			destroy = function(element)
				game.currentMap:DestroyPreviewFloor(previewFloor)
				game.Refresh()
			end,
		}
		--[[
		local timeofdayLabel = gui.Label{
			text = PreviewLightingTypes[previewTimeOfDayIndex],
			selfStyle = {
				height = "100%",
				width = 200,
				textAlignment = 'center',
			},
			events = {
				refresh = function(element)
					element.text = PreviewLightingTypes[previewTimeOfDayIndex]
				end,
			},
		}
		previewSelector = gui.Panel{
			styles = {
				{
					width = 960/2,
					height = 40,
					flow = "horizontal",
					halign = "center",
					valign = "center",
					bgcolor = 'white',
					fontSize = "40%",
					borderWidth = 0,
				},
				{
					selectors = {"paging-arrow"},
					height = "100%",
					width = "50% height",
				},
				{
					selectors = {'hover', 'paging-arrow'},
					brightness = 2,
					scale = 1.2,
				},
				{
					selectors = {'press', 'paging-arrow'},
					brightness = 0.7,
				},
			},
			children = {
				gui.Panel{
					classes = {"paging-arrow"},
					bgimage = "panels/InventoryArrow.png",
					events = {
						click = function(element)
							previewTimeOfDayIndex = previewTimeOfDayIndex-1
							if previewTimeOfDayIndex < 1 then
								previewTimeOfDayIndex = #PreviewLightingTypes
							end
							timeofdayLabel:FireEvent("refresh")
							previewScene:SetTimeOfDay(PreviewLightingTypes[previewTimeOfDayIndex])
						end,
					},
				},
				timeofdayLabel,
				gui.Panel{
					classes = {"paging-arrow"},
					bgimage = "panels/InventoryArrow.png",
					selfStyle = {scale = {x = -1, y = 1}},
					events = {
						click = function(element)
							previewTimeOfDayIndex = previewTimeOfDayIndex+1
							if previewTimeOfDayIndex > #PreviewLightingTypes then
								previewTimeOfDayIndex = 1
							end
							timeofdayLabel:FireEvent("refresh")
							previewScene:SetTimeOfDay(PreviewLightingTypes[previewTimeOfDayIndex])
						end,
					},
				},
			},
		}
		--]]
	end

	local liveEditPanel = nil
	if options.objectInstances and #nodes == 1 then
		local function ShowReplaceImageError(msg)
			local errModal
			errModal = gui.Panel{
				classes = {"framedPanel"},
				styles = ThemeEngine.GetStyles(),
				width = 440,
				height = "auto",
				halign = "center",
				valign = "center",
				flow = "vertical",
				pad = 20,
				borderBox = true,
				gui.Label{
					width = "100%",
					height = "auto",
					halign = "center",
					color = "white",
					fontSize = 18,
					bold = true,
					bmargin = 10,
					text = "Replace Image Failed",
				},
				gui.Label{
					width = "100%",
					height = "auto",
					halign = "center",
					color = "#ff8888",
					fontSize = 14,
					bmargin = 16,
					text = msg,
				},
				gui.PrettyButton{
					text = "OK",
					width = 120,
					height = 32,
					fontSize = 14,
					halign = "center",
					click = function(element)
						gui.CloseModal()
					end,
				},
			}
			gui.ShowModal(errModal)
		end

		local liveEditButton = nil
		if dmhub.patronTier > 0 then
			liveEditButton = gui.PrettyButton{
				text = "Live Edit",
				width = 130,
				height = 28,
				fontSize = 14,
				vmargin = 3,
				click = function(element)
					nodes[1]:LiveEdit()
				end,
			}
		end

		liveEditPanel = gui.Panel{
			classes = {"sectionPanel", "bordered", cond(options.blueprint, "big"), cond(selectedComponentName ~= "Core" and selectedComponentName ~= "Map", "collapsed")},
			bgimage = true,
			height = 72,
			flow = "horizontal",
			valign = "top",

			--Only show the image-editing controls (Live Edit / Replace Image)
			--when the Core or Map component is selected. Other components
			--(light, collision, etc.) don't edit the object's image, so this
			--panel collapses out of the layout for them. Fired via the
			--editorPanel:FireEventTree('refresh') that runs on component switch.
			refresh = function(element)
				element:SetClass("collapsed", selectedComponentName ~= "Core" and selectedComponentName ~= "Map")
			end,

			gui.Panel{
				bgimage = nodes[1].displayImageId,
				bgcolor = "white",
				width = 48,
				height = 48,
				halign = "left",
				valign = "center",
				hmargin = 8,
				refreshObjects = function(element)
					element.bgimage = nodes[1].displayImageId
				end,
			},

			gui.Panel{
				width = "auto",
				height = "auto",
				flow = "vertical",
				halign = "right",
				valign = "center",
				hmargin = 8,

				liveEditButton,

				gui.PrettyButton{
					text = "Replace Image",
					width = 130,
					height = 28,
					fontSize = 14,
					vmargin = 3,
					click = function(element)
						dmhub.OpenFileDialog{
							id = "replaceObjectImage",
							extensions = {"png", "jpg", "jpeg", "webp"},
							prompt = "Choose a replacement image",
							open = function(path)
								nodes[1]:ReplaceImageFromFile(path, ShowReplaceImageError)
							end,
						}
					end,
				},
			},
		}
	end

	editorPanel = gui.Panel{
		classes = {'editor-panel'},
		children = {
			multiselectPanel,
			namePanel,
			childObjectsPanel,
			idPanel,
			liveEditPanel,
			keywordsPanel,
			previewImage,
			previewSelector,
			fieldsPanel,
			lockPanel,
		},
	}

	mainPanel = gui.Panel{
		id = 'MainObjectPropertiesPanel',
		children = {
			leftPanel,
			editorPanel,
		},
		events = {
			refreshGame = function(element)

				--when refreshing the game, check that components are still valid, and remove any that aren't.
				local deletes = {}
				for componentKey,info in pairs(components) do
					local removeComponents = false
					for _,item in ipairs(info.componentsList) do
						if item.component == nil or not item.component.valid then
							removeComponents = true
						end
					end

					if removeComponents then
						local newComponents = {}
						for _,item in ipairs(info.componentsList) do
							if item.component ~= nil and item.component.valid then
								newComponents[#newComponents+1] = item
							end
						end

						info.componentsList = newComponents

						if #info.componentsList == 0 then
							deletes[#deletes+1] = componentKey
						end
					end
				end

				--if any components have been removed from all selected objects (the common case when components are deleted)
				--then remove their entries and fire appropriate events.
				if #deletes > 0 then
					local refreshSelected = false
					for _,del in ipairs(deletes) do
						components[del] = nil
						if selectedComponentName == del then
							refreshSelected = true
						end
					end

					if refreshSelected then
						selectedComponentName = 'Core'
						editorPanel:FireEventTree('refresh')
					end
					leftPanel:FireEventTree('create')
				end

				if element.enabled then
					element:FireEventTree("refreshObjects")
				end


			end,
		},
	}

	--monitor the game objects and if they change we want to trigger a refresh
	if options.objectInstances then
		mainPanel.monitorGame = dmhub.activeObjectsPath
	end

	if objectLocked then
		mainPanel:FireEventTree("lock", true)
	end
	
	return mainPanel
end

local m_objectEditor = nil

local function CreateObjectEditorPanel()
	local DialogWidth = 440
	local DialogHeight = 500
	if dmhub.GetSettingValue("dev") then
		DialogHeight = DialogHeight + 60
	end

	local extras = {
		{
			width = DialogWidth,
			height = DialogHeight,
			flow = "vertical",
			halign = "left",
			valign = "top",
		},
		-- Lock overlay: semi-transparent scheme-bg veil with a centered themed
		-- lock glyph. Replaces the legacy hardcoded black/white look so the
		-- overlay tracks the active color scheme.
		{
			selectors = {"lockOverlay"},
			bgimage = true,
			bgcolor = "@bg",
			opacity = 0.9,
		},
		{
			selectors = {"lockOverlayIcon"},
			bgcolor = "@fg",
		},
		{
			selectors = {"framedPanel", "hasBanner"},
			height = DialogHeight + DialogWidth/4 + 8,
		},
		{
			selectors = {"framedPanel"},
			collapsed = 1,
			opacity = 0,
			uiscale = {x = 0.01, y = 0.01},
		},
		{
			selectors = {"framedPanel", "show"},
			collapsed = 0,
			opacity = 1,
			uiscale = {x = 1, y = 1},
		},
		{
			selectors = {"framedPanel", "show", "left"},
			x = -400,
		},
		{
			selectors = {"framedPanel", "show", "right"},
			x = 400,
		},
		{
			selectors = {"framedPanel", "show", "above"},
			y = -250,
		},
		{
			selectors = {"framedPanel", "show", "below"},
			y = 250,
		},
		{
			selectors = {"#MainObjectPropertiesPanel"},
			flow = "horizontal",
			height = "100% available",
		},
		{
			selectors = {"editor-panel"},
			priority = 5,
			flow = "vertical",
			width = "70%-20",
			height = "100%-20",
		},
		{
			selectors = {"add-property-dropdown"},
			width = "90%",
			halign = "center",
			tmargin = 6,
		},
		{
			selectors = {"dropdown-option"},
			priority = 10,
			width = "200%",
		},
		{
			selectors = {"left-panel"},
			priority = 5,
			width = "30%",
			height = "100%-20",
		},
		{
			selectors = {"label-text"},
			priority = 4,
			width = "auto",
			height = "auto",
		},
		{
			selectors = {"field-editor-panel"},
			bgcolor = "clear",
			width = "90%",
			minHeight = 40,
			height = "auto",
			priority = 4,
			pad = 4,
			margin = 4,
			flow = "vertical",
		},
		{
			selectors = {"field-editor-panel", "parent:groupingPanel"},
			width = "100%",
		},
		{
			selectors = {"field-description-label"},
			priority = 4,
			textWrap = false,
			width = 80,
			height = "auto",
			halign = "left",
			valign = "center",
		},
		{
			selectors = {"field-name-label"},
			priority = 5,
			maxWidth = 240,
		},
		{
			selectors = {"property-label"},
			priority = 5,
			width = "auto",
			height = "auto",
			margin = 8,
			halign = "right",
		},
		{
			selectors = {"#ArtistsAndKeywords"},
			priority = 5,
			hmargin = 0,
			valign = "bottom",
			width = "100%",
			height = "auto",
			flow = "vertical",
		},
		{
			selectors = {"sectionPanel"},
			bgcolor = "@bgAlt",
			vmargin = 12,
			halign = "center",
			hpad = 12,
			width = "100%-48",
		},
		{
			selectors = {"button", "cmdButton"},
			priority = 10,
			width = "70%",
			halign = "center",
		},
		{
			selectors = {"left-panel"},
			-- bgcolor = "@bgAlt",
			flow = "vertical",
			valign = "top",
			hmargin = 8,
			vmargin = 8,
			borderWidth = 0,
		},
		{
			selectors = {"component-header"},
			bgcolor = "@bgAlt",
			color = "@fg",
			width = "90%",
			height = 30,
			valign = "top",
			halign = "center",
			textAlignment = "center",
			vmargin = 6,
		},
		{
			selectors = {"component-header", "incomplete"},
			color = "@fgMuted",
		},
		{
			selectors = {"component-header", "hover"},
			color = "@fgInverse",
			bgcolor = "@bgInverse",
			borderColor = "@border",
		},
		{
			selectors = {"component-header", "press"},
			bgcolor = "@accentHover",
			borderColor = "@border",
		},
		{
			selectors = {"component-header", "selected"},
			borderColor = "@accent",
			borderWidth = 2,
		},
		{
			selectors = {"component-header", "disabled"},
			brightness = 0.4,
			italics = true,
		},
		{
			selectors = {"lockIcon", "locked"},
			bgcolor = "@fg",
		},
		{
			selectors = {"lockIcon", "unlocked"},
			bgcolor = "@fgMuted",
		},
	}

	local resultPanel
	resultPanel = gui.Panel{
		classes = {"framedPanel"},
		draggable = true,

		destroy = function(element)
			if m_objectEditor == element then
				m_objectEditor = nil
			end
		end,

		beginDrag = function(element)
		end,

		drag = function(element, target)
			element.x = element.x + element.dragDelta.x
			element.y = element.y + element.dragDelta.y
		end,

		width = DialogWidth,
		height = DialogHeight,
		flow = "vertical",
		halign = "left",
		valign = "top",

		styles = ThemeEngine.MergeStyles(extras),
		
		data = {
			objectsShown = {},

			ShowObjects = function(objects)
				resultPanel.data.objectsShown = objects

				--resultPanel.selfStyle.width = DialogWidth
				--resultPanel.selfStyle.height = DialogHeight + DialogWidth/4 + 8

				local closeButton = gui.Button{
					classes = {"closeButton"},
					floating = true,
					halign = "right",
					valign = "top",
					click = function(element)
						resultPanel:DestroySelf()
					end,
				}

				local m_anchorDrag = nil

				local resizePanel = gui.Panel{
					classes = {"collapsed"},
					floating = true,
					halign = "right",
					valign = "bottom",
					width = 32,
					height = 32,
					bgimage = true,
					bgcolor = "clear",
					hoverCursor = "diagonal-expand",
					dragBounds = { x1 = 100, y1 = -1000, x2 = 1000, y2 = -100 },
					draggable = true,
					swallowPress = true,

					beginDrag = function(element)
						m_anchorDrag = {x = resultPanel.selfStyle.width, y = resultPanel.selfStyle.height}
					end,

					dragging = function(element)
						if m_anchorDrag ~= nil then
							resultPanel.selfStyle.width = math.max(DialogWidth, m_anchorDrag.x + element.xdrag)
							resultPanel.selfStyle.height = math.max(DialogHeight, m_anchorDrag.y + element.ydrag)
						end
					end,
					drag = function(element)
						--element.x = element.xdrag
						--element.y = element.ydrag
					end,
				}

				local banner = nil

				local panel
				local createEditorFunction
				createEditorFunction = function()
					return CreateObjectEditor(objects, {
						sliderWidth = 180,
						labelWidth = 30,
						vmargin = 8,
						addPropertyText = 'Add...', --the text to use to add properties. This is the short version for a smaller area.
						objectInstances = true, --this signals that we are editing actual object instances, not blueprints.
						recreate = function(element, newObjects)
							objects = newObjects
							resultPanel.data.objectsShown = objects
							panel = createEditorFunction()
							resultPanel.children = {banner, panel, resizePanel, closeButton}
						end,
					})
					
				end

				panel = createEditorFunction()


				--see if there is a single artist for all objects.

				local artist = nil
				for _,obj in ipairs(objects) do
					if obj.artist ~= nil then
						if artist ~= nil and artist ~= obj.artist then
							artist = nil
							break
						end

						artist = obj.artist
					end
				end

				if artist ~= nil then
					local artistInfo = assets.artists[artist]
					if artistInfo ~= nil and artistInfo.bannerImage ~= nil and artistInfo.bannerImage ~= "" and dmhub.whiteLabel ~= "mcdm" then
						resultPanel:SetClass("hasBanner", true)
						banner = gui.Panel{
							classes = {"image"},
							width = "100%-4",
							height = "25% width",
							halign = "center",
							vmargin = 2,
							cornerRadius = 4,
							bgimage = artistInfo.bannerImage,
							hoverCursor = "hand",
							click = function(element)
								if dmhub.hasStoreAccess then
									GameHud.instance.mainDialogPanel:AddChild(CreateShopScreen{ titlescreen = GameHud.instance, artistid = artist })
								else
									dmhub.OpenArtistPage(artist)
								end
							end,
						}
					end
				end

				resultPanel.children = { banner, panel, resizePanel, closeButton }

				if not resultPanel:HasClass("show") then
					if resultPanel.parent.mousePoint ~= nil then
						resultPanel.x = resultPanel.parent.renderedWidth*resultPanel.parent.mousePoint.x - DialogWidth*0.5
						resultPanel.y = resultPanel.parent.renderedHeight*(1 - resultPanel.parent.mousePoint.y) - DialogHeight * 0.5

						resultPanel:SetClass("above", resultPanel.parent.mousePoint.y < 0.25)
						resultPanel:SetClass("below", resultPanel.parent.mousePoint.y > 0.75)
						resultPanel:SetClass("left", resultPanel.parent.mousePoint.x > 0.5)
						resultPanel:SetClass("right", not resultPanel:HasClass("left"))
					end
					resultPanel:SetClass('show', true)
				end
				return resultPanel
			end,

			ClearObjects = function()
				resultPanel.data.objectsShown = {}
				resultPanel.children = {}
				resultPanel:SetClass('show', false)
			end,
		},
	}

	ThemeEngine.OnThemeChanged(mod, function()
		if resultPanel ~= nil and resultPanel.valid then
			resultPanel.styles = ThemeEngine.MergeStyles(extras)
		end
	end)

	return resultPanel
end

mod.shared.EditObjectDialog = function(nodeids)

	local nodes = {}
	local node = assets:GetObjectNode(nodeids[#nodeids])
	for i,nodeid in ipairs(nodeids) do
		nodes[#nodes+1] = assets:GetObjectNode(nodeid)
	end

	local backups = {}
	for i,node in ipairs(nodes) do
		backups[#backups+1] = node:Backup()
	end

	local mainPanel = CreateObjectEditor(nodes, { blueprint = true })

	local changeAllCheck = gui.Check{
		id = 'change-all-objects-check',
		text = 'Update all objects created with this blueprint',
		value = true,
		x = 270,
		style = {
			cornerRadius = 0,
			borderWidth = 0,
			height = 30,
			width = '40%',
			fontSize = '40%',
			halign = 'left',
		}
	}

	local buttonPanel = gui.Panel{
		id = "BottomButtons",
		width = "90%",
		height = 80,
		margin = 8,
		valign = "bottom",
		halign = "center",
		flow = "horizontal",

		children = {

			gui.Button{
				classes = {"sizeXxl"},
				text = "Confirm",
				halign = "center",
				valign = "center",
				events = {
					click = function(element)
						gui.CloseModal()

						local groupid = dmhub.GenerateGuid()
						for i,currentNode in ipairs(nodes) do
							currentNode:Upload(groupid)
							if changeAllCheck.value then
								currentNode:UpdateObjectInstances()
							end
						end
					end,
				}
			},

			gui.Button{
				classes = {"sizeXxl"},
				text = "Cancel",
				halign = "center",
				valign = "center",
				events = {
					click = function(element)
						for i,node in ipairs(nodes) do
							node:Restore(backups[i])
						end
						gui.CloseModal()
					end,
				}
			},

		}
	}

	local DialogWidth = 1200
	local DialogHeight = 1000

	local extras = {
		{
			width = DialogWidth,
			height = DialogHeight,
			flow = "vertical",
		},
		{
			selectors = {"#MainObjectPropertiesPanel"},
			flow = "horizontal",
			height = "100%-140",
		},
		{
			selectors = {"editor-panel"},
			priority = 5,
			flow = "vertical",
			width = "80%",
			height = "100%",
		},
		{
			selectors = {"dropdown-option"},
			priority = 10,
			cornerRadius = 0,
			width = "200%",
			height = "100%",
			fontSize = 12,
		},
		{
			selectors = {"add-property-dropdown"},
			priority = 5,
			width = "90%",
			height = 40,
			halign = "center",
		},
		{
			selectors = {"left-panel"},
			priority = 5,
			width = "20%",
			height = "100%",
		},
		{
			selectors = {"label-text"},
			priority = 4,
			fontSize = 18,
			width = "auto",
			height = "auto",
		},
		{
			selectors = {"field-editor-panel"},
			bgcolor = "clear",
			width = "40%",
			minHeight = 40,
			height = "auto",
			priority = 4,
			cornerRadius = 8,
			borderWidth = 0,
			pad = 4,
			margin = 4,
			flow = "none",
		},
		{
			selectors = {"field-description-label"},
			priority = 4,
			width = "auto",
			height = "auto",
			halign = "left",
			valign = "center",
		},
		{
			selectors = {"#ArtistsAndKeywords"},
			priority = 5,
			valign = "top",
			width = "100%",
			height = "auto",
			flow = "vertical",
		},
		{
			selectors = {"property-label"},
			priority = 5,
			width = "auto",
			height = "auto",
			fontSize = 12,
			margin = 8,
			halign = "right",
		},
		{
			selectors = {"property-pane"},
			width = "auto",
			height = "auto",
			priority = 5,
			flow = "horizontal",
		},
		{
			selectors = {"sectionPanel"},
			bgcolor = "@bgAlt",
			cornerRadius = 8,
			vmargin = 4,
			halign = "center",
			hpad = 12,
			width = "100%-48",
		},
		{
			selectors = {"sectionPanel", "big"},
			width = "100%-80",
			priority = 5,
		},
		{
			selectors = {"fieldsPanel", "big"},
			width = "100%-34",
			priority = 5,
		},
		{
			selectors = {"left-panel", "big"},
			height = "auto",
			priority = 6,
		},
		{
			selectors = {"left-panel"},
			bgcolor = "@bgAlt",
			flow = "vertical",
			valign = "top",
			hmargin = 8,
			vmargin = 8,
			borderWidth = 0,
		},
		{
			selectors = {"component-header"},
			bgcolor = "@bgAlt",
			color = "@fg",
			fontSize = 18,
			width = "90%",
			height = 44,
			valign = "top",
			halign = "center",
			textAlignment = "center",
			vmargin = 8,
		},
		{
			selectors = {"component-header", "parent:objectInstances"},
			halign = "left",
		},
		{
			selectors = {"component-header", "incomplete"},
			color = "@fgMuted",
		},
		{
			selectors = {"component-header", "hover"},
			color = "@fgInverse",
			bgcolor = "@bgInverse",
			borderColor = "@border",
		},
		{
			selectors = {"component-header", "press"},
			bgcolor = "@accentHover",
			borderColor = "@border",
		},
		{
			selectors = {"component-header", "selected"},
			borderColor = "@accent",
			borderWidth = 2,
		},
		{
			selectors = {"component-header", "disabled"},
			brightness = 0.4,
			italics = true,
		},
		{
			selectors = {"lockIcon", "locked"},
			bgcolor = "@fg",
		},
		{
			selectors = {"lockIcon", "unlocked"},
			bgcolor = "@fgMuted",
		},
	}

	local dialogPanel = gui.Panel{
		id = "EditObjectDialog",
		classes = {"framedPanel"},

		styles = ThemeEngine.MergeStyles(extras),

		children = {
			mainPanel,
			changeAllCheck,
			buttonPanel,
		}
	}

	ThemeEngine.OnThemeChanged(mod, function()
		if dialogPanel ~= nil and dialogPanel.valid then
			dialogPanel.styles = ThemeEngine.MergeStyles(extras)
		end
	end)

	gui.ShowModal(dialogPanel)
end

dmhub.EditObjectDialog = mod.shared.EditObjectDialog


local m_objectsScheduledToShow = nil

--called by DMHub when the selected objects change.
dmhub.ObjectsSelected = function(objects)
	m_objectsScheduledToShow = objects

	--schedule this to make sure it happens early in the frame.
	dmhub.Schedule(0.01, function()
		objects = m_objectsScheduledToShow
		m_objectsScheduledToShow = nil
		
		if objects == nil then
			--we had multiple calls in the same frame and this one isn't needed.
			return
		end

		--get only valid objects
		local validObjects = {}
		for _,obj in ipairs(objects) do
			if obj.valid then
				validObjects[#validObjects+1] = obj
			end
		end

		objects = validObjects

		if #objects == 0 then
			if m_objectEditor ~= nil then
				m_objectEditor.data.ClearObjects()
			end
			return
		end

		if m_objectEditor ~= nil and #m_objectEditor.data.objectsShown == #objects then
			--if we are selecting the exact same objects again then de-select
			local same = true
			for i=1,#objects do
				if objects[i].objid ~= m_objectEditor.data.objectsShown[i].objid or objects[i].floorid ~= m_objectEditor.data.objectsShown[i].floorid then
					same = false
					break
				end
			end

			if same then
				m_objectEditor.data.ClearObjects()
				return
			end
		end

		if m_objectEditor == nil then
			m_objectEditor = CreateObjectEditorPanel()
			gui.ShowDialogOverMap(mod, m_objectEditor, { nofade = true})
		end

		m_objectEditor.data.ShowObjects(objects)
	end)
end
