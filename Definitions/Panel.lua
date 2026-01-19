--- @class Panel 
--- @field id string The unique id of the panel. If not specified a random id will be assigned. It is important that each panel have a unique ID, so if you assign an ID explicitly ensure it is unique.
--- @field idprefix string The prefix of the panel's id. A random ID will be generated but will begin with this prefix.
--- @field debugBacktrace string|nil 
--- @field inworld any 
--- @field blurBackground any 
--- @field monitorMod string The id of the mod to monitor. When this mod is reloaded the refreshMod event will be fired on the panel.
--- @field monitorAssets AssetCategory|AssetCategory[] (write-only) A list of asset categories to monitor. When the asset categories are updated, the refreshAssets event will be fired on this panel.
--- @field constrainToScreen boolean (default=false) If true, the panel will be constrained to the screen area.
--- @field floating boolean (default=false) A floating panel does not respect the **flow** of its parent. @see Panel.flow
--- @field data table An arbitrary table of user data that is attached to the panel. Store any interesting fields here that you want to have associated with the panel.
--- @field root Panel The root panel of the hierarchy this Panel is within.
--- @field parent Panel The parent panel of this panel. Returns nil if this panel is at the root of its hierarchy.
--- @field siblingIndex number (read-only) Returns the 'sibling index' of this panel. The first child of its parent is 1, the second is 2, and so forth.
--- @field children Panel[] A list of the children of this panel. Note that you may set this panel to a new list of children. Any panels that are left orphaned by doing this are automatically destroyed.
--- @field selfStyle Style|StyleArgs Any style settings that are set directly on this panel. They do not apply to children, only directly to this panel. Note that styles that are set here override any other styling on the panel. Selectors set on this style are ignored.
--- @field style Style|StyleArgs Style settings set on this panel, and all of its hierarchical children. Styles here are lower priority than those set in @see selfStyle but higher priority than other styles. Selectors set on this style are ignored.
--- @field styles StyleArgs[] A list of styles that are applied to this panel and all of its children in the hierarchy. Styles may have their selectors field set and will apply only to panels where the selector criteria matches. Styles set like this are lower priority than @see selfStyle and @see style. Styles that are more specific (have more elements in their selector) are higher priority, and those specified later in the list are higher priority. You can use the priority field to manually set a priority for a style.
--- @field bgimage string|boolean The image to set as the background of this panel. If left unset or set to false the panel will not have a background image. Note that the background image is the main display of most panels, so if this is not set the panel will be invisible, though its children may still be visible. This can be set to true (or 'panels/square.png') to set to a plain white square image (which can then have further styling set to it). It can also be set to an image uploaded in a mod, e.g. bgimage = mod.images.myicon
--- @field bgimageStreamed string (Write-only) This can be set to set the bgimage, but the image is streamed, so the panel may be invisible until it is properly loaded. This is good to do for many panels that may have videos or other long-loading images.
--- @field bgimageInit boolean True if the bgimage for this panel has been loaded. This can be set to true if you want to force the panel to be visible even if its image isn't available yet. If the image isn't available, then it will be displayed as a plain white square.
--- @field bgimageMask string 
--- @field bgimageAlpha string 
--- @field bgimageTokenMask string 
--- @field bgimageTokenMaskInclusive string 
--- @field bgimageMaskInvert number 
--- @field bgimageMaskRect Vector4 
--- @field bgimageWidth number The width of the @see bgimage. This will be -1 if the bgimage hasn't been loaded yet.
--- @field bgimageHeight number The height of the @see bgimage. This will be -1 if the bgimage hasn't been loaded yet.
--- @field x number A horizontal offset in pixels to apply to this panel's positioning. Note that this will be an offset to where the panel is positioned, but will not affect the layout of other panels in the hierarchy. @see translate
--- @field y number A vertical offset in pixels to apply to this panel's positioning. Note that this will be an offset to where the panel is positioned, but will not affect the layout of other panels in the hierarchy. @see translate
--- @field translate Vector2 A vector to translate the panel's position to. This is the same behavior as using @see x and @see y.
--- @field dragThreshold number (Default: 4) How many pixels the panel has to be dragged before it's considered dragging. This is only relevant if @see draggable is true.
--- @field dragDelta Vector2 The pixels the mouse has moved since the drag operation began. Will return (0,0) if the panel is not currently begin dragged..
--- @field playbackSpeed any 
--- @field xdrag number The pixels the panel has been translated horizontally by dragging. 0 if the panel is not currently being dragged.
--- @field ydrag number The pixels the panel has been translated vertically by dragging. 0 if the panel is not currently being dragged.
--- @field enabled boolean (Read-only) This is true if the panel is displayed and active. It's false if the panel is collapsed, hidden, or is being destroyed.
--- @field events PanelEventArgs The events that are registered for this panel. When the event with the key in the table is fired on the panel that function is called. The panel itself is always passed as the first argument, and then any other arguments to the event are passed. Some standard events include 'create', 'hover', 'dehover', 'click', 'press'. Some events are also enabled based on other arguments such as 'refreshAssets' and 'think'. @see thinkTime. You can also fire a user-defined event using @see FireEvent and @see FireEventTree
--- @field hscroll boolean Set this to true to make the panel be horizontally scrollable. The size of the scroll area will be automatically calculated based on the position and size of its children.
--- @field vscroll boolean Set this to true to make the panel be vertically scrollable. The size of the scroll area will be automatically calculated based on the position and size of its children.
--- @field vscrollLockToBottom boolean Set this to true to by default set the scrollbar to lock to the bottom when new content is added to the panel.
--- @field vscrollPosition number The position of the vertical scrollbar, from 0 to 1. 0 = at the bottom, 1 = at the top.
--- @field canFocus boolean True if the panel can accept input focus.
--- @field hasFocus boolean True if the panel currently has input focus.
--- @field inputEvents InputEvent[] A list of input events that this panel subscribes to and receives. When the named input event occurs, the panel will have an event with that name fired on it. Panels are arranged in priority order to receive an event and only one panel will receive the event.
--- @field escapeActivates boolean If true, the 'click' event will be fired on this panel when escape is pressed. This is used for panels that act as though they were clicked on when escape is pressed.
--- @field captureEscape boolean If true, the 'escape' event will be fired on this panel when escape is pressed. Only the panel with the highest @see escapePriority that is active will receive the escape event.
--- @field escapePriority number The priority with which this panel captures escape events compared to other panels.
--- @field draggable boolean If true, this panel can be dragged.
--- @field canDragOnto nil|(fun(thisPanel: Panel, targetPanel: Panel): boolean) This function tells us if this panel can be dragged onto the given target panel. This will only be called on a target panel if @see dragTarget is set to true for the target panel.
--- @field dragTarget boolean If true, this panel may be used as a drag target for other panels -- other panels may be dragged onto it. @see canDragOnto will still be called on the panel being dragged to confirm it can be dragged onto this panel.
--- @field dragTargetPriority number If a panel is dragged and overlapping multiple potential target panels, the higher dragTargetPriority panel will take precendence as the drag target.
--- @field dragging boolean (read-only) true if the panel is currently being dragged.
--- @field dragBounds Vector4 A bounding box for dragging that the panel may not go outside of when dragged.
--- @field dragMove boolean (Write-only) if set to true, the panel will be physically moved when dragged. If false, the panel will receive drag events but won't be moved when dragged.
--- @field dragxwrap boolean (write-only) if set to true, if @see dragBounds is set, the panel will wrap around if it goes outside of the bounds horizontally.
--- @field dragywrap boolean (write-only) if set to true, if @see dragBounds is set, the panel will wrap around if it goes outside of the bounds vertically.
--- @field monitor string|string[]|(fun(Panel):nil) (write-only) A setting id or list of setting ids to 'monitor'. When one of these game settings changes, the 'monitor' event is fired on this panel. This allows a panel to be responsive to changes in a setting's value and allows multiple panels to collaborate in managing a setting.
--- @field monitorValue any The current value of the setting that this panel is monitoring. Should only be used if the panel is monitoring a single setting.
--- @field valid boolean (read-only) True if the panel is valid and working. If the panel has been destroyed this is false. If you save a reference to a panel between events, you should always check that the panel is valid before using it. If the panel is not valid then it will not be safe to use at all.
--- @field className string The class of the panel. Classes may be any string of your choosing and are used to select panels for styling and other purposes. Usually you will want to use the more general @see classes which can set multiple classes on a panel.
--- @field classes string[] The classes the panel belongs to. Classes can be strings of your choice and are used by the styling system to identify which panels a style should apply to. The selectors of a style can be used to check a panel is in a certain class when choosing whether to apply the style to the panel.
--- @field tooltip string|Panel|nil When this property is set, the given panel will appear over this element as a tooltip. The tooltip will be disappear automatically when the user moves the mouse away from the panel. It is usually best to set this in response to the 'hover' event. This property will always read as a Panel, but you can set a string, in which case the CreateTooltipPanel global function will be called to create the tooltip panel. Tooltips may have halign and valign styles set on them to control their positioning relative to their parent.
--- @field tooltipParent Panel The panel to which tooltips spawned from this panel will be parented. By default this will be equal to the panel itself, but you may wish to spawn tooltips from a parent panel instead.
--- @field popupPositioning Panel|"mouse"|"panel" The positioning of @see popup panels spawned from this panel. They can be positioned relative to this panel, or to the mouse position at the time of spawning the popup. You can also specify a different panel which they will be positioned relative to. You can set valign and halign on popup panels to specify how they will be placed relative to their positioning.
--- @field popup Panel|nil When this property is set to a panel, that panel will be spawned and placed as a 'popup' over this panel. Popup panels are similar to tooltips in their behavior, but they are removed differently. Usually tooltips are very transient and removed when the user moves the mouse, and cannot be interacted with. Popup panels can be interacted with, and remain until the user clicks away from them, or you manually set popup to nil. Popups are useful for implementing context menus and other small interactive dialogs.
--- @field interactable boolean (default: true) If this is set to false then the panel becomes non-interactable. It won't respond to or block click, press, or other mouse events.
--- @field blocksGameInteraction boolean (default: true) If set to false, then this panel does not block the user from interacting with non-UI elements such as the map and tokens on the map.
--- @field GetValue nil|(fun(panel: Panel): any) This function is used if you want the panel to have a value that it manages. This is useful for implementing a user-interface control such as a checkbox (in which case the value would be a boolean) or a dropdown (in which case it might be a string of possible values). The function should return the current value stored in the panel. @see SetValue @see value
--- @field SetValue nil|fun(panel: Panel, value: any) This function is used if you want the panel to have a value that it manages. This is useful for implementing a user-interface control such as a checkbox (in which case the value would be a boolean) or a dropdown (in which case it might be a string of possible values). The function should return the current value stored in the panel. @see GetValue @see value
--- @field value any The current value the panel represents, if any. This is used for panels that represent controls that allow you to edit a value, such as a checkbox, a dropdown, a color picker, or similar.
--- @field text string A synonym for value.
--- @field thinkTime number|nil The interval in seconds which the 'think' event will be fired on this panel. Allows a panel to regularly calculate some logic. Set to a very small value such as 0.001 to have 'think' fired as often as possible (in practice this will likely fire it at between 30 and 120hz). If set to nil (the default), think will not be fired on this panel. Use think carefully, since it can be performance intensive and slow down the application. Try to use other events instead.
--- @field monitorGame nil|string|string[] A path within the game's data store that this panel monitors. When anything within that path changes, the 'refreshGame' event is fired on this panel. This is very useful if you want to update the panel whenever some data changes. For instance, you could monitor a token's path to update the panel whenever the creature that token represents changes.
--- @field mousePoint Vector2 The position of the mouse within this panel, or (0,0) if the mouse is not within the panel.
--- @field bgsprite Sprite The @see Sprite object representing the bgimage for this panel.
--- @field swallowPress boolean (Default: false) If true, if this panel receives the 'press' event its parent panel will not receive the press event. By default, a panel, and its parents, all the way up the hierarchy receive the press event.
--- @field hoverCursor MouseCursor|nil The style of mouse cursor that will be displayed when this panel is hovered.
--- @field clip boolean (Default: false) If set to true, this panel's bgimage will be used to clip its children. By default child panels can appear outside the bounds of their parent. With this set to true, the child panels will instead be clipped.
--- @field clipHidden boolean (Default: false) This is relevant only if @see clip is set. If set to true, this panel won't have its bgimage drawn. The bgimage will be used only for the purpose of clipping the child panels.
--- @field renderedWidth number (read-only) The width, in pixels, at which this panel has been rendered at. The rendering size of a panel will depend on its styling information.
--- @field renderedHeight number (read-only) The height, in pixels, at which this panel has been rendered at. The rendering size of a panel will depend on its styling information.
--- @field renderedScale Vector2 (read-only) The scale at which this panel has been rendered. This will have been done based on the styling information the panel has.
--- @field renderedPosition Vector3 (read-only) The position at which the panel has been rendered, relative to its parent.
--- @field eventsWithMinDelay string[] A list of panel events which have minimum delay rules set on them. When an event in this list is fired, it cannot be fired again within @see eventsMinDelayTime seconds. If it is, then the event firing will be delayed until eventsMinDelayTime has fired. This is useful to stop, for instance, a user typing very fast in an input control from triggering multiple searches in very quick succession which might slow the app down.
--- @field eventsMinDelayTime number The minimum delay for events listed in @see eventsWithMinDelay
--- @field aliveTime number (read-only) the number of seconds since this panel was created.
--- @field shapes Shapes A shapes API allowing vector drawing on this panel.
--- @field monitorGameEvent string The event which is fired when the part of the game monitored by @see monitorGame is updated. (default='refreshGame')
--- @field mapfocus boolean If set to true, this panel receives mappress and maphover events when the user interacts with the game map. These events accept a loc: Loc and pos: Vector2 as arguments. Only one panel may have map focus at a time. Setting map focus to true on a panel will clear any other panel that has map focus.
--- @field hideObjectsOutOfScroll boolean (default=false) This is relevant only for panels that have @see vscroll set to true. Child panels that are not visible within the scrollable area will automatically be considered hidden.
--- @field alphaHitTest boolean If set to true (default=false), the panel will only be considered hovered by the mouse if the bgimage of the panel has a non-transparent pixel at the exact position the mouse is at. When set to false, the mouse need only be in the bounding box of the panel.
--- @field dragAndDropExtensions string[]|nil A list of possible file extensions that this panel accepts to be dragged onto it from Windows. When files with matching extensions are dropped onto this panel, the 'dropfiles' event is filed, which takes a string[] of the filenames dropped.
--- @field renderpos Vector2 The position the panel is rendering at, relative to its parent.
--- @field commands string[] A list of the game commands the panel is listening for. When one of these commands is fired, the event with the same name in the panel will be called.
--- @field distancesToScreenEdge Vector4 The distances to the edge of the screen from the edges of this panel.
--- @field keybinds nil|{id: string, defaultBind: string}[] When set, binds this panel to the given 'defaultBind' keybindings. (Note: currently the defaultBind cannot be changed, in the future the user may be able to configure the binding). When the keybind is pressed, the panel will receive the 'keybind' event, which takes the id of the keybind as its argument.
--- @field positionInScreenSpace Vector2 The position of the panel in screen space.
--- @field positionInWorldSpace Vector2 The position of the panel in world space.
Panel = {}

