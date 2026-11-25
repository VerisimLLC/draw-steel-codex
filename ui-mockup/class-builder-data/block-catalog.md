# Blocks the class builder has (2026-11-25)

- **Choose a perk** (`perkChoice`, group skill): The player picks perks from the groups you name.
- **Have or choose skills** (`skills`, group skill): Skills the hero always has, plus any the player chooses from skill groups or a list you name.
- **Raise a characteristic** (`charChoice`, group stats): The player raises one characteristic of their choice by 1, up to the maximum you set.
- **Choose an ability** (`abilityChoice`, group abil): The player picks abilities from a list you build here (signature, or heroic with a cost).
- **Choose your subclass** (`subclassChoice`, group res): The player chooses their subclass (College, Circle, Domain...).
- **Change a stat** (`stat`, group stats): Raise, lower or set one of the hero's numbers: Stamina, speed, stability, a characteristic...
- **Movement type** (`move`, group stats): A movement type: fly, climb, swim or burrow.
- **You ignore / can't...** (`flag`, group stats): A special rule the hero follows, such as Ignore Difficult Terrain.
- **Edge or bane on rolls** (`edge`, group rolls): An edge or bane on tests (by skill) or on ability rolls (by keyword).
- **Rolls against you** (`enemy`, group rolls): Abilities used against you have a bane (or edge).
- **Extra damage** (`damage`, group rolls): Your abilities deal extra damage, optionally only with some keywords or a damage type.
- **Change the outcome** (`outcome`, group rolls): Change a roll's outcome: always tier 3, never tier 1, one tier better or worse. Optionally for a cost.
- **Change potency** (`potency`, group rolls): Raise or lower the potency of your abilities (or of ones used against you). Optionally for a cost.
- **Forced movement bonus** (`moveBonus`, group rolls): Your abilities' forced movement (push, pull, slide) goes further, by a number or formula.
- **Roll differently** (`replaceRoll`, group rolls): Tests (or ability rolls) roll different dice, such as 3d10, keep the highest 2.
- **Change forced movement** (`moveSwap`, group rolls): Forced movement of one kind can be done as another (push as slide...).
- **Change damage type** (`dmgType`, group rolls): Your abilities' damage (all of it, or one type) can be dealt as another type instead.
- **Surge damage type** (`surgeType`, group rolls): When the roll has surges, the player can make the surge damage a type you pick (acid, fire...).
- **Extra surges** (`surges`, group rolls): Your ability rolls gain surges. Optionally only with some keywords, or for a cost.
- **Immunity or weakness** (`immunity`, group def): Damage immunity or weakness to one or more types.
- **Can't be (condition)** (`condImm`, group def): You can't gain the conditions you pick.
- **You know a language** (`language`, group skill): You know the languages you pick.
- **Recoveries or a resource** (`resource`, group res): You have a number of Recoveries (or another resource).
- **Kit** (`kit`, group res): You can use and gain the benefits of a martial or caster kit.
- **Gain an ability** (`ability`, group abil): Give the hero an ability. You build it in the ability editor.
- **Gain a triggered ability** (`trigger`, group abil): Give the hero an ability they use in response to something happening. You build it in the ability editor.
- **Change an ability** (`modAbility`, group abil): Change an ability: more distance, more targets, or a keyword.
- **Add to an ability** (`abilityAddon`, group abil): When you use an ability, it also does more: extra steps built in the ability editor, and text added to its card.
- **Reminder text** (`reminder`, group res): A note on the hero's sheet, for a rule the game can't apply for you. It doesn't change anything in play.
- **Growing table** (`growing`, group res): Benefits that switch on as the hero's resource climbs during a turn, like the Fury's Growing Ferocity. Each row says what the hero gets at that amount; a later row can replace an earlier one.
- **Aura** (`aura`, group abil): An area around you: the blocks inside apply to creatures in it (you and your allies, enemies...).
- **Your companion** (`companionMods`, group abil): The blocks inside apply to your companion instead of you.
- **Your summons** (`summonerMods`, group abil): The blocks inside apply to the creatures you summon (or, set to summoner, to you from your summons).
- **Choose from options** (`optionChoice`, group res): The player picks one (or more) of the options you build here; each option is its own set of blocks.
- **Engine choice** (`simpleChoice`, group res): A choice from a list the game keeps (a deity, a companion).
- **Combined roll change** (`rollCombo`, group rolls): Roll changes that apply together, saved as one power roll modifier.
- **Logic** (`onlyIf`, group if): The blocks inside apply only while something is true: you're Strained, winded or prone, you have enough Victories, it's your turn...

Roll blocks share the options: "Offered when [test]", "on [any roll / rolls with surges / an edge / no bane...]", "Automatically selected [always / when [test] / never / always and it costs N / never and it costs N]". Roll blocks with the same keywords can be combined into one power modifier. Edge block options: an edge, a double edge, a bane, a double bane, a bane removed, an edge removed, banes ignored, edges ignored, a +1 bonus, a +2 bonus, a +3 bonus, a -1 penalty, a -2 penalty, a -3 penalty. Outcome options: have a tier 3 outcome, can't have a tier 1 outcome, are improved by one tier, are worsened by one tier, can't have a tier 3 outcome, have a tier 1 outcome. Rolls: tests (by characteristic and skill), opposed tests, ability rolls (by keyword), all power rolls.

Logic ("Only if [test]") wraps any non-choice blocks; tests include: conditions, winded, dying, Stamina, Victories, level, characteristics, the heroic resource (now / most this turn), effects, keywords, nearby creatures, whose turn, in combat, Strained, or any GoblinScript formula.

How you gain the heroic resource: start-of-turn gain (set amount or die, + per-level steps) and event gains (combat starts, first time each round you deal/take damage, winded, dying, force move, use an ability, or any trigger event) with amounts that can change by level.

The "Gain an ability" / "Gain a triggered ability" blocks open the full ability editor (damage, conditions, forced movement, effects, follow-up abilities, auras, summons, resources, power roll triggers...).
