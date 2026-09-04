local mod = dmhub.GetModLoading()

--- Shared vocabulary for the Negotiation feature.
NEGConstants = RegisterGameType("NEGConstants")

-- Identity
NEGConstants.libraryDoc = "negLibrary"
NEGConstants.activeRunDoc = "negActive"
NEGConstants.panelName = "Negotiation"         -- keys the launchable panel
NEGConstants.panelTitle = "Negotiation"        -- what the Director's window says
NEGConstants.playerPanelTitle = "Negotiation"
NEGConstants.icon = "phosphor/handshake.png"

--- The presented-dialog id. NOT "negotiation": the old feature registers that
--- one unconditionally, outside its own feature flag, and two registrations
--- under one id leave whichever loads second in charge.
NEGConstants.dialogId = "dsnegotiation"

-- Window
NEGConstants.windowWidth = 1240
NEGConstants.windowHeight = 700
NEGConstants.listWidth = 360
NEGConstants.listRightMargin = 12

-- Player window: no footer, and wide enough to seat the NPC beside the board
NEGConstants.playerWindowWidth = 1220
NEGConstants.playerWindowHeight = 660

--- What DialogShell keeps for itself on a window with no footer: PAD top and
--- bottom (12 each) plus the heading band (40). The rule under the title sits
--- INSIDE that band rather than below it, so it costs nothing extra. The
--- working area is the rest, and the portrait is sized from it.
NEGConstants.playerShellChrome = 64
NEGConstants.playerWorkingHeight =
    NEGConstants.playerWindowHeight - NEGConstants.playerShellChrome

--- The NPC's portrait down the player window's left side, 2:3 - the proportion
--- the Avatar library's art is drawn at. The column is a FIXED width worked
--- out from the working area's height, because that is what the height gives
--- us; sizing the image off the height instead let it grow wider than its
--- column and sit on top of the form.
NEGConstants.playerPortraitWidth =
    math.floor(NEGConstants.playerWorkingHeight * 2 / 3)
NEGConstants.playerPortraitGap = 16

--- Footer cells. The band, its rule and the window's padding are the
--- DialogShell's; only the split inside the band is ours. Whole percentages,
--- and the middle cell carries the odd point so three of them sum to 100.
NEGConstants.footerCells = {33, 34, 33}

-- Run status
NEGConstants.statusSetup = "setup"
NEGConstants.statusRunning = "running"
NEGConstants.statusEnded = "ended"

-- Setup step: who is at the table
NEGConstants.participantRowHeight = 38
NEGConstants.participantImageSize = 32

-- The two things a hero can do: press the case, or read the room
NEGConstants.trackArgument = "argument"
NEGConstants.trackLearn = "learn"

-- Slot keys on the live negotiation
NEGConstants.slotLead = "argumentLead"
NEGConstants.slotAssist = "argumentAssist"
NEGConstants.slotLearn = "learn"

--- Track widths are set by how many token-plus-dropdown units each holds, not
--- by giving the two tracks equal halves. Two units in the argument and one in
--- the read means 2:1, which lands every unit on about a third of the pane -
--- the same room a montage challenge gives its Lead and Assist columns.
NEGConstants.trackArgumentWidth = "66%"
NEGConstants.trackLearnWidth = "32%"

-- Tray and slots
NEGConstants.slotSize = 46
NEGConstants.tokenSize = 40
NEGConstants.trayHeight = 52
NEGConstants.slotClass = "negSlot"     -- markers, not looks: drag targets test for these
NEGConstants.trayClass = "negTray"
NEGConstants.tokenClass = "negToken"

-- Rolling
NEGConstants.rollCheckId = "neg_test"

--- The bands a roller is shown before they roll. Deliberately vague: telling
--- the player "this appeals to a motivation" hands them the Director's read of
--- the NPC, which is the thing the negotiation is about finding out.
NEGConstants.tierBands = {
    "Probably bad",
    "Uncertain",
    "Probably good",
}

--- Power roll type for the modifier pipeline. Must be a stock type: the
--- modifier matcher admits only "all" or an exact match against a closed
--- vocabulary, and a miss drops every Tests-scoped modifier without raising -
--- Skilled included, so rolls just come out two lower with no error.
NEGConstants.modifierRollType = "test_power_roll"

--- What a slot opens on. The rules name these three for both making an
--- argument and reading an NPC; the dropdown offers every characteristic, on
--- the same chapter's "another applicable test, as the Director determines".
NEGConstants.argumentAttributes = { "rea", "inu", "prs" }

NEGConstants.iconShare = "phosphor/share-fat-bold.png"
NEGConstants.iconRoll = "ui-icons/dsdice/djordice-d10.png"

