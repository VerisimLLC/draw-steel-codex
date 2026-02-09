local mod = dmhub.GetModLoading()

--This implements the user interface for editing ongoing effects.

function CharacterOngoingEffect.CreateEditor(condid, editorOptions)
	editorOptions = editorOptions or {}
	local tableName = editorOptions.tableName or "characterOngoingEffects"

	local ongoingEffectPanel = gui.Panel{
		classes = 'ongoingEffect-panel',
		styles = {
			{
				classes = {'ongoingEffect-panel'},
				width = 1200,
				height = 'auto',
				halign = 'left',
				valign = 'top',
				flow = 'vertical',
				pad = 20,
			},
			{
				classes = {'label'},
				color = 'white',
				fontSize = 18,
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
			}
		},
		data = {},
	}

	local SetOngoingEffect
	SetOngoingEffect = function(ongoingEffectid)
		local ongoingEffectTable = dmhub.GetTable(tableName) or {}
		local ongoingEffect = ongoingEffectTable[ongoingEffectid]
		local json = dmhub.ToJson(ongoingEffect)
		print("OngoingEffect:: SET", tableName, ongoingEffectid, ongoingEffect ~= nil)
		local UploadOngoingEffect = function()

			--make sure all the mods inherit the ongoingEffect's description and name.
			for i,mod in ipairs(ongoingEffect.modifiers) do
                if mod.name == nil or mod.name == "" then
				    mod.name = ongoingEffect.name
                end
                if mod.description == nil or mod.description == "" then
				    mod.description = ongoingEffect.description
                end
			end
			dmhub.SetAndUploadTableItem(tableName, ongoingEffect)
		end

		local children = {}

        if devmode() then
            --the id of the ongoing effect.
            children[#children+1] = gui.Panel{
                classes = {'formPanel'},
                gui.Label{
                    text = 'ID:',
                    valign = 'center',
                    minWidth = 240,
                },
                gui.Input{
                    text = ongoingEffect.id,
                    editable = false,
                },
            }
        end

		--the name of the ongoingEffect.
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = 'Name:',
				valign = 'center',
				minWidth = 100,
			},
			gui.Input{
				text = ongoingEffect.name,
				change = function(element)
					ongoingEffect.name = trim(element.text)
					UploadOngoingEffect()
				end,
			},

			destroy = function(element)
				--just make it so when we leave this we upload the ongoingEffect.
				--this takes care of modifiers or whatnot changing things causing the ongoingEffect to upload.
				if dmhub.ToJson(ongoingEffect) ~= json then
					UploadOngoingEffect()
				end
			end,
		}

		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = "Description:",
				valign = 'top',
				minWidth = 100,
			},

			gui.Input{
				text = ongoingEffect.description,
				textAlignment = 'topleft',
				placeholderText = "Enter Ongoing Effect Description...",
				multiline = true,
				height = 'auto',
				minHeight = 60,
				fontSize = 14,
                characterLimit = 8192,
				change = function(element)
					ongoingEffect.description = element.text
					UploadOngoingEffect()
				end,
			},
		}

		local conditionOptions = {
			{
				id = "none",
				text = "None",
			}
		}

		local conditionsTable = dmhub.GetTable(CharacterCondition.tableName) or {}
		for k,cond in pairs(conditionsTable) do
			if not cond:try_get("hidden", false) then
				conditionOptions[#conditionOptions+1] = {
					id = k,
					text = cond.name,
				}
			end
		end

		table.sort(conditionOptions, function(a,b) return a.text < b.text end)

        ongoingEffect:FillEditingFields(children)

		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = "Condition:",
				valign = 'center',
				minWidth = 100,
			},

			gui.Dropdown{
				options = conditionOptions,
				idChosen = ongoingEffect.condition,
				change = function(element)
					ongoingEffect.condition = element.idChosen
					local newCondition = conditionsTable[element.idChosen]
					if newCondition ~= nil then
						ongoingEffect.iconid = newCondition.iconid
						ongoingEffect.display = DeepCopy(newCondition.display)
					end

					UploadOngoingEffect()
					SetOngoingEffect(ongoingEffectid)
				end,
			},
		}


        if ongoingEffect.allowEditingDisplayInfo then
            children[#children+1] = gui.Check{
                text = "Hidden",
                halign = "left",
                value = not ongoingEffect.statusEffect,
                hover = gui.Tooltip("If this is checked, the ongoing effect will not appear on the token or be available in menus."),
                change = function(element)
                    ongoingEffect.statusEffect = not element.value
                    UploadOngoingEffect()
                    SetOngoingEffect(ongoingEffectid)
                end,
            }

            if ongoingEffect.statusEffect then

                children[#children+1] = gui.Check{
                    text = "Hidden on token",
                    halign = "left",
                    value = ongoingEffect.hiddenOnToken,
                    change = function(element)
                        ongoingEffect.hiddenOnToken = element.value
                        UploadOngoingEffect()
                        SetOngoingEffect(ongoingEffectid)
                    end,
                }

                children[#children+1] = gui.Check{
                    text = "Hidden from enemies",
                    halign = "left",
                    value = ongoingEffect.hiddenFromEnemies,
                    change = function(element)
                        ongoingEffect.hiddenFromEnemies = element.value
                        UploadOngoingEffect()
                        SetOngoingEffect(ongoingEffectid)
                    end,
                }


                local associationOptions = {}
                local associationRules = ongoingEffect:get_or_add("association", {})

                for i,entry in ipairs(associationRules) do
                    local info = dmhub.GetTable(entry.table)[entry.id]
                    if info ~= nil then
                        children[#children+1] = gui.Panel{
                            flow = "horizontal",
                            width = 380,
                            height = 20,
                            gui.Label{
                                text = info.name,
                                width = 220,
                                fontSize = 18,
                                textAlignment = "left",
                                halign = "left",
                            },

                            gui.Dropdown{
                                fontSize = 14,
                                width = 100,
                                height = 18,
                                idChosen = entry.type or "self",
                                options = {
                                    {
                                        id = "self",
                                        text = "Self",
                                    },
                                    {
                                        id = "ally",
                                        text = "Ally",
                                    },
                                    {
                                        id = "any",
                                        text = "Any",
                                    },
                                },

                                change = function(element)
                                    entry.type = element.idChosen
                                    UploadOngoingEffect()
                                end,
                            },

                            gui.DeleteItemButton{
                                halign = "right",
                                valign = "center",
                                width = 16,
                                height = 16,
                                click = function(element)
                                    table.remove(associationRules, i)
                                    UploadOngoingEffect()
                                    SetOngoingEffect(ongoingEffectid)
                                end,
                            },
                        }
                    end
                end

                for key,value in unhidden_pairs(dmhub.GetTable(Race.tableName)) do
                    associationOptions[#associationOptions+1] = {
                        id = key,
                        text = string.format("%s: %s", GameSystem.RaceName, value.name),
                        table = Race.tableName,
                    }
                end

                children[#children+1] = gui.Panel{
                    classes = {'formPanel'},
                    gui.Label{
                        text = 'Association:',
                        valign = "center",
                        minWidth = 200,
                        width = 'auto',
                        height = 'auto',
                    },
                    gui.Dropdown{
                        options = associationOptions,
                        textDefault = "Add Association...",
                        hasSearch = true,
                        width = 300,
                        height = 30,
                        fontSize = 16,
                        change = function(element)
                            if element.idChosen ~= nil then
                                local option = nil
                                for _,entry in ipairs(associationOptions) do
                                    if entry.id == element.idChosen then
                                        option = entry
                                    end
                                end
                                associationRules[#associationRules+1] = {
                                    id = option.id,
                                    table = option.table,
                                }
                                UploadOngoingEffect()
                                SetOngoingEffect(ongoingEffectid)
                            end
                        end,
                    },

                }
            end

            --the ongoingEffect's icon.
            local iconEditor = gui.IconEditor{
                library = "ongoingEffects",
                bgcolor = ongoingEffect.display['bgcolor'] or '#ffffffff',
                margin = 20,
                width = 64,
                height = 64,
                halign = "left",
                value = ongoingEffect.iconid,
                change = function(element)
                    ongoingEffect.iconid = element.value
                    UploadOngoingEffect()
                end,
                create = function(element)
                    element.selfStyle.hueshift = ongoingEffect.display['hueshift']
                    element.selfStyle.saturation = ongoingEffect.display['saturation']
                    element.selfStyle.brightness = ongoingEffect.display['brightness']
                end,
            }

            local iconColorPicker = gui.ColorPicker{
                value = ongoingEffect.display['bgcolor'] or '#ffffffff',
                hmargin = 8,
                width = 24,
                height = 24,
                valign = 'center',
                borderWidth = 2,
                borderColor = '#999999ff',

                confirm = function(element)
                    iconEditor.selfStyle.bgcolor = element.value
                    ongoingEffect.display['bgcolor'] = element.value
                end,

                change = function(element)
                    iconEditor.selfStyle.bgcolor = element.value
                end,
            }

            local iconPanel = gui.Panel{
                width = 'auto',
                height = 'auto',
                flow = 'horizontal',
                halign = 'left',
                iconEditor,
                iconColorPicker,
            }

            children[#children+1] = iconPanel

            children[#children+1] = gui.Panel{
                classes = {'formPanel'},
                gui.Label{
                    text = 'Blend:',
                    valign = "center",
                    minWidth = 200,
                    width = 'auto',
                    height = 'auto',
                },
                gui.Dropdown{
                    options = { { id = "normal", text = "Normal" }, { id = "add", text = "Add" }},
                    idChosen = ongoingEffect.display.blend or 'normal',
                    width = 200,
                    height = 40,
                    fontSize = 20,
                    change = function(element)
                        ongoingEffect.display = dmhub.DeepCopy(ongoingEffect.display)
                        ongoingEffect.display.blend = cond(element.idChosen == 'add', 'add', nil)
                        iconEditor:FireEvent('create')
                        UploadOngoingEffect()
                    end,
                },
            }

            local CreateDisplaySlider = function(options)
                return gui.Slider{
                    style = {
                        height = 30,
                        width = 200,
                        fontSize = 14,
                    },

                    sliderWidth = 140,
                    labelWidth = 50,
                    value = ongoingEffect.display[options.attr],
                    minValue = options.minValue,
                    maxValue = options.maxValue,

                    formatFunction = function(num)
                        return string.format('%d%%', round(num*100))
                    end,

                    deformatFunction = function(num)
                        return num*0.01
                    end,

                    events = {
                        change = function(element)
                            ongoingEffect.display = dmhub.DeepCopy(ongoingEffect.display)
                            ongoingEffect.display[options.attr] = element.value
                            iconEditor:FireEvent('create')
                        end,
                        confirm = function(element)
                            UploadOngoingEffect()
                        end,
                    }
                }
            end

            local sliders = {}
            sliders[#sliders+1] = CreateDisplaySlider{ attr = 'hueshift', minValue = 0, maxValue = 1, }
            sliders[#sliders+1] = CreateDisplaySlider{ attr = 'saturation', minValue = 0, maxValue = 2, }
            sliders[#sliders+1] = CreateDisplaySlider{ attr = 'brightness', minValue = 0, maxValue = 2, }

            children[#children+1] = gui.Panel{
                classes = {'formPanel'},
                gui.Label{
                    text = 'Hue:',
                    valign = "center",
                    minWidth = 200,
                    width = 'auto',
                    height = 'auto',
                },
                sliders[1],
            }

            children[#children+1] = gui.Panel{
                classes = {'formPanel'},
                gui.Label{
                    text = 'Saturation:',
                    valign = "center",
                    minWidth = 200,
                    width = 'auto',
                    height = 'auto',
                },
                sliders[2],
            }

            children[#children+1] = gui.Panel{
                classes = {'formPanel'},
                gui.Label{
                    text = 'Brightness:',
                    valign = "center",
                    minWidth = 200,
                    width = 'auto',
                    height = 'auto',
                },
                sliders[3],
            }

            local emojiOptions = {
                {
                    id = "none",
                    text = "No Emoji",
                }
            }

            for k,emoji in pairs(assets.emojiTable) do
                if (not emoji.hidden) and emoji.emojiType == 'Status' and emoji.looping then
                    emojiOptions[#emojiOptions+1] = {
                        id = k,
                        text = emoji.description,
                    }
                end
            end

            children[#children+1] = gui.Panel{
                classes = {'formPanel'},
                gui.Label{
                    text = 'Emoji:',
                    valign = "center",
                    minWidth = 200,
                    width = 'auto',
                    height = 'auto',
                },
                gui.Dropdown{
                    classes = "formDropdown",
                    options = emojiOptions,
                    idChosen = ongoingEffect.emoji,
                    change = function(element)
                        ongoingEffect.emoji = element.idChosen
                        UploadOngoingEffect()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    text = "Caster Tracking:",
                    valign = "center",
                    minWidth = 200,
                    width = 'auto',
                    height = 'auto',
                },
                gui.Dropdown{
                    classes = {"formDropdown"},
                    options = CharacterOngoingEffect.CasterTrackingOptions,
                    idChosen = ongoingEffect.casterTracking,
                    change = function(element)
                        ongoingEffect.casterTracking = element.idChosen
                        UploadOngoingEffect()
                        element.parent.parent:FireEventTree("refreshCasterTracking")
                    end,
                }
            }

            children[#children+1] = gui.Check{
                classes = {cond(ongoingEffect.casterTracking == "bond", nil, "collapsed-anim")},
                text = "Share Recoveries",
                halign = "left",
                value = ongoingEffect:try_get("recoverySharing", false),
                refreshCasterTracking = function(element)
                    element:SetClass("collapsed-anim", ongoingEffect.casterTracking ~= "bond")
                end,
                change = function(element)
                    ongoingEffect.recoverySharing = element.value
                    UploadOngoingEffect()
                end,
            }

            children[#children+1] = gui.Check{
                text = "Stackable",
                halign = "left",
                value = ongoingEffect.stackable,
                change = function(element)
                    ongoingEffect.stackable = element.value
                    UploadOngoingEffect()
                    element.parent:FireEventTree("recalculateStacks")
                end,
            }

            children[#children+1] = gui.Check{
                classes = {cond(ongoingEffect.stackable, nil, "collapsed-anim")},
                text = "Clear Stacks When Applying",
                halign = "left",
                value = ongoingEffect.clearStacksWhenApplying,
                recalculateStacks = function(element)
                    element:SetClass("collapsed-anim", not ongoingEffect.stackable)
                end,
                change = function(element)
                    ongoingEffect.clearStacksWhenApplying = element.value
                    UploadOngoingEffect()
                end,
            }

            if ongoingEffect.condition ~= "none" then
                local conditionInfo = conditionsTable[ongoingEffect.condition]
                if conditionInfo ~= nil and conditionInfo:try_get("maxInstancesFormula", "") ~= "" then
                    children[#children+1] = gui.Check{
                        text = "Counts Toward Instance Limit",
                        halign = "left",
                        value = ongoingEffect.countsTowardInstanceLimit,
                        change = function(element)
                            ongoingEffect.countsTowardInstanceLimit = element.value
                            UploadOngoingEffect()
                        end,
                    }
                end
            end
        end --end allow editing display info

		local resourceOptions = DeepCopy(CharacterResource.GetDropdownOptions("Actions", true))
		resourceOptions[#resourceOptions+1] = {
			id = "halfmove",
			text = "Half Movement",
		}
		resourceOptions[#resourceOptions+1] = {
			id = "fullmove",
			text = "Full Movement",
		}

        if ongoingEffect.allowEditingDisplayInfo then
            local endActionTypePanel = gui.Panel{
                classes = {'formPanel', cond(ongoingEffect.canEndWithAction, nil, 'collapsed-anim')},
                refresh = function(element)
                    element:SetClass('collapsed-anim', not ongoingEffect.canEndWithAction)
                end,
                gui.Label{
                    text = 'End Action:',
                    valign = "center",
                    minWidth = 200,
                    width = 'auto',
                    height = 'auto',
                },

                gui.Dropdown{
                    classes = {"formDropdown"},
                    options = resourceOptions,
                    idChosen = ongoingEffect.endActionType,
                    change = function(element)
                        ongoingEffect.endActionType = element.idChosen
                        UploadOngoingEffect()
                    end,
                },
            }

            children[#children+1] = gui.Check{
                text = "Subject can end with an action",
                halign = "left",
                value = ongoingEffect.canEndWithAction,
                change = function(element)
                    ongoingEffect.canEndWithAction = element.value
                    UploadOngoingEffect()

                    endActionTypePanel:FireEvent("refresh")
                end,
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    text = "End on Trigger:",
                    valign = "center",
                    minWidth = 200,
                    width = "auto",
                    height = "auto",
                },
                gui.Dropdown{
                    options = TriggeredAbility.GetTriggerDropdownOptions(true),
                    idChosen = ongoingEffect.endTrigger,
                    change = function(element)
                        ongoingEffect.endTrigger = element.idChosen
                        UploadOngoingEffect()
                    end,
                },
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    text = "Sustain:",
                    valign = "center",
                    minWidth = 199,
                    width = 'auto',
                    height = 'auto',
                },
                gui.GoblinScriptInput{
                    classes = {"formInput"},
                    value = ongoingEffect.sustainFormula,
                    change = function(element)
                        ongoingEffect.sustainFormula = element.value
                        UploadOngoingEffect()
                    end,
                    documentation = {
                        help = string.format("This GoblinScript is used to calculate if the ongoing effect continues. If it results in a 0 or false value the ongoing effect will end."),
                        output = "true or false",
                        examples = {
                            {
                                script = "Hitpoints > 5",
                                text = "The ongoing effect will continue as long as the creature's hitpoints are greater than 5. It will end as soon as the creature's hitpoints drop to 5 or lower.",
                            },
                        },
                        subject = creature.helpSymbols,
                        subjectDescription = "The creature using the ability",
                    },
                },
            }

            children[#children+1] = endActionTypePanel
        end


		local modifiersPanel = gui.Panel{
			classes = {'modsPanel'},
			styles = {
				{
					halign = "left",
				},
				{
					classes = {'modsPanel'},
					width = 800,
					height = "auto",
					halign = 'left',
				},
				{
					classes = {'namePanel'},
					collapsed = 1,
				},
				{
					classes = {'sourcePanel'},
					collapsed = 1,
				},
				{
					classes = {'descriptionPanel'},
					collapsed = 1,
				},
			},

			ongoingEffect:EditorPanel{
				noscroll = true,
				height = "auto",
				modifierRefreshed = function(element)
					UploadOngoingEffect()
				end,
			},
		}

		children[#children+1] = modifiersPanel

		ongoingEffectPanel.children = children


	end

	ongoingEffectPanel.data.SetOngoingEffect = SetOngoingEffect
	if condid then
		SetOngoingEffect(condid)
	end
	return ongoingEffectPanel
	
end

function CharacterOngoingEffect.CreateOngoingEffectEditorDialog(options)
	local ongoingEffectid = options.ongoingEffectid
	local ongoingEffectTable = dmhub.GetTable("characterOngoingEffects")
	local ongoingEffect = ongoingEffectTable[ongoingEffectid]

	local dialogWidth = 1200
	local dialogHeight = 980

	local resultPanel = nil


	local mainFormPanel = gui.Panel{
		style = {
			bgcolor = 'white',
			pad = 0,
			margin = 0,
			width = 1060,
			height = 840,
		},
		vscroll = true,

		CharacterOngoingEffect.CreateEditor(ongoingEffectid),
	}

	local newItem = nil

	local closePanel = 
		gui.Panel{
			style = {
				valign = 'bottom',
				flow = 'horizontal',
				height = 60,
				width = '100%',
				fontSize = '60%',
				vmargin = 0,
			},

			children = {
				gui.PrettyButton{
					text = 'Close',
					style = {
						height = 60,
						width = 160,
						fontSize = 44,
						bgcolor = 'white',
					},
					events = {
						click = function(element)
							dmhub.SetAndUploadTableItem("characterOngoingEffects", ongoingEffect)
							resultPanel:DestroySelf()
						end,
					},
				},
			},
		}

	local titleLabel = gui.Label{
		text = "Edit Ongoing Effect",
		valign = 'top',
		halign = 'center',
		width = 'auto',
		height = 'auto',
		color = 'white',
		fontSize = 28,
	}

	resultPanel = gui.Panel{
		floating = true,
		styles = {
			Styles.Panel,
			{
				bgcolor = 'white',
				width = dialogWidth,
				height = dialogHeight,
				halign = 'center',
				valign = 'center',
			},
		},

		classes = {"framedPanel"},

		captureEscape = true,
		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
		escape = function(element)
			dmhub.SetAndUploadTableItem("characterOngoingEffects", ongoingEffect)
			resultPanel:DestroySelf()
		end,

		children = {

			gui.Panel{
				id = 'content',
				style = {
					halign = 'center',
					valign = 'center',
					width = '94%',
					height = '94%',
					flow = 'vertical',
				},
				children = {
					titleLabel,
					mainFormPanel,
					closePanel,

				},
			},
		},
	}

	return resultPanel
end
