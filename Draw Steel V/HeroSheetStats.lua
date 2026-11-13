local mod = dmhub.GetModLoading()

--The Hero sheet's stats band: the five characteristics; Size, Speed,
--Disengage and Stability; Potency; Wealth and Renown; then the words row:
--skills by group, languages, immunities and weaknesses. Each shows a hover
--card of where its value comes from, and a characteristic's card pins on a
--click with Roll, which opens the app's roll dialog. Edit mode frames what
--can be edited and turns a pinned card into its editor; the Skills and
--Languages windows build on this. The numbers come from the shared read of
--the Hero (HeroSheetRefresh.Read, which the EotW sheet uses too).

HeroSheetStats = rawget(_G, "HeroSheetStats") or {}

--The hover cards' content width (the item cards' too).
local CARD_WIDTH = HeroSheetTheme.CARD_WIDTH

--An immunity row's value column: the number and its source ("10 (Level 9
--Immunity)") read on one line; the damage types take the rest.
local RESISTANCE_VALUE_WIDTH = 230

--The Skills card's value column: a group's skills ("Climb, Heal, Jump, Lift,
--Swim") beside the group's name.
local SKILLS_VALUE_WIDTH = 270

--Narrow's word rows: the headings' column (wide enough for Skills' Manage pill).
local NARROW_LABEL_WIDTH = 170

--Where Narrow's characteristics go: under the banner, outside the band, so
--they show on every pane. Made by HeroSheetStats.Create.
--- @type Panel
local g_tilesHolder

--A label on the band's plate.
--- @param args table gui.Label args; classes default to heroSheetCardText
--- @return Panel
local function Text(args)
    args.classes = args.classes or {"heroSheetCardText"}
    args.width = args.width or "auto"
    args.height = args.height or "auto"
    return gui.Label(args)
end

--Small capitals in the warm label colour ("MIGHT", "SPEED").
--- @param text string
--- @param args nil|table more label args
--- @return Panel
local function Caps(text, args)
    local fields = {
        classes = {"heroSheetCardLabel"},
        text = string.upper(text),
        fontSize = 11.5,
        bold = true,
        textWrap = false,
    }
    for field, value in pairs(args or {}) do
        fields[field] = value
    end
    return Text(fields)
end

--A block heading ("CHARACTERISTICS", "SKILLS").
--- @param text string
--- @return Panel
local function Heading(text)
    return Text{
        classes = {"heroSheetCardStrong"},
        text = string.upper(text),
        fontSize = 16,
        bold = true,
        textWrap = false,
        halign = "left",
        valign = "center",
    }
end

----------------------------------------------------------------------
--Reading the Hero.

--- @class HeroSheetResistanceGroup
--- @field source nil|string
--- @field parts {name: string, value: nil|number}[]

--Immunities and weaknesses with where each comes from. Entries from
--one source share it: "Fire 10, Sonic 10 (Level 9 Immunity)". Entries added
--by hand (the "Innate" source) and condition immunities carry no source.
--- @param hero creature
--- @return HeroSheetResistanceGroup[] immunities
--- @return HeroSheetResistanceGroup[] weaknesses
local function Resistances(hero)
    local lists = {immunity = {}, weakness = {}}
    local bySource = {immunity = {}, weakness = {}}
    for _, resistance in ipairs(hero:ResistanceEntries()) do
        local dr = resistance.entry:try_get("dr", 0)
        local kind = cond(dr < 0, "weakness", "immunity")
        local source = resistance.entry:try_get("source")
        if source == "Innate" or source == "" then
            source = nil
        end
        local key = tostring(source)
        local group = bySource[kind][key]
        if group == nil then
            group = {source = source, parts = {}}
            bySource[kind][key] = group
            local list = lists[kind]
            list[#list+1] = group
        end
        group.parts[#group.parts+1] = {name = TacPanel.CleanResistanceText(resistance.text), value = math.abs(dr)}
    end
    local conditions = hero:ConditionImmunityDescription()
    if conditions ~= nil and conditions ~= "" then
        local list = lists.immunity
        list[#list+1] = {source = nil, parts = {{name = TacPanel.CleanResistanceText(conditions), value = nil}}}
    end
    return lists.immunity, lists.weakness
end

--The band's read, kept from the signature so the redraw that follows in the
--same pass does not read the Hero again.
--- @type {charid: nil|string, read: nil|table, immunities: table, weaknesses: table}
local g_read = {charid = nil, read = nil, immunities = {}, weaknesses = {}}

--- @param token CharacterToken
--- @return string
local function Signature(token)
    local read = HeroSheetRefresh.Read(token)
    local immunities, weaknesses = {}, {}
    pcall(function() immunities, weaknesses = Resistances(token.properties) end)
    g_read = {charid = token.charid, read = read, immunities = immunities, weaknesses = weaknesses}
    if read == nil then
        return "none"
    end
    return dmhub.ToJson({read.characteristics, read.stats, read.movement, read.potency, read.wealth, read.renown, read.skills, read.languages, immunities, weaknesses})
end

--- @param token CharacterToken
--- @return nil|table read, table immunities, table weaknesses
local function Read(token)
    if g_read.charid ~= token.charid or g_read.read == nil then
        Signature(token)
    end
    return g_read.read, g_read.immunities, g_read.weaknesses
end

----------------------------------------------------------------------
--Hover cards: the stat's name and value, its base, then every source.

--- @class HeroSheetStatRow
--- @field label string
--- @field value string
--- @field base nil|boolean the base row's label is muted

--A small button for a pinned card (Roll, Add).
--- @param text string
--- @param click fun()
--- @param args nil|table more panel args (margins)
--- @return Panel
local function SmallButton(text, click, args)
    local fields = {
        classes = {"heroSheetButton", "heroSheetSolid", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 6,
        width = "auto",
        height = HeroSheetWindow.TargetSize(26),
        hpad = 9,
        borderBox = true,
        halign = "left",
        valign = "center",
        click = function(element)
            click()
        end,
        gui.Label{
            classes = {"heroSheetButtonLabel"},
            text = text,
            width = "auto",
            height = "auto",
            fontSize = 12.5,
            valign = "center",
            textWrap = false,
            interactable = false,
        },
    }
    for field, value in pairs(args or {}) do
        fields[field] = value
    end
    return gui.Panel(fields)
end

--One card row: the label at the left, the value at the right, a faint line
--under it.
--- @param row HeroSheetStatRow
--- @param valueWidth nil|number the value's column (default 104: a stat's number)
--- @return Panel
local function CardRow(row, valueWidth)
    valueWidth = valueWidth or 104
    return gui.Panel{
        classes = {"heroSheetCardRowLine"},
        bgimage = "panels/square.png",
        --a faint line under each row.
        border = {x1 = 0, y1 = 1, x2 = 0, y2 = 0},
        width = "100%",
        height = "auto",
        vpad = 5,
        borderBox = true,
        flow = "none",
        Text{
            classes = {cond(row.base, "heroSheetCardSub", "heroSheetCardText")},
            text = row.label,
            fontSize = 14,
            width = string.format("100%%-%d", valueWidth + 6),
            textWrap = true,
            halign = "left",
            valign = "center",
        },
        Text{
            classes = {"heroSheetCardStrong"},
            text = row.value,
            fontSize = 14,
            bold = true,
            width = valueWidth,
            textAlignment = "right",
            textWrap = true,
            halign = "right",
            valign = "center",
        },
    }
end

--- @class HeroSheetStatCardArgs
--- @field title string
--- @field value nil|string shown beside the title
--- @field rows nil|HeroSheetStatRow[]
--- @field pinned boolean a pinned card carries an x at the top right
--- @field editor nil|Panel[] an editor's fields, under the rows (Edit mode)
--- @field hint nil|string the muted line at the foot ("Click to edit.")
--- @field actions nil|Panel[] buttons under a rule (Roll)
--- @field valueWidth nil|number the rows' value column: wider where a value carries its source (immunities)

--- @param args HeroSheetStatCardArgs
--- @return Panel
local function CardBody(args)
    local head = {
        Text{
            classes = {"heroSheetCardStrong"},
            text = args.title,
            fontSize = 20,
            bold = true,
            valign = "bottom",
        },
    }
    if args.value ~= nil then
        head[#head+1] = Text{
            classes = {"heroSheetCardLabel"},
            text = args.value,
            fontSize = 15,
            bold = true,
            lmargin = 6,
            bmargin = 2,
            valign = "bottom",
        }
    end
    local children = {
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            --clear of a pinned card's x.
            rmargin = cond(args.pinned, 30, 0),
            bmargin = 4,
            children = head,
        },
    }
    for _, row in ipairs(args.rows or {}) do
        children[#children+1] = CardRow(row, args.valueWidth)
    end
    for _, panel in ipairs(args.editor or {}) do
        children[#children+1] = panel
    end
    if args.hint ~= nil then
        children[#children+1] = Text{
            classes = {"heroSheetCardSub"},
            text = args.hint,
            fontSize = 12,
            italics = true,
            width = "100%",
            textWrap = true,
            tmargin = 9,
            halign = "left",
        }
    end
    local actions = args.actions
    if actions ~= nil and #actions > 0 then
        children[#children+1] = gui.Panel{
            classes = {"heroSheetCardRowLine"},
            bgimage = "panels/square.png",
            border = {x1 = 0, y1 = 0, x2 = 0, y2 = 1},
            width = "100%",
            height = "auto",
            tmargin = 8,
            tpad = 10,
            borderBox = true,
            flow = "horizontal",
            children = actions,
        }
    end
    return gui.Panel{
        width = CARD_WIDTH,
        height = "auto",
        flow = "vertical",
        children = children,
    }
end

--A stat's base and sources as card rows, as the shared read of the Hero
--gives them.
--- @param stat nil|{base: any, sources: {name: string, value: string}[]}
--- @param baseText nil|string the base as shown (a size name, a signed number)
--- @return HeroSheetStatRow[]
local function SourceRows(stat, baseText)
    local rows = {}
    if stat == nil then
        return rows
    end
    if stat.base ~= nil then
        rows[#rows+1] = {label = "Base", value = baseText or tostring(stat.base), base = true}
    end
    for _, src in ipairs(stat.sources or {}) do
        rows[#rows+1] = {label = src.name, value = src.value}
    end
    return rows
end

--The hover card's foot in Edit mode: what a click does.
--- @param pinned boolean
--- @return nil|string
local function EditHint(pinned)
    if not pinned and HeroSheet.Editing() then
        return "Click to edit."
    end
    return nil
end

--The band's model: the read it shows now. Built parts register how they
--repaint from it (OnUpdate), and their cards read it when they open, so a
--change or another Hero repaints the built band in place instead of
--building it again. This state, g_keyed and g_updaters live at file level
--because there is one stats band at a time: a second HeroSheetStats.Create()
--would take them over from the first.
--- @type {read: table, immunities: HeroSheetResistanceGroup[], weaknesses: HeroSheetResistanceGroup[]}
local g_model = {read = {}, immunities = {}, weaknesses = {}}
--- @type fun()[]
local g_updaters = {}

--- Register how a built part repaints itself from g_model; it runs now too.
--- @param fn fun()
local function OnUpdate(fn)
    g_updaters[#g_updaters+1] = fn
    fn()
end

--Elements with a card, by key ("mgt", "speed", "imm"...), from the band's
--last draw. A redraw pins again the card that was pinned, so an editor stays
--open while the change it makes redraws the band; "+ Add" pins its column's.
--- @type table<string, Panel>
local g_keyed = {}

--Adds a hover card to panel args: hovering shows it, a click pins it open.
--- @param args table the panel's args
--- @param build fun(pinned: boolean, close: fun(), element: Panel): Panel the card's body
--- @param key nil|string names the element in g_keyed
--- @return table
local function WithCard(args, build, key)
    if key ~= nil then
        local create = args.create
        args.create = function(element)
            g_keyed[key] = element
            if create ~= nil then
                create(element)
            end
        end
    end
    --a pinned card sits under its value, where a tall editor has room.
    return HeroSheetTheme.HoverCard(args, function(pinned, close, element)
        return HeroSheetTheme.CardFrame(build(pinned, close, element), pinned, close)
    end, nil, {halign = "center", valign = "bottom"})
end

--The key whose card is pinned now, if any.
--- @return nil|string
local function PinnedKey()
    for key, element in pairs(g_keyed) do
        --a destroyed panel errors on any read, even .valid.
        local ok, open = pcall(function() return element.valid and element.popup ~= nil end)
        if ok and open then
            return key
        end
    end
    return nil
end

--A field in the pinned card holds the keyboard. The card is a popup, outside
--the band's own panels, so the refresh layer asks this before redrawing the
--band (which would rebuild the card and lose what is being typed).
--- @return boolean
local function PinnedCardHasFocus()
    local key = PinnedKey()
    if key == nil then
        return false
    end
    local has = false
    pcall(function()
        for _, field in ipairs(g_keyed[key].popup:GetChildrenWithClassRecursive("heroSheetField")) do
            --a choice has no input focus: only the typed fields answer.
            local input = field --[[@as Input]]
            if input.hasInputFocus then
                has = true
            end
        end
    end)
    return has
end

--Pin the card of the element with this key (as a click on it does), a frame
--later so the element has its place on screen.
--- @param key string
local function PinSoon(key)
    local function Pin()
        local element = g_keyed[key]
        local ok, valid = pcall(function() return element ~= nil and element.valid end)
        if ok and valid then
            if element.popup == nil then
                element:FireEvent("click")
            end
            return true
        end
        return false
    end
    --at once when the new element is already made, so the card does not blink.
    if Pin() then
        return
    end
    dmhub.Schedule(0.01, function()
        if not mod.unloaded then
            Pin()
        end
    end)
end

--An open editor shows the Hero again after a change it saved: its card is
--built anew from the live Hero (the band's own redraw follows when what it
--shows changed, and pins it again on the new element).
--- @param element Panel the element the card is pinned to
local function Reopen(element)
    if not element.valid then
        return
    end
    --after Enter the closed field still holds the keyboard on record,
    --which would keep the band from redrawing.
    gui.SetFocus(nil)
    --the change is in the live Hero already: redraw now, not at the server's
    --echo. A band that redraws pins the card again; one that shows nothing
    --new keeps this element, whose card is rebuilt here.
    HeroSheet.Saved()
    dmhub.Schedule(0.03, function()
        if mod.unloaded or not element.valid then
            return
        end
        element.popup = nil
        element:FireEvent("click")
    end)
end

--The groups of a resistance list as card rows: the types, then the value
--and source.
--- @param groups HeroSheetResistanceGroup[]
--- @return HeroSheetStatRow[]
local function ResistanceRows(groups)
    local rows = {}
    for _, group in ipairs(groups) do
        local byValue = {}
        local order = {}
        for _, part in ipairs(group.parts) do
            local key = tostring(part.value)
            if byValue[key] == nil then
                byValue[key] = {}
                order[#order+1] = key
            end
            local names = byValue[key]
            names[#names+1] = part.name
        end
        for _, key in ipairs(order) do
            local value = cond(key == "nil", "", key)
            if group.source ~= nil then
                value = string.format("%s (%s)", value, group.source)
            end
            rows[#rows+1] = {label = table.concat(byValue[key], ", "), value = value}
        end
    end
    return rows
end

----------------------------------------------------------------------
--Edit mode. Every value that can be edited has a dashed frame (solid while
--hovered); a click pins its card as the editor: the old sheet's modification
--popup restyled into the card (base, sources, custom changes as fields with
--an x, an add row, Speed's movement types, Size's override), and the old
--sheet's immunities editor the same way. Potency follows the characteristics
--and is not edited.

--A framed value's padding: the frame sits this far outside the value.
local FRAME_HPAD = 4
local FRAME_VPAD = 3

--Give a value's panel Edit mode's frame: a dashed edge just outside it,
--solid while hovered. The padding and the edge are there in both modes
--(clear out of Edit mode), so nothing moves when Edit mode starts. Callers
--take FRAME_HPAD / FRAME_VPAD off their margins to keep the value in place.
--- @param args table the panel's args
--- @param editing boolean
--- @param hoverOf nil|table the args of the panel whose hover lights it (default: this one)
--- @return table args
local function Framed(args, editing, hoverOf)
    local classes = {"heroSheetEditFrame"}
    for _, className in ipairs(args.classes or {}) do
        classes[#classes+1] = className
    end
    if editing then
        classes[#classes+1] = "heroSheetEditOn"
    end
    args.classes = classes
    args.bgimage = "panels/square.png"
    args.border = 1
    args.cornerRadius = 4
    args.hpad = FRAME_HPAD
    args.vpad = FRAME_VPAD
    args.borderBox = true
    if not editing then
        return args
    end
    --the frame is lit from the hovered panel: itself, or the cell around it.
    local framePanel = nil
    local target = hoverOf or args
    local create = args.create
    args.create = function(element)
        framePanel = element
        if create ~= nil then
            create(element)
        end
    end
    local hover, dehover = target.hover, target.dehover
    target.hover = function(element)
        if framePanel ~= nil and framePanel.valid then
            framePanel:SetClass("heroSheetLit", true)
        end
        if hover ~= nil then
            hover(element)
        end
    end
    target.dehover = function(element)
        if framePanel ~= nil and framePanel.valid then
            framePanel:SetClass("heroSheetLit", false)
        end
        if dehover ~= nil then
            dehover(element)
        end
    end
    return args
end

--A typed field in an editor card, in the sheet's field style.
--- @param args table gui.Input args (text, width, change...)
--- @return Panel
local function Field(args)
    local fields = {
        classes = {"heroSheetField"},
        height = HeroSheetWindow.TargetSize(28),
        hpad = 8,
        vpad = 0,
        border = 1,
        cornerRadius = 5,
        borderBox = true,
        fontSize = 14,
        valign = "center",
    }
    for field, value in pairs(args) do
        fields[field] = value
    end
    return gui.Input(fields)
end

--A choice in an editor card, in the fields' look.
--- @param args table gui.Dropdown args (options, idChosen, width, change...)
--- @return Dropdown
local function Choice(args)
    local fields = {
        classes = {"heroSheetField"},
        height = HeroSheetWindow.TargetSize(28),
        valign = "center",
    }
    for field, value in pairs(args) do
        fields[field] = value
    end
    return gui.Dropdown(fields)
end

--The x on a row that can be removed.
--- @param click fun()
--- @return Panel
local function RemoveButton(click)
    return gui.Panel{
        classes = {"heroSheetXButton", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 5,
        width = HeroSheetWindow.TargetSize(28),
        height = HeroSheetWindow.TargetSize(28),
        lmargin = 6,
        valign = "center",
        click = function(element)
            click()
        end,
        gui.Panel{
            classes = {"heroSheetXIcon"},
            bgimage = "phosphor/x-bold.png",
            width = 11,
            height = 11,
            halign = "center",
            valign = "center",
            interactable = false,
        },
    }
end

--An editor row: fields side by side, with the card rows' faint line under.
--- @param children Panel[]
--- @return Panel
local function EditorRow(children)
    return gui.Panel{
        classes = {"heroSheetCardRowLine"},
        bgimage = "panels/square.png",
        border = {x1 = 0, y1 = 1, x2 = 0, y2 = 0},
        width = "100%",
        height = "auto",
        vpad = 5,
        borderBox = true,
        flow = "horizontal",
        children = children,
    }
end

--A whole number as typed: "+1", "-2" or "3"; nil for anything else.
--- @param text string
--- @return nil|number
local function ParseWhole(text)
    local number = tonumber(text)
    if number == nil or math.floor(number) ~= number then
        return nil
    end
    return math.floor(number)
end

--- @class HeroSheetCustomChange
--- @field guid string the custom change's feature guid
--- @field name string the source it shows
--- @field value number

--- @class HeroSheetStatEditSpec
--- @field stat string the stat's name in undo steps, as the old sheet's popup has it ("Might", "Disengage Speed")
--- @field rows HeroSheetStatRow[] the base and the sources that are not custom changes
--- @field custom HeroSheetCustomChange[]
--- @field feature nil|string the standard feature a new change is made from; nil: no add row
--- @field note nil|string the muted line at the foot
--- @field moves nil|boolean Speed: the movement types follow
--- @field size nil|boolean Size: the override follows

--Splits a stat's modifications (DescribeModifications) into source rows and
--the Hero's custom changes, which the old sheet's popup tells apart the same
--way: a "Custom" modifier whose sourceguid is a feature on the Hero.
--- @param hero creature
--- @param mods table[]
--- @param spec HeroSheetStatEditSpec
local function SplitChanges(hero, mods, spec)
    local byGuid = {}
    for _, heroFeature in ipairs(hero:try_get("characterFeatures", {})) do
        byGuid[heroFeature.guid] = heroFeature
    end
    for _, modification in ipairs(mods or {}) do
        local modifier = modification.mod
        local feature = nil
        if modifier ~= nil and modifier:try_get("source") == "Custom" then
            feature = byGuid[modifier:try_get("sourceguid", "")]
        end
        if feature ~= nil then
            spec.custom[#spec.custom+1] = {
                guid = feature.guid,
                name = feature.name,
                value = HeroSheetWrite.CustomChangeValue(feature.modifiers[1]),
            }
        elseif not modification.unchanged then
            spec.rows[#spec.rows+1] = {label = tostring(modification.key), value = tostring(modification.value)}
        end
    end
end

--What a stat's editor shows, read from the live Hero with the old sheet's
--popup's calls: the base (not editable on a Hero, as on the old sheet), its
--sources and the custom changes.
--- @param hero creature
--- @param key string a characteristic id ("mgt"), "size", "speed", "disengage", "stability", "wealth" or "renown"
--- @return HeroSheetStatEditSpec
local function StatEditSpec(hero, key)
    --- @type HeroSheetStatEditSpec
    local spec = {stat = key, rows = {}, custom = {}}
    local function Named(name)
        local base = hero:BaseNamedCustomAttribute(name)
        spec.rows[1] = {label = "Base", value = tostring(base), base = true}
        SplitChanges(hero, hero:DescribeModificationsToNamedCustomAttribute(name), spec)
        spec.stat = name
        spec.feature = name .. " Modification"
    end
    local info = creature.attributesInfo[key]
    if info ~= nil then
        local base = hero:GetBaseAttribute(key).baseValue or 0
        spec.rows[1] = {label = "Base", value = ModStr(base), base = true}
        SplitChanges(hero, hero:DescribeModifications(key, base), spec)
        --the sources can add up past the Hero maximum: say why the score is lower.
        local capped = false
        pcall(function() capped = hero:HeroCharacteristicIsCapped(key, hero:CalculateAttribute(key, base)) end)
        if capped then
            spec.rows[#spec.rows+1] = {label = "Hero Maximum", value = string.format("Capped at %d", creature.heroCharacteristicMax)}
        end
        spec.stat = info.description
        spec.feature = info.description .. " Modification"
        spec.note = "Base comes from the characteristic array chosen in the Builder."
    elseif key == "speed" then
        spec.rows[1] = {label = "Base", value = tostring(hero:GetBaseSpeed()), base = true}
        SplitChanges(hero, hero:DescribeSpeedModifications("walk"), spec)
        spec.stat = "Speed"
        spec.feature = "Speed Modification"
        spec.moves = true
    elseif key == "disengage" then
        Named("Disengage Speed")
    elseif key == "stability" then
        local base = hero:BaseForcedMoveResistance()
        spec.rows[1] = {label = "Base", value = tostring(base), base = true}
        SplitChanges(hero, hero:DescribeModifications("forcedmoveresistance", base), spec)
        spec.stat = "Stability"
        spec.feature = "Stability Modification"
    elseif key == "wealth" then
        Named("Wealth")
    elseif key == "renown" then
        Named("Renown")
    elseif key == "size" then
        --the ancestry's size is the base; an override set by hand replaces it.
        local race = nil
        pcall(function() race = (hero --[[@as character]]):AncestryOrInheritedAncestry() end)
        local label = "Base"
        local base = hero:GetBaseCreatureSize()
        if race ~= nil then
            label = string.format("Base (%s)", race.name)
            base = race.size
        end
        spec.rows[1] = {label = label, value = tostring(base or ""), base = true}
        SplitChanges(hero, hero:DescribeModifications("creatureSize", hero:GetBaseCreatureSizeNumber() or 1), spec)
        spec.stat = "Size"
        spec.size = true
    end
    return spec
end

--A custom change as fields: its source and number (Enter or a click away
--saves either), and an x.
--- @param spec HeroSheetStatEditSpec
--- @param change HeroSheetCustomChange
--- @param element Panel the element the card is pinned to
--- @return Panel
local function CustomChangeRow(spec, change, element)
    local description = string.format("Modify Custom %s Modification", spec.stat)
    return EditorRow{
        Field{
            text = change.name,
            width = "100%-96",
            characterLimit = 32,
            change = function(input)
                local name = input.text
                if name == "" or name == change.name then
                    input.text = change.name
                    return
                end
                HeroSheetWrite.EditCustomChange(change.guid, {name = name}, description)
                Reopen(element)
            end,
        },
        Field{
            text = ModStr(change.value),
            width = 56,
            lmargin = 6,
            textAlignment = "center",
            characterLimit = 4,
            change = function(input)
                local typed = ParseWhole(input.text)
                if typed == nil or typed == change.value then
                    input.text = ModStr(change.value)
                    return
                end
                HeroSheetWrite.EditCustomChange(change.guid, {value = typed}, description)
                Reopen(element)
            end,
        },
        RemoveButton(function()
            HeroSheetWrite.RemoveCustomChange(change.guid, string.format("Remove Custom %s Modification", spec.stat))
            Reopen(element)
        end),
    }
end

--The add row: a source, a number, Add (Enter in the number adds too). A
--number that is not whole says so under the row.
--- @param spec HeroSheetStatEditSpec
--- @param element Panel the element the card is pinned to
--- @return Panel[]
local function AddChangeRow(spec, element)
    local nameField, valueField, problem
    local function Add()
        local typed = ParseWhole(valueField.text)
        if typed == nil then
            problem:SetClass("collapsed", false)
            return
        end
        local name = nameField.text
        if name == "" then
            name = "Custom change"
        end
        HeroSheetWrite.AddCustomChange(spec.feature, name, typed, string.format("Add Custom %s Modification", spec.stat))
        Reopen(element)
    end
    nameField = Field{
        text = "",
        placeholderText = "Source, e.g. a homebrew item",
        width = "100%-118",
        characterLimit = 32,
    }
    valueField = Field{
        text = "",
        placeholderText = "+1",
        width = 56,
        lmargin = 6,
        textAlignment = "center",
        characterLimit = 4,
        edit = function(input)
            problem:SetClass("collapsed", true)
        end,
        submit = function(input)
            Add()
        end,
    }
    problem = Text{
        classes = {"heroSheetCardWarning", "collapsed"},
        text = "Enter a number such as +1 or -2.",
        fontSize = 12,
        tmargin = 4,
        halign = "left",
    }
    return {
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 10,
            nameField,
            valueField,
            SmallButton("Add", Add, {lmargin = 6}),
        },
        problem,
    }
end

--Speed's movement types, as the old sheet's Speed popup lists them: a type
--the Hero has from a feature is ticked and fixed, with where it comes from;
--one given by hand can be taken away; any other can be given.
--- @param hero creature
--- @param element Panel the element the card is pinned to
--- @return Panel[]
local function MovementTypes(hero, element)
    local byGuid = {}
    for _, heroFeature in ipairs(hero:try_get("characterFeatures", {})) do
        byGuid[heroFeature.guid] = heroFeature
    end
    --the order the types are listed in; a type not named here goes last.
    local rank = {walk = 1, fly = 2, climb = 3, swim = 4, burrow = 5, teleport = 6}
    local types = {}
    for i, info in ipairs(creature.movementTypeInfo) do
        types[#types+1] = {info = info, rank = rank[info.id] or (100 + i)}
    end
    table.sort(types, function(left, right) return left.rank < right.rank end)
    local cells = {}
    for _, entry in ipairs(types) do
        local info = entry.info
        local has, customGuid, source = false, nil, nil
        if info.id == "walk" then
            has, source = true, "innate"
        else
            if (hero:try_get("movementSpeeds", {})[info.id] or 0) > 0 then
                has, source = true, "innate"
            end
            for _, modification in ipairs(hero:DescribeModifications(info.id, 0)) do
                has = true
                local feature = nil
                if modification.mod ~= nil and modification.mod:try_get("source") == "Custom" then
                    feature = byGuid[modification.mod:try_get("sourceguid", "")]
                end
                if feature ~= nil then
                    customGuid = feature.guid
                elseif source == nil then
                    source = tostring(modification.key)
                end
            end
        end
        --fixed: Walk, and a type the Hero has only from features.
        local fixed = has and customGuid == nil
        --a fixed box is dimmed (its own class: opacity is not inherited).
        local box = gui.Panel{
            classes = {"heroSheetCheck", cond(fixed, "heroSheetDisabled", nil)},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 3,
            width = 14,
            height = 14,
            valign = "center",
            interactable = false,
            gui.Panel{
                classes = {"heroSheetCheckMark", cond(has, cond(fixed, "heroSheetDisabled", nil), "collapsed")},
                bgimage = "phosphor/check-bold.png",
                width = 11,
                height = 11,
                halign = "center",
                valign = "center",
            },
        }
        local children = {
            box,
            Text{
                text = info.name,
                fontSize = 13.5,
                lmargin = 6,
                valign = "center",
                textWrap = false,
            },
        }
        if source ~= nil and customGuid == nil then
            children[#children+1] = HeroSheetTheme.EllipsisLabel{
                classes = {"heroSheetCardSub"},
                text = source,
                fontSize = 12,
                italics = true,
                width = "auto",
                maxWidth = 60,
                height = "auto",
                lmargin = 5,
                valign = "center",
            }
        end
        cells[#cells+1] = gui.Panel{
            classes = {cond(fixed, nil, "hoverable")},
            bgimage = "panels/square.png",
            bgcolor = "clear",
            width = "33%",
            height = HeroSheetWindow.TargetSize(24),
            flow = "horizontal",
            hover = function(cell)
                box:SetClass("hover", not fixed)
            end,
            dehover = function(cell)
                box:SetClass("hover", false)
            end,
            click = function(cell)
                if fixed then
                    return
                end
                if customGuid ~= nil then
                    HeroSheetWrite.RemoveCustomChange(customGuid, string.format("Remove custom %s movement", info.name))
                else
                    HeroSheetWrite.AddCustomMovement(info.id, info.name)
                end
                Reopen(element)
            end,
            children = children,
        }
    end
    return {
        Caps("Movement types", {tmargin = 12, bmargin = 2, halign = "left"}),
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            children = cells,
        },
    }
end

--Size's override: No override, or a size, then Set.
--- @param hero creature
--- @param element Panel the element the card is pinned to
--- @return Panel
local function SizeOverride(hero, element)
    local options = {{id = "none", text = "No override"}}
    for _, size in ipairs(creature.sizes) do
        options[#options+1] = {id = size, text = size}
    end
    local current = hero:try_get("creatureSizeOverride", "none")
    local choice = Choice{
        options = options,
        idChosen = current,
        width = 140,
    }
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tmargin = 10,
        choice,
        SmallButton("Set", function()
            local id = choice.idChosen
            if id == current then
                return
            end
            HeroSheetWrite.SetSizeOverride(tostring(id))
            Reopen(element)
        end, {lmargin = 6}),
    }
end

--A stat's pinned card in Edit mode.
--- @param key string see StatEditSpec
--- @param title string
--- @param value string the stat as the band shows it
--- @param element Panel the element the card is pinned to
--- @param actions nil|Panel[] Roll, under the editor
--- @return Panel
local function StatEditor(key, title, value, element, actions)
    local token = HeroSheet.Token()
    if token == nil then
        return CardBody{title = title, value = value, pinned = true}
    end
    local hero = token.properties
    local spec = StatEditSpec(hero, key)
    local editor = {}
    for _, change in ipairs(spec.custom) do
        editor[#editor+1] = CustomChangeRow(spec, change, element)
    end
    if spec.feature ~= nil then
        for _, panel in ipairs(AddChangeRow(spec, element)) do
            editor[#editor+1] = panel
        end
    end
    if spec.size then
        --An override in force gets its own row with an x, which returns the
        --Hero to the ancestry's size. "No override" in the dropdown alone was
        --easy to miss.
        local override = hero:try_get("creatureSizeOverride", "none")
        if override ~= "none" then
            editor[#editor+1] = EditorRow{
                Text{
                    text = "Set by hand",
                    fontSize = 14,
                    width = "100%-136",
                    valign = "center",
                },
                Text{
                    classes = {"heroSheetCardStrong"},
                    text = tostring(override),
                    fontSize = 14,
                    bold = true,
                    width = 96,
                    textAlignment = "right",
                    valign = "center",
                },
                RemoveButton(function()
                    HeroSheetWrite.SetSizeOverride("none")
                    Reopen(element)
                end),
            }
        end
        editor[#editor+1] = SizeOverride(hero, element)
    end
    if spec.moves then
        for _, panel in ipairs(MovementTypes(hero, element)) do
            editor[#editor+1] = panel
        end
    end
    return CardBody{
        title = title,
        value = value,
        rows = spec.rows,
        pinned = true,
        editor = editor,
        hint = spec.note,
        actions = actions,
    }
end

--The damage types a hand-added immunity or weakness can name: every type,
--then All (the old sheet's editor's list; the data keeps them in lower case).
--- @return DropdownOption[]
local function DamageTypeOptions()
    local options = {}
    for _, damageType in unhidden_pairs(dmhub.GetTable(DamageType.tableName) or {}) do
        options[#options+1] = {id = string.lower(damageType.name), text = damageType.name}
    end
    table.sort(options, function(left, right) return left.text < right.text end)
    options[#options+1] = {id = "all", text = "All"}
    return options
end

--Every immunity or weakness from features and items, grouped by source,
--including one a stronger entry hides in the band (the band shows only the
--one that counts): the editor lists them all beside those added by hand.
--The names are worded as ResistanceEntries words them.
--- @param hero creature
--- @param weakness boolean
--- @return HeroSheetResistanceGroup[]
local function SourcedResistances(hero, weakness)
    local own = {}
    for _, entry in ipairs(hero:GetResistances()) do
        own[entry] = true
    end
    local groups, bySource = {}, {}
    for _, entry in ipairs(hero:CalculateResistances()) do
        local dr = entry:try_get("dr")
        if entry:try_get("apply") == "Damage Reduction" and dr ~= nil and (dr < 0) == weakness and not own[entry] then
            local keywords = "Damage"
            for keyword, _ in pairs(entry:try_get("keywords", {})) do
                local canonical = ActivatedAbility.CanonicalKeyword(keyword)
                keywords = cond(keywords == "Damage", canonical, keywords .. "/" .. canonical)
            end
            local damageType = tostring(entry:try_get("damageType", "all"))
            local typeText = ""
            if string.lower(damageType) ~= "all" then
                typeText = string.upper_first(damageType) .. " "
            end
            local text = string.format("%s%s %s %d.", typeText, keywords, cond(dr < 0, "weakness", "immunity"), math.abs(dr))
            local source = entry:try_get("source")
            if source == "Innate" or source == "" then
                source = nil
            end
            local key = tostring(source)
            local group = bySource[key]
            if group == nil then
                group = {source = source, parts = {}, seen = {}}
                bySource[key] = group
                groups[#groups+1] = group
            end
            --the same entry can come twice from one source (an item worn twice).
            local name = TacPanel.CleanResistanceText(text)
            local seenKey = name .. "|" .. tostring(math.abs(dr))
            if not group.seen[seenKey] then
                group.seen[seenKey] = true
                group.parts[#group.parts+1] = {name = name, value = math.abs(dr)}
            end
        end
    end
    local conditions = hero:ConditionImmunityDescription()
    if not weakness and conditions ~= nil and conditions ~= "" then
        groups[#groups+1] = {source = nil, parts = {{name = TacPanel.CleanResistanceText(conditions), value = nil}}}
    end
    return groups
end

--The immunities or weaknesses editor in its pinned card: what comes
--from features and items as rows with their source, each one added by hand
--as fields (Immunity or Weakness, damage type, value, an x), then an add row.
--- @param weakness boolean
--- @param title string
--- @param element Panel the element the card is pinned to
--- @return Panel
local function ResistanceEditor(weakness, title, element)
    local token = HeroSheet.Token()
    if token == nil then
        return CardBody{title = title, pinned = true}
    end
    local hero = token.properties
    local types = DamageTypeOptions()
    --the entries that count: only the highest immunity (or weakness) of a
    --damage type applies, so one added by hand can be outweighed by another.
    local counted = {}
    for _, resistance in ipairs(hero:ResistanceEntries()) do
        counted[resistance.entry] = true
    end
    local editor = {}
    for index, entry in ipairs(hero:GetResistances()) do
        local dr = entry:try_get("dr")
        if entry:try_get("apply") == "Damage Reduction" and dr ~= nil and (dr < 0) == weakness then
            --- @type HeroSheetResistanceRef
            local ref = {index = index, damageType = entry:try_get("damageType", "all"), dr = dr}
            local row = {
                Choice{
                    options = {{id = "immunity", text = "Immunity"}, {id = "weakness", text = "Weakness"}},
                    idChosen = cond(weakness, "weakness", "immunity"),
                    width = 98,
                    change = function(dropdown)
                        local sign = cond(dropdown.idChosen == "weakness", -1, 1)
                        HeroSheetWrite.EditResistance(ref, {dr = math.abs(ref.dr) * sign})
                        Reopen(element)
                    end,
                },
                Choice{
                    options = types,
                    idChosen = ref.damageType,
                    hasSearch = true,
                    width = 120,
                    lmargin = 6,
                    change = function(dropdown)
                        HeroSheetWrite.EditResistance(ref, {damageType = tostring(dropdown.idChosen)})
                        Reopen(element)
                    end,
                },
                Field{
                    text = tostring(math.abs(dr)),
                    width = 50,
                    lmargin = 6,
                    textAlignment = "center",
                    characterLimit = 3,
                    change = function(input)
                        local typed = ParseWhole(input.text)
                        if typed == nil or typed == math.abs(ref.dr) then
                            input.text = tostring(math.abs(ref.dr))
                            return
                        end
                        --a negative number turns it into the other kind, as on the old sheet.
                        local sign = cond(weakness, -1, 1)
                        if typed < 0 then
                            sign = -sign
                        end
                        HeroSheetWrite.EditResistance(ref, {dr = math.abs(typed) * sign})
                        Reopen(element)
                    end,
                },
            }
            --an entry another source outweighs says so; hover tells why.
            if not counted[entry] then
                row[#row+1] = Text{
                    classes = {"heroSheetCardSub"},
                    text = "Not counted",
                    fontSize = 12,
                    italics = true,
                    lmargin = 8,
                    valign = "center",
                    textWrap = false,
                    hover = gui.Tooltip(cond(weakness,
                        "Weaknesses don't stack and the highest weakness value of a damage type is used.",
                        "Immunities don't stack and the highest immunity value of a damage type is used.")),
                }
            end
            row[#row+1] = RemoveButton(function()
                HeroSheetWrite.RemoveResistance(ref)
                Reopen(element)
            end)
            editor[#editor+1] = EditorRow(row)
        end
    end
    --the add row: a damage type and an amount (5 when left empty).
    local typeChoice = Choice{
        options = types,
        idChosen = types[1] ~= nil and types[1].id or "all",
        hasSearch = true,
        width = "100%-118",
    }
    local amountField
    local function Add()
        --- @type nil|number
        local typed = 5
        if amountField.text ~= "" then
            typed = ParseWhole(amountField.text)
        end
        if typed == nil then
            amountField.text = ""
            return
        end
        HeroSheetWrite.AddResistance(tostring(typeChoice.idChosen), math.abs(typed) * cond(weakness, -1, 1))
        Reopen(element)
    end
    amountField = Field{
        text = "",
        placeholderText = "5",
        width = 56,
        lmargin = 6,
        textAlignment = "center",
        characterLimit = 3,
        submit = function(input)
            Add()
        end,
    }
    editor[#editor+1] = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tmargin = 10,
        typeChoice,
        amountField,
        SmallButton("Add", Add, {lmargin = 6}),
    }
    return CardBody{
        title = title,
        rows = ResistanceRows(SourcedResistances(hero, weakness)),
        pinned = true,
        valueWidth = RESISTANCE_VALUE_WIDTH,
        editor = editor,
    }
end

--A pill by a word heading in Edit mode ("+ Add"): a small rounded button
--with an icon.
--- @param icon string
--- @param text string
--- @param click fun()
--- @return Panel
local function HeadingPill(icon, text, click)
    return gui.Panel{
        classes = {"heroSheetHeadPill", "hoverable"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 12,
        width = "auto",
        height = HeroSheetWindow.TargetSize(24),
        hpad = 9,
        borderBox = true,
        lmargin = 10,
        flow = "horizontal",
        halign = "left",
        valign = "center",
        click = function(element)
            click()
        end,
        gui.Panel{
            classes = {"heroSheetHeadPillIcon"},
            bgimage = icon,
            width = 11,
            height = 11,
            rmargin = 5,
            valign = "center",
            interactable = false,
        },
        gui.Label{
            classes = {"heroSheetCardStrong"},
            text = text,
            fontSize = 12,
            bold = true,
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
            interactable = false,
        },
    }
end

----------------------------------------------------------------------
--The band's parts.

--A characteristic tile: hover shows its card, a click pins it with Roll
--(and, in Edit mode, the editor). In Edit mode the tile's edge is dashed.
--Its name and value repaint from the band's model.
--- @param i integer which characteristic (in the shared read's order: Might first)
--- @param first boolean
--- @param valueSize number
--- @param editing boolean
--- @return Panel
local function Tile(i, first, valueSize, editing)
    --- @return table characteristic one characteristic from the shared read {id, name, value, base, sources}
    local function Characteristic()
        return (g_model.read.characteristics or {})[i] or {}
    end
    local name = Caps("", {halign = "center"})
    local value = Text{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = valueSize,
        bold = true,
        halign = "center",
    }
    OnUpdate(function()
        local characteristic = Characteristic()
        name.text = string.upper(characteristic.name or "")
        value.text = ModStr(characteristic.value or 0)
    end)
    local args = {
        classes = {"heroSheetTile", cond(editing, "heroSheetEditTile", nil)},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 8,
        width = "20%-6",
        height = "auto",
        lmargin = cond(first, 0, 7),
        tpad = 6,
        bpad = 5,
        borderBox = true,
        flow = "vertical",
        name,
        value,
    }
    if editing then
        args.hover = function(element)
            element:SetClass("heroSheetLit", true)
        end
        args.dehover = function(element)
            element:SetClass("heroSheetLit", false)
        end
    end
    return gui.Panel(WithCard(args, function(pinned, close, element)
        local characteristic = Characteristic()
        local actions = nil
        --Roll: the app's roll dialog for a test of this characteristic.
        if pinned and HeroSheetWrite.CanWrite() then
            actions = {
                SmallButton("Roll", function()
                    close()
                    local token = HeroSheet.Token()
                    if token ~= nil then
                        token.properties:ShowCharacteristicRollDialog(characteristic.id)
                    end
                end),
            }
        end
        if pinned and HeroSheet.Editing() then
            return StatEditor(characteristic.id, characteristic.name, ModStr(characteristic.value or 0), element, actions)
        end
        return CardBody{
            title = characteristic.name,
            value = ModStr(characteristic.value or 0),
            rows = SourceRows(characteristic, ModStr(characteristic.base or 0)),
            pinned = pinned,
            hint = EditHint(pinned),
            actions = actions,
        }
    end, Characteristic().id))
end

--- @param count integer how many characteristics
--- @param valueSize number
--- @param editing boolean
--- @return Panel
local function Tiles(count, valueSize, editing)
    local tiles = {}
    for i = 1, count do
        tiles[#tiles+1] = Tile(i, i == 1, valueSize, editing)
    end
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        tmargin = 8,
        children = tiles,
    }
end

--- @alias HeroSheetCardBuild fun(pinned: boolean, close: fun(), element: Panel): Panel

--Speed's other movement in the book's form: "(fly)".
--- @param read table
--- @return nil|string
local function MovementText(read)
    local movement = read.movement or {}
    if #movement == 0 then
        return nil
    end
    return string.format("(%s)", table.concat(movement, ", "))
end

--A stat's value from the model, for Stat: Speed adds its other movement.
--- @param key string
--- @return fun(): string, nil|string
local function StatValue(key)
    return function()
        local read = g_model.read
        local value = tostring(((read.stats or {})[key] or {}).value or "")
        if key == "speed" then
            return value, MovementText(read)
        end
        return value, nil
    end
end

--- @class HeroSheetStatArgs
--- @field label string
--- @field key string the stat ("size", "speed"...): names its card in g_keyed, and its value is StatValue(key) unless get is given
--- @field get nil|fun(): string, nil|string the value, and after it, muted, Speed's other movement
--- @field card HeroSheetCardBuild
--- @field cell boolean in a cell (Medium, Narrow) rather than on a line (Wide)
--- @field lmargin number
--- @field width nil|string the cell's width
--- @field editing boolean

--One stat as the band shows it, with its hover card: on a line ("SPEED 7")
--at Wide, or in a cell (the label over the value) at Medium. In Edit mode
--the label and value have a dashed frame. Its value repaints from the model.
--- @param args HeroSheetStatArgs
--- @return Panel
local function Stat(args)
    local label, card, cell, lmargin, width, key, editing = args.label, args.card, args.cell, args.lmargin, args.width, args.key, args.editing
    local get = args.get or StatValue(key)
    local valueLabel = Text{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 21,
        bold = true,
        --on a line the value follows its label.
        lmargin = cond(cell, 0, 8),
        valign = "bottom",
    }
    local extraLabel = Text{
        classes = {"heroSheetCardSub", "collapsed"},
        text = "",
        fontSize = 13,
        lmargin = 5,
        bmargin = 3,
        valign = "bottom",
    }
    OnUpdate(function()
        local value, extra = get()
        valueLabel.text = value
        extraLabel.text = extra or ""
        extraLabel:SetClass("collapsed", extra == nil)
    end)
    local valueRow = {valueLabel, extraLabel}
    if cell then
        --the frame goes round the label and value, inside the cell's edge;
        --hovering anywhere in the cell lights it.
        local args = {
            classes = {"heroSheetTile"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = width,
            height = "100%",
            lmargin = lmargin,
            vpad = 6 - FRAME_VPAD,
            hpad = 8,
            borderBox = true,
            flow = "vertical",
        }
        local inner = Framed({
            width = "auto",
            height = "auto",
            flow = "vertical",
            halign = "center",
            valign = "center",
            Caps(label, {halign = "center"}),
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                children = valueRow,
            },
        }, editing, args)
        args[1] = gui.Panel(inner)
        return gui.Panel(WithCard(args, card, key))
    end
    local children = {Caps(label, {valign = "bottom", bmargin = 4})}
    for _, panel in ipairs(valueRow) do
        children[#children+1] = panel
    end
    --the frame's padding comes out of the gap before the stat.
    return gui.Panel(WithCard(Framed({
        width = "auto",
        height = "auto",
        flow = "horizontal",
        lmargin = math.max(0, lmargin - 2 * FRAME_HPAD),
        valign = "bottom",
        children = children,
    }, editing), card, key))
end

--Potency's three values: a pill on a line at Wide, a cell at Medium.
--It follows the characteristics, so Edit mode leaves it as it is.
--- @param cell boolean
--- @param lmargin number
--- @param width nil|string
--- @return Panel
local function Potency(cell, lmargin, width)
    local tiers = {}
    local values = {}
    for i, name in ipairs({"Weak", "Average", "Strong"}) do
        tiers[#tiers+1] = Text{
            classes = {"heroSheetCardLab"},
            text = name,
            fontSize = cond(cell, 13, 14),
            lmargin = cond(i == 1 and cell, 0, cond(cell, 16, 20)),
            bmargin = 3,
            valign = "bottom",
        }
        values[i] = Text{
            classes = {"heroSheetCardStrong"},
            text = "",
            fontSize = cond(cell, 19, 21),
            bold = true,
            lmargin = cond(cell, 5, 8),
            valign = "bottom",
        }
        tiers[#tiers+1] = values[i]
    end
    OnUpdate(function()
        local potency = g_model.read.potency or {}
        values[1].text = tostring(potency.weak or 0)
        values[2].text = tostring(potency.average or 0)
        values[3].text = tostring(potency.strong or 0)
    end)
    local function Card(pinned)
        local potency = g_model.read.potency or {}
        return CardBody{
            title = "Potency",
            rows = {
                {label = "Strong", value = tostring(potency.strong or 0)},
                {label = "Average", value = tostring(potency.average or 0)},
                {label = "Weak", value = tostring(potency.weak or 0)},
            },
            pinned = pinned,
        }
    end
    if cell then
        return gui.Panel(WithCard({
            classes = {"heroSheetTile"},
            bgimage = "panels/square.png",
            border = 1,
            cornerRadius = 8,
            width = width,
            height = "100%",
            lmargin = lmargin,
            vpad = 6,
            hpad = 8,
            borderBox = true,
            flow = "vertical",
            Caps("Potency", {halign = "center"}),
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                children = tiers,
            },
        }, Card))
    end
    local children = {Caps("Potency", {valign = "bottom", bmargin = 5})}
    for _, panel in ipairs(tiers) do
        children[#children+1] = panel
    end
    return gui.Panel(WithCard({
        classes = {"heroSheetPotency"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 18,
        width = "auto",
        height = "auto",
        hpad = 14,
        vpad = 3,
        borderBox = true,
        flow = "horizontal",
        halign = "center",
        children = children,
    }, Card))
end

--The cards for Size, Speed, Disengage, Stability, Wealth and Renown: read
--rows on hover, the editor when pinned in Edit mode. They read the model
--when they open, so they always show the Hero on show.
--- @return table<string, HeroSheetCardBuild>
local function StatCards()
    --- @param key string
    --- @param title string
    --- @param getSources fun(): any the stat's {base, sources} from the shared read
    --- @param getValue fun(): string
    --- @param getBase nil|fun(): string the base as shown
    local function StatCard(key, title, getSources, getValue, getBase)
        return function(pinned, close, element)
            local value = getValue()
            if pinned and HeroSheet.Editing() then
                return StatEditor(key, title, value, element)
            end
            return CardBody{
                title = title,
                value = value,
                rows = SourceRows(getSources(), getBase ~= nil and getBase() or nil),
                pinned = pinned,
                hint = EditHint(pinned),
            }
        end
    end
    local function Stats()
        return g_model.read.stats or {}
    end
    --a named attribute's base and changes, read when its card opens.
    local function Named(name)
        local token = HeroSheet.Token()
        local hero = token ~= nil and token.properties or nil
        local base, mods = 0, {}
        if hero ~= nil then
            pcall(function() base = hero:BaseNamedCustomAttribute(name) end)
            pcall(function() mods = hero:DescribeModificationsToNamedCustomAttribute(name) end)
        end
        local stat = {base = base, sources = {}}
        for _, modification in ipairs(mods or {}) do
            if modification.key ~= nil and not modification.unchanged then
                stat.sources[#stat.sources+1] = {name = tostring(modification.key), value = tostring(modification.value)}
            end
        end
        return stat
    end
    local function Value(key)
        return function()
            return tostring((Stats()[key] or {}).value or "")
        end
    end
    --a stat whose sources the shared read lists.
    local function ReaderStatCard(key, title)
        return StatCard(key, title, function() return Stats()[key] end, Value(key))
    end
    return {
        size = StatCard("size", "Size", function() return Stats().size or {} end, Value("size"), function()
            local size = Stats().size or {}
            return creature.sizes[size.base] or tostring(size.base)
        end),
        speed = ReaderStatCard("speed", "Speed"),
        disengage = ReaderStatCard("disengage", "Disengage"),
        stability = ReaderStatCard("stability", "Stability"),
        wealth = StatCard("wealth", "Wealth", function() return Named("Wealth") end, function() return tostring(g_model.read.wealth or 0) end),
        renown = StatCard("renown", "Renown", function() return Named("Renown") end, function() return tostring(g_model.read.renown or 0) end),
    }
end

--- @class HeroSheetWordsColumnArgs
--- @field label string
--- @field content Panel
--- @field card HeroSheetCardBuild
--- @field width string
--- @field ruled boolean a faint rule at its left (every column but the first in a row)
--- @field key string
--- @field editable nil|boolean in Edit mode: a dashed frame round the words and "+ Add" by the heading
--- @field open nil|fun() edited in a window (Skills, Languages): in Edit mode the pill and a click on the words open it
--- @field pill nil|{icon: string, text: string} the heading's pill when not "+ Add" (Skills' "Manage")
--- @field row nil|boolean Narrow's row: the heading at the left, the words beside it

--The words row's columns: each a heading over its words, with a hover card.
--- @param args HeroSheetWordsColumnArgs
--- @param editing boolean
--- @return Panel
local function WordsColumn(args, editing)
    local edit = editing and args.editable == true
    local heading = Heading(args.label)
    local open = args.open
    if edit then
        local key = args.key
        local pill = args.pill or {icon = "phosphor/plus-bold.png", text = "Add"}
        heading = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            heading,
            HeadingPill(pill.icon, pill.text, function()
                if open ~= nil then
                    open()
                    return
                end
                local element = g_keyed[key]
                if element ~= nil and element.valid then
                    element:FireEvent("click")
                end
            end),
        }
    end
    --the frame stands out from the words by its padding, so the words keep
    --their place under the heading.
    local wordsArgs = Framed({
        width = "100%+" .. tostring(2 * FRAME_HPAD),
        height = "auto",
        flow = "vertical",
        lmargin = -FRAME_HPAD,
        tmargin = 5 - FRAME_VPAD,
        bmargin = -FRAME_VPAD,
        args.content,
    }, edit)
    --a word list edited in a window opens it from its frame; the hover card
    --still shows, and a click outside Edit mode pins it.
    if edit and open ~= nil then
        wordsArgs.click = function()
            open()
        end
    end
    if args.row then
        --Narrow: the heading in a column of its own, the words level with it.
        wordsArgs.tmargin = 1 - FRAME_VPAD
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            gui.Panel{
                width = NARROW_LABEL_WIDTH,
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "top",
                heading,
            },
            gui.Panel{
                width = string.format("100%%-%d", NARROW_LABEL_WIDTH),
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "top",
                gui.Panel(WithCard(wordsArgs, args.card, args.key)),
            },
        }
    end
    return gui.Panel{
        classes = {"heroSheetBandEdge"},
        bgimage = "panels/square.png",
        border = {x1 = cond(args.ruled, 1, 0), y1 = 0, x2 = 0, y2 = 0},
        width = args.width,
        height = "auto",
        lmargin = cond(args.ruled, 18, 0),
        lpad = cond(args.ruled, 16, 0),
        borderBox = true,
        flow = "vertical",
        valign = "top",
        heading,
        gui.Panel(WithCard(wordsArgs, args.card, args.key)),
    }
end

--Words as one wrapping line, or "None", repainted from the model.
--- @param get fun(): string the words ("" for none)
--- @return Panel
local function Words(get)
    local label = Text{
        text = "",
        fontSize = 14,
        width = "100%",
        textWrap = true,
        halign = "left",
    }
    OnUpdate(function()
        local text = get()
        label.text = cond(text == "", "None", text)
        label:SetClass("heroSheetCardSub", text == "")
        label:SetClass("heroSheetCardText", text ~= "")
    end)
    return label
end

--A resistance list as words: "Acid 5, Poison 5 (Adaptive Second Skin of
--Toxins)", the source smaller and muted.
--- @param groups HeroSheetResistanceGroup[]
--- @return string
local function ResistanceWords(groups)
    local sub = HeroSheetTheme.Palette().cardSub
    local parts = {}
    for _, group in ipairs(groups) do
        local names = {}
        for _, part in ipairs(group.parts) do
            names[#names+1] = part.name .. cond(part.value ~= nil, " " .. tostring(part.value), "")
        end
        local text = table.concat(names, ", ")
        if group.source ~= nil then
            text = string.format("%s <color=%s><size=88%%>(%s)</size></color>", text, sub, group.source)
        end
        parts[#parts+1] = text
    end
    return table.concat(parts, ", ")
end

--The skills by group, each group's name in the label colour: the line breaks
--between groups, and a group too long for the column wraps within itself.
--One label per group: the labels are made again only when the number of
--groups changes, else their words repaint.
--- @return Panel
local function SkillWords()
    --- @type Panel[]
    local units = {}
    local holder = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
    }
    OnUpdate(function()
        local skills = g_model.read.skills or {}
        local count = math.max(1, #skills)
        if #units ~= count then
            units = {}
            for i = 1, count do
                units[i] = Text{
                    text = "",
                    fontSize = 14,
                    maxWidth = "100%",
                    textWrap = true,
                    rmargin = 18,
                    halign = "left",
                }
            end
            holder.children = units
        end
        if #skills == 0 then
            units[1].text = "None"
            units[1]:SetClass("heroSheetCardSub", true)
            units[1]:SetClass("heroSheetCardText", false)
            return
        end
        local label = HeroSheetTheme.Palette().cardLabel
        for i, group in ipairs(skills) do
            units[i].text = string.format("<color=%s><size=82%%><b>%s</b></size></color> %s", label, string.upper(group.name), table.concat(group.skills, ", "))
            units[i]:SetClass("heroSheetCardSub", false)
            units[i]:SetClass("heroSheetCardText", true)
        end
    end)
    return holder
end

--The words row: Skills, Languages, Immunities, Weaknesses. Wide: one row.
--Medium: Skills across the top, the other three under it. Narrow: a row
--each, the heading at the left, with rules between. In Edit mode Skills and
--Languages open their windows from Manage / + Add and from their frames;
--Immunities and Weaknesses pin their editors. Words and cards read the
--band's model.
--- @param layout string "wide", "medium" or "narrow"
--- @param editing boolean
--- @return Panel[]
local function WordsRow(layout, editing)
    local function Skills()
        return g_model.read.skills or {}
    end
    local function Languages()
        return g_model.read.languages or {}
    end
    --where they come from: slow to work out, so read when a card first shows
    --and kept until the band repaints.
    local skillFrom, skillByHand, languageFrom = nil, nil, nil
    --display name -> in-world name, for languages Plain Language Names renames.
    local languageInWorld = nil
    OnUpdate(function()
        skillFrom, skillByHand, languageFrom, languageInWorld = nil, nil, nil, nil
    end)
    local function Hero()
        local token = HeroSheet.Token()
        return token ~= nil and token.properties or nil
    end
    --The card's foot: the sentences that apply, any of which may be nil.
    --- @param from nil|string where the words come from
    --- @param byHand nil|string the ones added by hand
    --- @param hint nil|string what a click does
    --- @return nil|string
    local function Sentences(from, byHand, hint)
        local list = {}
        for _, sentence in ipairs({from or "", byHand or "", hint or ""}) do
            if sentence ~= "" then
                list[#list+1] = sentence
            end
        end
        if #list == 0 then
            return nil
        end
        return table.concat(list, " ")
    end
    local function SkillsCard(pinned)
        local rows = {}
        for _, group in ipairs(Skills()) do
            rows[#rows+1] = {label = group.name, value = table.concat(group.skills, ", ")}
        end
        local hero = Hero()
        if skillFrom == nil and hero ~= nil then
            local from, byHand = nil, nil
            --looked up when used: the Builder's files load after the sheet's.
            pcall(function() from, byHand = rawget(_G, "HeroSkillsLanguages").SkillSources(hero --[[@as character]]) end)
            skillFrom, skillByHand = from or "", byHand
        end
        local from = skillFrom ~= "" and skillFrom or nil
        --a group's skills take most of the card, so a long list keeps to a line.
        return CardBody{title = "Skills", rows = rows, pinned = pinned, hint = Sentences(from, skillByHand, EditHint(pinned)), valueWidth = SKILLS_VALUE_WIDTH}
    end
    local function LanguagesCard(pinned)
        local hero = Hero()
        if languageFrom == nil then
            languageFrom = {}
            languageInWorld = {}
            if hero ~= nil then
                pcall(function()
                    for _, row in ipairs(rawget(_G, "HeroSkillsLanguages").LanguageSources(hero --[[@as character]])) do
                        languageFrom[row.label] = row.value
                        languageInWorld[row.label] = row.inWorld
                    end
                end)
            end
        end
        local rows = {}
        for _, name in ipairs(Languages()) do
            local label = name
            if languageInWorld ~= nil and languageInWorld[name] ~= nil then
                label = string.format("%s (%s)", name, languageInWorld[name])
            end
            rows[#rows+1] = {label = label, value = languageFrom[name] or ""}
        end
        return CardBody{title = "Languages", rows = rows, pinned = pinned, hint = EditHint(pinned)}
    end
    --- @param title string
    --- @param weakness boolean
    local function ResistanceCard(title, weakness)
        return function(pinned, close, element)
            if pinned and HeroSheet.Editing() then
                return ResistanceEditor(weakness, title, element)
            end
            local groups = cond(weakness, g_model.weaknesses, g_model.immunities)
            return CardBody{title = title, rows = ResistanceRows(groups), pinned = pinned, hint = EditHint(pinned), valueWidth = RESISTANCE_VALUE_WIDTH}
        end
    end
    local function Column(label, content, card, width, ruled, key, editable)
        local args = {label = label, content = content, card = card, width = width, ruled = ruled, key = key, editable = editable, row = layout == "narrow"}
        if key == "skills" then
            args.editable = true
            args.open = HeroSheetWindows.OpenSkills
            args.pill = {icon = "phosphor/pencil-simple.png", text = "Manage"}
        elseif key == "langs" then
            args.editable = true
            args.open = HeroSheetWindows.OpenLanguages
        end
        return WordsColumn(args, editing)
    end
    local skillsWords = SkillWords()
    local langWords = Words(function() return table.concat(Languages(), ", ") end)
    local immWords = Words(function() return ResistanceWords(g_model.immunities) end)
    local weakWords = Words(function() return ResistanceWords(g_model.weaknesses) end)
    local immCard = ResistanceCard("Immunities", false)
    local weakCard = ResistanceCard("Weaknesses", true)
    if layout == "narrow" then
        local function Between()
            return gui.Panel{
                classes = {"heroSheetBandRule"},
                bgimage = "panels/square.png",
                width = "100%",
                height = 1,
                vmargin = 9,
            }
        end
        return {
            Column("Skills", skillsWords, SkillsCard, "100%", false, "skills"),
            Between(),
            Column("Languages", langWords, LanguagesCard, "100%", false, "langs"),
            Between(),
            Column("Immunities", immWords, immCard, "100%", false, "imm", true),
            Between(),
            Column("Weaknesses", weakWords, weakCard, "100%", false, "weak", true),
        }
    end
    if layout == "medium" then
        return {
            Column("Skills", skillsWords, SkillsCard, "100%", false, "skills"),
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                tmargin = 10,
                Column("Languages", langWords, LanguagesCard, "33%-12", false, "langs"),
                Column("Immunities", immWords, immCard, "34%-12", true, "imm", true),
                Column("Weaknesses", weakWords, weakCard, "33%-12", true, "weak", true),
            },
        }
    end
    return {
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            Column("Skills", skillsWords, SkillsCard, "46%-14", false, "skills"),
            Column("Languages", langWords, LanguagesCard, "17%-14", true, "langs"),
            Column("Immunities", immWords, immCard, "21%-14", true, "imm", true),
            Column("Weaknesses", weakWords, weakCard, "16%-14", true, "weak", true),
        },
    }
end

--The faint rule between the numbers and the words.
--- @return Panel
local function Rule()
    return gui.Panel{
        classes = {"heroSheetBandRule"},
        bgimage = "panels/square.png",
        width = "100%",
        height = 1,
        tmargin = 10,
        bmargin = 9,
    }
end

--The band at Wide: the tiles and, right of a rule, three centred lines
--(Size to Stability, the Potency pill, Wealth and Renown), then the words.
--- @param editing boolean
--- @return Panel[]
local function WideBand(editing)
    local cards = StatCards()
    local function Line(children, tmargin, bmargin)
        return gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            tmargin = tmargin,
            bmargin = bmargin,
            children = children,
        }
    end
    local lines = gui.Panel{
        classes = {"heroSheetBandEdge"},
        bgimage = "panels/square.png",
        border = {x1 = 1, y1 = 0, x2 = 0, y2 = 0},
        width = "46%-26",
        height = "auto",
        lmargin = 26,
        lpad = 24,
        borderBox = true,
        flow = "vertical",
        valign = "center",
        Line({
            Stat{label = "Size", key = "size", card = cards.size, cell = false, lmargin = 0, editing = editing},
            Stat{label = "Speed", key = "speed", card = cards.speed, cell = false, lmargin = 26, editing = editing},
            Stat{label = "Disengage", key = "disengage", card = cards.disengage, cell = false, lmargin = 26, editing = editing},
            Stat{label = "Stability", key = "stability", card = cards.stability, cell = false, lmargin = 26, editing = editing},
        }, -FRAME_VPAD, 0),
        --the framed lines' padding comes out of the gaps round Potency.
        Line({Potency(false, 0)}, 14 - FRAME_VPAD, 0),
        Line({
            Stat{label = "Wealth", key = "wealth", get = function() return tostring(g_model.read.wealth or 0), nil end, card = cards.wealth, cell = false, lmargin = 0, editing = editing},
            Stat{label = "Renown", key = "renown", get = function() return tostring(g_model.read.renown or 0), nil end, card = cards.renown, cell = false, lmargin = 26, editing = editing},
        }, 14 - FRAME_VPAD, -FRAME_VPAD),
    }
    local children = {
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            gui.Panel{
                width = "54%",
                height = "auto",
                flow = "vertical",
                valign = "top",
                Heading("Characteristics"),
                Tiles(#(g_model.read.characteristics or {}), 30, editing),
            },
            lines,
        },
        Rule(),
    }
    for _, panel in ipairs(WordsRow("wide", editing)) do
        children[#children+1] = panel
    end
    return children
end

--One half of the Wealth and Renown cell: the label over the value, the pair
--framed one by one in Edit mode.
--- @param label string
--- @param get fun(): string
--- @param card HeroSheetCardBuild
--- @param key string
--- @param editing boolean
--- @return Panel
local function Half(label, get, card, key, editing)
    local args = {
        width = "50%",
        height = "auto",
        flow = "vertical",
        valign = "center",
    }
    local value = Text{
        classes = {"heroSheetCardStrong"},
        text = "",
        fontSize = 21,
        bold = true,
        halign = "center",
    }
    OnUpdate(function()
        value.text = get()
    end)
    local inner = Framed({
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "center",
        valign = "center",
        Caps(label, {halign = "center"}),
        value,
    }, editing, args)
    args[1] = gui.Panel(inner)
    return gui.Panel(WithCard(args, card, key))
end

--The Wealth and Renown cell at Medium and Narrow.
--- @param cards table<string, HeroSheetCardBuild>
--- @param editing boolean
--- @param width string
--- @return Panel
local function WealthRenownPair(cards, editing, width)
    return gui.Panel{
        classes = {"heroSheetTile"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 8,
        width = width,
        height = "100%",
        lmargin = 7,
        vpad = 6 - FRAME_VPAD,
        hpad = 8,
        borderBox = true,
        flow = "horizontal",
        Half("Wealth", function() return tostring(g_model.read.wealth or 0) end, cards.wealth, "wealth", editing),
        Half("Renown", function() return tostring(g_model.read.renown or 0) end, cards.renown, "renown", editing),
    }
end

--The band at Medium: the tiles across the top, then one strip of equal
--cells (Size to Stability, Potency, Wealth and Renown), then the words.
--- @param editing boolean
--- @return Panel[]
local function MediumBand(editing)
    local cards = StatCards()
    --the strip's shares: four equal cells, then Potency (1.9 cells) and the
    --pair (1.4).
    local pair = WealthRenownPair(cards, editing, "19.2%-6")
    local strip = gui.Panel{
        width = "100%",
        height = 58,
        flow = "horizontal",
        tmargin = 7,
        Stat{label = "Size", key = "size", card = cards.size, cell = true, lmargin = 0, width = "13.7%-6", editing = editing},
        Stat{label = "Speed", key = "speed", card = cards.speed, cell = true, lmargin = 7, width = "13.7%-6", editing = editing},
        Stat{label = "Disengage", key = "disengage", card = cards.disengage, cell = true, lmargin = 7, width = "13.7%-6", editing = editing},
        Stat{label = "Stability", key = "stability", card = cards.stability, cell = true, lmargin = 7, width = "13.7%-6", editing = editing},
        Potency(true, 7, "26%-6"),
        pair,
    }
    local children = {
        Heading("Characteristics"),
        Tiles(#(g_model.read.characteristics or {}), 30, editing),
        strip,
        Rule(),
    }
    for _, panel in ipairs(WordsRow("medium", editing)) do
        children[#children+1] = panel
    end
    return children
end

--The band at Narrow, for the Stats pane: the characteristics go to the
--holder under the banner (they show on every pane); here Size to Stability
--as four cells, Potency beside Wealth and Renown, then the words as rows.
--- @param editing boolean
--- @return Panel[]
local function NarrowBand(editing)
    local cards = StatCards()
    --the banner row: smaller numbers, the row flush with its plate.
    local tiles = Tiles(#(g_model.read.characteristics or {}), 22, editing)
    tiles.selfStyle.tmargin = 0
    g_tilesHolder.children = {tiles}
    g_tilesHolder:SetClass("collapsed", false)
    local pair = WealthRenownPair(cards, editing, "50%-4")
    local children = {
        gui.Panel{
            width = "100%",
            height = 58,
            flow = "horizontal",
            Stat{label = "Size", key = "size", card = cards.size, cell = true, lmargin = 0, width = "25%-6", editing = editing},
            Stat{label = "Speed", key = "speed", card = cards.speed, cell = true, lmargin = 7, width = "25%-6", editing = editing},
            Stat{label = "Disengage", key = "disengage", card = cards.disengage, cell = true, lmargin = 7, width = "25%-6", editing = editing},
            Stat{label = "Stability", key = "stability", card = cards.stability, cell = true, lmargin = 7, width = "25%-6", editing = editing},
        },
        gui.Panel{
            width = "100%",
            height = 58,
            flow = "horizontal",
            tmargin = 7,
            Potency(true, 0, "50%-3"),
            pair,
        },
        Rule(),
    }
    for _, panel in ipairs(WordsRow("narrow", editing)) do
        children[#children+1] = panel
    end
    return children
end

----------------------------------------------------------------------
--The band.

--- The stats band for the Character tab. A HeroSheetRefresh block, built
--- once for a tier and Edit mode and repainted in place when what it shows
--- changes or another Hero is shown (as the EotW sheet does); it is built again
--- only when its shape changes (the tier, Edit mode).
--- @return Panel band
--- @return Panel tiles Narrow's characteristics, for the sheet to place under the banner
function HeroSheetStats.Create()
    g_tilesHolder = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
    }
    --Edit mode as the band was last drawn: opening a tab ends Edit mode even
    --when it was off, and that must not redraw the band.
    local drawnEditing = nil
    --the shape the built band has, nil before it is built.
    --- @type nil|string
    local drawnShape = nil

    --What fixes the band's panels: the tier, Edit mode and how many
    --characteristics. Anything else repaints in place.
    --- @param tier string
    --- @return string
    local function Shape(tier)
        return table.concat({tier, tostring(HeroSheet.Editing()), tostring(#(g_model.read.characteristics or {}))}, "|")
    end

    --Points the model at the Hero's read; false when there is none yet.
    --- @param token CharacterToken
    --- @return boolean
    local function Model(token)
        local read, immunities, weaknesses = Read(token)
        g_model = {read = read or {}, immunities = immunities or {}, weaknesses = weaknesses or {}}
        return read ~= nil
    end

    --Builds the band for a tier. A card pinned before (an editor whose change
    --rebuilt the band) is pinned again, unless Edit mode just changed.
    --- @param panel Panel
    --- @param token CharacterToken
    --- @param tier string
    --- @param repin boolean
    local function Draw(panel, token, tier, repin)
        local pinned = nil
        if repin then
            pinned = PinnedKey()
        end
        g_keyed = {}
        g_updaters = {}
        if not Model(token) then
            drawnShape = nil
            panel.children = {}
            return
        end
        local editing = HeroSheet.Editing()
        drawnEditing = editing
        drawnShape = Shape(tier)
        local narrow = tier == "narrow"
        if not narrow and #g_tilesHolder.children > 0 then
            g_tilesHolder.children = {}
        end
        g_tilesHolder:SetClass("collapsed", not narrow)
        --at Narrow the band sits in the lists' plate, as a pane: no plate of its own.
        panel:SetClass("heroSheetPlate", not narrow)
        panel:SetClass("heroSheetBlock", not narrow)
        panel:SetClass("heroSheetBandPane", narrow)
        panel.selfStyle.hpad = cond(narrow, 2, 18)
        panel.selfStyle.vpad = cond(narrow, 4, 12)
        if tier == "wide" then
            panel.children = WideBand(editing)
        elseif narrow then
            panel.children = NarrowBand(editing)
        else
            panel.children = MediumBand(editing)
        end
        if pinned ~= nil then
            PinSoon(pinned)
        end
    end

    --Repaints the built band from the Hero (a change, another Hero), or
    --builds it when its shape changed. A pinned card is built again from
    --the new read, so an open editor shows the change it saved.
    --- @param panel Panel
    --- @param token CharacterToken
    --- @param tier string
    local function Repaint(panel, token, tier)
        if not Model(token) or drawnShape == nil or Shape(tier) ~= drawnShape then
            Draw(panel, token, tier, true)
            return
        end
        for _, fn in ipairs(g_updaters) do
            fn()
        end
        local pinned = PinnedKey()
        if pinned ~= nil then
            local element = g_keyed[pinned]
            element.popup = nil
            element:FireEvent("click")
        end
    end

    --The tier and Edit mode are part of the signature: the window's events
    --can miss the band (a kept window reopening at another size), and the
    --next refresh pass then rebuilds it. A new window's first layout comes as
    --the event.
    local spec = {
        name = "stats band",
        signature = function(token)
            --the label and muted colours are written into the skill groups'
            --and sources' text, so a new colour scheme repaints the band.
            local palette = HeroSheetTheme.Palette()
            return table.concat({Signature(token), HeroSheet.Tier(), tostring(HeroSheet.Editing()), palette.cardLabel, palette.cardSub}, "|")
        end,
        refresh = function(panel, token)
            Repaint(panel, token, HeroSheet.Tier())
        end,
        holdsKeyboard = function(panel)
            return PinnedCardHasFocus()
        end,
    }
    local band = HeroSheetRefresh.Block({
        classes = {"heroSheetPlate", "heroSheetBlock"},
        bgimage = "panels/square.png",
        border = 1,
        cornerRadius = 10,
        width = "100%",
        height = "auto",
        flow = "vertical",
        vpad = 12,
        hpad = 18,
        borderBox = true,
        valign = "top",
        heroSheetTier = function(element, tier)
            local token = HeroSheet.Token()
            if token ~= nil then
                Draw(element, token, tier, true)
            end
        end,
        heroSheetEdit = function(element, editing)
            local token = HeroSheet.Token()
            if token ~= nil and HeroSheet.Editing() ~= drawnEditing then
                Draw(element, token, HeroSheet.Tier(), false)
            end
        end,
    }, spec)
    return band, g_tilesHolder
end
