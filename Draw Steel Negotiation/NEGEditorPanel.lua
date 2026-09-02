local mod = dmhub.GetModLoading()

--- The configuration surface for the selected negotiation.
NEGEditorPanel = RegisterGameType("NEGEditorPanel")

--- One motivation or pitfall: which of the twelve, and what it means here.
--- @param defid string
--- @param kind string "motivations" or "pitfalls"
--- @param row NEGTrait
--- @param used table<string, boolean>
--- @return Panel
local function TraitCard(defid, kind, row, used)
    local rowId = row.id
    local traitId = row:try_get("trait", "")

    --No "border" class and no border: that class turns the card into a painted
    --surface, which is where the fill behind the dropdown row and the stray
    --corner mark were both coming from. Cards separate on margin alone.
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        vmargin = 6,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "top",

            gui.Dropdown{
                classes = { "formStacked", "sizeXs" },
                width = "100%-34",
                height = 24,
                halign = "left",
                valign = "center",
                options = NEGRules.TraitOptions(used, traitId),
                idChosen = traitId,
                change = function(element)
                    NEGDefinition.SetTraitField(defid, kind, rowId, "trait", element.idChosen)
                end,
            },

            gui.Button{
                classes = { "deleteButton", "sizeXs" },
                halign = "right",
                valign = "center",
                hover = gui.Tooltip("Remove this one"),
                click = function()
                    NEGDefinition.RemoveTrait(defid, kind, rowId)
                end,
            },
        },

        --Same width as the dropdown above it, so the pair reads as one field
        --rather than two that nearly line up.
        gui.Input{
            classes = { "formStacked", "sizeXs" },
            width = "100%-34",
            height = NEGConstants.multilineHeight,
            halign = "left",
            multiline = true,
            textAlignment = "topLeft",
            characterLimit = NEGConstants.noteLimit,
            placeholderText = "What this means to this NPC.",
            text = row:try_get("note", ""),
            change = function(element)
                NEGDefinition.SetTraitField(defid, kind, rowId, "note", element.text)
            end,
        },
    }
end

