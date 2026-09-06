local mod = dmhub.GetModLoading()

--Map Markup: the wall type dialog and the map-pack sharing dialog.
local MM = MapMarkupImpl
local K, m, gs = MM.K, MM.m, MM.gs

--============================================================================
--Edit dialog for markup walls: the gameplay fields only, none of the art
--fields that are meaningless on an invisible wall.
--============================================================================

--owner (optional) = the element the edit was invoked from; when it lives in
--a popped-out Map Markup window the dialog shows inside that OS window
--(gui.ShowModal owner routing). The dialog closes via the captured layer so
--a palette rebuild destroying the owner cannot strand it open.
local function ShowMarkupWallDialog(wallid, owner)
    local asset = assets.walls[wallid]
    if asset == nil then
        return
    end

    local modalLayer = nil

    local originalValues = {
        description = asset.description,
        blocksMovement = asset.blocksMovement,
        blocksForcedMovement = asset.blocksForcedMovement,
        occludesVision = asset.occludesVision,
        occludesLight = asset.occludesLight,
        visionOneWay = asset.visionOneWay,
        cover = asset.cover,
        soundOcclusion = asset.soundOcclusion,
        climbable = asset.climbable,
        solidity = asset.solidity,
        breakStamina = asset.breakStamina,
        rubbleKeyword = asset.rubbleKeyword,
        rubbleTerrainId = asset.rubbleTerrainId,
    }

    --pcall + engine gate, like the openable fields below: pre-scoping engine
    --builds have no markupMapId to capture or restore.
    if m.mapScope.WallSupported() then
        pcall(function()
            originalValues.markupMapId = asset.markupMapId
        end)
    end

    local RevertChanges = function()
        asset.description = originalValues.description
        asset.blocksMovement = originalValues.blocksMovement
        asset.blocksForcedMovement = originalValues.blocksForcedMovement
        asset.occludesVision = originalValues.occludesVision
        asset.occludesLight = originalValues.occludesLight
        asset.visionOneWay = originalValues.visionOneWay
        asset.cover = originalValues.cover
        asset.soundOcclusion = originalValues.soundOcclusion
        asset.climbable = originalValues.climbable
        asset.solidity = originalValues.solidity
        asset.breakStamina = originalValues.breakStamina
        asset.rubbleKeyword = originalValues.rubbleKeyword
        asset.rubbleTerrainId = originalValues.rubbleTerrainId
        if originalValues.openable ~= nil then
            pcall(function()
                asset.openable = originalValues.openable
                asset.openSound = originalValues.openSound
                asset.closeSound = originalValues.closeSound
            end)
        end
        if originalValues.markupMapId ~= nil then
            pcall(function()
                asset.markupMapId = originalValues.markupMapId
            end)
        end
    end

    --Breakability working state. The material is derived from the stamina on
    --open (see BreakMaterialForStamina) and both live here until Save, so
    --Cancel reverts cleanly like every other field in this dialog.
    local breakable = MM.AssetIsBreakable(asset)
    local breakStamina = asset.breakStamina or 0
    if breakable and breakStamina <= 0 then
        breakStamina = K.DEFAULT_BREAK_STAMINA
    end
    local breakMaterialId = MM.BreakMaterialForStamina(breakStamina)

    --Openable (door) state lives on the WALL ASSET (WallAsset.openable, plus
    --the open/close sounds SetAssetOpenable stamps). Applied live like every
    --other field: Save uploads, Cancel reverts. Needs the engine build - the
    --checkbox only shows when the asset supports the field.
    local canBeOpenable = MM.OpenableWallsSupported()
    local openable = MM.AssetIsOpenable(asset)
    if canBeOpenable then
        originalValues.openable = openable
        pcall(function()
            originalValues.openSound = asset.openSound
            originalValues.closeSound = asset.closeSound
        end)
    end

    --Pushes the working break state onto the asset. Called on every change so
    --the live asset always matches the controls; Save uploads, Cancel reverts.
    local ApplyBreakToAsset = function()
        MM.SetAssetBreakable(asset, breakable, breakStamina)
    end

    --Shared ("global") walls fork on save rather than being edited in place:
    --a wall other maps can also use must not change under them. Save creates
    --a copy carrying the edits, private to this map, and retypes every wall
    --drawn with the original on this map to the copy (palette chips follow).
    --"Save Changes to This Wall for All Maps" is the explicit opt-in to edit
    --the shared wall in place - and once the wall has been RENAMED it swaps
    --to "Make Available to All Maps", because a renamed wall is a different
    --wall: the fork then uploads game-wide instead of map-private, leaving
    --the original untouched either way. Requires the scoping engine build:
    --on a stale build every wall reads as unscoped, so forking is disabled
    --and the dialog saves in place exactly as before.
    local isGlobalWall = m.mapScope.WallSupported() and m.mapScope.WallMapId(asset) == nil

    local IsRenamed = function()
        return (asset.description or "") ~= (originalValues.description or "")
    end

    --any difference from the state the dialog opened with, so a Save on an
    --untouched shared wall does not fork pointlessly.
    local IsEdited = function()
        if IsRenamed()
            or asset.blocksMovement ~= originalValues.blocksMovement
            or asset.blocksForcedMovement ~= originalValues.blocksForcedMovement
            or asset.occludesVision ~= originalValues.occludesVision
            or asset.occludesLight ~= originalValues.occludesLight
            or asset.visionOneWay ~= originalValues.visionOneWay
            or asset.cover ~= originalValues.cover
            or asset.soundOcclusion ~= originalValues.soundOcclusion
            or asset.climbable ~= originalValues.climbable
            or asset.solidity ~= originalValues.solidity
            or asset.breakStamina ~= originalValues.breakStamina then
            return true
        end
        local openableChanged = false
        if originalValues.openable ~= nil then
            pcall(function()
                openableChanged = asset.openable ~= originalValues.openable
                    or asset.openSound ~= originalValues.openSound
                    or asset.closeSound ~= originalValues.closeSound
            end)
        end
        return openableChanged
    end

    --Creates the fork and points this map at it. DuplicateWall serializes
    --the LIVE in-memory asset, so the copy snapshots the dialog's edits
    --exactly as they stand; the original is then reverted and never
    --uploaded - other maps keep it exactly as it was. Every operation drawn
    --with the original on this map is retyped to the fork
    --(ReplaceWallOperations keeps each op's timestamp so geometry re-applies
    --in the same order), and palette chips follow - a forked library chip
    --becomes a custom chip so Edit Wall stays available on it.
    local ForkAsset = function(makeGlobal)
        local newGuid = assets:DuplicateWall(wallid)
        if newGuid == nil then
            RevertChanges()
            return
        end

        local fork = assets.walls[newGuid]
        if makeGlobal then
            pcall(function()
                fork.markupMapId = ""
            end)
        else
            m.mapScope.StampWall(fork)
        end
        fork:Upload()

        RevertChanges()

        pcall(function()
            game.currentMap:ReplaceWallOperations(wallid, newGuid)
        end)

        local changed = false
        for _,entry in ipairs(m.paletteEntries) do
            if entry.guid == wallid then
                entry.guid = newGuid
                if entry.kind == "wall" then
                    entry.kind = "custom"
                end
                changed = true
            end
        end
        if changed then
            MM.SavePalette(m.paletteEntries)
        end
    end

    local dialogPanel
    dialogPanel = gui.Panel{
        id = "MarkupWallDialog",
        classes = {"framedPanel"},
        --94% of the modal layer, capped at the design width: full size in
        --the main window, shrink-to-fit inside a small popout window.
        width = "94%",
        maxWidth = 460,
        height = "auto",
        pad = 16,
        borderBox = true,
        flow = "vertical",
        styles = ThemeEngine.MergeStyles{
            Styles.Panel,
            Styles.Form,
            {
                classes = {"formStackedRow"},
                width = "96%",
            },
            {
                classes = {"slider"},
                height = 30,
            },
            {
                classes = {"sliderLabel"},
                fontSize = 14,
            },
            {
                classes = {"formCheck"},
                lmargin = 8,
                vmargin = 2,
            },
        },

        children = {
            gui.Label{
                classes = {"dialogTitle"},
                text = "Edit Markup Wall",
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Name:",
                },
                gui.Input{
                    classes = {"formStacked"},
                    text = asset.description or "",
                    change = function(element)
                        asset.description = element.text
                        --renaming a shared wall makes it a new wall: the
                        --shared-wall row's label and button follow the name.
                        dialogPanel:FireEventTree("refreshscope")
                    end,
                },
            },

            --map-private wall types: created from this map's palette and
            --hidden from other maps' pickers until promoted, mirroring the
            --zone type editor's button. Applied live like every other field
            --in this dialog: Save uploads the promotion, Cancel reverts it.
            gui.Panel{
                classes = {"formStackedRow", cond(m.mapScope.WallMapId(asset) ~= nil, nil, "collapsed")},
                gui.Label{
                    classes = {"formStacked"},
                    text = "This wall type is only available on this map.",
                },
                gui.Button{
                    classes = {"sizeM"},
                    halign = "left",
                    text = "Make Available to All Maps",
                    click = function(element)
                        pcall(function()
                            asset.markupMapId = ""
                        end)
                        element.parent:SetClass("collapsed", true)
                    end,
                },
            },

            --shared walls: the explicit opt-in to edit the wall in place for
            --every map that uses it - or, once renamed, to make the FORK
            --available to all maps instead (a renamed wall is a new wall;
            --see the fork comment above). Both act immediately and close.
            gui.Panel{
                classes = {"formStackedRow", cond(isGlobalWall, nil, "collapsed")},
                flow = "vertical",
                height = "auto",

                gui.Label{
                    classes = {"formStacked"},
                    width = "100%",
                    text = "This wall is shared with other maps. Save makes a copy private to this map.",
                    refreshscope = function(element)
                        if IsRenamed() then
                            element.text = "Renamed: saving creates a new wall type for this map."
                        else
                            element.text = "This wall is shared with other maps. Save makes a copy private to this map."
                        end
                    end,
                },

                gui.Button{
                    classes = {"sizeM"},
                    halign = "left",
                    vmargin = 4,
                    text = "Save Changes to This Wall for All Maps",
                    refreshscope = function(element)
                        if IsRenamed() then
                            element.text = "Make Available to All Maps"
                        else
                            element.text = "Save Changes to This Wall for All Maps"
                        end
                    end,
                    click = function()
                        if IsRenamed() then
                            --a renamed wall is a new wall: fork it game-wide,
                            --leaving the original untouched.
                            ForkAsset(true)
                        else
                            --edit the shared wall in place: every map using
                            --it sees the changes.
                            asset:Upload()
                        end
                        gui.CloseModalInLayer(modalLayer)
                    end,
                },
            },

            gui.Check{
                classes = {"formCheck", cond(canBeOpenable, nil, "collapsed")},
                text = "Openable (Door)",
                tooltip = "When set, every wall segment drawn with this type is a door: a clickable icon floats over it, and opening it disables the whole segment's blocking until it is closed again. The Director can right-click the icon to lock the door.",
                value = openable,
                change = function(element)
                    openable = element.value
                    MM.SetAssetOpenable(asset, openable)
                    dialogPanel:FireEventTree("refreshopenable")
                end,
            },

            gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = "While closed, the door blocks exactly like this wall type (all the settings below apply). Opening it via its icon disables the drawn segment entirely; the sound plays for everyone. The Director always sees door icons and can right-click them to lock or unlock; players can use a door within 2 tiles and line of sight.",
                width = "96%",
                height = "auto",
                halign = "center",
                vmargin = 2,
                refreshopenable = function(element)
                    element:SetClass("collapsed", not openable)
                end,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "Blocks Movement",
                value = asset.blocksMovement == true,
                change = function(element)
                    asset.blocksMovement = element.value
                end,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "Blocks Forced Movement",
                value = asset.blocksForcedMovement == true,
                change = function(element)
                    asset.blocksForcedMovement = element.value
                end,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "Blocks Vision",
                value = asset.occludesVision == true,
                change = function(element)
                    asset.occludesVision = element.value
                end,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "Blocks Light",
                value = asset.occludesLight == true,
                change = function(element)
                    asset.occludesLight = element.value
                end,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "One-Way Vision & Light",
                tooltip = "When set, the wall only blocks vision and light from one side. The side depends on the direction the wall was drawn in.",
                value = asset.visionOneWay == true,
                change = function(element)
                    asset.visionOneWay = element.value
                end,
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Cover:",
                },
                gui.Dropdown{
                    classes = {"formStacked"},
                    idChosen = asset.cover or "None",
                    options = {
                        {
                            id = "None",
                            text = "No Cover",
                        },
                        {
                            id = "Half",
                            text = "Half Cover",
                        },
                        {
                            id = "ThreeQuarters",
                            text = "Three-Quarters Cover",
                        },
                        {
                            id = "Full",
                            text = "Full Cover",
                        },
                    },
                    change = function(element)
                        asset.cover = element.idChosen
                    end,
                },
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Climbable:",
                },
                gui.Dropdown{
                    classes = {"formStacked"},
                    idChosen = asset.climbable or "NotClimbable",
                    options = {
                        {
                            id = "NotClimbable",
                            text = "Not Climbable",
                        },
                        {
                            id = "ClimbersOnly",
                            text = "Climbable (Climbers Only)",
                        },
                        {
                            id = "AllCreatures",
                            text = "Climbable (All Creatures)",
                        },
                    },
                    change = function(element)
                        asset.climbable = element.idChosen
                    end,
                },
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Blocks Sounds:",
                },
                gui.Slider{
                    value = asset.soundOcclusion or 0,
                    minValue = 0,
                    maxValue = 1,
                    sliderWidth = 240,
                    labelWidth = 50,
                    events = {
                        change = function(element)
                            asset.soundOcclusion = element.value
                        end,
                    },
                },
            },

            --Breakable: a creature shoved into this wall with enough force
            --smashes through it. Applies to thin walls and solid blocks
            --alike. The material rows below stay hidden until it is on.
            gui.Check{
                classes = {"formCheck"},
                text = "Breakable",
                tooltip = "When set, a creature shoved into this wall hard enough smashes through it instead of stopping. The force needed is the wall's stamina.",
                value = breakable,
                change = function(element)
                    breakable = element.value
                    ApplyBreakToAsset()
                    dialogPanel:FireEventTree("refreshbreak")
                end,
            },

            gui.Panel{
                classes = {"formStackedRow"},
                refreshbreak = function(element)
                    element:SetClass("collapsed", not breakable)
                end,

                gui.Label{
                    classes = {"formStacked"},
                    text = "Material:",
                },
                gui.Dropdown{
                    classes = {"formStacked"},
                    idChosen = breakMaterialId,
                    options = (function()
                        local result = {}
                        for _,material in ipairs(K.BREAK_MATERIALS) do
                            result[#result+1] = {
                                id = material.id,
                                text = material.text,
                            }
                        end
                        return result
                    end)(),
                    change = function(element)
                        breakMaterialId = element.idChosen
                        local material = MM.BreakMaterialById(breakMaterialId)
                        --Presets stamp their stamina; Custom keeps whatever
                        --value was already there as the starting point.
                        if material ~= nil and material.stamina ~= nil then
                            breakStamina = material.stamina
                        end
                        ApplyBreakToAsset()
                        dialogPanel:FireEventTree("refreshbreak")
                    end,
                },
            },

            gui.Panel{
                classes = {"formStackedRow"},
                refreshbreak = function(element)
                    element:SetClass("collapsed", not breakable)
                end,

                gui.Label{
                    classes = {"formStacked"},
                    text = "Stamina:",
                },

                --Preset materials show their fixed value; only Custom is
                --editable. Both live here and swap by collapse so the row
                --keeps its layout either way.
                gui.Label{
                    classes = {"formStacked"},
                    text = "",
                    refreshbreak = function(element)
                        element:SetClass("collapsed", breakMaterialId == "custom")
                        element.text = string.format("%d", breakStamina)
                    end,
                },

                gui.Input{
                    classes = {"formStacked"},
                    text = string.format("%d", breakStamina),
                    width = 60,
                    characterLimit = 3,
                    numeric = true,
                    selectAllOnFocus = true,
                    refreshbreak = function(element)
                        element:SetClass("collapsed", breakMaterialId ~= "custom")
                    end,
                    change = function(element)
                        local n = tonumber(element.text)
                        if n == nil or n < 1 then
                            --reject non-numeric / zero: restore the last good
                            --value rather than silently making it unbreakable.
                            element.text = string.format("%d", breakStamina)
                            return
                        end
                        breakStamina = math.floor(n + 0.5)
                        element.text = string.format("%d", breakStamina)
                        ApplyBreakToAsset()
                    end,
                },
            },

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                vmargin = 8,

                gui.Button{
                    classes = {"sizeM"},
                    text = "Cancel",
                    halign = "center",
                    captureEscape = true,
                    escapePriority = EscapePriority.EXIT_DIALOG,
                    events = {
                        click = function(element)
                            element:FireEvent("escape")
                        end,
                        escape = function()
                            RevertChanges()
                            gui.CloseModalInLayer(modalLayer)
                        end,
                    },
                },

                gui.Button{
                    classes = {"sizeM"},
                    text = cond(isGlobalWall, "Save Copy for This Map", "Save"),
                    halign = "center",
                    events = {
                        click = function()
                            if isGlobalWall then
                                --editing a shared wall forks it (see the
                                --fork comment above); untouched = nothing
                                --to fork, so just restore and close.
                                if IsEdited() then
                                    ForkAsset(false)
                                else
                                    RevertChanges()
                                end
                            else
                                asset:Upload()
                            end
                            gui.CloseModalInLayer(modalLayer)
                        end,
                    },
                },
            },
        },
    }

    --settle the breakability + openable rows' initial collapse state + values,
    --and the shared-wall row's label/button text.
    dialogPanel:FireEventTree("refreshbreak")
    dialogPanel:FireEventTree("refreshopenable")
    dialogPanel:FireEventTree("refreshscope")

    modalLayer = gui.ShowModal(dialogPanel, {owner = owner})
