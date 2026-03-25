--- @class Input:Panel 
--- @field text string The text held in this input.
--- @field textNoNotify string An alias of @see text, but if set, no events will fire on the panel, such as the change event which normally fires when the text is changed.
--- @field editlag number When the text is edited, the lag before calling the 'edit' event, all keypresses during this time will be coalesced into one. Use this to make it so a user typing very fast doesn't cause an excessive number of edit events.
--- @field placeholderText string The grayed text to display when the input field is empty.
--- @field editable boolean (default=true) If the input is editable by the user.
--- @field multiline boolean (default=false) If the input displays multiple lines.
--- @field verticalScrollbar boolean (default=false) If set to true, a vertical scrollbar is shown on the input when in multiline mode. The scrollbar color can be styled using the scrollHandleColor style property.
--- @field lineType "SingleLine"|"MultiLineSubmit"|"MultiLineNewLine" When this is SingleLine, the input is a single line. Pressing enter will fire the 'submit' event. When MultiLineSubmit, the input is multiple lines but pressing enter will still fire 'submit'. The user can press shift+enter to enter a new line. MultiLineNewLine will be multiple lines. Pressing enter will create a new line, rather than firing submit.
--- @field characterLimit number The maximum number of characters this input can contain.
--- @field hasInputFocus boolean True if this input has the input focus.
--- @field selectAllOnFocus boolean If set to true, the text will be selected when the input clicks on the input. This is useful to turn on for inputs the user is very likely to want to change in their entirety.
--- @field caretPosition number The position of the cursor within the input.
--- @field selectionAnchorPosition number The bounds of the selection. The @caretPosition is the opposite bounds of the selection. If this is equal to @see caretPosition the user has no text selected.
--- @field password boolean If set to true, this input will not display the text that is being typed on-screen to keep it secret and safe.
--- @field consumeTab boolean (default=false) If set to true, pressing Tab while editing will fire the 'tab' event but will not insert a tab character or remove focus from the input.
--- @field restoreOriginalTextOnEscape boolean If set to true, all edits will be canceled, and the text will be restored if the user presses escape while editing.
--- @field blockChangesWhenEditing boolean If set to true, setting @see text in code will fail if the user is editing the text.
--- @field caretWorldPosition {x: number, y: number, lineHeight: number}|nil Returns the world-space position of the caret and the line height at that position. Returns nil if the text info is not yet available. Use this to position popups near the caret.
--- @field placeholderAlpha number The alpha value of placeholder text. (default=0.6)
Input = {}

--- SetTextAndCaret: Sets the text and moves the caret to the given position reliably, even when the input needs to be re-focused. The caret positioning is deferred until after the input has fully activated. Fires a 'caretReady' event on the input when the caret is in position.
--- @param caretPos number
--- @param newText string
--- @return nil
function Input:SetTextAndCaret(caretPos, newText)
	-- dummy implementation for documentation purposes only
end

--- GetCharWorldPosition: Returns the world-space position of the character at the given 1-based index and its line height. Returns nil if the text info is not yet available. Use this to position popups near a specific character.
--- @param charIndex number
--- @return any
function Input:GetCharWorldPosition(charIndex)
	-- dummy implementation for documentation purposes only
end

--- @class InputArgs:PanelArgs 
--- @field text nil|string The text held in this input.
--- @field textNoNotify nil|string An alias of @see text, but if set, no events will fire on the panel, such as the change event which normally fires when the text is changed.
--- @field editlag nil|number When the text is edited, the lag before calling the 'edit' event, all keypresses during this time will be coalesced into one. Use this to make it so a user typing very fast doesn't cause an excessive number of edit events.
--- @field placeholderText nil|string The grayed text to display when the input field is empty.
--- @field editable nil|boolean (default=true) If the input is editable by the user.
--- @field multiline nil|boolean (default=false) If the input displays multiple lines.
--- @field verticalScrollbar nil|boolean (default=false) If set to true, a vertical scrollbar is shown on the input when in multiline mode. The scrollbar color can be styled using the scrollHandleColor style property.
--- @field lineType nil|"SingleLine"|"MultiLineSubmit"|"MultiLineNewLine" When this is SingleLine, the input is a single line. Pressing enter will fire the 'submit' event. When MultiLineSubmit, the input is multiple lines but pressing enter will still fire 'submit'. The user can press shift+enter to enter a new line. MultiLineNewLine will be multiple lines. Pressing enter will create a new line, rather than firing submit.
--- @field characterLimit nil|number The maximum number of characters this input can contain.
--- @field hasInputFocus nil|boolean True if this input has the input focus.
--- @field selectAllOnFocus nil|boolean If set to true, the text will be selected when the input clicks on the input. This is useful to turn on for inputs the user is very likely to want to change in their entirety.
--- @field caretPosition nil|number The position of the cursor within the input.
--- @field selectionAnchorPosition nil|number The bounds of the selection. The @caretPosition is the opposite bounds of the selection. If this is equal to @see caretPosition the user has no text selected.
--- @field password nil|boolean If set to true, this input will not display the text that is being typed on-screen to keep it secret and safe.
--- @field consumeTab nil|boolean (default=false) If set to true, pressing Tab while editing will fire the 'tab' event but will not insert a tab character or remove focus from the input.
--- @field restoreOriginalTextOnEscape nil|boolean If set to true, all edits will be canceled, and the text will be restored if the user presses escape while editing.
--- @field blockChangesWhenEditing nil|boolean If set to true, setting @see text in code will fail if the user is editing the text.
--- @field caretWorldPosition {x: number, y: number, lineHeight: number}|nil Returns the world-space position of the caret and the line height at that position. Returns nil if the text info is not yet available. Use this to position popups near the caret.
--- @field placeholderAlpha nil|number The alpha value of placeholder text. (default=0.6)
InputArgs = {}
