# The Training Grounds: lines to write

Fill in every `Line:` below. When it is done, each entry becomes one
`text("id", [[...]])` row in `Codex Titlescreen/EotwTextTown.lua`, under the
id shown, so please leave the ids alone.

Rules (the same ones as the Lua text files):

- **Plain keyboard characters only.** Straight quotes `'` and `"`, three dots
  `...`, a hyphen or colon for a dash. Curly quotes and em dashes break the
  file.
- `{name}`-style words in braces are filled in by the game. Keep each one,
  spelled exactly as shown. You can move it anywhere in the sentence.
- Entries ending `.one` / `.other` are the same line for a count of 1 and
  for any other count.
- Lines marked *(optional)* can be left blank and I will leave that feature
  out.
- The Town Hall's live wording is shown under some entries for tone and
  length. You don't have to match it.

---

## 0. Project settings (decided 2026-11-04)

| Setting | Proposed | Yours |
|---|---|---|
| Setting | Decided |
|---|---|
| Project id | `build-training-grounds` |
| Who builds it | The whole town (community project, like the Hall of Heroes and the Town Hall) |
| Cost | **6000** Project Points, one completion, under way from the start |
| Stage 1: Planning (points 0-2999) | Reason or Presence; Architecture, Lead, Strategy, Society |
| Stage 2: Building (points 3000-6000) | Might or Agility; Blacksmithing, Carpentry, Fletching, Mechanics |
| Map icon while building | hammer (same as the other sites) |
| Map icon once built | crossed swords |
| Map spot (fraction of the map) | (0.905, 0.44): the open square in the east district, clear of every other marker |
| Site art while building | the Hall of Heroes' Construction still (placeholder, as the Town Hall uses) |
| Built art | Czepeku *Jousting Tournament* (Original Day HD) video loop over its first frame, Czepeku credit |

The skill names are the game's own ("Lead", not "Leadership"). Tell me if
you want a different skill list for either stage.

---

## 1. The map node

### While it is being built

- `eotw.locations.training_grounds_site.label`: the name on the map marker (1-3 words).
  Town Hall: *Town Hall Site*
  Line:
- `eotw.locations.training_grounds_site.title`: the heading when it is opened.
  Town Hall: *The Town Hall Site*
  Line:
- `eotw.locations.training_grounds_site.tagline`: one or two sentences under the heading.
  Town Hall: *Blackbottom needs a place to gather, argue and decide. Lend a hand and raise the Town Hall!*
  Line:

### Once it is built

- `eotw.locations.training_grounds.label`: the name on the map marker.
  Line:
- `eotw.locations.training_grounds.title`: the heading when it is opened.
  Line:
- `eotw.locations.training_grounds.tagline`: one or two sentences under the heading.
  Town Hall: *Where the people of Blackbottom have their say. Vote on the questions put to the town, or raise a petition of your own.*
  Line:

---

## 2. The building site's card

Shown above the project card while the town builds it.

- `downtime.training_grounds_site.intro`: a short call to action (shown large, in italics).
  Town Hall: *Build the Town Hall, decide the future of Blackbottom!*
  Line:
- `downtime.training_grounds_site.community`: one or two sentences on what it will be.
  Town Hall: *Come together to build the Town Hall! A place for the Council to meet and decide the important matters facing the town.*
  Line:

---

## 3. The project

- `downtime.projects.build_training_grounds.title`: the project's name.
  Town Hall: *Build the Town Hall*
  Line:
- `downtime.projects.build_training_grounds.place`: where it is worked on, as in "Go to ___ to work on it."
  Town Hall: *the Town Hall Site*
  Line:
- `downtime.projects.build_training_grounds.benefit`: shown under its cost.
  Town Hall: *The Town Hall opens for the whole town*
  Line:
- `downtime.projects.build_training_grounds.blurb`: the line under the title while it is being built.
  Town Hall: *All of Blackbottom builds this together: every Downtime Activity spent contributes to the total.*
  Line:
- `downtime.projects.build_training_grounds.blurb_maxed`: the same line once it is finished.
  Town Hall: *The Town Hall stands complete.*
  Line:
- `downtime.projects.build_training_grounds.complete_banner`: the big banner when the last roll finishes it.
  Town Hall: *The Town Hall!*
  Line:
- `downtime.projects.build_training_grounds.complete_subtitle`: the line under that banner.
  Town Hall: *Blackbottom built it together. Come and have your say.*
  Line:

### The two stages

The project card shows which stage it is in, and the roll uses that stage's
characteristics and skills.

- `downtime.projects.build_training_grounds.stage_planning`: the first stage's name (1-2 words).
  Line:
- `downtime.projects.build_training_grounds.stage_building`: the second stage's name (1-2 words).
  Line:
