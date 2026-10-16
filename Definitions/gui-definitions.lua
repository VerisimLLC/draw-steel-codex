---@meta

--- Event handlers receive the panel, then any extra arguments the firing call passed. The
--- engine (SheetPanel.cs) fires these with none, except keybind (the bind id) and rendered
--- (width, height); Lua FireEvent/FireEventTree calls can pass more to any of them.
--- @class PanelArgsBase:StyleArgs
--- @field keybind nil|string|(fun(panel:Panel, bind:string, ...:any):nil)
--- @field monitor nil|string|(fun(panel:Panel, ...:any):nil)
--- @field closePopup nil|string|(fun(panel:Panel, ...:any):nil)
--- @field delete nil|string|(fun(panel:Panel, ...:any):nil) @Fired when the delete key is pressed.
--- @field change nil|string|(fun(panel:Panel, ...:any):nil) @Fired when the value managed by this panel is changed.
--- @field click nil|string|(fun(panel:Panel, ...:any):nil) @Fired when this panel is clicked.
--- @field rightClick nil|string|(fun(panel:Panel, ...:any):nil) @Fired when this panel is right-clicked.
--- @field rendered nil|string|(fun(panel:Panel,width:number,height:number, ...:any):nil) @Fired when this panel is first rendered.
--- @field enable nil|string|(fun(panel:Panel, ...:any):nil)
--- @field disable nil|string|(fun(panel:Panel, ...:any):nil)
--- @field create nil|string|(fun(panel:Panel, ...:any):nil)
--- @field think nil|string|(fun(panel:Panel, ...:any):nil) @Fired every thinkTime seconds.
--- @field escape nil|string|(fun(panel:Panel, ...:any):nil) @Fired when escape is set if the panel has captureEscape set
--- @field refreshGame nil|string|(fun(panel:Panel, ...:any):nil) If we are monitoring the game for changes, fires when the part of the game we are monitoring changes.
--- @field imageLoaded nil|string|(fun(panel:Panel, ...:any):nil) Fired when the background image this panel uses is loaded.

--- @class PanelEventArgs
--- @field keybind nil|string|(fun(panel:Panel, bind:string, ...:any):nil)
--- @field monitor nil|string|(fun(panel:Panel, ...:any):nil)
--- @field closePopup nil|string|(fun(panel:Panel, ...:any):nil)
--- @field delete nil|string|(fun(panel:Panel, ...:any):nil) @Fired when the delete key is pressed.
--- @field change nil|string|(fun(panel:Panel, ...:any):nil) @Fired when the value managed by this panel is changed.
--- @field click nil|string|(fun(panel:Panel, ...:any):nil) @Fired when this panel is clicked.
--- @field rightClick nil|string|(fun(panel:Panel, ...:any):nil) @Fired when this panel is right-clicked.
--- @field rendered nil|string|(fun(panel:Panel,width:number,height:number, ...:any):nil) @Fired when this panel is first rendered.
--- @field enable nil|string|(fun(panel:Panel, ...:any):nil)
--- @field disable nil|string|(fun(panel:Panel, ...:any):nil)
--- @field create nil|string|(fun(panel:Panel, ...:any):nil)
--- @field think nil|string|(fun(panel:Panel, ...:any):nil) @Fired every thinkTime seconds.
--- @field escape nil|string|(fun(panel:Panel, ...:any):nil) @Fired when escape is set if the panel has captureEscape set
--- @field refreshGame nil|string|(fun(panel:Panel, ...:any):nil) If we are monitoring the game for changes, fires when the part of the game we are monitoring changes.
--- @field imageLoaded nil|string|(fun(panel:Panel, ...:any):nil) Fired when the background image this panel uses is loaded.
--- @field [string] nil|string|(fun(panel:Panel, ...:any):any) Any other event by name: engine events (hover, dehover, press, linger, destroy, refreshAssets, ...) or a custom event fired with FireEvent/FireEventTree.

