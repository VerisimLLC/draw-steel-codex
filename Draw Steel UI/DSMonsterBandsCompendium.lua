local mod = dmhub.GetModLoading()

-- Monster Bands compendium page. See MONSTER_BANDS_PRD.md.
--
-- Replaces the Rules -> Malice page: same MonsterGroup table, but the whole
-- band entry (lore, languages, tactics, sample encounters, malice, roster,
-- associated creatures) rather than malice alone.

local ShowMonsterBands

Compendium.Register{
    section = "Rules",
    text = "Monster Bands",
    contentType = "MonsterGroup",
    click = function(contentPanel)
        ShowMonsterBands(contentPanel)
    end,
}

-- Monster Bands compendium page -- harness build.
-- Reads and writes the REAL MonsterGroup record. No fixtures.
--
-- Refresh is SCOPED, following DSClassEditor.lua: a mutation rebuilds only the
-- affected section's body, never the whole editor. The vscroll container is an
-- ancestor of every section, so leaving it alone is what preserves scroll
-- position, expand/collapse state, and the layout cost of the other sections
-- (panels inside a vscroll container measure ~3ms each -- see the perf notes at
-- DSClassEditor.lua:907).

local CONTENT_W = 720
local FIELD_W = 560

-- Left pane geometry. Percentages resolve against the OUTER box under
-- borderBox, so sizes here are explicit.
local LIST_W = 230          -- the pane itself
local LIST_INNER = 204      -- pane minus padding; panels render at their exact width
local SEARCH_W = 184        -- gui.Input renders ~20 units WIDER than requested
                            -- (frame + blur), so subtract that to line the
                            -- search box up with the list below it
local ROW_W = 190           -- inner minus the scroll handle, so a highlighted
                            -- row stops just short of the scrollbar


local g_styles = nil
local function Styles()
    if g_styles == nil then
        g_styles = ThemeEngine.MergeStyles{
            {
                selectors = {"bandRow"},
                bgimage = true,
                bgcolor = "clear",
            },
            {
                selectors = {"bandRow", "selected"},
                bgcolor = "@bgInverse",
            },
            {
                selectors = {"bandRowLabel", "parent:selected"},
                color = "@fgInverse",
            },
            {
                selectors = {"bandDivider"},
                bgimage = true,
                bgcolor = "@border",
            },
            {
                -- DMHub hit-tests against a panel surface, so click targets
                -- need one even when they paint nothing.
                selectors = {"bandClickable"},
                bgimage = true,
                bgcolor = "clear",
            },
        }
    end
    return g_styles
end

local function Upload(g)
    dmhub.SetAndUploadTableItem(MonsterGroup.tableName, g)
end

-- The default malice group is not a band -- it is the fallback whose abilities
-- every monster gets when its own band does not inherit them. It is flagged
-- bandScope="monster" so it would otherwise be filtered out, but the old Malice
-- page was the only way to edit it, so it is listed here as an explicit
-- exception and labelled rather than passed off as a band.
local function IsDefaultMaliceGroup(id)
    return id == MonsterGroup.DefaultMaliceGroupId()
end

local function ListedHere(id, v)
    return v:IsBand() or IsDefaultMaliceGroup(id)
end

-- Monsters per band, by groupid.
local function MemberCounts()
    local counts = {}
    for _, m in pairs(assets.monsters or {}) do
        local p = m.properties
        if p ~= nil then
            local gid = p:try_get("groupid")
            if gid ~= nil then counts[gid] = (counts[gid] or 0) + 1 end
        end
    end
    return counts
end

local function RosterFor(bandid)
    local out = {}
    for id, m in pairs(assets.monsters or {}) do
        local p = m.properties
        if p ~= nil and p:try_get("groupid") == bandid then
            out[#out + 1] = {
                id = id,
                name = m.description or "(unnamed)",
                level = p:try_get("level", 1),
                role = p:try_get("role", ""),
                ev = p:try_get("ev", 0),
            }
        end
    end
    table.sort(out, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.name < b.name
    end)
    return out
end