--- GetMouseButton: Returns true if the given mouse button is currently depressed. 0 = left mouse button, 1 = right mouse button, 2 = middle mouse button.
--- @param nbutton number
--- @return boolean
function Panel:GetMouseButton(nbutton)
	-- dummy implementation for documentation purposes only
end

--- FindParentWithClass: If the parent of this panel is of the 'classid' class it is returned, otherwise if its parent is of that class it is returned, and so forth. If no ancestor is found with the given class, nil will be returned.
--- @param classid string
--- @return Panel|nil
function Panel:FindParentWithClass(classid)
	-- dummy implementation for documentation purposes only
end

--- SetAsFirstSibling: Makes this panel the first child of its parent. Its siblings are shuffled back and maintain their order.
--- @return nil
function Panel:SetAsFirstSibling()
	-- dummy implementation for documentation purposes only
end

--- SetAsLastSibling: Makes this panel the last child of its parent. Its siblings are shuffled forward and maintain their order.
--- @return nil
function Panel:SetAsLastSibling()
	-- dummy implementation for documentation purposes only
end

--- AddChild: Adds childPanel as a child of this panel. It will be added as the last child.
--- @param childPanel Panel The child panel to add.
function Panel:AddChild(childPanel)
	-- dummy implementation for documentation purposes only
