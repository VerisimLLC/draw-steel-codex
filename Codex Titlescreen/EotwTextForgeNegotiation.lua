local mod = dmhub.GetModLoading()

--Encounter of the Week town: everything said and shown at the BUILT Great
--Forge -- Giddlebrick Thundlestrom's greeting the first time a player comes
--to use it, his negotiation for a crafting station, and the workshop where
--heroes craft treasures. Code: EotwForge.lua.
--
--Lines marked DRAFT were written by Claude as a first pass, for you to
--rewrite as you like. Lines not marked are David's.
--
--HOW TO EDIT THIS FILE (for writers)
--
--  Each entry is:   text("an.id", [[the words]])
--
--  * Change only the words between [[ and ]]. Never change the id in quotes:
--    it is how the game finds the words.
--  * A line break inside [[ ]] is a line break on screen.
--  * Words in {braces}, like {hero} or {time}, are filled in by the game.
--    Keep them (you can move them around in the sentence).
--  * Use plain keyboard characters only: straight quotes ' and ", three dots
--    ..., a hyphen or a colon for a dash. Curly quotes, em dashes and other
--    special characters break the file.
--  * Lines starting with -- are notes for you; the game ignores them.
--  * Save, then restart the Codex to see a change.
--
--Code: UIText (DMHub Utils/UIText.lua). Checked by tests/uitext_check.lua.

local text = UIText.Define("EotwTextForgeNegotiation")

----------------------------------------------------------------------------
-- THE FIRST VISIT: Giddlebrick greets the player
----------------------------------------------------------------------------
--One of the player's heroes in town answers him. Which greeting plays
--depends on the player:
--  defender  one of their heroes helped defeat the demons at the Forge
--  builder   their heroes put 100 or more points into building it
--  stranger  neither
--Each greeting is three lines, then the hero picks what to say: push for a
--station (the negotiation starts), or leave (Giddlebrick answers and the
--player is back on the town map; next time the greeting plays again).
--The push and leave lines are also the two choices the player clicks, so
--keep them short enough to read at a glance.