- `downtime.card.stage`: the line on the card, shared by any project with stages. `{stage}` is one of the names above, `{number}` the stage's number, `{count}` how many stages there are.
  Line:
- `downtime.projects.build_training_grounds.stage_planning_blurb`: replaces the project's blurb during planning. What the town is doing and why the planners are needed.
  Line:
- `downtime.projects.build_training_grounds.stage_building_blurb`: the same during building.
  Line:
- `downtime.projects.build_training_grounds.stage_banner`: the banner shown to the hero whose roll finishes the planning (like the completion banner, but smaller news).
  Line:
- `downtime.projects.build_training_grounds.stage_subtitle`: the line under it, telling players building starts now with Might or Agility.
  Line:

### On Discord

The milestone cards ("Work on ___ is 50% done", "The town has finished ___!")
are shared wording. They only need the building's name, as it reads in the
middle of a sentence. (This one goes into the server's Discord code, not the
Lua text file.)

- `discord.community_project_name.build-training-grounds`: as in "The town has finished ___!"
  Town Hall: *the Town Hall*
  Line:

---

## 4. What heroes say after a project roll

After each roll, the hero says one line. For this project the line follows
the two stages, each split in half:

- **planning_early**: points 0-1499. **planning_late**: 1500-2999.
- **building_early**: 3000-4499. **building_late**: 4500-6000.
- **hopeful**: a good roll. **neutral**: a middling roll. **frustrated**: a poor roll.

There are three lines in each group, and a line said recently is not
repeated while another one is left. Planning lines are about surveying,
drawing plans, arguing over the layout and winning people over; building
lines are about timber, iron, sawing and hammering. At 6000 points this
project will see a lot of rolls, so variety helps.

Town Hall examples: *"The surveyors have marked out the ground. It's going to
be big."* (early, hopeful), *"The bell cracked on the way up. Now it only
rings flat."* (mid, frustrated).

### Planning, first half

- `downtime.lines.training_grounds.planning_early_hopeful_1`: Line:
- `downtime.lines.training_grounds.planning_early_hopeful_2`: Line:
- `downtime.lines.training_grounds.planning_early_hopeful_3`: Line:
- `downtime.lines.training_grounds.planning_early_neutral_1`: Line:
- `downtime.lines.training_grounds.planning_early_neutral_2`: Line:
- `downtime.lines.training_grounds.planning_early_neutral_3`: Line:
- `downtime.lines.training_grounds.planning_early_frustrated_1`: Line:
- `downtime.lines.training_grounds.planning_early_frustrated_2`: Line:
- `downtime.lines.training_grounds.planning_early_frustrated_3`: Line:

### Planning, second half

- `downtime.lines.training_grounds.planning_late_hopeful_1`: Line:
- `downtime.lines.training_grounds.planning_late_hopeful_2`: Line:
- `downtime.lines.training_grounds.planning_late_hopeful_3`: Line:
- `downtime.lines.training_grounds.planning_late_neutral_1`: Line:
- `downtime.lines.training_grounds.planning_late_neutral_2`: Line:
- `downtime.lines.training_grounds.planning_late_neutral_3`: Line:
- `downtime.lines.training_grounds.planning_late_frustrated_1`: Line:
- `downtime.lines.training_grounds.planning_late_frustrated_2`: Line:
- `downtime.lines.training_grounds.planning_late_frustrated_3`: Line:

### Building, first half

- `downtime.lines.training_grounds.building_early_hopeful_1`: Line:
- `downtime.lines.training_grounds.building_early_hopeful_2`: Line:
- `downtime.lines.training_grounds.building_early_hopeful_3`: Line:
- `downtime.lines.training_grounds.building_early_neutral_1`: Line:
- `downtime.lines.training_grounds.building_early_neutral_2`: Line:
- `downtime.lines.training_grounds.building_early_neutral_3`: Line:
- `downtime.lines.training_grounds.building_early_frustrated_1`: Line:
- `downtime.lines.training_grounds.building_early_frustrated_2`: Line:
- `downtime.lines.training_grounds.building_early_frustrated_3`: Line:

### Building, second half

- `downtime.lines.training_grounds.building_late_hopeful_1`: Line:
- `downtime.lines.training_grounds.building_late_hopeful_2`: Line:
- `downtime.lines.training_grounds.building_late_hopeful_3`: Line:
- `downtime.lines.training_grounds.building_late_neutral_1`: Line:
- `downtime.lines.training_grounds.building_late_neutral_2`: Line:
- `downtime.lines.training_grounds.building_late_neutral_3`: Line:
- `downtime.lines.training_grounds.building_late_frustrated_1`: Line:
- `downtime.lines.training_grounds.building_late_frustrated_2`: Line:
- `downtime.lines.training_grounds.building_late_frustrated_3`: Line:

