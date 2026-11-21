local mod = dmhub.GetModLoading()

--Encounter of the Week: the words of the Training Grounds -- the town's
--6000-point building project (planned, then built) and the finished
--Training Grounds, where heroes Level up.
--
--Code: EotwDowntime.lua (the project), EotwTrainingGrounds.lua (the built
--Training Grounds), EncounterOfTheWeek.lua (the map), EotwHeroSheet.lua.
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
--  * Two entries ending .one and .other are the same line for a count of one
--    and for any other count.
--  * Use plain keyboard characters only: straight quotes ' and ", three dots
--    ..., a hyphen or a colon for a dash. Curly quotes, em dashes and other
--    special characters break the file.
--  * Lines starting with -- are notes for you; the game ignores them.
--  * An entry marked OPTIONAL can be emptied ([[]]) and the game will leave
--    that line out.
--
--Code: UIText (DMHub Utils/UIText.lua). Design: EncounterOfTheWeek/EncounterOfTheWeek.md,
--"The Training Grounds".

local text = UIText.Define("EotwTextTrainingGrounds")

----------------------------------------------------------------------------
-- THE MAP: the location's marker and heading
----------------------------------------------------------------------------

--While the town is still building it. The label is the name on the map
--marker (1-3 words); the title and tagline head the screen when it is opened.
text("eotw.locations.training_grounds_site.label", [[Training Grounds Construction]])
text("eotw.locations.training_grounds_site.title", [[Training Grounds Construction]])
text("eotw.locations.training_grounds_site.tagline", [[Every hero needs a place to learn and refine their skills. Gather to build the Training Grounds where that will be possible!]])

--Once it is built.
text("eotw.locations.training_grounds.label", [[Training Grounds]])
text("eotw.locations.training_grounds.title", [[Training Grounds]])
text("eotw.locations.training_grounds.tagline", [[The sounds of steel sharpening, swords clashing, and the fizzling sounds of the arcane. Come here to train and refine your skills. For heroes who are experienced enough to level up!]])

----------------------------------------------------------------------------
-- THE BUILDING SITE: the card above the project
----------------------------------------------------------------------------

--A short call to action, shown large in italics.
text("downtime.training_grounds_site.intro", [[Come together to build the Training Grounds so the Heroes of Blackbottom may increase their power!]])
--One or two sentences on what it will be.
text("downtime.training_grounds_site.community", [[Come together to plan the Training Grounds and then build them, so heroes will have a place to gain power.]])

----------------------------------------------------------------------------
-- THE PROJECT: Build the Training Grounds
----------------------------------------------------------------------------

text("downtime.projects.build_training_grounds.title", [[Build the Training Grounds]])
--Where it is worked on, as in "Go to the Training Grounds Site to work on it."
text("downtime.projects.build_training_grounds.place", [[the Training Grounds Construction]])
--Shown under its cost.
text("downtime.projects.build_training_grounds.benefit", [[The Training Grounds open for all residents of Blackbottom: You may level up your heroes there!]])
--The line under the title, and the same line once it is finished.
text("downtime.projects.build_training_grounds.blurb", [[This is a Community Project, everyone builds this together!]])
text("downtime.projects.build_training_grounds.blurb_maxed", [[The Training Grounds are complete.]])
--The big banner when the last roll finishes it, and the line under it.
text("downtime.projects.build_training_grounds.complete_banner", [[The Training Grounds!]])
text("downtime.projects.build_training_grounds.complete_subtitle", [[The Training Grounds, built by the Heroes of Blackbottom. Bring your heroes here to train and Level up.]])

----------------------------------------------------------------------------
-- THE PROJECT: its two stages (planning, then building)
----------------------------------------------------------------------------

