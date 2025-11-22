local mod = dmhub.GetModLoading()

--clear any existing icons and start fresh. This can be done in an extension module if you want to override
--all built-in DMHub icons. You can also use TokenUI.ClearIcon("iconid") to remove a specific icon.
TokenUI.ClearAllIcons()

--this registers a setting in DMHub. We want this setting to control whether the wounded icon shows.
local woundedIconSetting = setting{
	id = "showwoundedicon",
	description = "Show wounded icon",
	editor = "check",
	default = true,

    --this makes the setting get stored in the game's setting, shared by everyone.
	storage = "game",

    --this makes the setting show up as an editable setting in the 'game' area of settings.
    section = "game",

    --ensure only the DM can manipulate this setting.
    classes = {"dmonly"},
}

--the wounded icon configuration.
TokenUI.RegisterIcon{
    id = "wounded",
    icon = "ui-icons/wounded-border.png",
    Filter = function(creature)
        --this controls if the icon should display.
	    return creature.damage_taken >= creature:MaxHitpoints()/2 and woundedIconSetting:Get()
    end,

    --Only show to those who can't see the health bar.
    showToAll = true,
    showToGM = true,
    showToController = true,
    showToFriends = true,
    showToEnemies = true,
}

--the wounded icon configuration.
TokenUI.RegisterIcon{
    id = "concentration",
    icon = "ui-icons/concentration.png",
    Filter = function(creature)
        --this controls if the icon should display.
        if creature:HasConcentration() then
            for _,concentration in ipairs(creature.concentrationList) do
                if not concentration:HasExpired() then
                    return true
                end
            end
        end

        return false
    end,

    showToAll = true,
}

--The movetype icon is a dynamic icon which uses a function to calculate the icon
TokenUI.RegisterIcon{
    id = "movetype",
    Calculate = function(creature)

        --get the movetype of the creature and return an icon entry based on it.
		local movetype = creature:CurrentMoveTypeInfo()

        if creature:CurrentMoveType() == "walk" then
            --'walk' is the regular way a creature moves, so don't display an icon.
		    return { id = movetype.id, icon = "ui-icons/token-elevation-icon.png", yadjust = -1.5, hasAltitude = true, hideAtZeroAltitude = true }
        end

		return { id = movetype.id, icon = movetype.icon, hasAltitude = true } --movetype.hasAltitude }
    end,

    showToAll = true,
}

local hpbarsVisibleOnlyInCombat = setting{
    id = "hpbarsonlyincombat",
    description = "Stamina Bars hidden when not in combat",
    editor = "check",
	default = true,

    --this makes the setting get stored in the game's setting, shared by everyone.
	storage = "game",

    --this makes the setting show up as an editable setting in the 'game' area of settings.
    section = "game",

    --ensure only the DM can manipulate this setting.
    classes = {"dmonly"},
}

--provide some settings for if hitpoints bars are visible or not.
local gmSeesHitpoints = setting{
	id = "hpbarfordm",
	description = "Stamina Bars shown to Director",
	editor = "check",
	default = true,

    --this makes the setting get stored in the game's setting, shared by everyone.
	storage = "game",

    --this makes the setting show up as an editable setting in the 'game' area of settings.
    section = "game",

    --ensure only the DM can manipulate this setting.
    classes = {"dmonly"},
}

local playersSeeOwnHitpoints = setting{
	id = "hpbarforownplayer",
	description = "Stamina Bars shown to controlling player",
	editor = "check",
	default = true,

    --this makes the setting get stored in the game's setting, shared by everyone.
	storage = "game",

    --this makes the setting show up as an editable setting in the 'game' area of settings.
    section = "game",

    --ensure only the DM can manipulate this setting.
    classes = {"dmonly"},
}

local playersSeePartyHitpoints = setting{
	id = "hpbarforparty",
	description = "Stamina Bars shown to party",
	editor = "check",
	default = true,

    --this makes the setting get stored in the game's setting, shared by everyone.
	storage = "game",

    --this makes the setting show up as an editable setting in the 'game' area of settings.
    section = "game",

    --ensure only the DM can manipulate this setting.
    classes = {"dmonly"},
}

local playersSeeEnemyHitpoints = setting{
	id = "hpbarforenemy",
	description = "Stamina Bars for enemies shown to players",
	editor = "check",
	default = false,

    --this makes the setting get stored in the game's setting, shared by everyone.
	storage = "game",

    --this makes the setting show up as an editable setting in the 'game' area of settings.
    section = "game",

    --ensure only the DM can manipulate this setting.
    classes = {"dmonly"},
}

local playersSeeEnemyHitpointsAsPercent = setting{
    id = "hppctforenemy",
    description = "Stamina bars for enemies show percentage",
    editor = "check",
    default = false,

    storage = "game",
    section = "game",
    classes = {"dmonly"},
}


TokenUI.RegisterStatusBar{
    id = "lifebar",

    debug = false,
    --showToAll = true,
    showToGM = function() return gmSeesHitpoints:Get() end,
    showToController = function() return playersSeeOwnHitpoints:Get() end,
    showToFriends = function() return playersSeePartyHitpoints:Get() end,
    showToEnemies = function() return playersSeeEnemyHitpoints:Get() end,

    height = 9,
    width = 1,
    seek = 10, --bar goes up or down 10 hp /second

    --make the fill color change according to current number of hitpoints.
    fillColor = {
        {
            value = 0.5,
            color = "white",

            gradient = Styles.healthGradient,
        },
        {
            color = "white",
            gradient = Styles.damagedGradient,
        },
    },
    tempColor = "blue",
    Calculate = function(creature)
        if hpbarsVisibleOnlyInCombat:Get() then
            local q = dmhub.initiativeQueue
            if q == nil or q.hidden then
                return nil
            end
        end

        return {
            value = creature:CurrentHitpoints(),
            max = creature:MaxHitpoints(),
            temp = creature:TemporaryHitpoints(),
            width = 1, --math.min(1, math.max(0.25, (max_hp*0.1)/creature:GetCalculatedCreatureSizeAsNumber())),
        }
    end
}