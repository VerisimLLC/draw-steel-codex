local mod = dmhub.GetModLoading()

--Encounter of the Week: the words of the town -- the Encounter of the Week screen, the town map and its locations, the party lobby, the Hero's Guild and Graveyard, the Blue Fish Inn, downtime, leads and the Arcane Market.
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
--  * Two entries ending .one and .other are the same line for a count of one
--    and for any other count.
--  * Use plain keyboard characters only: straight quotes ' and ", three dots
--    ..., a hyphen or a colon for a dash. Curly quotes, em dashes and other
--    special characters break the file.
--  * Lines starting with -- are notes for you; the game ignores them.
--
--Code: UIText (DMHub Utils/UIText.lua). Checked by tests/uitext_check.lua.

local text = UIText.Define("EotwTextTown")

----------------------------------------------------------------------------
-- THE BETA SETTING: General Settings, before the town is ever opened
----------------------------------------------------------------------------

--The checkbox's name in General Settings.
text("eotw.settings.beta_name", [[Encounter of the Week Beta]])
--The help line under it.
text("eotw.settings.beta_help", [[Opt in to the Encounter of the Week beta.]])

----------------------------------------------------------------------------
-- OPENING THE TOWN: the loading screen
----------------------------------------------------------------------------

--The big title while the town loads.
text("eotw.veil.title", [[Encounter of the Week]])
--Under it. Dots are added after it, one by one, as it waits.
text("eotw.veil.loading", [[Loading]])

----------------------------------------------------------------------------
-- THE TOWN MAP: the plaque, the way out, the chat button
----------------------------------------------------------------------------

--The pill button at the top left that leaves the town. Short: a button.
text("eotw.town.back_to_title", [[Back to Title Screen]])
--The town's name, large, on the plaque at the top left.
text("eotw.town.plaque_name", [[Blackbottom]])
--The line under the town's name.
text("eotw.town.plaque_subtitle", [[Encounter of the Week]])
--How many players are in town. {count} is the number.
text("eotw.town.plaque_adventurers.one", [[{count} hero in town]])
text("eotw.town.plaque_adventurers.other", [[{count} heroes in town]])
--The button at the bottom right that opens the chat. Short: a button.
text("eotw.town.chat_button", [[Town Chat]])

----------------------------------------------------------------------------
-- THE TOWN MAP: the locations
----------------------------------------------------------------------------

--Each location has a label (the name plaque under its icon on the map;
--short), and most have a title (large, at the top of its full-screen scene)
--and a tagline (the line under the title).