--- The standard events again, on each engine widget's Args class with the panel typed as
--- that widget, so a handler written in gui.Label{...}, gui.Input{...} or gui.TextEditor{...}
--- gets a Label/Input/TextEditor `element` with no ---@cast. A subclass field overrides the
--- inherited PanelArgsBase one. Custom events are not covered: a [string] catch-all here would
--- also land on the instance (Label extends LabelArgs) and turn off undefined-field on it.
--- @class LabelArgs
--- @field keybind nil|string|(fun(panel:Label, bind:string, ...:any):nil)
--- @field monitor nil|string|(fun(panel:Label, ...:any):nil)
--- @field closePopup nil|string|(fun(panel:Label, ...:any):nil)
--- @field delete nil|string|(fun(panel:Label, ...:any):nil)
--- @field change nil|string|(fun(panel:Label, ...:any):nil)
--- @field click nil|string|(fun(panel:Label, ...:any):nil)
--- @field rightClick nil|string|(fun(panel:Label, ...:any):nil)
--- @field rendered nil|string|(fun(panel:Label, width:number,height:number, ...:any):nil)
--- @field enable nil|string|(fun(panel:Label, ...:any):nil)
--- @field disable nil|string|(fun(panel:Label, ...:any):nil)
--- @field create nil|string|(fun(panel:Label, ...:any):nil)
--- @field think nil|string|(fun(panel:Label, ...:any):nil)
--- @field escape nil|string|(fun(panel:Label, ...:any):nil)
--- @field refreshGame nil|string|(fun(panel:Label, ...:any):nil)
--- @field imageLoaded nil|string|(fun(panel:Label, ...:any):nil)

--- @class InputArgs
--- @field keybind nil|string|(fun(panel:Input, bind:string, ...:any):nil)
--- @field monitor nil|string|(fun(panel:Input, ...:any):nil)
--- @field closePopup nil|string|(fun(panel:Input, ...:any):nil)
--- @field delete nil|string|(fun(panel:Input, ...:any):nil)
--- @field change nil|string|(fun(panel:Input, ...:any):nil)
--- @field click nil|string|(fun(panel:Input, ...:any):nil)
--- @field rightClick nil|string|(fun(panel:Input, ...:any):nil)
--- @field rendered nil|string|(fun(panel:Input, width:number,height:number, ...:any):nil)
--- @field enable nil|string|(fun(panel:Input, ...:any):nil)
--- @field disable nil|string|(fun(panel:Input, ...:any):nil)
--- @field create nil|string|(fun(panel:Input, ...:any):nil)
--- @field think nil|string|(fun(panel:Input, ...:any):nil)
--- @field escape nil|string|(fun(panel:Input, ...:any):nil)
--- @field refreshGame nil|string|(fun(panel:Input, ...:any):nil)
--- @field imageLoaded nil|string|(fun(panel:Input, ...:any):nil)

--- @class TextEditorArgs
--- @field keybind nil|string|(fun(panel:TextEditor, bind:string, ...:any):nil)
--- @field monitor nil|string|(fun(panel:TextEditor, ...:any):nil)
--- @field closePopup nil|string|(fun(panel:TextEditor, ...:any):nil)
--- @field delete nil|string|(fun(panel:TextEditor, ...:any):nil)
--- @field change nil|string|(fun(panel:TextEditor, ...:any):nil)
--- @field click nil|string|(fun(panel:TextEditor, ...:any):nil)
--- @field rightClick nil|string|(fun(panel:TextEditor, ...:any):nil)
--- @field rendered nil|string|(fun(panel:TextEditor, width:number,height:number, ...:any):nil)
--- @field enable nil|string|(fun(panel:TextEditor, ...:any):nil)
--- @field disable nil|string|(fun(panel:TextEditor, ...:any):nil)
--- @field create nil|string|(fun(panel:TextEditor, ...:any):nil)
--- @field think nil|string|(fun(panel:TextEditor, ...:any):nil)
--- @field escape nil|string|(fun(panel:TextEditor, ...:any):nil)
--- @field refreshGame nil|string|(fun(panel:TextEditor, ...:any):nil)
--- @field imageLoaded nil|string|(fun(panel:TextEditor, ...:any):nil)

