--- Shared constants for the Fishing feature
--- Provides the enum vocabulary, size bands, and species presentation pools
--- used across the fishing classes.
--- @class FSHConstants
FSHConstants = RegisterGameType("FSHConstants")

--- Turns on every testing affordance at once: the Trip's starting points, the
--- forced cast outcome, and the forced events-table result. One switch so none
--- of them can be left on by accident. Ships false.
FSHConstants.DEBUG_MODE = true

--- Points a Trip opens with while debugging, so the Tackle table is reachable
--- without a long night's fishing.
FSHConstants.DEBUG_STARTING_POINTS = 600

--- The id of the roll check a cast is asked for under.
FSHConstants.rollCheckId = "fsh_cast"

--- Items the Tackle table hands out.
FSHConstants.itemHeartyMeal = "f6b399c9-bc72-4beb-8c0f-cc90b4617636"
FSHConstants.itemGreatMeal = "2cdce78b-f0b6-4f26-8d91-ec87f301df9f"
FSHConstants.itemAmazingMeal = "2a0994cf-ac5b-4c77-b9de-4466bc7cf53e"

--- The shared effect all three meals apply.
FSHConstants.effectMeal = "a89ba2b7-a60c-4536-8bcc-cdb016e71c3e"

--- The name of the fishing window, which is also how it is launched.
FSHConstants.windowName = "Fishing"

--- Titles the module grants. Angler, Goldenrod, and Master of Reels ship with
--- the game; Devil's Bargain is added by the fishing content.
FSHConstants.titleAngler = "396b55b9-efc0-4a6d-85c2-0bbab68213ce"
FSHConstants.titleGoldenrod = "c1b8ca34-655b-4bac-a0f6-753af9df91e1"
FSHConstants.titleMasterOfReels = "c5fd6e95-bf65-4a12-a40b-1eda365dfaef"
FSHConstants.titleDevilsBargain = "a5df30c4-b496-48bd-a688-6e53d04fcb36"

--- Ongoing effects the module applies. Empty until the content is authored, at
--- which point applying one becomes a no-op rather than an error.
FSHConstants.effectFondMemories = "dba6aaef-b67a-47c6-9edb-9e25415da8d2"
FSHConstants.effectGoldenrodReroll = "be68db96-c2f6-462b-ac3e-645fcf543d7a"

--- The modifier pipeline's scope for the roll itself. A cast is a project roll,
--- which the rules define as a test with special handling, so it reads the
--- Tests scope: that is where Skilled lives.
FSHConstants.modifierRollType = "test_power_roll"

--- The modifier pipeline's scope for fishing's own capabilities, kept separate
--- so a title that only matters while fishing never surfaces anywhere else.
FSHConstants.fishingRollType = "fishing_roll"

--- Valid water types. A Water and a species are each strictly one or the other.
FSHConstants.WATER_TYPE = {
    DTConstant.CreateNew("fresh", 1, "Fresh"),
    DTConstant.CreateNew("salt", 2, "Salt")
}

--- Valid size bands, ordered smallest to largest.
FSHConstants.BAND = {
    DTConstant.CreateNew("tiny", 1, "Tiny"),
    DTConstant.CreateNew("small", 2, "Small"),
    DTConstant.CreateNew("good", 3, "Good"),
    DTConstant.CreateNew("big", 4, "Big"),
    DTConstant.CreateNew("monster", 5, "Monster"),
    DTConstant.CreateNew("ancient", 6, "Ancient")
}

--- Convenience accessors for direct access to specific constants
FSHConstants.WATER_TYPE.FRESH = FSHConstants.WATER_TYPE[1]
FSHConstants.WATER_TYPE.SALT = FSHConstants.WATER_TYPE[2]

FSHConstants.BAND.TINY = FSHConstants.BAND[1]
FSHConstants.BAND.SMALL = FSHConstants.BAND[2]
FSHConstants.BAND.GOOD = FSHConstants.BAND[3]
FSHConstants.BAND.BIG = FSHConstants.BAND[4]
FSHConstants.BAND.MONSTER = FSHConstants.BAND[5]
FSHConstants.BAND.ANCIENT = FSHConstants.BAND[6]

--- Points falling in each band. The lowest band opens at 12 because a total of
--- 11 or less is the one that got away and never produces a species. Ancient
--- has no ceiling.
FSHConstants.BAND_POINTS = {
    tiny = {
        min = 12,
        max = 14
    },
    small = {
        min = 15,
        max = 18
    },
    good = {
        min = 19,
        max = 23
    },
    big = {
        min = 24,
        max = 29
    },
    monster = {
        min = 30,
        max = 99
    },
    ancient = {
        min = 100
    }
}

--- Phosphor glyphs used for species art, pooled by band so that glyph weight
--- tracks the size of the fish.
FSHConstants.SPECIES_ICONS = {
    tiny = {
        "phosphor/fish-simple-thin.png",
        "phosphor/fish-simple-light.png",
        "phosphor/shrimp-thin.png",
        "phosphor/shrimp-light.png"
    },
    small = {
        "phosphor/fish-simple.png",
        "phosphor/fish-simple-light.png",
        "phosphor/fish-thin.png",
        "phosphor/shrimp.png"
    },
    good = {
        "phosphor/fish.png",
        "phosphor/fish-simple.png",
        "phosphor/fish-bold.png"
    },
    big = {
        "phosphor/fish-bold.png",
        "phosphor/fish-fill.png",
        "phosphor/fish-simple-bold.png"
    },
    monster = {
        "phosphor/fish-fill.png",
        "phosphor/fish-duotone.png",
        "phosphor/fish-simple-fill.png"
    },
    ancient = {
        "phosphor/fish-duotone.png",
        "phosphor/fish-fill.png",
        "phosphor/waves-fill.png"
    }
}

--- Base species colour: hue carries the water type, depth carries the band, and
--- Ancient breaks to gold in both waters.
FSHConstants.SPECIES_COLORS = {
    fresh = {
        tiny = "#8fd4b0",
        small = "#6fc49a",
        good = "#4a9b6e",
        big = "#35785a",
        monster = "#245a45",
        ancient = "#c9a227"
    },
    salt = {
        tiny = "#9fc8dd",
        small = "#7fb0cc",
        good = "#4f8aab",
        big = "#3a6b8a",
        monster = "#274c66",
        ancient = "#c4952f"
    }
}

--- Stand-in used when no species matches a catch. Surfaced quietly: the player
--- sees a fish, never an error.
FSHConstants.GENERIC_FISH = {
    name = "fish",
    icon = "phosphor/fish-simple.png",
    color = "#7f9aa8"
}
