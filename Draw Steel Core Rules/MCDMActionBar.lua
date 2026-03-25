local mod = dmhub.GetModLoading()


--make sure when we load this mod the game hud gets rebuilt so it includes our new action bar.
dmhub.RebuildGameHud()


local barScale = 0.95
local standardAspect = 16/9
local actualAspect = dmhub.screenDimensionsBelowTitlebar.x/dmhub.screenDimensionsBelowTitlebar.y

if actualAspect < standardAspect then
    barScale = barScale * actualAspect/standardAspect
end

ActionBar.allowTinyActionBar = false
ActionBar.hasLoadoutPanel = false
ActionBar.hasCustomizationPanel = false
ActionBar.hasMovementTypePanel = false
ActionBar.resourceBarHeight = 32
ActionBar.containerUIScale = 0.4
ActionBar.containerPageSize = 10
ActionBar.mainPanelMaxWidth = 400*barScale
ActionBar.mainPanelHAlign = "right"
ActionBar.resourceBarWidth = 960*barScale
ActionBar.actionsMinWidth = 1000*barScale
ActionBar.transparentBackground = false
ActionBar.spellInfoOnClick = true
ActionBar.resourcesWithBars = true
ActionBar.largeQuantityResourceHorizontal = false
ActionBar.sortByDisplayOrder = true
ActionBar.hasReactionBar = true

ActionBar.bars = {
--  {
--      category = "Basic Attack",
--      description = "Free Strikes",
--      halign = "left",
--      uiscale = 0.7,
--      panelid = "basic-attack",
--      hasActionResourcesBar = true,
--  },

    {
        category = "Trigger",
        halign = "left",
        hmargin = 16,
        uiscale = 0.7,
        panelid = "triggers",
        hasResourcesBar = false,
        drawer = true,
        drawerText = "T",
        additionalCategories = {
            ["Basic Attack"] = true,
        }
    },

    {
        category = "Ability",
        halign = "left",
        uiscale = 0.7,
        panelid = "ability",
        hasResourcesBar = false,
        drawer = true,
        drawerText = "A",
    },

    {
        category = "Heroic Ability",
        description = "Heroic",
        halign = "center",
        uiscale = 0.7,
        panelid = "heroic-ability",
        hasResourcesBar = true,
        calculateDescription = function(token)
            if token.properties:IsMonster() then
                return ""
            else
                return "Heroic"
            end
        end,
    },

    {
        category = "Signature Ability",
        description = "Signature",
        halign = "right",
        uiscale = 0.7,
        panelid = "signature-ability",
    },

    {
        category = "Skill",
        description = "Common",
        halign = "right",
        uiscale = 0.7,
        panelid = "common",
        hmargin = 16,
        drawer = true,
        drawerText = "C",
    },

    {
        category = "Malice",
        description = "Malice",
        halign = "right",
        uiscale = 0.7,
        panelid = "malice",
        drawer = true,
        drawerText = "M",
        calculateVisible = function(token)
            return token.properties:IsMonster()
        end,
    },


}

Commands.RegisterMacro{
    name = "actionbar",
    summary = "activate ability slot",
    doc = "Usage: /actionbar <panel> <slot>\nActivates the given slot number on the specified action bar panel.",
    command = function(str)
        local items = string.split(str, " ")
        if type(items) ~= "table" or #items ~= 2 then
            return
        end

        local panelid = items[1]
        local n = items[2]
        n = tonumber(n)
        if n == nil then
            return
        end
        if gamehud ~= nil then
            local target = gamehud.dialog.sheet:Get(panelid)
            if target ~= nil and target.enabled then
                target:FireEventTree("activate", n)
            end
        end
    end,
}

Keybinds.Register{
    command = "actionbar basic-attack 1",
    name = tr("Ability: Basic Attack"),
    section = "gameplay",
}

for i=1,3 do
    Keybinds.Register{
        command = "actionbar signature-ability "..i,
        name = tr(string.format("Ability: Signature Ability %d", i)),
        section = "gameplay",
    }
end

for i=1,4 do
    Keybinds.Register{
        command = "actionbar heroic-ability "..i,
        name = tr(string.format("Ability: Heroic Ability %d", i)),
        section = "gameplay",
    }
end

for i=1,10 do
    Keybinds.Register{
        command = "actionbar actions-main-panel "..i,
        name = tr(string.format("Skill: %d", i)),
        ord = string.format("Skill: %03d", i),
        section = "gameplay",
    }
end