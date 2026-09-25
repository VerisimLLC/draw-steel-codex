local mod = dmhub.GetModLoading()

--Footprint styles: the tracks a creature leaves when it walks on a surface that
--takes prints (AudioSurfaceTypes entries flagged footprints: snow, grass). Each
--creature picks one on its Appearance tab (the creature's footprintStyle field).
--LeaveFootprints in Draw Steel Audio/AudioMain.lua lays them down; the engine's
--FootprintRenderer draws and fades them.
--
--The built-in styles below ship with the app (their art is in the engine's
--Assets/UIImages/footprints) and are offered in every game. Directors add more in
--Compendium > Assets > Footprints. "Feet" is what a creature leaves until someone
--picks something else; "None" leaves nothing. "Basic" is the engine's generated
--boot print.
--
--Every print is drawn black at partial opacity (FootprintStyle.printColor), so it
--just darkens whatever ground it lands on. Only an image's transparency matters.

--- @class FootprintStyle: GameType
--- @field id string GUID identifier (engine-managed for table items)
--- @field name string Display name
--- @field imageid string Image asset id of the print, drawn toe-up. "" uses the built-in boot print.
--- @field length number Print length in tiles for a medium creature; bigger creatures scale up.
--- @field spacing number Distance walked between prints, in tiles, for a medium creature.
--- @field alternate boolean Prints step to either side of the path, mirrored for the left foot.
FootprintStyle = RegisterGameType("FootprintStyle")

FootprintStyle.tableName = "footprintStyles"

FootprintStyle.name = "New Footprints"
FootprintStyle.imageid = ""
FootprintStyle.length = 0.3
FootprintStyle.spacing = 0.45
FootprintStyle.alternate = true

--What every print is drawn as: black, partly transparent.
FootprintStyle.printColor = "#00000066"

--Values of a creature's footprintStyle besides a table id. An unset value means
--the default style (Feet), which is why picking Feet stores nothing.
FootprintStyle.defaultId = "feet"
FootprintStyle.basicId = "basic"
FootprintStyle.noneId = "none"

--The built-in styles, in dropdown order, in the same shape GetForCreature returns.
--Their ids are fixed strings, so a creature's choice means the same in every game.
--imageid nil is the engine's generated boot.
local g_builtinStyles = {
    { id = FootprintStyle.defaultId, name = "Feet", imageid = "footprints/feet.png", length = 0.26, spacing = 0.4, alternate = true },
    { id = FootprintStyle.basicId, name = "Basic", imageid = nil, length = 0.3, spacing = 0.45, alternate = true },
    { id = "boots", name = "Boots", imageid = "footprints/boots.png", length = 0.3, spacing = 0.45, alternate = true },
    { id = "hooves", name = "Hooves", imageid = "footprints/hooves.png", length = 0.2, spacing = 0.5, alternate = true },
    { id = "paws", name = "Paws", imageid = "footprints/paws.png", length = 0.2, spacing = 0.4, alternate = true },
    { id = "talons", name = "Talons", imageid = "footprints/talons.png", length = 0.24, spacing = 0.4, alternate = true },
    --one wavy drag mark per print, laid end to end into a continuous trail.
    { id = "trail", name = "Trail", imageid = "footprints/trail.png", length = 0.45, spacing = 0.45, alternate = false },
}

local g_builtinById = {}
for _,style in ipairs(g_builtinStyles) do
    g_builtinById[style.id] = style
end

local g_defaultStyle = g_builtinById[FootprintStyle.defaultId]

--- @param args table|nil Field overrides (Compendium.GenericEditor calls this as CreateNew{})
--- @return FootprintStyle
function FootprintStyle.CreateNew(args)
    return FootprintStyle.new(args or {})
end

--- The style a creature leaves as a plain table {id, name, imageid, length,
--- spacing, alternate}, or nil when it leaves no prints. A compendium style that
--- has since been deleted or hidden falls back to the default (Feet).
--- @param props creature
--- @return table|nil
function FootprintStyle.GetForCreature(props)
    local id = props:try_get("footprintStyle")
    if id == nil or id == "" then
        return g_defaultStyle
    end

    if id == FootprintStyle.noneId then
        return nil
    end

    local builtin = g_builtinById[id]
    if builtin ~= nil then
        return builtin
    end

    local styles = dmhub.GetTable(FootprintStyle.tableName) or {}
    local style = styles[id]
    if style == nil or style:try_get("hidden") then
        return g_defaultStyle
    end

    local imageid = style.imageid
    if imageid == "" then
        imageid = nil
    end

    return {
        id = id,
        name = style.name,
        imageid = imageid,
        length = style.length,
        spacing = style.spacing,
        alternate = style.alternate,
    }
end

--- Dropdown options for picking a creature's footprints: the built-in styles,
--- then every compendium style by name, then None.
--- @return {id: string, text: string}[]
function FootprintStyle.GetOptions()
    local options = {}
    for _,style in ipairs(g_builtinStyles) do
        options[#options+1] = { id = style.id, text = style.name }
    end

    local custom = {}
    for id, style in unhidden_pairs(dmhub.GetTable(FootprintStyle.tableName) or {}) do
        custom[#custom+1] = { id = id, text = style.name }
    end
    table.sort(custom, function(a, b) return a.text < b.text end)
    for _,option in ipairs(custom) do
        options[#options+1] = option
    end

    options[#options+1] = { id = FootprintStyle.noneId, text = "None" }
    return options
end

--A number field that ignores text it can't read and clamps what it can.
local function NumberRow(style, label, field, minValue, maxValue, Upload)
    return gui.Panel{
        classes = {"formStackedRow"},
        gui.Label{
            classes = {"formStacked"},
            text = label,
        },
        gui.Input{
            classes = {"formStacked"},
            text = tostring(style[field]),
            editlag = 0.4,
            change = function(element)
                local value = tonumber(element.text)
                if value == nil then
                    element.text = tostring(style[field])
                    return
                end
                value = math.max(minValue, math.min(maxValue, value))
                style[field] = value
                element.text = tostring(value)
                Upload()
            end,
        },
    }
end

local function SetStyle(editorPanel, styleid)
    local styles = dmhub.GetTable(FootprintStyle.tableName) or {}
    local style = styles[styleid]
    if style == nil then
        editorPanel.children = {}
        return
    end

    local Upload = function()
        dmhub.SetAndUploadTableItem(FootprintStyle.tableName, style)
    end

    local children = {}

    children[#children+1] = gui.Panel{
        classes = {"formStackedRow"},
        gui.Label{
            classes = {"formStacked"},
            text = "Name:",
        },
        gui.Input{
            classes = {"formStacked"},
            text = style.name,
            editlag = 0.4,
            change = function(element)
                style.name = element.text
                Upload()
            end,
        },
    }

    children[#children+1] = gui.Panel{
        classes = {"formStackedRow"},
        height = "auto",
        gui.Label{
            classes = {"formStacked"},
            text = "Image:",
        },
        gui.IconEditor{
            library = "footprints",
            allowNone = true,
            allowPaste = true,
            width = 96,
            height = 96,
            halign = "left",
            value = cond(style.imageid == "", nil, style.imageid),
            change = function(element)
                local imageid = element.value or ""
                if imageid == style.imageid then
                    return
                end
                style.imageid = imageid
                Upload()
            end,
        },
    }

    children[#children+1] = gui.Label{
        classes = {"hint"},
        text = "Draw the print toe-up: the top of the image points the way the creature is walking. Only the image's shape (its transparency) is used: every print is drawn as a faint black mark. With no image, the built-in boot print is used.",
    }

    children[#children+1] = NumberRow(style, "Length (tiles):", "length", 0.05, 3, Upload)
    children[#children+1] = NumberRow(style, "Spacing (tiles):", "spacing", 0.1, 5, Upload)

    children[#children+1] = gui.Label{
        classes = {"hint"},
        text = "Sizes are for a medium creature and scale with the creature's size. The print's width follows the image's proportions.",
    }

    children[#children+1] = gui.Check{
        text = "Alternate left and right feet",
        value = style.alternate,
        halign = "left",
        change = function(element)
            style.alternate = element.value
            Upload()
        end,
    }

    editorPanel.children = children
end

--- The compendium editor for footprint styles.
--- @return Panel panel exposing data.SetData(id)
function FootprintStyle.CreateEditor()
    local editor
    editor = gui.Panel{
        data = {
            SetData = function(styleid)
                SetStyle(editor, styleid)
            end,
        },
        styles = {
            {
                selectors = {"hint"},
                bold = false,
                fontSize = 12,
                color = "#bbbbbb",
                width = "98%",
                height = "auto",
                halign = "left",
                valign = "top",
                tmargin = 2,
                bmargin = 8,
            },
        },
        width = "100%",
        height = "auto",
        halign = "left",
        flow = "vertical",
        pad = 20,
        borderBox = true,
    }

    return editor
end

Compendium.Register{
    section = "Assets",
    text = "Footprints",
    contentType = FootprintStyle.tableName,
    click = function(contentPanel)
        Compendium.GenericEditor(contentPanel, FootprintStyle)
    end,
}
