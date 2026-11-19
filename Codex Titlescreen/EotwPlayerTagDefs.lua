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
--  style        a badge style: bronze, silver, gold, ember, slate, teal, violet, copper
--  rule         one of:
--    { counter = "wins", atLeast = 10 }
--        counters: wins, defeats, encountersPlayed (each counts games, not heroes),
--        challengeWins, deadlyWins (different encounters won in that mode),
--        projectPoints (points put into town projects), ritesAided (Rites of
--        Return helped that raised another player's hero)
--    { counter = "projectPoints", atLeast = 100, project = "restore-temple" }
--        projectPoints in one project only
--    { event = "projectTopBuilder", project = "build-great-forge" }
--        the top contributor(s) when that project is finished
--    { manual = true }
--        only an admin can grant it

EotwPlayerTagDefs = {
    version = 1,
    tags = {
        { id = "hero-of-blackbottom", name = "Hero of Blackbottom", description = "Won your first encounter.", style = "bronze", rule = { counter = "wins", atLeast = 1 } },
        { id = "wayfarer", name = "Wayfarer", description = "Played 5 encounters.", style = "teal", rule = { counter = "encountersPlayed", atLeast = 5 } },
        { id = "bricklayer", name = "Bricklayer", description = "Put 100 points into town projects.", style = "copper", rule = { counter = "projectPoints", atLeast = 100 } },
        { id = "seasoned", name = "Seasoned", description = "Won 10 encounters.", style = "silver", rule = { counter = "wins", atLeast = 10 } },
        { id = "regular", name = "Regular", description = "Played 25 encounters.", style = "teal", rule = { counter = "encountersPlayed", atLeast = 25 } },
        { id = "builder", name = "Builder", description = "Put 1,000 points into town projects.", style = "copper", rule = { counter = "projectPoints", atLeast = 1000 } },
        { id = "legend", name = "Legend", description = "Won 50 encounters.", style = "gold", rule = { counter = "wins", atLeast = 50 } },
        { id = "undaunted", name = "Undaunted", description = "Fell in 5 encounters and kept coming back.", style = "slate", rule = { counter = "defeats", atLeast = 5 } },
        { id = "forgewright", name = "Forgewright", description = "Contributed the most to building the Great Forge.", style = "ember", rule = { event = "projectTopBuilder", project = "build-great-forge" } },
        { id = "pilgrim", name = "Pilgrim", description = "Put 100 points into restoring the Temple of Saint Llewellyn.", style = "silver", rule = { counter = "projectPoints", atLeast = 100, project = "restore-temple" } },
        { id = "hand-of-saint-llewellyn", name = "Hand of Saint Llewellyn", description = "Contributed the most to restoring the Temple of Saint Llewellyn.", style = "gold", rule = { event = "projectTopBuilder", project = "restore-temple" } },
        { id = "keeper-of-the-rite", name = "Keeper of the Rite", description = "Helped raise 5 fallen heroes.", style = "gold", rule = { counter = "ritesAided", atLeast = 5 } },
        { id = "challenger", name = "Challenger", description = "Won an encounter in Challenge Mode.", style = "ember", rule = { counter = "challengeWins", atLeast = 1 } },
        { id = "glutton-for-punishment", name = "Glutton for Punishment", description = "Won 10 different encounters in Challenge Mode.", style = "ember", rule = { counter = "challengeWins", atLeast = 10 } },
        { id = "deathdefier", name = "Deathdefier", description = "Won an encounter in Deadly Mode.", style = "slate", rule = { counter = "deadlyWins", atLeast = 1 } },
    },
}
