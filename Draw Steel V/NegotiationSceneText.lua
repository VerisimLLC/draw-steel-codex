local mod = dmhub.GetModLoading()

--Negotiation scenes (NegotiationScene.lua, NegotiationSceneStage.lua): the words
--of the negotiation screen itself -- the meters, the buttons, the log. What the
--NPC and the heroes say is in each negotiation's own script, not here.
--The Encounter of the Week game and the town of Blackbottom both use these.
--
--HOW TO EDIT THIS FILE (for writers)
--
--  Each entry is:   text("an.id", [[the words]])
--
--  * Change only the words between [[ and ]]. Never change the id in quotes:
--    it is how the game finds the words.
--  * {name} is filled in by the game (a hero's name, a number, ...). Keep every
--    one, spelled exactly as it is; you may move it anywhere in the sentence.
--  * <b>...</b>, <i>...</i> and <color=...>...</color> are formatting. Keep
--    them, in pairs.
--  * A line break inside [[ ]] is a line break on screen.
--  * Use plain keyboard characters only: straight quotes ' and ", three dots
--    ..., a hyphen or a colon for a dash. Curly quotes, em dashes and other
--    special characters break the file.
--  * Lines starting with -- are notes for you; the game ignores them.
--
--Code: UIText (DMHub Utils/UIText.lua). Checked by tests/uitext_check.lua.

local text = UIText.Define("NegotiationSceneText")

----------------------------------------------------------------------------
-- THE METERS: how patient the NPC still is ({npc} is their name)
----------------------------------------------------------------------------

text("negscene.patience.none", [[{npc} is done listening.]])
text("negscene.patience.one", [[One weak word could end this.]])
text("negscene.patience.two", [[{npc}'s patience is thinning.]])
text("negscene.patience.three", [[{npc} is hearing you out.]])
text("negscene.patience.four", [[{npc} has time for you.]])
text("negscene.patience.five", [[{npc} is in no hurry.]])
--The names in front of the two meters.
text("negscene.patience_name", [[Patience]])
text("negscene.interest_name", [[Interest]])

--How interested the NPC is ({npc} is their name), from 0 (the talk is over)
--to 5 (won over).
text("negscene.interest.none", [[{npc} is done with you.]])
text("negscene.interest.one", [[{npc} is unmoved.]])
text("negscene.interest.two", [[{npc} is wary of you.]])
text("negscene.interest.three", [[{npc} is listening.]])
text("negscene.interest.four", [[{npc} is warming to you.]])
text("negscene.interest.five", [[{npc} is won over.]])

--What is on the table now. {shape} is the offer's name ("No, but...").
text("negscene.on_the_table", [[On the table: {shape}]])

----------------------------------------------------------------------------
-- THE ARGUMENTS: the cards the heroes choose from
----------------------------------------------------------------------------

text("negscene.argument.said", [[Already said]])
--{trait} is a motivation or pitfall the heroes have learned.
text("negscene.argument.avoid", [[Avoid: {trait}]])
text("negscene.argument.appeal", [[Appeals to: {trait}]])
--On a knack argument (one only some heroes can make): {requirement} is what a
--hero needs to make it ("you are skilled in Psionics"); the heroes who can
--are shown as tokens under it.
text("negscene.argument.knack_for", [[Knack: {requirement}]])
--Under an argument the selected hero has an edge on. {why} is what earns it,
--from the script's "|Edge:" line ("your Wealth is 2+"); several join with "; ".
text("negscene.argument.edge", [[Edge: {why}]])

--Under each hero's card: how often they have spoken.
text("negscene.hero.quiet", [[Has not spoken]])
text("negscene.hero.spoke_once", [[Spoke once]])
text("negscene.hero.spoke_many", [[Spoke {count} times]])

----------------------------------------------------------------------------
-- BUTTONS AND HEADINGS
----------------------------------------------------------------------------

text("negscene.read", [[Read them]])
--Before the first argument, where the party has Intelligence to spend.
text("negscene.spend_clue", [[Spend 1 Intelligence for a hint]])
text("negscene.noticed", [[What you've noticed]])
text("negscene.learned", [[What you've learned]])
text("negscene.so_far", [[So far]])
text("negscene.take_deal", [[Take the deal]])
text("negscene.continue", [[Continue]])
text("negscene.vote_deal", [[Take the deal]])
text("negscene.vote_talk", [[Keep talking]])
text("negscene.vote_refuse", [[Walk away]])
--Leaving the screen where nothing can be refused (the town): the talk ends
--with what is on the table now.
text("negscene.leave", [[Leave]])

----------------------------------------------------------------------------
-- WHAT HAPPENS: the lines in the speech box
----------------------------------------------------------------------------

text("negscene.read_found", [[{hero} sees it: {trait} matters here.]])
text("negscene.read_pushed", [[{hero} stares too long, and {npc} notices.]])
text("negscene.read_nothing", [[{hero} watches closely and learns nothing new.]])
--What a hint bought with Intelligence revealed.
text("negscene.clue_found", [[What you found out on the way here: {trait} matters.]])
text("negscene.argued", [[{hero}: {argument}]])
text("negscene.rolling", [[Choosing the words...]])
text("negscene.final_offer", [[This is the final offer.]])
text("negscene.voting", [[The party is deciding whether to take the deal.]])
text("negscene.deal", [[The deal is struck.]])
text("negscene.refused", [[The party walks away.]])
text("negscene.no_deal", [[No deal.]])
text("negscene.vote_yours", [[{text} You said: {choice}.]])
text("negscene.vote_waiting", [[{text} Waiting for: {players}.]])
text("negscene.split", [[The party was split, and {player} settled it. {text}]])

--The prompt over the argument cards.
text("negscene.prompt_wait", [[The table is waiting.]])
text("negscene.prompt_vote", [[The party is deciding.]])
text("negscene.prompt_argument", [[Choose an argument.]])
text("negscene.prompt_hero", [[Pick who speaks, then an argument.]])
--The same, when several players share the table.
text("negscene.prompt_hero_party", [[Talk it over, pick who speaks, then an argument.]])

--The "What you've learned" list and the "So far" log.
text("negscene.learned_motivation", [[+  Appeal to: {trait}]])
text("negscene.learned_pitfall", [[x  Avoid: {trait}]])
text("negscene.log", [[{hero}: {argument}]])

--What the NPC says when an argument has no line of its own for how it went.
text("negscene.reply.positive", [[That's a fair point.]])
text("negscene.reply.negative", [[I don't buy that.]])
text("negscene.reply.impatient", [[I've heard that before.]])

----------------------------------------------------------------------------
-- THE TEST
----------------------------------------------------------------------------

--The name of the test to read the NPC.
text("negscene.roll.read_name", [[Read Them]])
--The three results of a test.
text("negscene.roll.tier1", [[It falls short.]])
text("negscene.roll.tier2", [[It lands.]])
text("negscene.roll.tier3", [[It lands well.]])
--The roll dialog's description: {hero} rolls {name} ({test}).
text("negscene.roll.description", [[{hero}: {name}]])
