--[[
 Block Editor: the "Simple" editors for abilities, triggered abilities,
 classes and (later) titles, perks, kits, items and monsters. A record is
 shown as a stack of coloured blocks, each one sentence with words the author
 can change, instead of a form.

 Full design: BLOCK_EDITOR_IMPLEMENTATION_PLAN.md. The decision ledger at the
 end of BLOCK_EDITOR_FRAMEWORK.md is authoritative where the two differ.

 - Overall Design
 - Where Things Live
 - Responding to Events
 - Managing State, Undo and Saving
 - Helper Functions
 - Files
 - What Is Built So Far

 OVERALL DESIGN

 The module is organised like the Character Builder beside it
 (Draw Steel Character Builder/CharacterBuilder.lua): one controller panel
 holds a state object and a host; panels below it never write data
 themselves. They fire an event on the controller, the controller changes the
 state, and one refresh event goes back down the tree.

 Blocks are a view over the engine's own records. Nothing is migrated: a
 record the editor cannot show is routed to today's editor, which is called
 the Advanced editor everywhere (BlockEditor.Routes).

 WHERE THINGS LIVE

 Every registry is data on the Block global (DMHub Utils/Block.lua), declared
 beside the game types in the rules files: blocks, colour groups, hosts, gain
 events, stats, tests, triggers, wrappers and recipes. This module only READS
 them. Adding a block or a whole host never edits a file in this folder.

 Two rules follow from that, and a CI grep checks the first:

  * No file in this folder may name a modifier, behaviour or choice type id.
  * The module's only registration point is BlockEditor.RegisterSlotWidget,
    for a new kind of slot control.

 There are no host-specific UI files. A host's page is built from its
 Block.RegisterHost declaration.

 RESPONDING TO EVENTS

 Any change: a panel calls _fireControllerEvent(element, "editorChange", ...)
 (or another controller event). The controller runs BEState:Change and then
 fires __refreshEditorState__ on its whole tree with (state, changedIds).

 When responding to refreshEditorState, a panel that is hidden (another tab,
 a collapsed section) should return early and halt the event. Only the block
 that changed should redraw; never rebuild a whole stack for one edit.

 Big panels (a section's features, the shelf, the proofs) are built on first
 use. Deferred work (uploads, drag auto-scroll) checks mod.unloaded first.

 MANAGING STATE, UNDO AND SAVING

 BEState (State.lua) holds one small plain-table model per record, the undo
 and redo stacks, and the set of records with unsaved changes. Undo works on
 the model; the server only ever receives whole records, through the host's
 upload function, two seconds after the last change, on tab switch and on
 close. See plan section 12.

 HELPER FUNCTIONS

 Helpers live on BlockEditor in this file and are aliased as locals where
 they are used. Private names start with an underscore.

 _getController(element)
 The controller panel above a panel (or the panel itself). Editors can be
 nested (the ability editor opens inside the class builder), so the
 controller is found from the element, never from a global.

 _fireControllerEvent(element, eventName, ...)
 Fires an event on that controller.

 _getState(element) / _getHost(element)
 The controller's BEState and BlockEditorHost.

 FILES (load order)

 BlockEditor.lua      this file: design, constants, helpers, RegisterSlotWidget (load first)
 State.lua            BEState: the editing model, undo/redo, uploads
 BlockEditorText.lua  every string the UI shows (UIText)
 Styles.lua           BEStyles: sizes, chrome styles, block colours and glyphs
 RecordCache.lua      BERecordCache: a record opened into blocks and saved back
 Slots.lua            BESlots: a block's sentence, one word panel per word
 BlockPanel.lua       BEBlockPanel: one placed block and its bodies
 Stack.lua            BEStack: a list of blocks, drop slots, dragging
 Shelf.lua            BEShelf: the column of blocks to add
 Page.lua             BEPage: the host's sections
 SidePanel.lua        BESidePanel: the checks and the book-style card
 MainPanel.lua        the controller: BlockEditor.Open / Routes, /blockeditor
 RoundTrip.lua        /blockroundtrip: every listed record saves back unchanged
 Proofs.lua           /blockproofs: developer-only checks of what the engine can draw
 Main.lua             empty placeholder in the mod's file list

 Only BlockEditor.lua must load first; the others reach each other only when
 the editor opens.

 WHAT IS BUILT SO FAR (phase 2)

 The ability host (Draw Steel Core Rules/MCDMAbilityBlocks.lua) reads every
 class ability into blocks and saves it back; blocks are declared beside the
 behaviour types. Saving to the server through the containing record
 (milestone 2c) is not built yet, and BlockEditor.Routes returns false.
]]

local mod = dmhub.GetModLoading()

--- What the editor needs from where a record lives. The editor never writes
--- data itself: every save goes through upload. (Plan section 4.)
--- @class BlockEditorHost
--- @field id string the Block host id, or "demo" for the developer window
--- @field canWrite fun(): boolean whether this user may change the record
--- @field upload fun(record: table|nil, model: BERecordModel): boolean|nil saves one model; record is the private copy it was opened from. False (or an error) keeps it dirty to try again
--- @field decl nil|BlockHost the Block.RegisterHost declaration the page is built from
--- @field immediate? boolean save after every change instead of after a pause (an editor inside another, which uploads)
--- @field track? fun(model: BERecordModel, record: table) names the live record a model saves into

--- A control that edits one kind of slot.
--- @class BESlotWidget
--- @field kind string the BlockSlot kind it edits
--- @field create fun(args: table): Panel|nil builds the control (opened as a popup at the word)

--- @class BlockEditor
BlockEditor = {}

--The class on the controller panel; _getController looks for it.
BlockEditor.CONTROLLER_CLASS = "beController"

--The event the controller fires down its tree after any change.
BlockEditor.REFRESH_EVENT = "refreshEditorState"

--How many undo steps are kept (plan section 12).
BlockEditor.UNDO_LIMIT = 100

--The developer setting the editor sits behind until a record type round-trips
--(plan section 7); then it becomes the Simple tab beside the Advanced editor.
BlockEditor.SETTING_ID = "blockeditor:enabled"
setting{
    id = BlockEditor.SETTING_ID,
    section = "dev",
    text = "Block Editor (in development)",
    description = "Turns on the Block Editor's developer commands: /blockeditor, /blockroundtrip and /blockproofs. Needs developer mode.",
    storage = "preference",
    editor = "check",
    default = false,
}

--Seconds after the last change to a record before it uploads.
BlockEditor.UPLOAD_DELAY = 2

--How often the controller checks for uploads that are due, while any are.
BlockEditor.UPLOAD_THINK_TIME = 0.5

--[[
    Slot widgets: the module's one registration point
]]

--- @type table<string, BESlotWidget>
local g_slotWidgets = {}

--- Registers the control for a kind of slot. Registering a kind again
--- replaces it.
--- @param widget BESlotWidget
function BlockEditor.RegisterSlotWidget(widget)
    if type(widget) ~= "table" or type(widget.kind) ~= "string" or type(widget.create) ~= "function" then
        dmhub.Error("BlockEditor: RegisterSlotWidget needs { kind = <string>, create = <function> }")
        return
    end
    g_slotWidgets[widget.kind] = widget
end

--- The control registered for a kind of slot, or nil.
--- @param kind string
--- @return BESlotWidget|nil
function BlockEditor.GetSlotWidget(kind)
    return g_slotWidgets[kind]
end

--[[
    Helpers
]]

--- The controller panel above a panel, or the panel itself if it is one.
--- @param element Panel
--- @return Panel|nil
function BlockEditor._getController(element)
    if element == nil or not element.valid then
        return nil
    end
    if element:HasClass(BlockEditor.CONTROLLER_CLASS) then
        return element
    end
    return element:FindParentWithClass(BlockEditor.CONTROLLER_CLASS)
end

--- Fires an event on the controller above a panel.
--- @param element Panel
--- @param eventName string
--- @param ... any
function BlockEditor._fireControllerEvent(element, eventName, ...)
    local controller = BlockEditor._getController(element)
    if controller ~= nil then
        controller:FireEvent(eventName, ...)
    end
end

--- The editing state of the controller above a panel.
--- @param element Panel
--- @return BEState|nil
function BlockEditor._getState(element)
    local controller = BlockEditor._getController(element)
    if controller == nil then
        return nil
    end
    return controller.data.state
end

--- The host of the controller above a panel.
--- @param element Panel
--- @return BlockEditorHost|nil
function BlockEditor._getHost(element)
    local controller = BlockEditor._getController(element)
    if controller == nil then
        return nil
    end
    return controller.data.host
end

--- Whether the developer-only parts (the commands, the proofs) are available.
--- @return boolean
function BlockEditor._isDeveloper()
    return devmode() == true and dmhub.GetSettingValue(BlockEditor.SETTING_ID) == true
end