end

--- RemoveChild: Removes childPanel as a child of this panel. No effect if childPanel is not a child of the panel. The panel being removed will be destroyed. @see Unparent for a way to remove a panel without destroying it (and possibly reparenting it under another panel)
--- @param childPanel Panel The child panel to remove.
function Panel:RemoveChild(childPanel)
	-- dummy implementation for documentation purposes only
end

--- ScheduleEvent: Arranges for eventName to be fired on this panel after the given delay, with the given arguments passed to the event. If the panel is destroyed before the scheduled event, the event will not fire. The event will fire even if the panel is hidden or collapsed.
--- @param eventName string The name of the event to fire.
--- @param delay number The time in seconds to delay the event being fired.
--- @vararg args any The arguments to pass to the event.
function Panel:ScheduleEvent(eventName, delay, args)
	-- dummy implementation for documentation purposes only
end

--- DestroySelf: Destroy the panel. It will be removed from the hierarchy.
--- @return nil
function Panel:DestroySelf()
	-- dummy implementation for documentation purposes only
end

--- Unparent: Unparent the panel from its parent without destroying it. Note that unparented panels must be immediately reparented before returning or yielding. A panel cannot be left orphaned without a parent, and will be automatically destroyed with an error if it is.
--- @return nil
function Panel:Unparent()
	-- dummy implementation for documentation purposes only
