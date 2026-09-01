local mod = dmhub.GetModLoading()

--- Shared vocabulary for the Respite feature.
RSPConstants = RegisterGameType("RSPConstants")

-- Identity
RSPConstants.sessionDoc = "rspSession"
RSPConstants.dialogId = "rsprespite"
RSPConstants.panelName = "Respite"
RSPConstants.icon = "phosphor/campfire-bold.png"
RSPConstants.registryEvent = "rspActivityRegistry"  -- features listen by name to register activities

RSPConstants.phaseSetup = "setup"
RSPConstants.phaseOffered = "offered"
RSPConstants.phaseActive = "active"

-- Window
RSPConstants.windowWidth = 900
RSPConstants.windowHeight = 620

-- Footer cells. The band, its rule and the window's padding are the
-- DialogShell's; only the split inside the band is ours.
RSPConstants.footerCells = {33, 34, 33}   -- the middle takes the odd point
RSPConstants.footerCheckboxMargin = 12
RSPConstants.extendButtonWidth = 110        -- narrower than the size class; Complete Respite is the wide one

-- Body: instructions beside or above the working area, gutter is the leftover
RSPConstants.orientSide = "side"
RSPConstants.orientTop = "top"
RSPConstants.instructionsSideWidth = "25%"
RSPConstants.workingSideWidth = "73%"
RSPConstants.instructionsTopHeight = "20%"
RSPConstants.workingTopHeight = "78%"

-- Character rows, shared by every Respite list
RSPConstants.characterRowHeight = 34
RSPConstants.characterRowImageSize = 30
RSPConstants.characterRowIndent = 24        -- a follower sits in from its hero
RSPConstants.characterRowNameMargins = 16
RSPConstants.characterRowNameMaxChars = 20
RSPConstants.characterRowTrailingSlot = 26  -- one slot per trailing widget, so columns line up
RSPConstants.characterRowIndicatorWidth = "32%"
RSPConstants.characterRowRollsWidth = 26
RSPConstants.characterRowRollsRightMargin = 0
RSPConstants.characterRowLockSize = 20
RSPConstants.characterRowAttentionSize = 20
RSPConstants.characterRowSheetSize = 20

RSPConstants.iconUncommitted = "phosphor/lock-simple-open-duotone.png"
RSPConstants.iconCommitted = "phosphor/lock-simple-fill.png"

--- The name takes what the image, indent and trailing widgets leave. Pixels,
--- not shares, so a new widget cannot push the row wider than its list.
--- @param trailing number how many widgets follow the name
--- @param indent nil|boolean whether this row sits under the one above
--- @return string
function RSPConstants.CharacterRowNameWidth(trailing, indent)
    local taken = RSPConstants.characterRowImageSize
        + RSPConstants.characterRowNameMargins
        + ((trailing or 0) * RSPConstants.characterRowTrailingSlot)

    if indent then
        taken = taken + RSPConstants.characterRowIndent
    end

    return "100%-" .. tostring(taken)
end

-- Setup step: the Respite's own fields, then the activity registry below them
RSPConstants.daysMin = 1
RSPConstants.daysMax = 99
RSPConstants.activitiesMin = 0
RSPConstants.activitiesMax = 99
RSPConstants.formLabelWidth = "46%"
RSPConstants.stepperWidth = "22%"
RSPConstants.locationWidth = "50%"          -- a name needs more room than a stepper
RSPConstants.stepperButtonWidth = "24%"     -- button / well / button
RSPConstants.stepperWellWidth = "52%"
RSPConstants.activityAreaHeight = "100%-146"
RSPConstants.activityHeaderTopMargin = 12
RSPConstants.activityHeaderBottomMargin = 4
RSPConstants.activityBodyIndent = 24

-- Activities step, player: roster beside the activity pane
RSPConstants.activityListWidth = "26%"
RSPConstants.activityPaneWidth = "72%"
RSPConstants.activityPickerGap = 8          -- label sizes to its text, so this is the gap to the dropdown
RSPConstants.activityBodyHeight = "100%-56"
RSPConstants.activitySheetButtonSize = 28
RSPConstants.iconCharacterSheet = "ui-icons/character-sheet.png"
RSPConstants.sheetTabBuilder = "Builder"    -- where a player goes to change a kit mid-Respite
RSPConstants.sheetTabDowntime = "Downtime"  -- where the Director goes to read a hero's projects

-- Activities step, Director: wider roster, it carries markers and roll counts
RSPConstants.directorListWidth = "40%"
RSPConstants.directorPaneWidth = "58%"
RSPConstants.directorListHeight = "100%"
RSPConstants.directorFooterCells = {20, 55, 25}  -- two checkboxes need more than a third

-- Director feed
RSPConstants.feedPaneHeight = "100%-10"
RSPConstants.feedSectionInset = 6           -- clears the scroll bar off the text
RSPConstants.feedSectionWidth = "100%-12"
RSPConstants.feedScrollWidth = "100%-4"
RSPConstants.feedScrollHeight = "100%-8"
RSPConstants.iconAttention = "phosphor/warning-diamond-duotone.png"
RSPConstants.iconComplete = "phosphor/check-circle-duotone.png"
RSPConstants.eventIconSize = 16

-- Extend Respite prompt
RSPConstants.extendDialogWidth = 520
RSPConstants.extendDialogHeight = 268
RSPConstants.extendDialogButtonLift = 14

-- Journal: "public" is the Shared Documents root; the folder is made on first use
RSPConstants.journalRoot = "public"
RSPConstants.journalFolder = "Respites"
