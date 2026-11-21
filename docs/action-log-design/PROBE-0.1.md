# History chunk 0.1: what a record costs

Measured 2026-11-06 in the live Codex (build 13), game TwistedRainbowWaywornGuardian, on a cloud
game server, with two clients connected: Director and Player accounts on one machine (the app's
"new player window"). The Director client wrote, the Player client watched. Scripts are in
`probes/`; they run over the bridge (`/execute`), fill the `ARG_` values with `sed` first.

The record used was as full as stage 2 will make it, to be safe: two targets, a roll, three named
sources, one trigger, about 3.2 KB of JSON, most of it ids. A stage 0 record is much smaller.

## Result: nested records fail, packed records pass

The design said entries keyed by id, as `BattleLog.RecordBattle` does. Storing each entry as a
nested table does not scale. `BeginChange` deep-copies the whole document and `CompleteChange` walks
it twice to find the difference, so each write costs in proportion to every value in the document
(about 100 values per record).

Storing each entry as one JSON string, still keyed by id, costs a tiny fraction of that, because a
string is one value to copy and compare (`ScriptSerialize.DeepCopy`, `LuaValuePatch`).

Cost of one write, on the writing client, in ms (average; the worst single write in brackets):

| Records in the document | Nested table | One JSON string |
|---|---|---|
| Under 50 | 47 (155) | 1 (3) |
| 100 | 248 (550) | 2 (3) |
| 200 | 462 (695) | 3 (5) |
| 300 | 674 (929) | 4 (5) |
| 450 | not run | 7 (13) |
| 600 | not run | 10 (67) |

The nested run was stopped at 330: the Director client was down to about 2 frames a second.
The worst packed writes (54 to 88 ms) came a few times a run, and are not tied to document size.

## The other client

- Idle, this client runs at 14 ms a frame, worst 41 ms.
- At one write a second with 330 records (the realistic case), frames stay at 14 ms; around most
  arrivals one frame takes about 40 ms. That is the worst frame it shows idle anyway, so a write
  costs at most about 30 ms on the receiving client, on one frame.
- At ten writes a second (far above real play) frames average 18.5 ms.
- Each write arrived 0.8 s after it was stamped, flat at every size. Part of that may be the two
  clients' clocks; it reads as "under a second".

## Reading it back

On the Player client, in ms:

| Records | Document | Find and sort the keys | Parse the newest 40 | Parse everything (search) |
|---|---|---|---|---|
| 330 | 1.26 MB | under 1 | 1 | 16 |
| 614 | 2.34 MB | under 1 | 2 | 28 |

## Joining the game

Restarting the Player client with 660 packed records in the document: the game snapshot went from
1.71 MB to 4.22 MB, and still completed 0.2 s after subscribing here. On a slow connection the
extra size is what counts: about 0.4 MB per 100 full records.

## On the server

All of a mod's documents share one row (`game::modDocuments/{modid}`), rewritten at most every 4 s
while writes come in, and split automatically if it outgrows a row. So History's size is added to
that row. It is not a limit at these sizes.

## Decisions

- **Entries are stored as JSON strings keyed by id.** Same store, same merge behaviour, same
  document per map. The tray parses only the rows it builds, so opening it stays cheap.
- **One write per action, at the end of the cast.** Writes are cheap enough now that this is about
  keeping a cast's facts together, not about cost. Stage 1 should still batch a cast's results.
- **Hard cap 500 entries.** Two encounters fit: about 12 turns a round, 5 rounds, 3 entries a turn
  is 180 an encounter, and big fights reach 240. At 500 a write costs about 8 ms even with
  full-sized records and the document is at most about 1.9 MB. The cap is one constant,
  `History.hardCap`. Check it again in 6.2 with real records.