end

--============================================================================
--Sharing markup back to a map pack.
--
--A map added from a map pack (game.currentMap.packSource ~= nil) can have
--the markup drawn on it - walls and doors, zones, footstep regions, props -
--shared with everyone who adds that map from the pack. The engine diffs the
--game's floors against the pack's copy (mappacks.GetMarkupSummary), the user
--ticks the parts to include and adds a description and author name, and
--mappacks.UploadMarkup publishes the set. The Create Map dialog lists shared
--sets under each pack map and adds the map with the chosen one applied.
--
--Lives on `m` rather than as a file-level local so the Walls tab's share
--icon (MapMarkupPanel.lua) can reach it.
--============================================================================
do
    local ShareRow = function(args)
        local count = args.count or 0
        local available = count > 0 or args.extra ~= nil
        local detail = ""
        if count > 0 then
            detail = string.format("%d %s", count, cond(count == 1, args.singular, args.plural))
        end
        if args.extra ~= nil then
            detail = cond(detail ~= "", detail .. ", " .. args.extra, args.extra)
        end
        if detail == "" then
            detail = "none added"
        end

        return gui.Panel{
            classes = {"formStackedRow"},
            flow = "horizontal",
            height = "auto",
            valign = "top",
            gui.Check{
                classes = {"formCheck"},
                text = args.text,
                value = available,
                interactable = available,
                width = 180,
                halign = "left",
                valign = "center",
                change = function(element)
                    args.state[args.key] = element.value
                end,
            },
            gui.Label{
                classes = {"formStacked"},
                width = "100%-190",
                height = "auto",
                valign = "center",
                fontSize = 13,
                opacity = cond(available, 1, 0.6),
                text = detail,
            },
        }
    end

    --owner: the panel element the dialog is opened from (routes the modal to
    --the window that panel lives in).
    m.ShowMarkupShareDialog = function(owner)
        local map = game.currentMap
        if map == nil or map.packSource == nil then
            return
        end
        local mapid = map.id
        local mapName = map.description

        mappacks.GetMarkupSummary{
            mapid = mapid,
            error = function(msg)
                gui.ModalMessage{
                    title = "Cannot Share Markup",
                    message = msg,
                }
            end,
            success = function(summary)
                if game.currentMapId ~= mapid then
                    return
                end

                --existing: the newest markup set this user already shared for
                --the map, if any. The dialog then updates (upload the new set,
                --drop the old one) and offers deletion.
                local BuildDialog = function(existing)
                    local state = {
                        walls = summary.walls > 0 or summary.wallTypes > 0,
                        zones = summary.zones > 0,
                        footsteps = summary.footsteps > 0 or summary.footstepDefault,
                        props = summary.props > 0,
                        elevation = summary.elevation > 0,
                    }
                    local anything = state.walls or state.zones or state.footsteps or state.props or state.elevation

                    local description = cond(existing ~= nil, (existing or {}).description, "")
                    local author = cond(existing ~= nil, (existing or {}).author, dmhub.userDisplayName or "")
                    if author == nil or author == "" then
                        author = dmhub.userDisplayName or ""
                    end
                    local modalLayer

                    local uploadButton
                    local statusLabel

                    local dialogPanel
                    dialogPanel = gui.Panel{
                        id = "MarkupShareDialog",
                        classes = {"framedPanel"},
                        width = "94%",
                        maxWidth = 520,
                        height = "auto",
                        pad = 16,
                        borderBox = true,
                        flow = "vertical",
                        styles = ThemeEngine.MergeStyles{
                            Styles.Panel,
                            Styles.Form,
                            {
                                classes = {"formStackedRow"},
                                width = "96%",
                            },
                            {
                                classes = {"formCheck"},
                                lmargin = 8,
                                vmargin = 2,
                            },
                        },

                        children = {
                            gui.Label{
                                classes = {"dialogTitle"},
                                text = cond(existing ~= nil, "Update Map Markup", "Share Map Markup"),
                            },

                            gui.Label{
                                classes = {"formStacked"},
                                width = "96%",
                                height = "auto",
                                textWrap = true,
                                vmargin = 6,
                                text = cond(anything,
                                    cond(existing ~= nil,
                                        string.format("You have already shared markup for %s. Updating replaces it with the markup on the map now. Choose what to include:", mapName),
                                        string.format("Share the markup you have added to %s with everyone who adds this map from its map pack. Choose what to include:", mapName)),
                                    string.format("%s has no markup beyond what the map pack ships with. Draw some walls, zones, footstep regions, elevation or props first.", mapName)),
                            },

                            ShareRow{
                                state = state, key = "walls", text = "Walls & Doors",
                                count = summary.walls, singular = "segment", plural = "segments",
                                extra = cond(summary.wallTypes > 0, string.format("%d wall %s", summary.wallTypes, cond(summary.wallTypes == 1, "type", "types")), nil),
                            },
                            ShareRow{
                                state = state, key = "zones", text = "Zones",
                                count = summary.zones, singular = "zone", plural = "zones",
                            },
                            ShareRow{
                                state = state, key = "footsteps", text = "Footsteps",
                                count = summary.footsteps, singular = "region", plural = "regions",
                                extra = cond(summary.footstepDefault, "default surface", nil),
                            },
                            ShareRow{
                                state = state, key = "elevation", text = "Elevation",
                                count = summary.elevation, singular = "painted area", plural = "painted areas",
                            },
                            ShareRow{
                                state = state, key = "props", text = "Props",
                                count = summary.props, singular = "prop", plural = "props",
                            },

                            gui.Panel{
                                classes = {"formStackedRow", cond(anything, nil, "collapsed")},
                                flow = "vertical",
                                height = "auto",
                                gui.Label{
                                    classes = {"formStacked"},
                                    text = "Description:",
                                },
                                gui.Input{
                                    classes = {"formStacked"},
                                    width = "100%",
                                    height = 70,
                                    multiline = true,
                                    textAlignment = "topleft",
                                    characterLimit = 300,
                                    placeholderText = "e.g. Walls and doors, elevation, and water.",
                                    text = description,
                                    change = function(element)
                                        description = element.text
                                    end,
                                },
                            },

                            gui.Panel{
                                classes = {"formStackedRow", cond(anything, nil, "collapsed")},
                                gui.Label{
                                    classes = {"formStacked"},
                                    text = "Author:",
                                },
                                gui.Input{
                                    classes = {"formStacked"},
                                    characterLimit = 40,
                                    placeholderText = "Your name, as shown to other users",
                                    text = author,
                                    change = function(element)
                                        author = element.text
                                    end,
                                },
                            },

                            gui.Label{
                                classes = {"formStacked"},
                                width = "96%",
                                height = "auto",
                                textWrap = true,
                                fontSize = 12,
                                opacity = 0.8,
                                vmargin = 4,
                                text = cond(anything, "Shared markup is public: anyone adding this map can choose it. You can delete your own uploads from the Create Map dialog.", ""),
                            },

                            gui.Label{
                                classes = {"formStacked"},
                                width = "96%",
                                height = "auto",
                                textWrap = true,
                                fontSize = 13,
                                text = "",
                                create = function(element)
                                    statusLabel = element
                                end,
                            },

                            gui.Panel{
                                width = "100%",
                                height = "auto",
                                flow = "horizontal",
                                halign = "center",
                                vmargin = 8,

                                gui.Button{
                                    classes = {"sizeM"},
                                    text = cond(anything, "Cancel", "Close"),
                                    halign = "center",
                                    captureEscape = true,
                                    escapePriority = EscapePriority.EXIT_DIALOG,
                                    events = {
                                        click = function(element)
                                            element:FireEvent("escape")
                                        end,
                                        escape = function()
                                            gui.CloseModalInLayer(modalLayer)
                                        end,
                                    },
                                },

                                --removes the user's shared set from the cloud; only offered
                                --when one exists.
                                gui.Button{
                                    classes = {"sizeM", cond(existing ~= nil, nil, "collapsed")},
                                    text = "Delete Shared Markup",
                                    halign = "center",
                                    click = function(element)
                                        gui.ModalMessage{
                                            title = "Delete Shared Markup",
                                            message = string.format("Remove the markup you shared for %s? Everyone loses access to it, and this cannot be undone.", mapName),
                                            options = {
                                                {
                                                    text = "Delete",
                                                    execute = function()
                                                        if not dialogPanel.valid then
                                                            return
                                                        end
                                                        statusLabel.text = "Deleting..."
                                                        mappacks.DeleteMarkup{
                                                            pack = existing.pack,
                                                            mapid = existing.mapid,
                                                            id = existing.id,
                                                            success = function()
                                                                if dialogPanel.valid then
                                                                    gui.CloseModalInLayer(modalLayer)
                                                                end
                                                                gui.ModalMessage{
                                                                    title = "Shared Markup Deleted",
                                                                    message = string.format("Your shared markup for %s has been removed.", mapName),
                                                                }
                                                            end,
                                                            error = function(msg)
                                                                if dialogPanel.valid then
                                                                    statusLabel.text = "Delete failed: " .. tostring(msg)
                                                                end
                                                            end,
                                                        }
                                                    end,
                                                },
                                                {
                                                    text = "Cancel",
                                                },
                                            },
                                        }
                                    end,
                                },

                                gui.Button{
                                    classes = {"sizeM", cond(anything, nil, "collapsed")},
                                    text = cond(existing ~= nil, "Update", "Upload"),
                                    halign = "center",
                                    create = function(element)
                                        uploadButton = element
                                    end,
                                    click = function(element)
                                        if not (state.walls or state.zones or state.footsteps or state.props or state.elevation) then
                                            statusLabel.text = "Choose at least one part to share."
                                            return
                                        end
                                        if author == nil or author:match("%S") == nil then
                                            statusLabel.text = "Enter an author name."
                                            return
                                        end

                                        element:SetClass("hidden", true)
                                        statusLabel.text = "Uploading..."
                                        MM.track("markup_share_upload", {
                                            pack = summary.pack,
                                            walls = cond(state.walls, summary.walls, 0),
                                            zones = cond(state.zones, summary.zones, 0),
                                            footsteps = cond(state.footsteps, summary.footsteps, 0),
                                            props = cond(state.props, summary.props, 0),
                                            elevation = cond(state.elevation, summary.elevation, 0),
                                        })
                                        mappacks.UploadMarkup{
                                            mapid = mapid,
                                            walls = state.walls,
                                            zones = state.zones,
                                            footsteps = state.footsteps,
                                            props = state.props,
                                            elevation = state.elevation,
                                            description = description,
                                            author = author,
                                            success = function(id)
                                                if dialogPanel.valid then
                                                    gui.CloseModalInLayer(modalLayer)
                                                end
                                                --an update replaces the previous set: the new one is
                                                --live, so the old one can go.
                                                if existing ~= nil and existing.id ~= id then
                                                    mappacks.DeleteMarkup{
                                                        pack = existing.pack,
                                                        mapid = existing.mapid,
                                                        id = existing.id,
                                                    }
                                                end
                                                gui.ModalMessage{
                                                    title = cond(existing ~= nil, "Markup Updated", "Markup Shared"),
                                                    message = cond(existing ~= nil,
                                                        string.format("Your shared markup for %s has been replaced with the markup on the map now.", mapName),
                                                        string.format("Your markup for %s is now available to everyone who adds this map.", mapName)),
                                                }
                                            end,
                                            error = function(msg)
                                                if not dialogPanel.valid then
                                                    return
                                                end
                                                element:SetClass("hidden", false)
                                                statusLabel.text = "Upload failed: " .. tostring(msg)
                                            end,
                                        }
                                    end,
                                },
                            },
                        },
                    }

                    modalLayer = gui.ShowModal(dialogPanel, {owner = owner})
                end

                mappacks.ListMarkup{
                    pack = summary.pack,
                    mapid = summary.mapid,
                    success = function(list)
                        local existing = nil
                        for _, info in ipairs(list) do
                            if info.mine and (existing == nil or info.mtime > existing.mtime) then
                                existing = info
                            end
                        end
                        BuildDialog(existing)
                    end,
                    error = function(msg)
                        --the list is a nicety; sharing still works without it.
                        BuildDialog(nil)
                    end,
                }
            end,
        }
    end
end


--============================================================================
--Exports: the other MapMarkup files call these through MM.
--============================================================================
MM.ShowMarkupWallDialog = ShowMarkupWallDialog
