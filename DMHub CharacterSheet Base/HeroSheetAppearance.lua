local mod = dmhub.GetModLoading()

--The Hero sheet's Appearance tab: the card art column on the left, and the
--Look, Description, Effects and Summons sub-tabs on the right. Tokens that
--are not Heroes keep CharSheet.AppearancePanel.
--
--This file loads before the Hero sheet's own files (Draw Steel V), so it
--touches their globals only inside functions, never while loading.
--
--Every panel is built once and repainted after; drags and sliders preview
--on the token locally and upload once, on release.

HeroSheetAppearance = rawget(_G, "HeroSheetAppearance") or {}

--A look's own name, by look: lookNames[i] names the look at engine
--index i - 1. Missing or "" shows as "Look N". Kept in step with the
--engine's looks by this tab (a look deleted here takes its name with it).
--- @class creature
--- @field lookNames? string[]

----------------------------------------------------------------------
--Sizes in sheet units.

--the sheet card's shape at Wide (384 x 500, the same as the card itself):
--the big art shows the card's own framing at this shape.
local CARD_ASPECT = 384 / 500
--the most looks the engine keeps on one token.
local MAX_LOOKS = 8
--a name may be this long, typed or suggested.
local NAME_LIMIT = 60
--Card zoom: the card's magnification of the picture, 100% (the picture's
--short side fills the card's width) to 400%.
local ZOOM_MIN = 1
local ZOOM_MAX = 4
--the token's Zoom (portraitZoom: the crop's size as a share of the
--picture's short side), the Encounter of the Week sheet's range; a typed
--value outside it is kept.
local TOKEN_ZOOM_MIN = 0.25
local TOKEN_ZOOM_MAX = 2
--the wheel over either art: one notch moves Zoom 5% and Card zoom 10% (the
--engine's wheel delta is many units a notch, so only its sign is used), and
--a spin uploads once, this long after its last notch.
local TOKEN_WHEEL_STEP = 0.05
local CARD_WHEEL_STEP = 0.1
local WHEEL_SETTLE = 0.4

--the panel under the big art: its rows and the gaps between them.
local UNDER_PAD = 10
local ZOOM_ROW = 28
local ID_ROW = 28
local LOOK_NAME_ROW = 20
local COLOUR_BLOCK = 64
local ROW_GAP = 8
--the gap between the big art and the panel under it.
local ART_GAP = 10
--Narrow's art banner: the card art at this size, its
--controls beside it.
local BANNER = {ART_W = 170, H = 230}

--the Looks strip: as many looks show as fit the strip with room kept for
--the arrows (three at 140% Font Size, five at 100%); the
--arrows come in past that. The strip fits its half at 480 units.
local TILE_W = 86
local TILE_ART_H = 90
local TILE_H = 118
local TILES_SHOWN = 4
local TILE_GAP = 6
local ARROW_W = 26

--2 Fit it: the token preview's size, and the share of the art's square the
--frame takes on a popout token at Circle 100%; must match the engine's
--popout token drawing.
local TOKEN_BOX = 180
--the token's column (the crop box) and the gap after it.
local TOKEN_COLUMN = 220
local TOKEN_GAP = 16
local POPOUT_FRAME_SHARE = 1 / 1.46
--the Token frame and Background windows' grids.
local PICK_TILE = 96
local PICK_COLUMNS = 4
local PICK_GAP = 8

--Mount's saddle counts in words, 1 to 20.
local SADDLE_WORDS = {"One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten",
    "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen", "Twenty"}

--Your colour's swatches; the row shows the first six.
local SWATCHES = {"#6fa8ff", "#e06a5a", "#4db88c", "#e0a84a", "#b07ae0", "#e4ddd0", "#57c4d8", "#f08fc0"}
local SWATCHES_IN_ROW = 6

--the Description tab's fields: key in CharacterDescription, label.
local DESCRIPTION_FIELDS = {
    {key = "height", text = "Height"},
    {key = "weight", text = "Weight"},
    {key = "hair", text = "Hair"},
    {key = "eyes", text = "Eyes"},
    {key = "build", text = "Build"},
    {key = "skinTone", text = "Skin tone"},
    {key = "genderPresentation", text = "Gender presentation"},
    {key = "pronouns", text = "Pronouns"},
}
local DESCRIPTION_FEATURES = {key = "physicalFeatures", text = "Physical features"}

--the sub-tabs across the right side, in order.
local SUBTABS = {
    {id = "look", text = "Look"},
    {id = "description", text = "Description"},
    {id = "effects", text = "Effects"},
    {id = "summons", text = "Summons"},
}

----------------------------------------------------------------------
--Reading the Hero.

--- One wheel event as notches: -1, 0 or 1 (a notch's delta is many units).
--- @param delta number
--- @return number
local function Notches(delta)
    if delta > 0 then
        return 1
    elseif delta < 0 then
        return -1
    end
    return 0
end

--- The open Hero, looked up now.
--- @return nil|CharacterToken
local function Token()
    return HeroSheet.Token()
end

--- True when this engine stores a card framing on each look.
--- Older engines read the new fields as nil.
--- @param token CharacterToken
--- @return boolean
local function HasCardFields(token)
    return token.cardZoom ~= nil
end

--- The picture the card shows: a popout look's card art, else its portrait.
--- @param token CharacterToken
--- @return nil|string
local function CardArt(token)
    local art = token.offTokenPortrait
    if art == nil or art == "" then
        art = token.portrait
    end
    if art == nil or art == "" then
        return nil
    end
    return art
end

--- The look's names as stored (see creature.lookNames).
--- @param token CharacterToken
--- @return string[]
local function LookNames(token)
    local names = nil
    pcall(function() names = token.properties:try_get("lookNames") end)
    if type(names) ~= "table" then
        return {}
    end
    return names
end

--- A look's name: its own, or "Look N" by its place.
--- @param names string[]
--- @param index integer the engine's index (0-based)
--- @return string
local function LookName(names, index)
    local name = names[index + 1]
    if type(name) == "string" and name ~= "" then
        return name
    end
    return string.format("Look %d", index + 1)
end

--- @class HeroAppearanceLook
--- @field kind "look"|"effect"
--- @field index integer the engine's index for a look
--- @field key nil|string an effect look's key
--- @field name string
--- @field art nil|string
--- @field rect nil|Vector4 the token crop of the look's picture
--- @field selected boolean
--- @field customised boolean an effect look with a stored look of its own, which Revert clears

--- The looks the strip shows: the Hero's own, then those effects give.
--- @param token CharacterToken
--- @return HeroAppearanceLook[]
local function Looks(token)
    local result = {}
    local names = LookNames(token)
    local count = math.max(1, token.numAppearanceVariations or 1)
    local override = token.alternateAppearanceOverride
    for i = 0, count - 1 do
        local info = nil
        pcall(function() info = token:GetVariationInfo(i) end)
        result[#result+1] = {
            kind = "look",
            index = i,
            name = LookName(names, i),
            art = info ~= nil and info.portrait or nil,
            rect = info ~= nil and info.portraitRect or nil,
            selected = override == nil and token.appearanceVariationIndex == i,
            customised = false,
        }
    end
    local effects = nil
    pcall(function() effects = token.properties:GetAlternateAppearances() end)
    if effects ~= nil then
        local keys = table.keys(effects)
        table.sort(keys)
        for _, key in ipairs(keys) do
            local stored = nil
            pcall(function() stored = token:GetAlternateAppearanceInfo(key) end)
            local active = override == key
            local art, rect = nil, nil
            if stored ~= nil then
                art = stored.portrait
                rect = stored.portraitRect
            else
                --an untouched effect look shows the effect's own monster.
                local monster = assets.monsters[effects[key].monsterDefault]
                if monster ~= nil then
                    pcall(function() art = monster.info.portrait end)
                end
            end
            result[#result+1] = {
                kind = "effect",
                index = -1,
                key = key,
                name = key,
                art = art,
                rect = rect,
                selected = active,
                --stored: it has its own look, which Revert clears. Showing
                --one stores it too, so a shown look can always revert, as on
                --the old sheet.
                customised = stored ~= nil,
            }
        end
    end
    return result
end

--- Who may set Your colour: a player, on their own primary Hero.
--- @param token CharacterToken
--- @return boolean
local function ShowsColour(token)
    return (not dmhub.isDM) and token.canControl == true and token.primaryCharacter == true
end

--- The player's colour as a hex string.
--- @return string
local function PlayerColourHex()
    local colour = dmhub.GetSettingValue("playercolor")
    local hex = nil
    pcall(function() hex = colour.tostring end)
    if type(hex) ~= "string" then
        return "#ffffffff"
    end
    return hex
end

--- @param hex string
local function SetPlayerColour(hex)
    dmhub.SetSettingValue("playercolor", core.Color(hex))
end

----------------------------------------------------------------------
--Writing. Look fields go through the token's appearance upload (undoable,
--HeroSheetWrite.SaveAppearance); look names and the description are the
--Hero's own data (HeroSheetWrite.Save). Switching, adding and deleting a
--look are the engine's own calls, which are not undoable.

--- Store the looks' names.
--- @param description string
--- @param undoable boolean
--- @param change fun(names: string[])
local function SaveNames(description, undoable, change)
    HeroSheetWrite.Save{
        description = description,
        undoable = undoable,
        execute = function(props, token)
            local names = {}
            local stored = props:try_get("lookNames")
            if type(stored) == "table" then
                for i, name in ipairs(stored) do
                    names[i] = name
                end
            end
            change(names)
            props.lookNames = names
        end,
    }
end

--- The Hero's summons that follow its frame take a new frame, tint or look.
--- A frame later, once the change is on the Hero's token.
local function RestyleFollowers()
    dmhub.Schedule(0.05, function()
        local token = Token()
        if mod.unloaded or token == nil or not HeroSheetWrite.CanWrite() then
            return
        end
        ActivatedAbilitySummonBehavior.RestyleFollowingSummons(token)
    end)
end

--- Show a look, or an effect's look.
--- @param look HeroAppearanceLook
local function SwitchTo(look)
    local token = Token()
    if token == nil or not HeroSheetWrite.CanWrite() or look.selected then
        return
    end
    if look.kind == "effect" then
        local effects = token.properties:GetAlternateAppearances()
        local entry = effects ~= nil and effects[look.key] or nil
        local default = nil
        local monster = entry ~= nil and assets.monsters[entry.monsterDefault] or nil
        if monster ~= nil then
            default = monster.info
        end
        token:OverrideAlternateAppearance(look.key, default)
    else
        token:SwitchAppearanceVariation(look.index)
    end
    RestyleFollowers()
    HeroSheetRefresh.Changed()
end

----------------------------------------------------------------------
--Small parts in the sheet's look.

--- A label.
--- @param args table gui.Label args
--- @return Panel
local function Text(args)
    args.classes = args.classes or {"heroSheetCardText"}
    args.width = args.width or "auto"
    args.height = args.height or "auto"
    return gui.Label(args)
end

--- A typed name tidied: ends trimmed, runs of spaces made one.
--- @param text nil|string
--- @return string
local function CleanName(text)
    return trim((string.gsub(text or "", "%s+", " ")))
end

--- A field's name over it (the sheet windows' small warm heading).
--- @param text string
--- @return Panel
local function FieldName(text)
    return gui.Label{
        classes = {"heroSheetFieldLabel"},
        text = string.upper(text),
        fontSize = 11.5,
        bold = true,
        width = "100%",
        height = 18,
        textWrap = false,
    }
end

--- A small button sized to its words, with an optional icon.
--- @param args {text: string, icon: nil|string, click: fun(element: Panel), rightClick: nil|fun(element: Panel), width: nil|number}
--- @return Panel button
--- @return Panel label
--- @return nil|Panel icon
local function SmallButton(args)
    local icon = nil
    if args.icon ~= nil then
        icon = gui.Panel{
            classes = {"heroSheetFg"},
            bgimage = args.icon,
            width = 14,
            height = 14,
            rmargin = 6,
            valign = "center",
            interactable = false,
        }
    end
    local label = Text{
        classes = {"heroSheetButtonLabel"},
        text = args.text,
        fontSize = 13,
        valign = "center",
        textWrap = false,
        interactable = false,
    }
    local button = gui.Panel{
        classes = {"heroSheetSmallButton", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 5,
        width = args.width or "auto",
        height = 26,
        hpad = 10,
        borderBox = true,
        flow = "horizontal",
        halign = "left",
        valign = "center",
        rmargin = 8,
        data = {},
        hover = function(element)
            if element.data.tip ~= nil then
                gui.Tooltip(element.data.tip)(element)
            end
        end,
        click = function(element)
            if not element:HasClass("heroSheetOff") then
                args.click(element)
            end
        end,
        rightClick = args.rightClick,
        icon,
        label,
    }
    return button, label, icon
end

--- A text field in the sheet windows' look.
--- search: the app's search field (gui.SearchInput), with its own look.
--- @param args {text: string, placeholder: nil|string, limit: nil|integer, multiline: nil|boolean, height: nil|number, selectAll: nil|boolean, search: nil|boolean, edit: nil|fun(text: string), defocus: nil|fun(text: string)}
--- @return Panel
local function Field(args)
    if args.search == true then
        return gui.SearchInput{
            text = args.text,
            placeholderText = args.placeholder or "",
            width = "100%",
            height = args.height or 30,
            borderBox = true,
            characterLimit = args.limit or 200,
            editlag = 0.05,
            edit = function(element)
                if args.edit ~= nil then
                    args.edit(element.text or "")
                end
            end,
        }
    end
    return gui.Input{
        classes = {"heroSheetField"},
        text = args.text,
        placeholderText = args.placeholder or "",
        width = "100%",
        height = args.height or 30,
        hpad = 10,
        vpad = cond(args.multiline, 6, 0),
        borderBox = true,
        border = 1,
        cornerRadius = 6,
        fontSize = 14,
        multiline = args.multiline == true,
        textWrap = args.multiline == true,
        textAlignment = cond(args.multiline, "topleft", "left"),
        characterLimit = args.limit or 200,
        selectAllOnFocus = args.selectAll == true,
        editlag = 0.05,
        edit = function(element)
            if args.edit ~= nil then
                args.edit(element.text or "")
            end
        end,
        defocus = function(element)
            if args.defocus ~= nil then
                args.defocus(element.text or "")
            end
        end,
    }
end

--- A block on the tab: a plate with a heading and a one-line hint, and
--- optionally something at the heading's right (Light's night label).
--- @param title string
--- @param hint string
--- @param content Panel
--- @param extra? {panel: Panel, width: number} at the heading's right, the hint giving it room
--- @return Panel block
--- @return Panel hintLabel
--- @return Panel titleLabel
local function Block(title, hint, content, extra)
    local titleLabel = Text{
        classes = {"heroSheetCardStrong"},
        text = string.upper(title),
        fontSize = 14,
        bold = true,
        halign = "left",
        valign = "center",
        textWrap = false,
    }
    local hintLabel = Text{
        classes = {"heroSheetCardSub"},
        text = hint,
        fontSize = 12,
        width = string.format("100%%-%d", 90 + (extra ~= nil and extra.width or 0)),
        height = 16,
        lmargin = 12,
        --left, or the row centres it once the extra part collapses.
        halign = "left",
        valign = "center",
        textWrap = false,
        textOverflow = "ellipsis",
    }
    --an empty hint takes no room, so a long title and the extra part fit.
    hintLabel:SetClass("collapsed", hint == "")
    local block = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = "auto",
        flow = "vertical",
        pad = 12,
        borderBox = true,
        gui.Panel{
            width = "100%",
            height = 20,
            flow = "horizontal",
            bmargin = 10,
            titleLabel,
            hintLabel,
            extra ~= nil and extra.panel or nil,
        },
        content,
    }
    return block, hintLabel, titleLabel
end

----------------------------------------------------------------------
--Windows.

--- New look: its name, then the engine copies the current look into a
--- new one and shows it.
--- @param token CharacterToken
local function NewLookWindow(token)
    local field = Field{
        text = "",
        placeholder = "Battle-worn, Formal, Incognito...",
        limit = NAME_LIMIT,
    }
    HeroSheetWindow.ShowDialog{
        title = "New look",
        subtitle = token.name,
        width = 520,
        --the heights of the body's children below: field name, field, the
        --note's gap and the note.
        bodyHeight = 18 + 30 + 10 + 36,
        body = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            FieldName("Name"),
            field,
            Text{
                classes = {"heroSheetCardSub"},
                text = "It starts as a copy of the current look: art, frame, name and anthem.",
                fontSize = 13,
                width = "100%",
                height = 36,
                tmargin = 10,
                textWrap = true,
            },
        },
        saveText = "Add look",
        onSave = function()
            local live = Token()
            if live == nil or not HeroSheetWrite.CanWrite() then
                return
            end
            local count = math.max(1, live.numAppearanceVariations or 1)
            if count >= MAX_LOOKS then
                return
            end
            --the engine copies the look being left into the new slot.
            live:SwitchAppearanceVariation(count)
            local name = CleanName(field.text)
            SaveNames("Add look", false, function(names)
                for i = #names + 1, count do
                    names[i] = ""
                end
                names[count + 1] = name
            end)
            HeroSheetRefresh.Changed()
        end,
    }
    dmhub.Schedule(0.05, function()
        if not mod.unloaded and field.valid then
            gui.SetFocus(field)
        end
    end)
end

--- Rename look.
--- @param token CharacterToken
--- @param look HeroAppearanceLook
local function RenameWindow(token, look)
    local field = Field{
        text = look.name,
        limit = NAME_LIMIT,
        selectAll = true,
    }
    HeroSheetWindow.ShowDialog{
        title = "Rename look",
        subtitle = token.name,
        width = 520,
        bodyHeight = 18 + 30,
        body = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            FieldName("Name"),
            field,
        },
        onSave = function()
            local name = CleanName(field.text)
            SaveNames("Rename look", true, function(names)
                for i = #names + 1, look.index do
                    names[i] = ""
                end
                names[look.index + 1] = name
            end)
            HeroSheetRefresh.Changed()
        end,
    }
    dmhub.Schedule(0.05, function()
        if not mod.unloaded and field.valid then
            gui.SetFocus(field)
        end
    end)
end

--- Delete <look>? The engine deletes only a look not showing, so a showing
--- one hands over to its neighbour first, as on the old sheet.
--- @param token CharacterToken
--- @param look HeroAppearanceLook
local function ConfirmDelete(token, look)
    HeroSheetWindow.ShowDialog{
        title = string.format("Delete %s?", look.name),
        width = 520,
        bodyHeight = 22,
        body = Text{
            classes = {"heroSheetCardText"},
            text = "Its art, frame, name and anthem go with it.",
            fontSize = 14,
            width = "100%",
            textWrap = true,
        },
        saveText = "Delete",
        onSave = function()
            local live = Token()
            if live == nil or not HeroSheetWrite.CanWrite() then
                return
            end
            local count = math.max(1, live.numAppearanceVariations or 1)
            if count <= 1 then
                return
            end
            if live.appearanceVariationIndex == look.index and live.alternateAppearanceOverride == nil then
                live:SwitchAppearanceVariation(cond(look.index == 0, 1, look.index - 1))
            end
            live:DeleteAppearanceVariation(look.index)
            RestyleFollowers()
            SaveNames("Delete look", false, function(names)
                if look.index + 1 <= #names then
                    table.remove(names, look.index + 1)
                end
            end)
            HeroSheetRefresh.Changed()
        end,
    }
end

--- Your colour: the swatches and any colour.
local function ColourWindow()
    --The picker fires change every frame of a drag: the colour is saved (a
    --settings write) and the sheet checked once, when the drag lets go.
    --- @type any a colour picked but not saved yet
    local pending = nil
    local function SavePending()
        if pending ~= nil then
            dmhub.SetSettingValue("playercolor", pending)
            pending = nil
            HeroSheetRefresh.Recheck()
        end
    end
    local picker = gui.ColorPicker{
        value = dmhub.GetSettingValue("playercolor"),
        hasAlpha = false,
        width = 36,
        height = 36,
        cornerRadius = 18,
        border = 1,
        borderColor = "#ffffff40",
        halign = "left",
        change = function(element)
            pending = element.value
        end,
        confirm = function(element)
            pending = element.value
            SavePending()
        end,
        --the window closed mid-pick: keep what was picked.
        destroy = function(element)
            SavePending()
        end,
    }
    local swatches = {}
    for _, hex in ipairs(SWATCHES) do
        swatches[#swatches+1] = gui.Panel{
            classes = {"hoverable"},
            bgimage = "panels/square.png",
            bgcolor = hex,
            cornerRadius = 14,
            border = 1,
            borderColor = "#ffffff40",
            width = 28,
            height = 28,
            rmargin = 8,
            click = function(element)
                pending = nil
                SetPlayerColour(hex)
                picker.value = core.Color(hex)
                --the colour is a setting, not the Hero's data.
                HeroSheetRefresh.Recheck()
            end,
        }
    end
    HeroSheetWindow.ShowDialog{
        title = "Your colour",
        width = 520,
        --the heights of the body's children below, with their top margins:
        --the note, the swatch row, then the field name and the picker.
        bodyHeight = 40 + 10 + 28 + 14 + 18 + 36,
        body = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            Text{
                classes = {"heroSheetCardText"},
                text = "Your colour marks your rolls, pings and drawings for everyone. It belongs to your account, not this Hero.",
                fontSize = 14,
                width = "100%",
                height = 40,
                textWrap = true,
            },
            gui.Panel{
                width = "100%",
                height = 28,
                tmargin = 10,
                flow = "horizontal",
                children = swatches,
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                tmargin = 14,
                flow = "vertical",
                FieldName("Any colour"),
                picker,
            },
        },
        onDone = function() end,
    }
end

----------------------------------------------------------------------
--The art column: the big art as the card's own framing, at the
--card's shape over a dimmed fill of the same picture at the same placement;
--the name on it; under it Card zoom, privacy and Suggest a name, the look's
--name line and Your colour. The column never scrolls: the art takes the
--height the panel under it leaves. Its view is HeroAppearanceView (HeroSheet.lua).

--- What the tab's parts call on each other: the art column fills it in.
--- @class HeroAppearanceBus
--- @field PreviewArt nil|fun(id: nil|string) shows a picture on the big card (nil puts the look's back)
--- @field MapShown nil|fun(shown: boolean) On the map's preview is on screen, or not
--- @field MapReset nil|fun() the sheet closed: On the map opens in Daylight next time
--- @field EffectsShown nil|fun(shown: boolean) the Effects tab (its night preview) is on screen, or not
--- @field SummonsShown nil|fun(shown: boolean) the Summons tab (its map preview) is on screen, or not
--- @field EditName nil|fun() starts typing the name on the card
--- @field ShowSubtab nil|fun(id: string) opens a sub-tab
--- @field RevealArt nil|fun(): nil|Panel opens Look with 1 Choose the art in view; its plate

--- Who hosts the surface, fired as heroAppearanceHost on the column and the
--- body: the sheet (builder false) or the Builder's Appearance step.
--- @class HeroAppearanceHost
--- @field builder boolean
--- @field shown boolean the Builder shows the step (ignored for the sheet)
--- @field columnUnits nil|number the art column's width in its host's units

--- @param bus HeroAppearanceBus
--- @return Panel column
local function BuildColumn(bus)
    --shown as Narrow's banner (heroAppearanceBanner), not the left column.
    local banner = false
    --the column's width in units when the Builder hosts it; nil on the sheet.
    --- @type nil|number
    local hostUnits = nil
    --the drag or slider in progress: the snapshot to upload with.
    --- @type nil|string
    local snapshot = nil
    --- @type nil|{anchor: Vector2, offset: Vector2, w: number, h: number}
    local drag = nil
    --what the big art shows: set by Paint, read by the drag.
    --- @type {art: nil|string, cardRect: nil|Vector4, cardWidthPct: number, cardHeightPct: number, boxW: nil|number, boxH: nil|number, perPixel: number}
    local model = {art = nil, cardRect = nil, cardWidthPct = 1, cardHeightPct = 1, boxW = nil, boxH = nil, perPixel = 1}

    local box
    local fill
    local card
    local cardArt
    local dragTag
    local nameLabel
    local namePrompt
    --- @type fun(token: nil|CharacterToken)
    local PaintName
    local nameField
    local nameStrip
    local under
    local zoomRow
    local zoomSlider
    local eyeButton, eyeLabel, eyeIcon
    local suggestButton
    local lookNameRow
    local useHeroLink
    local colourBlock
    local colourSwatches = {}
    local Fit
    --bumped by each wheel notch: only a spin's last notch uploads.
    local wheelSerial = 0

    --- The card's framing now: the look's own, or the token's crop it falls
    --- back to (so the first drag starts from what the card already shows).
    --- @param token CharacterToken
    --- @return number zoom, Vector2 offset
    local function Framing(token)
        if token.hasCardFraming then
            return token.cardZoom, token.cardOffset
        end
        local zoom = token.portraitZoom
        if type(zoom) ~= "number" or zoom <= 0 then
            zoom = 1
        end
        return zoom, token.portraitOffset or core.Vector2(0, 0)
    end

    --- Start a preview of the card framing (a drag, the slider): the
    --- snapshot for undo, and the look given a card framing of its own.
    --- @return nil|CharacterToken
    local function Begin()
        local token = Token()
        if token == nil or not HeroSheetWrite.CanWrite() or not HasCardFields(token) then
            return nil
        end
        if snapshot == nil then
            local live, shot = HeroSheetWrite.PreviewAppearance()
            if live == nil or shot == nil then
                return nil
            end
            token = live
            snapshot = shot
            local zoom, offset = Framing(token)
            token.cardZoom = zoom
            token.cardOffset = core.Vector2(offset.x, offset.y)
        end
        return token
    end

    --- Keep the stored offset where the card's crop actually sits: the engine
    --- keeps the crop inside the picture, and an offset past the edge would
    --- make the next drag do nothing until it came back.
    --- @param token CharacterToken
    local function ClampOffset(token)
        local art = CardArt(token)
        if art == nil then
            return
        end
        local rect = nil
        pcall(function() rect = token:GetCardRectForAspect(CARD_ASPECT, art) end)
        if rect ~= nil then
            token.cardOffset = core.Vector2((rect.x1 + rect.x2) / 2 - 0.5, (rect.y1 + rect.y2) / 2 - 0.5)
        end
    end

    --- Upload the previewed framing as one undo step.
    local function Commit()
        local shot = snapshot
        snapshot = nil
        drag = nil
        if shot ~= nil then
            HeroSheetWrite.CommitAppearance(shot)
            HeroSheetRefresh.Changed()
        end
    end

    --- Place the fill in the box from its shares (set by PaintArt) and the
    --- box's last measured size, so a drag moves it in the same frame.
    local function PlaceFill()
        if model.boxW == nil then
            return
        end
        fill.selfStyle.lmargin = math.floor((fill.data.left or 0) * model.boxW * model.perPixel + 0.5)
        fill.selfStyle.tmargin = math.floor((fill.data.top or 0) * model.boxH * model.perPixel + 0.5)
    end

    --- Paint the big art from the token's framing; the fill is the same
    --- picture at the same placement, cut to where it reaches in the box.
    --- @param token CharacterToken
    local function PaintArt(token)
        local art = CardArt(token)
        model.art = art
        if art == nil then
            cardArt.bgimage = "panels/square.png"
            cardArt.selfStyle.bgcolor = "#1d1915ff"
            fill:SetClass("collapsed", true)
            return
        end
        local rect = nil
        pcall(function() rect = CardPortraitRect(token, CARD_ASPECT, art) end)
        model.cardRect = rect
        cardArt.bgimage = art
        cardArt.selfStyle.bgcolor = "white"
        cardArt.selfStyle.imageRect = rect
        if rect == nil then
            fill:SetClass("collapsed", true)
            return
        end
        --the picture's UV span per box width / height, from the card's.
        local uPerBox = (rect.x2 - rect.x1) / model.cardWidthPct
        local vPerBox = (rect.y2 - rect.y1) / model.cardHeightPct
        local cu = (rect.x1 + rect.x2) / 2
        local cv = (rect.y1 + rect.y2) / 2
        --the box in UV, then clipped to the picture.
        local bx1, bx2 = cu - uPerBox / 2, cu + uPerBox / 2
        local by1, by2 = cv - vPerBox / 2, cv + vPerBox / 2
        local ux1, ux2 = math.max(0, bx1), math.min(1, bx2)
        local uy1, uy2 = math.max(0, by1), math.min(1, by2)
        if ux2 <= ux1 or uy2 <= uy1 then
            fill:SetClass("collapsed", true)
            return
        end
        fill:SetClass("collapsed", false)
        fill.bgimage = art
        fill.selfStyle.imageRect = {x1 = ux1, y1 = uy1, x2 = ux2, y2 = uy2}
        --where that part sits in the box, as shares of its size (UV y runs
        --up, the box's down).
        fill.selfStyle.width = string.format("%.3f%%", 100 * (ux2 - ux1) / uPerBox)
        fill.selfStyle.height = string.format("%.3f%%", 100 * (uy2 - uy1) / vPerBox)
        fill.data.left = (ux1 - bx1) / uPerBox
        fill.data.top = (by2 - uy2) / vPerBox
        PlaceFill()
    end

    --a Suggested thumbnail hovered: its picture at the card's framing, the
    --fill hidden; nil paints the look again.
    bus.PreviewArt = function(id)
        local token = Token()
        if token == nil or snapshot ~= nil or not cardArt.valid then
            return
        end
        if id == nil then
            PaintArt(token)
            return
        end
        local rect = nil
        pcall(function() rect = CardPortraitRect(token, CARD_ASPECT, id) end)
        cardArt.bgimage = id
        cardArt.selfStyle.bgcolor = "white"
        cardArt.selfStyle.imageRect = rect
        fill:SetClass("collapsed", true)
    end

    --- The rest of the column from the Hero: name, buttons, rows shown.
    --- @param token CharacterToken
    local function PaintRest(token)
        local writable = HeroSheetWrite.CanWrite()
        PaintName(token)
        local cardFields = HasCardFields(token)
        dragTag:SetClass("collapsed", not (writable and cardFields and CardArt(token) ~= nil))
        zoomRow:SetClass("collapsed", not cardFields)
        if cardFields and snapshot == nil then
            local zoom = Framing(token)
            zoomSlider.value = math.clamp(1 / zoom, ZOOM_MIN, ZOOM_MAX)
        end
        local private = token.namePrivate == true
        eyeLabel.text = cond(private, "Name hidden", "Name shown")
        eyeIcon.bgimage = cond(private, "phosphor/eye-slash.png", "phosphor/eye.png")
        eyeButton.data.tip = cond(private, "Hidden from other players", "Visible to other players")
        local hasTable, ancestry = HeroSheetCard.NameTable(token)
        suggestButton:SetClass("heroSheetOff", not hasTable or not writable)
        suggestButton.data.tip = cond(hasTable, nil, HeroSheetCard.NoNamesTip(ancestry))
        --a look other than the first carries its own name;
        --"Use <Hero>" needs the first look's name, which engines that report
        --it per look (GetVariationInfo's characterName) give.
        local laterLook = token.alternateAppearanceOverride == nil and (token.appearanceVariationIndex or 0) > 0
        lookNameRow:SetClass("collapsed", not laterLook)
        local heroName = nil
        if laterLook then
            pcall(function()
                --read as a plain table: characterName is not in the stub's shape yet.
                local info = token:GetVariationInfo(0) --[[@as table]]
                heroName = info.characterName
            end)
        end
        useHeroLink:SetClass("collapsed", heroName == nil or heroName == "" or heroName == token.name)
        if heroName ~= nil then
            useHeroLink.text = string.format("Use %s", heroName)
            useHeroLink.data.name = heroName
        end
        local colour = ShowsColour(token)
        colourBlock:SetClass("collapsed", not colour)
        if colour then
            local current = string.lower(string.sub(PlayerColourHex(), 1, 7))
            for i, swatch in ipairs(colourSwatches) do
                swatch:SetClass("selected", SWATCHES[i] == current)
            end
        end
        --the art takes what the panel under it leaves.
        local underHeight = 2 * UNDER_PAD + ID_ROW
        if cardFields then
            underHeight = underHeight + ZOOM_ROW + ROW_GAP
        end
        if laterLook then
            underHeight = underHeight + LOOK_NAME_ROW + ROW_GAP
        end
        if colour then
            underHeight = underHeight + COLOUR_BLOCK + ROW_GAP
        end
        under.selfStyle.height = underHeight
        --as Narrow's banner the art keeps the banner's height, beside the panel.
        box.selfStyle.height = cond(banner, "100%", string.format("100%%-%d", underHeight + ART_GAP))
    end

    --- Fit the card and the fill to the box's shape, measured after layout.
    local fitGen = 0
    Fit = function()
        fitGen = fitGen + 1
        local gen = fitGen
        HeroSheetWindow.AfterLayout(function()
            if gen ~= fitGen or not box.valid then
                return
            end
            local boxWidth, boxHeight = box.renderedWidth, box.renderedHeight
            if boxWidth <= 0 or boxHeight <= 0 then
                return
            end
            local boxAspect = boxWidth / boxHeight
            local wPct, hPct = 1, 1
            if boxAspect > CARD_ASPECT then
                wPct = CARD_ASPECT / boxAspect
            else
                hPct = boxAspect / CARD_ASPECT
            end
            local changed = math.abs(wPct - model.cardWidthPct) > 0.001 or math.abs(hPct - model.cardHeightPct) > 0.001
            model.cardWidthPct = wPct
            model.cardHeightPct = hPct
            card.selfStyle.width = string.format("%.3f%%", wPct * 100)
            card.selfStyle.height = string.format("%.3f%%", hPct * 100)
            --units per screen pixel, from the box's known width: the banner's
            --art, the Builder's card column, or the sheet's for its tier.
            local columnUnits = hostUnits or HeroSheet.CardColumnWidth(HeroSheet.Tier()) or 384
            if banner then
                columnUnits = BANNER.ART_W
            end
            model.perPixel = columnUnits / boxWidth
            model.boxW = boxWidth
            model.boxH = boxHeight
            --the fill's placement depends on the card's share of the box.
            local token = Token()
            if changed and token ~= nil and snapshot == nil then
                PaintArt(token)
            else
                PlaceFill()
            end
        end)
    end

    --The name typed on the card: Enter or a click away saves, Esc puts the
    --old name back (as the sheet card's name does).
    local typing = false
    --the Hero whose name is being typed: a save landing after a switch to
    --another Hero is dropped, not given to them.
    local openFor = nil
    --- The name on the card, or while it is empty and the Hero can be
    --- renamed, the "Name your Hero" prompt in the to-do colour.
    --- @param token nil|CharacterToken
    PaintName = function(token)
        local name = token ~= nil and token.name or ""
        local prompt = name == "" and not typing and HeroSheetWrite.CanWrite()
        nameLabel.text = name
        nameLabel:SetClass("collapsed", typing or prompt)
        namePrompt:SetClass("collapsed", not prompt)
        nameStrip:SetClass("heroAppearNameEmpty", prompt)
    end
    --counts the field's openings, so a save left over from one opening never
    --closes the next (Suggest a name clicked again while typing).
    local nameOpenings = 0
    local function CloseName()
        typing = false
        nameField:SetClass("collapsed", true)
        PaintName(Token())
        nameField.captureEscape = false
        --a click away ends the typing but leaves gui's focus on the field,
        --and the sheet holds this column's redraws while it has the focus.
        if gui.GetFocus() == nameField then
            gui.SetFocus(nil)
        end
    end
    --- @param text string
    local function CommitName(text)
        if not typing then
            return
        end
        CloseName()
        local token = Token()
        if token == nil or token.charid ~= openFor then
            return
        end
        local name = string.sub(CleanName(text), 1, NAME_LIMIT)
        if name ~= "" and name ~= token.name then
            HeroSheetWrite.SaveAppearance(function(live)
                live.name = name
            end)
            HeroSheetRefresh.Changed()
        end
    end
    --- @param text string
    local function OpenName(text)
        if not HeroSheetWrite.CanWrite() then
            return
        end
        nameOpenings = nameOpenings + 1
        typing = true
        local token = Token()
        openFor = token ~= nil and token.charid or nil
        PaintName(token)
        nameField:SetClass("collapsed", false)
        nameField.captureEscape = true
        nameField.text = text
        dmhub.Schedule(0.01, function()
            if not mod.unloaded and nameField.valid and typing then
                gui.SetFocus(nameField)
            end
        end)
    end
    bus.EditName = function()
        local token = Token()
        if token ~= nil and not typing then
            OpenName(token.name or "")
        end
    end

    fill = gui.Panel{
        classes = {"collapsed"},
        bgimage = "panels/square.png",
        --the same picture, dimmed, around the card; the frost panel over it
        --blurs it.
        bgcolor = "#5c5c5cff",
        halign = "left",
        valign = "top",
        width = "100%",
        height = "100%",
        interactable = false,
        data = {},
    }

    --shown while the card is hovered (a style rule, so a drag that ends off
    --the card cannot leave it showing); collapsed when the art cannot move.
    dragTag = Text{
        classes = {"heroSheetCardText", "heroAppearDragTag", "collapsed"},
        text = "Drag to move",
        fontSize = 12,
        bgimage = "panels/square.png",
        bgcolor = "#000000b0",
        cornerRadius = 4,
        hpad = 6,
        vpad = 2,
        borderBox = true,
        halign = "left",
        valign = "top",
        lmargin = 8,
        tmargin = 8,
        textWrap = false,
        interactable = false,
    }

    nameLabel = Text{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 26,
        bold = true,
        width = "100%-28",
        textWrap = true,
        halign = "left",
        valign = "bottom",
        interactable = false,
    }
    namePrompt = Text{
        classes = {"heroAppearNamePrompt", "collapsed"},
        text = "Name your Hero",
        fontSize = 26,
        bold = true,
        italics = true,
        width = "100%-28",
        textWrap = true,
        halign = "left",
        valign = "bottom",
        interactable = false,
    }
    nameField = gui.Input{
        classes = {"heroSheetNameField", "collapsed"},
        width = "100%-28",
        height = "auto",
        fontSize = 26,
        bold = true,
        hpad = 4,
        borderBox = true,
        halign = "left",
        valign = "bottom",
        --Enter saves, Shift+Enter adds a line. No multiline = true: the
        --engine turns that into Enter-adds-a-line.
        lineType = "MultiLineSubmit",
        textWrap = true,
        characterLimit = NAME_LIMIT,
        selectAllOnFocus = true,
        placeholderText = "",
        text = "",
        captureEscape = false,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            CloseName()
            gui.SetFocus(nil)
        end,
        submit = function(element)
            local text = element.text
            gui.SetFocus(nil)
            CommitName(text)
        end,
        defocus = function(element)
            local text = element.text
            --a Suggest a name click defocuses the field and puts the next
            --suggestion in it: that typing goes on, so this save does not.
            local opening = nameOpenings
            dmhub.Schedule(0.05, function()
                if not mod.unloaded and opening == nameOpenings then
                    CommitName(text)
                end
            end)
        end,
    }
    --the name strip never starts a drag: it takes the press itself.
    nameStrip = gui.Panel{
        classes = {"heroAppearNameStrip", "hoverable"},
        bgimage = "panels/square.png",
        bgcolor = "#000000a6",
        width = "100%",
        height = "auto",
        hpad = 12,
        vpad = 10,
        borderBox = true,
        flow = "horizontal",
        valign = "bottom",
        swallowPress = true,
        linger = function(element)
            if HeroSheetWrite.CanWrite() and not typing then
                gui.Tooltip("Click to rename")(element)
            end
        end,
        click = function(element)
            if not typing then
                local token = Token()
                OpenName(token ~= nil and token.name or "")
            end
        end,
        nameLabel,
        namePrompt,
        nameField,
        gui.Panel{
            classes = {"heroSheetFg"},
            bgimage = "phosphor/pencil-simple.png",
            width = 16,
            height = 16,
            lmargin = 8,
            halign = "right",
            valign = "bottom",
            bmargin = 6,
            interactable = false,
        },
    }

    cardArt = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "#1d1915ff",
        cornerRadius = 10,
        width = "100%",
        height = "100%",
        interactable = false,
    }

    card = gui.Panel{
        classes = {"heroSheetCardFrame"},
        bgimage = "panels/square.png",
        bgcolor = "clear",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        flow = "none",
        --the art drags only while the button is held.
        press = function(element)
            --a press on the name strip reaches the card too, but its release
            --does not: a drag started here would never end.
            if model.art == nil or model.cardRect == nil or typing or nameStrip:HasClass("hover") then
                return
            end
            local token = Begin()
            if token == nil then
                return
            end
            local offset = token.cardOffset
            drag = {
                anchor = element.mousePoint,
                offset = core.Vector2(offset.x, offset.y),
                w = model.cardRect.x2 - model.cardRect.x1,
                h = model.cardRect.y2 - model.cardRect.y1,
            }
            element.thinkTime = 0.02
        end,
        unpress = function(element)
            element.thinkTime = nil
            if drag ~= nil then
                Commit()
            end
        end,
        think = function(element)
            local token = Token()
            if drag == nil or token == nil or element.mousePoint == nil then
                return
            end
            --the picture follows the pointer: the crop moves the other way.
            local dx = element.mousePoint.x - drag.anchor.x
            local dy = element.mousePoint.y - drag.anchor.y
            token.cardOffset = core.Vector2(drag.offset.x - dx * drag.w, drag.offset.y - dy * drag.h)
            ClampOffset(token)
            PaintArt(token)
        end,
        --the wheel drives Card zoom (wheel up zooms in); a spin is one upload.
        wheel = function(element, delta)
            if model.art == nil or drag ~= nil then
                return true
            end
            local token = Begin()
            if token == nil then
                return true
            end
            local magnification = math.clamp(1 / token.cardZoom + CARD_WHEEL_STEP * Notches(delta), ZOOM_MIN, ZOOM_MAX)
            token.cardZoom = 1 / magnification
            ClampOffset(token)
            PaintArt(token)
            zoomSlider.value = magnification
            wheelSerial = wheelSerial + 1
            local serial = wheelSerial
            dmhub.Schedule(WHEEL_SETTLE, function()
                if not mod.unloaded and serial == wheelSerial and drag == nil then
                    Commit()
                end
            end)
            return true
        end,
        cardArt,
        dragTag,
        nameStrip,
    }

    box = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "#1d1915ff",
        cornerRadius = 10,
        width = "100%",
        height = "100%-200",
        flow = "none",
        fill,
        --blurs the dimmed fill around the card. It is clear, so with
        --Transparent UI off the fill shows unblurred; the card draws on top
        --and stays sharp.
        gui.Panel{
            bgimage = "panels/square.png",
            bgcolor = "#ffffff00",
            frost = 14,
            cornerRadius = 10,
            width = "100%",
            height = "100%",
            halign = "left",
            valign = "top",
            interactable = false,
        },
        card,
    }

    zoomSlider = gui.Slider{
        width = "100%-90",
        height = 20,
        sliderWidth = 160,
        --the slider's own number reads the magnification as a percent.
        labelFormat = "rawpercent",
        labelWidth = 50,
        valign = "center",
        minValue = ZOOM_MIN,
        maxValue = ZOOM_MAX,
        value = 1,
        events = {
            change = function(element)
                local token = Begin()
                if token == nil then
                    return
                end
                local magnification = math.clamp(element.value, ZOOM_MIN, ZOOM_MAX)
                token.cardZoom = 1 / magnification
                ClampOffset(token)
                PaintArt(token)
            end,
            confirm = function(element)
                Commit()
            end,
        },
    }
    zoomRow = gui.Panel{
        width = "100%",
        height = ZOOM_ROW,
        flow = "horizontal",
        bmargin = ROW_GAP,
        Text{
            classes = {"heroSheetFieldLabel"},
            text = "Card zoom",
            fontSize = 13,
            width = 90,
            valign = "center",
            textWrap = false,
        },
        zoomSlider,
    }

    eyeButton, eyeLabel, eyeIcon = SmallButton{
        text = "Name shown",
        icon = "phosphor/eye.png",
        click = function()
            HeroSheetWrite.SaveAppearance(function(live)
                live.namePrivate = not live.namePrivate
            end)
            HeroSheetRefresh.Changed()
        end,
    }
    suggestButton = SmallButton{
        text = "Suggest a name",
        icon = "phosphor/dice-five.png",
        click = function()
            local token = Token()
            local name = nil
            if token ~= nil then
                pcall(function() name = HeroBuild.main.GenerateName(token.properties --[[@as character]]) end)
            end
            if name ~= nil then
                OpenName(string.sub(name, 1, NAME_LIMIT))
            end
        end,
    }

    useHeroLink = Text{
        classes = {"heroSheetFeatLink", "hoverable", "collapsed"},
        text = "",
        fontSize = 13,
        lmargin = 10,
        halign = "left",
        valign = "center",
        textWrap = false,
        data = {},
        click = function(element)
            local name = element.data.name
            if type(name) == "string" and name ~= "" then
                HeroSheetWrite.SaveAppearance(function(live)
                    live.name = name
                end)
                HeroSheetRefresh.Changed()
            end
        end,
    }
    lookNameRow = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = LOOK_NAME_ROW,
        flow = "horizontal",
        bmargin = ROW_GAP,
        Text{
            classes = {"heroSheetCardSub"},
            text = "Name for this look",
            fontSize = 13,
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        useHeroLink,
    }

    for i = 1, SWATCHES_IN_ROW do
        local hex = SWATCHES[i]
        colourSwatches[i] = gui.Panel{
            classes = {"heroSheetIconButton", "hoverable"},
            bgimage = "panels/square.png",
            bgcolor = hex,
            cornerRadius = 12,
            border = 2,
            width = 24,
            height = 24,
            rmargin = 8,
            valign = "center",
            click = function(element)
                SetPlayerColour(hex)
                --the colour is a setting, not the Hero's data.
                HeroSheetRefresh.Recheck()
            end,
        }
    end
    local moreButton = SmallButton{
        text = "More",
        click = function()
            ColourWindow()
        end,
    }
    local swatchRow = gui.Panel{
        width = "100%",
        height = 26,
        tmargin = 4,
        flow = "horizontal",
    }
    for _, swatch in ipairs(colourSwatches) do
        swatchRow:AddChild(swatch)
    end
    swatchRow:AddChild(moreButton)
    colourBlock = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = COLOUR_BLOCK,
        flow = "vertical",
        tmargin = ROW_GAP,
        FieldName("Your colour"),
        Text{
            classes = {"heroSheetCardSub"},
            text = "Your account's colour, for your rolls, pings and drawings",
            fontSize = 12,
            width = "100%",
            height = 16,
            textWrap = false,
            textOverflow = "ellipsis",
        },
        swatchRow,
    }

    under = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = 2 * UNDER_PAD + ID_ROW,
        tmargin = ART_GAP,
        pad = UNDER_PAD,
        borderBox = true,
        flow = "vertical",
        zoomRow,
        gui.Panel{
            width = "100%",
            height = ID_ROW,
            flow = "horizontal",
            bmargin = ROW_GAP,
            eyeButton,
            suggestButton,
        },
        lookNameRow,
        colourBlock,
    }

    local column
    column = HeroSheetRefresh.Block({
        width = "100%",
        height = "100%",
        flow = "vertical",
        heroSheetLayout = function(element)
            Fit()
        end,
        --the sheet hosts the column as Narrow's banner on the Appearance tab:
        --the art at the left, the panel beside it.
        heroAppearanceBanner = function(element, on)
            if on == banner then
                return
            end
            banner = on
            element.selfStyle.flow = cond(on, "horizontal", "vertical")
            element.selfStyle.height = cond(on, BANNER.H, "100%")
            box.selfStyle.width = cond(on, BANNER.ART_W, "100%")
            under.selfStyle.width = cond(on, string.format("100%%-%d", BANNER.ART_W + ART_GAP), "100%")
            under.selfStyle.tmargin = cond(on, 0, ART_GAP)
            under.selfStyle.lmargin = cond(on, ART_GAP, 0)
            under.selfStyle.valign = "top"
            --the small card takes a smaller name.
            nameLabel.selfStyle.fontSize = cond(on, 18, 26)
            nameField.selfStyle.fontSize = cond(on, 18, 26)
            local token = Token()
            if token ~= nil then
                PaintRest(token)
            end
            Fit()
        end,
        heroSheetTier = function(element)
            Fit()
        end,
        --- @param host HeroAppearanceHost
        heroAppearanceHost = function(element, host)
            hostUnits = cond(host.builder, host.columnUnits, nil)
            Fit()
        end,
        box,
        under,
    }, {
        name = "appearance art",
        signature = function(token)
            return table.concat({
                CardPortraitSignature(token), tostring(token.hasCardFraming),
                tostring(token.name), tostring(token.namePrivate),
                tostring(token.appearanceVariationIndex), tostring(token.alternateAppearanceOverride),
                tostring(HeroSheetWrite.CanWrite()), cond(ShowsColour(token), PlayerColourHex(), ""),
            }, "|")
        end,
        refresh = function(panel, token)
            --a preview in progress keeps its own values on screen.
            if snapshot ~= nil then
                return
            end
            PaintRest(token)
            PaintArt(token)
            Fit()
        end,
    })
    return column