--- DockablePanel is implemented in the codex (DMHub Core UI/DockablePanel.lua).
--- Its table-constructor members are declared here because LuaLS binds this class
--- to this declaration, so fields in the codex's `DockablePanel = {...}` literal are
--- not seen. Members the codex adds with `DockablePanel.X = function` (StartProcess,
--- StopProcess, GetProcess, HasActiveProcess) are picked up from the codex directly.
--- @class DockablePanel
--- @field ContentWidth number Width in pixels of a docked panel's content.
--- @field DockWidth number Width in pixels of a side dock, before the dock scale.
--- @field FloatingDockMargin number Horizontal margin in pixels around a panel on the floating (center) dock.
DockablePanel = {}

--- Register a dockable panel.
--- @param args {name: string, icon: nil|string, minHeight: nil|number, vscroll: nil|boolean, dmonly: nil|boolean, content: (fun(): Panel)}
function DockablePanel.Register(args)
end

--- Remove the registration with this name, if any.
--- @param name string
function DockablePanel.Deregister(name)
end

--- May the local user have this panel at all (devonly needs dev mode, dmonly the Director UI,
--- and a custom interface may suppress it)? A nil registration returns true.
--- @param registration table|nil A registration from GetRegistration.
--- @return boolean
function DockablePanel.PanelPermittedForUser(registration)
end

--- The dock scale in effect: 1 while the icon rail is on, otherwise the dockscale setting.
--- @return number
function DockablePanel.EffectiveDockScale()
end

--- Open a panel by its registered name (case-insensitive), or raise it if it is open.
--- @param name string|nil
--- @return boolean found True if a panel by that name is registered.
function DockablePanel.ShowPanelByName(name)
end

--- Toggle, show or hide the panel whose menu text matches this name (case-insensitive).
--- @param name string
--- @param operation? 'toggle'|'show'|'hide' Defaults to toggle.
--- @return boolean found True if a menu item by that name exists.
function DockablePanel.LaunchPanelByName(name, operation)
end

--- The registration table for a panel name (case-insensitive): the args passed to
--- Register plus modid, guid and identifier. Nil if no such panel is registered.
--- @param name string
--- @return table|nil
function DockablePanel.GetRegistration(name)
end

--- Registrations whose new-content alert is lit and which offer a way to clear it.
--- @return table[]
function DockablePanel.GetAlertedRegistrations()
end

--- Names of the panels docked in one side's dock, in order.
--- @param side string "left" or "right".
--- @return string[]
function DockablePanel.GetDockPanels(side)
end

--- Replace the panels docked in one side's dock with these panels, in this order.
--- @param side string "left" or "right".
--- @param names string[]
function DockablePanel.SetDockPanels(side, names)
end

--- Menu items for the registered panels the user may open: {id, name, identifier, text,
--- icon, bind, check, click = fun(operation), ...}, or folder items with a submenu.
--- @param flat? boolean Do not group panels into folder submenus.
--- @param includeFiltered? boolean Include panels that hide themselves from the menus.
--- @return table[]
function DockablePanel.GetMenuItems(flat, includeFiltered)
end

--- The open instance of a panel, by registration identifier, or nil.
--- @param identifier string
--- @return Panel|nil
function DockablePanel.FindInstance(identifier)
end

--- Every open panel instance, keyed by registration identifier.
--- @return table<string, Panel>
function DockablePanel.GetAllInstancesByIdentifier()
end

--- Save the current dock layout to the panels setting.
function DockablePanel.Serialize()
end

--- Rebuild the docks from the saved layout.
function DockablePanel.Deserialize()
end