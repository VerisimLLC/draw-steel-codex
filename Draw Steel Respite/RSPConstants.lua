local mod = dmhub.GetModLoading()

--- Shared vocabulary for the Respite feature.
RSPConstants = RegisterGameType("RSPConstants")

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
RSPConstants.formLabelWidth = "46%"
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
--- Every trailing widget gets the same slot, so the columns line up whatever
--- a row happens to carry.
RSPConstants.characterRowTrailingSlot = 26
RSPConstants.characterRowNameMargins = 16
RSPConstants.characterRowRollsWidth = 26

--- The name takes whatever the token image and the trailing widgets leave
--- behind, so it shrinks as a row gains a rolls count, a status icon or a
--- lock.
--- The name takes what is left after the fixed furniture: the token image, the
--- indent on a follower's row, and one slot per trailing widget. Counted in
--- pixels rather than shares, so adding a widget cannot quietly push the row
--- wider than the list holding it.
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

--- Where a completed Respite writes itself up. "public" is the Shared
--- Documents root; the folder is made on first use.
RSPConstants.journalRoot = "public"
RSPConstants.journalFolder = "Respites"

--- Fired when the activity registry is ready to take registrations. Features
--- load before this module, so they cannot register during their own load and
--- no engine event covers a code reload. Any feature registering an activity
--- must listen for this by name.
RSPConstants.registryEvent = "rspActivityRegistry"

--- The Activities steps put a narrow roster beside the pane where the
--- activities themselves will live.
RSPConstants.activityListWidth = "26%"
RSPConstants.activityPaneWidth = "72%"

--- The Director's split is its own: that roster carries a warning marker and a
--- combined roll count beside every name, so it needs room the player's list
--- does not, and the feed beside it gives up about a fifth of its width.
RSPConstants.directorListWidth = "40%"
RSPConstants.directorPaneWidth = "58%"

--- What the roster leaves for the completion count beneath it.
RSPConstants.directorListHeight = "100%-32"

--- The Activities footer does not divide into thirds: two checkboxes side by
--- side need more than a third between two buttons that need less.
RSPConstants.directorFooterCells = {"20%", "55%", "25%"}

--- Air either side of each footer checkbox, so the pair does not read as one
--- run-on line.
RSPConstants.footerCheckboxMargin = 12

--- Extend keeps the size class's height and type but not its 175 width: it
--- says one short word, and Complete Respite is the wide one for a reason.
RSPConstants.extendButtonWidth = 110

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
RSPConstants.characterRowRollsRightMargin = 0

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

--- Events the Director has to act on, and the ones that went well.
RSPConstants.iconAttention = "phosphor/warning-diamond-duotone.png"
RSPConstants.iconComplete = "phosphor/check-circle-duotone.png"
RSPConstants.eventIconSize = 16

--- A Director feed section, inset from the pane so the scroll bar clears the
--- text rather than sitting over it.
RSPConstants.feedSectionInset = 6
RSPConstants.feedSectionWidth = "100%-12"

--- The scroller sits inside the bordered pane so its bar never lands on the
--- frame.
RSPConstants.feedScrollWidth = "100%-4"
RSPConstants.feedScrollHeight = "100%-8"

--- The Director's feed pane stops a little short of the divider below it.
RSPConstants.feedPaneHeight = "100%-10"

--- The Extend Respite prompt: two steppers and a pair of buttons.
RSPConstants.extendDialogWidth = 520
RSPConstants.extendDialogHeight = 268

--- Lifts the button row off the bottom edge of the prompt.
RSPConstants.extendDialogButtonLift = 14
