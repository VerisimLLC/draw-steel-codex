local mod = dmhub.GetModLoading()

--- Shared vocabulary for the Respite feature.
RSPConstants = {}

RSPConstants.sessionDoc = "rspSession"

RSPConstants.dialogId = "rsprespite"
RSPConstants.panelName = "Respite"
RSPConstants.icon = "phosphor/campfire-bold.png"

RSPConstants.phaseSetup = "setup"
RSPConstants.phaseOffered = "offered"
RSPConstants.phaseActive = "active"

RSPConstants.windowWidth = 900
RSPConstants.windowHeight = 620

--- Bands the shell reserves off the top and bottom of the window. The working
--- area takes whatever is left, so these are the dials for the overall
--- balance. Vertical only: widths inside a step are all relative.
--- What the header band is reserved at for the height maths. The band itself
--- is auto-height so the hairline hugs the heading; a generous reserve only
--- costs the working area a few pixels.
RSPConstants.headerHeight = 40
RSPConstants.dividerBand = 26
RSPConstants.footerHeight = 40

--- How tight the hairline sits under the heading. A laid-out MCDMDivider
--- scales its line art to its own height, so the height is the weight of the
--- rule, not a spacing lever; move the rule with the margins instead.
RSPConstants.headerDividerHeight = 12
RSPConstants.headerDividerTopMargin = -4
RSPConstants.headerDividerBottomMargin = 8

--- The heading's own line box carries slack under the baseline that no size
--- class trims. Pulling the label's bottom edge up closes it so the hairline
--- can sit against the type rather than against the box.
RSPConstants.headerTitleBottomMargin = -6

--- Margin above and below the divider that separates the working area from
--- the footer.
RSPConstants.footerDividerMargin = 12

--- Instructions run down the side of a step, or across the top of it. The
--- leftover percent in each pair is the gutter between the two.
RSPConstants.orientSide = "side"
RSPConstants.orientTop = "top"

RSPConstants.instructionsSideWidth = "25%"
RSPConstants.workingSideWidth = "73%"
RSPConstants.instructionsTopHeight = "20%"
RSPConstants.workingTopHeight = "78%"

--- Halves of the header line: heading left, Respite information right.
RSPConstants.headerTitleWidth = "25%"
RSPConstants.headerInfoWidth = "67%"

--- The launchable host floats its close button over the top-right corner, so
--- the header information has to stop short of it.
RSPConstants.headerInfoRightMargin = 0

--- Thirds of the footer, so a step's controls land left, centre or right.
RSPConstants.footerCellWidth = "33.3%"

RSPConstants.daysMin = 1
RSPConstants.daysMax = 99
RSPConstants.activitiesMin = 0
RSPConstants.activitiesMax = 99

--- A form row splits into a label and the control beside it.
RSPConstants.formLabelWidth = "35%"
RSPConstants.stepperWidth = "22%"

--- Shares of a stepper: a button, the well, a button.
RSPConstants.stepperButtonWidth = "24%"
RSPConstants.stepperWellWidth = "52%"

--- A character row in any of the Respite lists.
RSPConstants.characterRowHeight = 34
RSPConstants.characterRowImageSize = 30
RSPConstants.characterRowIndicatorWidth = "32%"

--- Share of the row the name gets when an indicator sits beside it. The rest
--- of the row is the token image, the indicator, and the margins between
--- them, so these two shares deliberately fall short of 100%.
RSPConstants.characterRowNameShare = "60%-"
RSPConstants.characterRowNameShareCrowded = "58%-"
RSPConstants.characterRowRollsWidth = "12%"

--- The name takes whatever the token image and the trailing widgets leave
--- behind, so it shrinks as a row gains a rolls count, a status icon or a
--- lock.
--- An indented row gives up the same width again, so its trailing widgets stay
--- in line with every other row's.
--- @param trailing number how many widgets follow the name
--- @param indent nil|boolean whether this row sits under the one above
--- @return string
function RSPConstants.CharacterRowNameWidth(trailing, indent)
    local share = "100%-"
    if trailing == 1 then
        share = RSPConstants.characterRowNameShare
    elseif trailing >= 2 then
        share = RSPConstants.characterRowNameShareCrowded
    end

    local taken = RSPConstants.characterRowImageSize
    if indent then
        taken = taken + RSPConstants.characterRowIndent
    end
    return share .. tostring(taken)
end

--- Commitment shown on a Director list row.
RSPConstants.iconUncommitted = "phosphor/lock-simple-open-duotone.png"
RSPConstants.iconCommitted = "phosphor/lock-simple-fill.png"
RSPConstants.characterRowLockSize = 20

--- Registered downtime activities sit in their own scrolling region below the
--- Respite's own fields, with each activity's fields indented under its
--- availability checkbox.
RSPConstants.activityAreaHeight = "100%-146"
RSPConstants.activityHeaderTopMargin = 12
RSPConstants.activityHeaderBottomMargin = 4
RSPConstants.activityBodyIndent = 24

--- Fired when the activity registry is ready to take registrations. Features
--- load before this module, so they cannot register during their own load and
--- no engine event covers a code reload. Any feature registering an activity
--- must listen for this by name.
RSPConstants.registryEvent = "rspActivityRegistry"

--- The Activities steps put a narrow roster beside the pane where the
--- activities themselves will live.
RSPConstants.activityListWidth = "28%"
RSPConstants.activityPaneWidth = "70%"

--- How far a follower's row sits in from its hero's.
RSPConstants.characterRowIndent = 24

--- Completion shown on an Activities list row.
RSPConstants.iconNotDone = "phosphor/circle-duotone.png"
RSPConstants.iconDone = "phosphor/check-circle.png"
RSPConstants.characterRowStatusSize = 20

--- Longest character name a list row shows before cutting it short.
RSPConstants.characterRowNameMaxChars = 20

--- Gap between a row's roll count and the icon beside it. Small, so the
--- number sits close to the status it belongs with.
RSPConstants.characterRowRollsRightMargin = 2

--- The activity pane's picker row, and what the body takes once the picker
--- has had its band.
--- The label sizes to its text, so this is the gap before the dropdown.
RSPConstants.activityPickerGap = 8
RSPConstants.activityBodyHeight = "100%-56"

--- Jumping from a Respite to the character sheet. The Builder tab is where a
--- player goes to change a kit, which is the usual reason to leave mid-Respite.
RSPConstants.iconCharacterSheet = "ui-icons/character-sheet.png"
RSPConstants.sheetTabBuilder = "Builder"
RSPConstants.activitySheetButtonSize = 28