### The roll that finishes it

- `downtime.lines.training_grounds.done_1`: Line:
- `downtime.lines.training_grounds.done_2`: Line:
- `downtime.lines.training_grounds.done_3`: Line:

---

## 5. The Training Grounds (once built)

The built location is a full-screen scene (the jousting video) with one card:
the player's heroes, one row each. A row shows the hero's portrait, name,
"Level N Ancestry Class", an XP bar, and then one of these:

- a **Level Up** button, when they have enough XP;
- a **Finish Your Level** button, when an earlier Level up was closed with
  choices left unmade;
- otherwise, a short line saying why they can't Level yet.

Level Up raises the hero one Level and opens the Builder on the new Level's
page. A hero with XP for two Levels gets the button again afterwards.

### The card's heading

- `traininggrounds.intro`: a short line at the top of the card (shown large, in italics).
  Town Hall: *The council holds votes. Shape the future of Blackbottom by voting wisely!*
  Line:
- `traininggrounds.explainer`: one or two sentences on how it works: XP comes from Victories at a respite, and here they turn into Levels.
  Line:
- `traininggrounds.heroes_heading`: the heading over the list of heroes (shown in capitals).
  Line:

### A hero's row

The "Level 3 Human Fury" line under the name reuses the roster's existing
wording, so it isn't listed here.

- `traininggrounds.row.xp`: on or beside the XP bar. `{xp}` is the XP into this Level, `{per}` the XP a Level takes (16).
  Hero sheet: *{xp} of {per} XP to Level {level}.*
  Line:
- `traininggrounds.row.ready`: replaces that when they have enough XP. `{level}` is the Level they can reach.
  Hero sheet: *{xp} XP: enough for Level {level}.*
  Line:
- `traininggrounds.row.more_levels.one` / `.other`: shown on a hero with XP for more than one Level. `{count}` is how many Levels.
  Line (.one):
  Line (.other):

### The buttons

- `traininggrounds.level_up_button`: the button (1-3 words).
  Line:
- `traininggrounds.level_up_tooltip`: its hover. `{hero}` is the hero's name, `{level}` the new Level.
  Line:
- `traininggrounds.finish_button`: the button for a Level up left unfinished.
  Line:
- `traininggrounds.finish_tooltip`: its hover. `{hero}` is the hero's name.
  Line:

### Why a hero can't Level (shown instead of a button)

- `traininggrounds.reason.xp`: not enough XP yet. `{need}` is the XP still needed, `{level}` the next Level.
  Line:
- `traininggrounds.reason.maxlevel`: already at the top Level.
  Line:
- `traininggrounds.reason.away`: out on an encounter right now.
  Line:
- `traininggrounds.reason.notloaded`: the hero is still loading on this machine (rare, brief).
  Line:
- `traininggrounds.reason.banked.one` / `.other` *(optional)*: added when the hero has Victories not yet turned into XP. `{count}` is the Victories. Points them to the inn.
  Line (.one):
  Line (.other):

### Empty and error states

- `traininggrounds.empty`: the player has no heroes yet. Point them to the Hero's Guild.
  Town Hall: *You need a hero in Blackbottom to vote or raise a petition. Visit the Hero's Guild.*
  Line:
- `traininggrounds.error.not_connected`: offline.
  Town Hall: *Not connected to the town.*
  Line:
- `traininggrounds.error.could_not_open`: the Level up could not start (the hero changed since the row was drawn).
  Line:

### After the Builder closes

- `traininggrounds.done.finished`: a short note when they made every choice. `{hero}` is the name, `{level}` the new Level.
  Line:
- `traininggrounds.done.unfinished`: when they closed it with choices left. `{hero}` is the name.
  Line:

### Flavor *(optional)*

A trainer or a crowd voice that greets the player, and a cheer on a Level up.
Leave these blank if you'd rather the place speak for itself.

- `traininggrounds.greeting_1`: Line:
- `traininggrounds.greeting_2`: Line:
- `traininggrounds.greeting_3`: Line:
- `traininggrounds.cheer_1`: Line:
- `traininggrounds.cheer_2`: Line:
- `traininggrounds.cheer_3`: Line:

---

## 6. Existing lines that change meaning

Once the Training Grounds stand, a respite at the Blue Fish Inn only turns
Victories into XP. The Level up happens here. These lines already exist; tell
me if you want different wording.

- `herosheet.card.respite_line` (in `EotwTextHeroes.lua`): today *A respite would Level this Hero.*, which stops being true once the Grounds are built. A new line for after:
  `herosheet.card.respite_line_grounds`: Line:
- `herosheet.card.ready_line`: today *Head to the Training Grounds to Level your Hero.* Already right; no change unless you want one.