end

--- MoveToNativeWindow: (Experimental!) Unparents the panel and makes it the top of its hierarchy and places it inside a native Windows window outside of the normal VTT interface. This effectively 'pops out' this panel into its own window.
--- @param args any
--- @return nil
function Panel:MoveToNativeWindow(args)
	-- dummy implementation for documentation purposes only
end

--- GetChildrenWithClass: Returns all children that are members of the given class. Only returns direct children, does not search recursively.
--- @param className string The class name to search for. Can begin with ~ to search for Panels that do NOT have that class.
--- @return Panel[]
function Panel:GetChildrenWithClass(className)
	-- dummy implementation for documentation purposes only
end

--- GetChildrenWithClasses: Returns all children that are members of the given class. Only returns direct children, does not search recursively.
--- @param classCriteria string[] A list of the class names to search for. Class names may begin with ~ to specify that the panel may NOT be a member of that class.
--- @return Panel[]
function Panel:GetChildrenWithClasses(classCriteria)
	-- dummy implementation for documentation purposes only
end

--- GetChildrenWithClassRecursive: Returns all children that are members of the given class, searches recursively through the entire hierarchy below this panel. Results are returned in a flat array that does not reflect the panel hierarchy.
--- @param className string The class name to search for. Can begin with ~ to search for Panels that do NOT have that class.
--- @return Panel[]
function Panel:GetChildrenWithClassRecursive(className)
	-- dummy implementation for documentation purposes only
end

--- FindChildRecursive: Searches this panel and all its children, searching recursively through the entire hierarchy. 'predicate' is run on each panel found. The first time predicate returns true, that panel is returned as the result. If no panel is found which predicate returns true for, then nil is returned.
--- @param predicate fun(panel: Panel): boolean
---  @return Panel|nil
function Panel:FindChildRecursive(predicate)
	-- dummy implementation for documentation purposes only
end

--- GetChild: Gets the nth child of the panel
--- @param n number
--- @return Panel|nil
function Panel:GetChild(n)
	-- dummy implementation for documentation purposes only
end

--- IsDescendantOf: Returns true if this panel is a child, direct or indirect, of the 'other' panel.
--- @param other Panel
--- @return boolean
function Panel:IsDescendantOf(other)
	-- dummy implementation for documentation purposes only
end

--- Get: Finds and returns the panel in the hierarchy that has the given id. Returns nil if no such panel is found. The id must be an exact match. The entire hierarchy from the root is searched (not just the descendants of this panel). However, other hierarchies within the app are not searched.
--- @param id string The id of the panel to get.
--- @return Panel|nil
function Panel:Get(id)
	-- dummy implementation for documentation purposes only
