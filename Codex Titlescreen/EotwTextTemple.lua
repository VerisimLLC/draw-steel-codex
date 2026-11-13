local mod = dmhub.GetModLoading()

--Encounter of the Week: the words of the Temple of Saint Llewellyn -- the town's
--6000-point community project (first rebuilt, then reconsecrated) and the
--Temple itself, where fallen heroes are raised by a Rite of Return.
--
--Code: EotwDowntime.lua (the project), EncounterOfTheWeek.lua (the map),
--EotwTemple.lua (the built Temple).
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
--EVERY LINE BELOW IS A PLACEHOLDER DRAFT (2026-11-12), waiting for real words.
--
--Code: UIText (DMHub Utils/UIText.lua). Design: TEMPLE_BRIEF.md.

local text = UIText.Define("EotwTextTemple")


----------------------------------------------------------------------------
-- THE MAP: the location's marker and heading
----------------------------------------------------------------------------

--While the town is still restoring it. The label is the name on the map
--marker (1-3 words); the title and tagline head the screen when it is opened.
text("eotw.locations.temple_site.label", [[Destroyed Temple]])
text("eotw.locations.temple_site.title", [[The Destroyed Temple]])
text("eotw.locations.temple_site.tagline", [[Saint Llewellyn's temple lies in ruins. Restore it, and the valiant knight may help Blackbottom's fallen rise from death.]])
--Once it is restored.
text("eotw.locations.temple.label", [[Saint Llewellyn's Temple]])
text("eotw.locations.temple.title", [[The Temple of Saint Llewellyn]])
text("eotw.locations.temple.tagline", [[Noble heroes felled in battle may rise once again.]])

----------------------------------------------------------------------------
-- THE BUILDING SITE: the card above the project
----------------------------------------------------------------------------

--A short call to action, shown large in italics.
text("downtime.temple_site.intro", [[Help restore the Destroyed Temple!]])
--One or two sentences on what it will be.
text("downtime.temple_site.community", [[Once the Temple is repaired, the town may resurrect its fallen heroes. Every noble hero of Blackbottom should lend a hand.]])

----------------------------------------------------------------------------
-- THE PROJECT: Restore the Temple
----------------------------------------------------------------------------

text("downtime.projects.restore_temple.title", [[Rebuild the Temple]])
--Where it is worked on, as in "Go to the Destroyed Temple to work on it."
text("downtime.projects.restore_temple.place", [[the Destroyed Temple]])
--Shown under its cost.
text("downtime.projects.restore_temple.benefit", [[The Temple of Saint Llewellyn opens for all who protect the weak. Fallen heroes can be raised there.]])
--The line under the title, and the same line once it is finished.
text("downtime.projects.restore_temple.blurb", [[This is a Community Project, everyone builds this together!]])
text("downtime.projects.restore_temple.blurb_maxed", [[The Temple of Saint Llewellyn is rebuilt!]])
--The big banner when the last roll finishes it, and the line under it.
text("downtime.projects.restore_temple.complete_banner", [[The Temple of Saint Llewellyn!]])
text("downtime.projects.restore_temple.complete_subtitle", [[Rebuilt by the heroes of Blackbottom. The fallen may yet come home.]])

----------------------------------------------------------------------------
-- THE PROJECT: its two stages
----------------------------------------------------------------------------

--The two stages' names (1-2 words each).
text("downtime.projects.restore_temple.stage_rebuilding", [[Rebuilding]])
text("downtime.projects.restore_temple.stage_reconsecration", [[Reconsecration]])
--Replaces the project's blurb during each stage.
text("downtime.projects.restore_temple.stage_reconsecration_blurb", [[The Temple must be made holy again: rites, records and a priesthood. Presence or Intuition.]])
text("downtime.projects.restore_temple.stage_rebuilding_blurb", [[The walls of the Temple must be rebuilt!]])
--The banner shown to the hero whose roll finishes the rebuilding (the first
--stage), and the line under it.
text("downtime.projects.restore_temple.stage_banner", [[Make the Temple holy again.]])
text("downtime.projects.restore_temple.stage_subtitle", [[The walls are rebuilt!]])

----------------------------------------------------------------------------
-- DISCORD: the building's name on the town's progress posts
----------------------------------------------------------------------------

--As it reads in the middle of a sentence: "Work on ___ is 50% done". The
--server writes these cards, so this name lives in its code, not here:
--cloudflare-game-server/src/discord-core.ts, COMMUNITY_PROJECT_NAMES
--("the Temple of Saint Llewellyn").

----------------------------------------------------------------------------
-- THE TEMPLE: raising the fallen (EotwTemple.lua)
----------------------------------------------------------------------------

--At the top of the Temple, large in italics.
text("temple.intro", [[Candles burn before Saint Llewellyn. Here, the valiant can be brought back from death.]])
--How it works, in a sentence or two.
text("temple.how", [[Begin a Rite of Return for one of your fallen heroes. Any hero may aid in this rite. When the rite completes, the hero will be resurrected.]])
text("temple.loading", [[Reading the Temple's ledger...]])
text("temple.error.not_connected", [[The Temple can't be reached right now. Try again in a moment.]])
--A hero's name when the game cannot find it.
text("temple.hero_fallback", [[A fallen hero]])
--Your Fallen: this player's fallen heroes.
text("temple.fallen.heading", [[Your Fallen]])
text("temple.fallen.empty", [[None of your heroes lie in the Graveyard.]])
text("temple.fallen.begin_button", [[Begin the Rite]])
text("temple.fallen.begin_confirm", [[Click again to begin]])
text("temple.fallen.rite_under_way", [[A Rite of Return is under way for this hero (see Rites Under Way).]])
text("temple.fallen.no_slot", [[You need a free hero slot to begin. Expand the Guild, or dismiss a hero.]])
--A Revenant (or a hero with Back From the Grave) whose killing blow was fire.
text("temple.fallen.fire", [[Fire destroyed this hero's body, so they will not awaken on their own.]])
--A Hakaan who chose their death (doomed).
text("temple.fallen.beyond", [[This hero met their doom. Nothing can bring them back.]])
--Undying heroes (Hakaan, Revenant, Vampire) come back at the Graveyard
--instead. {clock} is a time of day, like "9:40 PM".
text("temple.fallen.awaken_waiting", [[This hero will be ready to awaken at the Graveyard at {clock}.]])
text("temple.fallen.awaken_ready", [[This hero can be awakened now: go to the Graveyard.]])
--The rite's cost. {goal} is points, {level} the hero's level, {rolls} about how
--many Downtime rolls it takes.
text("temple.goal", [[Goal {goal} points (level {level}, about {rolls} rolls)]])
text("temple.goal_doubled", [[Raised {count} time(s) before: the goal is doubled each time.]])
--Rites Under Way: every rite in town.
text("temple.rites.heading", [[Rites Under Way]])
text("temple.rites.empty", [[No rites are under way.]])
text("temple.rites.show_all", [[Show all {count} rites]])
text("temple.rite.name_yours", [[{name} (yours)]])
text("temple.rite.name_of", [[{name}]])
text("temple.rite.progress", [[{points} of {goal} points ({percent}%)]])
text("temple.rite.helpers", [[Raised by the labour of: {names}]])
text("temple.rite.contributor", [[{hero} ({player})]])
text("temple.rite.no_helpers", [[None of your heroes has Downtime rolls to use right now.]])
--In the hero picker. {downtime} is how many Downtime Activities they have.
text("temple.helper_option", [[{name} ({downtime} Downtime)]])
text("temple.rite.roll_button", [[Spend 1 Downtime roll]])
--The dice's title.
text("temple.rite_title", [[Rite of Return for {name}]])
text("temple.rite.waiting_mine", [[The rite is complete, but your roster is full. Dismiss a hero, and then raise them.]])
text("temple.rite.waiting_other", [[The rite is complete. The hero will rise once their player has a free hero slot.]])
text("temple.rite.rise_button", [[Raise them]])
--Banners after a roll.
text("temple.banner.risen_title", [[{name} Returns!]])
text("temple.banner.risen_subtitle", [[The Rite of Return is complete.]])
text("temple.banner.complete_title", [[The Rite for {name} Is Complete]])
text("temple.banner.complete_subtitle", [[They rise once their player has a free hero slot.]])
text("temple.banner.breakthrough_subtitle", [[A free roll on the rite!]])

----------------------------------------------------------------------------
-- THE PROJECT: what heroes say after a roll
----------------------------------------------------------------------------

--Chosen by how far along the project is and how the roll went (hopeful: a
--good roll; neutral; frustrated: a poor roll). Three lines each.
--
--NOT SHOWN YET: these are not hooked up to rolls. Fill them in, then they
--get wired into the project (EotwDowntime.lua). Leave none empty.

--Reconsecration, first half (points 3000-4499).
text("downtime.lines.temple.reconsecration_early_hopeful_1", [[]])
text("downtime.lines.temple.reconsecration_early_hopeful_2", [[]])
text("downtime.lines.temple.reconsecration_early_hopeful_3", [[]])
text("downtime.lines.temple.reconsecration_early_neutral_1", [[]])
text("downtime.lines.temple.reconsecration_early_neutral_2", [[]])
text("downtime.lines.temple.reconsecration_early_neutral_3", [[]])
text("downtime.lines.temple.reconsecration_early_frustrated_1", [[]])
text("downtime.lines.temple.reconsecration_early_frustrated_2", [[]])
text("downtime.lines.temple.reconsecration_early_frustrated_3", [[]])

--Reconsecration, second half (points 4500-6000).
text("downtime.lines.temple.reconsecration_late_hopeful_1", [[]])
text("downtime.lines.temple.reconsecration_late_hopeful_2", [[]])
text("downtime.lines.temple.reconsecration_late_hopeful_3", [[]])
text("downtime.lines.temple.reconsecration_late_neutral_1", [[]])
text("downtime.lines.temple.reconsecration_late_neutral_2", [[]])
text("downtime.lines.temple.reconsecration_late_neutral_3", [[]])
text("downtime.lines.temple.reconsecration_late_frustrated_1", [[]])
text("downtime.lines.temple.reconsecration_late_frustrated_2", [[]])
text("downtime.lines.temple.reconsecration_late_frustrated_3", [[]])

--Rebuilding, first half (points 0-1499).
text("downtime.lines.temple.rebuilding_early_hopeful_1", [[]])
text("downtime.lines.temple.rebuilding_early_hopeful_2", [[]])
text("downtime.lines.temple.rebuilding_early_hopeful_3", [[]])
text("downtime.lines.temple.rebuilding_early_neutral_1", [[]])
text("downtime.lines.temple.rebuilding_early_neutral_2", [[]])
text("downtime.lines.temple.rebuilding_early_neutral_3", [[]])
text("downtime.lines.temple.rebuilding_early_frustrated_1", [[]])
text("downtime.lines.temple.rebuilding_early_frustrated_2", [[]])
text("downtime.lines.temple.rebuilding_early_frustrated_3", [[]])

--Rebuilding, second half (points 1500-2999).
text("downtime.lines.temple.rebuilding_late_hopeful_1", [[]])
text("downtime.lines.temple.rebuilding_late_hopeful_2", [[]])
text("downtime.lines.temple.rebuilding_late_hopeful_3", [[]])
text("downtime.lines.temple.rebuilding_late_neutral_1", [[]])
text("downtime.lines.temple.rebuilding_late_neutral_2", [[]])
text("downtime.lines.temple.rebuilding_late_neutral_3", [[]])
text("downtime.lines.temple.rebuilding_late_frustrated_1", [[]])
text("downtime.lines.temple.rebuilding_late_frustrated_2", [[]])
text("downtime.lines.temple.rebuilding_late_frustrated_3", [[]])

--The roll that finishes it.
text("downtime.lines.temple.done_1", [[]])
text("downtime.lines.temple.done_2", [[]])
text("downtime.lines.temple.done_3", [[]])
