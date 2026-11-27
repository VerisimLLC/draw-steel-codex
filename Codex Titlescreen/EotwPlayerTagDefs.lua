local mod = dmhub.GetModLoading()

--Player Tags: the badges Encounter of the Week players earn and choose to show
--beside their name. Design: PLAYER_TAGS_BRIEF.md. Code: EotwPlayerTags.lua.
--
--THIS FILE IS DATA ONLY. The town server (cloudflare-game-server) reads it when
--it is deployed and decides who has earned what, so keep exactly to the shapes
--below: plain strings, numbers and true/false, no functions, no variables, no
--joining strings with "..". After a change, regenerate the server's copy
--(in cloudflare-game-server: npm run gen-player-tags) and deploy the server too.
--
--Each tag:
--  id           permanent; never change or reuse one (players keep tags by id)
--  name         the words on the badge
--  description  how it is earned, shown in the Guild and on the earn banner
--  style        a badge style: bronze, silver, gold, ember, slate, teal, violet, copper,
--               or special (a deep purple kept for one-of-a-kind titles)
--  hidden       true: left out of everyone's tag list until they earn it (a
--               surprise, or one that can no longer be earned). Leave it off to
--               show the tag, locked, as a goal in the Guild's list.
--  opens        "YYYY-MM-DD" (UTC): nobody earns the tag before this day. Any
--               award made earlier is taken back, to be earned again once it opens.
--  steam        optional: the API Name of the Steam achievement this tag also
--               unlocks. It must match an achievement set up in Steamworks.
--               Keep to tags anyone can earn by playing (wins, defeats, modes).
--  rule         one of:
--    { counter = "wins", atLeast = 10 }
--        counters: wins, defeats, encountersPlayed (each counts games, not heroes),
--        challengeWins, deadlyWins (different encounters won in that mode),
--        projectPoints (points put into town projects), ritesAided (Rites of
--        Return helped that raised another player's hero)
--    { counter = "projectPoints", atLeast = 100, project = "restore-temple" }
--        projectPoints in one project only
--    { counter = "encountersPlayed", atLeast = 1, before = "2026-12-31" }
--        wins, defeats and encountersPlayed may take `before`: only games
--        played before that day (UTC, written YYYY-MM-DD) count
--    { event = "projectTopBuilder", project = "build-great-forge" }
--        the top contributor(s) when that project is finished
--    { manual = true }
--        only an admin can grant it

EotwPlayerTagDefs = {
    version = 1,
    tags = {
        { id = "hero-of-blackbottom", name = "Hero of Blackbottom", description = "Won your first encounter for Blackbottom.", style = "bronze", steam = "EOTW_HERO_OF_BLACKBOTTOM", rule = { counter = "wins", atLeast = 1 } },
        { id = "wayfarer", name = "Wayfarer", description = "Saw 5 encounters through to the end, win or lose.", style = "teal", steam = "EOTW_WAYFARER", rule = { counter = "encountersPlayed", atLeast = 5 } },
        { id = "bricklayer", name = "Bricklayer", description = "Put 100 points of work into the town's projects.", style = "copper", rule = { counter = "projectPoints", atLeast = 100 } },
        { id = "seasoned", name = "Seasoned", description = "Won 10 encounters. You know how this goes by now.", style = "silver", steam = "EOTW_SEASONED", rule = { counter = "wins", atLeast = 10 } },
        { id = "regular", name = "Regular", description = "Saw 25 encounters through. The Guards at the Town Gate knows your face.", style = "teal", steam = "EOTW_REGULAR", rule = { counter = "encountersPlayed", atLeast = 25 } },
        { id = "builder", name = "Builder", description = "Put 1,000 points of work into the town's projects.", style = "copper", hidden = true, rule = { counter = "projectPoints", atLeast = 1000 } },
        { id = "legend", name = "Legend", description = "Won 50 encounters. They'll be telling stories about you.", style = "gold", hidden = true, steam = "EOTW_LEGEND", rule = { counter = "wins", atLeast = 50 } },
        { id = "undaunted", name = "Undaunted", description = "Fell in 5 encounters and kept coming back.", style = "slate", hidden = true, steam = "EOTW_UNDAUNTED", rule = { counter = "defeats", atLeast = 5 } },
        { id = "forgewright", name = "Forgewright", description = "Did more than anyone to build the Great Forge.", style = "special", hidden = true, rule = { event = "projectTopBuilder", project = "build-great-forge" } },
        { id = "pilgrim", name = "Pilgrim", description = "Put 100 points of work into restoring the Temple of Saint Llewellyn.", style = "silver", hidden = true, rule = { counter = "projectPoints", atLeast = 100, project = "restore-temple" } },
        { id = "hand-of-saint-llewellyn", name = "Hand of the Saint", description = "Did more than anyone to restore the Temple of Saint Llewellyn.", style = "special", hidden = true, rule = { event = "projectTopBuilder", project = "restore-temple" } },
        { id = "keeper-of-the-rite", name = "Keeper of the Rite", description = "Helped bring 5 fallen heroes back from the grave.", style = "gold", hidden = true, rule = { counter = "ritesAided", atLeast = 5 } },
        { id = "challenger", name = "Challenger", description = "Took on Challenge Mode and won.", style = "ember", hidden = true, steam = "EOTW_CHALLENGER", rule = { counter = "challengeWins", atLeast = 1 } },
        { id = "glutton-for-punishment", name = "Glutton for Punishment", description = "Won 10 different encounters in Challenge Mode. Why stop now?", style = "ember", hidden = true, steam = "EOTW_GLUTTON_FOR_PUNISHMENT", rule = { counter = "challengeWins", atLeast = 10 } },
        --Given once, by the playtest reset (reset-playtest in cloudflare-game-server
        --city.ts), to every account that had played; nobody can earn it afterwards.
        { id = "founding-hero", name = "Founding Hero", description = "Fought for Blackbottom. Thank you.", style = "silver", hidden = true, rule = { manual = true } },
        --Given by hand (admin-grant-tag), never by a rule: an in-joke about devils' hoofprints pointing the wrong way.
        { id = "devil-podiatrist", name = "Devil Podiatrist", description = "Knows which way a devil's hoofprints should point.", style = "special", hidden = true, rule = { manual = true } },
        { id = "deathdefier", name = "Deathdefier", description = "Won in Deadly Mode and lived to tell it.", style = "slate", hidden = true, steam = "EOTW_DEATHDEFIER", rule = { counter = "deadlyWins", atLeast = 1 } },
    },
}