local function LanguageOptions()
    local opts = {}
    for k, v in pairs(dmhub.GetTable(Language.tableName) or {}) do
        opts[#opts + 1] = { id = k, text = v.name }
    end
    table.sort(opts, function(a, b) return a.text < b.text end)
    return opts
end


local function Count(n, singular, plural)
    if n == 0 then return "empty" end
    return string.format("%d %s", n, cond(n == 1, singular, plural))
end

-- ------------------------------------------------------------------ controls

-- Returns the section panel AND its body. Fire "refreshSection" on the body to
-- rebuild just that section (children + the header's count) in place.
--   noteFn         -- function returning the header's muted count text
--   buildChildren  -- function returning the body's children
local function Section(title, noteFn, buildChildren, startOpen)
    local noteLabel = gui.Label{
        classes = {"label", "fgMuted", "sizeXs"},
        text = noteFn and noteFn() or "",
        width = "auto", height = "auto", lmargin = 8, valign = "center",
    }

    local body = gui.Panel{
        width = CONTENT_W, height = "auto", flow = "vertical", vmargin = 2,
        classes = { cond(startOpen, nil, "collapsed") },
        create = function(element) element:FireEvent("refreshSection") end,
        refreshSection = function(element)
            element.children = buildChildren()
            if noteFn ~= nil and noteLabel.valid then
                noteLabel.text = noteFn()
            end
        end,
    }

    local caret = gui.Label{
        classes = {"label", "fgMuted", "sizeXs"},
        text = cond(startOpen, "v", ">"),
        width = 16, height = 20, valign = "center",
    }

    local header = gui.Panel{
        classes = {"bandClickable", "hoverable"},
        bgimage = true,
        width = CONTENT_W, height = 26, flow = "horizontal", vmargin = 4,
        hpad = 2, borderBox = true,
        click = function(element)
            local nowOpen = body:HasClass("collapsed")
            body:SetClass("collapsed", not nowOpen)
            caret.text = cond(nowOpen, "v", ">")
        end,
        caret,
        gui.Label{
            classes = {"label", "bold", "sizeM"},
            text = title, width = "auto", height = "auto", valign = "center",
        },
        noteLabel,
    }

    local panel = gui.Panel{
        width = CONTENT_W, height = "auto", flow = "vertical", halign = "left",
        header, body,
    }

    return panel, body
end

local function FormRow(labelText, control)
    return gui.Panel{
        classes = {"formRow"},
        width = CONTENT_W, height = "auto", flow = "horizontal", vmargin = 3,
        gui.Label{
            classes = {"label", "form"},
            text = labelText, height = 24, valign = "center", lmargin = 18,
        },
        control,
    }
end

local function Empty(text)
    return gui.Label{
        classes = {"label", "fgMuted", "sizeS"},
        text = text, width = "auto", height = 24, lmargin = 18, vmargin = 2,
    }
end

-- Click targets are a Panel wrapping a Label: the panel carries the surface
-- DMHub hit-tests against, the label carries the type styling.
local function AddLink(text, onClick)
    return gui.Panel{
        classes = {"bandClickable", "hoverable"},
        bgimage = true,
        width = "auto", height = 24, flow = "horizontal",
        lmargin = 18, vmargin = 4, halign = "left",
        click = onClick,
        gui.Label{
            classes = {"label", "link", "sizeS"},
            text = text, width = "auto", height = "auto", valign = "center",
        },
    }
end

-- Destructive actions use the house delete button so they get the "Confirm
-- Delete" modal from requireConfirm. Losing an authored lore section to a
-- stray click has no undo.
local function DeleteGlyph(onClick)
    return gui.Button{
        classes = {"deleteButton", "sizeXs"},
        halign = "right", valign = "center",
        requireConfirm = true,
        click = onClick,
    }
end

local function MoveGlyph(glyph, onClick)
    return gui.Panel{
        classes = {"bandClickable", "hoverable"},
        bgimage = true,
        width = 20, height = 24, flow = "horizontal",
        halign = "right", valign = "center",
        click = onClick,
        gui.Label{
            classes = {"label", "fgMuted", "sizeXs"},
            text = glyph, width = "auto", height = "auto",
            halign = "center", valign = "center",
        },
    }
end

-- A set-of-ids editor: current entries as removable chips, plus a searchable
-- picker for the rest. Used for both Keywords and Inherits.
--
-- gui.KeywordSelector is NOT reusable here: its option list is hardcoded to
-- GameSystem.abilityKeywords (Strike, Melee, Magic...) and it renders the raw
-- key as the label, so it can neither offer band names nor resolve an id to a
-- band's display name.
local function ChipPicker(set, options, addText, onChange)
    local chipsPanel, picker

    local function LabelFor(id)
        for _, o in ipairs(options) do
            if o.id == id then return o.text end
        end
        -- stale id (band deleted, keyword retired): show something rather than
        -- an empty chip, so it can be seen and removed
        return string.format("%s (unknown)", tostring(id))
    end

    chipsPanel = gui.Panel{
        width = FIELD_W, height = "auto", flow = "horizontal",
        create = function(element) element:FireEvent("refreshChips") end,
        refreshChips = function(element)
            local ids = {}
            for k, v in pairs(set) do
                if v == true then ids[#ids + 1] = k end
            end
            table.sort(ids, function(a, b) return LabelFor(a) < LabelFor(b) end)

            local chips = {}
            for _, id in ipairs(ids) do
                local thisId = id
                chips[#chips + 1] = gui.Panel{
                    classes = {"panel", "multiselectChip"},
                    width = "auto", height = 24, flow = "horizontal",
                    hmargin = 3, vmargin = 2,
                    gui.Label{
                        classes = {"label", "multiselectChipText"},
                        text = LabelFor(thisId), width = "auto", height = 22,
                        valign = "center",
                    },
                    gui.Panel{
                        classes = {"panel", "multiselectChipRemove"},
                        valign = "center", lmargin = 6,
                        click = function()
                            set[thisId] = nil
                            chipsPanel:FireEvent("refreshChips")
                            picker:FireEvent("refreshChips")
                            if onChange ~= nil then onChange() end
                        end,
                    },
                }
            end
            if #chips == 0 then
                chips[1] = gui.Label{
                    classes = {"label", "fgMuted", "sizeS"},
                    text = "None", width = "auto", height = 24, valign = "center",
                }
            end
            element.children = chips
        end,
    }

    picker = gui.Dropdown{
        classes = {"dropdown", "form"},
        vmargin = 4, halign = "left",
        sort = true, hasSearch = true,
        textDefault = addText,
        idChosen = "none",
        create = function(element) element:FireEvent("refreshChips") end,
        refreshChips = function(element)
            local opts = {}
            for _, o in ipairs(options) do
                if not set[o.id] then opts[#opts + 1] = o end
            end
            element.options = opts
            element:SetClass("collapsed", #opts == 0)
        end,
        change = function(element)
            local chosen = element.idChosen
            if chosen ~= nil and chosen ~= "none" then
                set[chosen] = true
                element.idChosen = "none"
                chipsPanel:FireEvent("refreshChips")
                element:FireEvent("refreshChips")
                if onChange ~= nil then onChange() end
            end
        end,
    }

    return gui.Panel{
        width = FIELD_W, height = "auto", flow = "vertical", halign = "left",
        chipsPanel, picker,
    }
end

-- ---------------------------------------------------------------- right pane

local function BandEditor(bandid)
    local t = dmhub.GetTable(MonsterGroup.tableName) or {}
    local g = t[bandid]
    if g == nil then return gui.Panel{ width = 10, height = 10 } end
    local m_dirty = false
    local function Invalidate() m_dirty = true end

    -- The engine's default characterLimit is 256. Imported lore sections run
    -- to 4212 characters, so an unset limit silently truncates a section the
    -- moment it is edited. Single-line fields get a generous cap too.
    local LIMIT_BODY = 16000
    local LIMIT_LINE = 1000

    local function Text(get, set, w, minH, placeholder)
        local multiline = (minH ~= nil and minH > 30)
        return gui.Input{
            classes = { "input", "form", "bordered", cond(multiline, "multiline", nil) },
            text = get() or "", placeholderText = placeholder or "",
            width = w, height = "auto", minHeight = minH or 24,
            multiline = multiline, vmargin = 2,
            characterLimit = cond(multiline, LIMIT_BODY, LIMIT_LINE),
            lineType = cond(multiline, "MultiLineNewLine", "SingleLine"),
            change = function(element) set(element.text) Invalidate() end,
        }
    end

    -- Lists are NOT attached to the record on open -- browsing a band should
    -- not dirty it. The list is attached by Commit, on the first actual edit.
    local function List(field)
        return g:try_get(field, nil) or {}
    end

    local function Commit(field, list)
        g[field] = list
        Upload(g)
    end

    local loreList  = List("loreSections")
    local langList  = List("languages")
    local encList   = List("sampleEncounters")
    local assocList = List("associatedCreatures")
    local maliceList = g:try_get("maliceAbilities", {})

    -- Section bodies, declared up front so each section's builders can fire a
    -- refresh at their own body without rebuilding the editor.
    local langBody, encBody, maliceBody, loreBody, assocBody, rosterBody

    -- ------------------------------------------------------------- identity
    local inheritSet = g:try_get("inherits", nil) or {}
    local inheritOptions = {}
    for k, v in unhidden_pairs(dmhub.GetTable(MonsterGroup.tableName) or {}) do
        if k ~= bandid and type(v.name) == "string" and v.name ~= "" then
            inheritOptions[#inheritOptions + 1] = { id = k, text = v.name }
        end
    end
    table.sort(inheritOptions, function(a, b) return a.text < b.text end)

    local kwSet = g:try_get("keywords", nil) or {}
    local kwOptions, kwSeen = {}, {}
    for _, v in unhidden_pairs(dmhub.GetTable(MonsterGroup.tableName) or {}) do
        local n = v.name
        if type(n) == "string" and n ~= "" and not kwSeen[n] then
            kwSeen[n] = true
            kwOptions[#kwOptions + 1] = { id = n, text = n }
        end
    end
    for k, _ in pairs(kwSet) do
        if not kwSeen[k] then
            kwSeen[k] = true
            kwOptions[#kwOptions + 1] = { id = k, text = k }
        end
    end
    table.sort(kwOptions, function(a, b) return a.text < b.text end)

    local function BuildIdentity()
        return {
            FormRow("Name", Text(function() return g.name end,
                function(v) g.name = v end, FIELD_W)),
            FormRow("Keywords", ChipPicker(kwSet, kwOptions,
                "Add Keyword...", function() Commit("keywords", kwSet) end)),
        }
    end

    -- ------------------------------------------------------------ languages
    local function BuildLanguages()
        local out = { FormRow("Note", Text(
            function() return g:try_get("languageNote", "") end,
            function(v) g.languageNote = v end, FIELD_W, 44,
            "The book's languages sentence, as printed")) }
        for i, l in ipairs(langList) do
            local idx = i
            --The stored qualifier, defaulted the same way the dropdown below
            --defaults it. Entries imported before qualifiers existed have none,
            --so the dropdown opens on "most" and fires change at construction;
            --without this guard that wrote "most" back and uploaded the band,
            --i.e. merely LOOKING at a band edited the library.
            local qualifier = l.qualifier or "most"
            out[#out + 1] = gui.Panel{
                width = CONTENT_W - 30, height = "auto", flow = "horizontal",
                lmargin = 18, vmargin = 2,
                gui.Dropdown{
                    classes = {"dropdown", "form"},
                    sort = true, hasSearch = true,
                    options = LanguageOptions(), idChosen = l.id,
                    change = function(element)
                        ---@cast element Dropdown
                        langList[idx].id = element.idChosen Upload(g)
                    end,
                },
                gui.Dropdown{
                    -- "form" as well as "dropdown": that pairing carries the
                    -- vmargin and valign the language dropdown beside it gets,
                    -- and without them this one rides 4px higher than its row.
                    -- Width is the only thing worth overriding.
                    classes = {"dropdown", "form"},
                    width = 150, lmargin = 8,
                    options = MonsterGroup.languageQualifiers,
                    idChosen = qualifier,
                    change = function(element)
                        ---@cast element Dropdown
                        if element.idChosen == qualifier then return end
                        langList[idx].qualifier = element.idChosen Upload(g)
                    end,
                },
                DeleteGlyph(function()
                    table.remove(langList, idx)
                    Commit("languages", langList) langBody:FireEvent("refreshSection")
                end),
            }
        end
        if #langList == 0 then out[#out + 1] = Empty("No languages listed.") end
        out[#out + 1] = AddLink("+ Add Language", function()
            local opts = LanguageOptions()
            langList[#langList + 1] = { id = opts[1] and opts[1].id or "", qualifier = "most" }
            Commit("languages", langList) langBody:FireEvent("refreshSection")
        end)
        return out
    end

    -- -------------------------------------------------------------- tactics
    local function BuildTactics()
        return { FormRow("Tactics", Text(
            function() return g:try_get("tactics", "") end,
            function(v) g.tactics = v end, FIELD_W, 54,
            "How this band fights (only a few bands have this)")) }
    end

    -- ---------------------------------------------------- sample encounters
    local function BuildEncounters()
        local out = {}
        for i, e in ipairs(encList) do
            local idx = i
            out[#out + 1] = gui.Panel{
                width = CONTENT_W - 30, height = "auto", flow = "horizontal",
                lmargin = 18, vmargin = 2,
                Text(function() return e.name end,
                    function(v) encList[idx].name = v end, 180, nil, "Name"),
                gui.Input{
                    classes = {"input", "form", "bordered"},
                    text = tostring(e.ev or 0), width = 60, height = 24,
                    lmargin = 6, placeholderText = "EV",
                    change = function(element)
                        encList[idx].ev = tonumber(element.text) or 0 Upload(g)
                    end,
                },
                Text(function() return e.composition end,
                    function(v) encList[idx].composition = v end, 300, nil, "Composition"),
                DeleteGlyph(function()
                    table.remove(encList, idx)
                    Commit("sampleEncounters", encList) encBody:FireEvent("refreshSection")
                end),
            }
        end
        if #encList == 0 then
            out[#out + 1] = Empty("No sample encounters. Only 6 bands in the book have them.")
        end
        out[#out + 1] = AddLink("+ Add Encounter", function()
            encList[#encList + 1] = { name = "New Encounter", ev = 0, composition = "" }
            Commit("sampleEncounters", encList) encBody:FireEvent("refreshSection")
        end)
        return out
    end

    -- --------------------------------------------------------------- malice
    local function ClipboardHasMaliceAbility()
        local c = dmhub.GetInternalClipboard()
        return c ~= nil and (c.typeName == "MaliceAbility" or c.typeName == "ActivatedAbility")
    end

    local function BuildMalice()
        local out = {}
        for i, a in ipairs(maliceList) do
            local idx = i
            local ability = a
            out[#out + 1] = gui.Panel{
                classes = { "panel", cond(i % 2 == 0, "bgAlt", "transparent") },
                bgimage = true,
                width = CONTENT_W - 30, height = "auto", flow = "vertical",
                lmargin = 18, vmargin = 2, pad = 5, borderBox = true,

                rightClick = function(element)
                    element.popup = gui.ContextMenu{
                        entries = {
                            {
                                text = "Copy",
                                click = function()
                                    element.popup = nil
                                    dmhub.CopyToInternalClipboard(ability)
                                end,
                            },
                        },
                    }
                end,

                gui.Panel{
                    width = "100%", height = "auto", flow = "horizontal",
                    gui.Label{
                        classes = {"label", "bold", "sizeS"},
                        text = ability.name, width = 230, height = 24, valign = "center",
                    },
                    gui.Label{
                        classes = {"label", "accent", "sizeS"},
                        text = string.format("%s Malice",
                            tostring(ability:try_get("resourceNumber", "?"))),
                        width = 96, height = 24, valign = "center",
                    },
                    gui.Dropdown{
                        classes = {"dropdown"},
                        width = 70, height = 28, valign = "center",
                        idChosen = tostring(ability:try_get("minLevel", 1)),
                        options = (function()
                            local o = {}
                            for lvl = 1, 10 do o[#o + 1] = { id = tostring(lvl), text = tostring(lvl) } end
                            return o
                        end)(),
                        change = function(element)
                            ---@cast element Dropdown
                            ability.minLevel = tonumber(element.idChosen) Upload(g)
                        end,
                    },
                    gui.Button{
                        classes = { "settingsButton", "sizeXs" },
                        halign = "right", valign = "center",
                        press = function(element)
                            element.root:AddChild(ability:ShowEditActivatedAbilityDialog{
                                close = function()
                                    Upload(g) maliceBody:FireEvent("refreshSection")
                                end,
                            })
                        end,
                    },
                    gui.Button{
                        classes = { "deleteButton", "sizeXs" },
                        halign = "right", valign = "center", hpad = 5,
                        requireConfirm = true,
                        click = function(element)
                            table.remove(maliceList, idx)
                            Upload(g) maliceBody:FireEvent("refreshSection")
                        end,
                    },
                },

                -- What the ability actually does. Without this the row is just
                -- a name and a cost, and reading malice means opening a dialog.
                gui.DocumentDisplay{
                    width = "100%", height = "auto", fontSize = 16,
                    text = ability.description,
                },
            }
        end
        if #maliceList == 0 then out[#out + 1] = Empty("No malice abilities.") end
        -- Inherits sits with the authoring controls at the foot of the section
        -- rather than at its head: it is something you set while building a
        -- band's malice, not the first thing to read about it.
        out[#out + 1] = FormRow("Inherits", ChipPicker(inheritSet, inheritOptions,
            "Inherits from Band...", function() Commit("inherits", inheritSet) end))
        out[#out + 1] = AddLink("+ Add Malice Ability", function()
            maliceList[#maliceList + 1] = MaliceAbility.Create{ name = "New Malice Ability" }
            Commit("maliceAbilities", maliceList)
            maliceBody:FireEvent("refreshSection")
        end)
        out[#out + 1] = gui.Button{
            classes = {"sizeM"},
            halign = "left", valign = "bottom",
            width = "auto", minWidth = 120, height = 35,
            lmargin = 18, hpad = 16, borderBox = true,
            text = "Paste Ability",
            create = function(element)
                element:SetClass("collapsed", not ClipboardHasMaliceAbility())
            end,
            internalClipboardChanged = function(element)
                element:SetClass("collapsed", not ClipboardHasMaliceAbility())
            end,
            click = function(element)
                if not ClipboardHasMaliceAbility() then return end
                local pasted = MaliceAbility.Create(DeepCopy(dmhub.GetInternalClipboard()))
                pasted.guid = dmhub.GenerateGuid()
                maliceList[#maliceList + 1] = pasted
                Commit("maliceAbilities", maliceList)
                maliceBody:FireEvent("refreshSection")
            end,
        }
        return out
    end

    -- ----------------------------------------------------------------- lore
    local function BuildLore()
        local out = {}
        for i, s in ipairs(loreList) do
            local idx = i
            out[#out + 1] = gui.Panel{
                classes = {"featureCard"},
                width = CONTENT_W - 30, height = "auto", flow = "vertical",
                lmargin = 18, vmargin = 4, pad = 8, borderBox = true,
                gui.Panel{
                    width = CONTENT_W - 50, height = "auto", flow = "horizontal",
                    Text(function() return s.heading end,
                        function(v) loreList[idx].heading = v end,
                        FIELD_W - 90, nil, "Heading"),
                    MoveGlyph("^", function()
                        if idx > 1 then
                            loreList[idx], loreList[idx-1] = loreList[idx-1], loreList[idx]
                            Commit("loreSections", loreList) loreBody:FireEvent("refreshSection")
                        end
                    end),
                    MoveGlyph("v", function()
                        if idx < #loreList then
                            loreList[idx], loreList[idx+1] = loreList[idx+1], loreList[idx]
                            Commit("loreSections", loreList) loreBody:FireEvent("refreshSection")
                        end
                    end),
                    DeleteGlyph(function()
                        table.remove(loreList, idx)
                        Commit("loreSections", loreList) loreBody:FireEvent("refreshSection")
                    end),
                },
                Text(function() return s.text end,
                    function(v) loreList[idx].text = v end, CONTENT_W - 66, 54, "Body"),
            }
        end
        if #loreList == 0 then out[#out + 1] = Empty("No lore sections yet.") end
        out[#out + 1] = AddLink("+ Add Section", function()
            loreList[#loreList + 1] = { heading = "New Section", text = "" }
            Commit("loreSections", loreList) loreBody:FireEvent("refreshSection")
        end)
        return out
    end

    -- --------------------------------------------------------------- roster
    local members = RosterFor(bandid)
    local function BuildRoster()
        local out = {}

        for _, m in ipairs(members) do
            out[#out + 1] = gui.Panel{
                width = CONTENT_W - 30, height = 24, flow = "horizontal", lmargin = 18,
                gui.Label{
                    classes = {"label", "sizeS"},
                    text = m.name, width = 220, height = 22, valign = "center",
                },
                gui.Label{
                    classes = {"label", "fgMuted", "sizeXs"},
                    text = string.format("L%d %s", m.level, tostring(m.role)),
                    width = 150, height = 22, valign = "center",
                },
                gui.Label{
                    classes = {"label", "fgMuted", "sizeXs"},
                    text = string.format("EV %s", tostring(m.ev)),
                    width = 60, height = 22, valign = "center",
                },
            }
        end
        if #members == 0 then
            out[#out + 1] = Empty("No monsters belong to this band.")
        end
        return out
    end

    -- -------------------------------------------------- associated creatures
    local function BuildAssoc()
        local out = {}
        for i, s in ipairs(assocList) do
            local idx = i
            out[#out + 1] = gui.Panel{
                classes = {"featureCard"},
                width = CONTENT_W - 30, height = "auto", flow = "vertical",
                lmargin = 18, vmargin = 3, pad = 8, borderBox = true,
                gui.Panel{
                    width = CONTENT_W - 50, height = "auto", flow = "horizontal",
                    Text(function() return s.heading end,
                        function(v) assocList[idx].heading = v end, 260, nil, "Creature"),
                    DeleteGlyph(function()
                        table.remove(assocList, idx)
                        Commit("associatedCreatures", assocList) assocBody:FireEvent("refreshSection")
                    end),
                },
                Text(function() return s.text end,
                    function(v) assocList[idx].text = v end, CONTENT_W - 66, 44, "Note"),
            }
        end
        if #assocList == 0 then out[#out + 1] = Empty("No associated creatures.") end
        out[#out + 1] = AddLink("+ Add Creature", function()
            assocList[#assocList + 1] = { heading = "New Creature", text = "" }
            Commit("associatedCreatures", assocList) assocBody:FireEvent("refreshSection")
        end)
        return out
    end

    -- ------------------------------------------------------------- assemble
    local identitySection = Section("Identity", nil, BuildIdentity, true)
    local langSection, encSection, maliceSection, loreSection, assocSection
    langSection,   langBody   = Section("Languages",
        function() return Count(#langList, "language", "languages") end, BuildLanguages, true)
    local tacticsSection = Section("Tactics",
        function() return cond(g:try_get("tactics", "") == "", "empty", "written") end,
        BuildTactics, false)
    encSection,    encBody    = Section("Sample Encounters",
        function() return Count(#encList, "encounter", "encounters") end, BuildEncounters, false)
    maliceSection, maliceBody = Section("Malice",
        function() return Count(#maliceList, "ability", "abilities") end, BuildMalice, true)
    loreSection,   loreBody   = Section("Lore",
        function() return Count(#loreList, "section", "sections") end, BuildLore, true)
    local rosterSection
    rosterSection, rosterBody = Section("Roster",
        function() return Count(#members, "monster", "monsters") end, BuildRoster, true)
    assocSection,  assocBody  = Section("Associated Creatures",
        function() return Count(#assocList, "creature", "creatures") end, BuildAssoc, false)

    return gui.Panel{
        width = "100%", height = "100%", flow = "vertical", vscroll = true,
        hpad = 14, borderBox = true, halign = "left",

        destroy = function()
            if m_dirty then Upload(g) m_dirty = false end
        end,

        gui.Label{
            classes = {"label", "bold", "sizeXl"},
            text = g.name, width = "auto", height = 36, vmargin = 6,
        },
        gui.Label{
            classes = { "label", "fgMuted", "sizeS",
                cond(MonsterGroup.DefaultMaliceGroupId() == bandid, nil, "collapsed") },
            text = "Default malice group -- these abilities apply to every monster whose band does not inherit them.",
            width = CONTENT_W, height = "auto", vmargin = 2, halign = "left",
        },
        gui.Panel{
            classes = {"bandDivider"},
            width = CONTENT_W, height = 1, vmargin = 2, halign = "left",
        },

        identitySection,
        langSection,
        maliceSection,
        tacticsSection,
        encSection,
        loreSection,
        rosterSection,
        assocSection,

        gui.Panel{ width = CONTENT_W, height = 40 },
    }
end

ShowMonsterBands = function(contentPanel)
    -- ----------------------------------------------------------------- left pane

    local rightPane, listPanel
    local m_filter = ""
    local m_dataItems = {}

    local function ShowBand(bandid)
        rightPane.children = { BandEditor(bandid) }
    end

    -- Compendium.CreateListItem brings the house behaviour with it: right-click
    -- Duplicate / Delete, soft-delete handling (hidden rows collapse unless the
    -- showdeleted setting is on), the compendium's global search integration, and
    -- the imported/modified badges. monitorAssets keeps the list live, so a band
    -- added or deleted anywhere shows up here without reopening the page.
    listPanel = gui.Panel{
        id = "bandsListPanel",
        classes = {"list-panel"},
        width = LIST_INNER, height = "100%-70", flow = "vertical", vscroll = true,
        halign = "left",
        monitorAssets = true,
        refreshAssets = function(element)
            local t = dmhub.GetTable(MonsterGroup.tableName) or {}
            local counts = MemberCounts()
            local newDataItems = {}
            local children = {}

            for k, item in unhidden_pairs(t) do
                if ListedHere(k, item) then
                    local name = item.name or ""
                    if m_filter == "" or string.find(string.lower(name), m_filter, 1, true) ~= nil then
                        local key = k
                        newDataItems[k] = m_dataItems[k] or Compendium.CreateListItem{
                            tableName = MonsterGroup.tableName,
                            key = k,
                            select = element.aliveTime > 0.2,
                            click = function() ShowBand(key) end,
                        }
                        if IsDefaultMaliceGroup(k) then
                            newDataItems[k].text = string.format("%s  (default malice)", name)
                        else
                            newDataItems[k].text = string.format("%s  (%d)", name, counts[k] or 0)
                        end
                        children[#children + 1] = newDataItems[k]
                    end
                end
            end

            table.sort(children, function(a, b) return a.text < b.text end)
            m_dataItems = newDataItems
            element.children = children
        end,
    }

    listPanel:FireEvent("refreshAssets")

    local leftPane = gui.Panel{
        id = "bandsLeftPane",
        classes = {"panel", "bgAlt", "bordered"},
        bgimage = true,
        width = LIST_W, height = "100%", flow = "vertical",
        pad = 6, borderBox = true,

        gui.Input{
            classes = {"input", "bordered"},
            text = "", placeholderText = "Search bands...",
            width = SEARCH_W, height = 26, vmargin = 4, halign = "left",
            change = function(element)
                m_filter = string.lower(element.text)
                listPanel:FireEvent("refreshAssets")
            end,
        },
        listPanel,
        Compendium.AddButton{
            click = function(element)
                dmhub.SetAndUploadTableItem(MonsterGroup.tableName,
                    MonsterGroup.CreateNew{ name = "New Band" })
            end,
        },
    }

    -- 230 left pane + 16 root padding (borderBox percentages resolve against the
    -- outer box, not the content box) + 6 gutter.
    rightPane = gui.Panel{
        width = "100%-252", height = "100%", flow = "vertical", halign = "right",
    }

    local root = gui.Panel{
        classes = {"panel"},
        styles = Styles(),
        bgimage = true,
        width = "100%", height = "100%", flow = "horizontal",
        pad = 8, borderBox = true,
        create = function(element)
            local t = dmhub.GetTable(MonsterGroup.tableName) or {}
            local first = nil
            for k, v in unhidden_pairs(t) do
                if v:IsBand() then
                    if v.name == "Goblin" then first = k break end
                    if first == nil then first = k end
                end
            end
            if first ~= nil then ShowBand(first) end
        end,
        leftPane,
        rightPane,
    }

    contentPanel.children = { root }
end