end

--- FireEvent: Fires the named event on this panel. This can be a built-in event such as click, or any name you choose. If it exists, the corresponding event handler (@see events) will be called on this panel. The panel itself is always passed as the first argument and then any arguments you passed are called.
--- @param eventName string The name of the event to fire.
--- @vararg args any Additional arguments to pass to the event.
function Panel:FireEvent(eventName, args)
	-- dummy implementation for documentation purposes only
end

--- FireEventOnParents: Fires the named event on the parent of this panel, on the grand-parent, and all parents up to the root of the hierarchy. Does not fire the event on this panel itself. @see FireEvent
--- @param eventName string The name of the event to fire.
--- @vararg args any Additional arguments to pass to the event.
function Panel:FireEventOnParents(key, args)
	-- dummy implementation for documentation purposes only
end

--- FireEventTree: Fires the named event on this panel, and all children, grand-children, etc, recursively down the hierarchy. @see FireEvent
--- @param eventName string The name of the event to fire.
--- @vararg args any Additional arguments to pass to the event.
function Panel:FireEventTree(key, args)
	-- dummy implementation for documentation purposes only
end

--- FireEventTreeVisible: Fires the named event on this panel, and all children, grand-children, etc, recursively down the hierarchy. Only panels that are visible (not hidden or collapsed) have the event fired, others are ignored. @see FireEvent @see FireEventTree
--- @param eventName string The name of the event to fire.
--- @vararg args any Additional arguments to pass to the event.
function Panel:FireEventTreeVisible(key, args)
	-- dummy implementation for documentation purposes only
end

--- SetClassTree: Adds or removes the given class to this panel and every descendant panel in the hierarchy. If value is true, the class is added, if it is false, it is removed.
--- @param classid string
--- @param value boolean
--- @return nil
function Panel:SetClassTree(classid, value)
	-- dummy implementation for documentation purposes only
end

--- SetClassTreeImmediate: Adds or removes the given class to this panel and every descendant panel in the hierarchy. If value is true, the class is added, if it is false, it is removed. The class change happens immediately, with the transitionTime field in any styling ignored.
--- @param classid string
--- @param value boolean
--- @return nil
function Panel:SetClassTreeImmediate(classid, value)
	-- dummy implementation for documentation purposes only
end

--- AddClassTree: Adds the class to this panel and every descendent panel, recursively in the panel hierarchy.
--- @param classid string
--- @return nil
function Panel:AddClassTree(classid)
	-- dummy implementation for documentation purposes only
end

--- RemoveClassTree: Removes the class from this panel and every descendent panel, recursively in the panel hierarchy.
--- @param classid string
--- @return nil
function Panel:RemoveClassTree(classid)
	-- dummy implementation for documentation purposes only
end

--- PulseClassTree: Adds the class to this panel and every descendent panel, recursively in the hierarchy. When a class is 'pulsed' it is added momentarily, and then removed. This has the effect of any styles being applied, and then fading out according to their transitionTime value.
--- @param classid string
--- @return nil
function Panel:PulseClassTree(classid)
	-- dummy implementation for documentation purposes only
end

--- HasClass: This returns true if this panel has the given class applied to it.
--- @param classid string
--- @return boolean
function Panel:HasClass(classid)
	-- dummy implementation for documentation purposes only
end

--- SetClass: Adds or removes the given class to this panel. If value is true, the class is added, otherwise it is removed.
--- @param classid string
--- @param value boolean
--- @return nil
function Panel:SetClass(classid, value)
	-- dummy implementation for documentation purposes only
end

--- SetClassImmediate: Adds or removes the given class to this panel. If value is true, the class is added, otherwise it is removed. The change happens immediately, ignoring any transitionTime value in styles.
--- @param classid string
--- @param value boolean
--- @return nil
function Panel:SetClassImmediate(classid, value)
	-- dummy implementation for documentation purposes only
end

--- AddClass: Adds the given class to this panel.
--- @param classid string
--- @return nil
function Panel:AddClass(classid)
	-- dummy implementation for documentation purposes only
end

--- RemoveClass: Removes the given class from this panel.
--- @param classid string
--- @return nil
function Panel:RemoveClass(classid)
	-- dummy implementation for documentation purposes only
end

--- PulseClass: Adds the class to this panel momentarily and then removes it immediately. This has the effect of any styles dependent on the class applying and then fading out according to the value of their transitionTime value. This can be used to create effects such as making a button flash to gain the user's attention.
--- @param classid string
--- @return nil
function Panel:PulseClass(classid)
	-- dummy implementation for documentation purposes only
end

--- UpdateStyle: Forcibly recalculate the style of this panel. This should generally not be necessary to call manually, though you may call it to debug if a panel's style is not getting updated by the engine correctly.
--- @return nil
function Panel:UpdateStyle()
	-- dummy implementation for documentation purposes only
end

--- MakeNonInteractiveRecursive: Makes this panel and all descendent panels non-interactable. @see interactable
--- @return nil
function Panel:MakeNonInteractiveRecursive()
	-- dummy implementation for documentation purposes only
end

