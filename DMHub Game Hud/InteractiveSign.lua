local mod = dmhub.GetModLoading()


RegisterGameType("SignInteractive", "Interactive")

SignInteractive.id = "Sign"
SignInteractive.text = "Sign"

Interactive.Register(SignInteractive)

function SignInteractive.Create()
    return SignInteractive.new{}
end

SignInteractive.displayText = "This is a sign"

function SignInteractive:Interact(controller, token)
    return gui.Label{
        gui.Button{
            classes = {"closeButton"},
            halign = "right",
            valign = "top",
            floating = true,
            click = function(element)
                element.parent:DestroySelf()
            end,
        },
        halign = "center",
        valign = "center",
        width = 800,
        height = 500,
        text = self.displayText,
        bgimage = "panels/square.png",
        bgcolor = "black",
        color = "white",
        fontSize = 40,
        textAlignment = "center",
        captureEscape = true,
        escape = function(element)
            element:DestroySelf()
        end,
    }
end


function SignInteractive:Edit(controller)
    return gui.Panel{
        width = 800,
        height = 500,
        bgimage = "panels/square.png",
        bgcolor = "black",
        halign = "center",
        valign = "center",
        flow = "vertical",
        captureEscape = true,
        escapePriority = EscapePriority.DMHUB_POPUP,
        escape = function(element)
            element:DestroySelf()
        end,

        gui.Button{
            classes = {"closeButton"},
            halign = "right",
            valign = "top",
            floating = true,
            click = function(element)
                element.parent:FireEvent("escape")
            end,
        },

        gui.Input{
            width = 400,
            height = 40,
            fontSize = 14,
            text = self.displayText,
            change = function(element)
                controller:BeginChanges()
                self.displayText = element.text
                controller:CompleteChanges()
            end,
        }
    }
end

--============================================================================
--Squishy interactive: click feedback for fleshy/soft objects. Interacting
--plays a squelch sound (PlaySoundEvent already reaches every client through
--gameDetails) and a small squash-and-stretch wobble on the object. The wobble
--is a local-only engine effect (obj:PlaySquishAnimation), so it is broadcast
--through the squishfx document below to make every client's copy wobble.
--============================================================================

RegisterGameType("SquishFx")

SquishFx.docid = "squishfx"
--"" not nil: assigning nil to a game-type field is a no-op, so the field
--would not exist and reading it would raise (see CLAUDE.md).
SquishFx.lastNonce = ""

--Find the live object and wobble it. pcall: older engine builds have no
--PlaySquishAnimation, and the feature degrades to sound-only there.
function SquishFx.PlayLocal(floorid, objid, intensity)
    local m = game.currentMap
    if m == nil then
        return
    end
    for _,floor in ipairs(m.floors) do
        if floor.floorid == floorid then
            for id,obj in pairs(floor.objects) do
                if id == objid then
                    pcall(function()
                        obj:PlaySquishAnimation{ intensity = intensity }
                    end)
                    return
                end
            end
        end
    end
end

--Wobble locally right away (instant feedback for the clicker), then write the
--event so every other client's monitor panel replays it. The nonce is what
--distinguishes a fresh event from the one already sitting in the document.
function SquishFx.Broadcast(floorid, objid, intensity)
    SquishFx.PlayLocal(floorid, objid, intensity)

    local doc = mod:GetDocumentSnapshot(SquishFx.docid)
    local nonce = dmhub.GenerateGuid()
    --record the nonce BEFORE CompleteChange: the monitor's refreshGame fires
    --synchronously inside it, and must see this event as already played.
    SquishFx.lastNonce = nonce
    doc:BeginChange()
    doc.data.event = {
        nonce = nonce,
        floorid = floorid,
        objid = objid,
        intensity = intensity,
    }
    doc:CompleteChange("Squish", {undoable = false})
end

--Invisible always-alive monitor panel, mounted by GameHud next to
--FullscreenDisplay. Seeding lastNonce from the current document is what stops
--the event already stored there replaying when a client loads in.
function SquishFx.CreateMonitorPanel()
    local doc = mod:GetDocumentSnapshot(SquishFx.docid)
    if doc.data.event ~= nil then
        SquishFx.lastNonce = doc.data.event.nonce
    end

    return gui.Panel{
        width = 0,
        height = 0,
        monitorGame = doc.path,
        refreshGame = function(element)
            local d = mod:GetDocumentSnapshot(SquishFx.docid)
            local ev = d.data.event
            if ev == nil or ev.nonce == SquishFx.lastNonce then
                return
            end
            SquishFx.lastNonce = ev.nonce
            SquishFx.PlayLocal(ev.floorid, ev.objid, ev.intensity)
        end,
    }
end

RegisterGameType("SquishInteractive", "Interactive")

SquishInteractive.id = "Squish"
SquishInteractive.text = "Squishy"

--the Interactable component's optional panel fields this type uses; the
--object properties panel shows exactly these (see InteractiveContainer.FieldEnabled).
SquishInteractive.panelFields = {
    sound = true,
    soundVolume = true,
    squishIntensity = true,
}

Interactive.Register(SquishInteractive)

function SquishInteractive.Create()
    return SquishInteractive.new{}
end

--Read one of the Interactable component's field values off its reflected
--descriptors. Older engine builds lack the optional fields entirely, so a
--missing descriptor just yields the default.
local function ComponentFieldValue(controller, id, default)
    local result = nil
    pcall(function()
        for _,f in ipairs(controller.fields) do
            if f.id == id then
                result = f.currentValue
                return
            end
        end
    end)
    if result == nil then
        return default
    end
    return result
end

function SquishInteractive:Interact(controller, token)
    local soundid = ComponentFieldValue(controller, "sound", nil)
    if soundid ~= nil and soundid ~= "" then
        local asset = assets.audioTable[soundid]
        if asset ~= nil then
            --networked already: every client hears this, so only the clicker
            --plays it (the squishfx broadcast must NOT also play sounds).
            local volume = tonumber(ComponentFieldValue(controller, "soundVolume", 0.6)) or 0.6
            audio.PlaySoundEvent{ asset = asset, volume = volume }
        end
    end

    local intensity = tonumber(ComponentFieldValue(controller, "squishIntensity", 0.06)) or 0.06
    SquishFx.Broadcast(controller.floorid, controller.objid, intensity)

    --no dialog: returning nil means the interaction is just the effect.
    return nil
end

