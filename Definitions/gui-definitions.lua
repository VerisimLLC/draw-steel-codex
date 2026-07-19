--- @class PanelArgsBase:StyleArgs
--- @field keybind nil|(fun(panel:Panel, bind:string):nil)
--- @field monitor nil|(fun(panel:Panel):nil)
--- @field closePopup nil|(fun(panel:Panel):nil)
--- @field delete nil|(fun(panel:Panel):nil) @Fired when the delete key is pressed.
--- @field change nil|(fun(panel:Panel):nil) @Fired when the value managed by this panel is changed.
--- @field click nil|(fun(panel:Panel):nil) @Fired when this panel is clicked.
--- @field rightClick nil|(fun(panel:Panel):nil) @Fired when this panel is right-clicked.
--- @field rendered nil|(fun(panel:Panel,width:number,height:number):nil) @Fired when this panel is first rendered.
--- @field enable nil|(fun(panel:Panel):nil)
--- @field disable nil|(fun(panel:Panel):nil)
--- @field create nil|(fun(panel:Panel):nil)
--- @field think nil|(fun(panel:Panel):nil) @Fired every thinkTime seconds.
--- @field escape nil|(fun(panel:Panel):nil) @Fired when escape is set if the panel has captureEscape set
--- @field refreshGame nil|(fun(panel:Panel):nil) If we are monitoring the game for changes, fires when the part of the game we are monitoring changes.
--- @field imageLoaded nil|(fun(panel:Panel):nil) Fired when the background image this panel uses is loaded.

--- @class PanelEventArgs
--- @field keybind nil|(fun(panel:Panel, bind:string):nil)
--- @field monitor nil|(fun(panel:Panel):nil)
--- @field closePopup nil|(fun(panel:Panel):nil)
--- @field delete nil|(fun(panel:Panel):nil) @Fired when the delete key is pressed.
--- @field change nil|(fun(panel:Panel):nil) @Fired when the value managed by this panel is changed.
--- @field click nil|(fun(panel:Panel):nil) @Fired when this panel is clicked.
--- @field rightClick nil|(fun(panel:Panel):nil) @Fired when this panel is right-clicked.
--- @field rendered nil|(fun(panel:Panel,width:number,height:number):nil) @Fired when this panel is first rendered.
--- @field enable nil|(fun(panel:Panel):nil)
--- @field disable nil|(fun(panel:Panel):nil)
--- @field create nil|(fun(panel:Panel):nil)
--- @field think nil|(fun(panel:Panel):nil) @Fired every thinkTime seconds.
--- @field escape nil|(fun(panel:Panel):nil) @Fired when escape is set if the panel has captureEscape set
--- @field refreshGame nil|(fun(panel:Panel):nil) If we are monitoring the game for changes, fires when the part of the game we are monitoring changes.
--- @field imageLoaded nil|(fun(panel:Panel):nil) Fired when the background image this panel uses is loaded.

--- @module DockablePanel
--- DockablePanel = {}

--- Register a dockable panel.
--- @param args {name: string, icon: nil|string, minHeight: nil|number, vscroll: nil|boolean, dmonly: nil|boolean, content = (fun(): Panel)}
function DockablePanel.Register(args)
end