end

----------------------------------------------------------------------
--The Looks block: the Hero's looks, then the
--looks effects give, four at a time with arrows; New look pinned at the end.
--The tiles are a pool that only grows, painted from the Hero.

--- @return Panel block
--- @return Panel plate the plate a matched Row lines up
local function BuildLooks()
    --- @type HeroAppearanceLook[]
    local looks = {}
    local first = 0
    --how many looks fit the strip (set from its width by its think).
    local shown = TILES_SHOWN
    --the shown look's place when last painted: a new selection (or a new
    --fit) pulls it into view, while an arrow's page turn leaves it be.
    --- @type nil|integer
    local pulledFor = nil
    local tiles = {}
    local strip
    local prev
    local nextArrow
    local newTile
    local hint

    --- One tile: the look's picture, its name, and for an effect's look the
    --- effect; the shown look has the "..." menu.
    --- @param slot integer
    --- @return Panel
    local function Tile(slot)
        --the art fills the tile edge to edge, rounded at the top only.
        local art = gui.Panel{
            bgimage = "panels/square.png",
            bgcolor = "#1d1915ff",
            cornerRadius = {x1 = 7, y1 = 7, x2 = 0, y2 = 0},
            width = "100%",
            height = TILE_ART_H,
            halign = "center",
            interactable = false,
        }
        local name = Text{
            classes = {"heroSheetCardText"},
            text = "",
            fontSize = 13,
            width = TILE_W - 12,
            height = 18,
            tmargin = 4,
            halign = "center",
            textAlignment = "center",
            textWrap = false,
            textOverflow = "ellipsis",
            interactable = false,
        }
        --an effect's look: a gold tag over the art.
        local from = Text{
            classes = {"heroLookFrom", "collapsed"},
            bgimage = "panels/square.png",
            cornerRadius = 7,
            text = "",
            fontSize = 11,
            bold = true,
            width = "auto",
            maxWidth = TILE_W - 36,
            height = 15,
            hpad = 6,
            textOverflow = "ellipsis",
            borderBox = true,
            x = 4,
            y = 4,
            halign = "left",
            valign = "top",
            floating = true,
            textWrap = false,
            interactable = false,
        }
        local menu = gui.Panel{
            classes = {"heroSheetKeb", "hoverable", "heroSheetKebAlways", "collapsed"},
            bgimage = "panels/square.png",
            --a dark backing: it sits over the look's picture.
            bgcolor = "#000000c0",
            border = 1,
            cornerRadius = 5,
            width = 22,
            height = 22,
            x = -4,
            y = 4,
            halign = "right",
            valign = "top",
            floating = true,
            swallowPress = true,
            click = function(element)
                local look = looks[first + slot]
                local token = Token()
                if look == nil or token == nil or not HeroSheetWrite.CanWrite() then
                    return
                end
                if look.kind == "effect" then
                    HeroSheetLists.ShowMenu(element, {
                        {text = "Revert", reason = cond(look.customised, nil, "Not changed"), click = function()
                            if look.customised then
                                token:ClearAlternateAppearance(look.key)
                                RestyleFollowers()
                                HeroSheetRefresh.Changed()
                            end
                        end},
                    }, nil, {below = true, alignRight = true})
                    return
                end
                local entries = {
                    {text = "Rename", click = function()
                        RenameWindow(token, look)
                    end},
                }
                if math.max(1, token.numAppearanceVariations or 1) > 1 then
                    entries[#entries+1] = {text = "Delete", danger = true, click = function()
                        ConfirmDelete(token, look)
                    end}
                end
                HeroSheetLists.ShowMenu(element, entries, nil, {below = true, alignRight = true})
            end,
            gui.Panel{
                classes = {"heroSheetFg"},
                bgimage = "phosphor/dots-three-bold.png",
                width = 12,
                height = 12,
                halign = "center",
                valign = "center",
                interactable = false,
            },
        }
        local tile = gui.Panel{
            classes = {"heroLookTile", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = TILE_W,
            height = TILE_H,
            halign = "left",
            pad = 1,
            borderBox = true,
            flow = "vertical",
            rmargin = TILE_GAP,
            data = {},
            linger = function(element)
                local look = looks[first + slot]
                if look ~= nil and look.customised then
                    gui.Tooltip("Customised")(element)
                end
            end,
            click = function(element)
                local look = looks[first + slot]
                if look ~= nil then
                    SwitchTo(look)
                end
            end,
            art,
            name,
            from,
            menu,
        }
        tile.data.art = art
        tile.data.name = name
        tile.data.from = from
        tile.data.menu = menu
        return tile
    end

    --- @param token CharacterToken
    local function Paint(token)
        looks = Looks(token)
        local writable = HeroSheetWrite.CanWrite()
        --the arrows only show once there are more looks than fit.
        local paged = #looks > shown
        --bring a newly shown look into view.
        for i, look in ipairs(looks) do
            if look.selected and i ~= pulledFor then
                pulledFor = i
                if i - 1 < first or i - 1 >= first + shown then
                    first = math.max(0, math.min(i - 1, #looks - shown))
                end
            end
        end
        first = math.max(0, math.min(first, math.max(0, #looks - shown)))
        for slot = 1, #tiles do
            local look = nil
            if slot <= shown then
                look = looks[first + slot]
            end
            local tile = tiles[slot]
            tile:SetClass("collapsed", look == nil)
            if look ~= nil then
                local art = tile.data.art
                local image = look.art
                --- @type nil|Vector4|{x1: number, y1: number, x2: number, y2: number}
                local rect = look.rect
                --the shown look's tile is cut like its card; the engine keeps
                --no card framing for the others, so they show their token crop.
                if look.selected then
                    image = CardArt(token) or image
                    if image ~= nil then
                        pcall(function()
                            local card = CardPortraitRect(token, CARD_ASPECT, image)
                            --the top of the card (where the face is), trimmed to
                            --the tile's shape; image rects count y up from the bottom.
                            local keep = (card.y2 - card.y1) * CARD_ASPECT * TILE_ART_H / (TILE_W - 2)
                            rect = {x1 = card.x1, y1 = card.y2 - keep, x2 = card.x2, y2 = card.y2}
                        end)
                    end
                end
                if image ~= nil and image ~= "" then
                    art.bgimage = image
                    art.selfStyle.bgcolor = "white"
                    art.selfStyle.imageRect = rect
                else
                    art.bgimage = "panels/square.png"
                    art.selfStyle.bgcolor = "#1d1915ff"
                    art.selfStyle.imageRect = nil
                end
                tile.data.name.text = look.name
                tile.data.from:SetClass("collapsed", look.kind ~= "effect")
                tile.data.from.text = string.format("From %s", look.key or "")
                tile.selfStyle.borderStyle = cond(look.kind == "effect", "dashed", "solid")
                tile:SetClass("selected", look.selected)
                tile.data.menu:SetClass("collapsed", not (look.selected and writable))
            end
        end
        prev:SetClass("collapsed", not paged)
        nextArrow:SetClass("collapsed", not paged)
        prev:SetClass("heroSheetOff", first <= 0)
        nextArrow:SetClass("heroSheetOff", first + shown >= #looks)
        local count = math.max(1, token.numAppearanceVariations or 1)
        newTile:SetClass("heroSheetOff", count >= MAX_LOOKS or not writable)
        newTile.data.tip = cond(count >= MAX_LOOKS, "Up to 8 looks.", nil)
        --an effect's look says where it comes from.
        local effect = nil
        for _, look in ipairs(looks) do
            if look.kind == "effect" and look.selected then
                effect = look
            end
        end
        if effect ~= nil then
            hint.text = string.format("From the %s effect: it ends with the effect. Revert puts back the effect's own look.", effect.key)
        else
            hint.text = "Art, frame, name and anthem belong to the look you pick."
        end
    end

    --- @param icon string
    --- @param step integer
    --- @return Panel
    local function Arrow(icon, step)
        return gui.Panel{
            classes = {"heroSheetSmallButton", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 5,
            width = ARROW_W,
            height = 56,
            rmargin = TILE_GAP,
            halign = "left",
            valign = "center",
            click = function(element)
                if element:HasClass("heroSheetOff") then
                    return
                end
                first = math.max(0, math.min(first + step, #looks - shown))
                local token = Token()
                if token ~= nil then
                    Paint(token)
                end
            end,
            gui.Panel{
                classes = {"heroSheetFg"},
                bgimage = icon,
                width = 12,
                height = 12,
                halign = "center",
                valign = "center",
                interactable = false,
            },
        }
    end

    prev = Arrow("phosphor/caret-left-bold.png", -1)
    nextArrow = Arrow("phosphor/caret-right-bold.png", 1)
    for slot = 1, TILES_SHOWN do
        tiles[slot] = Tile(slot)
    end

    --The strip's width sets how many looks fit (the arrows' room kept, so
    --the count holds as they come and go): tiles are added up to it, never
    --removed. 100 units tall: rendered sizes are pixels, widths are units.
    local probe = gui.Panel{
        width = 1,
        height = 100,
        floating = true,
        interactable = false,
    }
    --- @param element Panel the strip
    local function FitCount(element)
        local perUnit = probe.renderedHeight / 100
        if perUnit <= 0 or element.renderedWidth <= 0 then
            return
        end
        local room = element.renderedWidth / perUnit - TILE_W - 2 * (ARROW_W + TILE_GAP)
        local fit = math.clamp(math.floor(room / (TILE_W + TILE_GAP)), 1, MAX_LOOKS)
        if fit == shown then
            return
        end
        shown = fit
        if #tiles < fit then
            for slot = #tiles + 1, fit do
                tiles[slot] = Tile(slot)
            end
            local children = {probe, prev}
            for _, tile in ipairs(tiles) do
                children[#children+1] = tile
            end
            children[#children+1] = nextArrow
            children[#children+1] = newTile
            element.children = children
        end
        pulledFor = nil
        local token = Token()
        if token ~= nil then
            Paint(token)
        end
    end

    newTile = gui.Panel{
        classes = {"heroSheetTitleAdd", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        borderStyle = "dashed",
        cornerRadius = 8,
        width = TILE_W,
        height = TILE_H,
        halign = "left",
        flow = "vertical",
        data = {},
        hover = function(element)
            if element.data.tip ~= nil then
                gui.Tooltip(element.data.tip)(element)
            end
        end,
        click = function(element)
            local token = Token()
            if token ~= nil and not element:HasClass("heroSheetOff") then
                NewLookWindow(token)
            end
        end,
        gui.Panel{
            classes = {"heroSheetTitleAddIcon"},
            bgimage = "phosphor/plus-bold.png",
            width = 18,
            height = 18,
            halign = "center",
            tmargin = 38,
            interactable = false,
        },
        Text{
            classes = {"heroSheetTitleAddText"},
            text = "New look",
            fontSize = 12,
            width = "100%",
            height = 16,
            tmargin = 8,
            textAlignment = "center",
            textWrap = false,
            interactable = false,
        },
    }

    strip = gui.Panel{
        width = "100%",
        height = TILE_H,
        flow = "horizontal",
        --the room changes with a resize, Font Size or the row pairing.
        thinkTime = 0.25,
        think = FitCount,
        probe,
        prev,
    }
    for _, tile in ipairs(tiles) do
        strip:AddChild(tile)
    end
    strip:AddChild(nextArrow)
    strip:AddChild(newTile)

    local block
    block, hint = Block("Looks", "Art, frame, name and anthem belong to the look you pick.", strip)
    local blockPanel = HeroSheetRefresh.Block({
        width = "100%",
        height = "auto",
        flow = "vertical",
        block,
    }, {
        name = "appearance looks",
        signature = function(token)
            local parts = {
                tostring(token.numAppearanceVariations), tostring(token.appearanceVariationIndex),
                tostring(token.alternateAppearanceOverride), table.concat(LookNames(token), "/"),
                CardPortraitSignature(token), tostring(HeroSheetWrite.CanWrite()),
            }
            pcall(function()
                local effects = token.properties:GetAlternateAppearances()
                if effects ~= nil then
                    parts[#parts+1] = table.concat(table.keys(effects), "/")
                end
            end)
            return table.concat(parts, "|")
        end,
        refresh = function(panel, token)
            Paint(token)
        end,
    })
    return blockPanel, block
end

----------------------------------------------------------------------
--2 Fit it: the token
--crop with Zoom (the wheel too), Pop out of the frame and Circle, then the
--Frame, Background and Mount lines and Reset placement. Drags and sliders
--preview on the token locally and upload once on release, as the art does.

--- An image's name in its library, or nil: built-in frames and backgrounds
--- have none, an upload has its file's name.
--- @param id nil|string
--- @return nil|string
local function ImageName(id)
    if id == nil or id == "" then
        return nil
    end
    local asset = assets.imagesTable[id]
    local name = asset ~= nil and asset.description or nil
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return name
end

--- True when the look's picture came from the Popout avatars library: art
--- made to rise above the frame, with a transparent background.
--- @param token CharacterToken
--- @return boolean
local function PopoutArt(token)
    local asset = nil
    if token.portrait ~= nil and token.portrait ~= "" then
        asset = assets.imagesTable[token.portrait]
    end
    return asset ~= nil and asset.imageType == "AvatarPopout"
end

--- True when this engine stores Pop out of the frame on each look. Older
--- engines read the field as nil.
--- @param token CharacterToken
--- @return boolean
local function HasPopoutMode(token)
    return token.popoutMode ~= nil
end

--- The Mount line's summary: "Two saddles . carries 1S".
--- @param token CharacterToken
--- @return string
local function MountSummary(token)
    local count = token.saddles or 0
    if count <= 0 then
        return "Not mountable"
    end
    local words = SADDLE_WORDS[count] or tostring(count)
    --"\xC2\xB7" is a middle dot: Lua source stays ASCII.
    return string.format("%s %s \xC2\xB7 carries %s", words, cond(count == 1, "saddle", "saddles"), tostring(token.saddleSize))
end

--- The frame's tint on a panel showing the frame, as the token draws it.
--- @param panel Panel
--- @param token CharacterToken
local function TintFrame(panel, token)
    panel.selfStyle.hueshift = token.portraitFrameHueShift or 0
    panel.selfStyle.saturation = token.portraitFrameSaturation or 1
    panel.selfStyle.brightness = token.portraitFrameBrightness or 1
end

--- True when the frame carries a tint (the default is no tint).
--- @param token CharacterToken
--- @return boolean
local function Tinted(token)
    return math.abs((token.portraitFrameHueShift or 0)) > 0.001
        or math.abs((token.portraitFrameSaturation or 1) - 1) > 0.001
        or math.abs((token.portraitFrameBrightness or 1) - 1) > 0.001
end

--- The look's token as the map draws it: the picture at its crop inside the
--- frame; a popout token has a disc (background and frame) under the whole
--- picture, sized by Circle (laid out as the engine draws a popout token).
--- @param size number
--- @return Panel panel
--- @return fun(token: CharacterToken) paint
--- @return fun(token: CharacterToken): number footprint the token's own square, in units: the disc on a popout token
local function TokenPreview(size)
    local background = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "#2a2520ff",
        width = "100%",
        height = "100%",
        interactable = false,
    }
    local discFrame = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "white",
        width = "100%",
        height = "100%",
        floating = true,
        interactable = false,
    }
    local disc = gui.Panel{
        classes = {"collapsed"},
        width = size,
        height = size,
        halign = "center",
        valign = "center",
        floating = true,
        interactable = false,
        background,
        discFrame,
    }
    local art = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "#1d1915ff",
        width = "100%",
        height = "100%",
        floating = true,
        interactable = false,
    }
    local frameTop = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "white",
        width = "100%",
        height = "100%",
        floating = true,
        interactable = false,
    }
    local panel = gui.Panel{
        width = size,
        height = size,
        flow = "none",
        disc,
        art,
        frameTop,
    }

    --- @param token CharacterToken
    --- @return number
    local function Footprint(token)
        if token.popoutPortrait == true then
            return math.floor(size * (token.popoutScale or 1) * POPOUT_FRAME_SHARE + 0.5)
        end
        return size
    end

    --- @param token CharacterToken
    local function Paint(token)
        local frame = token.portraitFrame
        local framed = frame ~= nil and frame ~= ""
        local popout = token.popoutPortrait == true
        if token.portrait ~= nil and token.portrait ~= "" then
            art.bgimage = token.portrait
            art.selfStyle.bgcolor = "white"
            --a popout token draws its whole picture: its crop applies only
            --to a framed token.
            art.selfStyle.imageRect = cond(popout, {x1 = 0, y1 = 0, x2 = 1, y2 = 1}, token.portraitRect)
        else
            art.bgimage = "panels/square.png"
            art.selfStyle.bgcolor = "#1d1915ff"
            art.selfStyle.imageRect = nil
        end
        disc:SetClass("collapsed", not popout)
        frameTop:SetClass("collapsed", popout or not framed)
        if popout then
            art.bgimageTokenMask = nil
            local footprint = Footprint(token)
            disc.selfStyle.width = footprint
            disc.selfStyle.height = footprint
            local back = token.portraitBackground
            if back ~= nil and back ~= "" then
                background.bgimage = back
                background.selfStyle.bgcolor = "white"
            else
                background.bgimage = "panels/square.png"
                background.selfStyle.bgcolor = "#2a2520ff"
            end
            --without a frame the disc is a plain circle.
            background.bgimageTokenMask = cond(framed, frame, nil)
            background.selfStyle.cornerRadius = cond(framed, 0, footprint / 2)
            discFrame:SetClass("collapsed", not framed)
            if framed then
                discFrame.bgimage = frame
                TintFrame(discFrame, token)
            end
        else
            art.bgimageTokenMask = cond(framed, frame, nil)
            if framed then
                frameTop.bgimage = frame
                TintFrame(frameTop, token)
            end
        end
    end

    return panel, Paint, Footprint
end

--- @class HeroAppearanceGridArgs
--- @field library string the image library to show
--- @field height number the grid's height; it scrolls past that
--- @field none string the no-image tile's words
--- @field follow nil|string a tile before it that picks "#follow" (a summon's Same as <Hero>)
--- @field upload nil|HeroAppearanceGridUpload the upload tile's words, if it has one
--- @field current fun(): nil|string the image in use now
--- @field pick fun(id: string) a tile was clicked ("" for none)
--- @field uploadClick nil|fun() the upload tile was clicked
--- @field mask nil|fun(): nil|string a frame to cut each picture to, as the token shows it (a circle without one)

--- @class HeroAppearanceGridUpload
--- @field title string
--- @field sub string

--- A grid of a library's pictures to pick from (the Token frame and
--- Background windows). Its slots are built once and painted after a pick;
--- the first is the upload tile (if any), then the no-image tile.
--- @param args HeroAppearanceGridArgs
--- @return Panel panel
--- @return fun() paint
local function ImageGrid(args)
    local all = dmhub.SearchImages("", args.library)
    local slotCount = #all + 1 + cond(args.upload ~= nil, 1, 0) + cond(args.follow ~= nil, 1, 0)
    local rows = {}
    local slots = {}
    --- @type string[]
    local shown = {}

    --- @param slot integer
    --- @return Panel
    local function Slot(slot)
        local image = gui.Panel{
            bgimage = "panels/square.png",
            bgcolor = "white",
            width = PICK_TILE - 12,
            height = PICK_TILE - 12,
            halign = "center",
            valign = "center",
            interactable = false,
        }
        local title = Text{
            classes = {"heroSheetCardText"},
            text = "",
            fontSize = 12.5,
            width = PICK_TILE - 12,
            height = 34,
            textAlignment = "center",
            textWrap = true,
            halign = "center",
            interactable = false,
        }
        local sub = Text{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 11,
            width = PICK_TILE - 12,
            height = 28,
            textAlignment = "center",
            textWrap = true,
            halign = "center",
            interactable = false,
        }
        local words = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            valign = "center",
            interactable = false,
            title,
            sub,
        }
        local tile = gui.Panel{
            classes = {"heroLookTile", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = PICK_TILE,
            height = PICK_TILE,
            rmargin = PICK_GAP,
            halign = "left",
            flow = "none",
            data = {},
            linger = function(element)
                local name = ImageName(shown[slot])
                if name ~= nil then
                    gui.Tooltip(name)(element)
                end
            end,
            click = function(element)
                local id = shown[slot]
                if id == "#upload" then
                    if args.uploadClick ~= nil then
                        args.uploadClick()
                    end
                elseif id ~= nil then
                    args.pick(id)
                end
            end,
            image,
            words,
        }
        tile.data.image = image
        tile.data.words = words
        tile.data.title = title
        tile.data.sub = sub
        return tile
    end

    for i = 1, slotCount do
        slots[i] = Slot(i)
        local rowIndex = math.floor((i - 1) / PICK_COLUMNS) + 1
        if rows[rowIndex] == nil then
            rows[rowIndex] = gui.Panel{
                width = "100%",
                height = PICK_TILE,
                flow = "horizontal",
                bmargin = PICK_GAP,
            }
        end
        rows[rowIndex]:AddChild(slots[i])
    end

    local grid = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        children = rows,
    }
    local holder = gui.Panel{
        width = "100%",
        height = args.height,
        flow = "vertical",
        vscroll = math.ceil(slotCount / PICK_COLUMNS) * (PICK_TILE + PICK_GAP) > args.height,
        grid,
    }

    local function Paint()
        shown = {}
        if args.upload ~= nil then
            shown[#shown+1] = "#upload"
        end
        if args.follow ~= nil then
            shown[#shown+1] = "#follow"
        end
        shown[#shown+1] = ""
        for _, id in ipairs(all) do
            shown[#shown+1] = id
        end
        local current = args.current() or ""
        for i, tile in ipairs(slots) do
            local id = shown[i]
            tile:SetClass("collapsed", id == nil)
            if id ~= nil then
                local special = id == "" or id == "#upload" or id == "#follow"
                tile.data.image:SetClass("collapsed", special)
                tile.data.words:SetClass("collapsed", not special)
                tile:SetClass("selected", id == current)
                tile.selfStyle.borderStyle = cond(special, "dashed", "solid")
                if id == "#upload" and args.upload ~= nil then
                    tile.data.title.text = args.upload.title
                    tile.data.sub.text = args.upload.sub
                elseif id == "#follow" then
                    tile.data.title.text = args.follow or ""
                    tile.data.sub.text = ""
                elseif id == "" then
                    tile.data.title.text = args.none
                    tile.data.sub.text = ""
                else
                    tile.data.image.bgimage = id
                    if args.mask ~= nil then
                        local frame = args.mask()
                        local framed = frame ~= nil and frame ~= ""
                        tile.data.image.bgimageTokenMask = cond(framed, frame, nil)
                        tile.data.image.selfStyle.cornerRadius = cond(framed, 0, (PICK_TILE - 12) / 2)
                    end
                end
            end
        end
        for rowIndex, row in ipairs(rows) do
            row:SetClass("collapsed", shown[(rowIndex - 1) * PICK_COLUMNS + 1] == nil)
        end
    end

    return holder, Paint
end

--- A tint slider in the Token frame window: previews on change, saves on
--- release.
--- @param text string
--- @param field "portraitFrameHueShift"|"portraitFrameSaturation"|"portraitFrameBrightness"
--- @param preview fun(field: string, value: number)
--- @param commit fun()
--- @return Panel row
--- @return Panel slider
local function TintSlider(text, field, preview, commit)
    local slider = gui.Slider{
        width = "100%-84",
        height = 20,
        sliderWidth = 90,
        labelFormat = "percent",
        labelWidth = 44,
        valign = "center",
        minValue = 0,
        maxValue = 1,
        value = 0,
        events = {
            change = function(element)
                preview(field, element.value)
            end,
            confirm = function(element)
                commit()
            end,
        },
    }
    local row = gui.Panel{
        width = "100%",
        height = 26,
        flow = "horizontal",
        Text{
            classes = {"heroSheetCardText"},
            text = text,
            fontSize = 13,
            width = 84,
            valign = "center",
            textWrap = false,
        },
        slider,
    }
    return row, slider
end

--- Upload a frame into this game's frames, then use it (Upload a frame).
--- @param use fun(id: string)
local function UploadFrame(use)
    if not HeroSheetWrite.CanWrite() then
        return
    end
    dmhub.OpenFileDialog{
        id = "IconImages",
        extensions = {"png", "webp"},
        multiFiles = false,
        open = function(path)
            local failed = false
            local token = Token()
            local charid = token ~= nil and token.charid or nil
            local assetid = assets:UploadImageAsset{
                path = path,
                description = FileDrops.BaseName(path),
                imageType = "AvatarFrame",
                error = function(text)
                    failed = true
                    gui.ModalMessage{
                        title = "Error loading image: " .. text,
                        message = text,
                    }
                end,
                upload = function(imageid)
                end,
            }
            --the frame is usable once it is in the image table.
            local function Poll()
                if mod.unloaded or failed or assetid == nil then
                    return
                end
                if assets.imagesTable[assetid] ~= nil then
                    --only onto the Hero it was uploaded for, if the sheet
                    --has switched Hero meanwhile.
                    local live = Token()
                    if live ~= nil and live.charid == charid then
                        use(assetid)
                    end
                else
                    dmhub.Schedule(0.1, Poll)
                end
            end
            dmhub.Schedule(0.1, Poll)
        end,
    }
end

--- Token frame: the frames, an upload, No frame; the look's
--- token beside them with the tint. Picks save as you go.
--- @param token CharacterToken
local function FrameWindow(token)
    local paintGrid
    local paintToken
    --- @type nil|string
    local snapshot = nil
    local sliders = {}

    local function Repaint()
        local live = Token()
        if live ~= nil then
            paintToken(live)
            for field, slider in pairs(sliders) do
                slider.value = live[field] or cond(field == "portraitFrameHueShift", 0, 1)
            end
        end
    end

    --- @param id string
    local function Pick(id)
        HeroSheetWrite.SaveAppearance(function(live)
            live.portraitFrame = id
        end)
        RestyleFollowers()
        HeroSheetRefresh.Changed()
        paintGrid()
        Repaint()
    end

    local grid
    grid, paintGrid = ImageGrid{
        library = "AvatarFrame",
        height = 440,
        none = "No frame",
        upload = {title = "Upload a frame", sub = "png with a clear middle"},
        current = function()
            local live = Token()
            return live ~= nil and live.portraitFrame or nil
        end,
        pick = Pick,
        uploadClick = function()
            UploadFrame(Pick)
        end,
    }

    local preview
    preview, paintToken = TokenPreview(150)

    --- @param field string
    --- @param value number
    local function PreviewTint(field, value)
        local live = Token()
        if live == nil or not HeroSheetWrite.CanWrite() then
            return
        end
        if snapshot == nil then
            local _, shot = HeroSheetWrite.PreviewAppearance()
            snapshot = shot
        end
        live[field] = value
        paintToken(live)
        --the map's token follows before the upload.
        live:RefreshAppearanceLocally()
    end
    local function CommitTint()
        local shot = snapshot
        snapshot = nil
        if shot ~= nil then
            HeroSheetWrite.CommitAppearance(shot)
            RestyleFollowers()
            HeroSheetRefresh.Changed()
        end
    end

    local hueRow, saturationRow, brightnessRow
    hueRow, sliders.portraitFrameHueShift = TintSlider("Hue", "portraitFrameHueShift", PreviewTint, CommitTint)
    saturationRow, sliders.portraitFrameSaturation = TintSlider("Saturation", "portraitFrameSaturation", PreviewTint, CommitTint)
    brightnessRow, sliders.portraitFrameBrightness = TintSlider("Brightness", "portraitFrameBrightness", PreviewTint, CommitTint)

    local resetLink = Text{
        classes = {"heroSheetFeatLink", "hoverable"},
        text = "Reset",
        fontSize = 13,
        halign = "right",
        valign = "center",
        textWrap = false,
        click = function(element)
            HeroSheetWrite.SaveAppearance(function(live)
                live.portraitFrameHueShift = 0
                live.portraitFrameSaturation = 1
                live.portraitFrameBrightness = 1
            end)
            RestyleFollowers()
            HeroSheetRefresh.Changed()
            Repaint()
        end,
    }

    local side = gui.Panel{
        width = 220,
        height = "auto",
        flow = "vertical",
        halign = "right",
        valign = "top",
        FieldName("On your token"),
        gui.Panel{
            width = "100%",
            height = 160,
            flow = "none",
            preview,
        },
        gui.Panel{
            width = "100%",
            height = 18,
            tmargin = 12,
            flow = "horizontal",
            Text{
                classes = {"heroSheetFieldLabel"},
                text = "TINT",
                fontSize = 11.5,
                bold = true,
                halign = "left",
                valign = "center",
                textWrap = false,
            },
            resetLink,
        },
        hueRow,
        saturationRow,
        brightnessRow,
        Text{
            classes = {"heroSheetCardSub"},
            text = "The tint previews here and on the map.",
            fontSize = 12,
            width = "100%",
            height = 32,
            tmargin = 6,
            textWrap = true,
        },
    }

    local body = gui.Panel{
        width = "100%",
        height = 440,
        flow = "horizontal",
        gui.Panel{
            width = PICK_COLUMNS * (PICK_TILE + PICK_GAP) + 10,
            height = "100%",
            flow = "vertical",
            halign = "left",
            valign = "top",
            grid,
        },
        side,
    }

    paintGrid()
    Repaint()
    HeroSheetWindow.ShowDialog{
        title = "Token frame",
        subtitle = token.name,
        width = PICK_COLUMNS * (PICK_TILE + PICK_GAP) + 10 + 220 + 40,
        bodyHeight = 440,
        body = body,
        onDone = function()
            CommitTint()
        end,
    }
end

--- @class HeroAppearanceBackgroundArgs
--- @field subtitle string whose background it is
--- @field current fun(): nil|string the background in use now
--- @field frame fun(): nil|string the frame each background is cut to
--- @field pick fun(id: string) a background was picked ("" for None)

--- Background: what shows behind a popout token's art, inside
--- its frame. Picks save as you go. The Hero's token, or a summon's.
--- @param args HeroAppearanceBackgroundArgs
local function BackgroundWindow(args)
    local paintGrid
    local grid
    grid, paintGrid = ImageGrid{
        library = "AvatarBackground",
        height = 330,
        none = "None",
        current = args.current,
        --each background cut to the frame, as it shows behind the art.
        mask = args.frame,
        pick = function(id)
            args.pick(id)
            paintGrid()
        end,
    }
    paintGrid()
    HeroSheetWindow.ShowDialog{
        title = "Background",
        subtitle = args.subtitle,
        width = PICK_COLUMNS * (PICK_TILE + PICK_GAP) + 40,
        --the note, its gap and the grid below.
        bodyHeight = 22 + 10 + 330,
        body = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            Text{
                classes = {"heroSheetCardText"},
                text = "Shows behind the art inside the frame.",
                fontSize = 14,
                width = "100%",
                height = 22,
                bmargin = 10,
            },
            grid,
        },
        onDone = function() end,
    }
end

--- Mount: a fixed-size popover under Change, so Fit it never
--- changes height. Each choice saves at once.
--- @param anchor Panel
local function MountPopover(anchor)
    local token = Token()
    if token == nil then
        return
    end
    local saddleOptions = {{id = "0", text = "Not mountable"}}
    for i, word in ipairs(SADDLE_WORDS) do
        saddleOptions[#saddleOptions+1] = {id = tostring(i), text = string.format("%s %s", word, cond(i == 1, "saddle", "saddles"))}
    end
    local sizeOptions = {}
    for _, size in ipairs(creature.sizes) do
        sizeOptions[#sizeOptions+1] = {id = tostring(size), text = tostring(size)}
    end
    local carry
    local saddles = gui.Dropdown{
        classes = {"heroSheetField"},
        width = "100%",
        height = 30,
        options = saddleOptions,
        idChosen = tostring(token.saddles or 0),
        change = function(element)
            ---@cast element Dropdown
            local count = tonumber(element.idChosen) or 0
            HeroSheetWrite.SaveAppearance(function(live)
                live.saddles = count
            end)
            carry:SetClass("heroSheetDisabled", count <= 0)
            HeroSheetRefresh.Changed()
        end,
    }
    carry = gui.Dropdown{
        classes = {"heroSheetField", cond((token.saddles or 0) <= 0, "heroSheetDisabled", nil)},
        width = "100%",
        height = 30,
        options = sizeOptions,
        idChosen = tostring(token.saddleSize),
        change = function(element)
            ---@cast element Dropdown
            local size = element.idChosen
            HeroSheetWrite.SaveAppearance(function(live)
                live.saddleSize = tostring(size)
            end)
            HeroSheetRefresh.Changed()
        end,
    }
    HeroSheetWindow.ShowPopup{
        width = 280,
        --the content's padding and its children below, top to bottom.
        height = 12 + 20 + 8 + 18 + 30 + 10 + 18 + 30 + 10 + 34 + 12,
        anchor = anchor,
        below = true,
        content = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            pad = 12,
            borderBox = true,
            Text{
                classes = {"heroSheetCardStrong"},
                text = "MOUNT",
                fontSize = 14,
                bold = true,
                height = 20,
                halign = "left",
                bmargin = 8,
            },
            FieldName("Saddles"),
            saddles,
            gui.Panel{width = "100%", height = 10},
            FieldName("Can carry"),
            carry,
            Text{
                classes = {"heroSheetCardSub"},
                text = "Drag the saddles on the token to place the riders.",
                fontSize = 12.5,
                width = "100%",
                height = 34,
                tmargin = 10,
                textWrap = true,
            },
        },
    }
end

--- A numbered step: its number on a gold disc, its name, and under them
--- what it does.
--- @param number integer
--- @param title string
--- @param hint string
--- @param content Panel
--- @param extra? Panel at the header's right (Choose the art's Token builder link)
--- @return Panel step
--- @return Panel hintLabel
local function Step(number, title, hint, content, extra)
    local hintLabel = Text{
        classes = {"heroSheetCardSub"},
        text = hint,
        fontSize = 12.5,
        width = "100%",
        tmargin = 6,
        bmargin = 10,
        textWrap = true,
    }
    local step = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = "auto",
        flow = "vertical",
        pad = 12,
        borderBox = true,
        gui.Panel{
            width = "100%",
            height = 22,
            flow = "horizontal",
            Text{
                classes = {"heroAppearStepNumber"},
                bgimage = "panels/square.png",
                cornerRadius = 11,
                text = tostring(number),
                fontSize = 12.5,
                bold = true,
                width = 22,
                height = 22,
                textAlignment = "center",
                halign = "left",
                valign = "center",
            },
            Text{
                classes = {"heroSheetCardStrong"},
                text = string.upper(title),
                fontSize = 14,
                bold = true,
                lmargin = 8,
                halign = "left",
                valign = "center",
                textWrap = false,
            },
            extra,
        },
        hintLabel,
        content,
    }
    return step, hintLabel
end

--- One of Fit it's lines (Frame, Background, Mount): its name, a thumbnail,
--- the value and a quieter note, then its button under them.
--- @param title string
--- @param buttonText string
--- @param click fun(element: Panel)
--- @return Panel line
--- @return {thumb: Panel, value: Panel, note: Panel, extra: Panel, button: Panel}
local function FitLine(title, buttonText, click)
    local thumb = gui.Panel{
        classes = {"collapsed"},
        bgimage = "panels/square.png",
        bgcolor = "white",
        width = 22,
        height = 22,
        rmargin = 6,
        halign = "left",
        valign = "center",
        interactable = false,
    }
    local value = Text{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 14,
        bold = true,
        width = "auto",
        maxWidth = 230,
        height = 20,
        rmargin = 8,
        halign = "left",
        valign = "center",
        textWrap = false,
        textOverflow = "ellipsis",
    }
    local note = Text{
        classes = {"heroSheetCardSub"},
        text = "",
        fontSize = 12,
        width = "auto",
        height = 18,
        halign = "left",
        valign = "center",
        textWrap = false,
    }
    local extra = Text{
        classes = {"heroSheetCardSub", "collapsed"},
        text = "",
        fontSize = 12,
        width = "100%",
        height = 16,
        textWrap = false,
        textOverflow = "ellipsis",
    }
    local button = SmallButton{
        text = buttonText,
        click = click,
    }
    local line = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        bmargin = 14,
        gui.Panel{
            width = "100%",
            height = 24,
            flow = "horizontal",
            Text{
                classes = {"heroSheetFieldLabel"},
                text = string.upper(title),
                fontSize = 11.5,
                bold = true,
                width = "auto",
                rmargin = 8,
                halign = "left",
                valign = "center",
                textWrap = false,
            },
            thumb,
            value,
            note,
        },
        extra,
        gui.Panel{
            width = "100%",
            height = 26,
            tmargin = 4,
            flow = "horizontal",
            button,
        },
    }
    return line, {thumb = thumb, value = value, note = note, extra = extra, button = button}
end

--- Fit it's token beside its lines when Fit it has room, else the lines
--- under the token, so the frame's name never cuts off.
--- @param tokenColumn Panel
--- @param lines Panel
--- @return fun(element: Panel) think for the panel holding them
local function FitItAdapt(tokenColumn, lines)
    local beside = true
    return function(element)
        local renderedWidth = element.renderedWidth
        if renderedWidth == nil or renderedWidth <= 0 then
            return
        end
        --about 560 units of plate: its content, less the padding.
        local want = renderedWidth / math.max(0.01, HeroSheetWindow.Zoom()) >= 536
        if want == beside then
            return
        end
        beside = want
        element.selfStyle.flow = cond(want, "horizontal", "vertical")
        tokenColumn.selfStyle.halign = cond(want, "left", "center")
        lines.selfStyle.width = cond(want, string.format("100%%-%d", TOKEN_COLUMN + TOKEN_GAP), "100%")
        lines.selfStyle.halign = cond(want, "right", "left")
        lines.selfStyle.tmargin = cond(want, 18, 12)
    end
end

--Fit it's parts that the Hero's look and a summon's build the same way, in
--one table: this file is near Lua's cap on locals.
local FitParts = {}

--- A slider row under the token: its name, then the slider.
--- @param text string
--- @param slider Panel
--- @param tip nil|string
--- @return Panel
function FitParts.SliderRow(text, slider, tip)
    return gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "clear",
        width = "100%",
        height = 26,
        tmargin = 6,
        flow = "horizontal",
        linger = function(element)
            if tip ~= nil then
                gui.Tooltip(tip)(element)
            end
        end,
        Text{
            classes = {"heroSheetCardText"},
            text = text,
            fontSize = 13,
            width = 50,
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        slider,
    }
end

--- The "Drag to move" tag over the token; the caller shows it when the
--- picture can move.
--- @return Panel
function FitParts.DragTag()
    return Text{
        classes = {"heroSheetCardText", "heroAppearDragTag", "collapsed"},
        text = "Drag to move",
        fontSize = 12,
        bgimage = "panels/square.png",
        bgcolor = "#000000b0",
        cornerRadius = 4,
        hpad = 6,
        vpad = 2,
        borderBox = true,
        halign = "center",
        valign = "top",
        tmargin = 4,
        floating = true,
        textWrap = false,
        interactable = false,
    }
end

--- Pop out of the frame: its check row, the row's tick, and the hint under
--- it for art made to pop out that shows inside the frame.
--- @param click fun(element: Panel)
--- @return Panel row
--- @return Panel mark
--- @return Panel hint
function FitParts.PopoutCheck(click)
    local popoutMark = gui.Panel{
        classes = {"heroSheetCheckMark", "collapsed"},
        bgimage = "phosphor/check-bold.png",
        width = 11,
        height = 11,
        halign = "center",
        valign = "center",
    }
    local popoutRow = gui.Panel{
        classes = {"hoverable"},
        bgimage = "panels/square.png",
        bgcolor = "clear",
        width = "100%",
        height = 22,
        tmargin = 8,
        flow = "horizontal",
        click = click,
        gui.Panel{
            classes = {"heroSheetCheck"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 3,
            width = 14,
            height = 14,
            halign = "left",
            valign = "center",
            interactable = false,
            popoutMark,
        },
        Text{
            classes = {"heroSheetCardText"},
            text = "Pop out of the frame",
            fontSize = 13,
            lmargin = 8,
            halign = "left",
            valign = "center",
            textWrap = false,
            interactable = false,
        },
    }
    local popoutHint = Text{
        classes = {"heroSheetCardSub", "collapsed"},
        text = "This picture is made to pop out. Zoom in to fill the frame.",
        fontSize = 12,
        width = "100%",
        height = 32,
        tmargin = 4,
        textWrap = true,
    }
    return popoutRow, popoutMark, popoutHint
end

--- The token's column: its heading, the token, and the controls under it.
--- @param tokenBox Panel
--- @param zoomRow Panel
--- @param popoutRow Panel
--- @param popoutHint Panel
--- @param circleRow Panel
--- @return Panel
function FitParts.TokenColumn(tokenBox, zoomRow, popoutRow, popoutHint, circleRow)
    return gui.Panel{
        width = TOKEN_COLUMN,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        Text{
            classes = {"heroSheetFieldLabel"},
            text = "TOKEN",
            fontSize = 11.5,
            bold = true,
            width = "100%",
            height = 18,
            textAlignment = "center",
            textWrap = false,
        },
        tokenBox,
        zoomRow,
        popoutRow,
        popoutHint,
        circleRow,
    }
end

--- Zoom after one wheel event over the token. A typed value already outside
--- the range is never snapped back in.
--- @param current number
--- @param delta number the wheel's delta
--- @return number
function FitParts.WheelZoom(current, delta)
    local zoom = current - TOKEN_WHEEL_STEP * Notches(delta)
    if delta > 0 then
        return math.max(zoom, math.min(current, TOKEN_ZOOM_MIN))
    end
    return math.min(zoom, math.max(current, TOKEN_ZOOM_MAX))
end

--- A plate in a plain holder, as BuildBody's Row matches them.
--- @param plate Panel
--- @return Panel
function FitParts.Hold(plate)
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        plate,
    }
end

--- @return Panel block
--- @return Panel plate the plate a matched Row lines up
local function BuildFitIt()
    --the drag, slider or wheel spin in progress: the snapshot to upload with.
    --- @type nil|string
    local snapshot = nil
    --- @type nil|{anchor: Vector2, offset: Vector2, w: number, h: number}
    local drag = nil
    local wheelSerial = 0
    local saddleMarks = {}
    local zoomSlider
    local zoomRow
    local circleRow
    local circleSlider
    local popoutRow
    local popoutMark
    local popoutHint
    local frameLine, frameParts
    local backgroundLine, backgroundParts
    local mountLine, mountParts
    local resetButton
    local saddleLayer
    local dragTag

    local preview, paintPreview, footprintOf = TokenPreview(TOKEN_BOX)

    --- @return nil|CharacterToken
    local function Begin()
        local token = Token()
        if token == nil or not HeroSheetWrite.CanWrite() then
            return nil
        end
        if snapshot == nil then
            local live, shot = HeroSheetWrite.PreviewAppearance()
            if live == nil or shot == nil then
                return nil
            end
            token = live
            snapshot = shot
            --a look with no card framing cuts its card from the token's crop,
            --so give it the crop it shows now: the card stays put.
            if HasCardFields(token) and not token.hasCardFraming then
                local offset = token.portraitOffset or core.Vector2(0, 0)
                local zoom = token.portraitZoom
                if type(zoom) ~= "number" or zoom <= 0 then
                    zoom = 1
                end
                token.cardZoom = zoom
                token.cardOffset = core.Vector2(offset.x, offset.y)
            end
        end
        return token
    end

    local function Commit()
        local shot = snapshot
        snapshot = nil
        drag = nil
        if shot ~= nil then
            HeroSheetWrite.CommitAppearance(shot)
            HeroSheetRefresh.Changed()
        end
    end

    --- The saddles on the token: the map's saddle markers, sized to the
    --- riders' size against this creature's, placed from the centre in token
    --- widths.
    --- @param token CharacterToken
    local function PaintSaddles(token)
        local count = math.max(0, token.saddles or 0)
        local footprint = footprintOf(token)
        saddleLayer.selfStyle.width = footprint
        saddleLayer.selfStyle.height = footprint
        local ratio = 1
        pcall(function()
            ratio = dmhub.CreatureSizeToTokenScale(token.saddleSize) / dmhub.CreatureSizeToTokenScale(token.creatureSize)
        end)
        local positions = token.saddlePositions or {}
        for i = #saddleMarks + 1, count do
            local saddleIndex = i
            local mark
            mark = gui.Panel{
                classes = {"hoverable"},
                bgimage = "panels/horse-saddle.png",
                bgcolor = "white",
                width = 30,
                height = 30,
                halign = "left",
                valign = "top",
                floating = true,
                swallowPress = true,
                data = {},
                linger = function(element)
                    if HeroSheetWrite.CanWrite() then
                        gui.Tooltip("Drag to place this saddle")(element)
                    end
                end,
                press = function(element)
                    local live = Begin()
                    if live == nil or saddleLayer.mousePoint == nil then
                        return
                    end
                    local pos = (live.saddlePositions or {})[saddleIndex]
                    if pos == nil then
                        return
                    end
                    element.data.anchor = saddleLayer.mousePoint
                    element.data.start = core.Vector2(pos.x, pos.y)
                    element.thinkTime = 0.02
                end,
                unpress = function(element)
                    element.thinkTime = nil
                    element.data.anchor = nil
                    Commit()
                end,
                think = function(element)
                    local live = Token()
                    local anchor = element.data.anchor
                    if live == nil or anchor == nil or saddleLayer.mousePoint == nil then
                        return
                    end
                    local all = live.saddlePositions or {}
                    local start = element.data.start
                    all[saddleIndex] = core.Vector2(start.x + saddleLayer.mousePoint.x - anchor.x, start.y + saddleLayer.mousePoint.y - anchor.y)
                    live.saddlePositions = all
                    PaintSaddles(live)
                    live:RefreshAppearanceLocally()
                end,
            }
            saddleMarks[i] = mark
            saddleLayer:AddChild(mark)
        end
        --the riders' true size, as the map draws them.
        local markSize = math.max(12, math.floor(footprint * ratio + 0.5))
        for i, mark in ipairs(saddleMarks) do
            local pos = positions[i]
            local shown = i <= count and pos ~= nil
            mark:SetClass("collapsed", not shown)
            if shown then
                --placed by margins from the layer's corner: positions run up.
                mark.selfStyle.width = markSize
                mark.selfStyle.height = markSize
                mark.selfStyle.lmargin = math.floor(footprint / 2 + pos.x * footprint - markSize / 2 + 0.5)
                mark.selfStyle.tmargin = math.floor(footprint / 2 - pos.y * footprint - markSize / 2 + 0.5)
            end
        end
    end

    --- @param token CharacterToken
    local function Paint(token)
        local writable = HeroSheetWrite.CanWrite()
        paintPreview(token)
        PaintSaddles(token)
        --a popout token draws its whole picture on the map: its crop does
        --nothing there, so Zoom and the drag go; Circle stays.
        local popout = token.popoutPortrait == true
        dragTag:SetClass("collapsed", popout or not (writable and token.portrait ~= nil and token.portrait ~= ""))
        zoomRow:SetClass("collapsed", popout)
        if snapshot == nil then
            zoomSlider.value = token.portraitZoom or 1
            circleSlider.value = token.popoutScale or 1
        end
        popoutRow:SetClass("collapsed", not HasPopoutMode(token))
        popoutRow:SetClass("heroSheetOff", not writable)
        popoutMark:SetClass("collapsed", not popout)
        --a hint when the art is made to pop out but shows inside the frame.
        popoutHint:SetClass("collapsed", not (HasPopoutMode(token) and not popout and PopoutArt(token)))
        circleRow:SetClass("collapsed", not popout)

        local frame = token.portraitFrame
        local framed = frame ~= nil and frame ~= ""
        frameParts.thumb:SetClass("collapsed", not framed)
        if framed then
            frameParts.thumb.bgimage = frame
            TintFrame(frameParts.thumb, token)
        end
        local frameName = ImageName(frame)
        frameParts.value.text = cond(framed, frameName or "", "No frame")
        frameParts.value:SetClass("collapsed", framed and frameName == nil)
        frameParts.note.text = cond(framed, cond(Tinted(token), "tinted", "no tint"), "")
        --the party's default frame replaced this one.
        local fromParty = false
        if framed then
            pcall(function()
                local party = GetParty(token.partyId)
                fromParty = party ~= nil and party:GetFrame() == frame
            end)
        end
        frameParts.extra.text = "From the party's default"
        frameParts.extra:SetClass("collapsed", not fromParty)
        frameParts.button:SetClass("heroSheetOff", not writable)

        backgroundLine:SetClass("collapsed", not popout)
        local back = token.portraitBackground
        local hasBack = back ~= nil and back ~= ""
        backgroundParts.thumb:SetClass("collapsed", not hasBack)
        if hasBack then
            backgroundParts.thumb.bgimage = back
        end
        local backName = ImageName(back)
        backgroundParts.value.text = cond(hasBack, backName or "", "None")
        backgroundParts.value:SetClass("collapsed", hasBack and backName == nil)
        backgroundParts.note.text = "Behind the art, inside the frame"
        backgroundParts.button:SetClass("heroSheetOff", not writable)

        mountParts.value.text = MountSummary(token)
        mountParts.button:SetClass("heroSheetOff", not writable)
        resetButton:SetClass("heroSheetOff", not writable)
    end

    dragTag = FitParts.DragTag()

    saddleLayer = gui.Panel{
        width = TOKEN_BOX,
        height = TOKEN_BOX,
        halign = "center",
        valign = "center",
        floating = true,
        flow = "none",
    }

    --the picture moves with the pointer while the button is held; the
    --wheel drives Zoom (wheel up zooms in), a spin is one upload.
    local tokenBox = gui.Panel{
        --a clear image: a panel with none takes no presses.
        bgimage = "panels/square.png",
        bgcolor = "clear",
        width = TOKEN_BOX,
        height = TOKEN_BOX,
        halign = "center",
        flow = "none",
        press = function(element)
            local live = Token()
            if live == nil or live.popoutPortrait == true then
                return
            end
            --a press on a saddle reaches the token too: the saddle moves, not
            --the picture.
            for _, mark in ipairs(saddleMarks) do
                if mark:HasClass("hover") then
                    return
                end
            end
            local token = Begin()
            if token == nil or element.mousePoint == nil then
                return
            end
            local rect = token.portraitRect
            local offset = token.portraitOffset or core.Vector2(0, 0)
            drag = {
                anchor = element.mousePoint,
                offset = core.Vector2(offset.x, offset.y),
                w = rect.x2 - rect.x1,
                h = rect.y2 - rect.y1,
            }
            element.thinkTime = 0.02
        end,
        unpress = function(element)
            element.thinkTime = nil
            if drag ~= nil then
                Commit()
            end
        end,
        think = function(element)
            local token = Token()
            if drag == nil or token == nil or element.mousePoint == nil then
                return
            end
            local dx = element.mousePoint.x - drag.anchor.x
            local dy = element.mousePoint.y - drag.anchor.y
            token.portraitOffset = core.Vector2(drag.offset.x - dx * drag.w, drag.offset.y - dy * drag.h)
            paintPreview(token)
            token:RefreshAppearanceLocally()
        end,
        wheel = function(element, delta)
            local live = Token()
            if drag ~= nil or live == nil or live.popoutPortrait == true then
                return true
            end
            local token = Begin()
            if token == nil then
                return true
            end
            local zoom = FitParts.WheelZoom(token.portraitZoom or 1, delta)
            token.portraitZoom = zoom
            zoomSlider.value = zoom
            paintPreview(token)
            PaintSaddles(token)
            token:RefreshAppearanceLocally()
            wheelSerial = wheelSerial + 1
            local serial = wheelSerial
            dmhub.Schedule(WHEEL_SETTLE, function()
                if not mod.unloaded and serial == wheelSerial and drag == nil then
                    Commit()
                end
            end)
            return true
        end,
        preview,
        saddleLayer,
        dragTag,
    }

    zoomSlider = gui.Slider{
        width = "100%-50",
        height = 20,
        sliderWidth = 70,
        labelFormat = "rawpercent",
        labelWidth = 46,
        valign = "center",
        minValue = TOKEN_ZOOM_MIN,
        maxValue = TOKEN_ZOOM_MAX,
        unclamped = true,
        value = 1,
        events = {
            change = function(element)
                local token = Begin()
                if token == nil then
                    return
                end
                token.portraitZoom = element.value
                paintPreview(token)
                PaintSaddles(token)
                token:RefreshAppearanceLocally()
            end,
            confirm = function(element)
                Commit()
            end,
        },
    }
    circleSlider = gui.Slider{
        width = "100%-50",
        height = 20,
        sliderWidth = 70,
        labelFormat = "rawpercent",
        labelWidth = 46,
        valign = "center",
        minValue = TOKEN_ZOOM_MIN,
        maxValue = TOKEN_ZOOM_MAX,
        value = 1,
        events = {
            change = function(element)
                local token = Begin()
                if token == nil then
                    return
                end
                token.popoutScale = element.value
                paintPreview(token)
                PaintSaddles(token)
                token:RefreshAppearanceLocally()
            end,
            confirm = function(element)
                Commit()
            end,
        },
    }

    zoomRow = FitParts.SliderRow("Zoom", zoomSlider)
    circleRow = FitParts.SliderRow("Circle", circleSlider, "Sizes the frame and background under the art.")
    circleRow:SetClass("collapsed", true)

    popoutRow, popoutMark, popoutHint = FitParts.PopoutCheck(function(element)
        local token = Token()
        if token == nil or element:HasClass("heroSheetOff") then
            return
        end
        --an explicit choice: 1 always pops out, 2 never does.
        local on = token.popoutPortrait == true
        HeroSheetWrite.SaveAppearance(function(live)
            live.popoutMode = cond(on, 2, 1)
        end)
        HeroSheetRefresh.Changed()
    end)

    local tokenColumn = FitParts.TokenColumn(tokenBox, zoomRow, popoutRow, popoutHint, circleRow)

    frameLine, frameParts = FitLine("Frame", "Change frame", function()
        local token = Token()
        if token ~= nil then
            FrameWindow(token)
        end
    end)
    backgroundLine, backgroundParts = FitLine("Background", "Change background", function()
        local token = Token()
        if token ~= nil then
            BackgroundWindow{
                subtitle = token.name,
                current = function()
                    local live = Token()
                    return live ~= nil and live.portraitBackground or nil
                end,
                frame = function()
                    local live = Token()
                    return live ~= nil and live.portraitFrame or nil
                end,
                pick = function(id)
                    HeroSheetWrite.SaveAppearance(function(live)
                        live.portraitBackground = cond(id == "", nil, id)
                    end)
                    HeroSheetRefresh.Changed()
                end,
            }
        end
    end)
    backgroundLine:SetClass("collapsed", true)
    backgroundParts.extra:SetClass("collapsed", true)
    mountLine, mountParts = FitLine("Mount", "Change", function(element)
        MountPopover(element)
    end)

    resetButton = SmallButton{
        text = "Reset placement",
        click = function()
            HeroSheetWrite.SaveAppearance(function(live)
                live.portraitZoom = 1
                live.portraitOffset = core.Vector2(0, 0)
                live.saddlePositions = nil
                --the card's own framing goes too: a 0 zoom clears it, so the
                --card follows the token's crop again.
                if HasCardFields(live) then
                    live.cardZoom = 0
                    live.cardOffset = core.Vector2(0, 0)
                end
            end)
            HeroSheetRefresh.Changed()
        end,
    }
    resetButton.data.tip = "Puts back the token and card framing, and the saddles."

    local lines = gui.Panel{
        width = string.format("100%%-%d", TOKEN_COLUMN + TOKEN_GAP),
        height = "auto",
        flow = "vertical",
        halign = "right",
        valign = "top",
        tmargin = 18,
        frameLine,
        backgroundLine,
        gui.Panel{
            width = "100%",
            height = 26,
            bmargin = 14,
            flow = "horizontal",
            resetButton,
        },
        mountLine,
    }

    local step = Step(2, "Fit it",
        "Drag the token to move the picture, and zoom to size it. The card has its own framing: drag the big art. Pop out of the frame suits art made to rise above it, on a transparent background.",
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            thinkTime = 0.25,
            think = FitItAdapt(tokenColumn, lines),
            tokenColumn,
            lines,
        })

    local blockPanel = HeroSheetRefresh.Block({
        width = "100%",
        height = "auto",
        flow = "vertical",
        step,
    }, {
        name = "appearance fit",
        signature = function(token)
            local offset = token.portraitOffset or core.Vector2(0, 0)
            local saddles = {}
            for _, pos in ipairs(token.saddlePositions or {}) do
                saddles[#saddles+1] = string.format("%.3f,%.3f", pos.x, pos.y)
            end
            return table.concat({
                tostring(token.portrait), string.format("%.4f|%.4f|%.4f", token.portraitZoom or 1, offset.x, offset.y),
                tostring(token.portraitFrame), string.format("%.3f|%.3f|%.3f", token.portraitFrameHueShift or 0, token.portraitFrameSaturation or 1, token.portraitFrameBrightness or 1),
                tostring(token.popoutPortrait), tostring(token.popoutMode), string.format("%.3f", token.popoutScale or 1),
                tostring(token.portraitBackground), tostring(token.saddles), tostring(token.saddleSize), table.concat(saddles, ";"),
                tostring(token.creatureSize), tostring(token.partyId), tostring(HeroSheetWrite.CanWrite()),
            }, "|")
        end,
        refresh = function(panel, token)
            --a preview in progress keeps its own values on screen.
            if snapshot ~= nil then
                return
            end
            Paint(token)
        end,
    })
    return blockPanel, step
end

----------------------------------------------------------------------
--1 Choose the art: Choose art and Upload,
--the TitanCraft link, a separate card picture; the Suggested cell beside it;
--the Art window, one scrolling grid whose few on-screen rows are recycled
--as it scrolls, so a library of hundreds costs what a screenful does.

--the pictures you used and uploaded, on your account: they
--follow you to every game; each list shows only what this game has.
local g_recentArt = setting{
    id = "heroartrecent",
    description = "Recent Hero art",
    storage = "account",
    default = {},
}
local g_uploadedArt = setting{
    id = "heroartuploads",
    description = "Hero art you uploaded",
    storage = "account",
    default = {},
}
local RECENT_LIMIT = 12
local UPLOADS_LIMIT = 60

--the Art window: tiles at the card's shape, six across; the grid shows
--about three rows, and keeps two more to scroll into.
local ART_COLUMNS = 6
local ART_TILE_W = 136
local ART_TILE_IMAGE_H = 177
local ART_TILE_H = ART_TILE_IMAGE_H + 22
local ART_TILE_GAP = 12
local ART_ROW_H = ART_TILE_H + 10
local ART_HEADER_H = 28
local ART_GRID_H = 540
local ART_POOL_ROWS = 5
local ART_WINDOW_W = ART_COLUMNS * (ART_TILE_W + ART_TILE_GAP) + 60
local ART_EXTENSIONS = {"jpeg", "jpg", "png", "webm", "webp", "mp4", "avi"}

--the Suggested cell's thumbnails.
local SUGGEST_W = 64
local SUGGEST_H = 84
local SUGGEST_GAP = 10
local SUGGEST_MAX = 6

--- A list of picture ids kept on your account, newest first, showing only
--- the pictures this game has.
--- @param listSetting table a setting
--- @return string[]
local function ArtList(listSetting)
    local result = {}
    local stored = listSetting:Get()
    if type(stored) == "table" then
        for _, id in ipairs(stored) do
            if type(id) == "string" and assets.imagesTable[id] ~= nil then
                result[#result+1] = id
            end
        end
    end
    return result
end

--- Put a picture first on an account list, once, and keep the list short.
--- @param listSetting table a setting
--- @param id string
--- @param limit integer
local function Remember(listSetting, id, limit)
    local list = {id}
    local stored = listSetting:Get()
    if type(stored) == "table" then
        for _, other in ipairs(stored) do
            if other ~= id and #list < limit then
                list[#list+1] = other
            end
        end
    end
    listSetting:Set(list)
end

--- Take a picture off an account list (it was deleted from its library).
--- @param listSetting table a setting
--- @param id string
local function Forget(listSetting, id)
    local stored = listSetting:Get()
    if type(stored) ~= "table" then
        return
    end
    local list = {}
    local found = false
    for _, other in ipairs(stored) do
        if other == id then
            found = true
        else
            list[#list+1] = other
        end
    end
    if found then
        listSetting:Set(list)
    end
end

--- True when the look has its own card picture: offTokenPortrait reads back
--- the token's picture when none is set.
--- @param token CharacterToken
--- @return boolean
local function SeparateCard(token)
    local card = token.offTokenPortrait
    return card ~= nil and card ~= "" and card ~= token.portrait
end

--- The art the Builder would suggest: the class's, then the ancestry's
--- (their compendium portraitid), each only when it has a picture.
--- @param token CharacterToken
--- @return {id: string, caption: string, kind: string}[]
local function ClassAndAncestryArt(token)
    local result = {}
    local props = token.properties
    if props == nil then
        return result
    end
    --a Hero's properties are a character, which has a class (heroes only).
    local hero = props --[[@as character]]
    pcall(function()
        local class = hero:GetClass()
        if class == nil then
            return
        end
        local art = class:try_get("portraitid", "")
        if art ~= "" and assets.imagesTable[art] ~= nil then
            result[#result+1] = {id = art, caption = class.name, kind = "class"}
        end
    end)
    pcall(function()
        local raceid = props:try_get("raceid")
        local race = raceid ~= nil and dmhub.GetTable(Race.tableName)[raceid] or nil
        if race == nil then
            return
        end
        local art = race:try_get("portraitid", "")
        if art ~= "" and assets.imagesTable[art] ~= nil then
            result[#result+1] = {id = art, caption = race.name, kind = "ancestry"}
        end
    end)
    return result
end

----------------------------------------------------------------------
--The summon the Summons tab edits. Its look lives on the Hero
--(creature.summonAppearances, keyed by monster type): the art window and the
--tab save into it, and each save restyles the Hero's live summons.

--- The summon being edited, by look key, and a drag or slider in progress:
--- token fields shown before they save, on release.
--- @type {key: nil|string, name: string, pending: table<string, any>, repaint: nil|fun()}
local g_summon = {key = nil, name = "", pending = {}, repaint = nil}

--- Save a change to the edited summon's look, as one undo step (labelled
--- as on the old sheet), then restyle the Hero's live summons of that kind. An emptied
--- look is removed: the summon is back to its stat block's.
--- @param mutate fun(look: table)
local function SaveSummonLook(mutate)
    local key = g_summon.key
    if key == nil then
        return
    end
    local saved = HeroSheetWrite.Save{
        description = "Change summon appearance",
        execute = function(props)
            local all = props:get_or_add("summonAppearances", {})
            local look = all[key] or {}
            mutate(look)
            if next(look) == nil then
                look = nil
            end
            all[key] = look
            --listed from now on, even after its live summons are gone.
            props:RecordSummonHistory(key)
        end,
    }
    local token = Token()
    if saved and token ~= nil then
        ActivatedAbilitySummonBehavior.RestyleLiveSummons(token, key)
    end
    HeroSheetRefresh.Changed()
end

--- Use a picture for the look: its token art, or its own card picture. A
--- pick is the player's: the Builder stops swapping in class art. A
--- summon's picture goes on the summon's look.
--- @param id string
--- @param target "token"|"card"|"summon"
local function UseArt(id, target)
    local token = Token()
    if token == nil or id == nil or id == "" or not HeroSheetWrite.CanWrite() then
        return
    end
    if target == "summon" then
        local monster = nil
        if g_summon.key ~= nil then
            local _
            _, monster = ActivatedAbilitySummonBehavior.ResolveSummonLookMonster(g_summon.key)
        end
        --its stat block's own picture stores nothing.
        local own = monster ~= nil and monster.info.portrait == id
        SaveSummonLook(function(look)
            look.portrait = cond(own, nil, id)
        end)
        Remember(g_recentArt, id, RECENT_LIMIT)
        return
    end
    HeroSheetWrite.SaveAppearance(function(live)
        if target == "card" then
            live.offTokenPortrait = id
        else
            live.portrait = id
        end
    end)
    local field = HeroBuild.main ~= nil and HeroBuild.main.AUTO_PORTRAIT_FIELD or nil
    if target == "token" and field ~= nil and token.properties:try_get(field) ~= false then
        HeroSheetWrite.Save{
            description = "Portrait",
            undoable = false,
            combine = true,
            execute = function(props)
                props[field] = false
            end,
        }
    end
    Remember(g_recentArt, id, RECENT_LIMIT)
    HeroSheetRefresh.Changed()
end

--- Upload a picture (a file, or "CLIPBOARD") into this game's avatar
--- library, or its popout library, then use it. Errors show in a message box.
--- @param path string
--- @param popout boolean
--- @param target "token"|"card"|"summon"
--- @param done nil|fun(id: string)
local function UploadArt(path, popout, target, done)
    if not HeroSheetWrite.CanWrite() then
        return
    end
    local library = cond(popout, "popoutavatars", "Avatar")
    local failed = false
    local token = Token()
    local charid = token ~= nil and token.charid or nil
    local summonKey = g_summon.key
    local assetid = assets:UploadImageAsset{
        path = path,
        --a pasted picture has no file name.
        description = cond(path == "CLIPBOARD", "", FileDrops.BaseName(path)),
        imageType = cond(popout, "AvatarPopout", "Avatar"),
        error = function(text)
            failed = true
            gui.ModalMessage{
                title = "Error loading image: " .. text,
                message = text,
            }
        end,
        upload = function(imageid)
            dmhub.AddAndUploadImageToLibrary(library, imageid)
        end,
    }
    --the picture is usable once it is in the image table.
    local function Poll()
        if mod.unloaded or failed or assetid == nil then
            return
        end
        if assets.imagesTable[assetid] ~= nil then
            Remember(g_uploadedArt, assetid, UPLOADS_LIMIT)
            --only onto the Hero (and summon) it was uploaded for, if the
            --sheet has switched meanwhile.
            local live = Token()
            if live == nil or live.charid ~= charid or (target == "summon" and g_summon.key ~= summonKey) then
                return
            end
            UseArt(assetid, target)
            if done ~= nil then
                done(assetid)
            end
        else
            dmhub.Schedule(0.1, Poll)
        end
    end
    dmhub.Schedule(0.1, Poll)
end

--- The file dialog for an upload (Upload, the Upload tile).
--- @param popout boolean
--- @param target "token"|"card"|"summon"
--- @param done nil|fun(id: string)
local function ChooseUpload(popout, target, done)
    if not HeroSheetWrite.CanWrite() then
        return
    end
    dmhub.OpenFileDialog{
        id = "IconImages",
        extensions = ART_EXTENSIONS,
        multiFiles = false,
        open = function(path)
            UploadArt(path, popout, target, done)
        end,
    }
end

--- The picture cut to a shape, the top kept (faces sit high): its whole
--- width or height, from its size once the asset knows it.
--- @param id string
--- @param aspect number width / height
--- @return nil|{x1: number, y1: number, x2: number, y2: number}
local function CoverRect(id, aspect)
    local asset = assets.imagesTable[id]
    local imageWidth = asset ~= nil and tonumber(asset.width) or nil
    local imageHeight = asset ~= nil and tonumber(asset.height) or nil
    if imageWidth == nil or imageHeight == nil or imageWidth <= 0 or imageHeight <= 0 then
        return nil
    end
    local imageAspect = imageWidth / imageHeight
    if imageAspect > aspect then
        local share = aspect / imageAspect
        return {x1 = 0.5 - share / 2, y1 = 0, x2 = 0.5 + share / 2, y2 = 1}
    end
    local share = imageAspect / aspect
    return {x1 = 0, y1 = 1 - share, x2 = 1, y2 = 1}
end

--- The right-click menu on a picture: copy it, paste one, and
--- for the Director, delete it from a library; two developer extras.
--- @param anchor Panel
--- @param id nil|string the picture under the pointer, if any
--- @param library nil|string the library it shows from, for Delete
--- @param paste nil|fun(id: string) uses a pasted picture
--- @param deleted nil|fun()
local function ArtMenu(anchor, id, library, paste, deleted)
    local entries = {}
    if id ~= nil and id ~= "" then
        entries[#entries+1] = {text = "Copy image", click = function()
            dmhub.CopyToInternalClipboard("IMAGE:" .. id)
            HeroSheetWindow.Toast("Copied the image.")
        end}
    end
    local clip = dmhub.GetInternalClipboard()
    if paste ~= nil and type(clip) == "string" and string.sub(clip, 1, 6) == "IMAGE:" then
        entries[#entries+1] = {text = "Paste image", click = function()
            paste(string.sub(clip, 7))
            HeroSheetWindow.Toast("Pasted the image.")
        end}
    end
    if id ~= nil and id ~= "" and library ~= nil and dmhub.isDM then
        entries[#entries+1] = {text = "Delete from the library", danger = true, click = function()
            dmhub.RemoveAndUploadImageFromLibrary(library, id)
            --the picture stays in the game's images, so the lists must drop it.
            Forget(g_recentArt, id)
            Forget(g_uploadedArt, id)
            HeroSheetRefresh.Changed()
            HeroSheetWindow.Toast("Deleted from the library.")
            if deleted ~= nil then
                deleted()
            end
        end}
    end
    if id ~= nil and id ~= "" and dmhub.GetSettingValue("dev") then
        entries[#entries+1] = {text = "Open URL", hint = "Developer", click = function()
            dmhub.OpenImageAssetURL(id)
        end}
        entries[#entries+1] = {text = "Copy image ID", hint = "Developer", click = function()
            dmhub.CopyToClipboard(id)
        end}
    end
    if #entries > 0 then
        HeroSheetLists.ShowMenu(anchor, entries, nil, {below = true})
    end
end

--- @class HeroArtTab
--- @field id string
--- @field text string
--- @field library nil|string the image library it shows
--- @field upload nil|boolean it starts with the Upload tile
--- @field popout nil|boolean its uploads go to the popout library

--- The Art window's tabs: All, Classes, Ancestries, Recent, Your uploads,
--- then the other picture libraries (as the old sheet listed them).
--- @return HeroArtTab[]
local function ArtTabs()
    local tabs = {
        {id = "all", text = "All", library = "Avatar", upload = true},
        {id = "classes", text = "Classes"},
        {id = "ancestries", text = "Ancestries"},
        {id = "recent", text = "Recent"},
        {id = "uploads", text = "Your uploads", upload = true},
    }
    if dmhub.GetSettingValue("popoutavatars") then
        tabs[#tabs+1] = {id = "popout", text = "Popout avatars", library = "popoutavatars", upload = true, popout = true}
    end
    if dmhub.isDM then
        tabs[#tabs+1] = {id = "secret", text = "GM Secret", library = "secret"}
    end
    local extra = {}
    for key, lib in pairs(assets.imageLibrariesTable or {}) do
        local kind = lib.imageType
        if lib.extension and not lib.hidden and (dmhub.isDM or not lib.gmonly) and (kind == "Avatar" or kind == "AvatarPopout") then
            extra[#extra+1] = {id = "lib:" .. key, text = lib.name, library = key}
        end
    end
    table.sort(extra, function(left, right) return left.text < right.text end)
    for _, tab in ipairs(extra) do
        tabs[#tabs+1] = tab
    end
    return tabs
end

--- @class HeroArtEntry
--- @field id string "" for the Upload tile
--- @field caption string

--- @class HeroArtRow
--- @field header nil|string
--- @field tiles nil|HeroArtEntry[]
--- @field top number where the row starts in the grid
--- @field height number

--- The edited summon's picture now (the Summons tab sets it).
--- @type fun(): nil|string
local SummonArtNow = function() return nil end

--- Art: the tabs, search, and one scrolling grid of large tiles. Picks save
--- as you go; drop a file or press Ctrl+V to upload. A summon's has no
--- Suggested: that is the Hero's class and ancestry.
--- @param target "token"|"card"|"summon"
local function ArtWindow(target)
    local token = Token()
    if token == nil then
        return
    end
    local tabs = ArtTabs()
    local tab = tabs[1]
    local search = ""
    --- @type HeroArtRow[]
    local rows = {}
    local total = 0
    local first = -1
    local poolRows = {}
    local tabPanels = {}
    local holder, content, poolColumn, empty
    --- @type fun()
    local Refill
    --the open tab's library, as a set: Delete is offered only for its own pictures.
    --- @type table<string, boolean>
    local inLibrary = {}

    --- The picture this window sets, now.
    --- @return nil|string
    local function Current()
        local live = Token()
        if live == nil then
            return nil
        end
        if target == "summon" then
            return SummonArtNow()
        end
        return cond(target == "card", live.offTokenPortrait, live.portrait)
    end

    --- @param ids string[]
    --- @param caption fun(id: string): string
    --- @return HeroArtEntry[]
    local function Entries(ids, caption)
        local result = {}
        for _, id in ipairs(ids) do
            result[#result+1] = {id = id, caption = caption(id)}
        end
        return result
    end

    --- The compendium's class or ancestry art, as tiles.
    --- @param tableName string
    --- @param suffix string
    --- @return HeroArtEntry[]
    local function TableArt(tableName, suffix)
        local result = {}
        for _, item in unhidden_pairs(dmhub.GetTable(tableName) or {}) do
            local art = item:try_get("portraitid", "")
            if art ~= "" and assets.imagesTable[art] ~= nil then
                result[#result+1] = {id = art, caption = string.format("%s %s", item.name, suffix)}
            end
        end
        table.sort(result, function(left, right) return left.caption < right.caption end)
        return result
    end

    --- Narrow tiles to a search: a library's own search where there is one
    --- (it matches keywords), else the captions and the image search.
    --- @param list HeroArtEntry[]
    --- @return HeroArtEntry[]
    local function Filter(list)
        if search == "" then
            return list
        end
        local text = string.lower(search)
        local found = {}
        for _, id in ipairs(dmhub.SearchImages(search, nil)) do
            found[id] = true
        end
        local result = {}
        for _, entry in ipairs(list) do
            if found[entry.id] or string.find(string.lower(entry.caption), text, 1, true) ~= nil then
                result[#result+1] = entry
            end
        end
        return result
    end

    --- The rows for the open tab and search: headers and rows of tiles.
    local function Build()
        local live = Token()
        rows = {}
        total = 0
        inLibrary = {}
        if tab.library ~= nil then
            for _, id in ipairs(dmhub.SearchImages("", tab.library)) do
                inLibrary[id] = true
            end
        end
        --- @param text string
        local function Header(text)
            rows[#rows+1] = {header = text, top = total, height = ART_HEADER_H}
            total = total + ART_HEADER_H
        end
        --- @param list HeroArtEntry[]
        local function Tiles(list)
            for i = 1, #list, ART_COLUMNS do
                local chunk = {}
                for j = i, math.min(#list, i + ART_COLUMNS - 1) do
                    chunk[#chunk+1] = list[j]
                end
                rows[#rows+1] = {tiles = chunk, top = total, height = ART_ROW_H}
                total = total + ART_ROW_H
            end
        end
        local list = {}
        if tab.id == "classes" then
            list = Filter(TableArt(Class.tableName, "class art"))
        elseif tab.id == "ancestries" then
            list = Filter(TableArt(Race.tableName, "ancestry art"))
        elseif tab.id == "recent" then
            list = Filter(Entries(ArtList(g_recentArt), function(id) return ImageName(id) or "" end))
        elseif tab.id == "uploads" then
            list = Filter(Entries(ArtList(g_uploadedArt), function(id) return ImageName(id) or "" end))
        elseif tab.library ~= nil then
            local ids = dmhub.SearchImages(search, tab.library)
            list = Entries(ids, function(id) return ImageName(id) or "" end)
        end
        --All leads with the Hero's own suggestions.
        if tab.id == "all" and search == "" and live ~= nil and target ~= "summon" then
            local suggested = {}
            for _, art in ipairs(ClassAndAncestryArt(live)) do
                suggested[#suggested+1] = {id = art.id, caption = cond(art.kind == "class", "Your class", "Your ancestry")}
            end
            if #suggested > 0 then
                Header(string.format("Suggested for %s", live.name or ""))
                Tiles(suggested)
            end
            Header("Everything")
        end
        if tab.upload and search == "" then
            table.insert(list, 1, {id = "", caption = "Upload"})
        end
        Tiles(list)
        local hasPictures = false
        for _, entry in ipairs(list) do
            if entry.id ~= "" then
                hasPictures = true
            end
        end
        empty:SetClass("collapsed", hasPictures or (tab.id == "all" and search == ""))
        if search ~= "" then
            empty.text = "No pictures match."
        elseif tab.id == "uploads" then
            empty.text = "Pictures you upload show here."
        else
            empty.text = "Pictures you choose or upload show here."
        end
        content.selfStyle.height = math.max(total, 1)
    end

    --- One tile of a pool row, painted from an entry. Only a row's first
    --- tile can be the Upload tile, so only it builds the Upload words.
    --- @param canUpload boolean
    --- @return Panel
    local function Tile(canUpload)
        local image = gui.Panel{
            bgimage = "panels/square.png",
            bgcolor = "white",
            cornerRadius = {x1 = 7, y1 = 7, x2 = 0, y2 = 0},
            width = "100%",
            height = ART_TILE_IMAGE_H,
            interactable = false,
        }
        local caption = Text{
            classes = {"heroSheetCardText"},
            text = "",
            fontSize = 12.5,
            width = ART_TILE_W - 12,
            height = 18,
            tmargin = 2,
            halign = "center",
            textAlignment = "center",
            textWrap = false,
            textOverflow = "ellipsis",
            interactable = false,
        }
        local uploadWords = canUpload and gui.Panel{
            classes = {"collapsed"},
            width = "100%",
            height = ART_TILE_IMAGE_H,
            flow = "vertical",
            interactable = false,
            gui.Panel{
                classes = {"heroSheetTitleAddIcon"},
                bgimage = "phosphor/plus-bold.png",
                width = 20,
                height = 20,
                halign = "center",
                tmargin = 64,
            },
            Text{
                classes = {"heroSheetTitleAddText"},
                text = "Upload",
                fontSize = 14,
                width = "100%",
                height = 20,
                tmargin = 8,
                textAlignment = "center",
            },
            Text{
                classes = {"heroSheetCardSub"},
                text = "png, jpg, webp, webm, mp4",
                fontSize = 11.5,
                width = "100%",
                height = 16,
                tmargin = 4,
                textAlignment = "center",
            },
        } or nil
        local tile
        tile = gui.Panel{
            classes = {"heroLookTile", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = ART_TILE_W,
            height = ART_TILE_H,
            rmargin = ART_TILE_GAP,
            halign = "left",
            pad = 1,
            borderBox = true,
            flow = "vertical",
            data = {},
            linger = function(element)
                local id = element.data.id
                if id ~= nil and id ~= "" and element.data.captionText == "" then
                    local name = ImageName(id)
                    if name ~= nil then
                        gui.Tooltip(name)(element)
                    end
                end
            end,
            click = function(element)
                local id = element.data.id
                if id == "" then
                    ChooseUpload(tab.popout == true, target, function()
                        Refill()
                    end)
                elseif id ~= nil then
                    UseArt(id, target)
                    for _, row in ipairs(poolRows) do
                        row.data.paint()
                    end
                end
            end,
            rightClick = function(element)
                local id = element.data.id
                if id ~= nil and id ~= "" then
                    ArtMenu(element, id, cond(inLibrary[id] == true, tab.library, nil), function(pasted)
                        UseArt(pasted, target)
                    end, function()
                        Build()
                        first = -1
                    end)
                end
            end,
            image,
            uploadWords,
            caption,
        }
        tile.data.image = image
        tile.data.label = caption
        tile.data.uploadWords = uploadWords
        return tile
    end

    --- @param tile Panel
    --- @param entry nil|HeroArtEntry
    local function PaintTile(tile, entry)
        tile:SetClass("collapsed", entry == nil)
        if entry == nil then
            tile.data.id = nil
            return
        end
        tile.data.id = entry.id
        tile.data.captionText = entry.caption
        local upload = entry.id == ""
        tile.data.image:SetClass("collapsed", upload)
        if tile.data.uploadWords ~= nil then
            tile.data.uploadWords:SetClass("collapsed", not upload)
        end
        tile.data.label:SetClass("collapsed", upload)
        tile.selfStyle.borderStyle = cond(upload, "dashed", "solid")
        tile:SetClass("selected", not upload and entry.id == Current())
        if not upload then
            tile.data.image.bgimage = entry.id
            tile.data.image.selfStyle.imageRect = CoverRect(entry.id, ART_TILE_W / ART_TILE_IMAGE_H)
            tile.data.label.text = entry.caption
        end
    end

    for i = 1, ART_POOL_ROWS do
        local header = Text{
            classes = {"heroSheetFieldLabel", "collapsed"},
            text = "",
            fontSize = 11.5,
            bold = true,
            width = "100%",
            height = ART_HEADER_H,
            textWrap = false,
            valign = "center",
        }
        local strip = gui.Panel{
            width = "100%",
            height = ART_TILE_H,
            flow = "horizontal",
        }
        local tiles = {}
        for column = 1, ART_COLUMNS do
            tiles[column] = Tile(column == 1)
            strip:AddChild(tiles[column])
        end
        local row
        row = gui.Panel{
            classes = {"collapsed"},
            width = "100%",
            height = ART_ROW_H,
            flow = "vertical",
            data = {},
            header,
            strip,
        }
        --- paints this pool row from the grid row it shows now.
        row.data.paint = function()
            local model = rows[row.data.index or 0]
            row:SetClass("collapsed", model == nil)
            if model == nil then
                return
            end
            row.selfStyle.height = model.height
            header:SetClass("collapsed", model.header == nil)
            strip:SetClass("collapsed", model.tiles == nil)
            if model.header ~= nil then
                header.text = string.upper(model.header)
            end
            for column = 1, ART_COLUMNS do
                PaintTile(tiles[column], model.tiles ~= nil and model.tiles[column] or nil)
            end
        end
        poolRows[i] = row
    end

    poolColumn = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        children = poolRows,
    }
    content = gui.Panel{
        width = "100%-12",
        height = 1,
        flow = "none",
        halign = "left",
        valign = "top",
        poolColumn,
    }
    empty = Text{
        classes = {"heroSheetMuted", "collapsed"},
        text = "",
        fontSize = 14,
        width = "100%",
        height = 30,
        textAlignment = "center",
        valign = "center",
        floating = true,
    }

    --- Show the rows from the one at the top of the view: the pool moves to
    --- that row and repaints, so only a screenful of tiles ever exists.
    local function Scroll()
        if not holder.valid then
            return
        end
        local top = 0
        local range = total - ART_GRID_H
        if range > 0 and holder.vscroll then
            --vscrollPosition runs 1 at the top to 0 at the bottom.
            top = (1 - (holder.vscrollPosition or 1)) * range
        end
        local start = 1
        for i, model in ipairs(rows) do
            if model.top + model.height > top then
                start = i
                break
            end
        end
        if start == first then
            return
        end
        first = start
        poolColumn.selfStyle.tmargin = rows[start] ~= nil and rows[start].top or 0
        for i, row in ipairs(poolRows) do
            row.data.index = start + i - 1
            row.data.paint()
        end
    end

    holder = gui.Panel{
        width = "100%",
        height = ART_GRID_H,
        flow = "vertical",
        thinkTime = 0.03,
        think = function(element)
            Scroll()
        end,
        content,
        empty,
    }

    --- A fresh tab or search: rebuild the rows, back to the top.
    Refill = function()
        Build()
        holder.vscroll = false
        first = -1
        Scroll()
        --built without scrolling, then scrolling turned on once laid out:
        --building under a scroll view costs more per panel.
        HeroSheetWindow.AfterLayout(function()
            if not holder.valid then
                return
            end
            holder.vscroll = total > ART_GRID_H
            holder.vscrollPosition = 1
        end)
    end

    local strip = gui.Panel{
        width = "100%",
        height = 30,
        flow = "horizontal",
        bmargin = 10,
    }
    for _, spec in ipairs(tabs) do
        local tabPanel = gui.Panel{
            classes = {"heroSheetListTabFrame", "hoverable"},
            bgimage = "panels/square.png",
            border = {x1 = 0, y1 = 2, x2 = 0, y2 = 0},
            width = "auto",
            height = 26,
            rmargin = 16,
            halign = "left",
            valign = "bottom",
            click = function(element)
                tab = spec
                for id, panel in pairs(tabPanels) do
                    panel:SetClassTree("selected", id == spec.id)
                end
                Refill()
            end,
            Text{
                classes = {"heroSheetListTab"},
                text = string.upper(spec.text),
                fontSize = 13,
                bold = true,
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        }
        tabPanels[spec.id] = tabPanel
        strip:AddChild(tabPanel)
    end
    tabPanels[tab.id]:SetClassTree("selected", true)

    local searchField = Field{
        text = "",
        placeholder = "Search images",
        search = true,
        edit = function(text)
            local trimmed = trim(text or "")
            if trimmed ~= search then
                search = trimmed
                Refill()
            end
        end,
    }

    local body = gui.Panel{
        width = "100%",
        height = 30 + 10 + 30 + 10 + ART_GRID_H,
        flow = "vertical",
        --a file dropped anywhere on the window, or Ctrl+V, uploads it.
        dragAndDropExtensions = map(ART_EXTENSIONS, function(ext) return "." .. ext end),
        dropfiles = function(element, files)
            if files ~= nil and files[1] ~= nil then
                UploadArt(files[1], tab.popout == true, target, function()
                    Refill()
                end)
            end
        end,
        keybinds = {{id = "heroartpaste", defaultBind = "ctrl+v"}},
        keybind = function(element, id)
            if id == "heroartpaste" and dmhub.HaveImageInClipboard() then
                UploadArt("CLIPBOARD", tab.popout == true, target, function()
                    Refill()
                end)
            end
        end,
        strip,
        gui.Panel{
            width = "100%",
            height = 30,
            flow = "horizontal",
            bmargin = 10,
            gui.Panel{
                width = 320,
                height = 30,
                halign = "left",
                searchField,
            },
            Text{
                classes = {"heroSheetCardSub"},
                text = "Drop images here, or paste one with Ctrl+V.",
                fontSize = 12.5,
                halign = "right",
                valign = "center",
                textWrap = false,
            },
        },
        holder,
    }

    Refill()
    HeroSheetWindow.ShowDialog{
        title = cond(target == "card", "Card art", "Art"),
        subtitle = cond(target == "summon", g_summon.name, token.name),
        width = ART_WINDOW_W,
        bodyHeight = 30 + 10 + 30 + 10 + ART_GRID_H,
        body = body,
        note = "Uploads go to this game's avatar library. Right-click a picture to copy or paste it.",
        onDone = function() end,
    }
end

--- The Suggested cell: the class's and ancestry's art, then
--- pictures you used recently, as many as fit; hover previews one on the
--- big card, a click uses it for the look.
--- @param bus HeroAppearanceBus
--- @return Panel block
--- @return Panel plate the plate a matched Row lines up
local function BuildSuggested(bus)
    local thumbs = {}
    local row
    local emptyLabel
    local fits = SUGGEST_MAX
    --- @type {id: string, caption: string}[]
    local shown = {}

    --- @param token CharacterToken
    local function Paint(token)
        shown = {}
        for _, art in ipairs(ClassAndAncestryArt(token)) do
            shown[#shown+1] = {id = art.id, caption = art.caption}
        end
        local seen = {}
        for _, entry in ipairs(shown) do
            seen[entry.id] = true
        end
        for _, id in ipairs(ArtList(g_recentArt)) do
            if not seen[id] then
                shown[#shown+1] = {id = id, caption = "Recent"}
                seen[id] = true
            end
        end
        local current = token.portrait
        for i, thumb in ipairs(thumbs) do
            local entry = shown[i]
            thumb:SetClass("collapsed", entry == nil or i > fits)
            if entry ~= nil then
                thumb.data.id = entry.id
                thumb.data.image.bgimage = entry.id
                thumb.data.image.selfStyle.imageRect = CoverRect(entry.id, SUGGEST_W / SUGGEST_H)
                thumb.data.image:SetClass("selected", entry.id == current)
                thumb.data.caption.text = entry.caption
            end
        end
        emptyLabel:SetClass("collapsed", #shown > 0)
    end

    for i = 1, SUGGEST_MAX do
        local image = gui.Panel{
            classes = {"heroLookTile"},
            bgimage = "panels/square.png",
            bgcolor = "white",
            border = 1,
            cornerRadius = 8,
            width = SUGGEST_W,
            height = SUGGEST_H,
            halign = "center",
            interactable = false,
        }
        local caption = Text{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 11.5,
            width = SUGGEST_W + SUGGEST_GAP - 2,
            height = 16,
            tmargin = 3,
            halign = "center",
            textAlignment = "center",
            textWrap = false,
            textOverflow = "ellipsis",
            interactable = false,
        }
        local thumb = gui.Panel{
            classes = {"hoverable", "collapsed"},
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = SUGGEST_W + SUGGEST_GAP,
            height = SUGGEST_H + 20,
            halign = "left",
            flow = "vertical",
            data = {},
            hover = function(element)
                local token = Token()
                if token == nil or element.data.id == nil then
                    return
                end
                local look = LookName(LookNames(token), token.appearanceVariationIndex or 0)
                if token.alternateAppearanceOverride ~= nil then
                    look = token.alternateAppearanceOverride
                end
                gui.Tooltip(string.format("Use this for %s.", look))(element)
                --a look with its own card picture keeps it: the card would not change.
                if bus.PreviewArt ~= nil and HeroSheetWrite.CanWrite() and not SeparateCard(token) then
                    bus.PreviewArt(element.data.id)
                end
            end,
            dehover = function(element)
                if bus.PreviewArt ~= nil then
                    bus.PreviewArt(nil)
                end
            end,
            click = function(element)
                if bus.PreviewArt ~= nil then
                    bus.PreviewArt(nil)
                end
                if element.data.id ~= nil then
                    UseArt(element.data.id, "token")
                end
            end,
            image,
            caption,
        }
        thumb.data.image = image
        thumb.data.caption = caption
        thumbs[i] = thumb
    end

    emptyLabel = Text{
        classes = {"heroSheetCardSub", "collapsed"},
        text = "Pictures you choose or upload show here.",
        fontSize = 12.5,
        width = "100%",
        height = 20,
        tmargin = 8,
        textWrap = false,
    }
    row = gui.Panel{
        width = "100%",
        height = SUGGEST_H + 20,
        flow = "horizontal",
        children = thumbs,
    }

    --- As many as fit the cell: it keeps its height at every width.
    local fitGen = 0
    local function Fit()
        fitGen = fitGen + 1
        local gen = fitGen
        HeroSheetWindow.AfterLayout(function()
            if gen ~= fitGen or not row.valid then
                return
            end
            local renderedWidth = row.renderedWidth
            if renderedWidth <= 0 then
                return
            end
            --the row's width in sheet units, from the window's zoom.
            local units = renderedWidth / math.max(0.01, HeroSheetWindow.Zoom())
            local count = math.clamp(math.floor(units / (SUGGEST_W + SUGGEST_GAP)), 1, SUGGEST_MAX)
            if count ~= fits then
                fits = count
                local token = Token()
                if token ~= nil then
                    Paint(token)
                end
            end
        end)
    end

    local block = Block("Suggested", "Your class and ancestry art, and pictures you used recently.", gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        row,
        emptyLabel,
    })
    local blockPanel = HeroSheetRefresh.Block({
        width = "100%",
        height = "auto",
        flow = "vertical",
        heroSheetLayout = function(element)
            Fit()
        end,
        heroSheetTier = function(element)
            Fit()
        end,
        block,
    }, {
        name = "appearance suggested",
        signature = function(token)
            local props = token.properties
            local class = ""
            pcall(function() class = tostring(props:try_get("classes")) .. tostring(props:try_get("raceid")) end)
            return table.concat({tostring(token.portrait), class, table.concat(ArtList(g_recentArt), ","), tostring(token.appearanceVariationIndex)}, "|")
        end,
        refresh = function(panel, token)
            Paint(token)
            Fit()
        end,
    })
    return blockPanel, block
end

--- 1 Choose the art: Choose art and Upload, the TitanCraft link, and a
--- separate card picture.
--- @return Panel block
--- @return Panel plate the plate a matched Row lines up
local function BuildChooseArt()
    local cardMark
    local cardButton
    --ticked but no card picture chosen yet: the button shows, nothing saved.
    local wanted = false

    --- Copy and Paste image between the look's art slots.
    --- @param target "token"|"card"
    --- @return fun(element: Panel)
    local function SlotMenu(target)
        return function(element)
            local token = Token()
            if token == nil then
                return
            end
            local id = cond(target == "card", token.offTokenPortrait, token.portrait)
            ArtMenu(element, id, nil, cond(HeroSheetWrite.CanWrite(), function(pasted)
                UseArt(pasted, target)
            end, nil))
        end
    end

    local chooseButton = SmallButton{
        text = "Choose art",
        click = function()
            ArtWindow("token")
        end,
        rightClick = SlotMenu("token"),
    }
    local uploadButton = SmallButton{
        text = "Upload",
        icon = "phosphor/upload-simple-bold.png",
        click = function()
            ChooseUpload(false, "token", nil)
        end,
    }
    cardButton = SmallButton{
        text = "Choose card art",
        click = function()
            ArtWindow("card")
        end,
        rightClick = SlotMenu("card"),
    }

    cardMark = gui.Panel{
        classes = {"heroSheetCheckMark", "collapsed"},
        bgimage = "phosphor/check-bold.png",
        width = 11,
        height = 11,
        halign = "center",
        valign = "center",
    }
    local cardRow = gui.Panel{
        classes = {"hoverable"},
        bgimage = "panels/square.png",
        bgcolor = "clear",
        width = "100%",
        height = 22,
        tmargin = 10,
        flow = "horizontal",
        click = function(element)
            local token = Token()
            if token == nil or not HeroSheetWrite.CanWrite() then
                return
            end
            if SeparateCard(token) then
                --unticked: the card shows the token's picture again.
                wanted = false
                HeroSheetWrite.SaveAppearance(function(live)
                    live.offTokenPortrait = ""
                end)
                HeroSheetRefresh.Changed()
            else
                wanted = not wanted
                cardMark:SetClass("collapsed", not wanted)
                cardButton:SetClass("collapsed", not wanted)
            end
        end,
        gui.Panel{
            classes = {"heroSheetCheck"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 3,
            width = 14,
            height = 14,
            halign = "left",
            valign = "center",
            interactable = false,
            cardMark,
        },
        Text{
            classes = {"heroSheetCardText"},
            text = "Use a different image for the card",
            fontSize = 13,
            lmargin = 8,
            halign = "left",
            valign = "center",
            textWrap = false,
            interactable = false,
        },
    }

    local link = Text{
        classes = {"heroSheetFeatLink", "hoverable"},
        text = "TitanCraft Token Builder",
        fontSize = 12.5,
        halign = "right",
        valign = "center",
        textWrap = false,
        click = function(element)
            dmhub.OpenURL("https://titancraft.com/?ref=codex")
        end,
    }

    local step = Step(1, "Choose the art", "The picture for this look's card and token.", gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Panel{
            width = "100%",
            height = 26,
            flow = "horizontal",
            chooseButton,
            uploadButton,
        },
        cardRow,
        gui.Panel{
            width = "100%",
            height = 26,
            tmargin = 6,
            flow = "horizontal",
            cardButton,
        },
    }, link)

    local blockPanel = HeroSheetRefresh.Block({
        width = "100%",
        height = "auto",
        flow = "vertical",
        --a tick left with no card picture does not carry over to the next Hero.
        heroSheetHero = function(element)
            wanted = false
        end,
        step,
    }, {
        name = "appearance choose",
        signature = function(token)
            return table.concat({tostring(token.portrait), tostring(token.offTokenPortrait), tostring(HeroSheetWrite.CanWrite())}, "|")
        end,
        refresh = function(panel, token)
            local writable = HeroSheetWrite.CanWrite()
            local separate = SeparateCard(token)
            if separate then
                wanted = false
            end
            cardMark:SetClass("collapsed", not (separate or wanted))
            cardButton:SetClass("collapsed", not (separate or wanted))
            chooseButton:SetClass("heroSheetOff", not writable)
            uploadButton:SetClass("heroSheetOff", not writable)
            cardButton:SetClass("heroSheetOff", not writable)
            cardRow:SetClass("heroSheetOff", not writable)
        end,
    })
    return blockPanel, step
end

----------------------------------------------------------------------
--3 On the map: the token on a preview floor, as the
--map draws it, by day or by night with the Effects light; Art scale; Cast a
--shadow; Size, which belongs to the Hero rather than a look.

--the preview floor renders at this shape; the panel shows the middle of it.
local MAP_TEXTURE_ASPECT = 1920 / 1080
local MAP_PREVIEW_H = 210
--grid lines kept for the preview: the night view's squares are smallest.
local MAP_GRID_COLUMNS = 32
local MAP_GRID_ROWS = 14
--Art scale (tokenScale): the old sheet's range. Below 0.3 a token all but
--vanishes, and the engine clamps it there anyway.
local ART_SCALE_MIN = 0.3
local ART_SCALE_MAX = 2

--the old sheet's two preview lights: daylight, and a
--night that shows the token's own light, zoomed out to show its reach.
local MAP_DAY = {
    useLight = false,
    previewZoom = 1,
    outdoors = "#ffffff",
    indoors = "#ffffff",
    illumination = 1,
    shadow = {
        dir = core.Vector2(3, 0.6),
        color = "#00000088",
    },
}
local MAP_NIGHT = {
    useLight = true,
    previewZoom = 3,
    outdoors = "#312c5a",
    indoors = "#312c5a",
    illumination = 0.4,
}

--the token fields the preview copies from the Hero's (the old sheet's list,
--and the shadow).
local MAP_TOKEN_FIELDS = {"portraitFrame", "portrait", "portraitBackground", "portraitRibbon",
    "portraitFrameHueShift", "portraitFrameSaturation", "portraitFrameBrightness", "name", "ownerId",
    "portraitZoom", "portraitOffset", "saddles", "saddleSize", "saddlePositions", "popoutScale",
    "tokenScale", "popoutMode", "hideShadow"}

--- The light the Hero's token carries (Effects' Light), or nil.
--- @param token CharacterToken
--- @return nil|string
local function TokenLight(token)
    local light = nil
    pcall(function() light = token.properties:GetEquippedLightSource() end)
    return light
end

--- The night label: a torch or lamp reads as lit, other lights by name.
--- @param token CharacterToken
--- @return string
local function NightLabel(token)
    local light = TokenLight(token)
    local entry = light ~= nil and dmhub.GetTable(equipment.tableName)[light] or nil
    if entry == nil then
        return "Night, no light"
    end
    local name = entry.name or ""
    if name == "Torch" or name == "Lamp" then
        return string.format("Night, %s lit", string.lower(name))
    end
    return string.format("Night, %s", name)
end

--- Token values compared as the preview needs: a Vector2 (an offset) or a
--- list of them (saddles) reads back as a new object each time, so == would
--- call every paint a change and refresh the floor (a full engine pass) for
--- nothing.
--- @param left any
--- @param right any
--- @return boolean
local function SameValue(left, right)
    if left == right then
        return true
    end
    --plain values that differ are different (a string even answers .x).
    local kind = type(left)
    if left == nil or right == nil or kind == "string" or kind == "number" or kind == "boolean" then
        return false
    end
    local same = false
    pcall(function()
        if type(left) == "table" and type(right) == "table" and left.x == nil then
            if #left ~= #right then
                return
            end
            for i = 1, #left do
                if not SameValue(left[i], right[i]) then
                    return
                end
            end
            same = true
        else
            same = left.x == right.x and left.y == right.y
        end
    end)
    return same
end

--- @class HeroAppearanceMapPreview
--- @field panel Panel
--- @field paint fun(token: CharacterToken|table, night: boolean)
--- @field setShown fun(shown: boolean) makes the floor while shown, lets it go when not
--- @field heroChanged fun() another Hero: the next paint copies it afresh

--How long (s) a hidden map preview's floor is kept for a preview to take
--back, before it is dropped.
HeroSheetAppearance.PREVIEW_KEEP = 3

--- Drop the preview floor the map previews share (MapPreview), at once.
function HeroSheetAppearance.DropSharedPreview()
    local shared = HeroSheetAppearance.sharedPreview
    HeroSheetAppearance.sharedPreview = nil
    if shared == nil then
        return
    end
    --the map may have changed under the preview since it was made.
    pcall(function() game.currentMap:DestroyPreviewFloor(shared.floor) end)
    pcall(game.Refresh, {
        currentMap = true,
        floors = {shared.floor.floorid},
        tokens = {shared.tokenId},
    })
end

--- The token on a preview floor, as on the old sheet. One floor is
--- shared by the Look, Effects and Summons previews and exists only while
--- one shows (it renders every frame), kept PREVIEW_KEEP seconds after.
--- @param source nil|fun(): nil|CharacterToken|table what a new floor shows first: the Hero, or a summon's look
--- @return HeroAppearanceMapPreview
local function MapPreview(source)
    --this preview's handle, to tell it from the other previews sharing the floor.
    local previewHandle = {}
    --- @type any the engine's PreviewMapFloorLua
    local floor = nil
    --- @type nil|string
    local tokenId = nil
    --- @type nil|CharacterToken
    local previewToken = nil
    local fresh = false
    local tiles = 1
    local zoom = 1
    local night = false
    --- @type nil|table
    local lastLighting = nil
    --- @type nil|string
    local lastLight = nil
    --- @type any the token's size as last refreshed
    local lastSize = nil
    --the camera as last set: its size (half the view's height, in squares)
    --and the point it centres on.
    local cameraSize = 1
    local centre = {x = 0, y = -4}
    local image
    local holder
    local gridLayer
    local columns = {}
    local rows = {}

    --- The map's grid over the preview, so the token's place in its squares
    --- shows (the preview floor does not draw one reliably). Squares are one
    --- unit wide with their centres on whole numbers, so lines sit on halves.
    local function Grid()
        --rendered sizes are screen pixels; margins are sheet units (Font Size).
        local renderedHeight = holder.renderedHeight
        if renderedHeight == nil or renderedHeight <= 0 or holder.renderedWidth <= 0 then
            return
        end
        local widthUnits = holder.renderedWidth / (renderedHeight / MAP_PREVIEW_H)
        --the floor's 16:9 picture is 2 x cameraSize squares tall, and Crop
        --makes it cover the panel: whichever side fills sets the square.
        local square = math.max(widthUnits / (2 * cameraSize * MAP_TEXTURE_ASPECT), MAP_PREVIEW_H / (2 * cameraSize))
        local colour = "#00000044"
        pcall(function() colour = dmhub.GetSettingValue("gridcolor").tostring end)
        --- @param lines Panel[]
        --- @param first number the first line's offset from the panel's middle, in squares
        --- @param extent number the panel's width or height
        --- @param vertical boolean
        local function Place(lines, first, extent, vertical)
            for i, line in ipairs(lines) do
                local at = math.floor(extent / 2 + (first + i - 1) * square + 0.5)
                local shown = at >= 0 and at < extent
                line:SetClass("collapsed", not shown)
                if shown then
                    line.selfStyle.bgcolor = colour
                    if vertical then
                        line.selfStyle.lmargin = at
                    else
                        line.selfStyle.tmargin = at
                    end
                end
            end
        end
        --the lines left of (and above) the middle that still show, then on.
        local half = math.ceil(widthUnits / 2 / square) + 1
        Place(columns, math.floor(centre.x - half) + 0.5 - centre.x, widthUnits, true)
        local halfH = math.ceil(MAP_PREVIEW_H / 2 / square) + 1
        --world y runs up, the panel's down: the top line is the highest one.
        Place(rows, centre.y - (math.floor(centre.y + halfH) + 0.5), MAP_PREVIEW_H, false)
    end

    --- The camera on the token's footprint (as the old sheet framed it),
    --- zoomed out at night to show its light.
    local function Camera()
        if floor == nil then
            return
        end
        local shift = 0
        local size = 1
        if tiles == 2 then
            shift, size = 0.5, 1.5
        elseif tiles == 3 then
            shift, size = 1, 2
        elseif tiles == 4 then
            shift, size = 1.5, 2
        elseif tiles >= 5 then
            shift, size = 2, 2.5
        end
        cameraSize = size * zoom
        centre = {x = shift, y = -4 + shift}
        floor.cameraSize = cameraSize
        floor.cameraPos = centre
        Grid()
    end

    --- The middle of the floor's 16:9 picture at the panel's shape, then the
    --- grid over it. Rendered sizes are only right once the panel is laid out,
    --- so the holder runs this whenever its width changes.
    local function Crop()
        local renderedWidth = holder.renderedWidth
        local renderedHeight = holder.renderedHeight
        if renderedWidth == nil or renderedHeight == nil or renderedWidth <= 0 or renderedHeight <= 0 then
            return
        end
        local aspect = renderedWidth / renderedHeight
        if aspect < MAP_TEXTURE_ASPECT then
            local share = aspect / MAP_TEXTURE_ASPECT
            image.selfStyle.imageRect = {x1 = 0.5 - share / 2, y1 = 0, x2 = 0.5 + share / 2, y2 = 1}
        else
            local share = MAP_TEXTURE_ASPECT / aspect
            image.selfStyle.imageRect = {x1 = 0, y1 = 0.5 - share / 2, x2 = 1, y2 = 0.5 + share / 2}
        end
        Grid()
    end

    --- @param token CharacterToken|table
    local function Paint(token)
        if floor == nil or previewToken == nil or not previewToken.valid then
            return
        end
        --another preview took the shared floor (shown first in a switch).
        local shared = HeroSheetAppearance.sharedPreview
        if shared == nil or shared.owner ~= previewHandle then
            return
        end
        --any game.Refresh is a full engine pass, whatever it names, so
        --refresh only for what the preview shows: the token's look, its size
        --and its light. The floor joins only when the lighting changes.
        local changed = false
        local lit = false
        if fresh or previewToken.properties == nil then
            previewToken.properties = DeepCopy(token.properties)
            fresh = false
            changed = true
        else
            --kept current for the next refresh; a change the token does not
            --show (dice, blood, footprints, notes) refreshes nothing.
            dmhub.Patch(previewToken.properties, token.properties)
        end
        for _, field in ipairs(MAP_TOKEN_FIELDS) do
            if not SameValue(previewToken[field], token[field]) then
                previewToken[field] = token[field]
                changed = true
            end
        end
        local size = token.creatureSize
        if size ~= lastSize then
            lastSize = size
            changed = true
        end
        local lighting = cond(night, MAP_NIGHT, MAP_DAY)
        local light = cond(night, TokenLight(token), nil)
        if lighting ~= lastLighting or light ~= lastLight then
            lastLighting = lighting
            lastLight = light
            floor.lighting = lighting
            previewToken.wieldedObjectsOverride = {mainhand = light}
            zoom = lighting.previewZoom
            changed = true
            lit = true
        end
        if changed then
            game.Refresh{
                floors = cond(lit, {floor.floorid}, nil),
                tokens = {tokenId},
            }
            local info = dmhub.rules.CreatureSizes[previewToken.creatureSizeNumber]
            tiles = info ~= nil and info.tiles or 1
            Camera()
        end
    end

    local function Make()
        if floor ~= nil or game.currentMap == nil then
            return
        end
        --One preview floor is shared by every map preview (Look, Effects,
        --Summons) and kept a moment after it hides: making one costs two
        --engine refreshes and dropping one a third, each a full pass.
        local shared = HeroSheetAppearance.sharedPreview
        if shared ~= nil and shared.mapid ~= game.currentMapId then
            HeroSheetAppearance.DropSharedPreview()
            shared = nil
        end
        if shared == nil then
            local made = game.currentMap:CreatePreviewFloor("ObjectPreview")
            made.cameraPos = {x = 0, y = -4}
            made.cameraSize = 1
            local madeToken = made:CreateToken(0, -4)
            game.Refresh{
                currentMap = true,
                floors = {made.floorid},
                tokens = {madeToken},
            }
            shared = {floor = made, tokenId = madeToken, mapid = game.currentMapId, owner = nil, lastOwner = nil, dropGen = 0}
            HeroSheetAppearance.sharedPreview = shared
        end
        shared.dropGen = shared.dropGen + 1
        shared.owner = previewHandle
        floor = shared.floor
        tokenId = shared.tokenId
        previewToken = dmhub.GetTokenById(tokenId)
        --the same preview taking its floor back finds the token as it left it:
        --Paint refreshes only what changed since. Another preview's token is
        --set up afresh.
        if shared.lastOwner ~= previewHandle then
            fresh = true
            lastLighting = nil
            lastLight = nil
            lastSize = nil
        end
        shared.lastOwner = previewHandle
        image.bgimage = "#MapPreview" .. floor.floorid
        image:SetClass("collapsed", false)
        gridLayer:SetClass("collapsed", false)
        Crop()
        local token = (source or Token)()
        if token ~= nil then
            Paint(token)
        end
    end

    --- Lets go of the shared floor; it is dropped a moment later unless a
    --- preview takes it back first (a tab or subtab switch back and forth).
    local function Drop()
        if floor == nil then
            return
        end
        floor = nil
        tokenId = nil
        previewToken = nil
        local shared = HeroSheetAppearance.sharedPreview
        if shared ~= nil and shared.owner == previewHandle then
            shared.owner = nil
            shared.dropGen = shared.dropGen + 1
            local gen = shared.dropGen
            --runs even after a reload, so a kept floor never outlives its code.
            dmhub.Schedule(HeroSheetAppearance.PREVIEW_KEEP, function()
                local now = HeroSheetAppearance.sharedPreview
                if now == shared and shared.owner == nil and shared.dropGen == gen then
                    HeroSheetAppearance.DropSharedPreview()
                end
            end)
        end
        if image.valid then
            image:SetClass("collapsed", true)
            gridLayer:SetClass("collapsed", true)
        end
    end

    image = gui.Panel{
        classes = {"collapsed"},
        bgimage = "panels/square.png",
        bgcolor = "white",
        width = "100%",
        height = "100%",
        interactable = false,
    }
    --enough lines for the night view's smallest squares; built once, placed by Grid.
    for i = 1, MAP_GRID_COLUMNS do
        columns[i] = gui.Panel{
            bgimage = "panels/square.png",
            width = 1,
            height = "100%",
            halign = "left",
            valign = "top",
            floating = true,
            interactable = false,
        }
    end
    for i = 1, MAP_GRID_ROWS do
        rows[i] = gui.Panel{
            bgimage = "panels/square.png",
            width = "100%",
            height = 1,
            halign = "left",
            valign = "top",
            floating = true,
            interactable = false,
        }
    end
    local lines = {}
    for _, line in ipairs(columns) do
        lines[#lines+1] = line
    end
    for _, line in ipairs(rows) do
        lines[#lines+1] = line
    end
    gridLayer = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "100%",
        floating = true,
        flow = "none",
        interactable = false,
        children = lines,
    }
    holder = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "#1d1915ff",
        cornerRadius = 6,
        width = "100%",
        height = MAP_PREVIEW_H,
        clip = true,
        data = {width = -1},
        destroy = function(element)
            Drop()
        end,
        --a resize, a tier change or Font Size: crop again once laid out.
        thinkTime = 0.25,
        think = function(element)
            local renderedWidth = element.renderedWidth
            if renderedWidth ~= element.data.width then
                element.data.width = renderedWidth
                Crop()
            end
        end,
        image,
        gridLayer,
    }

    return {
        panel = holder,
        paint = function(token, isNight)
            night = isNight
            Paint(token)
        end,
        setShown = function(shown)
            if shown then
                Make()
            else
                Drop()
            end
        end,
        heroChanged = function()
            fresh = true
        end,
    }
end

--- The Size popover: the ancestry's size or one set by hand,
--- for every look. A choice saves at once, as the stats band's Size does.
--- @param anchor Panel
local function SizePopover(anchor)
    local token = Token()
    if token == nil then
        return
    end
    local props = token.properties
    local race = nil
    pcall(function() race = (props --[[@as character]]):AncestryOrInheritedAncestry() end)
    local ancestryText = nil
    if race ~= nil then
        ancestryText = string.format("From %s (%s)", race.name, tostring(race.size))
    else
        ancestryText = string.format("From the rules (%s)", tostring(props:GetBaseCreatureSize() or token.creatureSize))
    end
    local options = {{id = "none", text = ancestryText}}
    for _, size in ipairs(creature.sizes) do
        options[#options+1] = {id = tostring(size), text = tostring(size)}
    end
    local current = tostring(props:try_get("creatureSizeOverride", "none"))
    HeroSheetWindow.ShowPopup{
        width = 280,
        --the content's padding and its children below, top to bottom.
        height = 12 + 20 + 8 + 34 + 30 + 12,
        anchor = anchor,
        below = true,
        content = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            pad = 12,
            borderBox = true,
            Text{
                classes = {"heroSheetCardStrong"},
                text = "SIZE",
                fontSize = 14,
                bold = true,
                height = 20,
                halign = "left",
                bmargin = 8,
            },
            Text{
                classes = {"heroSheetCardSub"},
                text = "Your size in the rules and on the map, for every look.",
                fontSize = 12.5,
                width = "100%",
                height = 34,
                textWrap = true,
            },
            gui.Dropdown{
                classes = {"heroSheetField"},
                width = "100%",
                height = 30,
                options = options,
                idChosen = current,
                change = function(element)
                    ---@cast element Dropdown
                    local id = tostring(element.idChosen)
                    if id == current then
                        return
                    end
                    current = id
                    HeroSheetWrite.SetSizeOverride(id)
                    HeroSheetRefresh.Changed()
                end,
            },
        },
    }
end

--- @param bus HeroAppearanceBus
--- @return Panel block
--- @return Panel plate the plate a matched Row lines up
local function BuildMap(bus)
    --the Art scale drag in progress: the snapshot to upload with.
    --- @type nil|string
    local snapshot = nil
    local night = false
    local preview = MapPreview()
    local pill
    local nightButton, nightLabel
    local scaleRow, scaleSlider
    local shadowRow, shadowMark
    local sizeLine, sizeParts

    --- @param token CharacterToken
    local function Paint(token)
        local writable = HeroSheetWrite.CanWrite()
        preview.paint(token, night)
        pill.text = cond(night, NightLabel(token), "Daylight")
        nightLabel.text = cond(night, "Show day", "Show night")
        if snapshot == nil then
            scaleSlider.value = token.tokenScale or 1
        end
        scaleRow:SetClass("heroSheetOff", not writable)
        --an unframed token that is not a popout shapes its shadow from the
        --picture, so an opaque one casts a square: the option shows only then.
        local framed = token.portraitFrame ~= nil and token.portraitFrame ~= ""
        shadowRow:SetClass("collapsed", framed or token.popoutPortrait == true)
        shadowRow:SetClass("heroSheetOff", not writable)
        shadowMark:SetClass("collapsed", token.hideShadow == true)

        local props = token.properties
        local override = props:try_get("creatureSizeOverride", "none")
        local race = nil
        pcall(function() race = (props --[[@as character]]):AncestryOrInheritedAncestry() end)
        sizeParts.value.text = tostring(token.creatureSize or "")
        if override ~= "none" then
            sizeParts.note.text = "Set by hand, for every look"
        elseif race ~= nil then
            sizeParts.note.text = string.format("From %s, for every look", race.name)
        else
            sizeParts.note.text = "From the rules, for every look"
        end
        sizeParts.button:SetClass("heroSheetOff", not writable)
    end

    bus.MapShown = function(shown)
        preview.setShown(shown)
        local token = Token()
        if shown and token ~= nil then
            Paint(token)
        end
    end
    bus.MapReset = function()
        night = false
    end

    pill = gui.Label{
        classes = {"heroSheetPill"},
        text = "Daylight",
        bgimage = "panels/square.png",
        bgcolor = "clear",
        border = 1,
        cornerRadius = 9,
        width = "auto",
        height = 18,
        hpad = 8,
        borderBox = true,
        fontSize = 12,
        bold = true,
        textWrap = false,
        rmargin = 8,
        valign = "center",
    }
    nightButton, nightLabel = SmallButton{
        text = "Show night",
        click = function()
            night = not night
            local token = Token()
            if token ~= nil then
                Paint(token)
            end
        end,
    }
    nightButton.selfStyle.rmargin = 0

    --a preview redraw is waiting (Art scale's drag throttle, below).
    local scaleMapDue = false
    scaleSlider = gui.Slider{
        width = "100%-70",
        height = 20,
        sliderWidth = 120,
        labelFormat = "rawpercent",
        labelWidth = 46,
        valign = "center",
        minValue = ART_SCALE_MIN,
        maxValue = ART_SCALE_MAX,
        unclamped = true,
        value = 1,
        events = {
            change = function(element)
                local token = Token()
                if token == nil or not HeroSheetWrite.CanWrite() then
                    return
                end
                if snapshot == nil then
                    local live, shot = HeroSheetWrite.PreviewAppearance()
                    if live == nil or shot == nil then
                        return
                    end
                    token = live
                    snapshot = shot
                end
                token.tokenScale = math.max(ART_SCALE_MIN, element.value)
                token:RefreshAppearanceLocally()
                --the preview's floor redraw is a full engine pass, so during a
                --drag it follows a few times a second, as the Summons tab's Art
                --scale does; the release redraws it (Changed).
                if not scaleMapDue then
                    scaleMapDue = true
                    dmhub.Schedule(0.12, function()
                        scaleMapDue = false
                        local live = Token()
                        if not mod.unloaded and live ~= nil and snapshot ~= nil then
                            preview.paint(live, night)
                        end
                    end)
                end
            end,
            confirm = function(element)
                local shot = snapshot
                snapshot = nil
                if shot ~= nil then
                    HeroSheetWrite.CommitAppearance(shot)
                    HeroSheetRefresh.Changed()
                end
            end,
        },
    }
    scaleRow = gui.Panel{
        width = "100%",
        height = 26,
        tmargin = 10,
        flow = "horizontal",
        Text{
            classes = {"heroSheetCardText"},
            text = "Art scale",
            fontSize = 13,
            width = 70,
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        scaleSlider,
    }

    shadowMark = gui.Panel{
        classes = {"heroSheetCheckMark"},
        bgimage = "phosphor/check-bold.png",
        width = 11,
        height = 11,
        halign = "center",
        valign = "center",
    }
    shadowRow = gui.Panel{
        classes = {"hoverable"},
        bgimage = "panels/square.png",
        bgcolor = "clear",
        width = "100%",
        height = 22,
        tmargin = 8,
        flow = "horizontal",
        linger = function(element)
            gui.Tooltip("Unframed pictures cast a shadow shaped like the picture. Turn it off if yours shows as a square.")(element)
        end,
        click = function(element)
            local token = Token()
            if token == nil or element:HasClass("heroSheetOff") then
                return
            end
            local hide = token.hideShadow ~= true
            HeroSheetWrite.SaveAppearance(function(live)
                live.hideShadow = hide
            end)
            HeroSheetRefresh.Changed()
        end,
        gui.Panel{
            classes = {"heroSheetCheck"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 3,
            width = 14,
            height = 14,
            halign = "left",
            valign = "center",
            interactable = false,
            shadowMark,
        },
        Text{
            classes = {"heroSheetCardText"},
            text = "Cast a shadow",
            fontSize = 13,
            lmargin = 8,
            halign = "left",
            valign = "center",
            textWrap = false,
            interactable = false,
        },
    }

    --one line, Change beside its words: it saves height, so On the map
    --matches Fit it.
    local sizeButton = SmallButton{
        text = "Change",
        click = function(element)
            SizePopover(element)
        end,
    }
    sizeButton.selfStyle.lmargin = 10
    sizeParts = {
        value = Text{
            classes = {"heroSheetCardStrong"},
            text = "",
            fontSize = 14,
            bold = true,
            rmargin = 8,
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        note = Text{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 12,
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        button = sizeButton,
    }
    sizeLine = gui.Panel{
        width = "100%",
        height = 26,
        tmargin = 12,
        flow = "horizontal",
        Text{
            classes = {"heroSheetFieldLabel"},
            text = "SIZE",
            fontSize = 11.5,
            bold = true,
            rmargin = 8,
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        sizeParts.value,
        sizeParts.note,
        sizeButton,
    }

    local step = Step(3, "On the map", "How the token sits on the battle map.",
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            preview.panel,
            scaleRow,
            shadowRow,
            sizeLine,
        },
        gui.Panel{
            width = "auto",
            height = 22,
            flow = "horizontal",
            halign = "right",
            valign = "center",
            pill,
            nightButton,
        })

    local blockPanel = HeroSheetRefresh.Block({
        --the Encounter of the Week town has no battle map to preview on.
        classes = {cond(dmhub.isLobbyGame, "collapsed", nil)},
        width = "100%",
        height = "auto",
        flow = "vertical",
        heroSheetHero = function(element)
            preview.heroChanged()
        end,
        step,
    }, {
        name = "appearance map",
        signature = function(token)
            local offset = token.portraitOffset or core.Vector2(0, 0)
            return table.concat({
                tostring(token.portrait), string.format("%.4f|%.4f|%.4f", token.portraitZoom or 1, offset.x, offset.y),
                tostring(token.portraitFrame), string.format("%.3f|%.3f|%.3f", token.portraitFrameHueShift or 0, token.portraitFrameSaturation or 1, token.portraitFrameBrightness or 1),
                tostring(token.popoutPortrait), tostring(token.popoutMode), string.format("%.3f", token.popoutScale or 1),
                tostring(token.portraitBackground), tostring(token.saddles), tostring(token.saddleSize),
                string.format("%.3f", token.tokenScale or 1), tostring(token.hideShadow), tostring(token.creatureSize),
                tostring(token.properties:try_get("creatureSizeOverride", "none")), tostring(TokenLight(token)),
                tostring(token.name), tostring(HeroSheetWrite.CanWrite()),
            }, "|")
        end,
        refresh = function(panel, token)
            --a drag in progress keeps its own value on screen.
            if snapshot ~= nil then
                return
            end
            Paint(token)
        end,
    })
    return blockPanel, step
end

----------------------------------------------------------------------
--4 Anthem: this look's anthem, played when the Hero's
--turn starts, with its own volume; the Anthem window picks, previews,
--uploads, and lets the Director (or whoever uploaded a sound) rename or
--delete it.

--sounds you uploaded, on your account like your pictures: a player may
--rename or delete these (images and sounds record no uploader).
local g_uploadedSounds = setting{
    id = "heroanthemuploads",
    description = "Anthems you uploaded",
    storage = "account",
    default = {},
}
local SOUND_UPLOADS_LIMIT = 60
local SOUND_EXTENSIONS = {"ogg", "mp3", "wav", "flac", "m4a"}

--the Anthem window: one scrolling list whose few on-screen rows are
--recycled as it scrolls.
local ANTHEM_WINDOW_W = 640
local ANTHEM_ROW_H = 48
local ANTHEM_LIST_H = 432
local ANTHEM_POOL = 11

--The one sound previewing now (only one at a time), shared by the block
--and the window. It plays through the anthem channel, as a turn's anthem
--does, so it obeys the player's anthem level.
--- @type {instance: nil|SoundEventInstanceLua, id: nil|string}
local g_audition = {instance = nil, id = nil}
--what repaints when a preview starts or stops, by owner.
--- @type table<table, fun()>
local g_auditionWatchers = {}

local function AuditionChanged()
    for _, fn in pairs(g_auditionWatchers) do
        fn()
    end
end

--- True while this sound (any sound when nil) previews.
--- @param id nil|string
--- @return boolean
local function Auditioning(id)
    return g_audition.instance ~= nil and (id == nil or g_audition.id == id)
end

local function StopAudition()
    local instance = g_audition.instance
    if instance == nil then
        return
    end
    g_audition = {instance = nil, id = nil}
    pcall(function() instance:Stop() end)
    AuditionChanged()
end

--- Preview a sound at a volume; a clip that ends on its own lets go.
--- @param id string
--- @param volume number
local function PlayAudition(id, volume)
    StopAudition()
    local asset = assets.audioTable[id]
    if asset == nil then
        return
    end
    local instance = asset:Play()
    if instance == nil then
        return
    end
    instance.volume = volume
    instance.solo = true
    instance.mixGroupId = "anthem"
    g_audition = {instance = instance, id = id}
    AuditionChanged()
    local function Poll()
        if mod.unloaded or g_audition.instance ~= instance then
            return
        end
        if not instance.playing then
            g_audition = {instance = nil, id = nil}
            AuditionChanged()
            return
        end
        dmhub.Schedule(0.25, Poll)
    end
    dmhub.Schedule(0.25, Poll)
end

--- The sounds you uploaded that this game still has.
--- @return string[]
local function UploadedSounds()
    local result = {}
    local stored = g_uploadedSounds:Get()
    if type(stored) == "table" then
        for _, id in ipairs(stored) do
            local asset = type(id) == "string" and assets.audioTable[id] or nil
            if asset ~= nil and not asset.hidden then
                result[#result+1] = id
            end
        end
    end
    return result
end

--- True when you may rename or delete a sound: the Director any, a player
--- the ones they uploaded.
--- @param id string
--- @return boolean
local function CanEditSound(id)
    if dmhub.isDM then
        return true
    end
    for _, mine in ipairs(UploadedSounds()) do
        if mine == id then
            return true
        end
    end
    return false
end

--- @param id nil|string
--- @return string
local function SoundName(id)
    local asset = id ~= nil and assets.audioTable[id] or nil
    if asset == nil then
        return "No anthem"
    end
    return asset.description or ""
end

--- A sound's kind and length: "Music \xC2\xB7 1:42"; your
--- uploads say so instead of their kind.
--- @param id string
--- @param uploads table<string, boolean>
--- @return string
local function SoundSub(id, uploads)
    local asset = assets.audioTable[id]
    if asset == nil then
        return ""
    end
    local kind = "Sound"
    if uploads[id] then
        kind = "Your upload"
    elseif asset.category == "music" then
        kind = "Music"
    elseif asset.category == "effects" then
        kind = "Effect"
    elseif asset.category == "ambience" then
        kind = "Ambience"
    end
    local seconds = tonumber(asset.duration) or 0
    if seconds <= 0 then
        return kind
    end
    seconds = math.floor(seconds + 0.5)
    --"\xC2\xB7" is a middle dot: Lua source stays ASCII.
    return string.format("%s \xC2\xB7 %d:%02d", kind, math.floor(seconds / 60), seconds % 60)
end

--- Set this look's anthem (nil: No anthem).
--- @param id nil|string
local function UseAnthem(id)
    if not HeroSheetWrite.CanWrite() then
        return
    end
    if id == "" then
        id = nil
    end
    HeroSheetWrite.SaveAppearance(function(live)
        live.anthem = id
    end)
    HeroSheetRefresh.Changed()
end

--- Upload a sound file into this game, then make it this look's anthem.
--- Errors show in a message box.
--- @param path string
--- @param done nil|fun(id: string)
local function UploadSound(path, done)
    if not HeroSheetWrite.CanWrite() then
        return
    end
    local token = Token()
    local charid = token ~= nil and token.charid or nil
    local operation = nil
    local assetid = assets:UploadAudioAsset{
        path = path,
        error = function(text)
            if operation ~= nil then
                operation.progress = 1
                operation:Update()
            end
            gui.ModalMessage{
                title = "Error creating audio",
                message = text,
            }
        end,
        upload = function(id)
            if operation ~= nil then
                operation.progress = 1
                operation:Update()
            end
            if mod.unloaded then
                return
            end
            Remember(g_uploadedSounds, id, SOUND_UPLOADS_LIMIT)
            --a long upload can finish after a switch to another Hero.
            local live = Token()
            if live == nil or live.charid ~= charid then
                return
            end
            UseAnthem(id)
            if done ~= nil then
                done(id)
            end
        end,
        progress = function(percent)
            if operation ~= nil then
                operation.progress = percent
                operation:Update()
            end
        end,
    }
    if assetid ~= nil then
        operation = dmhub.CreateNetworkOperation()
        operation.description = "Uploading Audio..."
        operation.status = "Uploading..."
        operation.progress = 0
        operation:Update()
    end
end

--- Rename sound.
--- @param id string
--- @param renamed fun()
local function RenameSoundWindow(id, renamed)
    local field = Field{
        text = SoundName(id),
        limit = NAME_LIMIT,
        selectAll = true,
    }
    HeroSheetWindow.ShowDialog{
        title = "Rename sound",
        subtitle = SoundName(id),
        width = 520,
        bodyHeight = 18 + 30,
        body = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            FieldName("Name"),
            field,
        },
        onSave = function()
            local name = CleanName(field.text)
            local asset = assets.audioTable[id]
            if asset == nil or name == "" or not CanEditSound(id) then
                return
            end
            asset.description = name
            asset:Upload()
            renamed()
            HeroSheetRefresh.Changed()
        end,
    }
    dmhub.Schedule(0.05, function()
        if not mod.unloaded and field.valid then
            gui.SetFocus(field)
        end
    end)
end

--- Delete <sound>? It goes for everyone.
--- @param id string
--- @param deleted fun()
local function ConfirmDeleteSound(id, deleted)
    HeroSheetWindow.ShowDialog{
        title = string.format("Delete %s?", SoundName(id)),
        width = 520,
        bodyHeight = 40,
        body = Text{
            classes = {"heroSheetCardText"},
            text = "This deletes for everyone in this game. Any token with this track set as their anthem will play nothing.",
            fontSize = 14,
            width = "100%",
            textWrap = true,
        },
        saveText = "Delete",
        onSave = function()
            local asset = assets.audioTable[id]
            if asset == nil or not CanEditSound(id) then
                return
            end
            if Auditioning(id) then
                StopAudition()
            end
            --deleting hides the sound from the game's library, as the old
            --sheet did.
            asset.hidden = true
            asset:Upload()
            Forget(g_uploadedSounds, id)
            local token = Token()
            if token ~= nil and token.anthem == id then
                UseAnthem(nil)
            end
            HeroSheetWindow.Toast("Deleted from the library.")
            deleted()
            HeroSheetRefresh.Changed()
        end,
    }
end

--- The play button (the block's and each row's): a disc showing play, or a
--- square while its sound previews.
--- @param size number
--- @param click fun(element: Panel)
--- @return Panel button
--- @return fun(playing: boolean) paint
local function PlayButton(size, click)
    local playIcon = gui.Panel{
        classes = {"heroSheetFg"},
        bgimage = "phosphor/play.png",
        width = math.floor(size * 0.45),
        height = math.floor(size * 0.45),
        halign = "center",
        valign = "center",
        interactable = false,
    }
    local stopIcon = gui.Panel{
        classes = {"heroSheetFg", "collapsed"},
        bgimage = "panels/square.png",
        cornerRadius = 2,
        width = math.floor(size * 0.32),
        height = math.floor(size * 0.32),
        halign = "center",
        valign = "center",
        interactable = false,
    }
    local button = gui.Panel{
        classes = {"heroSheetSmallButton", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = size / 2,
        width = size,
        height = size,
        halign = "left",
        valign = "center",
        swallowPress = true,
        data = {playing = false},
        linger = function(element)
            if not element:HasClass("heroSheetOff") then
                gui.Tooltip(cond(element.data.playing, "Stop", "Play"))(element)
            end
        end,
        click = function(element)
            if not element:HasClass("heroSheetOff") then
                click(element)
            end
        end,
        playIcon,
        stopIcon,
    }
    local function Paint(playing)
        button.data.playing = playing
        playIcon:SetClass("collapsed", playing)
        stopIcon:SetClass("collapsed", not playing)
    end
    return button, Paint
end

--- Volume: this look's anthem volume. It previews on the sound that is
--- playing and uploads once on release. It always works (a look keeps its
--- volume with No anthem, and sets a preview's); it only looks dimmed while
--- there is no anthem and nothing previewing.
--- @return Panel row
--- @return fun(token: CharacterToken) paint
local function VolumeRow()
    --- @type nil|string
    local snapshot = nil
    local slider
    local row
    slider = gui.Slider{
        width = "100%-60",
        height = 20,
        sliderWidth = 120,
        labelFormat = "rawpercent",
        labelWidth = 46,
        valign = "center",
        minValue = 0,
        maxValue = 1,
        value = 1,
        events = {
            change = function(element)
                local token = Token()
                if token == nil or not HeroSheetWrite.CanWrite() then
                    return
                end
                if snapshot == nil then
                    local live, shot = HeroSheetWrite.PreviewAppearance()
                    if live == nil or shot == nil then
                        return
                    end
                    token = live
                    snapshot = shot
                end
                token.anthemVolume = element.value
                --a preview plays at the look's volume, whichever sound it is.
                if g_audition.instance ~= nil then
                    g_audition.instance.volume = element.value
                end
            end,
            confirm = function(element)
                local shot = snapshot
                snapshot = nil
                if shot ~= nil then
                    HeroSheetWrite.CommitAppearance(shot)
                    HeroSheetRefresh.Changed()
                end
            end,
        },
    }
    row = gui.Panel{
        width = "100%",
        height = 26,
        flow = "horizontal",
        Text{
            classes = {"heroSheetCardText"},
            text = "Volume",
            fontSize = 13,
            width = 60,
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        slider,
    }
    --- @param token CharacterToken
    local function Paint(token)
        local anthem = token.anthem
        local idle = (anthem == nil or anthem == "") and not Auditioning(nil)
        --each part dims itself: a panel's opacity does not reach its children.
        row:SetClassTree("heroSheetDisabled", idle or not HeroSheetWrite.CanWrite())
        if snapshot == nil then
            slider.value = token.anthemVolume or 1
        end
    end
    return row, Paint
end

--- Anthem: tabs, search, one scrolling list (No anthem
--- first), this look's anthem marked; picks save as you go. Upload audio or
--- drop a sound on the window; the Director, or whoever uploaded a sound,
--- renames or deletes it from its right-click menu.
local function AnthemWindow()
    local token = Token()
    if token == nil then
        return
    end
    local tabs = {
        {id = "all", text = "All"},
        {id = "music", text = "Music"},
        {id = "effects", text = "Effects"},
        {id = "uploads", text = "Your uploads"},
    }
    --opens on Music, unless this look's anthem is something else.
    local tab = "music"
    local current = token.anthem
    if current ~= nil and current ~= "" and assets.audioTable[current] ~= nil and assets.audioTable[current].category ~= "music" then
        tab = "all"
    end
    local search = ""
    --- @type string[] "" for No anthem
    local ids = {}
    --- @type table<string, boolean>
    local uploads = {}
    local first = -1
    local poolRows = {}
    local tabPanels = {}
    local holder, content, poolColumn, empty
    local watcher = {}

    --- The rows for the open tab and search, by name.
    local function Build()
        uploads = {}
        local mine = UploadedSounds()
        for _, id in ipairs(mine) do
            uploads[id] = true
        end
        local found = nil
        if search ~= "" then
            found = {}
            for _, id in ipairs(dmhub.SearchSounds(search)) do
                found[id] = true
            end
        end
        local list = {}
        local source = {}
        if tab == "uploads" then
            source = mine
        else
            for id, _ in pairs(assets.audioTable) do
                source[#source+1] = id
            end
        end
        for _, id in ipairs(source) do
            local asset = assets.audioTable[id]
            local keep = asset ~= nil and not asset.hidden and (found == nil or found[id])
            if keep and tab == "music" then
                keep = asset.category == "music"
            elseif keep and tab == "effects" then
                keep = asset.category == "effects"
            end
            if keep then
                list[#list+1] = id
            end
        end
        table.sort(list, function(left, right)
            return string.lower(SoundName(left)) < string.lower(SoundName(right))
        end)
        if search == "" then
            table.insert(list, 1, "")
        end
        ids = list
        local hasSounds = #list > 0 and not (#list == 1 and list[1] == "")
        --the empty message shows only on Your uploads, or for a search.
        empty:SetClass("collapsed", hasSounds or (tab ~= "uploads" and search == ""))
        empty.text = cond(search ~= "", "No sounds match.", "Sounds you upload show here.")
        content.selfStyle.height = math.max(#ids * ANTHEM_ROW_H, 1)
    end

    local function PaintRows()
        for _, row in ipairs(poolRows) do
            row.data.paint()
        end
    end

    --- One pool row, painted from the sound it shows now.
    --- @return Panel
    local function Row()
        local row
        local play, paintPlay = PlayButton(30, function(element)
            local id = row.data.id
            if id == nil or id == "" then
                return
            end
            if Auditioning(id) then
                StopAudition()
            else
                local live = Token()
                PlayAudition(id, live ~= nil and live.anthemVolume or 1)
            end
        end)
        local name = Text{
            classes = {"heroSheetCardStrong"},
            text = "",
            fontSize = 14,
            bold = true,
            width = "100%",
            height = 20,
            textWrap = false,
            textOverflow = "ellipsis",
            interactable = false,
        }
        local sub = Text{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 12,
            width = "100%",
            height = 16,
            textWrap = false,
            interactable = false,
        }
        local mark = gui.Panel{
            classes = {"collapsed"},
            width = 150,
            height = 20,
            flow = "horizontal",
            halign = "right",
            valign = "center",
            interactable = false,
            gui.Panel{
                classes = {"heroSheetCheckMark"},
                bgimage = "phosphor/check-bold.png",
                width = 12,
                height = 12,
                halign = "right",
                valign = "center",
                rmargin = 6,
            },
            Text{
                classes = {"heroSheetCardStrong"},
                text = "This look's anthem",
                fontSize = 12,
                halign = "right",
                valign = "center",
                textWrap = false,
            },
        }
        local playSlot = gui.Panel{
            width = 30,
            height = 30,
            rmargin = 12,
            halign = "left",
            valign = "center",
            play,
        }
        row = gui.Panel{
            classes = {"heroLookTile", "hoverable", "collapsed"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 6,
            width = "100%",
            height = ANTHEM_ROW_H - 6,
            bmargin = 6,
            hpad = 10,
            borderBox = true,
            flow = "horizontal",
            data = {},
            click = function(element)
                local id = element.data.id
                if id ~= nil then
                    UseAnthem(id)
                    PaintRows()
                end
            end,
            rightClick = function(element)
                local id = element.data.id
                if id == nil or id == "" or not CanEditSound(id) then
                    return
                end
                local function Refill()
                    Build()
                    first = -1
                    PaintRows()
                end
                HeroSheetLists.ShowMenu(element, {
                    {text = "Rename", click = function()
                        RenameSoundWindow(id, Refill)
                    end},
                    {text = "Delete from the library", danger = true, click = function()
                        ConfirmDeleteSound(id, Refill)
                    end},
                }, nil, {below = true})
            end,
            playSlot,
            gui.Panel{
                width = "100%-200",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "center",
                interactable = false,
                name,
                sub,
            },
            mark,
        }
        row.data.paint = function()
            local id = ids[row.data.index or 0]
            row:SetClass("collapsed", id == nil)
            row.data.id = id
            if id == nil then
                return
            end
            local live = Token()
            local anthem = live ~= nil and live.anthem or nil
            if anthem == "" then
                anthem = nil
            end
            local chosen = (id == "" and anthem == nil) or (id ~= "" and id == anthem)
            row:SetClass("selected", chosen)
            mark:SetClass("collapsed", not chosen)
            playSlot:SetClass("hidden", id == "")
            if id == "" then
                name.text = "No anthem"
                sub.text = "Nothing plays on your turn"
            else
                name.text = SoundName(id)
                sub.text = SoundSub(id, uploads)
                paintPlay(Auditioning(id))
            end
        end
        return row
    end

    for i = 1, ANTHEM_POOL do
        poolRows[i] = Row()
    end
    poolColumn = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        children = poolRows,
    }
    content = gui.Panel{
        width = "100%-12",
        height = 1,
        flow = "none",
        halign = "left",
        valign = "top",
        poolColumn,
    }
    empty = Text{
        classes = {"heroSheetMuted", "collapsed"},
        text = "",
        fontSize = 14,
        width = "100%",
        height = 30,
        textAlignment = "center",
        valign = "center",
        floating = true,
    }

    --- Show the rows from the one at the top of the view (as the Art window).
    local function Scroll()
        if not holder.valid then
            return
        end
        local top = 0
        local range = #ids * ANTHEM_ROW_H - ANTHEM_LIST_H
        if range > 0 and holder.vscroll then
            --vscrollPosition runs 1 at the top to 0 at the bottom.
            top = (1 - (holder.vscrollPosition or 1)) * range
        end
        local start = math.floor(top / ANTHEM_ROW_H) + 1
        if start == first then
            return
        end
        first = start
        poolColumn.selfStyle.tmargin = (start - 1) * ANTHEM_ROW_H
        for i, row in ipairs(poolRows) do
            row.data.index = start + i - 1
            row.data.paint()
        end
    end

    holder = gui.Panel{
        width = "100%",
        height = ANTHEM_LIST_H,
        flow = "vertical",
        thinkTime = 0.03,
        think = function(element)
            Scroll()
        end,
        content,
        empty,
    }

    --- A fresh tab or search: rebuild the rows, back to the top.
    local function Refill()
        Build()
        holder.vscroll = false
        first = -1
        Scroll()
        --built without scrolling, then scrolling turned on once laid out:
        --building under a scroll view costs more per panel.
        HeroSheetWindow.AfterLayout(function()
            if not holder.valid then
                return
            end
            holder.vscroll = #ids * ANTHEM_ROW_H > ANTHEM_LIST_H
            holder.vscrollPosition = 1
        end)
    end

    local strip = gui.Panel{
        width = "100%",
        height = 30,
        flow = "horizontal",
        bmargin = 10,
    }
    for _, spec in ipairs(tabs) do
        local tabPanel = gui.Panel{
            classes = {"heroSheetListTabFrame", "hoverable"},
            bgimage = "panels/square.png",
            border = {x1 = 0, y1 = 2, x2 = 0, y2 = 0},
            width = "auto",
            height = 26,
            rmargin = 16,
            halign = "left",
            valign = "bottom",
            click = function(element)
                tab = spec.id
                for id, panel in pairs(tabPanels) do
                    panel:SetClassTree("selected", id == spec.id)
                end
                Refill()
            end,
            Text{
                classes = {"heroSheetListTab"},
                text = string.upper(spec.text),
                fontSize = 13,
                bold = true,
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        }
        tabPanels[spec.id] = tabPanel
        strip:AddChild(tabPanel)
    end
    tabPanels[tab]:SetClassTree("selected", true)

    local searchField = Field{
        text = "",
        placeholder = "Search sounds",
        search = true,
        edit = function(text)
            local trimmed = trim(text or "")
            if trimmed ~= search then
                search = trimmed
                Refill()
            end
        end,
    }

    local volume, paintVolume = VolumeRow()
    local function ChooseFile()
        if not HeroSheetWrite.CanWrite() then
            return
        end
        dmhub.OpenFileDialog{
            id = "AudioAssets",
            extensions = SOUND_EXTENSIONS,
            multiFiles = false,
            prompt = "Choose audio to load",
            open = function(path)
                UploadSound(path, function()
                    Refill()
                end)
            end,
        }
    end
    local uploadButton = SmallButton{
        text = "Upload audio",
        icon = "phosphor/upload-simple-bold.png",
        click = function()
            ChooseFile()
        end,
    }
    local footerLeft = gui.Panel{
        width = 520,
        height = 36,
        flow = "horizontal",
        halign = "left",
        valign = "center",
        uploadButton,
        Text{
            classes = {"heroSheetCardSub"},
            --every format the old sheet's picker takes.
            text = "mp3, ogg, wav, flac, m4a",
            fontSize = 12,
            rmargin = 14,
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        gui.Panel{
            width = 190,
            height = 26,
            halign = "left",
            valign = "center",
            volume,
        },
    }

    local body = gui.Panel{
        width = "100%",
        height = 30 + 10 + 30 + 10 + ANTHEM_LIST_H,
        flow = "vertical",
        --a sound file dropped anywhere on the window uploads it.
        dragAndDropExtensions = map(SOUND_EXTENSIONS, function(ext) return "." .. ext end),
        dropfiles = function(element, files)
            if files ~= nil and files[1] ~= nil then
                UploadSound(files[1], function()
                    Refill()
                end)
            end
        end,
        create = function(element)
            g_auditionWatchers[watcher] = function()
                PaintRows()
                local live = Token()
                if live ~= nil then
                    paintVolume(live)
                end
            end
        end,
        --closing the window stops the preview.
        destroy = function(element)
            g_auditionWatchers[watcher] = nil
            StopAudition()
        end,
        strip,
        gui.Panel{
            width = "100%",
            height = 30,
            flow = "horizontal",
            bmargin = 10,
            gui.Panel{
                width = 320,
                height = 30,
                halign = "left",
                searchField,
            },
            Text{
                classes = {"heroSheetCardSub"},
                text = "Drop a sound here to upload it.",
                fontSize = 12.5,
                halign = "right",
                valign = "center",
                textWrap = false,
            },
        },
        holder,
    }

    paintVolume(token)
    Refill()
    HeroSheetWindow.ShowDialog{
        title = "Anthem",
        subtitle = token.name,
        width = ANTHEM_WINDOW_W,
        bodyHeight = 30 + 10 + 30 + 10 + ANTHEM_LIST_H,
        body = HeroSheetRefresh.Block({
            width = "100%",
            height = "auto",
            flow = "vertical",
            body,
        }, {
            name = "anthem window",
            signature = function(live)
                return string.format("%s|%.3f|%s", tostring(live.anthem), live.anthemVolume or 1, tostring(HeroSheetWrite.CanWrite()))
            end,
            refresh = function(panel, live)
                paintVolume(live)
                PaintRows()
            end,
        }),
        footerLeft = footerLeft,
        onDone = function() end,
    }
end

--- The Anthem block beside Looks: play this look's anthem, its
--- name, Change, and its volume.
--- @return Panel block
--- @return Panel plate the plate a matched Row lines up
local function BuildAnthem()
    local watcher = {}
    local play, paintPlay
    local name
    local volume, paintVolume
    local change
    local block, hint

    --- @param token CharacterToken
    local function Paint(token)
        local anthem = token.anthem
        local has = anthem ~= nil and anthem ~= "" and assets.audioTable[anthem] ~= nil
        hint.text = string.format("Plays when %s starts a turn.", token.name or "this Hero")
        name.text = cond(has, SoundName(anthem), "No anthem")
        play:SetClass("heroSheetOff", not has)
        paintPlay(has and Auditioning(anthem))
        change:SetClass("heroSheetOff", not HeroSheetWrite.CanWrite())
        paintVolume(token)
    end

    play, paintPlay = PlayButton(34, function(element)
        local token = Token()
        if token == nil or token.anthem == nil or token.anthem == "" then
            return
        end
        if Auditioning(token.anthem) then
            StopAudition()
        else
            PlayAudition(token.anthem, token.anthemVolume or 1)
        end
    end)
    name = Text{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 15,
        bold = true,
        width = "100%",
        height = 20,
        textWrap = false,
        textOverflow = "ellipsis",
    }
    change = SmallButton{
        text = "Change",
        click = function()
            AnthemWindow()
        end,
    }
    change.selfStyle.halign = "right"
    change.selfStyle.rmargin = 0
    volume, paintVolume = VolumeRow()
    volume.selfStyle.tmargin = 8

    block, hint = Block("Anthem", "", gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Panel{
            width = "100%",
            height = 40,
            flow = "horizontal",
            play,
            gui.Panel{
                width = "100%-140",
                height = "auto",
                flow = "vertical",
                lmargin = 10,
                halign = "left",
                valign = "center",
                name,
                Text{
                    classes = {"heroSheetCardSub"},
                    text = "This look's anthem",
                    fontSize = 12,
                    width = "100%",
                    height = 16,
                    textWrap = false,
                },
            },
            change,
        },
        volume,
    })

    local blockPanel = HeroSheetRefresh.Block({
        width = "100%",
        height = "auto",
        flow = "vertical",
        create = function(element)
            g_auditionWatchers[watcher] = function()
                local token = Token()
                if token ~= nil then
                    Paint(token)
                end
            end
        end,
        destroy = function(element)
            g_auditionWatchers[watcher] = nil
        end,
        block,
    }, {
        name = "appearance anthem",
        signature = function(token)
            return string.format("%s|%.3f|%s|%s", tostring(token.anthem), token.anthemVolume or 1, tostring(token.name), tostring(HeroSheetWrite.CanWrite()))
        end,
        refresh = function(panel, token)
            Paint(token)
        end,
    })
    return blockPanel, block
end

----------------------------------------------------------------------
--The Effects tab: Light beside a night preview,
--Footprints, Blood, Dice and the developers' Teleport. These belong to the
--Hero, not a look; each pick saves at once as one undo step.

--the dice laid out as the Dice panel lays them: the Power
--Roll pair over a rule, then 3, 6 and 10. Sizes at scale 1 (the tab).
local DICE_PAIR_DIE = 84
local DICE_SMALL_DIE = 58
--the Dice window: the same layout bigger, the slot switch, then the grid.
local DICE_SHOWCASE_SCALE = 1.25
local DICE_SPOT_W = 80
local DICE_SPOT_GAP = 8
local DICE_SPOT_DIE = 56
local DICE_WINDOW_COLUMNS = 8
local DICE_WINDOW_W = DICE_WINDOW_COLUMNS * (DICE_SPOT_W + DICE_SPOT_GAP) + 64
local DICE_WINDOW_H = 600
local DICE_GRID_H = 290
--the live die's scale in its render, matched to the still die's framing.
local DICE_LIVE_SCALE = 5.5
--how long the pointer rests on a die before it spins (seconds).
local DICE_SPIN_DELAY = 0.15

--the layout's three dice, one per loadout slot: the power roll pair and the
--d6 (which d3 rolls also use). Its shape and size.
local DICE_FACES = {
    {id = "p1", key = "model", geo = "d10", size = DICE_PAIR_DIE},
    {id = "p2", key = "model2", geo = "d10", size = DICE_PAIR_DIE},
    {id = "d6", key = "modelD6", geo = "d6", size = DICE_SMALL_DIE},
}

--the Dice window's slots: a pick in All dice sets every die and clears any
--mix; the other two change only their own dice. tip is the slot's tooltip.
local DICE_SLOTS = {
    {key = "model", geo = "d10", text = "All dice", inherit = "Use my dice",
        dice = {p1 = true, p2 = true, d6 = true},
        tip = "Use my dice rolls whatever dice the roller has equipped."},
    {key = "model2", geo = "d10", text = "2nd power die", inherit = "Same as dice",
        dice = {p2 = true}, tip = "Power rolls pair your dice with this set."},
    {key = "modelD6", geo = "d6", text = "D3 / D6", inherit = "Same as dice",
        dice = {d6 = true}, tip = "A different set for d3 and d6 rolls."},
}

--- @class HeroEffectsOption
--- @field id string
--- @field text string

--- A row of choices, one selected; it wraps. The choices are rebuilt only
--- when the options themselves change, else repainted.
--- @param pick fun(id: string)
--- @param buildChoice fun(option: HeroEffectsOption, click: fun(element: Panel)): Panel builds one choice
--- @param selectTree boolean mark the choice's children selected too (a pill's label)
--- @return Panel row
--- @return fun(options: HeroEffectsOption[], selected: string, writable: boolean) paint
local function ChoiceRow(pick, buildChoice, selectTree)
    local row = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
    }
    local shape = nil
    --- @type table<string, Panel>
    local choices = {}

    --- @param options HeroEffectsOption[]
    --- @param selected string
    --- @param writable boolean
    local function Paint(options, selected, writable)
        local parts = {}
        for _, option in ipairs(options) do
            parts[#parts+1] = option.id .. "=" .. option.text
        end
        local key = table.concat(parts, "|")
        if key ~= shape then
            shape = key
            choices = {}
            local children = {}
            for _, option in ipairs(options) do
                local choice = buildChoice(option, function(element)
                    if not element:HasClass("heroSheetOff") then
                        pick(option.id)
                    end
                end)
                choices[option.id] = choice
                children[#children+1] = choice
            end
            row.children = children
        end
        for id, choice in pairs(choices) do
            if selectTree then
                choice:SetClassTree("selected", id == selected)
            else
                choice:SetClass("selected", id == selected)
            end
            choice:SetClass("heroSheetOff", not writable)
        end
    end
    return row, Paint
end

--- A row of pills, one choice selected; it wraps.
--- @param pick fun(id: string)
--- @return Panel row
--- @return fun(options: HeroEffectsOption[], selected: string, writable: boolean) paint
local function PillRow(pick)
    return ChoiceRow(pick, function(option, click)
        return gui.Panel{
            classes = {"heroSheetButton", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 13,
            width = "auto",
            height = 26,
            hpad = 12,
            borderBox = true,
            rmargin = 6,
            bmargin = 6,
            halign = "left",
            click = click,
            Text{
                classes = {"heroSheetButtonLabel"},
                text = option.text,
                --always bold: a selected pill keeps its width.
                bold = true,
                fontSize = 13,
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        }
    end, true)
end

--a Footprints or Blood tile: its picture over its name (two lines).
local TRACE_TILE_W = 84
local TRACE_TILE_H = 108
local TRACE_PICTURE_W = 76
local TRACE_PICTURE_H = 64

--- A row of picture tiles, one choice selected; it wraps.
--- @param pick fun(id: string)
--- @param picture fun(id: string): Panel draws a choice, built with its tile
--- @return Panel row
--- @return fun(options: HeroEffectsOption[], selected: string, writable: boolean) paint
local function TileRow(pick, picture)
    return ChoiceRow(pick, function(option, click)
        return gui.Panel{
            classes = {"heroLookTile", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = TRACE_TILE_W,
            height = TRACE_TILE_H,
            rmargin = 8,
            bmargin = 8,
            halign = "left",
            flow = "vertical",
            click = click,
            picture(option.id),
            Text{
                classes = {"heroSheetCardText"},
                text = option.text,
                fontSize = 11,
                width = TRACE_TILE_W - 6,
                height = 28,
                tmargin = 4,
                halign = "center",
                valign = "top",
                textAlignment = "top",
                textWrap = true,
                textOverflow = "ellipsis",
                interactable = false,
            },
        }
    end, false)
end

--- A style's prints walking up a patch of snow, laid as the map lays them,
--- the left foot mirrored; darker than the map's faint prints so they read
--- at this size. A style with no art (Basic, the engine's generated boot) or
--- None shows the snow alone.
--- @param id string
--- @return Panel
local function FootprintPicture(id)
    local patch = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "#dde4e8",
        cornerRadius = 6,
        width = TRACE_PICTURE_W,
        height = TRACE_PICTURE_H,
        halign = "center",
        tmargin = 4,
        flow = "none",
        interactable = false,
    }
    local style = nil
    pcall(function() style = FootprintStyle.GetStyle(id) end)
    if id == FootprintStyle.noneId or style == nil then
        return patch
    end
    --Basic is the engine's generated boot: no art, so draw a sole and heel.
    local generated = style.imageid == nil or style.imageid == ""
    --a print's size follows its length: 18 units for a 0.3-tile print.
    local size = math.clamp(math.floor(18 * (style.length or 0.3) / 0.3 + 0.5), 10, 28)
    local prints = {}
    local count = cond(style.alternate == false, 3, 4)
    local step = math.floor((TRACE_PICTURE_H - size) / math.max(1, count - 1))
    for i = 1, count do
        local left = style.alternate ~= false and i % 2 == 1
        local printLeft = TRACE_PICTURE_W / 2 - size / 2
        if style.alternate ~= false then
            printLeft = printLeft + cond(left, -7, 7)
        end
        local sole = math.floor(size * 0.42 + 0.5)
        prints[#prints+1] = gui.Panel{
            bgimage = cond(generated, nil, style.imageid),
            bgcolor = cond(generated, "clear", "#000000c0"),
            width = size,
            height = size,
            halign = "left",
            valign = "top",
            floating = true,
            lmargin = math.floor(printLeft + 0.5),
            tmargin = TRACE_PICTURE_H - size - (i - 1) * step,
            --the left foot is the right one mirrored.
            imageRect = cond(left and not generated, {x1 = 1, y1 = 0, x2 = 0, y2 = 1}, nil),
            interactable = false,
            children = generated and {
                gui.Panel{
                    bgimage = "panels/square.png",
                    bgcolor = "#000000c0",
                    cornerRadius = sole / 2,
                    width = sole,
                    height = math.floor(size * 0.58 + 0.5),
                    halign = "center",
                    valign = "top",
                    interactable = false,
                },
                gui.Panel{
                    bgimage = "panels/square.png",
                    bgcolor = "#000000c0",
                    cornerRadius = sole / 2,
                    width = math.floor(sole * 0.85 + 0.5),
                    height = math.floor(size * 0.3 + 0.5),
                    halign = "center",
                    valign = "bottom",
                    interactable = false,
                },
            } or nil,
        }
    end
    patch.children = prints
    return patch
end

--- A big splatter in a blood colour on pale stone: the red art, turned to
--- the colour's hue as the map recolours it. None shows the stone alone.
--- @param id string
--- @return Panel
local function BloodPicture(id)
    local patch = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "#cfc7bb",
        cornerRadius = 6,
        width = TRACE_PICTURE_W,
        height = TRACE_PICTURE_H,
        halign = "center",
        tmargin = 4,
        flow = "none",
        interactable = false,
    }
    if id == BloodSpatter.noneColor then
        return patch
    end
    local recolor = nil
    for _, colour in ipairs(BloodSpatter.colors) do
        if colour.id == id then
            recolor = colour.recolor
        end
    end
    patch.children = {
        gui.Panel{
            bgimage = "blood/splatter-1.png",
            bgcolor = "white",
            width = 62,
            height = 62,
            halign = "center",
            valign = "center",
            --the colour's hue, 0 to 1.
            hueshift = recolor ~= nil and core.Color(recolor).h or 0,
            interactable = false,
        },
    }
    return patch
end

--- The light sources a Hero may pick (the same list the old character sheet
--- offered): None, the lights anyone
--- may carry, the ones its features grant, and the one in its hand.
--- @param token CharacterToken
--- @return HeroEffectsOption[]
local function LightOptions(token)
    local props = token.properties
    local items = dmhub.GetTable(equipment.tableName)
    local custom = {}
    pcall(function() custom = props:GetCustomLightSources() end)
    local held = TokenLight(token)
    local options = {}
    for id, entry in unhidden_pairs(items) do
        if EquipmentCategory.IsLightSource(entry) and (entry:try_get("availability", "available") == "available" or custom[id] or id == held) then
            options[#options+1] = {id = id, text = entry.name}
        end
    end
    table.sort(options, function(left, right) return left.text < right.text end)
    table.insert(options, 1, {id = "none", text = "None"})
    return options
end

--- Choices with the ancestry's own marked, as "<name> . ancestry".
--- @param options HeroEffectsOption[]
--- @param ancestry string the id the creature has when nothing is stored
--- @return HeroEffectsOption[]
local function MarkAncestry(options, ancestry)
    local result = {}
    for _, option in ipairs(options) do
        local text = option.text
        if option.id == ancestry then
            --"\xC2\xB7" is a middle dot: Lua source stays ASCII.
            text = string.format("%s \xC2\xB7 ancestry", text)
        end
        result[#result+1] = {id = option.id, text = text}
    end
    return result
end

--- The id a body trait (footprints, blood) has with nothing stored: the
--- ancestry's, else the trait's default.
--- @param props creature
--- @param field string
--- @param default string
--- @return string
local function AncestryTrait(props, field, default)
    local value = nil
    pcall(function() value = props:GetDefaultBodyTrait(field) end)
    if value == nil or value == "" then
        return default
    end
    return value
end

--- The dice sets this account owns, by name (the old sheet's picker's list).
--- @return {id: string, text: string}[]
local function OwnedDice()
    local sets = {}
    local ok, list = pcall(function() return dice.GetAvailableDice() end)
    if ok and type(list) == "table" then
        for _, entry in ipairs(list) do
            if entry ~= nil and entry.value ~= nil and entry.value ~= "" then
                sets[#sets+1] = {id = entry.value, text = entry.text or entry.value}
            end
        end
    end
    table.sort(sets, function(left, right) return left.text < right.text end)
    return sets
end

--- A dice set's name: every registered set, so one the token keeps from
--- another account still reads right.
--- @param id string
--- @return string
local function DiceName(id)
    for _, set in ipairs(OwnedDice()) do
        if set.id == id then
            return set.text
        end
    end
    --every registered set lists as {id, text}; some have no name.
    local name = nil
    pcall(function()
        for _, entry in ipairs(dice.GetAllDice()) do
            if entry.id == id and entry.text ~= nil and entry.text ~= "" then
                name = entry.text
            end
        end
    end)
    return name or id
end

--- The set an uncustomised row rolls: the account's equipped dice (read as
--- the old sheet reads them), or for the extra rows the loadout's first set.
--- @param key string
--- @param loadout table
--- @return string
local function InheritedDice(key, loadout)
    if key ~= "model" and loadout.model ~= nil then
        return loadout.model
    end
    local equipped = dmhub.GetSettingValue("diceequipped")
    if equipped == nil or equipped == "" then
        equipped = "Default"
    end
    if key == "model" then
        return equipped
    end
    local id = dmhub.GetSettingValue(cond(key == "model2", "diceequipped2", "diceequippedd6"))
    if id == nil or id == "" then
        return equipped
    end
    return id
end

--- A die that rests still and spins while hovered, like the Dice panel's.
--- The still die is rendered once and cached, so resting dice cost nothing
--- per frame. The spinning die is a live render that exists only while
--- hovered; the engine frees it shortly after no panel shows it.
--- Each picture is its own panel, built once and then shown or hidden:
--- giving a drawn panel a different dice picture shows a white square
--- behind the die, and swapping children relays out the window.
--- @param size number
--- @param seq string keeps this die's live render apart from other dice of the same set
--- @return Panel die, fun(set: nil|string, geo: string) show, fun(on: boolean) spin, fun(set: string, geo: string): Panel preload
local function Die(size, seq)
    local die = gui.Panel{
        width = size,
        height = size,
        halign = "center",
        interactable = false,
    }
    --wanted: the pointer is on the die; ticket cancels a pending start.
    local state = {set = nil, geo = "d10", spinning = false, wanted = false, ticket = 0}
    --- @type nil|Panel
    local still = nil
    --- @type nil|Panel
    local live = nil
    --- @type table<string, Panel> each still die shown so far, by its picture
    local stills = {}

    --- @param image string
    --- @param blend nil|string
    --- @return Panel
    local function Layer(image, blend)
        return gui.Panel{
            bgimage = image,
            bgcolor = "white",
            blend = blend,
            width = size,
            height = size,
            floating = true,
            halign = "center",
            valign = "center",
            interactable = false,
        }
    end

    local function Start()
        state.spinning = true
        live = Layer(string.format("#DicePreview:%s:%s:%.2f:0:%d", tostring(state.set), seq,
            DICE_LIVE_SCALE, cond(state.geo == "d6", 6, 10)), "premultiplied")
        die:AddChild(live)
        --the live render takes a few frames to arrive: keep the still
        --die showing until then, so the die never blinks out.
        dmhub.Schedule(0.1, function()
            if mod.unloaded or still == nil or not still.valid or not state.spinning then
                return
            end
            still:SetClass("hidden", true)
        end)
    end

    local function Stop()
        state.ticket = state.ticket + 1
        if not state.spinning then
            return
        end
        state.spinning = false
        --once the live layer is gone, nothing shows the render and the engine frees it.
        if live ~= nil and live.valid then
            live:DestroySelf()
        end
        live = nil
        if still ~= nil then
            still:SetClass("hidden", false)
        end
    end

    --building a set's live die stalls a frame, so a die spins only once the
    --pointer rests on it: sweeping across the grid builds none.
    local function Arm()
        state.ticket = state.ticket + 1
        local ticket = state.ticket
        dmhub.Schedule(DICE_SPIN_DELAY, function()
            if mod.unloaded or not die.valid or ticket ~= state.ticket then
                return
            end
            if state.wanted and not state.spinning and state.set ~= nil then
                Start()
            end
        end)
    end

    --- @param on boolean
    local function Spin(on)
        state.wanted = on
        if not on then
            Stop()
        elseif not state.spinning then
            Arm()
        end
    end

    --- Builds a set's still die, hidden, so showing it later costs nothing.
    --- @param set string
    --- @param geo string
    --- @return Panel
    local function Preload(set, geo)
        local image = string.format("#DiceIcon:%s:%s", set, geo)
        local layer = stills[image]
        if layer == nil then
            layer = Layer(image)
            layer:SetClass("collapsed", true)
            stills[image] = layer
            die:AddChild(layer)
        end
        return layer
    end

    --- @param set nil|string
    --- @param geo string
    local function Show(set, geo)
        if set == state.set and geo == state.geo then
            return
        end
        Stop()
        state.set = set
        state.geo = geo
        if still ~= nil then
            still:SetClass("collapsed", true)
        end
        still = nil
        if set ~= nil then
            still = Preload(set, geo)
            still:SetClass("collapsed", false)
        end
        if state.wanted then
            Arm()
        end
    end

    return die, Show, Spin, Preload
end

--- One die spot on a tray: the set's die and its name; a click picks it.
--- @param args {size: number, width: number, seq: string, pick: fun(id: string), hover: nil|fun(spot: Panel, on: boolean)}
--- hover replaces spinning the spot's own die (the Dice window spins its showcase instead).
--- @return Panel
local function DieSpot(args)
    local die, showDie, spin = Die(args.size, args.seq)
    --names run to two lines ("Circle of Spring Dice"), then end in "...".
    local name = Text{
        classes = {"heroSheetCardText"},
        text = "",
        fontSize = 11,
        width = args.width - 6,
        height = 28,
        tmargin = 2,
        halign = "center",
        valign = "top",
        textAlignment = "top",
        textWrap = true,
        textOverflow = "ellipsis",
        interactable = false,
    }
    local spot = gui.Panel{
        classes = {"heroDiceSpot"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 8,
        width = args.width,
        height = "auto",
        vpad = 4,
        borderBox = true,
        halign = "left",
        flow = "vertical",
        data = {},
        linger = function(element)
            if element.data.text ~= nil then
                gui.Tooltip(element.data.text)(element)
            end
        end,
        hover = function(element)
            if args.hover ~= nil then
                args.hover(element, true)
            else
                spin(true)
            end
        end,
        dehover = function(element)
            if args.hover ~= nil then
                args.hover(element, false)
            else
                spin(false)
            end
        end,
        click = function(element)
            if element.data.id ~= nil and not element:HasClass("heroSheetOff") then
                args.pick(element.data.id)
            end
        end,
        die,
        name,
    }
    --- @param id nil|string the set it picks ("" inherits), nil to hide
    --- @param text string
    --- @param shows string the set whose die it shows
    --- @param geo string
    --- @param selected boolean
    --- @param writable boolean
    spot.data.paint = function(id, text, shows, geo, selected, writable)
        spot:SetClass("collapsed", id == nil)
        spot.data.id = id
        spot.data.text = text
        spot.data.shows = shows
        spot.data.geo = geo
        if id == nil then
            spin(false)
            return
        end
        showDie(shows, geo)
        name.text = text
        spot:SetClass("selected", selected)
        spot:SetClass("heroSheetOff", not writable)
        --dimmed when it takes no clicks (a die following Dice, view only).
        spot:SetClassTree("heroSheetDisabled", not writable)
    end
    spot.data.stop = function()
        spin(false)
    end
    return spot
end

--- The set each of the layout's dice rolls with, by die id (p1, p2, d6): the
--- loadout's sets, else what it inherits.
--- @param loadout table
--- @return table<string, string>
local function DiceSets(loadout)
    local main = loadout.model or InheritedDice("model", loadout)
    local second = loadout.model2 or InheritedDice("model2", loadout)
    local small = loadout.modelD6 or InheritedDice("modelD6", loadout)
    return {p1 = main, p2 = second, d6 = small}
end

--- @class HeroDiceLayoutDie one die of DiceLayout
--- @field pop Panel the die's panel, which grows on hover
--- @field show fun(set: nil|string, geo: string)
--- @field spin fun(on: boolean)
--- @field preload fun(set: string, geo: string): Panel

--- The Hero's dice: the power roll pair over a rule, then the d6. A die grows
--- when the pointer is on it and spins once the pointer rests (Die). No words
--- on the dice, so it reads as a preview rather than a roll.
--- @param args {scale: number, seq: string, click: nil|fun(id: string)}
--- click: a die was clicked (the Dice window picks its slot); nil, the dice take no clicks.
--- @return Panel panel
--- @return {paint: fun(sets: table<string, string>), dim: fun(lit: nil|table<string, boolean>), spin: fun(lit: table<string, boolean>, on: boolean), preload: fun(set: string), stop: fun()}
local function DiceLayout(args)
    local scale = args.scale
    --- @type table<string, HeroDiceLayoutDie>
    local dice = {}
    for _, face in ipairs(DICE_FACES) do
        local spec = face
        local size = math.floor(spec.size * scale)
        local die, show, spin, preload = Die(size, args.seq .. spec.id)
        local pop = gui.Panel{
            classes = {"heroDicePop"},
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = size,
            height = size,
            halign = "center",
            valign = "center",
            hover = function(element)
                element:SetClass("heroDicePopped", true)
                spin(true)
            end,
            dehover = function(element)
                element:SetClass("heroDicePopped", false)
                spin(false)
            end,
            click = function()
                if args.click ~= nil then
                    args.click(spec.id)
                end
            end,
            die,
        }
        dice[spec.id] = {pop = pop, show = show, spin = spin, preload = preload}
    end

    --a small gap between the pair; the d6 below centres under it, since the
    --pair, rule and d6 all centre in the same column.
    local pairGap = math.floor(12 * scale)
    dice.p2.pop.selfStyle.lmargin = pairGap
    local pairWidth = 2 * math.floor(DICE_PAIR_DIE * scale) + pairGap
    local pair = gui.Panel{
        width = pairWidth,
        height = math.floor(DICE_PAIR_DIE * scale),
        halign = "center",
        flow = "horizontal",
        dice.p1.pop,
        dice.p2.pop,
    }
    local panel = gui.Panel{
        width = "auto",
        height = "auto",
        halign = "center",
        flow = "vertical",
        pair,
        gui.Panel{
            classes = {"heroSheetDialogRule"},
            bgimage = "panels/square.png",
            width = math.floor(pairWidth * 1.4),
            height = 1,
            halign = "center",
            vmargin = math.floor(8 * scale),
        },
        dice.d6.pop,
    }

    local api = {}
    --- @param sets table<string, string> a set for each die id
    api.paint = function(sets)
        for _, face in ipairs(DICE_FACES) do
            dice[face.id].show(sets[face.id], face.geo)
        end
    end
    --- Dims every die not in lit (nil lights them all).
    --- @param lit nil|table<string, boolean>
    api.dim = function(lit)
        for id, entry in pairs(dice) do
            entry.pop:SetClassTree("heroSheetDisabled", lit ~= nil and not lit[id])
        end
    end
    --- @param lit table<string, boolean>
    --- @param on boolean
    api.spin = function(lit, on)
        for id, entry in pairs(dice) do
            entry.spin(on and lit[id] == true)
        end
    end
    --- Builds a set's still dice, hidden, so showing them later costs nothing.
    --- @param set string
    api.preload = function(set)
        for _, face in ipairs(DICE_FACES) do
            dice[face.id].preload(set, face.geo)
        end
    end
    api.stop = function()
        for _, entry in pairs(dice) do
            entry.pop:SetClass("heroDicePopped", false)
            entry.spin(false)
        end
    end
    return panel, api
end

--- A Hero's dice for the person viewing the sheet. The sheet's Dice is the
--- shop's class dice slot: the same account setting, set from another place.
---   key: the viewer's class dice slot ("class:<id>" or "class:<id>:<subclassid>"),
---        nil for a Hero with no class yet.
---   label: that slot's name as the shop shows it ("Summoner"), nil with no key.
---   loadout: the dice the viewer would roll for this Hero, as GetDiceLoadout
---        gives them (nil fields inherit the viewer's equipped dice).
---   slot: the class slot's own dice ("" fields inherit), nil when not activated.
---   writable: the viewer may change the class slot here.
---   reason: why not, for the Change dice tooltip: "player" (a Director on a
---        Hero they do not control) or "class" (no class yet). nil on a
---        view-only sheet, which opens the window to look only.
--- @param token CharacterToken
--- @return {key: nil|string, label: nil|string, loadout: table, slot: nil|table, writable: boolean, reason: nil|string}
function HeroSheetAppearance.DiceSource(token)
    local props = token.properties
    local diceSlots = rawget(_G, "DiceSlots")
    if diceSlots == nil then
        return {key = nil, loadout = props:GetDiceLoadout(), slot = nil, writable = false, reason = nil}
    end

    --what a roll would use: an activated slot, else the Hero's own dice if the
    --viewer owns them, else nil (the viewer's equipped dice).
    local rolled = diceSlots.RollLoadout(props, nil)
    local loadout = {}
    if rolled ~= nil then
        loadout = {
            model = rolled.model,
            model2 = rolled.model2 ~= "" and rolled.model2 or nil,
            modelD6 = rolled.modelD6 ~= "" and rolled.modelD6 or nil,
        }
    end

    local key = diceSlots.ClassKey(props)
    local result = {key = key, label = nil, loadout = loadout, slot = nil, writable = false, reason = nil}
    if key ~= nil then
        result.label = diceSlots.ClassLabel(key)
        result.slot = diceSlots.Loadout(key)
    end
    if not HeroSheetWrite.CanWrite() then
        return result
    end
    --a Director's class dice mean nothing to the player who rolls their Hero,
    --so a Director changes them only on a Hero with no owner or owned by them.
    local controls = token.canControlAsUser and (not dmhub.isDM or token.ownerId == nil or token.ownerId == dmhub.userid)
    if not controls then
        result.reason = "player"
    elseif key == nil then
        result.reason = "class"
    else
        result.writable = true
    end
    return result
end

--- Change dice: the Hero's dice over a slot switch and a
--- grid of every set you own. A pick saves at once; hovering a set shows it
--- in the slot's dice first.
local function DiceWindow()
    local token = Token()
    if token == nil then
        return
    end
    local sets = OwnedDice()
    local slot = DICE_SLOTS[1]
    --- @type nil|string the set the pointer is on in the grid ("" the inherit spot)
    local hovered = nil
    local spots = {}
    local switch = {}
    local Paint

    local showcase, showcaseApi = DiceLayout{
        scale = DICE_SHOWCASE_SCALE,
        seq = "herosheetshowcase",
        click = function(id)
            local live = Token()
            if live == nil then
                return
            end
            --a die picks the slot that changes it; the two extras need a set first.
            local key = cond(id == "p2", "model2", cond(id == "d6", "modelD6", "model"))
            if key ~= "model" and HeroSheetAppearance.DiceSource(live).slot == nil then
                return
            end
            for _, candidate in ipairs(DICE_SLOTS) do
                if candidate.key == key then
                    slot = candidate
                end
            end
            Paint()
        end,
    }

    --- The set a grid spot puts in the current slot ("" inherits).
    --- @param id string
    --- @param loadout table
    --- @return string
    local function Becomes(id, loadout)
        if id ~= "" then
            return id
        end
        if slot.key == "model" then
            return InheritedDice("model", {})
        end
        return InheritedDice(slot.key, {model = loadout.model})
    end

    Paint = function()
        local live = Token()
        if live == nil then
            return
        end
        local source = HeroSheetAppearance.DiceSource(live)
        local writable = source.writable
        --the grid marks the class slot's sets, or with no slot what rolls
        --(the Hero's own dice, else "" for the player's equipped dice).
        local current = source.slot or source.loadout
        --the 2nd die and D3/D6 add to a set the slot already has for All dice.
        local hasSet = source.slot ~= nil
        if slot.key ~= "model" and not hasSet then
            slot = DICE_SLOTS[1]
        end
        local shown = DiceSets(source.loadout)
        if hovered ~= nil then
            local set = Becomes(hovered, current)
            for id in pairs(slot.dice) do
                shown[id] = set
            end
        end
        showcaseApi.paint(shown)
        showcaseApi.dim(cond(slot.key == "model", nil, slot.dice))
        showcaseApi.spin(slot.dice, hovered ~= nil)

        for i, pill in ipairs(switch) do
            local candidate = DICE_SLOTS[i]
            local open = writable and (candidate.key == "model" or hasSet)
            pill:SetClassTree("selected", candidate == slot)
            pill:SetClass("heroSheetOff", not open)
            pill:SetClassTree("heroSheetDisabled", not open)
            local tip = candidate.tip
            if candidate.key == "model" and source.label ~= nil then
                local label = source.label
                if live.properties:GetDiceLoadout().model ~= nil then
                    tip = string.format("Clears your %s dice and %s's own dice: you roll the dice you have equipped.", label, live.name or "the Hero")
                else
                    tip = string.format("Clears your %s dice: you roll the dice you have equipped.", label)
                end
            end
            pill.data.tip = cond(open or not writable, tip, "Choose a set for All dice first.")
        end

        local chosen = current[slot.key] or ""
        for i, spot in ipairs(spots) do
            if i == 1 then
                spot.data.paint("", slot.inherit, Becomes("", current), slot.geo, chosen == "", writable)
            else
                local set = sets[i - 1]
                spot.data.paint(set.id, set.text, set.id, slot.geo, chosen == set.id, writable)
            end
        end
    end

    for i, candidate in ipairs(DICE_SLOTS) do
        local entry = candidate
        switch[i] = gui.Panel{
            classes = {"heroSheetButton", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 13,
            width = "auto",
            height = 26,
            hpad = 12,
            borderBox = true,
            rmargin = 6,
            halign = "left",
            data = {},
            linger = function(element)
                if element.data.tip ~= nil then
                    gui.Tooltip(element.data.tip)(element)
                end
            end,
            click = function(element)
                if not element:HasClass("heroSheetOff") then
                    slot = entry
                    Paint()
                end
            end,
            Text{
                classes = {"heroSheetButtonLabel"},
                text = entry.text,
                --always bold: a selected pill keeps its width.
                bold = true,
                fontSize = 13,
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        }
    end

    for i = 1, #sets + 1 do
        spots[i] = DieSpot{
            size = DICE_SPOT_DIE,
            width = DICE_SPOT_W,
            seq = "herosheetspot" .. i,
            pick = function(id)
                local key = slot.key
                local live = Token()
                if live == nil then
                    return
                end
                local source = HeroSheetAppearance.DiceSource(live)
                local diceSlots = rawget(_G, "DiceSlots")
                if not source.writable or source.key == nil or diceSlots == nil then
                    return
                end
                --the viewer's class slot, an account setting (no undo, as in the shop).
                local current = source.slot
                if key == "model" then
                    --All dice: one set for every die, so any mix goes.
                    diceSlots.Set(source.key, cond(id == "", nil, id))
                    if id == "" and live.properties:GetDiceLoadout().model ~= nil then
                        --Use my dice: the Hero's own dice would still roll otherwise.
                        HeroSheetWrite.Save{
                            description = "Change token dice",
                            execute = function(props)
                                props:ClearDiceLoadout()
                            end,
                        }
                    end
                elseif current ~= nil then
                    local model2 = cond(key == "model2", id, current.model2)
                    local modelD6 = cond(key == "modelD6", id, current.modelD6)
                    diceSlots.Set(source.key, current.model, model2, modelD6)
                end
                HeroSheetRefresh.Changed()
                Paint()
            end,
            hover = function(spot, on)
                if on then
                    hovered = spot.data.id
                elseif hovered == spot.data.id then
                    hovered = nil
                end
                Paint()
            end,
        }
        spots[i].selfStyle.rmargin = DICE_SPOT_GAP
        spots[i].selfStyle.bmargin = DICE_SPOT_GAP
    end
    Paint()

    local grid = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        valign = "top",
        children = spots,
    }
    local scroller = gui.Panel{
        width = "100%",
        height = DICE_GRID_H,
        tmargin = 12,
        flow = "vertical",
        grid,
    }
    local holder = gui.Panel{
        width = "100%",
        height = DICE_WINDOW_H,
        flow = "vertical",
        gui.Panel{
            width = "100%",
            --what the grid (and its 12 margin) and the slot switch (26, and its
            --16 margin) below leave.
            height = DICE_WINDOW_H - DICE_GRID_H - 12 - 26 - 16,
            flow = "vertical",
            showcase,
        },
        gui.Panel{
            width = "100%",
            height = 26,
            tmargin = 16,
            flow = "horizontal",
            children = switch,
        },
        scroller,
    }
    local opened = HeroSheetAppearance.DiceSource(token)
    local subtitle = token.name
    if opened.writable and opened.label ~= nil then
        local label = opened.label
        subtitle = string.format("Changes your %s dice: every %s you play rolls them.", label, label)
    end
    HeroSheetWindow.ShowDialog{
        title = "Dice",
        subtitle = subtitle,
        width = DICE_WINDOW_W,
        bodyHeight = DICE_WINDOW_H,
        body = holder,
        onDone = function() end,
    }
    --built without scrolling, then scrolling turned on once laid out:
    --building under a scroll view costs more per panel.
    HeroSheetWindow.AfterLayout(function()
        if not scroller.valid then
            return
        end
        scroller.vscroll = grid.renderedHeight > scroller.renderedHeight + 0.5
    end)
    --each set's showcase dice are built a few frames apart after opening:
    --building one on its first hover stalls that frame.
    for i, set in ipairs(sets) do
        local id = set.id
        dmhub.Schedule(0.05 + 0.03 * i, function()
            if mod.unloaded or not showcase.valid then
                return
            end
            showcaseApi.preload(id)
        end)
    end
end

--- @param bus HeroAppearanceBus
--- @param Row fun(left: Panel, leftPlate: Panel, right: Panel, rightPlate: Panel, matched: nil|boolean): Panel
--- @param Half fun(inner: Panel): Panel
--- @return Panel
local function BuildEffects(bus, Row, Half)
    local preview = MapPreview()
    local nightLabel
    local lightPills, paintLight
    local footHint, footPills, paintFoot
    local bloodHint, bloodNote, bloodPills, paintBlood
    local teleportRow, teleportHint, teleportPills, paintTeleport
    local diceHint

    local function RefreshSheet()
        local token = Token()
        if token ~= nil then
            HeroSheetRefresh.Changed()
        end
    end

    lightPills, paintLight = PillRow(function(id)
        local token = Token()
        if token == nil then
            return
        end
        HeroSheetWrite.Save{
            description = "Change light",
            execute = function(props)
                local gear = props:Equipment()
                gear.mainhand1 = cond(id == "none", nil, id)
                --from now on the light in hand is the one picked, not the default.
                local fields = props --[[@as table]]
                fields.initLight = true
            end,
        }
        --the map token's light follows at once.
        game.Refresh{tokens = {token.charid}}
        RefreshSheet()
    end)
    footPills, paintFoot = TileRow(function(id)
        local token = Token()
        if token == nil then
            return
        end
        --the ancestry's own stores nothing, so it keeps following the ancestry.
        --- @type nil|string
        local chosen = id
        if chosen == AncestryTrait(token.properties, "footprintStyle", FootprintStyle.defaultId) then
            chosen = nil
        end
        HeroSheetWrite.Save{
            description = "Change footprints",
            execute = function(props)
                local fields = props --[[@as table]]
                fields.footprintStyle = chosen
            end,
        }
        RefreshSheet()
    end, FootprintPicture)
    bloodPills, paintBlood = TileRow(function(id)
        local token = Token()
        if token == nil then
            return
        end
        --- @type nil|string
        local chosen = id
        if chosen == AncestryTrait(token.properties, "bloodColor", BloodSpatter.defaultColor) then
            chosen = nil
        end
        HeroSheetWrite.Save{
            description = "Change blood",
            execute = function(props)
                local fields = props --[[@as table]]
                fields.bloodColor = chosen
            end,
        }
        RefreshSheet()
    end, BloodPicture)
    teleportPills, paintTeleport = PillRow(function(id)
        if not HeroSheetWrite.CanWrite() then
            return
        end
        HeroSheetWrite.SaveAppearance(function(live)
            live.teleportAnimation = id
        end)
        RefreshSheet()
    end)

    nightLabel = Text{
        classes = {"heroSheetCardSub"},
        text = "",
        fontSize = 12,
        width = 150,
        height = 16,
        halign = "right",
        valign = "center",
        textAlignment = "right",
        textWrap = false,
    }
    local lightBlock = Block("Light", "", gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        lightPills,
        gui.Panel{
            --the Encounter of the Week town has no battle map to preview on.
            classes = {cond(dmhub.isLobbyGame, "collapsed", nil)},
            width = "100%",
            height = "auto",
            tmargin = 4,
            preview.panel,
        },
        Text{
            classes = {"heroSheetCardSub"},
            text = "Lights from items and effects you have also appear here.",
            fontSize = 12,
            width = "100%",
            height = 16,
            tmargin = 8,
            textWrap = false,
            textOverflow = "ellipsis",
        },
    }, {panel = nightLabel, width = 150})

    local footBlock
    footBlock, footHint = Block("Footprints", "", footPills)

    bloodNote = Text{
        classes = {"heroSheetCardSub"},
        text = "Show Blood is off in this game",
        fontSize = 12,
        width = 190,
        height = 16,
        halign = "right",
        valign = "center",
        textAlignment = "right",
        textWrap = false,
    }
    local bloodBlock
    bloodBlock, bloodHint = Block("Blood", "", bloodPills, {panel = bloodNote, width = 190})

    --the Hero's dice as the Dice panel shows them: a preview only; Change
    --dice opens the window where they are picked.
    local diceLayout, diceApi = DiceLayout{scale = 1, seq = "herosheettab"}
    local changeDice = SmallButton{
        text = "Change dice",
        click = function()
            DiceWindow()
        end,
    }
    changeDice.selfStyle.halign = "right"
    --the sets' names under the dice, centred on the button's row; the button
    --is about 100 wide, so the name keeps clear of it on both sides.
    local diceName = Text{
        classes = {"heroSheetCardText"},
        text = "",
        fontSize = 14,
        width = "100%-240",
        height = "auto",
        floating = true,
        halign = "center",
        valign = "center",
        textAlignment = "center",
        textWrap = false,
        textOverflow = "ellipsis",
    }
    local diceBlock
    diceBlock, diceHint = Block("Dice", "", gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        diceLayout,
        gui.Panel{
            width = "100%",
            height = "auto",
            tmargin = 10,
            diceName,
            changeDice,
        },
    })

    --- @param token CharacterToken
    local function PaintDice(token)
        local sets = DiceSets(HeroSheetAppearance.DiceSource(token).loadout)
        diceApi.paint(sets)
        --each set once, in the order the dice show them.
        local names = {}
        local seen = {}
        for _, id in ipairs({"p1", "p2", "d6"}) do
            if sets[id] ~= nil and not seen[sets[id]] then
                seen[sets[id]] = true
                names[#names+1] = DiceName(sets[id])
            end
        end
        diceName.text = table.concat(names, ", ")
    end

    local teleportBlock
    teleportBlock, teleportHint = Block("Teleport", "", teleportPills, {
        panel = Text{
            classes = {"heroSheetCardSub"},
            text = "Developer setting",
            fontSize = 12,
            width = 130,
            height = 16,
            halign = "right",
            valign = "center",
            textAlignment = "right",
            textWrap = false,
        },
        width = 130,
    })

    --- @param token CharacterToken
    local function Paint(token)
        local props = token.properties
        local writable = HeroSheetWrite.CanWrite()
        local name = token.name or "this Hero"
        preview.paint(token, true)
        nightLabel.text = NightLabel(token)
        paintLight(LightOptions(token), TokenLight(token) or "none", writable)

        footHint.text = string.format("The tracks %s leaves in snow.", name)
        local footAncestry = AncestryTrait(props, "footprintStyle", FootprintStyle.defaultId)
        local foot = nil
        pcall(function()
            local style = FootprintStyle.GetNaturalForCreature(props)
            foot = style ~= nil and style.id or FootprintStyle.noneId
        end)
        paintFoot(MarkAncestry(FootprintStyle.GetOptions(), footAncestry), foot or footAncestry, writable)

        bloodHint.text = string.format("The blood %s spatters when hurt.", name)
        --inform, don't hide: the pick waits until the Director turns Show Blood on.
        bloodNote:SetClass("collapsed", BloodSpatter.GameEnabled())
        local bloodAncestry = AncestryTrait(props, "bloodColor", BloodSpatter.defaultColor)
        paintBlood(MarkAncestry(BloodSpatter.GetColorOptions(), bloodAncestry), BloodSpatter.GetNaturalColorId(props), writable)

        local diceSource = HeroSheetAppearance.DiceSource(token)
        if diceSource.writable and diceSource.label ~= nil then
            local label = diceSource.label
            diceHint.text = string.format("Your %s dice: every %s you play rolls them.", label, label)
        else
            diceHint.text = string.format("The dice you roll for %s.", name)
        end
        --a Director on a player's Hero, or a Hero with no class: the dice are a
        --class slot of the player who plays it, so the button says why it is off.
        changeDice:SetClass("heroSheetOff", diceSource.reason ~= nil)
        if diceSource.reason == "player" then
            changeDice.data.tip = string.format("Only %s's player can change their dice.", name)
        elseif diceSource.reason == "class" then
            changeDice.data.tip = "Choose a class first: Hero dice are set for each class."
        else
            changeDice.data.tip = nil
        end
        PaintDice(token)

        local developer = dmhub.GetSettingValue("dev:customizeteleport") == true
        teleportRow:SetClass("collapsed", not developer)
        if developer then
            teleportHint.text = string.format("How %s vanishes and appears when teleported.", name)
            local options = {}
            local registry = dmhub.tokenAnimations and dmhub.tokenAnimations.teleportAnimations
            if registry ~= nil then
                for id, entry in pairs(registry) do
                    --hidden styles belong to something else (a teleporter's stairwell).
                    if not entry.hidden then
                        options[#options+1] = {id = id, text = entry.name or id}
                    end
                end
            end
            table.sort(options, function(left, right) return left.text < right.text end)
            local current = token.teleportAnimation or ""
            if current == "" then
                current = "default"
            end
            paintTeleport(options, current, writable)
        end
    end

    bus.EffectsShown = function(shown)
        preview.setShown(shown)
        --a hidden tab gets no dehover: stop any spinning die by hand.
        if not shown then
            diceApi.stop()
        end
        local token = Token()
        if shown and token ~= nil then
            Paint(token)
        end
    end

    teleportRow = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "horizontal",
        Half(FitParts.Hold(teleportBlock)),
    }

    return HeroSheetRefresh.Block({
        width = "100%",
        height = "auto",
        flow = "vertical",
        heroSheetHero = function(element)
            preview.heroChanged()
        end,
        --the Director's Show Blood, the developers' Teleport and the player's
        --dice (equipped and class slots) are settings, not the Hero: a change to
        --any of them repaints at once.
        multimonitor = {"blood:show", "dev:customizeteleport", "diceslotsequipped", "diceslotextras", "diceequipped", "diceequipped2", "diceequippedd6"},
        monitor = function(element)
            local token = Token()
            if token ~= nil then
                Paint(token)
            end
        end,
        Row(FitParts.Hold(lightBlock), lightBlock, FitParts.Hold(footBlock), footBlock, true),
        Row(FitParts.Hold(bloodBlock), bloodBlock, FitParts.Hold(diceBlock), diceBlock, true),
        teleportRow,
    }, {
        name = "appearance effects",
        signature = function(token)
            local props = token.properties
            local parts = {
                tostring(TokenLight(token)), tostring(props:try_get("footprintStyle")), tostring(props:try_get("bloodColor")),
                json(HeroSheetAppearance.DiceSource(token)), json(props:GetDiceLoadout()), tostring(token.teleportAnimation), tostring(dmhub.GetSettingValue("dev:customizeteleport")),
                tostring(BloodSpatter.GameEnabled()), tostring(token.name), tostring(HeroSheetWrite.CanWrite()),
                tostring(dmhub.GetSettingValue("diceequipped")), tostring(dmhub.GetSettingValue("diceequipped2")), tostring(dmhub.GetSettingValue("diceequippedd6")),
                tostring(token.portrait), tostring(token.portraitFrame),
                tostring(token.creatureSize), tostring(props:try_get("raceid")),
            }
            return table.concat(parts, "|")
        end,
        refresh = function(panel, token)
            Paint(token)
        end,
    })
end

----------------------------------------------------------------------
--The Summons tab: the Hero's summons in a list and the picked one's look
--beside it (its art and token, Ring tint, Size), its Frame, and On the map.
--The list is the old sheet's (summoned before, a saved look, on this map)
--plus what the Hero's summon abilities can call, found by a search of the
--bestiary spread over frames.

--Sizes and limits, in one table: this file is near Lua's cap on locals.
local SUMMON = {
    --the list's rows, two across.
    ROW_H = 58,
    --Suggested shows at most this many recent pictures, and
    --only as many as fit its row, so the row never grows.
    RECENT_MAX = 5,
    ROW_TOKEN = 40,
    --an ability matching more creatures than this offers a menu of
    --creatures, not this Hero's own summons, so the search leaves it out.
    SEARCH_CAP = 12,
    --the search's share of a frame, in milliseconds.
    SEARCH_SLICE = 4,
    --Call Forth asks for essence the Hero has now (none out of combat):
    --lifted for the search, so every creature it can call shows before play.
    ESSENCE_LIFT = 1000,
}

--- @class HeroSummonEntry
--- @field key string the look key: its monster type
--- @field monster any its bestiary entry
--- @field name string

--- @class HeroSummonSources
--- @field filters string[] the summon abilities' bestiary searches, each once
--- @field keys table<string, any> creatures named outright, by look key

--- @class HeroSummonCache
--- @field sources table<string, HeroSummonSources|false> what each Hero's summon abilities call, by Summons.Key: false while being worked out
--- @field finds table<string, {done: boolean, keys: table<string, any>}> the search's finds, by Summons.Key: look key -> bestiary entry
--- @field entries {charid: nil|string, frame: number, list: HeroSummonEntry[]} the list, read once a frame

--- @type HeroSummonCache
local g_summonCache = {sources = {}, finds = {}, entries = {charid = nil, frame = -1, list = {}}}

--The tab's reading of the Hero's summons, in one table (the locals cap).
local Summons = {}

--- A Hero's abilities change with their Level, so what they summon does too.
--- @param token CharacterToken
--- @return string
function Summons.Key(token)
    local level = 0
    pcall(function() level = token.properties:CharacterLevel() end)
    return string.format("%s|%s", token.charid, tostring(level))
end

--- The Hero's summon abilities' searches and named creatures, worked out a
--- moment later: summons nest deep (in modes, chained abilities and
--- triggers), so the walk is slow. Nil until then; the sheet repaints once
--- they are known.
--- @param token CharacterToken
--- @return nil|HeroSummonSources
function Summons.Sources(token)
    local cacheKey = Summons.Key(token)
    local known = g_summonCache.sources[cacheKey]
    if known ~= nil then
        return known or nil
    end
    g_summonCache.sources[cacheKey] = false
    local charid = token.charid
    dmhub.Schedule(0.05, function()
        if mod.unloaded then
            return
        end
        --- @type HeroSummonSources
        local sources = {filters = {}, keys = {}}
        local live = dmhub.GetCharacterById(charid)
        if live ~= nil and live.properties ~= nil then
            local seen = {}
            local seenFilter = {}
            --- @param obj any
            --- @param depth integer
            local function Walk(obj, depth)
                if depth > 16 or type(obj) ~= "table" or seen[obj] then
                    return
                end
                seen[obj] = true
                local ok, typeName = pcall(function() return obj.typeName end)
                if ok and typeName == "ActivatedAbilitySummonBehavior" then
                    local behavior = obj --[[@as ActivatedAbilitySummonBehavior]]
                    --a duplicate copies a token on the map: no creature to style.
                    if not behavior:try_get("duplicateMode", false) then
                        if behavior.monsterType ~= "custom" then
                            local monster = assets.monsters[behavior.monsterType]
                            if monster ~= nil then
                                sources.keys[ActivatedAbilitySummonBehavior.SummonLookKey(monster, behavior.monsterType)] = monster
                            end
                        else
                            local filter = trim(behavior.bestiaryFilter or "")
                            if filter ~= "" and not seenFilter[filter] then
                                seenFilter[filter] = true
                                sources.filters[#sources.filters+1] = filter
                            end
                        end
                    end
                end
                pcall(function()
                    for _, value in pairs(obj) do
                        if type(value) == "table" then
                            Walk(value, depth + 1)
                        end
                    end
                end)
            end
            local abilities = {}
            pcall(function() abilities = live.properties:GetActivatedAbilities() end)
            for _, ability in ipairs(abilities or {}) do
                Walk(ability, 0)
            end
            local triggered = {}
            pcall(function() triggered = live.properties:GetTriggeredAbilities() end)
            for _, ability in ipairs(triggered or {}) do
                Walk(ability, 0)
            end
        end
        g_summonCache.sources[cacheKey] = sources
        HeroSheetRefresh.Changed()
    end)
    return nil
end

--- Search the bestiary with each of the Hero's summon searches, a few
--- milliseconds a frame, once per Hero and Level. Searches that need a cast
--- (a target's Level) find nothing here; those creatures join the list once
--- summoned, as on the old sheet.
--- @param token CharacterToken
function Summons.StartSearch(token)
    local cacheKey = Summons.Key(token)
    if g_summonCache.finds[cacheKey] ~= nil then
        return
    end
    local sources = Summons.Sources(token)
    if sources == nil then
        --asked again on the repaint that follows.
        return
    end
    local finds = {done = false, keys = {}}
    g_summonCache.finds[cacheKey] = finds
    if #sources.filters == 0 then
        finds.done = true
        return
    end
    local charid = token.charid
    --the ids up front: the bestiary is walked across frames.
    local ids = {}
    for id, _ in pairs(assets.monsters) do
        ids[#ids+1] = id
    end
    dmhub.Coroutine(function()
        local watch = dmhub.Stopwatch()
        local live = dmhub.GetCharacterById(charid)
        for _, filter in ipairs(sources.filters) do
            --- @type table<string, any>
            local hits = {}
            local count = 0
            for _, id in ipairs(ids) do
                if watch.milliseconds > SUMMON.SEARCH_SLICE then
                    coroutine.yield(0.01)
                    watch = dmhub.Stopwatch()
                    live = dmhub.GetCharacterById(charid)
                end
                if mod.unloaded or live == nil or live.properties == nil then
                    return
                end
                local monster = assets.monsters[id]
                local node = assets:GetMonsterNode(id)
                if monster ~= nil and node ~= nil and not node.hidden and monster.properties:has_key("monster_type") then
                    local ok, result = pcall(function()
                        return ExecuteGoblinScript(filter, GenerateSymbols(live.properties, {
                            beast = GenerateSymbols(monster.properties),
                            heroicresourcesavailabletospend = SUMMON.ESSENCE_LIFT,
                        }), 0, "Hero sheet summon search")
                    end)
                    if ok and result ~= nil and result ~= 0 and result ~= false then
                        local key = ActivatedAbilitySummonBehavior.SummonLookKey(monster, id)
                        if hits[key] == nil then
                            hits[key] = monster
                            count = count + 1
                        end
                    end
                end
            end
            if count <= SUMMON.SEARCH_CAP then
                for key, monster in pairs(hits) do
                    finds.keys[key] = monster
                end
            end
        end
        finds.done = true
        HeroSheetRefresh.Changed()
    end)
end

--- A summon's name in the list: its bestiary name, else its monster type.
--- @param monster any
--- @param key string
--- @return string
function Summons.Name(monster, key)
    local name = monster.name
    if type(name) ~= "string" or name == "" then
        return key
    end
    return name
end

--- The Hero's summons, sorted by name: the old sheet's list (summoned before, a
--- saved look, live on this map), what their abilities name outright, and
--- what the search found.
--- @param token CharacterToken
--- @return HeroSummonEntry[]
function Summons.Entries(token)
    local frame = dmhub.FrameCount()
    if g_summonCache.entries.charid == token.charid and g_summonCache.entries.frame == frame then
        return g_summonCache.entries.list
    end
    --- @type table<string, any>
    local byKey = {}
    for _, entry in ipairs(ActivatedAbilitySummonBehavior.GetCustomizableSummons(token)) do
        byKey[entry.key] = entry.monster
    end
    local cacheKey = Summons.Key(token)
    local sources = g_summonCache.sources[cacheKey]
    if sources then
        for key, monster in pairs(sources.keys) do
            byKey[key] = byKey[key] or monster
        end
    end
    local finds = g_summonCache.finds[cacheKey]
    if finds ~= nil then
        for key, monster in pairs(finds.keys) do
            byKey[key] = byKey[key] or monster
        end
    end
    local list = {}
    for key, monster in pairs(byKey) do
        list[#list+1] = {key = key, monster = monster, name = Summons.Name(monster, key)}
    end
    table.sort(list, function(left, right) return left.name < right.name end)
    g_summonCache.entries = {charid = token.charid, frame = frame, list = list}
    return list
end

--- Whether the Summons tab shows: the Hero has summons, or
--- summon abilities whose search is still running.
--- @param token CharacterToken
--- @return boolean
function Summons.Available(token)
    if #Summons.Entries(token) > 0 then
        return true
    end
    local sources = Summons.Sources(token)
    if sources == nil or #sources.filters == 0 then
        return false
    end
    local finds = g_summonCache.finds[Summons.Key(token)]
    return finds == nil or not finds.done
end

--- The crop the engine cuts from a picture (must match the engine's own):
--- a square of its short side times zoom, centred on offset.
--- @param id nil|string
--- @param zoom number
--- @param offset Vector2
--- @return {x1: number, y1: number, x2: number, y2: number}
function Summons.CropRect(id, zoom, offset)
    local asset = id ~= nil and assets.imagesTable[id] or nil
    local imageWidth = asset ~= nil and tonumber(asset.width) or nil
    local imageHeight = asset ~= nil and tonumber(asset.height) or nil
    if imageWidth == nil or imageHeight == nil or imageWidth <= 0 or imageHeight <= 0 then
        return {x1 = 0, y1 = 0, x2 = 1, y2 = 1}
    end
    local side = zoom * math.min(imageWidth, imageHeight)
    local rw = side / imageWidth
    local rh = side / imageHeight
    local centreX = offset.x + 0.5
    local centreY = offset.y + 0.5
    return {x1 = centreX - rw / 2, y1 = centreY - rh / 2, x2 = centreX + rw / 2, y2 = centreY + rh / 2}
end

--- The summon as the map draws it for this Hero: its bestiary look, the
--- Hero's saved look over it (the same code a summon spawns with), then a
--- drag in progress. A plain table shaped like a token, for TokenPreview and
--- the map preview.
--- @param token CharacterToken
--- @param entry HeroSummonEntry
--- @param withPending boolean
--- @return table
function Summons.View(token, entry, withPending)
    local info = entry.monster.info
    local view = {properties = entry.monster.properties}
    for _, field in ipairs(MAP_TOKEN_FIELDS) do
        pcall(function() view[field] = info[field] end)
    end
    pcall(function() view.creatureSize = info.creatureSize end)
    --summons are the Hero's to control, as on the map.
    view.ownerId = token.ownerId
    ActivatedAbilitySummonBehavior.ResetToBestiaryLook(view, entry.monster)
    ActivatedAbilitySummonBehavior.ApplySummonLook(token, view, entry.key)
    if withPending and entry.key == g_summon.key then
        for field, value in pairs(g_summon.pending) do
            view[field] = value
        end
    end
    local offset = view.portraitOffset
    view.portraitOffset = core.Vector2(offset ~= nil and offset.x or 0, offset ~= nil and offset.y or 0)
    view.portraitRect = Summons.CropRect(view.portrait, view.portraitZoom or 1, view.portraitOffset)
    --popoutMode: 1 always pops out, 2 never does, 0 follows the picture's
    --library (must match the engine).
    local mode = view.popoutMode or 0
    if mode == 1 then
        view.popoutPortrait = true
    elseif mode == 2 then
        view.popoutPortrait = false
    else
        local asset = view.portrait ~= nil and assets.imagesTable[view.portrait] or nil
        view.popoutPortrait = asset ~= nil and asset.imageType == "AvatarPopout"
    end
    return view
end

--- @param bus HeroAppearanceBus
--- @param Row fun(left: Panel, leftPlate: Panel, right: Panel, rightPlate: Panel, matched: nil|boolean): Panel the tab's matched rows (BuildBody)
--- @return Panel
local function BuildSummons(bus, Row)
    --- @type HeroSummonEntry[]
    local entries = {}
    --- @type nil|HeroSummonEntry
    local selected = nil
    --- @type nil|table the summon as last painted
    local view = nil
    --- @type nil|{anchor: Vector2, offset: Vector2, w: number, h: number}
    local drag = nil
    local wheelSerial = 0
    --- @type Panel[]
    local listRows = {}
    --- @type fun(index: integer): Panel
    local MakeRow
    local listHolder, countPill
    local revertButton, chooseHint
    local picks = {}
    local picksFit = SUGGEST_MAX
    local paintToken, dragTag, zoomRow, zoomSlider, circleRow, circleSlider
    local popoutRow, popoutMark, popoutHint
    local frameLine, frameParts
    local backgroundLine, backgroundParts
    local sizeValue
    local scaleRow, scaleSlider
    local resetButton
    local preview = MapPreview(function() return view end)

    --- The edited summon's look as saved on the Hero, or nil.
    --- @return nil|table
    local function SavedLook()
        local token = Token()
        if token == nil or g_summon.key == nil then
            return nil
        end
        return token.properties:GetSummonAppearance(g_summon.key)
    end

    --- The edited summon now, with any drag in progress.
    --- @return nil|table
    local function ViewNow()
        local token = Token()
        if token == nil or selected == nil then
            return nil
        end
        return Summons.View(token, selected, true)
    end

    SummonArtNow = function()
        local now = ViewNow()
        return now ~= nil and now.portrait or nil
    end

    --- A drag or slider shows on the token at once; it saves on release. The
    --- map preview's floor is slow to redraw, so it follows only Art scale
    --- (shown nowhere else), a few times a second; a crop drag reaches it on
    --- release, since redrawing it made the drag lag.
    local mapDue = false
    --- @param onMap nil|boolean
    local function PreviewPending(onMap)
        local now = ViewNow()
        if now == nil then
            return
        end
        view = now
        paintToken(now)
        if not onMap or mapDue then
            return
        end
        mapDue = true
        dmhub.Schedule(0.12, function()
            mapDue = false
            if mod.unloaded then
                return
            end
            local latest = ViewNow()
            if latest ~= nil then
                view = latest
                preview.paint(latest, false)
            end
        end)
    end

    local function CommitPending()
        drag = nil
        local pending = g_summon.pending
        g_summon.pending = {}
        if next(pending) == nil then
            return
        end
        SaveSummonLook(function(look)
            for field, value in pairs(pending) do
                if field == "portraitOffset" then
                    look[field] = {x = value.x, y = value.y}
                else
                    look[field] = value
                end
            end
        end)
    end

    --- Revert to default: the whole saved look goes; the summon stays listed.
    local function Revert()
        local key = g_summon.key
        if key == nil or SavedLook() == nil then
            return
        end
        g_summon.pending = {}
        local saved = HeroSheetWrite.Save{
            description = "Change summon appearance",
            execute = function(props)
                local all = props:try_get("summonAppearances")
                if all ~= nil then
                    all[key] = nil
                end
            end,
        }
        local token = Token()
        if saved and token ~= nil then
            ActivatedAbilitySummonBehavior.RestyleLiveSummons(token, key)
        end
        HeroSheetRefresh.Changed()
    end

    --- @param token CharacterToken
    local function Paint(token)
        entries = Summons.Entries(token)
        local writable = HeroSheetWrite.CanWrite()
        --the pick stays, across a Hero switch too, while the list has it.
        local entry = nil
        for _, candidate in ipairs(entries) do
            if candidate.key == g_summon.key then
                entry = candidate
            end
        end
        if entry == nil then
            entry = entries[1]
            g_summon.key = entry ~= nil and entry.key or nil
            g_summon.pending = {}
            preview.heroChanged()
        end
        selected = entry
        g_summon.name = entry ~= nil and entry.name or ""
        countPill.text = tostring(#entries)

        local saved = token.properties:try_get("summonAppearances") or {}
        for i = #listRows + 1, #entries do
            listRows[i] = MakeRow(i)
            listHolder:AddChild(listRows[i])
        end
        for i, row in ipairs(listRows) do
            local rowEntry = entries[i]
            row:SetClass("collapsed", rowEntry == nil)
            if rowEntry ~= nil then
                row.data.paint(rowEntry, Summons.View(token, rowEntry, false), saved[rowEntry.key] ~= nil, rowEntry == entry, writable)
            end
        end

        if entry == nil then
            view = nil
            return
        end
        view = Summons.View(token, entry, true)
        local now = view
        local custom = saved[entry.key] ~= nil
        chooseHint.text = string.format("The picture for %s's token.", entry.name)
        --Suggested: its stat block's picture, then recent ones.
        local shown = {}
        local seen = {}
        local own = entry.monster.info.portrait
        if own ~= nil and own ~= "" then
            shown[#shown+1] = {id = own, caption = "Stat block"}
            seen[own] = true
        end
        local recent = 0
        for _, id in ipairs(ArtList(g_recentArt)) do
            if not seen[id] and recent < SUMMON.RECENT_MAX then
                shown[#shown+1] = {id = id, caption = "Recent"}
                seen[id] = true
                recent = recent + 1
            end
        end
        for i, pick in ipairs(picks) do
            local shownPick = shown[i]
            pick:SetClass("collapsed", shownPick == nil or i > picksFit)
            if shownPick ~= nil then
                pick.data.id = shownPick.id
                pick.data.image.bgimage = shownPick.id
                pick.data.image.selfStyle.imageRect = CoverRect(shownPick.id, 1)
                pick.data.image:SetClass("selected", shownPick.id == now.portrait)
                pick.data.caption.text = shownPick.caption
                pick:SetClass("heroSheetOff", not writable)
            end
        end
        revertButton:SetClass("heroSheetOff", not (writable and custom))
        revertButton.data.tip = cond(custom, nil, "This summon still has its stat block's look.")

        --the token: as Fit it's, Zoom and the drag gone on a popout.
        paintToken(now)
        local popout = now.popoutPortrait == true
        local hasMode = now.popoutMode ~= nil
        dragTag:SetClass("collapsed", popout or not writable)
        zoomRow:SetClass("collapsed", popout)
        if drag == nil then
            zoomSlider.value = now.portraitZoom or 1
            circleSlider.value = now.popoutScale or 1
            scaleSlider.value = now.tokenScale or 1
        end
        popoutRow:SetClass("collapsed", not hasMode)
        popoutRow:SetClass("heroSheetOff", not writable)
        popoutMark:SetClass("collapsed", not popout)
        local asset = now.portrait ~= nil and assets.imagesTable[now.portrait] or nil
        popoutHint:SetClass("collapsed", not (hasMode and not popout and asset ~= nil and asset.imageType == "AvatarPopout"))
        circleRow:SetClass("collapsed", not popout)

        local frame = now.portraitFrame
        local framed = frame ~= nil and frame ~= ""
        local look = saved[entry.key]

        backgroundLine:SetClass("collapsed", not popout)
        local back = now.portraitBackground
        local hasBack = back ~= nil and back ~= ""
        backgroundParts.thumb:SetClass("collapsed", not hasBack)
        if hasBack then
            backgroundParts.thumb.bgimage = back
        end
        local backName = ImageName(back)
        backgroundParts.value.text = cond(hasBack, backName or "", "None")
        backgroundParts.value:SetClass("collapsed", hasBack and backName == nil)
        backgroundParts.note.text = "Behind the art, inside the frame"
        backgroundParts.button:SetClass("heroSheetOff", not writable)

        sizeValue.text = tostring(now.creatureSize or "")

        --Frame: the frame, its tint, and where it comes from.
        frameParts.thumb:SetClass("collapsed", not framed)
        if framed then
            frameParts.thumb.bgimage = frame
            TintFrame(frameParts.thumb, now)
        end
        local frameName = ImageName(frame)
        local source
        if look ~= nil and look.portraitFrame ~= nil then
            frameParts.value.text = cond(framed, frameName or "", "No frame")
            source = "Picked for this summon"
        --a summon takes the Hero's frame only when both have a frame or
        --neither does, as summoning does: a frame never goes on unframed art.
        elseif ActivatedAbilitySummonBehavior.FollowsCasterFrame(token, entry.key)
            and ((token.portraitFrame ~= nil and token.portraitFrame ~= "") == (entry.monster.info.portraitFrame ~= nil and entry.monster.info.portraitFrame ~= "")) then
            frameParts.value.text = string.format("Same as %s", token.name or "")
            source = "Summons use your frame unless you pick their own."
        else
            frameParts.value.text = cond(framed, frameName or "", "No frame")
            source = "From its stat block"
        end
        frameParts.value:SetClass("collapsed", frameParts.value.text == "")
        frameParts.note.text = cond(framed, cond(Tinted(now), "tinted", "no tint"), "")
        frameParts.extra.text = source
        frameParts.extra:SetClass("collapsed", false)
        frameParts.button:SetClass("heroSheetOff", not writable)

        preview.paint(now, false)
        scaleRow:SetClass("heroSheetOff", not writable)
        resetButton:SetClass("heroSheetOff", not writable)
    end

    --- Show another summon.
    --- @param key string
    local function Select(key)
        if key == g_summon.key then
            return
        end
        CommitPending()
        g_summon.key = key
        g_summon.pending = {}
        preview.heroChanged()
        local token = Token()
        if token ~= nil then
            Paint(token)
        end
    end

    ----------------------------------------------------------------
    --Windows: Token frame (with the tint), Background.

    --- Token frame for a summon: Same as <Hero> first,
    --- then No frame, the frames and an upload; beside them its token with
    --- the tint. A tint drag previews in the window and saves on release.
    local function SummonFrameWindow()
        local token = Token()
        if token == nil or selected == nil then
            return
        end
        local paintGrid
        local tokenPanel, paintWindowToken = TokenPreview(150)
        local sliders = {}
        local function Repaint()
            local now = ViewNow()
            if now == nil then
                return
            end
            paintWindowToken(now)
            for field, slider in pairs(sliders) do
                slider.value = now[field] or cond(field == "portraitFrameHueShift", 0, 1)
            end
        end
        --- @param id string "#follow" for Same as <Hero>
        local function Pick(id)
            SaveSummonLook(function(look)
                if id == "#follow" then
                    look.portraitFrame = nil
                else
                    look.portraitFrame = id
                end
            end)
            paintGrid()
            Repaint()
        end
        --- @param field string
        --- @param value number
        local function PreviewTint(field, value)
            local now = ViewNow()
            if now == nil or not HeroSheetWrite.CanWrite() then
                return
            end
            --a tint is its three values together.
            for _, name in ipairs({"portraitFrameHueShift", "portraitFrameSaturation", "portraitFrameBrightness"}) do
                if g_summon.pending[name] == nil then
                    g_summon.pending[name] = now[name] or cond(name == "portraitFrameHueShift", 0, 1)
                end
            end
            g_summon.pending[field] = value
            local shown = ViewNow()
            if shown ~= nil then
                paintWindowToken(shown)
            end
            PreviewPending()
        end
        local grid
        grid, paintGrid = ImageGrid{
            library = "AvatarFrame",
            height = 440,
            none = "No frame",
            follow = string.format("Same as %s", token.name or ""),
            upload = {title = "Upload a frame", sub = "png with a clear middle"},
            current = function()
                local look = SavedLook()
                if look == nil or look.portraitFrame == nil then
                    return "#follow"
                end
                return look.portraitFrame
            end,
            pick = Pick,
            uploadClick = function()
                UploadFrame(Pick)
            end,
        }
        local hueRow, saturationRow, brightnessRow
        hueRow, sliders.portraitFrameHueShift = TintSlider("Hue", "portraitFrameHueShift", PreviewTint, CommitPending)
        saturationRow, sliders.portraitFrameSaturation = TintSlider("Saturation", "portraitFrameSaturation", PreviewTint, CommitPending)
        brightnessRow, sliders.portraitFrameBrightness = TintSlider("Brightness", "portraitFrameBrightness", PreviewTint, CommitPending)
        local resetLink = Text{
            classes = {"heroSheetFeatLink", "hoverable"},
            text = "Reset",
            fontSize = 13,
            halign = "right",
            valign = "center",
            textWrap = false,
            click = function(element)
                g_summon.pending = {}
                --no tint of its own: back to the Hero's (or its stat block's).
                SaveSummonLook(function(look)
                    look.portraitFrameHueShift = nil
                    look.portraitFrameSaturation = nil
                    look.portraitFrameBrightness = nil
                end)
                Repaint()
            end,
        }
        local side = gui.Panel{
            width = 220,
            height = "auto",
            flow = "vertical",
            halign = "right",
            valign = "top",
            FieldName("On its token"),
            gui.Panel{
                width = "100%",
                height = 160,
                flow = "none",
                tokenPanel,
            },
            gui.Panel{
                width = "100%",
                height = 18,
                tmargin = 12,
                flow = "horizontal",
                Text{
                    classes = {"heroSheetFieldLabel"},
                    text = "TINT",
                    fontSize = 11.5,
                    bold = true,
                    halign = "left",
                    valign = "center",
                    textWrap = false,
                },
                resetLink,
            },
            hueRow,
            saturationRow,
            brightnessRow,
            Text{
                classes = {"heroSheetCardSub"},
                text = "The tint is previewed here. Your summons on the map are updated when you let go.",
                fontSize = 12,
                width = "100%",
                height = 48,
                tmargin = 6,
                textWrap = true,
            },
        }
        local body = gui.Panel{
            width = "100%",
            height = 440,
            flow = "horizontal",
            gui.Panel{
                width = PICK_COLUMNS * (PICK_TILE + PICK_GAP) + 10,
                height = "100%",
                flow = "vertical",
                halign = "left",
                valign = "top",
                grid,
            },
            side,
        }
        paintGrid()
        Repaint()
        HeroSheetWindow.ShowDialog{
            title = "Token frame",
            subtitle = g_summon.name,
            width = PICK_COLUMNS * (PICK_TILE + PICK_GAP) + 10 + 220 + 40,
            bodyHeight = 440,
            body = body,
            onDone = function()
                CommitPending()
            end,
        }
    end

    ----------------------------------------------------------------
    --The list.

    listHolder = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
    }
    --- One row of the list, built when the list first needs it and repainted
    --- after that. Rows sit two across; the first of each pair has the gap.
    MakeRow = function(index)
        local tokenPanel, paintRowToken = TokenPreview(SUMMON.ROW_TOKEN)
        tokenPanel.selfStyle.halign = "center"
        tokenPanel.selfStyle.valign = "center"
        local ring = gui.Panel{
            classes = {"heroSummonCustom", "collapsed"},
            bgimage = "panels/square.png",
            border = 2,
            cornerRadius = (SUMMON.ROW_TOKEN + 8) / 2,
            width = SUMMON.ROW_TOKEN + 8,
            height = SUMMON.ROW_TOKEN + 8,
            halign = "center",
            valign = "center",
            floating = true,
            interactable = false,
        }
        local name = Text{
            classes = {"heroSheetCardStrong"},
            text = "",
            fontSize = 14,
            bold = true,
            width = "100%",
            height = 20,
            textWrap = false,
            textOverflow = "ellipsis",
            interactable = false,
        }
        local size = Text{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 12,
            width = "100%",
            height = 16,
            textWrap = false,
            interactable = false,
        }
        local row = gui.Panel{
            classes = {"heroLookTile", "hoverable"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = "50%-3",
            height = SUMMON.ROW_H,
            hpad = 8,
            borderBox = true,
            flow = "horizontal",
            halign = "left",
            bmargin = 6,
            rmargin = cond(index % 2 == 1, 6, 0),
            data = {},
            linger = function(element)
                if element.data.custom then
                    gui.Tooltip("Customised")(element)
                end
            end,
            click = function(element)
                if element.data.key ~= nil then
                    Select(element.data.key)
                end
            end,
            rightClick = function(element)
                local key = element.data.key
                if key == nil or not element.data.custom or not HeroSheetWrite.CanWrite() then
                    return
                end
                HeroSheetLists.ShowMenu(element, {
                    {text = "Revert", click = function()
                        Select(key)
                        Revert()
                    end},
                }, nil, {below = true})
            end,
            gui.Panel{
                width = SUMMON.ROW_TOKEN + 8,
                height = SUMMON.ROW_TOKEN + 8,
                flow = "none",
                valign = "center",
                interactable = false,
                ring,
                tokenPanel,
            },
            gui.Panel{
                width = string.format("100%%-%d", SUMMON.ROW_TOKEN + 18),
                height = "auto",
                flow = "vertical",
                lmargin = 10,
                valign = "center",
                interactable = false,
                name,
                size,
            },
        }
        --- @param entry HeroSummonEntry
        --- @param rowView table
        --- @param custom boolean
        --- @param isSelected boolean
        --- @param writable boolean
        row.data.paint = function(entry, rowView, custom, isSelected, writable)
            row.data.key = entry.key
            row.data.custom = custom
            paintRowToken(rowView)
            ring:SetClass("collapsed", not custom)
            name.text = entry.name
            size.text = tostring(rowView.creatureSize or "")
            row:SetClass("selected", isSelected)
        end
        return row
    end

    countPill = gui.Label{
        classes = {"heroSheetPill"},
        text = "0",
        bgimage = "panels/square.png",
        bgcolor = "clear",
        border = 1,
        cornerRadius = 9,
        width = "auto",
        height = 18,
        hpad = 8,
        borderBox = true,
        fontSize = 12,
        bold = true,
        textWrap = false,
        halign = "right",
        valign = "center",
    }
    local listBlock = Block("Summons", "", listHolder, {panel = countPill, width = 40})

    ----------------------------------------------------------------
    --The summon's look, in the Look tab's steps: its name
    --over 1 Choose the art, 2 Fit it and 3 On the map.

    revertButton = SmallButton{
        text = "Revert to default",
        click = function()
            Revert()
        end,
    }
    revertButton.selfStyle.rmargin = 0
    revertButton.selfStyle.halign = "right"

    local chooseButton = SmallButton{
        text = "Choose art",
        click = function()
            ArtWindow("summon")
        end,
    }
    local uploadButton = SmallButton{
        text = "Upload",
        click = function()
            ChooseUpload(false, "summon", nil)
        end,
    }

    local tokenPreview
    tokenPreview, paintToken = TokenPreview(TOKEN_BOX)
    dragTag = FitParts.DragTag()
    --the picture moves with the pointer while the button is held; the wheel
    --drives Zoom (wheel up zooms in), a spin is one save.
    local tokenBox = gui.Panel{
        --a clear image: a panel with none takes no presses.
        bgimage = "panels/square.png",
        bgcolor = "clear",
        width = TOKEN_BOX,
        height = TOKEN_BOX,
        halign = "center",
        flow = "none",
        press = function(element)
            if view == nil or view.popoutPortrait == true or not HeroSheetWrite.CanWrite() or element.mousePoint == nil then
                return
            end
            local rect = view.portraitRect
            local offset = view.portraitOffset
            drag = {
                anchor = element.mousePoint,
                offset = core.Vector2(offset.x, offset.y),
                w = rect.x2 - rect.x1,
                h = rect.y2 - rect.y1,
            }
            element.thinkTime = 0.02
        end,
        unpress = function(element)
            element.thinkTime = nil
            if drag ~= nil then
                CommitPending()
            end
        end,
        think = function(element)
            if drag == nil or element.mousePoint == nil then
                return
            end
            local dx = element.mousePoint.x - drag.anchor.x
            local dy = element.mousePoint.y - drag.anchor.y
            g_summon.pending.portraitOffset = core.Vector2(drag.offset.x - dx * drag.w, drag.offset.y - dy * drag.h)
            PreviewPending()
        end,
        wheel = function(element, delta)
            if drag ~= nil or view == nil or view.popoutPortrait == true or not HeroSheetWrite.CanWrite() then
                return true
            end
            local zoom = FitParts.WheelZoom(view.portraitZoom or 1, delta)
            g_summon.pending.portraitZoom = zoom
            zoomSlider.value = zoom
            PreviewPending()
            wheelSerial = wheelSerial + 1
            local serial = wheelSerial
            dmhub.Schedule(WHEEL_SETTLE, function()
                if not mod.unloaded and serial == wheelSerial and drag == nil then
                    CommitPending()
                end
            end)
            return true
        end,
        tokenPreview,
        dragTag,
    }

    --- A slider that previews on change and saves on release.
    --- @param field string the token field it sets
    --- @param minValue number
    --- @param maxValue number
    --- @param minSaved number the least it saves (Art scale's engine floor)
    --- @param width string
    --- @param sliderWidth number
    --- @return Panel
    local function PendingSlider(field, minValue, maxValue, minSaved, width, sliderWidth)
        return gui.Slider{
            width = width,
            height = 20,
            sliderWidth = sliderWidth,
            labelFormat = "rawpercent",
            labelWidth = 46,
            valign = "center",
            minValue = minValue,
            maxValue = maxValue,
            unclamped = true,
            value = 1,
            events = {
                change = function(element)
                    if not HeroSheetWrite.CanWrite() or selected == nil then
                        return
                    end
                    g_summon.pending[field] = math.max(minSaved, element.value)
                    PreviewPending(field == "tokenScale")
                end,
                confirm = function(element)
                    CommitPending()
                end,
            },
        }
    end

    zoomSlider = PendingSlider("portraitZoom", TOKEN_ZOOM_MIN, TOKEN_ZOOM_MAX, 0, "100%-50", 70)
    circleSlider = PendingSlider("popoutScale", TOKEN_ZOOM_MIN, TOKEN_ZOOM_MAX, 0, "100%-50", 70)
    zoomRow = FitParts.SliderRow("Zoom", zoomSlider)
    circleRow = FitParts.SliderRow("Circle", circleSlider, "Sizes the frame and background under the art.")
    circleRow:SetClass("collapsed", true)

    popoutRow, popoutMark, popoutHint = FitParts.PopoutCheck(function(element)
        if view == nil or element:HasClass("heroSheetOff") then
            return
        end
        --an explicit choice: 1 always pops out, 2 never does.
        local on = view.popoutPortrait == true
        SaveSummonLook(function(look)
            look.popoutMode = cond(on, 2, 1)
        end)
    end)

    local tokenColumn = FitParts.TokenColumn(tokenBox, zoomRow, popoutRow, popoutHint, circleRow)

    frameLine, frameParts = FitLine("Frame", "Change frame", function()
        SummonFrameWindow()
    end)

    backgroundLine, backgroundParts = FitLine("Background", "Change background", function()
        BackgroundWindow{
            subtitle = g_summon.name,
            current = function()
                local now = ViewNow()
                return now ~= nil and now.portraitBackground or nil
            end,
            frame = function()
                local now = ViewNow()
                return now ~= nil and now.portraitFrame or nil
            end,
            pick = function(id)
                --"" is None chosen: nothing behind, whatever the stat block has.
                SaveSummonLook(function(look)
                    look.portraitBackground = id
                end)
            end,
        }
    end)
    backgroundLine:SetClass("collapsed", true)
    backgroundParts.extra:SetClass("collapsed", true)

    sizeValue = Text{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 14,
        bold = true,
        rmargin = 8,
        halign = "left",
        valign = "center",
        textWrap = false,
    }
    local sizeLine = gui.Panel{
        width = "100%",
        height = 26,
        flow = "horizontal",
        Text{
            classes = {"heroSheetFieldLabel"},
            text = "SIZE",
            fontSize = 11.5,
            bold = true,
            rmargin = 8,
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        sizeValue,
        Text{
            classes = {"heroSheetCardSub"},
            text = "From its stat block",
            fontSize = 12,
            halign = "left",
            valign = "center",
            textWrap = false,
        },
    }

    resetButton = SmallButton{
        text = "Reset placement",
        click = function()
            g_summon.pending = {}
            SaveSummonLook(function(look)
                look.portraitZoom = nil
                look.portraitOffset = nil
                look.tokenScale = nil
                look.popoutScale = nil
            end)
        end,
    }
    resetButton.data.tip = "Puts back the token's framing, Circle and Art scale."

    local fitLines = gui.Panel{
        width = string.format("100%%-%d", TOKEN_COLUMN + TOKEN_GAP),
        height = "auto",
        flow = "vertical",
        halign = "right",
        valign = "top",
        tmargin = 18,
        frameLine,
        backgroundLine,
        gui.Panel{
            width = "100%",
            height = 26,
            bmargin = 14,
            flow = "horizontal",
            resetButton,
        },
    }

    ----------------------------------------------------------------
    --On the map: the summon alone, by day (it carries no light), and Art scale.

    scaleSlider = PendingSlider("tokenScale", ART_SCALE_MIN, ART_SCALE_MAX, ART_SCALE_MIN, "100%-70", 120)
    scaleRow = gui.Panel{
        width = "100%",
        height = 26,
        flow = "horizontal",
        Text{
            classes = {"heroSheetCardText"},
            text = "Art scale",
            fontSize = 13,
            width = 70,
            halign = "left",
            valign = "center",
            textWrap = false,
        },
        scaleSlider,
    }
    sizeLine.selfStyle.tmargin = 12

    --Suggested's pictures: built once, painted per summon.
    for i = 1, SUGGEST_MAX do
        local image = gui.Panel{
            classes = {"heroLookTile"},
            bgimage = "panels/square.png",
            bgcolor = "white",
            border = 1,
            cornerRadius = 8,
            width = SUGGEST_W,
            height = SUGGEST_W,
            halign = "center",
            interactable = false,
        }
        local caption = Text{
            classes = {"heroSheetCardSub"},
            text = "",
            fontSize = 11.5,
            width = SUGGEST_W + SUGGEST_GAP - 2,
            height = 16,
            tmargin = 3,
            halign = "center",
            textAlignment = "center",
            textWrap = false,
            textOverflow = "ellipsis",
            interactable = false,
        }
        local pick = gui.Panel{
            classes = {"hoverable", "collapsed"},
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = SUGGEST_W + SUGGEST_GAP,
            height = SUGGEST_W + 20,
            halign = "left",
            flow = "vertical",
            data = {},
            linger = function(element)
                local name = ImageName(element.data.id)
                if name ~= nil then
                    gui.Tooltip(name)(element)
                end
            end,
            click = function(element)
                if element.data.id ~= nil and not element:HasClass("heroSheetOff") then
                    UseArt(element.data.id, "summon")
                end
            end,
            image,
            caption,
        }
        pick.data.image = image
        pick.data.caption = caption
        picks[i] = pick
    end

    local chooseStep
    --the hint names the summon, so it is painted.
    chooseStep, chooseHint = Step(1, "Choose the art", "",
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Panel{
                width = "100%",
                height = 26,
                flow = "horizontal",
                chooseButton,
                uploadButton,
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                tmargin = 12,
                flow = "vertical",
                FieldName("Suggested"),
                gui.Panel{
                    width = "100%",
                    height = SUGGEST_W + 20,
                    tmargin = 4,
                    flow = "horizontal",
                    data = {width = -1},
                    --as many as fit, checked when the row's width changes.
                    thinkTime = 0.25,
                    think = function(element)
                        local renderedWidth = element.renderedWidth
                        if renderedWidth == element.data.width or renderedWidth <= 0 then
                            return
                        end
                        element.data.width = renderedWidth
                        local units = renderedWidth / math.max(0.01, HeroSheetWindow.Zoom())
                        local count = math.clamp(math.floor(units / (SUGGEST_W + SUGGEST_GAP)), 1, SUGGEST_MAX)
                        local token = Token()
                        if count ~= picksFit and token ~= nil and drag == nil and next(g_summon.pending) == nil then
                            picksFit = count
                            Paint(token)
                        end
                    end,
                    children = picks,
                },
            },
        }, revertButton)

    local fitStep = Step(2, "Fit it",
        "Drag the token to move the picture, and zoom to size it. Pop out of the frame suits art made to rise above it, on a transparent background.",
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            thinkTime = 0.25,
            think = FitItAdapt(tokenColumn, fitLines),
            tokenColumn,
            fitLines,
        })

    local mapStep = Step(3, "On the map", "How the token sits on the battle map.",
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            preview.panel,
            scaleRow,
            sizeLine,
        })
    scaleRow.selfStyle.tmargin = 10
    --the Encounter of the Week town has no battle map to preview on.
    mapStep:SetClass("collapsed", dmhub.isLobbyGame)

    bus.SummonsShown = function(shown)
        preview.setShown(shown)
        if not shown then
            CommitPending()
        end
        local token = Token()
        if shown and token ~= nil then
            Paint(token)
        end
    end

    --the Look tab's rows: the list beside 1 Choose the art,
    --2 Fit it beside 3 On the map, stacking below Wide as the Look tab does.
    return HeroSheetRefresh.Block({
        width = "100%",
        height = "auto",
        flow = "vertical",
        heroSheetHero = function(element)
            g_summon.pending = {}
            drag = nil
            preview.heroChanged()
        end,
        Row(FitParts.Hold(listBlock), listBlock, FitParts.Hold(chooseStep), chooseStep, true),
        Row(FitParts.Hold(fitStep), fitStep, FitParts.Hold(mapStep), mapStep, true),
    }, {
        name = "appearance summons",
        signature = function(token)
            local keys = {}
            for _, entry in ipairs(Summons.Entries(token)) do
                keys[#keys+1] = entry.key
            end
            return table.concat({
                tostring(token.charid), tostring(g_summon.key), table.concat(keys, ","),
                json(token.properties:try_get("summonAppearances") or {}),
                tostring(token.portraitFrame), string.format("%.3f|%.3f|%.3f", token.portraitFrameHueShift or 0, token.portraitFrameSaturation or 1, token.portraitFrameBrightness or 1),
                tostring(token.name), tostring(HeroSheetWrite.CanWrite()), table.concat(ArtList(g_recentArt), ","),
            }, "|")
        end,
        refresh = function(panel, token)
            --a drag in progress keeps its own values on screen.
            if drag ~= nil or next(g_summon.pending) ~= nil then
                return
            end
            Paint(token)
        end,
    })
end

----------------------------------------------------------------------
--The Description tab: optional, never counted as to-do; it
--belongs to the Hero, not a look. Typing saves after a pause.

--- @return Panel
local function BuildDescription()
    local KEY = CharacterDescription.CHARACTER_KEY
    --- @type table<string, Panel>
    local fields = {}
    local intro

    --- @param key string
    --- @param text string
    local function SaveField(key, text)
        HeroSheetWrite.SaveSoon("appearance:description:" .. key, {
            description = "Change description",
            execute = function(props)
                local description = props:try_get(KEY)
                if description == nil then
                    description = CharacterDescription.new{}
                    props[KEY] = description
                end
                description[key] = text
            end,
        })
    end

    --- @param spec {key: string, text: string}
    --- @param multiline boolean
    --- @return Panel
    local function FieldBox(spec, multiline)
        local input = Field{
            text = "",
            multiline = multiline,
            height = cond(multiline, 96, 30),
            limit = cond(multiline, 1000, 120),
            edit = function(text)
                SaveField(spec.key, text)
            end,
            defocus = function(text)
                HeroSheetWrite.Flush("appearance:description:" .. spec.key)
            end,
        }
        fields[spec.key] = input
        return gui.Panel{
            width = cond(multiline, "100%", "50%-6"),
            height = "auto",
            flow = "vertical",
            halign = "left",
            bmargin = 10,
            FieldName(spec.text),
            input,
        }
    end

    intro = Text{
        classes = {"heroSheetCardSub"},
        text = "",
        fontSize = 13,
        width = "100%",
        height = 18,
        bmargin = 12,
        textWrap = false,
        textOverflow = "ellipsis",
    }
    --the fields in two columns, a row at a time.
    local grid = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }
    for i = 1, #DESCRIPTION_FIELDS, 2 do
        local left = FieldBox(DESCRIPTION_FIELDS[i], false)
        left.selfStyle.rmargin = 12
        local row = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            left,
        }
        if DESCRIPTION_FIELDS[i + 1] ~= nil then
            row:AddChild(FieldBox(DESCRIPTION_FIELDS[i + 1], false))
        end
        grid:AddChild(row)
    end
    local features = FieldBox(DESCRIPTION_FEATURES, true)

    local plate = gui.Panel{
        classes = {"heroSheetPlate", "heroSheetBlock"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = "auto",
        flow = "vertical",
        pad = 14,
        borderBox = true,
        intro,
        grid,
        features,
    }
    return HeroSheetRefresh.Block({
        width = "100%",
        height = "auto",
        flow = "vertical",
        plate,
    }, {
        name = "appearance description",
        signature = function(token)
            local parts = {tostring(token.name), tostring(HeroSheetWrite.CanWrite())}
            local description = token.properties:try_get(KEY)
            if description ~= nil then
                for _, spec in ipairs(DESCRIPTION_FIELDS) do
                    parts[#parts+1] = tostring(description:try_get(spec.key))
                end
                parts[#parts+1] = tostring(description:try_get(DESCRIPTION_FEATURES.key))
            end
            return table.concat(parts, "|")
        end,
        --holds the keyboard while one of its fields is typed into.
        holdsKeyboard = function(panel)
            for _, input in pairs(fields) do
                if input.valid and (input --[[@as Input]]).hasInputFocus then
                    return true
                end
            end
            return false
        end,
        refresh = function(panel, token)
            intro.text = string.format("Optional. How %s looks and carries themself, for you and your table.", token.name or "this Hero")
            local description = token.properties:try_get(KEY)
            local writable = HeroSheetWrite.CanWrite()
            for key, input in pairs(fields) do
                --a field being typed in keeps what is typed.
                if not (input --[[@as Input]]).hasInputFocus then
                    input.text = description ~= nil and description:try_get(key) or ""
                end
                input.interactable = writable
            end
        end,
    })
end

----------------------------------------------------------------------
--The right side: the sub-tabs, then the open one's blocks.

--- @param state {subtab: string}
--- @param bus HeroAppearanceBus
--- @return Panel
local function BuildBody(state, bus)
    --- @type table<string, Panel>
    local panes = {}
    --- @type table<string, Panel>
    local tabs = {}
    local content
    local holder

    --- The body scrolls only once its content overflows: a panel under a
    --- scroll view costs more to build and lay out.
    local fitGen = 0
    local function FitScroll()
        fitGen = fitGen + 1
        local gen = fitGen
        HeroSheetWindow.AfterLayout(function()
            if gen ~= fitGen or not holder.valid then
                return
            end
            if holder.renderedHeight <= 0 then
                return
            end
            local over = content.renderedHeight > holder.renderedHeight + 0.5
            if (holder.vscroll == true) ~= over then
                holder.vscroll = over
            end
        end)
    end

    --whether the sheet shows this tab: the map preview's floor exists only
    --while it is on screen, and a preview stops when the tab goes.
    local sheetState = HeroSheet.State()
    local tabShown = sheetState == nil or sheetState.tab == "Appearance"
    --the window is open (not closed or minimized), and the Builder covers the sheet.
    local windowOpen = true
    local builderUp = false
    --the Builder's Appearance step hosts the surface, and shows it.
    local hosted = false
    local hostShown = false
    local function SyncShown()
        local shown = cond(hosted, hostShown, tabShown and not builderUp) and windowOpen
        if bus.MapShown ~= nil then
            bus.MapShown(shown and state.subtab == "look")
        end
        if bus.EffectsShown ~= nil then
            bus.EffectsShown(shown and state.subtab == "effects")
        end
        if bus.SummonsShown ~= nil then
            bus.SummonsShown(shown and state.subtab == "summons")
        end
        if not shown then
            StopAudition()
        end
    end

    --- @param id string
    local function Show(id)
        state.subtab = id
        for tabid, tab in pairs(tabs) do
            tab:SetClassTree("selected", tabid == id)
        end
        for paneid, pane in pairs(panes) do
            pane:SetClass("collapsed", paneid ~= id)
        end
        HeroSheetRefresh.CatchUpShown()
        FitScroll()
        SyncShown()
    end
    bus.ShowSubtab = Show

    local strip = gui.Panel{
        width = "100%",
        height = 30,
        flow = "horizontal",
        bmargin = 12,
    }
    for _, spec in ipairs(SUBTABS) do
        local id = spec.id
        local tab = gui.Panel{
            classes = {"heroSheetListTabFrame", "hoverable"},
            bgimage = "panels/square.png",
            border = {x1 = 0, y1 = 2, x2 = 0, y2 = 0},
            width = "auto",
            height = 26,
            rmargin = 18,
            halign = "left",
            valign = "bottom",
            click = function(element)
                Show(id)
            end,
            Text{
                classes = {"heroSheetListTab"},
                text = string.upper(spec.text),
                fontSize = 15,
                bold = true,
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        }
        tabs[id] = tab
        strip:AddChild(tab)
    end
    --the Summons tab shows only for a Hero with summons or summon abilities;
    --the search for what those call starts here, in the background, so the
    --tab is right before it is opened.
    strip:AddChild(HeroSheetRefresh.Block({
        width = 1,
        height = 1,
        floating = true,
        interactable = false,
    }, {
        name = "appearance summons tab",
        signature = function(token)
            --a side effect on purpose: starts the bestiary search (once per Hero and Level).
            Summons.StartSearch(token)
            return string.format("%s|%s", tostring(token.charid), tostring(Summons.Available(token)))
        end,
        refresh = function(panel, token)
            local available = Summons.Available(token)
            tabs.summons:SetClass("collapsed", not available)
            if not available and state.subtab == "summons" then
                Show("look")
            end
        end,
    }))

    --- A row's left half at Wide (the full width below it): the steps pair
    --- up across the tab.
    --- @param inner Panel
    --- @return Panel
    local function Half(inner)
        return gui.Panel{
            width = "50%-6",
            height = "auto",
            halign = "left",
            valign = "top",
            flow = "vertical",
            heroSheetTier = function(element, tier)
                element.selfStyle.width = cond(tier == "wide", "50%-6", "100%")
            end,
            inner,
        }
    end

    --- A row of two halves: side by side whenever both get their minimum width,
    --- at any tier, else stacked. A matched row's plates are one height while
    --- paired, so their edges line up: the shorter one grows to the taller,
    --- its content at the top. The engine has no row-height stretch ("100%"
    --- is the tab's).
    --- @param left Panel a refresh block holding one plate
    --- @param leftPlate Panel the plate in left
    --- @param right Panel a refresh block holding one plate
    --- @param rightPlate Panel the plate in right
    --- @param matched nil|boolean
    --- @param minHalf nil|number the least width a half needs, in units (default 434)
    --- @return Panel
    local function Row(left, leftPlate, right, rightPlate, matched, minHalf)
        minHalf = minHalf or 434
        --100 units tall: rendered sizes are screen pixels, widths here are units.
        local probe = gui.Panel{
            width = 1,
            height = 100,
            floating = true,
            interactable = false,
        }
        local leftHalf = gui.Panel{
            width = "50%-6",
            height = "auto",
            halign = "left",
            valign = "top",
            flow = "vertical",
            left,
        }
        local rightHalf = gui.Panel{
            width = "50%-6",
            height = "auto",
            halign = "right",
            valign = "top",
            flow = "vertical",
            right,
        }
        local paired = true
        --the plate that grows, and to what height (units).
        --- @type nil|Panel
        local grown = nil
        local grownTo = -1

        --- @param plate nil|Panel
        --- @param height number
        local function Grow(plate, height)
            if grown ~= nil and grown ~= plate then
                grown.selfStyle.minHeight = 0
            end
            grown = plate
            grownTo = height
            if plate ~= nil then
                --minHeight is the plate's content: its padding (12 each side) adds on.
                plate.selfStyle.minHeight = math.max(0, height - 24)
            end
        end

        --- The grown plate's height is its own only when it is taller than
        --- asked: then the other one grows instead.
        --- @param perUnit number
        local function Check(perUnit)
            if leftPlate.renderedHeight <= 0 or rightPlate.renderedHeight <= 0 then
                return
            end
            local leftHeight = math.floor(leftPlate.renderedHeight / perUnit + 0.5)
            local rightHeight = math.floor(rightPlate.renderedHeight / perUnit + 0.5)
            if grown == rightPlate then
                if rightHeight > grownTo then
                    Grow(leftPlate, rightHeight)
                elseif leftHeight ~= grownTo then
                    Grow(rightPlate, leftHeight)
                end
            elseif grown == leftPlate then
                if leftHeight > grownTo then
                    Grow(rightPlate, leftHeight)
                elseif rightHeight ~= grownTo then
                    Grow(leftPlate, rightHeight)
                end
            elseif leftHeight > rightHeight then
                Grow(rightPlate, leftHeight)
            elseif rightHeight > leftHeight then
                Grow(leftPlate, rightHeight)
            end
        end

        if matched == true then
            --a grown plate keeps its content at the top, under its header.
            for _, plate in ipairs({leftPlate, rightPlate}) do
                for _, child in ipairs(plate.children) do
                    child.selfStyle.valign = "top"
                end
            end
        end

        local row
        --- @param on boolean
        local function Pair(on)
            if on == paired then
                return
            end
            paired = on
            row.selfStyle.flow = cond(on, "horizontal", "vertical")
            leftHalf.selfStyle.width = cond(on, "50%-6", "100%")
            rightHalf.selfStyle.width = cond(on, "50%-6", "100%")
            rightHalf.selfStyle.halign = cond(on, "right", "left")
            rightHalf.selfStyle.tmargin = cond(on, 0, 12)
            if not on then
                Grow(nil, -1)
            end
        end

        row = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bmargin = 12,
            --the room and a plate's height change with a resize, Font Size or
            --content (a card row shown), so the row checks a few times a
            --second (cheap, and hidden panels do not think).
            thinkTime = 0.25,
            think = function(element)
                local perUnit = probe.renderedHeight / 100
                if perUnit <= 0 or element.renderedWidth <= 0 then
                    return
                end
                Pair(element.renderedWidth / perUnit >= 2 * minHalf + 12)
                if paired and matched == true then
                    Check(perUnit)
                end
            end,
            probe,
            leftHalf,
            rightHalf,
        }
        return row
    end

    local looks, looksPlate = BuildLooks()
    local anthem, anthemPlate = BuildAnthem()
    local chooseArt, chooseArtPlate = BuildChooseArt()
    local suggested, suggestedPlate = BuildSuggested(bus)
    local fitIt, fitItPlate = BuildFitIt()
    local onMap, onMapPlate = BuildMap(bus)
    local looksRow = Row(looks, looksPlate, anthem, anthemPlate, true, 480)
    panes.look = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        --Looks with this look's Anthem beside it; four looks and New look
        --need the wider half (480 still pairs them in the Builder).
        looksRow,
        --Choose the art beside Suggested.
        Row(chooseArt, chooseArtPlate, suggested, suggestedPlate, true),
        --2 Fit it beside 3 On the map.
        Row(fitIt, fitItPlate, onMap, onMapPlate, true),
    }
    panes.description = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        BuildDescription(),
    }
    panes.effects = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        BuildEffects(bus, Row, Half),
    }
    panes.summons = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        BuildSummons(bus, Row),
    }

    content = gui.Panel{
        width = "100%-10",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        panes.look,
        panes.description,
        panes.effects,
        panes.summons,
    }
    holder = gui.Panel{
        width = "100%",
        height = "100%-42",
        flow = "vertical",
        --content that grows in place (dice rows appearing, a card row) must
        --turn scrolling on too, or its top goes out of reach.
        data = {height = -1},
        thinkTime = 0.25,
        think = function(element)
            local renderedHeight = content.renderedHeight
            if renderedHeight ~= element.data.height then
                element.data.height = renderedHeight
                FitScroll()
            end
        end,
        content,
    }
    Show("look")

    --The Builder footer's Art link: Look, scrolled so 1 Choose the
    --art starts at the top once the tab has laid out. There is no engine
    --scroll-into-view, so the offset is the Looks row's rendered height.
    bus.RevealArt = function()
        Show("look")
        dmhub.Schedule(0.05, function()
            if mod.unloaded or not holder.valid or holder.vscroll ~= true then
                return
            end
            local range = content.renderedHeight - holder.renderedHeight
            if range > 0 then
                holder.vscrollPosition = 1 - math.min(range, looksRow.renderedHeight) / range
            end
        end)
        return chooseArtPlate
    end

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        heroSheetLayout = function(element)
            FitScroll()
        end,
        heroSheetTier = function(element)
            FitScroll()
        end,
        heroSheetHero = function(element)
            StopAudition()
            FitScroll()
        end,
        heroSheetTab = function(element, tabid)
            tabShown = tabid == "Appearance"
            SyncShown()
        end,
        --closed, minimized, or the Builder over the sheet.
        heroSheetWindowMode = function(element, data)
            if data.closed and bus.MapReset ~= nil then
                bus.MapReset()
            end
            windowOpen = not (data.closed or data.minimized)
            builderUp = data.builder == true
            SyncShown()
        end,
        --- @param host HeroAppearanceHost
        heroAppearanceHost = function(element, host)
            hosted = host.builder
            hostShown = host.shown
            SyncShown()
            FitScroll()
        end,
        strip,
        holder,
    }
end

--- Build the Appearance surface: the art column for the host's card column,
--- and the body for its right side. The sheet builds it the first time the
--- tab shows and keeps it.
--- @return HeroAppearanceView
function HeroSheetAppearance.Create()
    local state = {subtab = "look"}
    --- @type HeroAppearanceBus
    local bus = {}
    local column = BuildColumn(bus)
    local body = BuildBody(state, bus)
    return {
        column = column,
        body = body,
        state = state,
        show = function(id)
            bus.ShowSubtab(id)
        end,
        editName = function()
            bus.EditName()
        end,
        revealArt = function()
            return bus.RevealArt()
        end,
    }
end