--- Replaces the die once a track's roll is in: the roll is spent, and the only
--- thing left to do with that track is clear it for the next one.
NEGConstants.iconReset = "phosphor/arrows-counter-clockwise-fill.png"

--- What a scale wears when the Director has not opened it. The bubbles stay,
--- so the table can see there IS a scale and how long it is - they just do not
--- get to read it.
NEGConstants.iconUnknown = "phosphor/question.png"

-- Scales
NEGConstants.scaleInterest = "interest"
NEGConstants.scalePatience = "patience"
NEGConstants.scaleMin = 0
NEGConstants.scaleMax = 5

--- A negotiation opens with interest between 1 and 4 and patience above 0, so
--- the config scales stop short of the values that would end it before it
--- began. The live scales run the full range.
NEGConstants.startInterestMin = 1
NEGConstants.startInterestMax = 4
NEGConstants.startPatienceMin = 1
NEGConstants.startPatienceMax = 5

-- Impression
NEGConstants.impressionMin = 1
NEGConstants.impressionMax = 99
NEGConstants.impressionDefault = 1

--- One glyph per point on a scale, indexed by the value it stands for. Scales
--- run 0..5, six bubbles: 0 is a real and terminal state - "No, and...", where
--- the NPC offers nothing and turns on the heroes - not the absence of one.
NEGConstants.scalePips = {
    [0] = "phosphor/number-circle-zero.png",
    [1] = "phosphor/number-circle-one.png",
    [2] = "phosphor/number-circle-two.png",
    [3] = "phosphor/number-circle-three.png",
    [4] = "phosphor/number-circle-four.png",
    [5] = "phosphor/number-circle-five.png",
}

--- Which theme class the whole lit run wears, chosen by the value it has
--- reached rather than by each pip. Interest follows the offer it buys;
--- patience follows how much room is left. Same thirds either way.
NEGConstants.interestTone = {
    [0] = "bgDanger",
    [1] = "bgDanger",
    [2] = "bgWarning",
    [3] = "bgWarning",
    [4] = "bgSuccess",
    [5] = "bgSuccess",
}

NEGConstants.patienceTone = {
    [0] = "bgDanger",
    [1] = "bgDanger",
    [2] = "bgWarning",
    [3] = "bgWarning",
    [4] = "bgSuccess",
    [5] = "bgSuccess",
}

--- What an unreached pip wears.
NEGConstants.toneUnlit = "bgFgMuted"

-- Icons
NEGConstants.iconEyeShown = "phosphor/eye.png"
NEGConstants.iconEyeHidden = "phosphor/eye-slash.png"
NEGConstants.iconNewFolder = "phosphor/folder-plus.png"
NEGConstants.iconImport = "phosphor/upload-simple-bold.png"
NEGConstants.iconGear = "phosphor/gear-six-fill.png"
NEGConstants.iconPlay = "phosphor/play-fill.png"
NEGConstants.iconConfigured = "phosphor/check-circle.png"

-- Editor form
NEGConstants.multilineHeight = 60
NEGConstants.traitColumnWidth = "46%"
NEGConstants.traitColumnGap = 16
NEGConstants.scaleColumnWidth = "46%"
NEGConstants.pipSize = 22

--- Sections inset from the pane's right edge so the scroll bar rides beside
--- them instead of over them.
NEGConstants.sectionWidth = "100%-16"

--- An offer row is a FIXED height. Left to size themselves, the rows came out
--- unequal and the ladder read as randomly spaced.
NEGConstants.offerRowHeight = 68
NEGConstants.offerLabelWidth = 130

-- The NPC's picture. Small: it is a reminder, not the subject of the page.
NEGConstants.portraitWidth = 128
NEGConstants.portraitHeight = 192
NEGConstants.portraitColumnWidth = 136

-- Field limits
NEGConstants.nameLimit = 80
NEGConstants.summaryLimit = 4000
NEGConstants.noteLimit = 1000
NEGConstants.offerLimit = 2000
NEGConstants.jsonLimit = 60000

--- The rules ask for at least this many of each before a negotiation is ready
--- to run. Advisory only: the editor marks the shortfall, it does not block.
NEGConstants.motivationsExpected = 2
NEGConstants.pitfallsExpected = 1

--- Clamp to a scale's range.
--- @param value any
--- @param minValue number
--- @param maxValue number
--- @return number
function NEGConstants.Clamp(value, minValue, maxValue)
    local n = tonumber(value) or minValue
    return math.max(minValue, math.min(maxValue, math.floor(n)))
end
