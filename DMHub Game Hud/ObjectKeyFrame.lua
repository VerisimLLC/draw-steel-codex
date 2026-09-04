local mod = dmhub.GetModLoading()

RegisterGameType("KeyFrameComponent")

dmhub.CreateKeyFrameComponent = function()
    return KeyFrameComponent.new()
end

function KeyFrameComponent.CreatePropertiesEditor(component)
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        styles = {
            Styles.Form,
            {
                priority = 10,
                wrap = false,
            },
            {
                selectors = {"formPanel"},
                flow = "horizontal",
                width = "100%",
                height = 24,
                priority = 5,
                wrap = false,
            },
            {
                selectors = {"formLabel"},
                halign = "left",
                fontSize = 14,
                width = 80,
                minWidth = 80,
                priority = 5,
            },
            {
                selectors = {"formLabel", "unchanged"},
                color = "#bbbbbb",
                italics = true,
            },
            {
                selectors = {"formInput"},
                halign = "left",
                width = 100,
                priority = 5,
                fontSize = 14,
            },
        },

		monitorGame = "/mapFloors",
		refreshGame = function(element)
            element:FireEvent("create")
		end,

        create = function(element)

            local children = {}

            local frames = component.keyFrames
            for i,frame in ipairs(frames) do
                local deltas = frame.deltas
                local numChanges = 0
                for _,delta in ipairs(deltas) do
                    if delta.changed then
                        numChanges = numChanges + 1
                    end
                end

                local header = nil

                if i > 1 then

                    header = gui.Panel{
                        classes = {"formPanel"},

                        gui.Label{
                            classes = {"formLabel"},
                            text = "Name:",
                        },

                        gui.Input{
                            classes = {"formInput"},
                            text = frame.name,
                            change = function(element)
                                frame.name = element.text
                            end,
                        },

                        gui.Button{
                            classes = {"deleteButton", "sizeXs"},
                            halign = "right",
                            click = function(element)
                                component:DeleteKeyFrame(i)

                            end,
                        }
                    }
                else
                    header = gui.Panel{
                        classes = {"formPanel"},
                        gui.Label{
                            classes = {"formLabel"},
                            text = "Reset",
                        },

                        gui.Button{
                            width = 60,
                            height = 16,
                            fontSize = 12,
                            halign = "right",
                            text = "Recreate",
                            click = function(element)
                                component:RecreateResetState()
                            end,
                        }
                    }
                end


                children[#children+1] = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "vertical",


                    header,

                    gui.Panel{
                        classes = {"formPanel"},
                        gui.Label{
                            classes = {"formLabel"},
                            text = "Anim. Time:",
                        },

                        gui.Input{
                            classes = {"formInput"},
                            characterLimit = 8,
                            text = string.format("%0.2f", frame.animDuration),
                            change = function(element)
                                local n = tonumber(element.text)
                                if n ~= nil then
                                    frame.animDuration = n
                                end
                                element.text = string.format("%0.2f", frame.animDuration)
                            end,
                        }
                    },

                    gui.Panel{
                        flow = "vertical",
                        width = "100%",
                        height = "auto",
                        gui.Panel{
                            classes = {"formPanel"},
                            gui.Panel{
                                styles = gui.TriangleStyles,
				                bgimage = 'panels/triangle.png',
                                classes = {"triangle"},
                                width = 8,
                                height = 8,
                                click = function(element)
                                    element:SetClass("expanded", not element:HasClass("expanded"))
                                    element.parent.parent:FireEventTree("expanded", element:HasClass("expanded"))
                                end,
                            },
                            gui.Label{
                                classes = {"formLabel"},
                                text = string.format("Changes: %d", numChanges),
                            },

                        },

                        expanded = function(element, val)
                            local children = {element.children[1]}

                            if val then
                                children[#children+1] = gui.Check{
                                    text = "Show All",
                                    value = false,
                                    change = function(element)
                                        element.parent:FireEventTree("showall", element.value)
                                    end,
                                }
                                for _,delta in ipairs(deltas) do
                                    local items = {}
                                    items[#items+1] = gui.Label{
                                        classes = {"formLabel", cond(delta.changed, nil, "unchanged")},
                                        fontSize = 14,
                                        width = 100,
                                        height = "auto",
                                        text = string.format("%s: %s", delta.component, delta.name),
                                    }

                                    if type(delta.value) == "string" and string.starts_with(delta.value, "#") and type(delta.reference) == "string" then
                                        if delta.changed then
                                            items[#items+1] = gui.Panel{
                                                bgimage = "panels/square.png",
                                                width = 12,
                                                height = 12,
                                                bgcolor = delta.reference,
                                                borderWidth = 1,
                                                borderColor = "white",
                                                halign = "left",
                                            }

                                            items[#items+1] = gui.Label{
                                                classes = {"formLabel"},
                                                valign = "center",
                                                halign = "left",
                                                width = "auto",
                                                height = "auto",
                                                minWidth = 0,
                                                fontSize = 14,
                                                text = "->",
                                            }
                                        end

                                        --colors
                                        items[#items+1] = gui.Panel{
                                            bgimage = "panels/square.png",
                                            width = 12,
                                            height = 12,
                                            halign = "left",
                                            bgcolor = delta.value,
                                            borderWidth = 1,
                                            borderColor = "white",
                                        }

                                    else
                                        local text
                                        if delta.changed then
                                            text = string.format("%s -> %s", delta.reference, delta.value)
                                        else
                                            text = delta.reference
                                        end

                                        items[#items+1] = gui.Label{
                                            classes = {"formLabel", cond(delta.changed, nil, "unchanged")},
                                            fontSize = 14,
                                            halign = "left",
                                            lmargin = 0,
                                            width = "auto",
                                            height = "auto",
                                            text = text,
                                        }
                                    end

                                    children[#children+1] = gui.Panel{
                                        classes = {"formPanel", cond(delta.changed, nil, "collapsed")},
                                        width = "100%",
                                        height = "auto",
                                        flow = "horizontal",
                                        showall = function(element, val)
                                            if val then
                                                element:SetClass("collapsed", false)
                                            else
                                                element:SetClass("collapsed", not delta.changed)
                                            end
                                        end,
                                        children = items,
                                    }
                                end

                            end

                            element.children = children

                        end,


                    },

                    gui.Button{
                        halign = "right",
                        text = "Restore",
                        click = function(element)
                            component:RestoreKeyFrame(i)
                        end,
                    }
                }
            end

            element.children = children
        end,
    }
end