--- FloatTooltipNearTile: This shows the given tooltip panel near the given location on the map. Any other tooltips over the map will be cleared.
--- @param loc Loc
--- @param tooltip Panel
function Panel:FloatTooltipNearTile(loc, tooltip)
	-- dummy implementation for documentation purposes only
end

--- HaltEventPropagation: This will stop any active events to propagate to parents. It is useful inside an event such as 'press' to prevent the parent from getting the event as well.
--- @return nil
function Panel:HaltEventPropagation()
	-- dummy implementation for documentation purposes only
end

--- @class PanelArgs:PanelArgsBase 
--- @field id nil|string The unique id of the panel. If not specified a random id will be assigned. It is important that each panel have a unique ID, so if you assign an ID explicitly ensure it is unique.
--- @field idprefix nil|string The prefix of the panel's id. A random ID will be generated but will begin with this prefix.
--- @field debugBacktrace string|nil 
--- @field inworld nil|any 
--- @field blurBackground nil|any 
--- @field monitorMod nil|string The id of the mod to monitor. When this mod is reloaded the refreshMod event will be fired on the panel.
--- @field monitorAssets nil|AssetCategory|AssetCategory[] (write-only) A list of asset categories to monitor. When the asset categories are updated, the refreshAssets event will be fired on this panel.
--- @field constrainToScreen nil|boolean (default=false) If true, the panel will be constrained to the screen area.
--- @field floating nil|boolean (default=false) A floating panel does not respect the **flow** of its parent. @see Panel.flow
--- @field data nil|table An arbitrary table of user data that is attached to the panel. Store any interesting fields here that you want to have associated with the panel.
--- @field root nil|Panel The root panel of the hierarchy this Panel is within.
--- @field parent nil|Panel The parent panel of this panel. Returns nil if this panel is at the root of its hierarchy.
--- @field children nil|Panel[] A list of the children of this panel. Note that you may set this panel to a new list of children. Any panels that are left orphaned by doing this are automatically destroyed.
--- @field selfStyle nil|Style|StyleArgs Any style settings that are set directly on this panel. They do not apply to children, only directly to this panel. Note that styles that are set here override any other styling on the panel. Selectors set on this style are ignored.
--- @field style nil|Style|StyleArgs Style settings set on this panel, and all of its hierarchical children. Styles here are lower priority than those set in @see selfStyle but higher priority than other styles. Selectors set on this style are ignored.
--- @field styles nil|StyleArgs[] A list of styles that are applied to this panel and all of its children in the hierarchy. Styles may have their selectors field set and will apply only to panels where the selector criteria matches. Styles set like this are lower priority than @see selfStyle and @see style. Styles that are more specific (have more elements in their selector) are higher priority, and those specified later in the list are higher priority. You can use the priority field to manually set a priority for a style.
--- @field bgimage nil|string|boolean The image to set as the background of this panel. If left unset or set to false the panel will not have a background image. Note that the background image is the main display of most panels, so if this is not set the panel will be invisible, though its children may still be visible. This can be set to true (or 'panels/square.png') to set to a plain white square image (which can then have further styling set to it). It can also be set to an image uploaded in a mod, e.g. bgimage = mod.images.myicon
--- @field bgimageStreamed nil|string (Write-only) This can be set to set the bgimage, but the image is streamed, so the panel may be invisible until it is properly loaded. This is good to do for many panels that may have videos or other long-loading images.
--- @field bgimageInit nil|boolean True if the bgimage for this panel has been loaded. This can be set to true if you want to force the panel to be visible even if its image isn't available yet. If the image isn't available, then it will be displayed as a plain white square.
--- @field bgimageMask nil|string 
--- @field bgimageAlpha nil|string 
--- @field bgimageTokenMask nil|string 
--- @field bgimageTokenMaskInclusive nil|string 
--- @field bgimageMaskInvert nil|number 
--- @field bgimageMaskRect nil|Vector4 
--- @field bgimageWidth nil|number The width of the @see bgimage. This will be -1 if the bgimage hasn't been loaded yet.
--- @field bgimageHeight nil|number The height of the @see bgimage. This will be -1 if the bgimage hasn't been loaded yet.
--- @field x nil|number A horizontal offset in pixels to apply to this panel's positioning. Note that this will be an offset to where the panel is positioned, but will not affect the layout of other panels in the hierarchy. @see translate
--- @field y nil|number A vertical offset in pixels to apply to this panel's positioning. Note that this will be an offset to where the panel is positioned, but will not affect the layout of other panels in the hierarchy. @see translate
--- @field translate nil|Vector2 A vector to translate the panel's position to. This is the same behavior as using @see x and @see y.
--- @field dragThreshold nil|number (Default: 4) How many pixels the panel has to be dragged before it's considered dragging. This is only relevant if @see draggable is true.
--- @field dragDelta nil|Vector2 The pixels the mouse has moved since the drag operation began. Will return (0,0) if the panel is not currently begin dragged..
--- @field playbackSpeed nil|any 
--- @field xdrag nil|number The pixels the panel has been translated horizontally by dragging. 0 if the panel is not currently being dragged.
--- @field ydrag nil|number The pixels the panel has been translated vertically by dragging. 0 if the panel is not currently being dragged.
--- @field events nil|PanelEventArgs The events that are registered for this panel. When the event with the key in the table is fired on the panel that function is called. The panel itself is always passed as the first argument, and then any other arguments to the event are passed. Some standard events include 'create', 'hover', 'dehover', 'click', 'press'. Some events are also enabled based on other arguments such as 'refreshAssets' and 'think'. @see thinkTime. You can also fire a user-defined event using @see FireEvent and @see FireEventTree
--- @field hscroll nil|boolean Set this to true to make the panel be horizontally scrollable. The size of the scroll area will be automatically calculated based on the position and size of its children.
--- @field vscroll nil|boolean Set this to true to make the panel be vertically scrollable. The size of the scroll area will be automatically calculated based on the position and size of its children.
--- @field vscrollLockToBottom nil|boolean Set this to true to by default set the scrollbar to lock to the bottom when new content is added to the panel.
--- @field vscrollPosition nil|number The position of the vertical scrollbar, from 0 to 1. 0 = at the bottom, 1 = at the top.
--- @field canFocus nil|boolean True if the panel can accept input focus.
--- @field hasFocus nil|boolean True if the panel currently has input focus.
--- @field inputEvents nil|InputEvent[] A list of input events that this panel subscribes to and receives. When the named input event occurs, the panel will have an event with that name fired on it. Panels are arranged in priority order to receive an event and only one panel will receive the event.
--- @field escapeActivates nil|boolean If true, the 'click' event will be fired on this panel when escape is pressed. This is used for panels that act as though they were clicked on when escape is pressed.
--- @field captureEscape nil|boolean If true, the 'escape' event will be fired on this panel when escape is pressed. Only the panel with the highest @see escapePriority that is active will receive the escape event.
--- @field escapePriority nil|number The priority with which this panel captures escape events compared to other panels.
--- @field draggable nil|boolean If true, this panel can be dragged.
--- @field canDragOnto nil|(fun(thisPanel: Panel, targetPanel: Panel): boolean) This function tells us if this panel can be dragged onto the given target panel. This will only be called on a target panel if @see dragTarget is set to true for the target panel.
--- @field dragTarget nil|boolean If true, this panel may be used as a drag target for other panels -- other panels may be dragged onto it. @see canDragOnto will still be called on the panel being dragged to confirm it can be dragged onto this panel.
--- @field dragTargetPriority nil|number If a panel is dragged and overlapping multiple potential target panels, the higher dragTargetPriority panel will take precendence as the drag target.
--- @field dragBounds nil|Vector4 A bounding box for dragging that the panel may not go outside of when dragged.
--- @field dragMove nil|boolean (Write-only) if set to true, the panel will be physically moved when dragged. If false, the panel will receive drag events but won't be moved when dragged.
--- @field dragxwrap nil|boolean (write-only) if set to true, if @see dragBounds is set, the panel will wrap around if it goes outside of the bounds horizontally.
--- @field dragywrap nil|boolean (write-only) if set to true, if @see dragBounds is set, the panel will wrap around if it goes outside of the bounds vertically.
--- @field monitor nil|string|string[]|(fun(Panel):nil) (write-only) A setting id or list of setting ids to 'monitor'. When one of these game settings changes, the 'monitor' event is fired on this panel. This allows a panel to be responsive to changes in a setting's value and allows multiple panels to collaborate in managing a setting.
--- @field monitorValue nil|any The current value of the setting that this panel is monitoring. Should only be used if the panel is monitoring a single setting.
--- @field className nil|string The class of the panel. Classes may be any string of your choosing and are used to select panels for styling and other purposes. Usually you will want to use the more general @see classes which can set multiple classes on a panel.
--- @field classes nil|string[] The classes the panel belongs to. Classes can be strings of your choice and are used by the styling system to identify which panels a style should apply to. The selectors of a style can be used to check a panel is in a certain class when choosing whether to apply the style to the panel.
--- @field tooltip string|Panel|nil When this property is set, the given panel will appear over this element as a tooltip. The tooltip will be disappear automatically when the user moves the mouse away from the panel. It is usually best to set this in response to the 'hover' event. This property will always read as a Panel, but you can set a string, in which case the CreateTooltipPanel global function will be called to create the tooltip panel. Tooltips may have halign and valign styles set on them to control their positioning relative to their parent.
--- @field tooltipParent nil|Panel The panel to which tooltips spawned from this panel will be parented. By default this will be equal to the panel itself, but you may wish to spawn tooltips from a parent panel instead.
--- @field popupPositioning nil|Panel|"mouse"|"panel" The positioning of @see popup panels spawned from this panel. They can be positioned relative to this panel, or to the mouse position at the time of spawning the popup. You can also specify a different panel which they will be positioned relative to. You can set valign and halign on popup panels to specify how they will be placed relative to their positioning.
--- @field popup Panel|nil When this property is set to a panel, that panel will be spawned and placed as a 'popup' over this panel. Popup panels are similar to tooltips in their behavior, but they are removed differently. Usually tooltips are very transient and removed when the user moves the mouse, and cannot be interacted with. Popup panels can be interacted with, and remain until the user clicks away from them, or you manually set popup to nil. Popups are useful for implementing context menus and other small interactive dialogs.
--- @field interactable nil|boolean (default: true) If this is set to false then the panel becomes non-interactable. It won't respond to or block click, press, or other mouse events.
--- @field blocksGameInteraction nil|boolean (default: true) If set to false, then this panel does not block the user from interacting with non-UI elements such as the map and tokens on the map.
--- @field GetValue nil|(fun(panel: Panel): any) This function is used if you want the panel to have a value that it manages. This is useful for implementing a user-interface control such as a checkbox (in which case the value would be a boolean) or a dropdown (in which case it might be a string of possible values). The function should return the current value stored in the panel. @see SetValue @see value
--- @field SetValue nil|fun(panel: Panel, value: any) This function is used if you want the panel to have a value that it manages. This is useful for implementing a user-interface control such as a checkbox (in which case the value would be a boolean) or a dropdown (in which case it might be a string of possible values). The function should return the current value stored in the panel. @see GetValue @see value
--- @field value nil|any The current value the panel represents, if any. This is used for panels that represent controls that allow you to edit a value, such as a checkbox, a dropdown, a color picker, or similar.
--- @field text nil|string A synonym for value.
--- @field thinkTime number|nil The interval in seconds which the 'think' event will be fired on this panel. Allows a panel to regularly calculate some logic. Set to a very small value such as 0.001 to have 'think' fired as often as possible (in practice this will likely fire it at between 30 and 120hz). If set to nil (the default), think will not be fired on this panel. Use think carefully, since it can be performance intensive and slow down the application. Try to use other events instead.
--- @field monitorGame nil|string|string[] A path within the game's data store that this panel monitors. When anything within that path changes, the 'refreshGame' event is fired on this panel. This is very useful if you want to update the panel whenever some data changes. For instance, you could monitor a token's path to update the panel whenever the creature that token represents changes.
--- @field mousePoint nil|Vector2 The position of the mouse within this panel, or (0,0) if the mouse is not within the panel.
--- @field bgsprite nil|Sprite The @see Sprite object representing the bgimage for this panel.
--- @field swallowPress nil|boolean (Default: false) If true, if this panel receives the 'press' event its parent panel will not receive the press event. By default, a panel, and its parents, all the way up the hierarchy receive the press event.
--- @field hoverCursor MouseCursor|nil The style of mouse cursor that will be displayed when this panel is hovered.
--- @field clip nil|boolean (Default: false) If set to true, this panel's bgimage will be used to clip its children. By default child panels can appear outside the bounds of their parent. With this set to true, the child panels will instead be clipped.
--- @field clipHidden nil|boolean (Default: false) This is relevant only if @see clip is set. If set to true, this panel won't have its bgimage drawn. The bgimage will be used only for the purpose of clipping the child panels.
--- @field eventsWithMinDelay nil|string[] A list of panel events which have minimum delay rules set on them. When an event in this list is fired, it cannot be fired again within @see eventsMinDelayTime seconds. If it is, then the event firing will be delayed until eventsMinDelayTime has fired. This is useful to stop, for instance, a user typing very fast in an input control from triggering multiple searches in very quick succession which might slow the app down.
--- @field eventsMinDelayTime nil|number The minimum delay for events listed in @see eventsWithMinDelay
--- @field shapes nil|Shapes A shapes API allowing vector drawing on this panel.
--- @field monitorGameEvent nil|string The event which is fired when the part of the game monitored by @see monitorGame is updated. (default='refreshGame')
--- @field mapfocus nil|boolean If set to true, this panel receives mappress and maphover events when the user interacts with the game map. These events accept a loc: Loc and pos: Vector2 as arguments. Only one panel may have map focus at a time. Setting map focus to true on a panel will clear any other panel that has map focus.
--- @field hideObjectsOutOfScroll nil|boolean (default=false) This is relevant only for panels that have @see vscroll set to true. Child panels that are not visible within the scrollable area will automatically be considered hidden.
--- @field alphaHitTest nil|boolean If set to true (default=false), the panel will only be considered hovered by the mouse if the bgimage of the panel has a non-transparent pixel at the exact position the mouse is at. When set to false, the mouse need only be in the bounding box of the panel.
--- @field dragAndDropExtensions string[]|nil A list of possible file extensions that this panel accepts to be dragged onto it from Windows. When files with matching extensions are dropped onto this panel, the 'dropfiles' event is filed, which takes a string[] of the filenames dropped.
--- @field renderpos nil|Vector2 The position the panel is rendering at, relative to its parent.
--- @field commands nil|string[] A list of the game commands the panel is listening for. When one of these commands is fired, the event with the same name in the panel will be called.
--- @field distancesToScreenEdge nil|Vector4 The distances to the edge of the screen from the edges of this panel.
--- @field keybinds nil|{id: string, defaultBind: string}[] When set, binds this panel to the given 'defaultBind' keybindings. (Note: currently the defaultBind cannot be changed, in the future the user may be able to configure the binding). When the keybind is pressed, the panel will receive the 'keybind' event, which takes the id of the keybind as its argument.
--- @field positionInScreenSpace nil|Vector2 The position of the panel in screen space.
--- @field positionInWorldSpace nil|Vector2 The position of the panel in world space.
PanelArgs = {}