text("eotw.locations.guild.label", [[Hero's Guild]])
text("eotw.locations.guild.title", [[The Hero's Guild]])
text("eotw.locations.guild.tagline", [[A fire in the hearth, shields on the walls, and a ledger of every hero sworn to the guild. Create a hero or take on a recruit.]])

text("eotw.locations.gate.label", [[Town Gate]])
text("eotw.locations.gate.title", [[The Town Gate]])
text("eotw.locations.gate.tagline", [[Parties muster at the Town Gate before they set off to face the Encounter of the Week. Join one that is forming, or gather your own.]])

text("eotw.locations.inn.label", [[Blue Fish Inn]])
text("eotw.locations.inn.title", [[The Blue Fish Inn]])
text("eotw.locations.inn.tagline", [[A nice warm fire, a hot meal and a bed that passes as comfortable. Take a respite here, or just quickly catch your breath before the next encounter.]])

text("eotw.locations.market.label", [[Arcane Market]])
text("eotw.locations.market.title", [[The Arcane Market]])
text("eotw.locations.market.tagline", [[Behind the honest shopfronts, carts and back rooms deal in potions, powders and stranger things. Ask the right questions and the right stall finds you.]])

text("eotw.locations.danger.label", [[Proving Pits]])
text("eotw.locations.danger.title", [[The Proving Pits]])
text("eotw.locations.danger.tagline", [[Untried horrors and visions of possible terrible futures dreamed up by the planners and strategicians who lurk in the Hero's Guild. Do they really foretell possible horrors that may soon come? Only practice: no Victories, no treasure, nothing kept. Try one, then tell the makers what you thought and shape future Encounters.]])

--The Graveyard opens as a dialog, so it has only a label.
text("eotw.locations.graveyard.label", [[Graveyard]])

--The Hall of Heroes, while the town is still building it.
text("eotw.locations.construction.label", [[Construction]])
text("eotw.locations.construction.title", [[The Construction]])
text("eotw.locations.construction.tagline", [[The town comes together to build the Hall of Heroes where the works and deeds of heroes shall be recorded!]])
--The Hall of Heroes, once it is built.
text("eotw.locations.hall.label", [[Hall of Heroes]])
text("eotw.locations.hall.title", [[The Hall of Heroes]])
text("eotw.locations.hall.tagline", [[Every party that has conquered an Encounter of the Week is remembered here.]])

--Why a location will not open (shown when it is clicked while locked).
--While the town is still listing the player's heroes:
text("eotw.locations.locked.checking_roster", [[The guild is still checking your roster...]])
--The Town Gate and the Proving Pits, with no hero yet:
text("eotw.locations.locked.need_hero_venture", [[You need a hero before you can venture out. Visit the Hero's Guild.]])
--The Blue Fish Inn, with no hero yet:
text("eotw.locations.locked.need_hero_rest", [[You need a hero before you can rest. Visit the Hero's Guild.]])
--The Arcane Market, with no hero yet:
text("eotw.locations.locked.need_hero_shop", [[You need a hero before you can shop. Visit the Hero's Guild.]])

----------------------------------------------------------------------------
-- THE TOWN MAP: the active heroes along the bottom
----------------------------------------------------------------------------

--Under a hero's name on their card when they are dying.
text("eotw.town.strip_dying", [[Dying: needs a respite]])
--The tooltip on the card's dismiss button.
text("eotw.town.strip_dismiss_tooltip", [[Dismiss Hero: send them back to the guild.]])
--Where the cards would be, with no heroes at all:
text("eotw.town.strip_no_heroes", [[You have no heroes yet. Visit the Hero's Guild to create or recruit one.]])
--Where the cards would be, with heroes but none active:
text("eotw.town.strip_none_active", [[None of your heroes are active. Visit the Hero's Guild to choose up to four.]])

----------------------------------------------------------------------------
-- A LOCATION'S SCENE: the header
----------------------------------------------------------------------------

--The pill button at the top left of a scene. Short: a button.
text("eotw.scene.back_to_town", [[Back to Town]])
--The small spaced-out line above the location's title.
text("eotw.scene.overline", [[BLACKBOTTOM]])

----------------------------------------------------------------------------
-- THE CHAT DRAWER
----------------------------------------------------------------------------

--The drawer's title (in town).
text("eotw.chat.title", [[Town Chat]])
--The two tabs, while the player is in a party. Short: tabs.
text("eotw.chat.tab_town", [[Town Chat]])
text("eotw.chat.tab_game", [[Game Chat]])
--The small red marker after a tab's name when it has unread messages.
text("eotw.chat.tab_new", [[NEW]])
--The small red marker on the line between read and unread messages.
text("eotw.chat.new_divider", [[NEW]])
--The line above the messages: who is in town. {count} is how many, {names}
--their names.
text("eotw.chat.presence_town", [[Here now ({count}): {names}]])
text("eotw.chat.presence_empty", [[Nobody is here yet.]])
--On the Game Chat tab: who is in the party.
text("eotw.chat.presence_party", [[In this party ({count}): {names}]])
--After a party member's name when they are not in town.
text("eotw.chat.presence_away", [[(away)]])
--The message box's placeholder.
text("eotw.chat.placeholder", [[Say something...]])
--The message box's placeholder when town chat is also posted to Discord.
text("eotw.chat.placeholder_discord", [[Say something... (also posted to Discord)]])
--The small tag after the name of someone writing from Discord.
text("eotw.chat.discord_tag", [[DISCORD]])
--After a message that was edited.
text("eotw.chat.edited", [[(edited)]])
--A message's time. {time} is like 3:42.
text("eotw.chat.time_am", [[{time} AM]])
text("eotw.chat.time_pm", [[{time} PM]])
--In place of the chat when the app is too old for it.
text("eotw.chat.engine_update", [[Chat requires the lobby engine update.]])

--The connection line.
text("eotw.status.engine_update", [[Engine update required]])
text("eotw.status.disconnected", [[Disconnected from the town.]])
text("eotw.status.connecting", [[Connecting to the town...]])

----------------------------------------------------------------------------
-- THE TOWN GATE: the board
----------------------------------------------------------------------------

--The board's title.
text("eotw.gate.board_title", [[Encounter of the Week]])
--The small line at the top of the week's banner.
text("eotw.gate.week_overline", [[This Week's Encounter]])
--In the banner before an encounter is set.
text("eotw.gate.week_not_posted", [[The guild has not posted this week's encounter yet. Check back soon.]])
--The board's buttons. Short: buttons.
text("eotw.gate.form_party_button", [[Form a Party]])
text("eotw.gate.past_button", [[Past Encounters]])
--The error after Form a Party before an encounter is set.
text("eotw.gate.week_not_posted_error", [[This week's encounter has not been posted yet.]])
--When nobody is forming a party at the Gate.
text("eotw.gate.no_parties", [[No parties are forming right now. Form one and others can join you!]])

--Section headings on both boards (shown in capitals). Short: headings.
text("eotw.board.parties_forming", [[Parties Forming]])
text("eotw.board.underway", [[Encounters Underway]])
--In place of the board when the app is too old for it.
text("eotw.board.engine_update", [[This build of the Codex does not include the lobby engine update.]])

--Who made a community encounter, under its title. {module} is the module's
--name, {author} its author.
text("eotw.encounter.credit", [[From the module {module}]])
text("eotw.encounter.credit_by", [[From the module {module} by {author}]])

--An encounter in several parts: a part's name, on its chip and after the
--encounter's name. {number} is the part's number, {title} its title.
text("eotw.series.part", [[Part {number}]])
text("eotw.series.part_titled", [[Part {number}: {title}]])
--The tooltip on a locked part. {part} is the part to win first.
text("eotw.series.part_locked", [[Win Part {part} to unlock this part.]])
--The tooltip on a part already won.
text("eotw.series.part_won_tooltip", [[Your party has won this part.]])

----------------------------------------------------------------------------
-- THE PROVING PITS: the board
----------------------------------------------------------------------------

--The board's title.
text("eotw.pits.board_title", [[The Proving Pits]])
--The note at the top of the board, and wherever a Proving Pits party forms.
text("eotw.pits.practice_note", [[The Proving Pits are practice. Heroes earn no Victories, keep no treasure and carry nothing else home. Afterwards you can vote on the encounter and leave feedback for its creator.]])
--When nobody is forming a party in the Proving Pits.
text("eotw.pits.no_parties", [[Nobody is in the Proving Pits right now. Pick an encounter below to form a party.]])
--Section heading (shown in capitals). Short: a heading.
text("eotw.pits.encounters_to_try", [[Encounters to Try]])
text("eotw.pits.gathering", [[Gathering the encounters...]])
text("eotw.pits.none_submitted", [[No new encounters have been submitted. Publish one as an Encounter of the Week module and it will appear here.]])
--One encounter's row. {module} is its module's name, {author} its author.
text("eotw.pits.row_byline", [[{module} by {author}]])
text("eotw.pits.row_not_tried", [[Not yet tried]])
--{up} and {down} are its votes, {count} how often it was played.
text("eotw.pits.row_stats.one", [[{up} up, {down} down -- played {count} time]])
text("eotw.pits.row_stats.other", [[{up} up, {down} down -- played {count} times]])
text("eotw.pits.row_form_party_button", [[Form a Party]])
--The board's button for players who published encounters. Short: a button.
text("eotw.pits.creator_feedback_button", [[Feedback on Your Encounters]])

----------------------------------------------------------------------------
-- A PARTY'S ROW on a board
----------------------------------------------------------------------------

--After the party's name.
text("eotw.party.row_tag_private", [[(private)]])
text("eotw.party.row_tag_launched", [[(launched)]])
--Under the party's name. {host} is the host's name, {filled}/{total} the
--hero slots; {encounter} is " -- " and the encounter's name, or nothing.
text("eotw.party.row_byline", [[Hosted by {host} -- {filled}/{total} heroes{encounter}]])
--The row's buttons. Short: buttons.
text("eotw.party.row_open_button", [[Open]])
text("eotw.party.row_join_button", [[Join]])

--The player's own game in progress, at the top of the Gate's board.
text("eotw.resume.heading", [[Your game in progress]])
--Its name when it has none.
text("eotw.resume.fallback_name", [[Your game]])
text("eotw.resume.resume_button", [[Resume]])
text("eotw.resume.abandon_button", [[Abandon]])
--The Abandon button after one click: click again to confirm.
text("eotw.resume.abandon_confirm", [[Really?]])

----------------------------------------------------------------------------
-- A PARTY'S VIEW: the party the player is in
----------------------------------------------------------------------------

--The board's title while in a party.
text("eotw.party.board_title", [[Your Party]])
--After the party's name.
text("eotw.party.view_tag_private", [[(private)]])
text("eotw.party.view_tag_launched", [[(launched)]])
--Under the party's name. {host} is the host, {players} the members' names;
--{encounter} is " -- " and the encounter's name, or nothing.
text("eotw.party.view_byline", [[Hosted by {host} -- players: {players}{encounter}]])
text("eotw.party.view_byline_no_players", [[Hosted by {host} -- players: none yet{encounter}]])
--The heading over the hero cards. {filled}/{total} are the slots,
--{needed} how many heroes the party needs.
text("eotw.party.slots_heading", [[Hero Slots ({filled}/{total} filled; {needed} needed to begin)]])

--On a hero card.
--Under the card's name: whose hero it is. {player} is their name.
text("eotw.party.card_controlled_by", [[Controlled by {player}]])
--The small chip on a premade hero's card. Short: shown in capitals.
text("eotw.party.card_pregen_chip", [[Pregen]])
--On a hero who has already won this encounter.
text("eotw.party.card_already_completed", [[Already Completed]])
--After the encounter's name in the games list and the party's byline, for
--a Challenge Mode party. {encounter} is the encounter's name.
text("eotw.party.challenge_suffix", [[{encounter} (Challenge Mode)]])
--Under the encounter's story in a Challenge Mode party.
text("eotw.party.challenge_note", [[Challenge Mode: an especially lethal version of this encounter. A hero's first win in Challenge Mode is worth an extra Victory, and a hero who has never won this encounter earns both at once.]])
--Tooltips on the card's hover buttons.
text("eotw.party.card_remove_tooltip", [[Remove from the lineup]])
text("eotw.party.card_kick_tooltip", [[Kick {player} from the game (removes all their heroes)]])
text("eotw.party.card_kick_tooltip_unnamed", [[Kick this player from the game (removes all their heroes)]])
--The "+" card that adds a hero. Short: under the plus.
text("eotw.party.add_card_label", [[Add Hero]])
--The "+" card's tooltip, and the error on clicking it, once the player
--has 4 heroes in the party.
text("eotw.party.add_card_tooltip", [[You can claim up to 4 heroes. Other players can add more.]])
text("eotw.party.add_card_full", [[You can claim at most 4 heroes. Other players can add more.]])

--A member who has not added a hero yet. {player} is their name.
text("eotw.party.member_no_heroes", [[{player} -- no heroes yet]])
text("eotw.party.kick_button", [[Kick]])

--While the host sets the game up.
text("eotw.party.starting", [[The game is starting: the host is setting up the encounter. You will enter automatically when it is ready...]])
text("eotw.party.entering", [[Entering the game...]])

--The horn: the host calls for more heroes.
text("eotw.party.horn_button", [[Blow the Horn]])
text("eotw.party.horn_tooltip", [[Call for more heroes in town and on Discord. The party waits until it is full or the time you choose runs out.]])
--How long to wait. {minutes} is 2, 5 or 10. Short: a button.
text("eotw.party.horn_wait_button", [[Wait {minutes} min]])
text("eotw.party.horn_cancel_button", [[Cancel]])
--The countdown everyone in the party sees. {time} is like 4:59.
text("eotw.party.horn_waiting", [[The horn sounds! Waiting {time} for more heroes to join -- the party can begin when it is full or time runs out.]])
text("eotw.party.horn_sounded", [[The horn has sounded.]])
text("eotw.party.horn_full", [[The horn has sounded and the party is full.]])

--The party's buttons. Short: buttons.
text("eotw.party.join_button", [[Join Game]])
text("eotw.party.begin_button", [[Begin]])
text("eotw.party.rejoin_button", [[Re-join]])
text("eotw.party.invite_button", [[Invite Friends]])
text("eotw.party.invite_tooltip", [[Invite Steam friends to join this party.]])
--The host's button, which disbands the party, and a member's.
text("eotw.party.abandon_button", [[Abandon]])
text("eotw.party.leave_button", [[Leave]])
--The host's Abandon button after one click: click again to confirm.
text("eotw.party.abandon_confirm", [[Really?]])

--Errors after Begin. {time} is like 4:59; {filled}/{total} the slots;
--{needed} how many heroes the party needs.
text("eotw.party.begin_horn_sounding", [[The horn is still sounding: the party can begin when it is full or in {time}.]])
text("eotw.party.begin_too_many", [[At most {total} heroes can begin ({filled} filled).]])
text("eotw.party.begin_too_few", [[Need at least {needed} heroes to begin ({filled}/{total} filled).]])
--When the party the player was looking at is gone.
text("eotw.party.gone", [[That game is no longer available.]])

----------------------------------------------------------------------------
-- ADD A HERO: picking a hero for the party
----------------------------------------------------------------------------

text("eotw.add_hero.title", [[Add a Hero]])
text("eotw.add_hero.your_heroes", [[Your Heroes]])
text("eotw.add_hero.none_free", [[No heroes are free to join. Visit the Hero's Guild to create or recruit one.]])
--The heroes who cannot join because they are dying. {names} is their names.
text("eotw.add_hero.dying.one", [[{names} is dying and must rest at the Blue Fish Inn before setting out again.]])
text("eotw.add_hero.dying.other", [[{names} are dying and must rest at the Blue Fish Inn before setting out again.]])
--A dying hero's name when the game cannot find it.
text("eotw.add_hero.dying_fallback_name", [[A hero]])
text("eotw.add_hero.cancel_button", [[Cancel]])

----------------------------------------------------------------------------
-- FORM A PARTY: the create dialog
----------------------------------------------------------------------------

text("eotw.create.title", [[Form a Party]])
text("eotw.create.name_placeholder", [[Name your party...]])
--The party's name, filled in for the player. {player} is their name.
text("eotw.create.default_name_player", [[{player}'s Party]])
--The party's name when the player's name is unknown.
text("eotw.create.default_name", [[Encounter of the Week]])
text("eotw.create.public_check", [[Public party (anyone can join)]])
--The Challenge Mode checkbox, offered once the player has won the
--encounter, and its tooltip.
text("eotw.create.challenge_check", [[Challenge Mode]])
text("eotw.create.challenge_tooltip", [[Play an especially lethal version of this encounter. Gain an extra victory point the first time you win!]])
--A warning, when the player already has a game.
text("eotw.create.replace_warning", [[Creating a new game will permanently delete your current Encounter of the Week game.]])
text("eotw.create.create_button", [[Create]])
text("eotw.create.cancel_button", [[Cancel]])
--Status lines while the party is made.
text("eotw.create.part_locked", [[That part is locked.]])
text("eotw.create.reserving", [[Reserving your game...]])
text("eotw.create.creating", [[Creating the game...]])
--{message} is the reason the server gave.
text("eotw.create.list_failed", [[Could not list the game: {message}]])
text("eotw.create.create_failed", [[The game could not be created. Please try again.]])

----------------------------------------------------------------------------
-- DIALOGS over the town
----------------------------------------------------------------------------

--The button that closes a dialog with no other buttons.
text("eotw.dialog.close_button", [[Close]])

--Past Encounters (the Town Gate's button).
text("eotw.past.title", [[Past Encounters]])
text("eotw.past.none", [[There are no past Encounters of the Week yet.]])
text("eotw.past.form_party_button", [[Form a Party]])

--Feedback on Your Encounters (the Proving Pits' button for creators).
text("eotw.feedback.title", [[Feedback on Your Encounters]])
text("eotw.feedback.loading", [[Asking the Proving Pits...]])
text("eotw.feedback.not_tried", [[Nobody has tried it yet.]])
--{up} and {down} are the votes, {count} how often it was played.
text("eotw.feedback.stats.one", [[{up} up, {down} down -- played {count} time]])
text("eotw.feedback.stats.other", [[{up} up, {down} down -- played {count} times]])
--How one player voted; shown as {vote} below.
text("eotw.feedback.vote_up", [[voted up]])
text("eotw.feedback.vote_down", [[voted down]])
text("eotw.feedback.no_vote", [[no vote]])
--One player's feedback. {player} is their name, {feedback} what they wrote.
text("eotw.feedback.entry", [[<b>{player}</b> ({vote}): {feedback}]])
text("eotw.feedback.entry_no_text", [[<b>{player}</b> ({vote})]])
--{message} is the reason the server gave.
text("eotw.feedback.load_failed", [[Could not load the feedback: {message}]])

----------------------------------------------------------------------------
-- THE PROVING PITS DEBRIEF: back in town after a Proving Pits game
----------------------------------------------------------------------------

text("eotw.debrief.title", [[Proving Pits Debrief]])
--Under the encounter's name: how it went.
text("eotw.debrief.result_victory", [[Your party survived the Proving Pits. It was practice: nothing was awarded.]])
text("eotw.debrief.result_defeat", [[The Proving Pits got the better of your party. It was practice: nothing was awarded.]])
text("eotw.debrief.result_left", [[Your party left the Proving Pits. It was practice: nothing was awarded.]])
text("eotw.debrief.how_was_it", [[How was it?]])
--The two vote buttons. Short: buttons.
text("eotw.debrief.upvote", [[Upvote]])
text("eotw.debrief.downvote", [[Downvote]])
text("eotw.debrief.feedback_heading", [[Feedback for its creator (optional)]])
text("eotw.debrief.feedback_placeholder", [[What worked? What would make it better?]])
text("eotw.debrief.send_button", [[Send]])
text("eotw.debrief.skip_button", [[Skip]])
text("eotw.debrief.sending", [[Sending...]])
--{message} is the reason the server gave.
text("eotw.debrief.send_failed", [[Could not send: {message}]])

----------------------------------------------------------------------------
-- WHILE YOU WERE AWAY: a game the player left that their party finished
----------------------------------------------------------------------------

text("eotw.away.title", [[While You Were Away]])
--{encounter} is the encounter's name.
text("eotw.away.intro_victory", [[Your party finished <b>{encounter}</b> after you left, with your heroes fighting on as free agents, and won.]])
text("eotw.away.intro_defeat", [[Your party finished <b>{encounter}</b> after you left, with your heroes fighting on as free agents, and was defeated.]])
--The encounter's name when the game cannot find it.
text("eotw.away.encounter_fallback", [[your Encounter of the Week]])
--One line per hero. {hero} is the hero's name; {results} is the pieces
--below, joined with "; ".
text("eotw.away.hero_line", [[<b>{hero}</b>: {results}]])
text("eotw.away.hero_line_nothing", [[<b>{hero}</b>]])
--The pieces of a hero's line.
text("eotw.away.hero_fell", [[fell in battle]])
text("eotw.away.hero_victories.one", [[{count} Victory]])
text("eotw.away.hero_victories.other", [[{count} Victories]])
text("eotw.away.hero_no_victory", [[no Victory (already completed)]])
--{items} is the treasures found, joined with commas.
text("eotw.away.hero_found", [[found {items}]])
text("eotw.away.hero_wounded", [[came back wounded]])
--A hero's name, or a treasure's, when the game cannot find it.
text("eotw.away.hero_fallback_name", [[Your hero]])
text("eotw.away.item_fallback", [[an item]])
--The hint under the heroes: a win, a loss, a win where some heroes fell.
text("eotw.away.hint_victory", [[Claim the victory for your heroes, or count the game as abandoned and leave it be.]])
text("eotw.away.hint_defeat", [[Accept the defeat, and your fallen heroes are laid to rest in the Graveyard; or count the game as abandoned and leave it be.]])
text("eotw.away.hint_victory_fallen", [[Claim the victory for your heroes, and your fallen heroes are laid to rest in the Graveyard; or count the game as abandoned and leave it be.]])
--The buttons. Short: buttons.
text("eotw.away.claim_victory_button", [[Claim the Victory]])
text("eotw.away.accept_defeat_button", [[Accept the Defeat]])
text("eotw.away.abandon_button", [[Count as Abandoned]])

----------------------------------------------------------------------------
-- THE BETA SURVEY: after a finished game
----------------------------------------------------------------------------

text("eotw.survey.title", [[Encounter of the Week Survey]])
--Under the encounter's name: how it went, then the invitation.
text("eotw.survey.intro_victory", [[Your party won. Encounter of the Week is in beta, and a minute of your time helps us make it better. Every question is optional.]])
text("eotw.survey.intro_defeat", [[Your party was defeated. Encounter of the Week is in beta, and a minute of your time helps us make it better. Every question is optional.]])
text("eotw.survey.intro_left", [[You left the encounter. Encounter of the Week is in beta, and a minute of your time helps us make it better. Every question is optional.]])

--Asked only when the player left the game. Each answer is a short button.
text("eotw.survey.leave.prompt", [[What made you leave?]])
text("eotw.survey.leave.time", [[Ran out of time]])
text("eotw.survey.leave.not_fun", [[Wasn't enjoying it]])
text("eotw.survey.leave.bugs", [[Bugs or problems]])
text("eotw.survey.leave.doomed", [[I saw the writing on the wall, I knew I was going to lose :)]])
text("eotw.survey.leave.other", [[Something else]])
text("eotw.survey.leave.comment_placeholder", [[Anything to add? (optional)]])

text("eotw.survey.length.prompt", [[How did the length of the session feel?]])
text("eotw.survey.length.too_short", [[Too short]])
text("eotw.survey.length.about_right", [[About right]])
text("eotw.survey.length.too_long", [[Too long]])

text("eotw.survey.difficulty.prompt", [[Were you satisfied with the difficulty?]])
text("eotw.survey.difficulty.too_easy", [[No, too easy]])
text("eotw.survey.difficulty.satisfied", [[Yes, it felt right]])
text("eotw.survey.difficulty.too_hard", [[No, too hard]])

text("eotw.survey.bugs.prompt", [[Did you run into any bugs?]])
text("eotw.survey.bugs.none", [[No bugs]])
text("eotw.survey.bugs.minor", [[Minor annoyances]])
text("eotw.survey.bugs.disruptive", [[They got in the way]])
text("eotw.survey.bugs.ruined", [[They ruined the session]])
--The comment box, shown for any answer but No bugs.
text("eotw.survey.bugs.comment_placeholder", [[What went wrong? (optional)]])

text("eotw.survey.ui.prompt", [[Was the interface clear?]])
text("eotw.survey.ui.clear", [[Clear]])
text("eotw.survey.ui.mostly", [[Mostly clear]])
text("eotw.survey.ui.confusing", [[Often confusing]])
--The comment box, shown for any answer but Clear.
text("eotw.survey.ui.comment_placeholder", [[What was confusing? (optional)]])

text("eotw.survey.again.prompt", [[Do you want to keep playing Encounter of the Week?]])
text("eotw.survey.again.yes", [[Yes]])
text("eotw.survey.again.maybe", [[Maybe]])
text("eotw.survey.again.no", [[No]])

text("eotw.survey.anything_else", [[Anything else you'd like to tell us?]])
text("eotw.survey.anything_else_placeholder", [[Optional]])
text("eotw.survey.send_button", [[Send]])
text("eotw.survey.no_thanks_button", [[No thanks]])
text("eotw.survey.sending", [[Sending...]])
--{message} is the reason the server gave.
text("eotw.survey.send_failed", [[Could not send: {message}]])

----------------------------------------------------------------------------
-- THE BLUE FISH INN APPEARS: after heroes first come home
----------------------------------------------------------------------------

--What the most wounded hero says, typed out in the speech box.
text("eotw.inn_reveal.line", [[That was a tough challenge! We should head to the Blue Fish Inn to rest before continuing on more adventures.]])

----------------------------------------------------------------------------
-- WELCOME: the first time a player opens the town
----------------------------------------------------------------------------

text("eotw.welcome.title", [[Welcome to Encounter of the Week]])
text("eotw.welcome.intro", [[Play Draw Steel by yourself or with a few friends, or people you meet along the way. This game mode is experimental and in beta. Please report bugs using Feedback in the menus.]])
--{link} is the link below, underlined.
text("eotw.welcome.discord", [[Discuss Encounter of the Week in the {link}!]])
text("eotw.welcome.discord_link", [[DMHub Discord]])
text("eotw.welcome.be_kind", [[Encounter of the Week does let you play with other users. Be kind to each other. We really don't want to ban anybody, but we will if we have to.]])
--The buttons. Short: buttons.
text("eotw.welcome.discord_button", [[Join the Discord]])
text("eotw.welcome.go_button", [[Let's Go!]])

----------------------------------------------------------------------------
-- STEAM INVITES: joining a friend's party
----------------------------------------------------------------------------

--An error, when the Steam overlay is off.
text("eotw.invite.no_overlay", [[Steam's overlay is not available, so friends cannot be invited from here. Check that the Steam overlay is enabled.]])
--When the invited party is gone.
text("eotw.invite.not_found_title", [[Party Not Found]])
text("eotw.invite.not_found_text", [[That party is no longer forming. Your friend may have disbanded it, or it may have timed out.]])
--When the invited party has already set out. {host} is the host's name.
text("eotw.invite.set_out_title", [[Party Already Set Out]])
text("eotw.invite.set_out_text", [[{host}'s party has already begun its encounter.]])
text("eotw.invite.set_out_text_unnamed", [[Your friend's party has already begun its encounter.]])
--Asked when joining means leaving the player's current party. {host} is
--the inviting host; {consequence} is one of the three lines below.
text("eotw.invite.join_title", [[Join Your Friend's Party?]])
text("eotw.invite.join_text", [[{host} invited you to their party. {consequence}]])
text("eotw.invite.join_text_unnamed", [[A friend invited you to their party. {consequence}]])
text("eotw.invite.consequence_hosting", [[Joining will disband the party you are hosting.]])
--{host} is the host of the player's current party.
text("eotw.invite.consequence_leave", [[Joining will take you out of {host}'s party.]])
text("eotw.invite.consequence_leave_unnamed", [[Joining will take you out of your current party.]])
text("eotw.invite.join_button", [[Join]])
text("eotw.invite.cancel_button", [[Cancel]])

----------------------------------------------------------------------------
-- HEROES: shared bits
----------------------------------------------------------------------------

--A hero's name when the game cannot find it.
text("eotw.hero.fallback_name", [[Hero]])
--The start of a hero's details line ("Level 2 Wode Elf Troubadour").
text("eotw.hero.level", [[Level {level}]])

----------------------------------------------------------------------------
-- THE TOWN ROSTER: hero details and fallbacks (Codex Titlescreen/EotwRoster.lua)
----------------------------------------------------------------------------

--The first part of a hero's details line, like "Level 2 Wode Elf Troubadour":
--the ancestry and class names follow it. {level} is a number.
text("roster.details.level", [[Level {level}]])
--The name saved for a hero who was given none; other players see it in
--parties and town lists.
text("roster.unnamed_hero", [[Unnamed Hero]])
--Where a hero is when their party has no name, as in "Away: a party".
text("roster.away.party_fallback", [[a party]])

----------------------------------------------------------------------------
-- THE TOWN ROSTER: problems keeping heroes in step with the town
----------------------------------------------------------------------------

--These appear in red under the Hero's Guild roster (and in other screens'
--error lines) when something goes wrong.
--{hero} is the hero's name.
text("roster.error.load_failed", [[could not load {hero} from the city]])
--{hero} is the hero's name, {reason} what went wrong (one of the lines
--below, or a message from the town's server).
text("roster.error.bring_home_failed", [[could not bring {hero} home: {reason}]])
text("roster.error.not_connected", [[not connected]])
text("roster.error.export_failed", [[could not export the hero]])
--The short reason given to other screens when saving the hero failed.
text("roster.error.export_failed_reason", [[export failed]])
text("roster.error.never_appeared", [[the new hero never appeared in the lobby]])
text("roster.error.no_hero_type", [[could not start a new hero (no Hero character type)]])
text("roster.error.pregen_unavailable", [[that pregenerated hero is not available]])
text("roster.error.pregen_copy_failed", [[could not copy the pregenerated hero]])
text("roster.error.hero_unavailable", [[that hero is not available]])
text("roster.error.hero_copy_failed", [[could not copy that hero]])
text("roster.error.not_loaded", [[that hero has not loaded yet]])

----------------------------------------------------------------------------
-- THE HERO'S GUILD: the roster screen
----------------------------------------------------------------------------

--The heading over the roster.
text("guild.roster_heading", [[Your Roster]])
--Beside the heading. {heroes} is how many heroes, {slots} how many slots,
--{active} is the line below (shown in gold).
text("guild.header.slots", [[{heroes} / {slots} slots   {active}]])
--{active} is how many heroes are active, {max} how many may be.
text("guild.header.active", [[{active} / {max} active]])
--Tooltip on the row of slot pips. {slots} is a number.
text("guild.slots_tooltip", [[Your roster has {slots} hero slots.]])
--The line under the heading. {max} is how many heroes may be active.
text("guild.intro", [[Mark up to {max} heroes as active to adventure in town. Any of them can set out from the Town Gate.]])
--Shown in place of the roster while it loads.
text("guild.loading", [[Consulting the guild's ledgers...]])
--Shown when the player has no heroes.
text("guild.empty", [[Your roster is empty. Create a hero of your own, or recruit one of the adventurers looking for work.]])

--The buttons along the bottom. Short: buttons.
--The first button, before and while a hero is being built.
text("guild.create_button", [[Create a Hero]])
text("guild.continue_button", [[Continue Your Hero]])
text("guild.discard_button", [[Discard Draft]])
--The Discard Draft button after one click, asking for a second.
text("guild.discard_confirm", [[Really Discard?]])
text("guild.discard_tooltip", [[Throw away the hero you have not finished (click twice).]])
text("guild.recruit_button", [[Recruit a Hero]])
--Shown when the roster is full.
text("guild.project_button", [[Project: Expand Guild]])
text("guild.project_tooltip", [[Start a project to build another hero slot.]])

--Shown in red when the roster is full. {slots} is the number of slots.
--When the guild cannot grow any more:
text("guild.full.max", [[Your roster is full ({slots} heroes).]])
--When it can:
text("guild.full.slots", [[Your roster is full ({slots} slots). Start a project to expand the guild for another.]])
--Shown in red when too many heroes would be active. {max} is a number.
text("guild.error.max_active", [[At most {max} heroes can be active.]])
--The title of the builder when an existing hero is rebuilt.
text("guild.rebuild_title", [[Rebuild Your Hero]])

----------------------------------------------------------------------------
-- THE HERO'S GUILD: one hero's row
----------------------------------------------------------------------------

--A hero's name when the game cannot find it.
text("guild.row.hero_fallback", [[Hero]])
--The status line under the hero's name; several are joined with " - ".
text("guild.row.active", [[Active in town]])
--{party} is the name of the party the hero is with.
text("guild.row.away", [[Away: {party}]])
text("guild.row.loading", [[Loading...]])
--Captions under the hero's numbers. Short: a few letters each.
text("guild.stats.stamina", [[Stamina]])
text("guild.stats.recoveries", [[Recov.]])
--Tooltips on the star icon. {max} is how many heroes may be active.
text("guild.row.active_tooltip", [[Active: adventuring in town. Click to rest them.]])
text("guild.row.make_active_tooltip", [[Make active: up to {max} heroes adventure in town at once.]])
--Tooltips on the pencil icon.
text("guild.row.rebuild_tooltip", [[Rebuild this hero. You can change a hero's build any time they are in Blackbottom.]])
text("guild.row.sheet_tooltip", [[Open this hero's character sheet]])
--Tooltips on the bin icon.
text("guild.row.dismiss_away_tooltip", [[This hero is in a party and cannot be dismissed.]])
text("guild.row.dismiss_tooltip", [[Dismiss this hero from your roster (click twice). This cannot be undone.]])

----------------------------------------------------------------------------
-- THE HERO'S GUILD: the recruit picker
----------------------------------------------------------------------------

text("guild.picker.title", [[Recruit a Hero]])
text("guild.picker.subtitle", [[Choose a hero and give them a name.]])
--The section of the player's own heroes.
text("guild.picker.own_heading", [[Your Heroes]])
text("guild.picker.own_subtitle", [[Copy one of your titlescreen heroes into town. The copy starts at level 1 with no items.]])
--The section of pregenerated heroes.
text("guild.picker.hire_heading", [[Adventurers for Hire]])
text("guild.picker.hire_subtitle", [[Pregenerated heroes looking for work.]])
text("guild.picker.pregens_loading", [[The pregenerated heroes are still loading. Try again in a moment.]])
--Under each Hero module's name: its pregenerated heroes.
text("guild.picker.module_subtitle", [[Pregenerated heroes from a Hero module in your inventory.]])
--A card's name when the hero has none.
text("guild.picker.unnamed_hero", [[Unnamed Hero]])
--On the card of a hero the player has already copied into town.
text("guild.picker.already_in_roster", [[Already in your roster]])
text("guild.picker.cancel_button", [[Cancel]])

----------------------------------------------------------------------------
-- THE HERO'S GUILD: naming a recruit
----------------------------------------------------------------------------

text("guild.name_prompt.title", [[Name your recruit]])
--The line under the title for one of the player's own heroes. {name} is the
--hero's name, {details} like "Level 1 Wode Elf Troubadour".
text("guild.name_prompt.copy", [[A copy of {name} joins your roster as a {details}, without their items. Your titlescreen hero is unchanged.]])
--The line for a pregenerated hero. {details} like "Level 1 Wode Elf Troubadour".
text("guild.name_prompt.pregen", [[A {details} joins your roster. What do they call themselves?]])
--Faint text in the empty name box.
text("guild.name_prompt.placeholder", [[Hero name...]])
--Tooltip on the reroll icon.
text("guild.name_prompt.reroll_tooltip", [[Roll another name]])
text("guild.name_prompt.recruit_button", [[Recruit]])
text("guild.name_prompt.cancel_button", [[Cancel]])

----------------------------------------------------------------------------
-- THE GRAVEYARD
----------------------------------------------------------------------------

text("graveyard.title", [[The Graveyard]])
text("graveyard.subtitle", [[Here lie the heroes of Blackbottom who did not come home.]])
--Shown in place of the graves while they load, and when there are none.
text("graveyard.loading", [[Reading the headstones...]])
text("graveyard.empty", [[No one has fallen yet. May it stay that way.]])
--A fallen hero's name when the game cannot find it.
text("graveyard.hero_fallback", [[Hero]])
--The line saying where and when a hero fell. {where} is the encounter's
--name, {when} the date. Which one shows depends on what is known.
text("graveyard.fell", [[Fell]])
text("graveyard.fell_in", [[Fell in {where}]])
text("graveyard.fell_on", [[Fell, {when}]])
text("graveyard.fell_in_on", [[Fell in {where}, {when}]])
--{player} is the name of the player who played the hero.
text("graveyard.played_by", [[Played by {player}]])
--At the bottom of the list when there are more graves. Short: a button.
text("graveyard.older_button", [[Older graves...]])
--The button that closes the Graveyard. Short: a button.
text("graveyard.leave_button", [[Leave]])

----------------------------------------------------------------------------
-- THE HALL OF HEROES: every party that won an Encounter of the Week
----------------------------------------------------------------------------

--The tab that shows every encounter. Short.
text("roster.hall.all_tab", [[All]])
--Before the sort buttons. Short.
text("roster.hall.sort_label", [[Sort:]])
--The sort buttons. Short: buttons.
text("roster.hall.sort_recent", [[Most Recent]])
text("roster.hall.sort_fastest", [[Fastest]])
text("roster.hall.sort_rounds", [[Fewest Rounds]])
text("roster.hall.sort_deaths", [[Fewest Deaths]])
--Shown in place of the list while it loads, and when it is empty.
text("roster.hall.loading", [[Reading the roll of honour...]])
text("roster.hall.empty", [[No party has won here yet. Will yours be the first?]])
--At the bottom of the list when there are more entries. Short: a button.
text("roster.hall.more_button", [[More...]])
--Tooltip on each entry.
text("roster.hall.entry_tooltip", [[Show this party's victory screen]])
--A hero's name when the game cannot find it.
text("roster.hall.hero_fallback", [[Hero]])
--An encounter's name when the game cannot find it.
text("roster.hall.encounter_fallback", [[An Encounter of the Week]])
--{players} is the players' names, separated by commas.
text("roster.hall.played_by", [[Played by {players}]])
--Under the names: the encounter and when it was won. {encounter} is the
--encounter's name, {when} the date.
text("roster.hall.encounter_when", [[{encounter}, {when}]])
--The stats line. {time} is the play time (see below), {count} the number
--of rounds, {deaths} the deaths (see below).
text("roster.hall.stats.one", [[{time} played | {count} round | {deaths}]])
text("roster.hall.stats.other", [[{time} played | {count} rounds | {deaths}]])
--The play time. {minutes} and {hours} are numbers ({minutes} has two digits
--in the second).
text("roster.hall.time_unknown", [[time unknown]])
text("roster.hall.time_under_minute", [[under a minute]])
text("roster.hall.time_minutes", [[{minutes} min]])
text("roster.hall.time_hours", [[{hours}h {minutes}m]])
--The deaths. {count} is a number, {names} the fallen heroes' names.
text("roster.hall.no_deaths", [[no deaths]])
text("roster.hall.deaths.one", [[{count} death]])
text("roster.hall.deaths.other", [[{count} deaths]])
text("roster.hall.deaths_named.one", [[{count} death ({names})]])
text("roster.hall.deaths_named.other", [[{count} deaths ({names})]])
--Shown in red when an entry cannot be opened.
text("roster.hall.no_snapshot", [[This entry has no victory screen to show.]])
--The caption over a replayed victory screen. {encounter} is the
--encounter's name, {when} the date.
text("roster.hall.replay_caption", [[{encounter} -- {when}]])

----------------------------------------------------------------------------
-- THE BLUE FISH INN: taking a respite
----------------------------------------------------------------------------

--The heading at the top of the inn's card, and the note beside it.
text("inn.respite.heading", [[Take a Respite]])
text("inn.respite.duration", [[24 hours of rest]])
--The paragraph under the heading.
text("inn.respite.intro", [[Rest together and every hero at home turns their Victories into XP and Downtime Activities, and recovers fully. Or just catch your breath: spend a Recovery and keep your Victories for the next fight.]])

--Shown in place of the hero list.
text("inn.list.loading", [[The innkeeper is checking the guest book...]])
text("inn.list.no_heroes", [[You have no heroes. Visit the Hero's Guild.]])

--One hero's row. The name when the game cannot find it.
text("inn.row.hero_fallback", [[Hero]])
--The line under the hero's name. {stamina}/{stamina_max} and
--{recoveries}/{recoveries_max} are numbers.
text("inn.row.vitals", [[Stamina {stamina}/{stamina_max}  -  Recoveries {recoveries}/{recoveries_max}]])
--The same line for a dying hero. {dying} is the word below, in red;
--{vitals} is the line above.
text("inn.row.vitals_dying", [[{dying}  -  {vitals}]])
text("inn.row.dying", [[Dying]])
--What a respite gives this hero. {xp} and {downtime} are both the hero's
--Victories. Short: it sits under a small trophy count.
text("inn.row.gains", [[+{xp} XP  -  +{downtime} Downtime]])
--The same, for a hero with no Victories.
text("inn.row.full_rest", [[Full rest]])
--In place of the gains, for a hero who cannot rest. {party} is the name of
--the game the hero is away in.
text("inn.row.away", [[Away: {party}]])
text("inn.row.loading", [[Loading...]])

--The Catch Breath button on each row. Short: a small button.
text("inn.catch_breath.button", [[Catch Breath]])
--Its tooltip. {amount} is the Stamina a Recovery gives.
text("inn.catch_breath.tooltip", [[Spend a Recovery to regain {amount} Stamina, without resting. Victories stay unspent.]])
--Its tooltip when the hero cannot catch their breath.
text("inn.catch_breath.loading", [[Loading...]])
text("inn.catch_breath.away", [[This hero is away in a party.]])
text("inn.catch_breath.full_stamina", [[Already at full Stamina.]])
text("inn.catch_breath.no_recoveries", [[No Recoveries left. Take a respite to regain them.]])

--The line under the hero list, above the Take a Respite button.
text("inn.footer.nobody_home", [[None of your heroes are at home to rest.]])
--When nobody at home is hurt. Also shown under the button when it is pressed.
text("inn.footer.no_wounds", [[Your heroes are fresh and whole! Return when someone needs Stamina or Recoveries.]])
--What a respite will do. {count} is how many heroes rest.
text("inn.footer.rest.one", [[{count} hero respite: Victories become XP, and Stamina and Recoveries are restored.]])
text("inn.footer.rest.other", [[{count} heroes respite: Victories become XP, and Stamina and Recoveries are restored.]])
--The same when the heroes have Victories. {count} is how many heroes rest;
--{downtime} is the counted phrase below.
text("inn.footer.rest_downtime.one", [[{count} hero respite: Victories become XP and {downtime}, and Stamina and Recoveries are restored.]])
text("inn.footer.rest_downtime.other", [[{count} heroes respite: Victories become XP and {downtime}, and Stamina and Recoveries are restored.]])
--{count} is the total Victories, which become Downtime Activities.
text("inn.footer.downtime_activities.one", [[{count} Downtime Activity]])
text("inn.footer.downtime_activities.other", [[{count} Downtime Activities]])

--The Take a Respite button: it asks once, then a second click rests.
text("inn.respite.button", [[Take a Respite]])
text("inn.respite.button_confirm", [[Rest Now? (Victories become XP)]])
--Shown in red under the button when a respite cannot be taken.
text("inn.respite.nobody_home", [[None of your heroes are at home to rest.]])
text("inn.respite.not_connected", [[not connected]])

--The banner after a respite, for a hero with the Secret Twin complication
--whose past catches up with them.
text("inn.secret_twin.banner_title", [[Secret Twin]])
text("inn.secret_twin.banner_subtitle", [[You sense your past will soon catch up with you...]])

----------------------------------------------------------------------------
-- THE BLUE FISH INN: where to spend Downtime (under the respite)
----------------------------------------------------------------------------

--{count} is the heroes' unspent Downtime Activities.
text("inn.after.downtime.one", [[Your heroes have {count} Downtime Activity to spend on projects.]])
text("inn.after.downtime.other", [[Your heroes have {count} Downtime Activities to spend on projects.]])
--Tooltips on a project's button (the button shows the project's name and
--progress).
text("inn.after.project_here_tooltip", [[Work on it here.]])
--{place} is where the project is worked on.
text("inn.after.project_elsewhere_tooltip", [[Go to {place} to work on it.]])
--{place} when the project names no place.
text("inn.after.guild_place", [[the Hero's Guild]])
--The button when no project is under way, and its tooltip.
text("inn.after.guild_button", [[Go to the Hero's Guild]])
text("inn.after.guild_tooltip", [[When your roster is full, the guild can start a project to expand.]])

----------------------------------------------------------------------------
-- PROJECTS: what each one is called and does
----------------------------------------------------------------------------

--Expand the Guild. {benefit} is shown under its cost.
text("downtime.projects.expand_guild.title", [[Expand the Guild]])
text("downtime.projects.expand_guild.benefit", [[+1 Hero Slot]])
--The line under its title, before and after it can grow no more.
text("downtime.projects.expand_guild.blurb", [[Recruit new Heroes into the Guild.]])
text("downtime.projects.expand_guild.blurb_maxed", [[The guild hall is as large as it will get.]])

--Find the Arcane Market (opened by a lead heard at the inn).
text("downtime.projects.find_arcane_market.title", [[Find the Arcane Market]])
text("downtime.projects.find_arcane_market.benefit", [[The Arcane Market appears on your map]])
text("downtime.projects.find_arcane_market.blurb", [[Follow the old Elementalist's hints to the market that only the right contacts can find.]])
text("downtime.projects.find_arcane_market.blurb_maxed", [[Your heroes know the way into the Arcane Market.]])
--The banner when it is completed.
text("downtime.projects.find_arcane_market.complete_banner", [[The Arcane Market!]])
text("downtime.projects.find_arcane_market.complete_subtitle", [[You have found your way in to the Arcane Market! It is marked on your town map now.]])

--Build the Hall of Heroes (the whole town's project, at the Construction).
text("downtime.projects.build_hall.title", [[Build the Hall of Heroes]])
--Where it is worked on, as in "Go to the Construction to work on it."
text("downtime.projects.build_hall.place", [[the Construction]])
text("downtime.projects.build_hall.benefit", [[The Hall of Heroes opens for the whole town]])
text("downtime.projects.build_hall.blurb", [[All of Blackbottom builds this together: every Downtime Activity spent contributes to the total.]])
text("downtime.projects.build_hall.blurb_maxed", [[The Hall of Heroes stands complete.]])
--The banner when it is completed.
text("downtime.projects.build_hall.complete_banner", [[The Hall of Heroes!]])
text("downtime.projects.build_hall.complete_subtitle", [[Blackbottom built it together. Its doors are open to every hero.]])

----------------------------------------------------------------------------
-- PROJECTS: the Start a Project dialog
----------------------------------------------------------------------------

--The title. {project} is the project's name.
text("downtime.start.title", [[Start a Project: {project}?]])
--Under the description. {goal} is a number.
text("downtime.start.goal", [[{goal} Project Points to complete.]])
--In place of the goal when the project can never be done again.
text("downtime.start.maxed", [[The guild is already as large as it can be.]])
text("downtime.start.start_button", [[Start Project]])
text("downtime.start.not_now_button", [[Not Now]])
--Shown in red when the town is offline.
text("downtime.start.not_connected", [[Not connected to the town.]])

----------------------------------------------------------------------------
-- PROJECTS: the project card (the Guild, the inn, the Construction)
----------------------------------------------------------------------------

--The note at the card's top right.
text("downtime.card.under_way", [[Project under way]])
--What the project is rolled with. {characteristics} is like "Reason or
--Presence"; {skills} is a list of skill names.
text("downtime.card.needs", [[{characteristics}  -  {skills}]])
--Between characteristic names in that line. Keep the spaces.
text("downtime.card.characteristic_separator", [[ or ]])
--The latest rolls. {rolls} is a list of the rolls below.
text("downtime.card.latest", [[Latest: {rolls}]])
text("downtime.card.no_rolls", [[No one has worked on it yet.]])
--One roll: {hero} is who rolled, {total} the points it added.
text("downtime.card.recent_roll", [[{hero} +{total}]])
--The same for a breakthrough roll; {breakthrough} is the word below, in
--amber.
text("downtime.card.recent_roll_breakthrough", [[{hero} +{total} {breakthrough}]])
text("downtime.card.breakthrough_word", [[breakthrough]])
--A hero's name when the game cannot find it.
text("downtime.card.hero_fallback", [[Hero]])
--The card's button.
text("downtime.card.work_button", [[Work on This Project]])
text("downtime.card.breakthrough_button", [[Breakthrough Roll Waiting]])
--The button's tooltip when it cannot be used.
text("downtime.card.not_under_way", [[This project is not under way.]])
text("downtime.card.no_downtime", [[None of your heroes have Downtime Activities. When you take a respite at the inn and convert Victories to experience, you will earn them.]])

--The Construction's card, above the Hall of Heroes project.
text("downtime.construction.intro", [[Build the Hall of Heroes where the works and deeds of the heroes of Blackbottom shall be recorded!]])
text("downtime.construction.community", [[Come together to build the Hall of Heroes! When completed, the Hall of Heroes will be open for all to see the great deeds and works of Blackbottom's heroes.]])

----------------------------------------------------------------------------
-- PROJECTS: the project roll dialog
----------------------------------------------------------------------------

--The title. {project} is the project's name.
text("downtime.roll.title", [[{project}: Project Roll]])
--The hero choices.
text("downtime.roll.who_heading", [[Who works on it]])
--A hero's name when the game cannot find it.
text("downtime.roll.hero_fallback", [[Hero]])
--The small tag on a hero with a free roll waiting. Short.
text("downtime.roll.free_roll_tag", [[free roll]])
--Tooltips on a hero.
text("downtime.roll.free_roll_tooltip", [[A breakthrough roll is waiting: the next roll is free.]])
text("downtime.roll.no_downtime_tooltip", [[No Downtime Activities. Rest at the inn to earn them.]])
text("downtime.roll.nobody_home", [[None of your heroes are at home.]])
--Row headings. Short: a column of labels.
text("downtime.roll.characteristic_heading", [[Characteristic]])
text("downtime.roll.skill_heading", [[Skill]])
--The skill choices. {skill} is a skill's name.
text("downtime.roll.no_skill", [[No skill]])
text("downtime.roll.skill_choice", [[{skill} (+2)]])
--Beside the skill choice when the hero has none of the project's skills.
--{skills} is the list of them.
text("downtime.roll.skills_none_trained", [[None of {skills}]])

--The name of the dice roll. {project} is the project's name.
text("downtime.roll.dice_project", [[Project Roll: {project}]])
text("downtime.roll.dice_breakthrough", [[Breakthrough: {project}]])

--The result, under the big number while and after the dice roll.
text("downtime.roll.dice_rolling", [[The dice are rolling.]])
--{natural} is the number on the dice alone.
text("downtime.roll.result_natural", [[natural {natural}]])
--After the City records the roll. {hero} is who rolled.
text("downtime.roll.result_hero", [[natural {natural} -- {hero}]])
text("downtime.roll.result_finished", [[natural {natural} -- the project is finished]])
text("downtime.roll.result_complete", [[natural {natural} -- complete!]])
--The same two when a breakthrough's extra roll comes back. {hero} gets it.
text("downtime.roll.result_finished_refunded", [[natural {natural} -- the project is finished. The breakthrough refunds a Downtime Activity to {hero}]])
text("downtime.roll.result_complete_refunded", [[natural {natural} -- complete! The breakthrough refunds a Downtime Activity to {hero}]])
--Above the big number on a natural 19 or 20.
text("downtime.roll.breakthrough_label", [[Breakthrough!]])
--What the hero said about the roll. {hero} is the hero's name, {line} what
--they said (one of the project's lines below).
text("downtime.roll.hero_line", [[<b>{hero}:</b> "{line}"]])
--The hero's name when the game cannot find it.
text("downtime.roll.your_hero", [[Your hero]])

--The hint over the dice. {hero} is the chosen hero's name.
text("downtime.roll.hint_free", [[Breakthrough! Click or throw the dice for {hero}'s free roll.]])
--{hero} when no hero is chosen.
text("downtime.roll.hint_your_hero", [[your hero]])
text("downtime.roll.hint_roll", [[Click or throw the dice to roll. It spends one of this hero's Downtime Activities.]])
--{benefit} is what the project gives (each project's "benefit" above).
text("downtime.roll.hint_complete", [[Project complete! {benefit}.]])
--{benefit} when the project gives nothing named.
text("downtime.roll.hint_done", [[Done]])
text("downtime.roll.hint_not_under_way", [[This project is not under way.]])
text("downtime.roll.hint_nobody_home", [[None of your heroes are at home.]])
text("downtime.roll.hint_no_downtime_left", [[Your heroes have no Downtime Activities left. Rest at the inn to earn more.]])
text("downtime.roll.hint_hero_no_downtime", [[This hero has no Downtime Activities. Choose another hero, or rest at the inn.]])

--Shown in red under the result when the roll could not be made or recorded.
text("downtime.roll.not_ready", [[That hero is not ready yet.]])
text("downtime.roll.offline", [[Not connected to the town. Your roll is saved and will be recorded when you reconnect.]])

--The big button once nothing is left to roll, and the X's tooltip.
text("downtime.roll.close_button", [[Close]])
text("downtime.roll.close_tooltip", [[Close]])

--The banners after a roll. {hero} is who rolled, {project} the project.
text("downtime.roll.breakthrough_banner", [[Breakthrough!]])
text("downtime.roll.breakthrough_subtitle", [[{hero} made a breakthrough on {project}]])
text("downtime.roll.breakthrough_refunded_subtitle", [[{hero} finished {project} with a breakthrough: the extra roll comes back as a Downtime Activity]])
--When a project is completed (a project with its own banner above uses that).
text("downtime.roll.complete_banner", [[{project}!]])
text("downtime.roll.complete_subtitle", [[The project is complete.]])
--When Expand the Guild is completed. {slots} is the new number of hero slots.
text("downtime.roll.guild_banner", [[The Guild Expands!]])
text("downtime.roll.guild_subtitle", [[You now have {slots} hero slots.]])

----------------------------------------------------------------------------
-- PROJECTS: what heroes say after a roll on Find the Arcane Market
----------------------------------------------------------------------------

--Chosen by how far along the project is (early: under a third done; mid;
--late: two thirds or more) and how the roll went (hopeful: a good roll;
--neutral; frustrated: a poor roll). Three lines each; a line said
--recently is not repeated while another is left.
text("downtime.lines.arcane_market.early_hopeful_1", [[The apothecary went pale when I said 'Arcane Market'. We are on the right track.]])
text("downtime.lines.arcane_market.early_hopeful_2", [[A chalk mark on the alley wall. Is it the same one the old Elementalist drew? Very interesting.]])
text("downtime.lines.arcane_market.early_hopeful_3", [[A street sweeper says the carts only come out after midnight. Which carts, I wonder?]])
text("downtime.lines.arcane_market.early_neutral_1", [[Hmmm stymied again, let's keep looking.]])
text("downtime.lines.arcane_market.early_neutral_2", [[Nobody admits the market exists. But perhaps this means it does.]])
text("downtime.lines.arcane_market.early_neutral_3", [[Two taverns, three dead ends and a suspicious looking goat. Tomorrow we continue looking.]])
text("downtime.lines.arcane_market.early_frustrated_1", [[If I have to talk to yet another Crazy Gnome Tinkerer I think I'm going to come unglued...]])
text("downtime.lines.arcane_market.early_frustrated_2", [[Asking a fortune teller led nowhere. But at least I know how my next romance will end.]])
text("downtime.lines.arcane_market.early_frustrated_3", [[Every alchemist in Blackbottom suddenly has somewhere else to be.]])

text("downtime.lines.arcane_market.mid_hopeful_1", [[A gnome with singed eyebrows claimed he was just trying to cook himself dinner. But I know better.]])
text("downtime.lines.arcane_market.mid_hopeful_2", [[I traded a favor for a name. A real name this time, let's hope?]])
text("downtime.lines.arcane_market.mid_hopeful_3", [[So I knock twice hard and once soft? Let's hope that's right. Let's hope being wrong doesn't mean an arrow in the gut.]])
text("downtime.lines.arcane_market.mid_neutral_1", [[Hmmm stymied again, but we'll keep looking.]])
text("downtime.lines.arcane_market.mid_neutral_2", [[The trail went cold at the fishmonger's. And it smelled bad. Really bad.]])
text("downtime.lines.arcane_market.mid_neutral_3", [[Half the contacts I've found are lying. The trick is working out which half.]])
text("downtime.lines.arcane_market.mid_frustrated_1", [[If I have to talk to one more Crazy Gnome Tinkerer I think I'm going to come unglued...]])
text("downtime.lines.arcane_market.mid_frustrated_2", [[Well that gnome sold me a 'map'. Is it really just a drawing of a duck? Could be worse, couldn't it?]])
text("downtime.lines.arcane_market.mid_frustrated_3", [[I've knocked on so many doors my knuckles have calluses.]])

text("downtime.lines.arcane_market.late_hopeful_1", [[This seems like I'm getting close.]])
text("downtime.lines.arcane_market.late_hopeful_2", [[Is that brimstone and cinnamon I can smell through the wall? It's right here somewhere.]])
text("downtime.lines.arcane_market.late_hopeful_3", [[The right contact finally owes me a favor. One more little push.]])
text("downtime.lines.arcane_market.late_neutral_1", [[Hmmm, stymied again, but we'll keep looking. It can't be far off now.]])
text("downtime.lines.arcane_market.late_neutral_2", [[I swear there was a door here last night, wasn't there?]])
text("downtime.lines.arcane_market.late_neutral_3", [[Another painted door, another blank wall. Surely we are getting closer, though?]])
text("downtime.lines.arcane_market.late_frustrated_1", [[Missed the cart by a minute. A MINUTE!]])
text("downtime.lines.arcane_market.late_frustrated_2", [[Will we ever find this blasted market?]])
text("downtime.lines.arcane_market.late_frustrated_3", [[If one more gnome tells me in their wee little gnome voice it's 'close now, you will find it soon'...]])

--The roll that completes it.
text("downtime.lines.arcane_market.done_1", [[There it is! A painted door that opens when you knock twice. We're in!]])
text("downtime.lines.arcane_market.done_2", [[We needed just the right set of contacts, she said. Well, now we have them.]])
text("downtime.lines.arcane_market.done_3", [[You were the gnome tinkerer we talked to right at the start weren't you? I knew it was you!]])

----------------------------------------------------------------------------
-- PROJECTS: what heroes say after a roll on Build the Hall of Heroes
----------------------------------------------------------------------------

--Chosen the same way as the Arcane Market's lines above.
text("downtime.lines.hall.early_hopeful_1", [[The foundations are dug. Deep enough to hold a legend or two.]])
text("downtime.lines.hall.early_hopeful_2", [[The first stone is laid, and a crowd cheered. A small crowd. Still counts.]])
text("downtime.lines.hall.early_hopeful_3", [[The mason says my mortar is 'adequate'. From him, that is a hymn.]])
text("downtime.lines.hall.early_neutral_1", [[Mostly mud today. Honourable mud, but mud.]])
text("downtime.lines.hall.early_neutral_2", [[We moved a lot of rubble. Some of it twice.]])
text("downtime.lines.hall.early_neutral_3", [[The plans are bigger than the plot. Someone is measuring again.]])
text("downtime.lines.hall.early_frustrated_1", [[Somebody stole the shovels. Who steals shovels?]])
text("downtime.lines.hall.early_frustrated_2", [[It rained. The foundations are now a pond.]])
text("downtime.lines.hall.early_frustrated_3", [[The foreman shouted at me in three languages. All of them meant 'no'.]])

text("downtime.lines.hall.mid_hopeful_1", [[The walls are up to my shoulders. You can see the shape of it now.]])
text("downtime.lines.hall.mid_hopeful_2", [[We raised the first pillar today. The whole street came out to watch.]])
text("downtime.lines.hall.mid_hopeful_3", [[A carver is cutting the names of fallen heroes into the lintel. It's beautiful.]])
text("downtime.lines.hall.mid_neutral_1", [[Another day of hauling stone. The Hall rises an inch at a time.]])
text("downtime.lines.hall.mid_neutral_2", [[The scaffolding creaks, but it holds.]])
text("downtime.lines.hall.mid_neutral_3", [[We argued about the doors for an hour, then built a wall instead.]])
text("downtime.lines.hall.mid_frustrated_1", [[A whole cart of marble went into the canal. Again.]])
text("downtime.lines.hall.mid_frustrated_2", [[The pulley snapped and I learned some new words from the dwarves.]])
text("downtime.lines.hall.mid_frustrated_3", [[My back hurts, my hands hurt, and the gargoyle is crooked.]])

text("downtime.lines.hall.late_hopeful_1", [[The roof beams are going up. It's nearly done!]])
text("downtime.lines.hall.late_hopeful_2", [[They hung the great bronze doors today. They gleam.]])
text("downtime.lines.hall.late_hopeful_3", [[The banners are sewn. All we need now is the last of the stone.]])
text("downtime.lines.hall.late_neutral_1", [[Polishing, sweeping, polishing. The end is in sight.]])
text("downtime.lines.hall.late_neutral_2", [[Just the finishing touches left. Lots of finishing touches.]])
text("downtime.lines.hall.late_neutral_3", [[The scribes are already arguing over whose deeds go in first.]])
text("downtime.lines.hall.late_frustrated_1", [[The stained glass arrived in four hundred pieces. It was meant to be in forty.]])
text("downtime.lines.hall.late_frustrated_2", [[So close, and the chimney collapsed. Up we go again.]])
text("downtime.lines.hall.late_frustrated_3", [[If the architect changes the spire one more time...]])

--The roll that completes it.
text("downtime.lines.hall.done_1", [[The last stone is set. The Hall of Heroes stands!]])
text("downtime.lines.hall.done_2", [[The doors swing open, and the whole town cheers. We built this.]])
text("downtime.lines.hall.done_3", [[Let every deed be written here. The Hall of Heroes is complete!]])

----------------------------------------------------------------------------
-- LEADS: carousing at the Blue Fish Inn, and the conversations that tell a
-- lead (Codex Titlescreen/EotwLeads.lua)
----------------------------------------------------------------------------

--The Arcane Market lead: its name, shown on the "A New Lead!" banner and the
--inn card.
text("leads.arcane_market.title", [[The Arcane Market]])
--Who tells it. The speaker line reads "{name}, {title}".
text("leads.arcane_market.npc_name", [[Old Ysolde]])
text("leads.arcane_market.npc_title", [[Elementalist]])

--The conversation, line by line. npc = Old Ysolde, hero = the hero who
--caroused. {hero} is the hero's name.
text("leads.arcane_market.line1_npc", [[You've the look of someone who buys their potions from the front of the shop. Pity. The good ones never are.]])
text("leads.arcane_market.line2_hero", [[And where would the good ones be, grandmother?]])
text("leads.arcane_market.line3_npc", [[Grandmother! Ha. Forty years I've bought my powders in Blackbottom. There is a market here, the Arcane Market, that never stands still. Stalls in back rooms, carts that are there one night and gone the next.]])
text("leads.arcane_market.line4_hero", [[How does anyone find a market that moves?]])
text("leads.arcane_market.line5_npc", [[Just the right set of contacts. An alchemist who owes you a favour. A gnome who talks too much. A door that only opens to the right knock.]])
text("leads.arcane_market.line6_npc", [[Ask around, {hero}. And mind the gnome tinkerers: half of them are mad, and the other half are worse.]])
text("leads.arcane_market.line7_hero", [[Then I know what I'm doing with my downtime.]])

--The name above an NPC's line in a conversation.
text("leads.conversation.npc_speaker", [[{name}, {title}]])
--A hero's name when the game cannot find it.
text("leads.hero_fallback", [[Hero]])

--The carouse dialog.
text("leads.carouse.title", [[Carouse at the Blue Fish Inn]])
text("leads.carouse.intro", [[The common room is loud tonight. One hero buys a round, swaps stories and listens for rumours: a Presence test. A tier 3 result turns up a lead worth chasing.]])
--The name of the dice roll in the roll log.
text("leads.carouse.roll_name", [[Carouse at the Blue Fish Inn]])
--The three rows of the tier table.
text("leads.carouse.tier1", [[A sore head and no new friends. Nothing learned.]])
text("leads.carouse.tier2", [[Good company and tall tales, but nothing worth chasing.]])
text("leads.carouse.tier3", [[Someone in the corner knows a thing or two: learn a lead.]])
text("leads.carouse.who_heading", [[Who carouses]])
--A hero to choose; {bonus} is like +2.
text("leads.carouse.hero_choice", [[{hero}  (Presence {bonus})]])
--The chosen hero's name when the game cannot find it.
text("leads.carouse.your_hero", [[Your hero]])
text("leads.carouse.nobody_home", [[None of your heroes are at home.]])
text("leads.carouse.skill_heading", [[Skill]])
text("leads.carouse.no_skill", [[No skill]])
--A skill to choose: {skill} is its name.
text("leads.carouse.skill_choice", [[{skill} (+2)]])
--The big result, and the line under it while the dice settle.
text("leads.carouse.result_tier", [[Tier {tier}]])
text("leads.carouse.result_natural", [[natural {natural}]])
--The line under the result. {total} is the roll, {natural} the dice alone.
text("leads.carouse.result_lead", [[{total} (natural {natural}). {hero} catches the eye of someone in the corner who knows a thing or two... Lead: {lead}]])
text("leads.carouse.result_tier3_nothing_left", [[{total} (natural {natural}). A grand night, but there is nothing left to learn.]])
text("leads.carouse.result_tier2", [[{total} (natural {natural}). {hero} trades stories all night. Good company, but nothing worth chasing.]])
text("leads.carouse.result_tier1", [[{total} (natural {natural}). {hero} wakes with a sore head and no new friends. Nothing learned.]])
--The hint over the dice.
text("leads.carouse.hint_no_respite", [[Take a respite first: each respite earns one night of carousing.]])
text("leads.carouse.hint_roll", [[Click or throw the dice to carouse. One carouse per respite.]])
text("leads.carouse.listen_button", [[Listen...]])
text("leads.carouse.close_button", [[Close]])
text("leads.carouse.close_tooltip", [[Close]])
--The banner when a carouse learns a lead (the lead's name is under it).
text("leads.carouse.new_lead_banner", [[A New Lead!]])
--When the town is offline after the dice have landed.
text("leads.carouse.offline", [[Not connected to the town. The carouse is saved and will be recorded when you reconnect.]])

--The leads rows on the Blue Fish Inn's card.
text("leads.inn.carouse_row", [[The common room is lively tonight. One of your heroes could carouse and listen for rumours.]])
text("leads.inn.carouse_button", [[Carouse]])
text("leads.inn.carouse_tooltip", [[A Presence test. Tier 3 learns a lead. One carouse per respite: if you rest again first, tonight's chance is gone.]])
--A lead learned whose project has not started. {lead} is the lead's name,
--{npc} who told it.
text("leads.inn.project_row", [[Lead: {lead}. {npc} told you where to start looking.]])
text("leads.inn.project_button", [[Start Project]])
--{project} is the project's name.
text("leads.inn.project_tooltip", [[Start {project}, to spend Downtime on it.]])
--The project's name when the game cannot find it.
text("leads.inn.project_fallback", [[the project]])

----------------------------------------------------------------------------
-- THE ARCANE MARKET: the market's card in town (Codex Titlescreen/EotwMarket.lua)
----------------------------------------------------------------------------

--The card's heading.
text("market.card.title", [[Shop the Stalls]])
--The paragraph under the heading.
text("market.card.intro", [[The Arcane market! Where you purchase an extra potion that can mean the difference between life and death during your next encounter!]])
--Before a row of treasure icons: everything the market sells.
text("market.card.in_stock", [[In stock:]])
--Shown in place of the hero list while it loads.
text("market.card.loading_heroes", [[The merchants are sizing you up...]])
--Shown in place of the hero list when the player has no heroes.
text("market.card.no_heroes", [[You have no heroes. Visit the Hero's Guild.]])

--Each hero's row on the card.
--A hero's name when the game cannot find it.
text("market.card.hero_fallback", [[Hero]])
--The row's status line while the hero is still loading.
text("market.card.loading", [[Loading...]])
--The row's status line before the hero has shopped. {wealth} is their Wealth score.
text("market.card.status_not_shopped", [[Wealth {wealth}  -  has not shopped since their last encounter]])
--The row's status line after the hero has shopped. {tier} is 1, 2 or 3,
--{offered} how many treasures were found, {bought} how many bought, {limit}
--how many they may buy.
text("market.card.status_tier", [[Tier {tier}: {offered} on offer  -  bought {bought} of {limit}]])
--The same after a critical roll (a natural 19 or 20).
text("market.card.status_critical", [[Critical: {offered} on offer  -  bought {bought} of {limit}]])
--The row's button before the hero has shopped. Short: a button.
text("market.card.shop_button", [[Shop]])
--The row's button after the hero has shopped. Short: a button.
text("market.card.browse_button", [[Browse]])
--Tooltip on the Shop button.
text("market.card.shop_tooltip", [[Make a Presence test to find what is on offer.]])
--Tooltip name of a treasure icon when the game cannot find the treasure.
text("market.card.treasure_fallback", [[Treasure]])

----------------------------------------------------------------------------
-- THE ARCANE MARKET: why a hero cannot shop or buy
----------------------------------------------------------------------------

--Shown on the row, the Shop button's tooltip and over the dice.
text("market.blocked.loading", [[Loading...]])
--{reason} says where the hero is (for example, on an encounter).
text("market.blocked.away", [[Away: {reason}]])
--A hero's record is not ready yet.
text("market.error.hero_not_ready", [[That hero is not ready yet.]])
--A hero tried to roll again before their next encounter.
text("market.error.already_shopped", [[You've already shopped and had your fill of haggling with merchants. Go hit something before you're ready to deal with them again.]])
--Tooltips on a Buy button that cannot be used.
text("market.buy_blocked.roll_first", [[Make the Presence test first.]])
text("market.buy_blocked.not_offered", [[That treasure is not on offer to this hero.]])
text("market.buy_blocked.already_bought", [[Already bought.]])
text("market.buy_blocked.no_purchases_left", [[No purchases left until this hero's next encounter.]])
--When a purchase fails and the game gives no reason.
text("market.error.purchase_failed", [[The purchase did not go through.]])

----------------------------------------------------------------------------
-- THE ARCANE MARKET: the stall dialog, before the test
----------------------------------------------------------------------------

--The dialog's title. {hero} is the hero's name.
text("market.shop.title", [[The Arcane Market: {hero}]])
--The hero's name when the game cannot find it.
text("market.shop.your_hero", [[Your hero]])
--Under the title.
text("market.shop.flavor", [[Potions, powders and stranger things, sold to those who know whom to ask.]])
--Shown when the hero's record cannot be found.
text("market.shop.hero_missing", [[This hero is not here.]])
text("market.shop.intro", [[Make a Presence test to haggle with merchants and find the stalls worth your coin.]])
--Beside the skill dropdown. Short.
text("market.shop.skill_heading", [[Skill]])
--Dropdown choices: no skill, or a skill. {skill} is the skill's name.
text("market.shop.no_skill", [[No skill]])
text("market.shop.skill_choice", [[{skill} (+2)]])
--Beside the dropdown: which skills help.
text("market.shop.skills_hint_none", [[Alchemy or Magic would help (this hero has neither)]])
text("market.shop.skills_hint", [[Alchemy or Magic]])
--The roll's formula, like "2d10 +2 Presence". {bonus} is like +2,
--{characteristic} is Presence, {skill} the chosen skill's name.
text("market.formula.no_skill", [[2d10 {bonus} {characteristic}]])
text("market.formula.with_skill", [[2d10 {bonus} {characteristic} +2 {skill}]])
--The characteristic's name when the game cannot find it.
text("market.formula.presence", [[Presence]])
--The tier table: the roll needed, then what it finds.
text("market.shop.tier1_label", [[11 or lower]])
text("market.shop.tier1_text", [[2 treasures on offer]])
text("market.shop.tier2_label", [[12 - 16]])
text("market.shop.tier2_text", [[3 treasures on offer]])
text("market.shop.tier3_label", [[17 or higher]])
text("market.shop.tier3_text", [[4 treasures on offer]])
text("market.shop.critical_label", [[Natural 19 - 20]])
text("market.shop.critical_text", [[4 treasures on offer, and buy one extra]])
--Under the tier table. {hero} is the hero's name, {wealth} their Wealth score.
text("market.shop.can_buy", [[{hero} can buy up to {wealth} (Wealth {wealth}).]])
--The name of the dice roll in the roll log.
text("market.shop.roll_name", [[The Arcane Market]])
--The hint over the dice.
text("market.shop.hint_roll", [[Click or throw the dice to make the test.]])

----------------------------------------------------------------------------
-- THE ARCANE MARKET: the stall dialog, after the test
----------------------------------------------------------------------------

--The big result. {tier} is 1, 2 or 3.
text("market.shop.result_critical", [[Critical!]])
text("market.shop.result_tier", [[Tier {tier}]])
--Beside the result. {total} is the roll, {natural} the dice alone, {skill}
--the skill used.
text("market.shop.rolled", [[Rolled {total} (natural {natural})]])
text("market.shop.rolled_with_skill", [[Rolled {total} (natural {natural}) with {skill}]])
--The line under the result. {count} is how many treasures were found,
--{bought} how many bought, {limit} how many may be bought, {wealth} the
--hero's Wealth score.
text("market.shop.offer_summary.one", [[{count} treasure on offer.  Bought {bought} of {limit} (Wealth {wealth}).]])
text("market.shop.offer_summary.other", [[{count} treasures on offer.  Bought {bought} of {limit} (Wealth {wealth}).]])
--The same after a critical roll, which allows one extra purchase.
text("market.shop.offer_summary_critical.one", [[{count} treasure on offer.  Bought {bought} of {limit} (Wealth {wealth}, +1 for the critical).]])
text("market.shop.offer_summary_critical.other", [[{count} treasures on offer.  Bought {bought} of {limit} (Wealth {wealth}, +1 for the critical).]])
--Shown when the roll found nothing.
text("market.shop.nothing_in_stock", [[The stalls had nothing in stock.]])
--A treasure card's name when the game cannot find the treasure.
text("market.shop.treasure_fallback", [[A treasure]])
--The button under each treasure. Short: a button.
text("market.shop.buy_button", [[Buy]])
--Shown in place of the Buy button once bought. Short.
text("market.shop.bought", [[Bought]])
--The hint at the bottom once the hero has shopped.
text("market.shop.hint_done", [[The stalls change after this hero's next encounter.]])
--The button at the bottom, and the tooltip on the X in the corner.
text("market.shop.close_button", [[Close]])
text("market.shop.close_tooltip", [[Close]])
