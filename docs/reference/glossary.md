# Glossary

Key terms used throughout the Draw Steel Codex codebase and the Draw Steel TTRPG system.

---

## DMHub Engine Terms

| Term | Definition |
|------|-----------|
| **Game Type** | A registered type in the engine's serialization system. Created with `RegisterGameType()`. Game types define how objects are stored, loaded, and identified across sessions. |
| **Data Table** | Named persistent storage for game content definitions (creatures, classes, items, etc.). Accessed via `dmhub.GetTable()`. Each table holds entries keyed by a unique ID. |
| **Token** | A creature instance placed on the game map. Has `.properties` that hold its game state (stamina, conditions, resources, etc.). Tokens are the runtime representation of creatures. |
| **Shared Document** | Real-time cloud-synced key-value storage for session state. Accessed via `mod:GetDocumentSnapshot()`. Used to share data between the Director and players during a live game. |
| **Module** | A directory of Lua files loaded by DMHub. Named `ModuleName_XXXX` where `XXXX` is a hex ID (e.g., `Draw_Steel_Core_Rules_1b8f`). Each module groups related functionality. |
| **Panel** | A UI element in the declarative panel system. Created with `gui.Panel{}`. Panels are the building blocks of all DMHub user interfaces. |
| **DockablePanel** | A panel registered with `DockablePanel.Register` that appears in the sidebar. Used for persistent tool windows like the compendium, encounter panel, and character sheet. |
| **GoblinScript** | A pure functional expression language for game formulas. Used for damage expressions, ability costs, prerequisites, and any value that needs to be computed at runtime. |
| **Transient Field** | A field prefixed with `_tmp_` that is skipped during serialization. Used for runtime-only state such as UI caches and intermediate calculations that should not be saved. |
| **ModifyProperties** | The required wrapper for mutating token properties outside the character sheet. All property changes on a token must go through this call to ensure proper synchronization and event firing. |

## Draw Steel Game Terms

| Term | Definition |
|------|-----------|
| **Stamina** | Draw Steel's equivalent of hit points. When a creature's stamina reaches zero, they are dying or destroyed. |
| **Recoveries** | Resources spent to regain stamina. Heroes have a limited number of recoveries per day; spending one typically restores a fixed amount of stamina. |
| **Power Roll** | The core resolution mechanic. Roll 2d10 against a difficulty tier to determine the outcome. Results fall into three tiers that determine the degree of success or effect. |
| **Characteristics** | Draw Steel's six ability scores: Might, Agility, Reason, Intuition, Presence, plus derived scores. These modify power rolls and determine what a character excels at. |
| **Conditions** | Status effects applied to creatures (Bleeding, Dazed, Frightened, etc.). Conditions modify what a creature can do and are tracked as ongoing effects on the token. |
| **Malice** | A resource the Director (GM) accumulates and spends to activate special villain abilities, lair actions, and other dramatic effects during encounters. |
| **Kit** | An equipment loadout that grants abilities, bonuses, and defines a character's combat style. Characters select a kit during character creation and may change it as they advance. |
| **Ancestry** | A character's species or race (Human, Hakaan, Memonek, etc.). Ancestry provides innate traits, size, speed, and special abilities. |
| **Culture** | A character's background representing where they grew up. Culture provides skill options, language knowledge, and other formative traits. |
| **Surge** | A temporary resource used for extra actions or healing. Surges are a moment of adrenaline that let heroes push beyond their normal limits. |
| **Hero Tokens** | Tokens spent by players to activate heroic abilities. Hero tokens are a shared party resource earned through play and spent for powerful effects. |

## GoblinScript Terms

| Term | Definition |
|------|-----------|
| **Symbol** | A named value in a GoblinScript formula. Common symbols include `Self` (the creature using the ability), `Caster` (the creature who created the effect), and `Target` (the creature being affected). |
| **Expression** | A GoblinScript formula string that evaluates to a value at runtime. Expressions can reference symbols, perform arithmetic, and call built-in functions. |
| **Dice Notation** | The format used to specify dice rolls in GoblinScript. Examples: `2d6` (roll two six-sided dice), `4d8 keep 3` (roll four d8s and keep the highest three), `1d20 reroll 1` (roll a d20, rerolling ones). |
