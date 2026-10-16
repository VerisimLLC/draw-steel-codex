# Shared Documents

Shared Documents provide **real-time cloud-synced key-value storage** across all clients in a game session. They're used for live session state — initiative data, chat events, audio settings, global resources, and downtime project shares.

!!! info "Documents vs. Data Tables"
    [Data Tables](data-tables.md) store game **definitions** (abilities, conditions, classes). Shared Documents store live **session state** (who has initiative, current malice count, shared resources).

## Getting a snapshot

```lua
local doc = mod:GetDocumentSnapshot("drawsteel")
```

The `docid` is any unique string. The returned snapshot has:

- `.data` — The document contents (a Lua table)
- `.path` — A string used for monitoring changes in UI panels

## Reading data

Access fields directly on `.data`:

```lua
local doc = mod:GetDocumentSnapshot(g_sharedGlobalResourceDoc)
if doc.data == nil then return 0 end
local entry = doc.data[resourceid]
```

*Source: `DMHub_Game_Rules_fc51/Resource.lua`*

## Writing data

Wrap mutations in `BeginChange` / `CompleteChange`:

```lua
local doc = mod:GetDocumentSnapshot("drawsteel")
doc:BeginChange()
doc.data.guid = dmhub.GenerateGuid()
doc.data.claims = {}
doc.data.finished = nil
doc.data.delayFinished = nil
doc:CompleteChange("Initialize initiative")
```

*Source: `Draw_Steel_UI_bd58/DSInitiativeRoll.lua`*

`CompleteChange` accepts:

- First arg: a description string
- Optional second arg: options table (e.g., `{undoable = false}`)

## Monitoring changes in UI

Use the `think` callback to poll document state:

```lua
think = function(self)
    local doc = mod:GetDocumentSnapshot("drawsteel")
    if doc.data.finished then
        if doc.data.delayFinished ~= nil then
            self.data.delay = self.data.delay or (dmhub.Time() + doc.data.delayFinished)
            if self.data.delay > dmhub.Time() then return end
        end
    end
end,
```

*Source: `Draw_Steel_UI_bd58/DSInitiativeRoll.lua`*

You can also use `monitorGame` to trigger `refreshGame` when a document changes:

```lua
gui.Panel{
    monitorGame = mod:GetDocumentSnapshot("myDocId").path,
    refreshGame = function(element)
        local doc = mod:GetDocumentSnapshot("myDocId")
        -- update UI from doc.data
    end,
}
```

## Combat checkpoints

Register a document so **Revert Turn** rolls it back along with the rest of the board:

```lua
mod:RegisterDocumentForCheckpointBackups("myDocId")
```

This has nothing to do with saving: ordinary game backups include every document. Register only state the current turn can change and that should be undone with it (resources, Malice, combat logs). Do not register Director or table settings (audio, safety tools, campaign tracking) -- reverting a turn would silently undo them.

## Helper

`mod:GetDocumentPath("myDocId")` returns just the path string (equivalent to `mod:GetDocumentSnapshot("myDocId").path`).

## Key points

- **Get** with `mod:GetDocumentSnapshot(id)` — returns a snapshot with `.data` and `.path`
- **Read** directly from `.data`
- **Write** by wrapping in `BeginChange()` / `CompleteChange(description)`
- **Monitor** with `monitorGame` + `refreshGame` on UI panels, or `think` callbacks
- **Register** for combat checkpoints only if Revert Turn should roll the data back
- Document IDs are arbitrary strings — choose descriptive names
