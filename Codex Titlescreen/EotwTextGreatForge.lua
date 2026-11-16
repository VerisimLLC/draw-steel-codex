local mod = dmhub.GetModLoading()

--Encounter of the Week: the words of the Great Forge -- the town's
--10000-point building project, raised with the Tinkerer's Guild (a cabal of
--Gnome tinkerers): first planned, then built.
--
--Code: EotwDowntime.lua (the project), EncounterOfTheWeek.lua (the map).
--
--HOW TO EDIT THIS FILE (for writers)
--
--  Each entry is:   text("an.id", [[the words]])
--
--  * Change only the words between [[ and ]]. Never change the id in quotes:
--    it is how the game finds the words.
--  * {name} is filled in by the game (a hero's name, a number, ...). Keep every
--    one, spelled exactly as it is; you may move it anywhere in the sentence.
--  * A line break inside [[ ]] is a line break on screen.
--  * Use plain keyboard characters only: straight quotes ' and ", three dots
--    ..., a hyphen or a colon for a dash. Curly quotes, em dashes and other
--    special characters break the file.
--  * Lines starting with -- are notes for you; the game ignores them.
--
--EVERY LINE BELOW IS A PLACEHOLDER DRAFT (2026-11-10), waiting for real words.
--
--Code: UIText (DMHub Utils/UIText.lua). Design: EncounterOfTheWeek/EncounterOfTheWeek.md,
--"The Great Forge".

local text = UIText.Define("EotwTextGreatForge")

----------------------------------------------------------------------------
-- THE MAP: the location's marker and heading
----------------------------------------------------------------------------

--While the town is still building it. The label is the name on the map
--marker (1-3 words); the title and tagline head the screen when it is opened.
text("eotw.locations.great_forge_site.label", [[Great Forge Construction]])
text("eotw.locations.great_forge_site.title", [[The Great Forge Construction]])
text("eotw.locations.great_forge_site.tagline", [[The Tinkerer's Guild has agreed to help build the Great Forge. Lead them in building it so treasures may be forged.]])

--Once it is built.
text("eotw.locations.great_forge.label", [[Great Forge]])
text("eotw.locations.great_forge.title", [[The Great Forge]])
text("eotw.locations.great_forge.tagline", [[The Great Forge, a place to forge treasures of great value]])

----------------------------------------------------------------------------
-- THE BUILDING SITE: the card above the project
----------------------------------------------------------------------------

--A short call to action, shown large in italics.
text("downtime.great_forge_site.intro", [[Join the Tinkerer's Guild in building the Great Forge!]])
--One or two sentences on what it will be.
text("downtime.great_forge_site.community", [[The gnomes of the Tinkerer's Guild scurry back and forth, building the Forge. Help them in doing so!]])

----------------------------------------------------------------------------
-- THE PROJECT: Build the Great Forge
----------------------------------------------------------------------------

text("downtime.projects.build_great_forge.title", [[Build the Great Forge]])
--Where it is worked on, as in "Go to the Great Forge Construction to work on it."
text("downtime.projects.build_great_forge.place", [[the Great Forge Construction]])
--Shown under its cost.
text("downtime.projects.build_great_forge.benefit", [[The Great Forge opens for all the heroes of Blackbottom.]])
--The line under the title, and the same line once it is finished.
text("downtime.projects.build_great_forge.blurb", [[This is a Community Project, everyone builds this together!]])
text("downtime.projects.build_great_forge.blurb_maxed", [[The Great Forge is complete.]])
--The big banner when the last roll finishes it, and the line under it.
text("downtime.projects.build_great_forge.complete_banner", [[The Great Forge!]])
text("downtime.projects.build_great_forge.complete_subtitle", [[The Great Forge, built by the Heroes of Blackbottom and the Tinkerer's Guild.]])

----------------------------------------------------------------------------
-- THE PROJECT: its two stages
----------------------------------------------------------------------------

--The two stages' names (1-2 words each).
text("downtime.projects.build_great_forge.stage_planning", [[Planning]])
text("downtime.projects.build_great_forge.stage_building", [[Building]])
--Replaces the project's blurb during each stage.
text("downtime.projects.build_great_forge.stage_planning_blurb", [[The Tinkerer's Guild needs leaders, architects and mages to plan the Great Forge: Presence or Reason.]])
text("downtime.projects.build_great_forge.stage_building_blurb", [[The plans are drawn. Now the Great Forge must be built: Might or Agility.]])
--The banner shown to the hero whose roll finishes the planning, and the
--line under it.
text("downtime.projects.build_great_forge.stage_banner", [[The Plans Are Drawn!]])
text("downtime.projects.build_great_forge.stage_subtitle", [[The Great Forge goes up!]])

----------------------------------------------------------------------------
-- DISCORD: the building's name on the town's progress posts
----------------------------------------------------------------------------

--As it reads in the middle of a sentence: "Work on ___ is 50% done". The
--server writes these cards, so this name lives in its code, not here:
--cloudflare-game-server/src/discord-core.ts, COMMUNITY_PROJECT_NAMES
--("the Great Forge").

----------------------------------------------------------------------------
-- THE PROJECT: what heroes say after a roll
----------------------------------------------------------------------------

--Chosen by how far along the project is and how the roll went (hopeful: a
--good roll; neutral; frustrated: a poor roll). Three lines each; a line said
--recently is not repeated while another is left.
--
--NOT SHOWN YET: these are not hooked up to rolls. Fill them in, then they
--get wired into the project (EotwDowntime.lua). Leave none empty.

--Planning, first half (points 0-2499): what the planners, leaders and mages
--are doing with the gnomes of the Tinkerer's Guild.
text("downtime.lines.great_forge.planning_early_hopeful_1", [[]])
text("downtime.lines.great_forge.planning_early_hopeful_2", [[]])
text("downtime.lines.great_forge.planning_early_hopeful_3", [[]])
text("downtime.lines.great_forge.planning_early_neutral_1", [[]])
text("downtime.lines.great_forge.planning_early_neutral_2", [[]])
text("downtime.lines.great_forge.planning_early_neutral_3", [[]])
text("downtime.lines.great_forge.planning_early_frustrated_1", [[]])
text("downtime.lines.great_forge.planning_early_frustrated_2", [[]])
text("downtime.lines.great_forge.planning_early_frustrated_3", [[]])

--Planning, second half (points 2500-4999).
text("downtime.lines.great_forge.planning_late_hopeful_1", [[]])
text("downtime.lines.great_forge.planning_late_hopeful_2", [[]])
text("downtime.lines.great_forge.planning_late_hopeful_3", [[]])
text("downtime.lines.great_forge.planning_late_neutral_1", [[]])
text("downtime.lines.great_forge.planning_late_neutral_2", [[]])
text("downtime.lines.great_forge.planning_late_neutral_3", [[]])
text("downtime.lines.great_forge.planning_late_frustrated_1", [[]])
text("downtime.lines.great_forge.planning_late_frustrated_2", [[]])
text("downtime.lines.great_forge.planning_late_frustrated_3", [[]])

--Building, first half (points 5000-7499): the hands-on work -- alchemy,
--magic, the forge, stone and metal.
text("downtime.lines.great_forge.building_early_hopeful_1", [[]])
text("downtime.lines.great_forge.building_early_hopeful_2", [[]])
text("downtime.lines.great_forge.building_early_hopeful_3", [[]])
text("downtime.lines.great_forge.building_early_neutral_1", [[]])
text("downtime.lines.great_forge.building_early_neutral_2", [[]])
text("downtime.lines.great_forge.building_early_neutral_3", [[]])
text("downtime.lines.great_forge.building_early_frustrated_1", [[]])
text("downtime.lines.great_forge.building_early_frustrated_2", [[]])
text("downtime.lines.great_forge.building_early_frustrated_3", [[]])

--Building, second half (points 7500-10000).
text("downtime.lines.great_forge.building_late_hopeful_1", [[]])
text("downtime.lines.great_forge.building_late_hopeful_2", [[]])
text("downtime.lines.great_forge.building_late_hopeful_3", [[]])
text("downtime.lines.great_forge.building_late_neutral_1", [[]])
text("downtime.lines.great_forge.building_late_neutral_2", [[]])
text("downtime.lines.great_forge.building_late_neutral_3", [[]])
text("downtime.lines.great_forge.building_late_frustrated_1", [[]])
text("downtime.lines.great_forge.building_late_frustrated_2", [[]])
text("downtime.lines.great_forge.building_late_frustrated_3", [[]])

--The roll that finishes it.
text("downtime.lines.great_forge.done_1", [[]])
text("downtime.lines.great_forge.done_2", [[]])
text("downtime.lines.great_forge.done_3", [[]])