--The two stages' names (1-2 words each).
text("downtime.projects.build_training_grounds.stage_planning", [[Planning]])
text("downtime.projects.build_training_grounds.stage_building", [[Building]])
--The line on the project card. Shared by any project with stages.
--{stage} is one of the names above, {number} the stage's number, {count}
--how many stages there are.
text("downtime.card.stage", [[Stage {number} of {count}: {stage}]])
--Replaces the project's blurb during each stage.
text("downtime.projects.build_training_grounds.stage_planning_blurb", [[The Training Grounds are being planned and architected. The thinkers and leaders are needed to design the Training Grounds: Reason or Presence.]])
text("downtime.projects.build_training_grounds.stage_building_blurb", [[The Training Grounds have been planned. Now those skilled in Craft and Trade must come and build them: Might or Agility.]])
--The banner shown to the hero whose roll finishes the planning, and the
--line under it.
text("downtime.projects.build_training_grounds.stage_banner", [[The Plans Have Been! Drawn!]])
text("downtime.projects.build_training_grounds.stage_subtitle", [[The Training Grounds go up! Bring Might or Agility, and skill with hammer or forge.]])

----------------------------------------------------------------------------
-- DISCORD: the building's name on the town's progress posts
----------------------------------------------------------------------------

--As it reads in the middle of a sentence: "Work on ___ is 50% done", "The
--town has finished ___!". The server writes these cards, so this name lives
--in its code, not here: cloudflare-game-server/src/discord-core.ts,
--COMMUNITY_PROJECT_NAMES ("the Training Grounds").

----------------------------------------------------------------------------
-- THE PROJECT: what heroes say after a roll
----------------------------------------------------------------------------

