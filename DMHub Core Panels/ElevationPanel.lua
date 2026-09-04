local mod = dmhub.GetModLoading()

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

local CreateHeightmapEditor

local g_heightSetting = setting{
    id = "heightmap:height",
    description = "Height",
    editor = "slider",
    format = "F1",
    min = -10,
    max = 10,
    default = 0,
    storage = "transient",
}

local g_gradientSetting = setting{
    id = "heightmap:gradient",
    description = "Gradient",
    editor = "dropdown",
    storage = "transient",
    default = "flat",
    enum = {
        {
            value = "flat",
            text = "Flat",
        },
        {
            value = "slope",
            text = "Slope",
        },
    },

    monitorVisible = {"heightmaptool"},
    visible = function()
        local tool = dmhub.GetSettingValue("heightmaptool")
        return tool == "rectangle" or tool == "oval" or tool == "shape"
    end,
}

local g_blendSetting = setting{
    id = "heightmap:blend",
    description = "BlendDistance",
    editor = "slider",
    format = "F1",
    min = 0,
    max = 1,
    default = 0,
    storage = "transient",
    monitorVisible = {"heightmaptool"},
    visible = function()
        local tool = dmhub.GetSettingValue("heightmaptool")
        return tool == "rectangle" or tool == "oval" or tool == "shape"
    end,
}

local g_opacitySetting = setting{
    id = "heightmap:opacity",
    description = "Strength",
    editor = "slider",
    format = "F1",
    min = 0,
    max = 1,
    default = 1,
    storage = "transient",
    monitorVisible = {"heightmaptool"},
    visible = function()
        local tool = dmhub.GetSettingValue("heightmaptool")
        return tool == "rectangle" or tool == "oval" or tool == "shape"
    end,
}

local g_shadingSetting = setting{
    id = "heightmap:shading",
    description = "Use Shadows",
    editor = "check",
    default = true,
    storage = "transient",
}

local g_overlayOpacitySetting = setting{
    id = "heightmap:opacitysetting",
    description = "Overlay Opacity",
    editor = "slider",
    default = 0.5,
    min = 0,
    max = 1,
    storage = "preference",
}

local g_overlayTypeSetting = setting{
    id = "heightmap:overlaytype",
    description = "Overlay",
    editor = "dropdown",
    default = "overlay",
    storage = "preference",
    enum = {
        {
            value = "none",
            text = "None",
        },
        {
            value = "overlay",
            text = "Overlay",
        },
        {
            value = "labels",
            text = "Labeled Overlay",
        },
    },
}

if dmhub.patronTier > 0 then
    DockablePanel.Register{
        name = "Elevation Editor",
	    icon = "icons/standard/Icon_App_ElevationEditor.png",
        vscroll = true,
        dmonly = true,
        minHeight = 200,
        folder = "Map Editing",
        stickyFocus = true,
        --A press anywhere on the panel -- its background, its title bar --
        --re-claims focus and re-arms. Every other map-mode panel (Map Markup,
        --Measuring Tool, Terrain, Building, Objects) declares this; the
        --Elevation Editor was the one that did not, so once something else
        --took focus the ONLY way back was pressing one of its own controls --
        --and doing that writes a setting, which was itself what triggered the
        --steal. Report W9BJHDAQ.
        focusOnClick = true,
        content = function()
            track("panel_open", {
                panel = "Elevation Editor",
                dailyLimit = 30,
            })
            return CreateHeightmapEditor()
        end,
    }
end

local g_heightmapEditor = nil

--------------------------------------------------------------------------
--Arming.
--
--Height editing used to be gated PURELY on this panel holding GUI focus,
--which made it the most fragile map editor in the app: any panel anywhere
--that called gui.SetFocus turned the tool -- and the elevation overlay --
--off, with no visible cause and no way back except clicking a control here
--(which writes a setting, which was the very thing provoking the steal).
--Report W9BJHDAQ is exactly that: the Whiteboard's monitor handler grabbed
--focus after every settings write in the session, so the overlay "popped up
--for a brief moment before closing" and not one height op ever landed.
--
--Arming is now EXPLICIT, the same model Map Markup moved to: showing the
--panel or clicking it arms, hiding it or Escape disarms, and losing focus
--means nothing. Focus is still taken so keyboard routing and the host's
--focus highlight keep working -- it just is not the state any more.
local g_heightmapArmed = false

--Focus (and now arming) is not proof the editor is on SCREEN. A dock that is
--slid away carries the "offscreen" class and a panel behind another tab (or
--minimized) carries "collapsed"; either way the children stay alive and are
--invisible. A latch must not outlive visibility -- height editing pre-empts
--building operations in the engine (GameController.FinishRect /
--FinishEllipse), so an invisible armed panel would silently hijack another
--editor's strokes. Same check Objects.lua makes for object editing mode.
local function HeightmapEditorOnScreen(element)
    local p = element
    while p ~= nil do
        if p:HasClass("offscreen") or p:HasClass("collapsed") then
            return false
        end
        p = p.parent
    end

    return true
end

local function HeightmapArmed()
    if g_heightmapArmed == false then
        return false
    end

    if g_heightmapEditor == nil or (not g_heightmapEditor.valid) or g_heightmapEditor.parent == nil then
        return false
    end

    return HeightmapEditorOnScreen(g_heightmapEditor)
end

local function SetHeightmapArmed(on)
    g_heightmapArmed = on == true
end

