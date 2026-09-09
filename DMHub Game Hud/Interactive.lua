local mod = dmhub.GetModLoading()

RegisterGameType("InteractiveContainer")
RegisterGameType("Interactive")

local g_registry = {}

function Interactive.Register(args)
    g_registry[args.id] = args
end

dmhub.CreateObjectInteractive = function()
    return InteractiveContainer.new{


    }
end

function InteractiveContainer.GetTypes()
    local result = {}

    for _,v in pairs(g_registry) do
        result[#result+1] = v
    end

    printf("INTERACTIVE: %d", #result)

    table.sort(result, function(a,b) return a.text < b.text end)
    return result
end

--Which of the Interactable component's optional panel fields (sound,
--soundVolume, squishIntensity) the given type uses. The engine's
--GetFieldDisplayInfo calls this to hide the rest, so each type only shows
--the controls it reads. rawget: reading an undeclared field on a game-type
--class table raises.
function InteractiveContainer.FieldEnabled(id, fieldName)
    local info = g_registry[id]
    if info == nil then
        return false
    end
    local fields = rawget(info, "panelFields")
    if fields == nil then
        return false
    end
    return fields[fieldName] == true
end

function InteractiveContainer:Construct(id)
    local info = g_registry[id]
    if info == nil then
        return
    end

    printf("INTERACTIVE: CONSTRUCT")
    self.object = info.Create()
end

function InteractiveContainer:Interact(interactiveComponent, token)
    printf("INTERACTIVE: INTERACTIVE ")
    if self:has_key("object") == false then
        return
    end

    printf("INTERACTIVE: INTERACTIVE CONTAINER")
    local ui = self.object:Interact(interactiveComponent, token)

    if ui == nil then
        return
    end

    gui.ShowDialog(mod, ui)
end

function InteractiveContainer.Edit(self, interactiveComponent)
    if self:has_key("object") == false then
        return
    end

    local ui = self.object:Edit(interactiveComponent)

    if ui == nil then
        return
    end

    gui.ShowDialog(mod, ui)
end

function Interactive.Create()
    return Interactive.new{}
end

function Interactive:Interact(controller, token)
end

function Interactive:Edit(controller)
end