--Chosen by how far along the project is and how the roll went (hopeful: a
--good roll; neutral; frustrated: a poor roll). Three lines each; a line said
--recently is not repeated while another is left.
--
--Planning, first half (points 0-1499): surveying, plans, persuading people.
text("downtime.lines.training_grounds.planning_early_hopeful_1", [[I have paced the field and measured it twice. It seems the perfect size for training.]])
text("downtime.lines.training_grounds.planning_early_hopeful_2", [[An old wizardly fellow agreed to advise us. I just hope he knows what he is doing.]])
text("downtime.lines.training_grounds.planning_early_hopeful_3", [[An agreement from the magesterium not to tax the place. That is good news, good news indeed.]])
text("downtime.lines.training_grounds.planning_early_neutral_1", [[Well, we spent the day arguing about which field is used for which class of training. Arguing counts as progress, does it not?]])
text("downtime.lines.training_grounds.planning_early_neutral_2", [[Stables, fencing yards, weights, a place for studying the arcane. Is that everything we need?]])
text("downtime.lines.training_grounds.planning_early_neutral_3", [[Measure here, measure there. And then I find out they want them all in Hyrallian units?]])
text("downtime.lines.training_grounds.planning_early_frustrated_1", [[I write up the plans, and then someone uses them to wrap a fish?]])
text("downtime.lines.training_grounds.planning_early_frustrated_2", [[The neighbors don't seem to like us too much. Too many horses makes too much smell, they say.]])
text("downtime.lines.training_grounds.planning_early_frustrated_3", [[Well, all morning surveying a field. The wrong field.]])

--Planning, second half (points 1500-2999).
text("downtime.lines.training_grounds.planning_late_hopeful_1", [[The plans are nearly done. They are coming together. Soon we'll have our yards.]])
text("downtime.lines.training_grounds.planning_late_hopeful_2", [[The smiths' guild will lend us their forge, now will the stonemasons guild lend us their hammers?]])
text("downtime.lines.training_grounds.planning_late_hopeful_3", [[We have timer and iron and willing hands. It is almost time to build!]])
text("downtime.lines.training_grounds.planning_late_neutral_1", [[Just one more round of planning for the armory, I think. It's coming together...]])
text("downtime.lines.training_grounds.planning_late_neutral_2", [[Do we really have to account for every single nail?]])
text("downtime.lines.training_grounds.planning_late_neutral_3", [[We have allowed for twenty heroes to train at a time. That is enough, surely?]])
text("downtime.lines.training_grounds.planning_late_frustrated_1", [[A statue of the mayor? In our training grounds? I suppose getting out of taxes has its price...]])
text("downtime.lines.training_grounds.planning_late_frustrated_2", [[The lumber merchant doubled his price overnight. Back to finding a new lumber merchant...]])
text("downtime.lines.training_grounds.planning_late_frustrated_3", [[Three architects seemed like a good idea, until you realize that means we have three sets of plans...]])

--Building, first half (points 3000-4499): timber, iron, sawing, hammering.
text("downtime.lines.training_grounds.building_early_hopeful_1", [[The first fence posts are in, straight as a lance.]])
text("downtime.lines.training_grounds.building_early_hopeful_2", [[The forge is lit! The whole street can hear the anvils.]])
text("downtime.lines.training_grounds.building_early_hopeful_3", [[We raised the frame of the armory before lunch.]])
text("downtime.lines.training_grounds.building_early_neutral_1", [[We have to saw! We have to cut! We have to hammer! All in a day's work I suppose.]])
text("downtime.lines.training_grounds.building_early_neutral_2", [[Holes. Holes. Holes. Who knew that building a place like this would involve digging so many holes?]])
text("downtime.lines.training_grounds.building_early_neutral_3", [[Training dummies to hack. To skewer. Even to blow up. Lots of training dummies.]])
text("downtime.lines.training_grounds.building_early_frustrated_1", [[Hammering my thumb once was painful enough. But to hammer it again in the same day? Ouch!]])
text("downtime.lines.training_grounds.building_early_frustrated_2", [[I signed up for the sawing and the chopping. Not sure I signed up to do it in the rain.]])
text("downtime.lines.training_grounds.building_early_frustrated_3", [[One merchant gave us iron that was bent. Another was late with theirs. The third one didn't show at all.]])

--Building, second half (points 4500-6000).
text("downtime.lines.training_grounds.building_late_hopeful_1", [[Almost done. Almost done. Almost ready to train instead of build!]])
text("downtime.lines.training_grounds.building_late_hopeful_2", [[Almost skewed my finger with a nail twice today. But I didn't. And that's the important part.]])
text("downtime.lines.training_grounds.building_late_hopeful_3", [[Weapon racks set up with shiny weapons! Getting ready to train!]])
text("downtime.lines.training_grounds.building_late_neutral_1", [[I figured three layers of paint is enough?]])
text("downtime.lines.training_grounds.building_late_neutral_2", [[Sometimes it feels like you do nine parts in ten. Then it's time to do the other nine parts in ten.]])
text("downtime.lines.training_grounds.building_late_neutral_3", [[Down to raking the sand in the yards smooth. Have to keep the horses off it though.]])
text("downtime.lines.training_grounds.building_late_frustrated_1", [[Who let the goats into the stables then?]])
text("downtime.lines.training_grounds.building_late_frustrated_2", [[Hmmm I'm not sure having the archery range in range of the bakery was the best idea. Do we even need a bakery?]])
text("downtime.lines.training_grounds.building_late_frustrated_3", [[I suppose we didn't plan for the gate to fall off its hinges?]])

--The roll that finishes it.
text("downtime.lines.training_grounds.done_1", [[The Training Grounds are officially open!]])
text("downtime.lines.training_grounds.done_2", [[Let's blow a horn to welcome everyone to the training grounds!]])
text("downtime.lines.training_grounds.done_3", [[Time to open the Training Grounds!]])

----------------------------------------------------------------------------
-- THE TRAINING GROUNDS: the card listing your heroes
----------------------------------------------------------------------------

--The line at the top of the card, shown large in italics.
text("traininggrounds.intro", [[Here, your experience pays off as you learn new things.]])
--How it works, in a sentence or two.
text("traininggrounds.explainer", [[Rest at the Blue Fish Inn to turn Victories into experience. When a hero has enough experience, bring them here to Level up.]])
--The heading over the list of heroes. Shown in capitals.
text("traininggrounds.heroes_heading", [[Your Heroes]])

--On or beside a hero's XP bar. {xp} is the XP into this Level, {per} the XP
--a Level takes, {level} the next Level.
text("traininggrounds.row.xp", [[{xp} of {per} XP to Level {level}]])
--Replaces it when the hero has enough XP. {level} is the Level they can reach.
text("traininggrounds.row.ready", [[Ready for Level {level}!]])
--On a hero with XP for more than one Level. {count} is how many Levels.
text("traininggrounds.row.more_levels.one", [[Enough experience for {count} more Level after this one]])
text("traininggrounds.row.more_levels.other", [[Enough experience for {count} more Levels after this one]])

--The Level up button and its hover. {hero} is the hero's name, {level} the
--new Level.
text("traininggrounds.level_up_button", [[Level Up]])
text("traininggrounds.level_up_tooltip", [[Train {hero} to Level {level} and choose what they learn.]])
--The button for a Level up that was closed with choices left, and its hover.
text("traininggrounds.finish_button", [[Finish Your Level]])
text("traininggrounds.finish_tooltip", [[{hero} still has choices to make from their last Level up.]])

--Why a hero cannot Level, shown instead of a button.
--Not enough XP yet. {need} is the XP still needed, {level} the next Level.
text("traininggrounds.reason.xp", [[{need} more experience to Level {level}]])
--Already at the top Level.
text("traininggrounds.reason.maxlevel", [[A master of their craft: there is nothing left to teach.]])
--Out on an encounter right now.
text("traininggrounds.reason.away", [[This hero is away on an encounter. They can train when they return to Blackbottom.]])
--Still loading on this machine (rare, and brief).
text("traininggrounds.reason.notloaded", [[Still arriving...]])
--OPTIONAL: added when the hero has Victories not yet turned into XP.
--{count} is the Victories.
text("traininggrounds.reason.banked.one", [[{count} Victory to turn into experience: rest at the Blue Fish Inn.]])
text("traininggrounds.reason.banked.other", [[{count} Victories to turn into experience: rest at the Blue Fish Inn.]])

--No heroes yet.
text("traininggrounds.empty", [[You have no heroes to train yet. Visit the Hero's Guild.]])
--Offline.
text("traininggrounds.error.not_connected", [[Not connected to the town.]])
--The Level up could not start (the hero changed since the list was drawn).
text("traininggrounds.error.could_not_open", [[Error: Try again in a moment.]])

--After the Builder closes. {hero} is the hero's name, {level} the new Level.
--When every choice was made:
text("traininggrounds.done.finished", [[{hero} is now Level {level}!]])
--When it was closed with choices left:
text("traininggrounds.done.unfinished", [[{hero}'s training is saved. Come back to finish their choices.]])

--OPTIONAL flavor: a trainer greeting you when you arrive (one at random)...
text("traininggrounds.greeting_1", [["Feet apart, shield up! Oh, it's you. Come in."]])
text("traininggrounds.greeting_2", [["Back again? Good. The dummies missed you."]])
text("traininggrounds.greeting_3", [["You have your Victories, now let's hone them into skill shall we?"]])
--...and a cheer when a hero Levels up (one at random).
text("traininggrounds.cheer_1", [["Now THAT is a hero! That is a real hero!"]])
text("traininggrounds.cheer_2", [[Everyone roars approval at your new feats.]])
text("traininggrounds.cheer_3", [["Well trained! Now, off you go back out there. Try not to die."]])

----------------------------------------------------------------------------
-- THE HERO SHEET: a line that changes once the Training Grounds stand
----------------------------------------------------------------------------

--Under the XP bar of your own hero, when the next respite would give them
--enough XP for a Level (replaces "A respite would Level this Hero." once
--the Training Grounds are built).
text("herosheet.card.respite_line_grounds", [[After a respite, this hero can Level Up at the Training Grounds.]])