CreateHeightmapEditor = function()
    local resultPanel

    -- Every form-style setting in this panel uses the stacked (label-above-
    -- control) layout. Pull the option once so each CreateSettingsEditor call
    -- stays terse.
    local stackedOpts = {stacked = true}

    resultPanel = gui.Panel{
        flow = "vertical",
        height = "auto",
        width = "80%",

        styles = ThemeEngine.GetStyles(),

        --The host (dock container or rail window) fires this on a
        --user-initiated OPEN of the panel and when a press lands anywhere on
        --it that its own controls did not handle -- background, title bar. It
        --has already put focus here. Opening or clicking the panel is asking
        --to use it, so it ARMS. Requires focusOnClick on the registration.
        panelFocused = function(element)
            SetHeightmapArmed(true)
        end,

        --Switching to this tab is asking to edit elevation.
        showpanel = function(element)
            SetHeightmapArmed(true)
            if not gui.ChildHasFocus(element) then
                gui.SetFocus(element)
            end
        end,

        --Hiding it DOES disarm: a tool you cannot see must not keep eating
        --map clicks (and height editing pre-empts building strokes).
        hidepanel = function(element)
            SetHeightmapArmed(false)
            if gui.ChildHasFocus(element) then
                gui.SetFocus(nil)
            end
        end,

        --ESCAPE, first refusal. The host window offers the press to its
        --active panel before closing itself: while a tool is live, Escape
        --means "put it down", and claiming the press is what stops the same
        --keystroke also closing the window. Disarmed, we do not claim it.
        --Focus goes with the tool -- both hosts skip the panelFocused nudge
        --while focus is already here (ClaimTabFocus / FocusPanelContent guard
        --on it), so keeping focus would mean the next click does NOT re-arm.
        panelEscape = function(element, claim)
            if not HeightmapArmed() then
                return
            end

            SetHeightmapArmed(false)

            if gui.ChildHasFocus(element) then
                gui.SetFocus(nil)
            end

            if claim ~= nil then
                claim.claimed = true
            end
        end,

        --The panel going away disarms; the latch must never outlive it.
        destroy = function(element)
            if g_heightmapEditor == element then
                SetHeightmapArmed(false)
            end
        end,

        --The dockablePanel ancestor can be nil: panel content can be hosted
        --outside the dock (the document system's PanelDocument bridge), and
        --focus events can fire while detached. Guard like Objects.lua does.
        childfocus = function(element)
            local dockPanel = element:FindParentWithClass("dockablePanel")
            if dockPanel ~= nil then
                dockPanel:SetClass("highlightPanel", true)
            end
        end,

        childdefocus = function(element)
            local dockPanel = element:FindParentWithClass("dockablePanel")
            if dockPanel ~= nil then
                dockPanel:SetClass("highlightPanel", false)
            end
        end,

        CreateSettingsEditor("heightmaptool"),

        --brush editor.
        gui.Panel{
            classes = {cond(dmhub.GetSettingValue("heightmaptool") ~= 'brush', 'collapsed')},
            width = "auto",
            height = "auto",
            monitor = "heightmaptool",
            events = {
                monitor = function(element)
                    element:SetClass("collapsed", dmhub.GetSettingValue("heightmaptool") ~= 'brush')
                end,
            },
            mod.shared.BrushEditorPanel("heightmapbrush"),
        },

        CreateSettingsEditor("heightmap:height", stackedOpts),
        CreateSettingsEditor("heightmap:blend", stackedOpts),
        CreateSettingsEditor("heightmap:opacity", stackedOpts),
        CreateSettingsEditor("heightmap:gradient", stackedOpts),
        (function()
            local function slopeHintVisible()
                local tool = dmhub.GetSettingValue("heightmaptool")
                local toolUsesGradient = tool == "rectangle" or tool == "oval" or tool == "shape"
                return toolUsesGradient and g_gradientSetting:Get() == "slope"
            end
            return gui.Label{
                classes = {"fgMuted", cond(not slopeHintVisible(), "collapsed")},
                text = "Right-click while drawing to change direction",
                width = "90%",
                height = "auto",
                halign = "left",
                textAlignment = "center",
                fontSize = 12,
                italics = true,
                vmargin = 0,
                multimonitor = {"heightmap:gradient", "heightmaptool"},
                monitor = function(element)
                    element:SetClass("collapsed", not slopeHintVisible())
                end,
            }
        end)(),
        CreateSettingsEditor("heightmap:overlaytype", stackedOpts),
        CreateSettingsEditor("heightmap:opacitysetting", stackedOpts),

    }

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    g_heightmapEditor = resultPanel

    --A fresh instance arrives DISARMED. The latch is file-scope and outlives
    --any one panel, so without this a panel rebuilt while the old one was
    --armed would come up already live -- and a fresh dock open fires no
    --showpanel/panelFocused to correct it. Matches what focus-gating used to
    --give us (a newly built panel has no focus either).
    SetHeightmapArmed(false)

    return resultPanel
end


dmhub.GetHeightEditingInfo = function()
    --Armed, not focused. See the arming block above (report W9BJHDAQ).
    if not HeightmapArmed() then
        return nil
    end

    return {
        height = g_heightSetting:Get(),
        directional = g_gradientSetting:Get() == "slope",
        opacity = g_opacitySetting:Get(),
        blend = g_blendSetting:Get(),
    }
end

dmhub.SelectHeight = function(height)
    dmhub.SetSettingValue("heightmap:height", height)
end