--- One side of the traits section. The catalog is shared, so the add button
--- goes quiet once all twelve are spoken for.
--- @param defid string
--- @param def NEGDefinition
--- @param kind string
--- @param title string
--- @param expected number how many the rules ask for
--- @return Panel
local function TraitColumn(defid, def, kind, title, expected)
    local rows = def:try_get(kind, {})
    local used = def:UsedTraits()

    local remaining = 0
    for _, trait in ipairs(NEGRules.traits) do
        if used[trait.id] ~= true then
            remaining = remaining + 1
        end
    end

    local shortfall = #rows < expected

    local children = {
        --Add sits ahead of the name rather than out at the column's right
        --edge, where it reads as belonging to the row beneath it.
        gui.Panel{
            width = "100%",
            height = 26,
            flow = "horizontal",
            halign = "left",
            valign = "top",

            gui.Button{
                classes = { "addButton", "sizeXs" },
                halign = "left",
                valign = "center",
                interactable = remaining > 0,
                hover = gui.Tooltip(cond(remaining > 0,
                    string.format("Add one (%d left)", remaining),
                    "All twelve are spoken for")),
                click = function()
                    NEGDefinition.AddTrait(defid, kind)
                end,
            },

            gui.Label{
                classes = { "tableLabel", "sizeXs" },
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                lmargin = 6,
                text = title,
            },

            gui.Panel{
                classes = { cond(shortfall, "bgFgMuted", "bgSuccess") },
                width = 14,
                height = 14,
                halign = "left",
                valign = "center",
                lmargin = 6,
                bgimage = NEGConstants.iconConfigured,
                hover = gui.Tooltip(string.format(
                    "The rules ask for at least %d. This NPC has %d.", expected, #rows)),
            },
        },
    }

    for _, row in ipairs(rows) do
        children[#children + 1] = TraitCard(defid, kind, row, used)
    end

    if #rows == 0 then
        children[#children + 1] = gui.Label{
            classes = { "sizeXs", "noBold", "fgMuted" },
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            vmargin = 8,
            textAlignment = "left",
            text = "None yet.",
        }
    end

    return gui.Panel{
        width = NEGConstants.traitColumnWidth,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        rmargin = NEGConstants.traitColumnGap,
        children = children,
    }
end

--- The authoring surface. Controls a Director types into are built once and
--- refilled; only the parts whose shape changes get rebuilt, so a document
--- change never destroys the field under the cursor.
--- @return Panel
function NEGEditorPanel.Create()
    local m_defid = nil

    local nameInput = gui.Input{
        classes = { "formStacked", "sizeS" },
        characterLimit = NEGConstants.nameLimit,
        change = function(element)
            if m_defid == nil then
                return
            end
            local newName = trim(element.text or "")
            local current = NEGDefinition.GetByID(m_defid)
            if current == nil then
                return
            end
            if newName == "" then
                element.text = current.name or ""
                return
            end
            NEGDefinition.SetField(m_defid, "name", newName)
        end,
    }

    local npcInput = gui.Input{
        classes = { "formStacked", "sizeS" },
        characterLimit = NEGConstants.nameLimit,
        placeholderText = "Who the heroes are facing",
        change = function(element)
            if m_defid ~= nil then
                NEGDefinition.SetField(m_defid, "npcName", trim(element.text or ""))
            end
        end,
    }

    local languageDropdown = gui.Dropdown{
        classes = { "formStacked", "sizeS" },
        width = "100%",
        height = 26,
        change = function(element)
            if m_defid ~= nil then
                NEGDefinition.SetField(m_defid, "languageId", element.idChosen)
            end
        end,
    }

    local attitudeDropdown = gui.Dropdown{
        classes = { "formStacked", "sizeS" },
        width = "100%",
        height = 26,
        options = NEGRules.AttitudeOptions(),
        change = function(element)
            if m_defid ~= nil then
                NEGDefinition.ApplyAttitude(m_defid, element.idChosen)
            end
        end,
    }

    --A dropdown rather than a number: the score only means anything next to
    --the sort of NPC it describes, and carrying that inline beats a tooltip
    --the size of the rulebook table.
    local impressionDropdown = gui.Dropdown{
        classes = { "formStacked", "sizeS" },
        width = "100%",
        height = 26,
        options = NEGRules.ImpressionOptions(),
        change = function(element)
            if m_defid ~= nil then
                NEGDefinition.SetField(m_defid, "impression",
                    tonumber(element.idChosen) or NEGConstants.impressionDefault)
            end
        end,
    }

    --Same control the Class and Ancestry editors use for their artwork. The
    --portraitImage class carries the 196-wide, 3:2-tall frame.
    --portraitImage gives the frame and the 2:3 proportion; the size is ours,
    --because the class ships the 196-wide plate the Ancestry editor wants and
    --this is a thumbnail beside a form.
    local portraitEditor = gui.IconEditor{
        classes = { "portraitImage" },
        library = "Avatar",
        autosizeimage = true,
        allowPaste = true,
        width = NEGConstants.portraitWidth,
        height = NEGConstants.portraitHeight,
        halign = "center",
        valign = "top",
        change = function(element)
            if m_defid ~= nil then
                NEGDefinition.SetField(m_defid, "portraitid", element.value)
            end
        end,
    }

    local portraitColumn = gui.Panel{
        width = NEGConstants.portraitColumnWidth,
        height = "auto",
        flow = "vertical",
        halign = "right",
        valign = "top",

        portraitEditor,

        gui.Label{
            classes = { "sizeXxs", "fgMuted" },
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "top",
            tmargin = 2,
            text = "1000x1500 image",
        },
    }

    local summaryInput = gui.Input{
        classes = { "formStacked", "sizeS" },
        width = "100%",
        height = NEGConstants.multilineHeight,
        multiline = true,
        textAlignment = "topLeft",
        characterLimit = NEGConstants.summaryLimit,
        placeholderText = "What the heroes want, and why the NPC is torn. Markdown is welcome.",
        change = function(element)
            if m_defid ~= nil then
                NEGDefinition.SetField(m_defid, "summary", element.text)
            end
        end,
    }

    local scalesPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        tmargin = 8,
    }

    local traitsBody = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        halign = "left",
        valign = "top",
    }

    --One input per interest score, built once and refilled. The row is labelled
    --by the score's own glyph and the answer it buys.
    local offerInputs = {}
    local offerRows = {}
    for interest = NEGConstants.scaleMin, NEGConstants.scaleMax do
        --Short of the panel edge, so the pane's scroll bar rides beside the
        --field instead of over it.
        local input = gui.Input{
            classes = { "formStacked", "sizeXs" },
            width = "96%",
            height = NEGConstants.multilineHeight,
            halign = "left",
            multiline = true,
            textAlignment = "topLeft",
            characterLimit = NEGConstants.offerLimit,
            placeholderText = NEGRules.OfferDetail(interest),
            change = function(element)
                if m_defid ~= nil then
                    NEGDefinition.SetOffer(m_defid, interest, element.text)
                end
            end,
        }
        offerInputs[interest] = input

        --Fixed height, not "auto". Six rows each sizing themselves came out
        --unequal - three of them roughly twice the others - so the ladder read
        --as randomly spaced. Nothing here is allowed to size itself.
        offerRows[#offerRows + 1] = gui.Panel{
            width = "100%",
            height = NEGConstants.offerRowHeight,
            flow = "horizontal",
            halign = "left",
            valign = "top",
            vmargin = 1,

            gui.Panel{
                width = NEGConstants.offerLabelWidth,
                height = "100%",
                flow = "horizontal",
                halign = "left",
                valign = "top",

                --Same colour this number wears on the Interest scale, so the
                --offer ladder and the scale read as one vocabulary.
                gui.Panel{
                    classes = {
                        NEGConstants.interestTone[interest] or NEGConstants.toneUnlit,
                    },
                    width = 18,
                    height = 18,
                    halign = "left",
                    valign = "top",
                    rmargin = 6,
                    bgimage = NEGConstants.scalePips[interest],
                },

                gui.Label{
                    classes = { "sizeXs", "noBold" },
                    width = "100% available",
                    height = "auto",
                    halign = "left",
                    valign = "top",
                    text = NEGRules.OfferName(interest),
                },
            },

            gui.Panel{
                width = "100% available",
                height = "100%",
                flow = "vertical",
                halign = "left",
                valign = "top",

                input,
            },
        }
    end

    local traitsBodyWrapper = gui.Panel{
        width = NEGConstants.sectionWidth,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        children = { traitsBody },
    }

    local offersBody = gui.Panel{
        width = NEGConstants.sectionWidth,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        children = offerRows,
    }

    local traitsHeader = NEGWidgets.SectionHeader{ text = "Motivations & Pitfalls" }
    local offersHeader = NEGWidgets.SectionHeader{ text = "Offers" }

    local formPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",

        --Fields on the left, the NPC's picture beside them. The scales sit in
        --this block too, so the column stands about as tall as the portrait
        --rather than leaving a well of empty space under it.
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "top",

            gui.Panel{
                width = "100%-146",
                height = "auto",
                flow = "vertical",
                halign = "left",
                valign = "top",

                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    halign = "left",
                    valign = "top",

                    NEGWidgets.FormRow("Name", "48%", nameInput),
                    NEGWidgets.FormRow("NPC", "48%", npcInput),
                },

                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    halign = "left",
                    valign = "top",

                    NEGWidgets.FormRow("Native Language", "31%", languageDropdown),
                    NEGWidgets.FormRow("Starting Attitude", "31%", attitudeDropdown),
                    NEGWidgets.FormRow("Impression", "34%", impressionDropdown),
                },

                NEGWidgets.FormRow("Summary", "97%", summaryInput),
            },

            portraitColumn,
        },

        scalesPanel,

        traitsHeader,
        traitsBodyWrapper,

        offersHeader,
        offersBody,
    }

    local emptyLabel = gui.Label{
        classes = { "sizeS", "fgMuted" },
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        text = "Select a negotiation on the left, or add one.",
    }

    local resultPanel
    resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        valign = "top",
        vscroll = true,

        monitorGame = NEGDefinition.DocPath(),
        refreshGame = function(element)
            element:FireEvent("rebuild")
        end,

        setDefinition = function(element, defid)
            m_defid = defid
            element:FireEvent("rebuild")
        end,

        rebuild = function()
            local def = m_defid ~= nil and NEGDefinition.GetByID(m_defid) or nil

            formPanel:SetClass("collapsed", def == nil)
            emptyLabel:SetClass("collapsed", def ~= nil)

            if def == nil then
                return
            end

            local defid = m_defid

            nameInput.text = def.name or ""
            npcInput.text = def:try_get("npcName", "")
            summaryInput.text = def:try_get("summary", "")
            portraitEditor.value = def:try_get("portraitid", "")
            impressionDropdown.idChosen = tostring(def:try_get("impression",
                NEGConstants.impressionDefault))

            --Rebuilt every time rather than cached: the universal languages
            --are derived from a global rule that can change under us.
            languageDropdown.options = NEGRules.LanguageOptions()
            languageDropdown.idChosen = def:try_get("languageId", "")
            attitudeDropdown.idChosen = def:try_get("attitudeId", NEGDefinition.attitudeId)

            local interest = def:try_get("interest", NEGDefinition.interest)
            local patience = def:try_get("patience", NEGDefinition.patience)
            local langid = def:try_get("languageId", "")
            local interestCaption, interestClass = NEGWidgets.InterestCaption(interest)

            scalesPanel.children = {
                NEGWidgets.Scale{
                    which = NEGConstants.scaleInterest,
                    label = "Interest",
                    value = interest,
                    minValue = NEGConstants.startInterestMin,
                    maxValue = NEGConstants.startInterestMax,
                    interactive = true,
                    caption = interestCaption,
                    captionClass = interestClass,
                    change = function(value)
                        NEGDefinition.SetField(defid, "interest", value)
                    end,
                    eye = {
                        shown = def:try_get("showInterest", false),
                        change = function(shown)
                            NEGDefinition.SetField(defid, "showInterest", shown)
                        end,
                    },
                },

                NEGWidgets.Scale{
                    which = NEGConstants.scalePatience,
                    label = "Patience",
                    value = patience,
                    minValue = NEGConstants.startPatienceMin,
                    maxValue = NEGConstants.startPatienceMax,
                    interactive = true,
                    caption = NEGWidgets.PatienceCaption(patience, langid),
                    change = function(value)
                        NEGDefinition.SetField(defid, "patience", value)
                    end,
                    eye = {
                        shown = def:try_get("showPatience", false),
                        change = function(shown)
                            NEGDefinition.SetField(defid, "showPatience", shown)
                        end,
                    },
                },
            }

            traitsBody.children = {
                TraitColumn(defid, def, "motivations", "Motivations",
                    NEGConstants.motivationsExpected),
                TraitColumn(defid, def, "pitfalls", "Pitfalls",
                    NEGConstants.pitfallsExpected),
            }

            for interestValue = NEGConstants.scaleMin, NEGConstants.scaleMax do
                offerInputs[interestValue].text = def:GetOffer(interestValue)
            end
        end,

        create = function(element)
            element:FireEvent("rebuild")
        end,

        formPanel,
        emptyLabel,
    }

    return resultPanel
end