--The defender.
text("forge.talk.defender.line1_npc", [[Well, if it isn't one of our town's heroes! I suppose you are here to make use of this Forge you helped build and defend then?]])
text("forge.talk.defender.line2_hero", [[I was hoping to make use of the Forge, yes.]])
text("forge.talk.defender.line3_npc", [[It's possible, it's possible. It's just that after the attack by the Demons, only some of our stations are back online. It will take a while. A while I say. So you might have to wait your turn.]])
text("forge.talk.defender.push_hero", [[Oh come now, after defending the Forge and the Town surely I can get access to one of the stations...]])
--DRAFT: the defender's way out, and Giddlebrick's answer.
text("forge.talk.defender.leave_hero", [[Fair enough. I'll come back once things have settled down.]])
text("forge.talk.defender.leave_npc", [[Do, do! You'll always have a friend at this Forge, you will. Mind the loose step on your way out.]])

--The builder.
text("forge.talk.builder.line1_npc", [[One of the Builders! Your name is written right here on this plaque now, isn't it? What can I do for you then?]])
text("forge.talk.builder.line2_hero", [[I was hoping to use the Forge to craft some items now that it's built.]])
text("forge.talk.builder.line3_npc", [[Hoping to use it? Why of course, of course, you didn't help build it just out of the goodness of your heart now did you? But did you hear what happened my friend? Demons attacked it! We are still recovering. I don't have all my crafting stations online yet. So you might just have to wait a bit...]])
text("forge.talk.builder.push_hero", [[Come now, I helped to build it, I'm sure you can find a station for me.]])
--DRAFT: the builder's way out, and Giddlebrick's answer.
text("forge.talk.builder.leave_hero", [[All right, I can wait. I'll come back another time.]])
text("forge.talk.builder.leave_npc", [[Good, good! Patience, my friend. Your name is on that plaque for good, and the Forge isn't going anywhere either.]])

--The stranger.
text("forge.talk.stranger.line1_npc", [[Well hello there, hello there friend, I'm Giddlebrick Thundlestrom, the head of the Tinkerer's Guild. I suppose you're here looking to craft a special something?]])
text("forge.talk.stranger.line2_hero", [[I was just looking around, but now you mention it, crafting a treasure would help me a lot...]])
text("forge.talk.stranger.line3_npc", [[See, the unfortunate thing my friend is that the Forge was attacked. Attacked by Demons! Many of them. Some of your friends participated in defending it, but let's see, I don't have your name on the list. So I think you will have to wait your turn while we reorganize the Forge. Not all our crafting stations are online you see...]])
text("forge.talk.stranger.push_hero", [[Surely I can convince you?]])
text("forge.talk.stranger.leave_hero", [[I understand, thank you.]])
--DRAFT: Giddlebrick's answer when the stranger leaves.
text("forge.talk.stranger.leave_npc", [[Come back any time, friend, any time. Who knows? A station may open up sooner than you think.]])

----------------------------------------------------------------------------
-- THE NEGOTIATION
----------------------------------------------------------------------------
--Written exactly like an Encounter of the Week negotiation (the EotW script
--reference, "Negotiation beats"), with these differences:
--  * Attitude is set by the game, whatever this says: Open for a defender,
--    Neutral for a builder, Suspicious for a stranger.
--  * What a deal does is fixed by the game, so the offers have no rules
--    ("|" lines) -- only what Giddlebrick says. The offer's line should say
--    what happens:
--      5  Yes, and   a station, and 100 points toward the first treasure
--      4  Yes        a station
--      3  Yes, but   turned away for 1 hour
--      2  No, but    turned away for 4 hours
--      1  No         turned away for a day
--      0  No, and    turned away for a day
--  * Played by, Language and Renown are not used here.
--  * The players can take the offer on the table at any time.
--
--KNACKS: arguments that suit particular heroes, written as in a montage
--(KNACKS_REFERENCE.md in EncounterOfTheWeek has every requirement you can
--write). They are the lines starting "|" after an argument's "|Test:".
--  |Allow: <requirement>   a knack argument: it shows, in purple with the
--                          requirement and a token for each hero who meets
--                          it, only while a hero at home does, and only they
--                          can make it.
--  |Edge: <requirement>    anyone can make the argument; a hero who meets
--                          the requirement rolls with an edge.
--Requirements read like "you can make fire or you can deal fire damage",
--"you are skilled in Mechanics", "your Wealth is 2 or higher". The words
--after the colon are never shown as they are, so they can stay plain.
--
--What the players see: "Want" under his name; "Opening" is his first line.
--Every Clue is listed under "What you've noticed" from the start: a hint at
--what he cares about (motivations) or can't stand (pitfalls), never the
--answer. Each argument's title is the card the players pick; "PC" is what
--the hero says; "Appeals" is hidden. Giddlebrick's reply depends on the
--roll: Lands, Falls short, Backfires (a pitfall always Fails).
--The motivations are Greed and Discovery; the pitfalls Brag and Flirt.
--
--DRAFT: all of it.
text("forge.negotiation.script", [[
# Negotiation: Giddlebrick Thundlestrom

Pronouns: he
Attitude: Suspicious
Want: A crafting station at the Great Forge.
Opening: Stations, stations, everybody wants a station! Half of them are still in pieces, you know. So tell me, friend: why should one of them go to you?

## Motivation: Greed
Clue: He keeps a fat ledger tucked under one arm, and taps it whenever anyone mentions coin.

## Motivation: Discovery
Clue: His pockets bulge with half-built gadgets, and he stops mid-sentence to fiddle with one.

## Pitfall: Brag
Clue: A smith across the hall is boasting about his own handiwork. Giddlebrick's beard bristles.

## Pitfall: Flirt
Clue: A passing smith calls him handsome. He goes red to the ears and tells her to mind her bellows.

## Argument: Offer the Guild a cut
Appeals: Greed
PC: Whatever I make here, the Guild gets a share of what it's worth. Call it rent.
|Test: Presence (Persuade, Lead)
Lands: A share, you say? Ha! Now you're speaking my language, my friend.
Falls short: A share of what, though? A share of nothing is nothing.
Backfires: Trying to buy your way to the front of the line? The Guild is not for sale!

## Argument: Pay for the coal up front
Appeals: Greed
PC: I'll pay for the coal, the metal and your time, before I so much as pick up a hammer.
|Test: Reason (Persuade, Society)
|Edge: your Wealth is 2 or higher
Lands: Up front! Well, well, well. That does make the ledger balance nicely.
Falls short: Coal is cheap, my friend. Stations are not.
Backfires: You think a place at my Forge can simply be bought? Hmph!

## Argument: Bring him a puzzle
Appeals: Discovery
PC: I found something on the road I can't make sense of. Something tells me you'd like a look at it.
|Test: Reason (Magic, Mechanics)
|Edge: you can decipher writing
Lands: Oh! Oh, now isn't that a curious thing. Let me see, let me see...
Falls short: Hm. Seen one like it. Seen many like it, in fact.
Backfires: That isn't a mystery, friend. That's a broken doorknob.

## Argument: Ask how the Forge works
Appeals: Discovery
PC: How does it all run, the Forge? I've never seen anything like it.
|Test: Intuition (Magic, Empathize)
Lands: Ha! Nobody ever asks! Sit, sit, I'll draw it out for you.
Falls short: It works very well, thank you very much.
Backfires: Guild secrets, my friend. Guild secrets! Who sent you to ask?

## Argument: Tell him of your great deeds
Appeals: Brag
PC: Surely you've heard what I've done? Half the town is talking about it.
Fails: Heroes, heroes! Everyone is a hero this week. My stations don't care.

## Argument: Charm him
Appeals: Flirt
PC: Has anyone told you that you run the finest forge in all of Blackbottom? And you look the part, too.
Fails: Flattery won't fix a cracked bellows! Next!

## Argument: Help with the repairs
Appeals: Nothing
PC: Let me help get the broken stations running again, and I'll use one once it's fixed.
|Test: Might (Blacksmithing, Mechanics)
|Edge: you can lift great weights or you can shape stone
Lands: Strong hands are always welcome, always! Grab that wrench.
Falls short: My tinkerers are already tripping over one another.
Backfires: The last helper put a hammer through a steam pipe. No, thank you.

## Argument: Talk shop
Appeals: Discovery
PC: I've worked a forge or two myself. What's that valve on the big bellows for? I've never seen one like it.
|Test: Reason (Alchemy, Blacksmithing, Mechanics)
|Allow: you were an Artisan or you are skilled in Alchemy, Blacksmithing, Carpentry, Jewelry or Mechanics
Lands: A crafter! A real one! That valve is my own design, my friend. Come, come, let me show you.
Falls short: It lets the air out. As valves do.
Backfires: Worked a forge, have you? Then you ought to know better than to poke at a hot valve.

## Argument: Relight a cold furnace
Appeals: Nothing
PC: One of your furnaces has gone cold since the attack. Let me get it burning again.
|Test: Reason (Magic, Mechanics)
|Allow: you can make fire or you can deal fire damage
Lands: Hot as the day we built it! Ha! A furnace like that needs someone to tend it, doesn't it?
Falls short: Warm, I'll give you that. Warm is not hot, my friend.
Backfires: Not so close! Not so... and there go my eyebrows.

## Argument: Ward the Forge against demons
Appeals: Nothing
PC: The demons came once. Let me lay a ward on the Forge so they think twice about coming back.
|Test: Intuition (Magic, Religion)
|Allow: you can deal holy damage or you can perform a blessing or you can sense the supernatural
Lands: A ward! Oh, the tinkerers will sleep easier for that. Easier, I say!
Falls short: Pretty lights. Will they stop a demon? I wonder.
Backfires: Was it meant to smell of brimstone? Because it does.

## Argument: Ask nicely
Appeals: Nothing
PC: Please. I need this, and I'll treat the station like it was my own.
|Test: Presence (Persuade, Empathize)
Lands: Well... when you put it like that, how can I say no?
Falls short: Everyone needs it, my friend. Everyone.
Backfires: Begging, at my Forge? Out of the way, out of the way!

## Offer: No, and
Out! Out of my Forge, and don't come back until tomorrow!

## Offer: No
No station. Not today. Try me again tomorrow, maybe I'll have forgotten all this.

## Offer: No, but
Not today, my friend. Come back in a few hours and we'll see.

## Offer: Yes, but
Fine, fine, you'll have your turn. Just not yet: come back in an hour.

## Offer: Yes
A station is yours, my friend. Mind the sparks!

## Offer: Yes, and
A station is yours, and I'll get your first piece started myself!
]])

----------------------------------------------------------------------------
-- THE WORKSHOP: the Forge's page once the player has a station
----------------------------------------------------------------------------
--DRAFT: every line in this section.

--The card on the Forge's page.
text("great_forge.workshop.title", [[The Workshop]])
text("great_forge.workshop.intro", [[Each hero crafts one treasure at a time. Every Downtime Activity spent here is a project roll toward finishing it.]])
text("great_forge.workshop.loading", [[Looking for Giddlebrick...]])
--Before Giddlebrick has found the player a station.
text("great_forge.workshop.no_access", [[Every station is spoken for. Giddlebrick decides who works here.]])
--The button that starts his greeting (or the negotiation). Short: a button.
text("great_forge.workshop.talk_button", [[Talk to Giddlebrick]])
text("great_forge.workshop.no_heroes_home", [[All your heroes are away with a party. Come back when one of them is in town.]])
--The talk went badly. {time} is the time left, e.g. 1:23:45.
text("great_forge.workshop.locked", [[Giddlebrick has turned you away for now. Try again in {time}.]])
text("great_forge.workshop.no_heroes", [[You have no heroes yet. Create one at the Hero's Guild.]])
--A "Yes, and" deal: the first treasure the player starts gets 100 points.
text("great_forge.workshop.bonus", [[Giddlebrick promised you a head start: your first treasure begins with 100 Project Points.]])

--Each hero's row. {item} is the treasure's name.
text("great_forge.workshop.your_hero", [[Your hero]])
text("great_forge.workshop.loading_hero", [[Loading...]])
text("great_forge.workshop.away", [[Away with a party]])
text("great_forge.workshop.idle", [[Not crafting anything yet]])
text("great_forge.workshop.crafting", [[Crafting {item}]])
text("great_forge.workshop.finished", [[{item} is ready to collect]])
--On the progress bar: {points} of {goal} Project Points.
text("great_forge.workshop.progress", [[{points} / {goal}]])
--The row's button. Short: a button.
text("great_forge.workshop.choose_button", [[Choose Treasure]])
text("great_forge.workshop.work_button", [[Work on It]])
--After a breakthrough: one more roll that costs no Downtime Activity.
text("great_forge.workshop.free_roll_button", [[Free Roll]])
text("great_forge.workshop.collect_button", [[Collect]])
--Why the button does nothing (its tooltip).
text("great_forge.workshop.no_downtime", [[No Downtime Activities left. Take a respite at the Blue Fish Inn to earn more.]])
text("great_forge.workshop.busy", [[One moment...]])
--Right-click an unfinished treasure: the menu entry, then the confirm dialog.
--{item} is the treasure, {hero} who was crafting it, {count} the Downtime
--Activities given back (1 per 40 Project Points; leftovers give nothing).
text("great_forge.workshop.cancel_menu", [[Cancel Project]])
text("great_forge.workshop.cancel_title", [[Cancel {item}?]])
text("great_forge.workshop.cancel_refund.one", [[{hero} gets back {count} Downtime Activity. The rest of the progress is lost.]])
text("great_forge.workshop.cancel_refund.other", [[{hero} gets back {count} Downtime Activities. The rest of the progress is lost.]])
text("great_forge.workshop.cancel_no_refund", [[{hero} gets nothing back: it takes 40 Project Points to earn back a Downtime Activity.]])
text("great_forge.workshop.cancel_confirm_button", [[Cancel Project]])
text("great_forge.workshop.cancel_keep_button", [[Keep Crafting]])
text("great_forge.workshop.not_ready", [[This hero is still loading. Try again in a moment.]])
text("great_forge.workshop.offline", [[Can't reach the town right now. Try again in a moment.]])
--Named on the dice: {hero} and {item}.
text("great_forge.workshop.roll_description", [[{hero} works on {item}]])
--The crafting roll dialog, under the big number once the roll finishes the
--treasure. {natural} is the number on the dice alone, {item} the treasure.
text("great_forge.workshop.result_done", [[natural {natural} -- {item} is finished!]])
--The same when the roll was a breakthrough: its extra roll comes back to {hero}.
text("great_forge.workshop.result_done_refunded", [[natural {natural} -- {item} is finished! The breakthrough refunds a Downtime Activity to {hero}]])

--The treasure picker. {hero} is who will craft it.
text("great_forge.workshop.picker_title", [[A Treasure for {hero}]])
text("great_forge.workshop.picker_intro", [[Hover a treasure to see what it does, then pick one to craft.]])
--Shown in the empty search box.
text("great_forge.workshop.search", [[Search treasures]])
text("great_forge.workshop.picker_none", [[No treasure matches that search.]])
--Under each treasure's name: {goal} Project Points to craft it.
text("great_forge.workshop.goal", [[{goal} Project Points]])
text("great_forge.workshop.start_button", [[Start Crafting {item}]])
text("great_forge.workshop.close_tooltip", [[Close]])

--Banners across the screen. The game shows them in capitals; keep each
--subtitle to one short line. {hero}, {item} and {time} are filled in.
text("great_forge.workshop.access_banner", [[A Station at the Forge]])
text("great_forge.workshop.access_subtitle", [[Giddlebrick finds you a place at the anvils.]])
text("great_forge.workshop.access_bonus_subtitle", [[And he'll start your first treasure himself!]])
--The talk ended badly: {time} until the player may try again.
text("great_forge.workshop.refused_banner", [[Turned Away]])
text("great_forge.workshop.refused_subtitle", [[Giddlebrick will hear you out again in {time}.]])
text("great_forge.workshop.breakthrough_banner", [[Breakthrough!]])
text("great_forge.workshop.breakthrough_subtitle", [[{hero} gets a free roll.]])
text("great_forge.workshop.done_banner", [[{item} Is Finished!]])
text("great_forge.workshop.done_subtitle", [[{hero} can collect it at the Forge.]])
--The 100-point head start finished the treasure on the spot.
text("great_forge.workshop.done_bonus_subtitle", [[Giddlebrick's head start finished it on the spot, {hero}!]])
text("great_forge.workshop.collected_banner", [[{item} Collected]])
text("great_forge.workshop.collected_subtitle", [[{hero} adds it to their gear.]])
--Something failed; the reason is shown under it.
text("great_forge.workshop.error_banner", [[Something Went Wrong]])
