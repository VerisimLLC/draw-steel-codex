local mod = dmhub.GetModLoading()

--- @class EventHandlerComponent: GameType
EventHandlerComponent = RegisterGameType("EventHandlerComponent")

dmhub.CreateEventHandlerComponent = function()
    return EventHandlerComponent.new()
end

function EventHandlerComponent.CreatePropertiesEditor(component)
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
                selectors = {"checkbox-label"},
                fontSize = 14,
            }
        },

		monitorGame = "/mapFloors",
		refreshGame = function(element)
            element:FireEvent("create")
		end,

        create = function(element)

            local events = component:GetPossibleEvents()

            local children = {}

            local currentComponent = nil

            for _,event in ipairs(events) do
                if event.componentName ~= currentComponent then
                    currentComponent = event.componentName
                    children[#children+1] =
                        gui.Label{
                            text = currentComponent,
                            fontSize = 16,
                            width = "auto",
                            height = "auto",
                        }
                end
                local entry = component:GetEventEntry(event.eventid)
                children[#children+1] = gui.Panel{

                    flow = "horizontal",
                    width = "100%",
                    height = "auto",
                    gui.Check{
                        text = string.format("%s", event.name),
                        value = entry.exposed,
                        lmargin = 8,
                        change = function(element)
                            component:SetEventEntry(event.eventid, element.value)
                            element.parent:FireEventTree("exposed", element.value)
                        end,
                    },

                    gui.Button{
                        width = 40,
                        height = 16,
                        fontSize = 12,
                        halign = "right",
                        valign = "center",
                        rmargin = 8,
                        text = "Trigger",
                        create =  function(element)
                            element:SetClass("hidden", not entry.exposed)
                        end,
                        exposed = function(element, val)
                            element:SetClass("hidden", not val)
                        end,
                        click = function(element)
                            component:TriggerEvent(event.eventid)
                        end,
                    },
                }

            end

            element.children = children
        end,
    }
end




--Event Trigger
--- @class EventTriggerComponent: GameType
EventTriggerComponent = RegisterGameType("EventTriggerComponent")

dmhub.CreateEventTriggerComponent = function()
    return EventTriggerComponent.new()
end

function EventTriggerComponent.CreatePropertiesEditor(component)
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
                selectors = {"checkbox-label"},
                fontSize = 14,
            }
        },

		monitorGame = "/mapFloors",
		refreshGame = function(element)
            element:FireEvent("create")
		end,

        create = function(element)

            local triggers = component.triggers

            local children = {}

            for _,trigger in ipairs(triggers) do
                children[#children+1] = gui.Check{
                    text = trigger.name,
                    value = trigger.exposed,
                    change = function(element)
                        if element.value then
                            component:ExposeTrigger(trigger.triggerid)
                        else
                            component:HideTrigger(trigger.triggerid)
                        end
                    end,
                }
            end

            element.children = children
        end,
    }
end

--Data Input
--- @class DataInputComponent: GameType
DataInputComponent = RegisterGameType("DataInputComponent")

dmhub.CreateDataInputComponent = function()
    return DataInputComponent.new()
end

function DataInputComponent.CreatePropertiesEditor(component)
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
                selectors = {"checkbox-label"},
                fontSize = 14,
            }
        },

		monitorGame = "/mapFloors",
		refreshGame = function(element)
            element:FireEvent("create")
		end,

        create = function(element)

            local componentid = nil
            local children = {}

            for _,input in ipairs(component.inputs) do
                local id = input.id

                local prefix,postfix = string.match(id, "([^:]+):([^:]+)")
                if prefix ~= nil then

                    if prefix ~= componentid then
                        componentid = prefix
                        local text = componentid
                        if string.starts_with(text, "ObjectComponent") then
                            text = string.sub(text, 16)
                        end
                        
                        text = input.componentName or text
                        children[#children+1] =
                            gui.Label{
                                text = text,
                                fontSize = 16,
                                width = "auto",
                                height = "auto",
                            }
                    end

                    children[#children+1] = gui.Panel{
                        flow = "horizontal",
                        width = "100%",
                        height = "auto",
                        gui.Check{
                            text = postfix,
                            value = input.exposed,
                            change = function(element)
                                component:SetFieldExposed(id, element.value)
                            end,
                        },
                    }
                end
            end

            element.children = children
        end,
    }
end

--Data Output
--- @class DataOutputComponent: GameType
DataOutputComponent = RegisterGameType("DataOutputComponent")

dmhub.CreateDataOutputComponent = function()
    return DataOutputComponent.new()
end


function DataOutputComponent.CreatePropertiesEditor(component)
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
                selectors = {"checkbox-label"},
                fontSize = 14,
            }
        },

		monitorGame = "/mapFloors",
		refreshGame = function(element)
            element:FireEvent("create")
		end,

        create = function(element)

            local componentid = nil
            local children = {}

            printf("OUTPUTS:: READ OUTPUTS...")

            for _,output in ipairs(component.outputs) do
                local id = output.id

                local prefix,postfix = string.match(id, "([^:]+):([^:]+)")
                if prefix ~= nil then

                    if prefix ~= componentid then
                        componentid = prefix
                        local text = componentid
                        if string.starts_with(text, "ObjectComponent") then
                            text = string.sub(text, 16)
                        end
                        children[#children+1] =
                            gui.Label{
                                text = text,
                                fontSize = 16,
                                width = "auto",
                                height = "auto",
                            }
                    end

                    children[#children+1] = gui.Panel{
                        flow = "horizontal",
                        width = "100%",
                        height = "auto",
                        gui.Check{
                            text = postfix,
                            value = output.exposed,
                            change = function(element)
                                component:SetFieldExposed(id, element.value)
                            end,
                        },
                    }
                end
            end

            element.children = children
        end,
    }
end
